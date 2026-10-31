import std/[os, sets, strformat, tables]
import ../util/xml
from std/math import ceil, round
when defined(windows):
  import std/strutils

import ../[action, ffmpeg, media, timeline]
import ../util/[fun, rational]
import ../lib/speedmap

#[
Premiere Pro uses the Final Cut Pro 7 XML Interchange Format

See docs here:
https://developer.apple.com/library/archive/documentation/AppleApplications/Reference/FinalCutPro_XML/Elements/Elements.html

Also, Premiere itself will happily output subtlety incorrect XML files that don't
come back the way they started.
]#

const DEPTH = "16"


func setTbNtsc(tb: AVRational): (int64, string) =
  # See chart: https://developer.apple.com/library/archive/documentation/AppleApplications/Reference/FinalCutPro_XML/FrameRate/FrameRate.html#//apple_ref/doc/uid/TP30001158-TPXREF103
  if tb == AVRational(num: 24000, den: 1001):
    return (24'i64, "TRUE")
  if tb == AVRational(num: 30000, den: 1001):
    return (30'i64, "TRUE")
  if tb == AVRational(num: 60000, den: 1001):
    return (60'i64, "TRUE")

  var ctb = int64(ceil(tb.float64))
  if ctb notin [24'i64, 30, 60] and tb == ctb * AVRational(num: 1000, den: 1001):
    return (ctb, "TRUE")

  # Last resort for a non-integer, non-NTSC rate: truncate to a whole timebase.
  return (int64(tb.num div tb.den), "FALSE")


func elem(tag, text: string): XmlNode =
  let e = newElement(tag)
  e.add newText(text)
  return e

func param(id, name, value: string, min = "", max = ""): XmlNode =
  let p = <>parameter(authoringApp = "PremierePro")
  p.add elem("parameterid", id)
  p.add elem("name", name)
  if min != "": p.add elem("valuemin", min)
  if max != "": p.add elem("valuemax", max)
  p.add elem("value", value)
  return p

func mediaFrame(map: SpeedMap, clip: Clip, frame: int64): float64 =
  ## The source frame at `frame` in the clip's speed-scaled frames, which
  ## <in> and <out> count.
  if not map.ramp: return frame.float64 * map.mean
  map.mean * (clip.offset.float64 + clip.dur.float64 *
    map.mediaAt(float64(frame - clip.offset) / clip.dur.float64))

proc speedup(map: SpeedMap, clip: Clip, inFrame, outFrame: int64): XmlNode =
  let fil = newElement("filter")
  let effect = newElement("effect")
  effect.add elem("name", "Time Remap")
  effect.add elem("effectid", "timeremap")
  effect.add param("variablespeed", "variablespeed", (if map.ramp: "1" else: "0"),
    "0", "1")
  effect.add param("speed", "speed", $(map.mean * 100), "-100000", "100000")
  effect.add param("frameblending", "frameblending", "FALSE")
  if map.ramp:
    # A ramp's source frame at each frame from <in> to <out>, which the
    # editor joins with straight lines.
    let graph = param("graphdict", "graphdict", "0")
    let step = max(1'i64, (outFrame - inFrame) div 32)
    var frame = inFrame
    while true:
      let kf = newElement("keyframe")
      kf.add elem("when", $frame)
      kf.add elem("value", $round(map.mediaFrame(clip, frame), 3))
      graph.add kf
      if frame >= outFrame: break
      frame = min(frame + step, outFrame)
    effect.add graph
  fil.add effect

  return fil

func rampPoints(act: Action, dur: int64, fps: float): seq[(float32, float32)] =
  if act.kf.len <= 1:
    return @[(0.0'f32, (if act.kf.len == 1: act.kf[0] else: 1.0'f32))]
  if act.kt.len > 0:
    let denom = float32(max(1, int(dur) - 1))
    for (f, v) in act.timedKeys(act.kf, act.kt, int(dur), fps):
      result.add (float32(f) / denom, v)
    return
  if not act.hasEase:
    for i, v in act.kf:
      result.add (float32(i) / float32(act.kf.len - 1), v)
    return
  let animLen = case act.easeDurUnit
    of duClip: int(dur)
    of duSec: max(1, int(round(act.easeDur.float * fps)))
    of duFrames: max(1, int(round(act.easeDur.float)))
  let denom = max(1, int(dur) - 1)
  let samples = min(denom, 60)
  for s in 0 .. samples:
    let local = int(round(s.float / samples.float * denom.float))
    result.add (float32(local) / float32(denom),
      sampleKf(act.kf, applyEase(act.easeCurve, clipT(local, animLen))))

func rampParam(id, name: string, lo, hi, scale: float, act: Action,
    inFrame, outFrame, dur: int64, fps: float): XmlNode =
  let span = max(outFrame - inFrame - 1, 0)
  var keys: seq[(int64, float)]
  for (p, v) in rampPoints(act, dur, fps):
    let time = inFrame + int64(round(p.float * float(span)))
    let value = clamp(v.float * scale, lo, hi)
    if keys.len > 0 and keys[^1][0] == time: keys[^1] = (time, value)
    else: keys.add (time, value)

  if keys.len == 1:
    return param(id, name, $keys[0][1], $lo, $hi)

  result = <>parameter(authoringApp = "PremierePro")
  result.add elem("parameterid", id)
  result.add elem("name", name)
  result.add elem("valuemin", $lo)
  result.add elem("valuemax", $hi)
  for (time, value) in keys:
    let kf = newElement("keyframe")
    kf.add elem("when", $time)
    kf.add elem("value", $value)
    result.add kf

func opacityFilter(act: Action, inFrame, outFrame, dur: int64, fps: float): XmlNode =
  let effect = newElement("effect")
  effect.add elem("name", "Opacity")
  effect.add elem("effectid", "opacity")
  effect.add elem("effectcategory", "motion")
  effect.add elem("effecttype", "motion")
  effect.add elem("mediatype", "video")
  effect.add rampParam("opacity", "opacity", 0.0, 100.0, 100.0, act,
    inFrame, outFrame, dur, fps)
  result = newElement("filter")
  result.add effect

func audioLevelsFilter(act: Action, inFrame, outFrame, dur: int64,
    fps: float): XmlNode =
  let effect = newElement("effect")
  effect.add elem("name", "Audio Levels")
  effect.add elem("effectid", "audiolevels")
  effect.add elem("effectcategory", "audiolevels")
  effect.add elem("effecttype", "audiolevels")
  effect.add elem("mediatype", "audio")
  effect.add rampParam("level", "Level", 0.0, 3.98109, 1.0, act,
    inFrame, outFrame, dur, fps)
  result = newElement("filter")
  result.add effect

proc addTicks(clipitem: XmlNode, effects: Actions, clip: Clip,
    inFrame, outFrame: int64, tb: AVRational, video: bool) =
  ## Premiere's source times for <in> and <out>, which count frames after the
  ## speed change while the ticks count before it. Premiere keeps video on
  ## whole source frames, the ones the render shows, and audio exact.
  let map = initSpeedMap(effects)
  let perFrame = pproTicksPerSecond.float * tb.den.float / tb.num.float
  for (tag, frame) in [("pproTicksIn", inFrame), ("pproTicksOut", outFrame)]:
    let source = map.mediaFrame(clip, frame)
    let ticks = (if video: round(source) else: source) * perFrame
    clipitem.add elem(tag, $int64(round(ticks)))

proc clipFilters(effects: Actions, clip: Clip, isVideo: bool, inFrame, outFrame,
    dur: int64, fps: float): seq[XmlNode] =
  var seen: set[ActionKind]
  for a in effects:
    if a.kind in seen: continue
    seen.incl a.kind
    case a.kind
    of actSpeed:
      result.add speedup(initSpeedMap(effects), clip, inFrame, outFrame)
    of actOpacity:
      if isVideo:
        result.add opacityFilter(a, inFrame, outFrame, dur, fps)
    of actVolume:
      if not isVideo:
        result.add audioLevelsFilter(a, inFrame, outFrame, dur, fps)
    else: discard


proc mediaDef(filedef: XmlNode, url: string, mi: MediaInfo, tl: v3, tb: int64,
    ntsc: string, durationStr: string) =
  filedef.add elem("name", agSplitFile(mi.path).name)
  filedef.add elem("pathurl", url)

  let timecode = newElement("timecode")
  timecode.add elem("string", "00:00:00:00")
  timecode.add elem("displayformat", "NDF")
  let rate1 = newElement("rate")
  rate1.add elem("timebase", $tb)
  rate1.add elem("ntsc", ntsc)
  timecode.add rate1
  filedef.add timecode

  let rate2 = newElement("rate")
  rate2.add elem("timebase", $tb)
  rate2.add elem("ntsc", ntsc)
  filedef.add rate2

  # Blank for Resolve (which needs the tag present but empty) and for real video
  # (Premiere reads the length from the media); a frame count for still images so
  # Premiere holds them instead of falling back to its huge default still length.
  filedef.add elem("duration", durationStr)

  let mediadef = newElement("media")

  if mi.v.len > 0:
    let videodef = newElement("video")
    let vschar = newElement("samplecharacteristics")
    let rate3 = newElement("rate")
    rate3.add elem("timebase", $tb)
    rate3.add elem("ntsc", ntsc)
    vschar.add rate3
    # The file def must describe the source's own frame size, not the sequence's;
    # an overlay still/clip is often a different size than the timeline.
    vschar.add elem("width", $mi.v[0].width)
    vschar.add elem("height", $mi.v[0].height)
    vschar.add elem("pixelaspectratio", "square")
    videodef.add vschar
    mediadef.add videodef

  for aud in mi.a:
    let audiodef = newElement("audio")
    let aschar = newElement("samplecharacteristics")
    aschar.add elem("depth", DEPTH)
    aschar.add elem("samplerate", $tl.sr)
    audiodef.add aschar
    audiodef.add elem("channelcount", $aud.channels)
    mediadef.add audiodef

  filedef.add mediadef

type FileDefs = object
  urls, ids: Table[MediaInfo, string]
  written: HashSet[string] # urls that already have a full <file> definition
  resolve: bool

proc makeFiledef(files: var FileDefs, clipitem: XmlNode, mi: MediaInfo,
    tl: v3, timebase: int64, ntsc: string) =
  let pathurl = files.urls[mi]
  let filedef = <>file(id = files.ids[mi])
  if pathurl notin files.written:
    let durationStr =
      if files.resolve: ""                  # Resolve wants it blank
      # Premiere holds a still for the length given; blank, it ignores the
      # clip's in/out and falls back to a ~12h default.
      elif mi.isStill: $tl.len
      else: ""                              # Premiere reads media length
    mediaDef(filedef, pathurl, mi, tl, timebase, ntsc, durationStr)
    files.written.incl(pathurl)
  clipitem.add filedef

proc dissolveItem(t: Transition, mediaType: string, timebase: int64,
    ntsc: string): XmlNode

func channelsOf(mi: MediaInfo, stream: int16): int =
  if stream >= 0 and stream.int < mi.a.len: max(1, mi.a[stream].channels.int) else: 1

type ResolveAudioIds = seq[seq[seq[int]]] # [layer][channel][clip] -> clipitem id; 0 if none

proc planResolveAudio(tl: v3, ptrToMi: Table[ptr string, MediaInfo]): ResolveAudioIds =
  ## Resolve imports every audio clipitem as mono, reading trackindex as a
  ## channel of the file's first audio stream, so each channel gets its own
  ## track. setStreamTo0 has already made every clip's stream the first.
  # Ids must be unique across every audio track (a per-track j would repeat
  # them, making <link> refs ambiguous); audio continues after the video ids.
  var nextId = (if tl.v.len > 0: tl.v[0].len else: 0)
  for alayer in tl.a:
    var channels = 1
    for aclip in alayer:
      if aclip.src != nil:
        channels = max(channels, ptrToMi[aclip.src].channelsOf(aclip.stream))
    var layer = newSeq[seq[int]](channels)
    for sub in 0 ..< channels:
      layer[sub] = newSeq[int](alayer.len)
      for j, aclip in alayer:
        if aclip.src != nil and sub < ptrToMi[aclip.src].channelsOf(aclip.stream):
          nextId += 1
          layer[sub][j] = nextId
    result.add layer

proc addResolveLinks(clipitem: XmlNode, tl: v3, audioIds: ResolveAudioIds, j: int) =
  ## Link the video clip and every audio channel at position `j` together, so
  ## they move as one.
  var members: seq[(int, string)]
  if tl.v.len > 0 and j < tl.v[0].len and tl.v[0][j].src != nil:
    members.add (j + 1, "video")
  for layer in audioIds:
    for ids in layer:
      if j < ids.len and ids[j] != 0:
        members.add (ids[j], "audio")
  if members.len < 2:
    return
  for (id, mediaType) in members:
    let link = newElement("link")
    link.add elem("linkclipref", &"clipitem-{id}")
    link.add elem("mediatype", mediaType)
    clipitem.add link

proc resolveWriteAudio(audio: XmlNode, files: var FileDefs, tl: v3,
    ptrToMi: Table[ptr string, MediaInfo], audioIds: ResolveAudioIds,
    timebase: int64, ntsc: string) =
  for t, alayer in tl.a.pairs:
    let transitions = (if t < tl.at.len: tl.at[t] else: @[])
    let transitionLinks = transitionPlan(alayer, transitions)
    for sub, ids in audioIds[t]:
      let track = newElement("track")
      for j, aclip in alayer.pairs:
        if ids[j] == 0:
          continue
        let mi = ptrToMi[aclip.src]
        if transitionLinks[j].incoming >= 0:
          let transition = transitions[transitionLinks[j].incoming]
          if transition.alignment == taStart:
            track.add dissolveItem(transition, "audio", timebase, ntsc)

        var startVal = $aclip.start
        var endVal = $(aclip.start + aclip.dur)
        var inFrame = aclip.offset
        var outFrame = aclip.offset + aclip.dur
        if transitionLinks[j].incoming >= 0:
          let transition = transitions[transitionLinks[j].incoming]
          if transition.alignment == taCenter:
            startVal = "-1"
            inFrame = max(0'i64, inFrame - transition.dur div 2)
          elif transition.alignment == taStart:
            startVal = "-1"
        if transitionLinks[j].outgoing >= 0:
          let transition = transitions[transitionLinks[j].outgoing]
          if transition.alignment == taCenter:
            endVal = "-1"
            outFrame += transition.dur - transition.dur div 2
          elif transition.alignment == taEnd:
            endVal = "-1"
        let inVal = $inFrame
        let outVal = $outFrame

        let clipitem = newElement("clipitem")
        clipitem.attrs = {"id": &"clipitem-{ids[j]}"}.toXmlAttributes
        clipitem.add elem("name", agSplitFile(mi.path).name)
        clipitem.add elem("start", startVal)
        clipitem.add elem("end", endVal)
        clipitem.add elem("enabled", "TRUE")
        clipitem.add elem("in", inVal)
        clipitem.add elem("out", outVal)
        clipitem.addTicks(tl.effects[aclip.effects], aclip, inFrame, outFrame, tl.tb, false)

        files.makeFiledef(clipitem, mi, tl, timebase, ntsc)

        let sourcetrack = newElement("sourcetrack")
        sourcetrack.add elem("mediatype", "audio")
        sourcetrack.add elem("trackindex", $(sub + 1))
        clipitem.add sourcetrack

        clipitem.addResolveLinks(tl, audioIds, j)

        for f in clipFilters(tl.effects[aclip.effects], aclip, false, inFrame,
            outFrame, aclip.dur, tl.tb.float64):
          clipitem.add f

        track.add clipitem
        if transitionLinks[j].outgoing >= 0:
          track.add dissolveItem(transitions[transitionLinks[j].outgoing],
            "audio", timebase, ntsc)
      audio.add track

type AudioTrackInfo = object
  layerIdx: int         # Index into tl.a
  isStereo: bool        # Stereo source -> exploded track-pair; else mono track
  explodedIndex: int    # currentExplodedTrackIndex (0 or 1); 0 for mono
  sourceTrackIndex: int # sourcetrack/trackindex into the source file
  firstClipId: int      # clipitem id of this track's first clip

proc planPremiereAudio(tl: v3, ptrToMi: Table[ptr string, MediaInfo],
    firstAudioId: int): seq[AudioTrackInfo] =
  ## Lay out the audio tracks. A stereo (or higher) source is split into two
  ## exploded stereo tracks; a mono source becomes a single mono track. The
  ## exploded structure can't represent mono: Premiere derives each channel
  ## from currentExplodedTrackIndex, so a mono source's second exploded track
  ## would read a non-existent channel and play silent on one side.
  var nextId = firstAudioId
  var channelOffset = 0
  for layerIdx, alayer in tl.a:
    var channels = 1
    if alayer.len > 0 and alayer[0].src != nil:
      let mi = ptrToMi[alayer[0].src]
      let st = alayer[0].stream.int
      if st >= 0 and st < mi.a.len:
        channels = max(1, mi.a[st].channels.int)
    let isStereo = channels >= 2
    for explodedIndex in 0 ..< (if isStereo: 2 else: 1):
      result.add AudioTrackInfo(
        layerIdx: layerIdx,
        isStereo: isStereo,
        explodedIndex: explodedIndex,
        sourceTrackIndex: channelOffset + explodedIndex + 1,
        firstClipId: nextId,
      )
      nextId += alayer.len
    channelOffset += channels

proc premiereWriteAudio(audio: XmlNode, files: var FileDefs, tl: v3,
    ptrToMi: Table[ptr string, MediaInfo],
    audioPlan: seq[AudioTrackInfo], timebase: int64, ntsc: string) =
  audio.add elem("numOutputChannels", "2")
  let aformat = newElement("format")
  let aschar = newElement("samplecharacteristics")
  aschar.add elem("depth", DEPTH)
  aschar.add elem("samplerate", $tl.sr)
  aformat.add aschar
  audio.add aformat

  let hasVideo = tl.v.len > 0 and tl.v[0].len > 0
  var transitionPlans = newSeq[seq[TransitionLink]](tl.a.len)
  for i, layer in tl.a:
    let transitions = (if i < tl.at.len: tl.at[i] else: @[])
    transitionPlans[i] = transitionPlan(layer, transitions)
  for atrack in audioPlan:
    let alayer = tl.a[atrack.layerIdx]
    let track = newElement("track")
    let transitions = (if atrack.layerIdx < tl.at.len: tl.at[atrack.layerIdx] else: @[])
    let transitionLinks = transitionPlans[atrack.layerIdx]
    track.attrs = {
      "currentExplodedTrackIndex": $atrack.explodedIndex,
      "totalExplodedTrackCount": (if atrack.isStereo: "2" else: "1"),
      "premiereTrackType": (if atrack.isStereo: "Stereo" else: "Mono")
    }.toXmlAttributes

    if hasVideo and atrack.isStereo:
      track.add elem("outputchannelindex", $(atrack.explodedIndex + 1))

    for j, aclip in alayer.pairs:
      if aclip.src == nil:
        continue
      if transitionLinks[j].incoming >= 0:
        let t = transitions[transitionLinks[j].incoming]
        if t.alignment == taStart:
          track.add dissolveItem(t, "audio", timebase, ntsc)
      let src = ptrToMi[aclip.src]

      var startVal = $aclip.start
      var endVal = $(aclip.start + aclip.dur)
      var inFrame = aclip.offset
      var outFrame = aclip.offset + aclip.dur
      if transitionLinks[j].incoming >= 0:
        let t = transitions[transitionLinks[j].incoming]
        if t.alignment == taCenter:
          startVal = "-1"
          inFrame = max(0'i64, inFrame - t.dur div 2)
        elif t.alignment == taStart:
          startVal = "-1"
      if transitionLinks[j].outgoing >= 0:
        let t = transitions[transitionLinks[j].outgoing]
        if t.alignment == taCenter:
          endVal = "-1"
          outFrame += t.dur - t.dur div 2
        elif t.alignment == taEnd:
          endVal = "-1"
      let inVal = $inFrame
      let outVal = $outFrame

      let clipitem = newElement("clipitem")
      clipitem.attrs = {
        "id": &"clipitem-{atrack.firstClipId + j}",
        "premiereChannelType": (if atrack.isStereo: "stereo" else: "mono")
      }.toXmlAttributes
      clipitem.add elem("name", agSplitFile(src.path).name)
      clipitem.add elem("enabled", "TRUE")
      clipitem.add elem("start", startVal)
      clipitem.add elem("end", endVal)
      clipitem.add elem("in", inVal)
      clipitem.add elem("out", outVal)
      clipitem.addTicks(tl.effects[aclip.effects], aclip, inFrame, outFrame, tl.tb, false)

      files.makeFiledef(clipitem, src, tl, timebase, ntsc)

      let sourcetrack = newElement("sourcetrack")
      sourcetrack.add elem("mediatype", "audio")
      sourcetrack.add elem("trackindex", $atrack.sourceTrackIndex)
      clipitem.add sourcetrack

      let labels = newElement("labels")
      labels.add elem("label2", "Iris")
      clipitem.add labels

      for f in clipFilters(tl.effects[aclip.effects], aclip, false, inFrame,
          outFrame, aclip.dur, tl.tb.float64):
        clipitem.add f

      track.add clipitem
      if transitionLinks[j].outgoing >= 0:
        track.add dissolveItem(transitions[transitionLinks[j].outgoing],
          "audio", timebase, ntsc)
    audio.add track

proc handlePath(src: string): string =
  let absPath = src.absolutePath()
  when defined(windows):
    absPath.replace('\\', '/')
  else:
    absPath

proc dissolveItem(t: Transition, mediaType: string, timebase: int64,
    ntsc: string): XmlNode =
  let before = case t.alignment
    of taStart: 0'i64
    of taCenter: t.dur div 2
    of taEnd: t.dur
  result = newElement("transitionitem")
  let rate = newElement("rate")
  rate.add elem("timebase", $timebase)
  rate.add elem("ntsc", ntsc)
  result.add rate
  result.add elem("start", $(t.at - before))
  result.add elem("end", $(t.at + t.dur - before))
  result.add elem("alignment", case t.alignment
    of taStart: "start-black"
    of taCenter: "center"
    of taEnd: "end-black")
  let effect = newElement("effect")
  # FCP7 XML can't name the other kinds; editors read them as a dissolve.
  let effectName =
    if mediaType == "video": "Cross Dissolve"
    elif t.kind == tkConstantPower: "Cross Fade (+3dB)"
    else: "Cross Fade (0dB)"
  effect.add elem("name", effectName)
  effect.add elem("effectid", effectName)
  effect.add elem("effecttype", "transition")
  effect.add elem("mediatype", mediaType)
  effect.add elem("startratio", "0")
  effect.add elem("endratio", "1")
  effect.add elem("reverse", "FALSE")
  result.add effect

proc fcp7WriteXml*(name, output: string, resolve: bool, tl: v3) =
  let (width, height) = tl.res
  let (timebase, ntsc) = setTbNtsc(tl.tb)

  var files = FileDefs(resolve: resolve)
  var ptrToMi = initTable[ptr string, MediaInfo]()       # Cache ptr -> MediaInfo lookup

  var idCounter = 0
  for ptrSrc in tl.uniqueSources:
    idCounter += 1
    let src = ptrSrc[]
    let mi = initMediaInfo(src)
    files.urls[mi] = handlePath(src)
    files.ids[mi] = &"file-{idCounter}"
    ptrToMi[ptrSrc] = mi

  let hasVideo = tl.v.len > 0 and tl.v[0].len > 0

  # clipitem ids run V1, V2, ... then audio. Audio ids start past every video clip
  # across all tracks, not just v[0]'s, so <link> refs stay unambiguous.
  var videoTrackStart = newSeq[int](tl.v.len)
  var nextVideoId = 1
  for k in 0 ..< tl.v.len:
    videoTrackStart[k] = nextVideoId
    nextVideoId += tl.v[k].len
  let firstAudioId = (if hasVideo: nextVideoId else: 1)
  let audioPlan = if resolve: @[] else: planPremiereAudio(tl, ptrToMi, firstAudioId)
  let resolveAudio = if resolve: planResolveAudio(tl, ptrToMi) else: @[]

  let xmeml = <>xmeml(version = "5")
  let sequence = (if resolve: <>sequence() else: <>sequence(explodedTracks = "true"))

  sequence.add elem("name", name)
  sequence.add elem("duration", $tl.len)
  let rate1 = newElement("rate")
  rate1.add elem("timebase", $timebase)
  rate1.add elem("ntsc", ntsc)
  sequence.add rate1

  let media = newElement("media")
  let video = newElement("video")
  let vformat = newElement("format")
  let vschar = newElement("samplecharacteristics")

  vschar.add elem("width", $width)
  vschar.add elem("height", $height)
  vschar.add elem("pixelaspectratio", "square")

  let rate2 = newElement("rate")
  rate2.add elem("timebase", $timebase)
  rate2.add elem("ntsc", ntsc)
  vschar.add rate2
  vformat.add vschar
  video.add vformat

  if hasVideo:
    for vIdx, vlayer in tl.v:
      # resolve-fcp7's link/id scheme is wired for a single video track; only
      # Premiere gets the overlay tracks (v[1..]).
      if resolve and vIdx > 0:
        break
      if vlayer.len == 0:
        continue
      let track = newElement("track")
      let trackStart = videoTrackStart[vIdx]
      let transitions = (if vIdx < tl.vt.len: tl.vt[vIdx] else: @[])
      let transitionLinks = transitionPlan(vlayer, transitions)

      for j, clip in vlayer.pairs:
        # An audio-only timeline that gained `add:` overlays has a synthesized
        # base track with no source file (just a render canvas); there is nothing
        # to write for Premiere, so skip it (and drop a track left empty).
        if clip.src == nil:
          continue

        if transitionLinks[j].incoming >= 0:
          let t = transitions[transitionLinks[j].incoming]
          if t.alignment == taStart:
            track.add dissolveItem(t, "video", timebase, ntsc)
        let mi = ptrToMi[clip.src]
        let still = mi.isStill
        var startVal = $clip.start
        var endVal = $(clip.start + clip.dur)
        # A still is the same frame at every offset, so read `dur` frames from 0;
        # real media keeps its true source in/out.
        var inFrame = clip.offset
        var outFrame = clip.offset + clip.dur
        if transitionLinks[j].incoming >= 0:
          let t = transitions[transitionLinks[j].incoming]
          if t.alignment == taCenter:
            startVal = "-1"
            inFrame = max(0'i64, inFrame - t.dur div 2)
          elif t.alignment == taStart:
            startVal = "-1"
        if transitionLinks[j].outgoing >= 0:
          let t = transitions[transitionLinks[j].outgoing]
          if t.alignment == taCenter:
            endVal = "-1"
            outFrame += t.dur - t.dur div 2
          elif t.alignment == taEnd:
            endVal = "-1"
        let inVal = (if still: "0" else: $inFrame)
        let outVal = (if still: $clip.dur else: $outFrame)

        let thisClipid = &"clipitem-{trackStart + j}"
        let clipitem = <>clipitem(id = thisClipid)
        clipitem.add elem("name", agSplitFile(clip.src[]).name)
        clipitem.add elem("enabled", "TRUE")
        clipitem.add elem("start", startVal)
        clipitem.add elem("end", endVal)
        clipitem.add elem("in", inVal)
        clipitem.add elem("out", outVal)
        if still: clipitem.addTicks(tl.effects[clip.effects], clip, 0, clip.dur, tl.tb, true)
        else: clipitem.addTicks(tl.effects[clip.effects], clip, inFrame, outFrame, tl.tb, true)

        files.makeFiledef(clipitem, mi, tl, timebase, ntsc)

        clipitem.add elem("compositemode", "normal")

        for f in clipFilters(tl.effects[clip.effects], clip, true,
            (if still: 0'i64 else: inFrame), (if still: clip.dur else: outFrame),
            clip.dur, tl.tb.float64):
          clipitem.add f

        if resolve:
          clipitem.addResolveLinks(tl, resolveAudio, j)
        elif vIdx == 0:
          # Base track: link the clip to itself and to its aligned audio clips so
          # they move together. Overlay tracks (v[1..]) carry no audio, so they
          # stay standalone rather than forming a one-member self-link group.
          let vlink = newElement("link")
          vlink.add elem("linkclipref", thisClipid)
          vlink.add elem("mediatype", "video")
          vlink.add elem("trackindex", "1")
          vlink.add elem("clipindex", $(j + 1))
          clipitem.add vlink
          for k, atrack in audioPlan:
            if j >= tl.a[atrack.layerIdx].len: continue
            let link = newElement("link")
            link.add elem("linkclipref", &"clipitem-{atrack.firstClipId + j}")
            link.add elem("mediatype", "audio")
            link.add elem("trackindex", $(k + 1))
            link.add elem("clipindex", $(j + 1))
            clipitem.add link

        track.add clipitem
        if transitionLinks[j].outgoing >= 0:
          track.add dissolveItem(transitions[transitionLinks[j].outgoing],
            "video", timebase, ntsc)
      if track.len > 0:
        video.add track

  media.add video

  # Audio definitions and clips
  let audio = newElement("audio")
  if resolve:
    resolveWriteAudio(audio, files, tl, ptrToMi, resolveAudio, timebase, ntsc)
  else:
    premiereWriteAudio(audio, files, tl, ptrToMi, audioPlan, timebase, ntsc)

  media.add audio
  sequence.add media
  xmeml.add sequence

  writeXml(xmeml, output)
