import std/[os, sets, strformat, tables, xmltree]
from std/math import ceil, round
when defined(windows):
  import std/strutils

import ../[action, ffmpeg, media, timeline]
import ../util/[fun, rational]

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
  if ctb notin [24'i64, 30, 60] and tb == ctb * AVRational(num: 999, den: 1000):
    return (ctb, "TRUE")

  return (tb.int64, "FALSE")


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

func speedup(speed: float): XmlNode =
  let fil = newElement("filter")
  let effect = newElement("effect")
  effect.add elem("name", "Time Remap")
  effect.add elem("effectid", "timeremap")
  effect.add param("variablespeed", "variablespeed", "0", "0", "1")
  effect.add param("speed", "speed", $speed, "-100000", "100000")
  effect.add param("frameblending", "frameblending", "FALSE")
  fil.add effect

  return fil


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

proc resolveWriteAudio(audio: XmlNode, makeFiledef: proc(clipitem: XmlNode,
    mi: MediaInfo), tl: v3, ptrToMi: Table[ptr string, MediaInfo]) =
  for t, alayer in tl.a.pairs:
    let track = newElement("track")
    for j, aclip in alayer.pairs:
      let mi = ptrToMi[aclip.src]

      let startVal = $aclip.start
      let endVal = $(aclip.start + aclip.dur)
      let inVal = $aclip.offset
      let outVal = $(aclip.offset + aclip.dur)

      let clipItemNum = if mi.v.len == 0: j + 1 else: alayer.len + 1 + j

      let clipitem = newElement("clipitem")
      clipitem.attrs = {"id": &"clipitem-{clipItemNum}"}.toXmlAttributes
      clipitem.add elem("name", agSplitFile(mi.path).name)
      clipitem.add elem("start", startVal)
      clipitem.add elem("end", endVal)
      clipitem.add elem("enabled", "TRUE")
      clipitem.add elem("in", inVal)
      clipitem.add elem("out", outVal)

      makeFiledef(clipitem, mi)

      let sourcetrack = newElement("sourcetrack")
      sourcetrack.add elem("mediatype", "audio")
      sourcetrack.add elem("trackindex", $(t + 1))
      clipitem.add sourcetrack

      if mi.v.len > 0:
        let link1 = newElement("link")
        link1.add elem("linkclipref", &"clipitem-{j + 1}")
        link1.add elem("mediatype", "video")
        clipitem.add link1
        let link2 = newElement("link")
        link2.add elem("linkclipref", &"clipitem-{clipItemNum}")
        clipitem.add link2

      let effectGroup = tl.effects[aclip.effects]
      for effect in effectGroup:
        if effect.kind in [actSpeed, actVarispeed]:
          clipitem.add speedup(effect.val * 100)
          break

      track.add clipitem
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
    if alayer.len > 0:
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

proc premiereWriteAudio(audio: XmlNode, makeFiledef: proc(clipitem: XmlNode,
    mi: MediaInfo), tl: v3, ptrToMi: Table[ptr string, MediaInfo],
    audioPlan: seq[AudioTrackInfo]) =
  audio.add elem("numOutputChannels", "2")
  let aformat = newElement("format")
  let aschar = newElement("samplecharacteristics")
  aschar.add elem("depth", DEPTH)
  aschar.add elem("samplerate", $tl.sr)
  aformat.add aschar
  audio.add aformat

  let hasVideo = tl.v.len > 0 and tl.v[0].len > 0
  for atrack in audioPlan:
    let alayer = tl.a[atrack.layerIdx]
    let track = newElement("track")
    track.attrs = {
      "currentExplodedTrackIndex": $atrack.explodedIndex,
      "totalExplodedTrackCount": (if atrack.isStereo: "2" else: "1"),
      "premiereTrackType": (if atrack.isStereo: "Stereo" else: "Mono")
    }.toXmlAttributes

    if hasVideo and atrack.isStereo:
      track.add elem("outputchannelindex", $(atrack.explodedIndex + 1))

    for j, aclip in alayer.pairs:
      let src = ptrToMi[aclip.src]

      let startVal = $aclip.start
      let endVal = $(aclip.start + aclip.dur)
      let inVal = $aclip.offset
      let outVal = $(aclip.offset + aclip.dur)

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

      makeFiledef(clipitem, src)

      let sourcetrack = newElement("sourcetrack")
      sourcetrack.add elem("mediatype", "audio")
      sourcetrack.add elem("trackindex", $atrack.sourceTrackIndex)
      clipitem.add sourcetrack

      let labels = newElement("labels")
      labels.add elem("label2", "Iris")
      clipitem.add labels

      let effectGroup = tl.effects[aclip.effects]
      for effect in effectGroup:
        if effect.kind in [actSpeed, actVarispeed]:
          clipitem.add speedup(effect.val * 100)
          break

      track.add clipitem
    audio.add track

proc handlePath(src: string): string =
  let absPath = src.absolutePath()
  when defined(windows):
    absPath.replace('\\', '/')
  else:
    absPath

func isStillImage(mi: MediaInfo, tb: AVRational): bool =
  ## A source with a video stream but essentially no duration (0 or 1 frame) is a
  ## still image. Premiere holds these for a fixed length; given a blank
  ## `<duration>` it ignores the clip's in/out and falls back to a ~12h default.
  mi.v.len > 0 and int64(round(mi.duration * tb.float64)) <= 1

proc fcp7WriteXml*(name, output: string, resolve: bool, tl: v3) =
  let (width, height) = tl.res
  let (timebase, ntsc) = setTbNtsc(tl.tb)

  var miToUrl = initTable[MediaInfo, string]()
  var miToId = initTable[MediaInfo, string]()
  var ptrToMi = initTable[ptr string, MediaInfo]() # Cache ptr -> MediaInfo lookup
  var fileDefs = initHashSet[string]() # Contains urls

  var idCounter = 0
  for ptrSrc in tl.uniqueSources:
    idCounter += 1
    let src = ptrSrc[]
    let mi = initMediaInfo(src)
    miToUrl[mi] = handlePath(src)
    miToId[mi] = &"file-{idCounter}"
    ptrToMi[ptrSrc] = mi

  proc makeFiledef(clipitem: XmlNode, mi: MediaInfo) =
    let pathurl = miToUrl[mi]
    let filedef = <>file(id = miToId[mi])
    if pathurl notin fileDefs:
      let durationStr =
        if resolve: ""                              # Resolve wants it blank
        elif isStillImage(mi, tl.tb): $tl.len       # hold the still long enough
        else: ""                                    # Premiere reads media length
      mediaDef(filedef, pathurl, mi, tl, timebase, ntsc, durationStr)
      fileDefs.incl(pathurl)
    clipitem.add filedef

  let hasVideo = tl.v.len > 0 and tl.v[0].len > 0

  # clipitem ids run V1, V2, ... then audio. Overlay tracks (v[1..]) used to be
  # dropped entirely; emitting them means audio ids must start past every video
  # clip, not just v[0]'s.
  var videoTrackStart = newSeq[int](tl.v.len)
  var nextVideoId = 1
  for k in 0 ..< tl.v.len:
    videoTrackStart[k] = nextVideoId
    nextVideoId += tl.v[k].len
  let firstAudioId = (if hasVideo: nextVideoId else: 1)
  let audioPlan = (if resolve: @[]
                   else: planPremiereAudio(tl, ptrToMi, firstAudioId))

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

      for j, clip in vlayer.pairs:
        # An audio-only timeline that gained `add:` overlays has a synthesized
        # base track with no source file (just a render canvas); there is nothing
        # to write for Premiere, so skip it (and drop a track left empty).
        if clip.src == nil:
          continue

        let mi = ptrToMi[clip.src]
        let still = isStillImage(mi, tl.tb)
        let startVal = $clip.start
        let endVal = $(clip.start + clip.dur)
        # A still is the same frame at every offset, so read `dur` frames from 0;
        # real media keeps its true source in/out.
        let inVal = (if still: "0" else: $clip.offset)
        let outVal = (if still: $clip.dur else: $(clip.offset + clip.dur))

        let thisClipid = &"clipitem-{trackStart + j}"
        let clipitem = <>clipitem(id = thisClipid)
        clipitem.add elem("name", agSplitFile(clip.src[]).name)
        clipitem.add elem("enabled", "TRUE")
        clipitem.add elem("start", startVal)
        clipitem.add elem("end", endVal)
        clipitem.add elem("in", inVal)
        clipitem.add elem("out", outVal)

        makeFiledef(clipitem, mi)

        clipitem.add elem("compositemode", "normal")

        let effectGroup = tl.effects[clip.effects]
        for effect in effectGroup:
          if effect.kind in [actSpeed, actVarispeed]:
            clipitem.add speedup(effect.val * 100)
            break

        if resolve:
          let link1 = newElement("link")
          link1.add elem("linkclipref", thisClipid)
          clipitem.add link1
          let link2 = newElement("link")
          link2.add elem("linkclipref", &"clipitem-{tl.v[0].len + j + 1}")
          clipitem.add link2
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
      if track.len > 0:
        video.add track

  media.add video

  # Audio definitions and clips
  let audio = newElement("audio")
  if resolve:
    resolveWriteAudio(audio, makeFiledef, tl, ptrToMi)
  else:
    premiereWriteAudio(audio, makeFiledef, tl, ptrToMi, audioPlan)

  media.add audio
  sequence.add media
  xmeml.add sequence

  if output == "-":
    echo $xmeml
  else:
    let xmlStr = "<?xml version='1.0' encoding='utf-8'?>\n" & $xmeml
    writeFile(output, xmlStr)
