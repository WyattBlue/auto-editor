import std/[json, os, sequtils, tables, strformat, sysrand, strutils]
import ./mlt
import ../util/xml
import ../[action, media, timeline]
import ../util/[color, fun, rational]
import ../lib/dnorm16

proc genUuid*(): string =
  var bytes: array[16, byte]
  discard urandom(bytes)

  # Set version (4) and variant bits according to RFC 4122
  bytes[6] = (bytes[6] and 0x0F) or 0x40 # Version 4
  bytes[8] = (bytes[8] and 0x3F) or 0x80 # Variant bits

  # Convert to hex string in UUID format: xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx
  result = ""
  for i, b in bytes:
    result.add(b.toHex(2).toLowerAscii())
    if i in [3, 5, 7, 9]:
      result.add("-")

type Kdenlive = object
  ## A Kdenlive project being written. Element ids are numbered in document
  ## order, so the counters advance as elements are added.
  mlt: XmlNode
  tb: AVRational
  globalOut: string # the timeline's length as a timecode
  aChannels, vChannels: int
  uniquePaths: seq[string]       # sources in order of first appearance
  sourceIds: Table[string, string] # path -> kdenlive:id
  pathDuration: Table[string, float64]
  chains, playlists, filterId, transitionId: int
  clipPlaylists: seq[XmlNode]    # two sub-playlists per track
  trackTractors: seq[XmlNode]
  # (track, source path) -> chain id, per track type
  audioChainOf, videoChainOf: Table[(int, string), int]
  binChainOf: Table[string, int]

const zeroTc = "00:00:00.000"

func nch(k: Kdenlive): int = k.aChannels + k.vChannels

func warpedProducerId(k: Kdenlive, w, channel: int): string =
  ## Producer ids for warped clips are a pure function of the clip's index in
  ## the warped clips and the channel, so creating them and referencing them
  ## from entries cannot drift apart.
  &"producer{1 + w * k.nch + channel}"

proc tcf(k: Kdenlive, f: int64): string = toTimecode(f.float / k.tb.float, standard)

proc element(tag: string, attrs: openArray[(string, string)]): XmlNode =
  result = newElement(tag)
  result.attrs = attrs.toXmlAttributes()

proc addProps(parent: XmlNode, props: openArray[(string, string)]) =
  for (name, value) in props:
    parent.addProp(name, value)

func streamProps(k: Kdenlive, channel: int): array[4, (string, string)] =
  ## Which of the source's streams channel `channel` (audio tracks first)
  ## plays, and the test flags that hide the other kind.
  if channel < k.aChannels:
    [("vstream", "0"), ("astream", $(k.aChannels - 1 - channel)),
     ("set.test_audio", "0"), ("set.test_video", "1")]
  else:
    [("vstream", $(k.vChannels - 1 - (channel - k.aChannels))), ("astream", "0"),
     ("set.test_audio", "1"), ("set.test_video", "0")]

proc addBlackProducer(k: var Kdenlive) =
  ## The reserved producer0 the sequence's first track plays.
  let producer = element("producer", {"id": "producer0"})
  producer.addProps({"length": k.globalOut, "eof": "continue",
    "resource": "black", "mlt_service": "color",
    "kdenlive:playlistid": "black_track", "mlt_image_format": "rgba",
    "aspect_ratio": "1"})
  k.mlt.add(producer)

proc addWarpedProducers(k: var Kdenlive, tl: v3, clips: seq[Clip],
    warpedClips: seq[int]) =
  ## A timewarp producer per warped clip and channel.
  for w, clipIdx in warpedClips:
    for i in 0 ..< k.nch:
      let clip = clips[clipIdx]
      let path = $clip.src[]

      var speedVal = 1.0
      var warpPitch = false
      for effect in tl.effects[clip.effects]:
        if effect.kind == actSpeed:
          speedVal = effect.val
          warpPitch = not effect.varispeed
          break

      let prod = element("producer", {
        "id": k.warpedProducerId(w, i),
        "in": zeroTc,
        # A timewarp producer is as long as the warped source, not the
        # timeline; clamping to timeline length freezes any clip whose warped
        # source position lies past it.
        "out": toTimecode(k.pathDuration[path] / speedVal, standard)})
      prod.addProps({"resource": &"{speedVal}:{path}", "warp_speed": $speedVal,
        "warp_resource": path, "warp_pitch": (if warpPitch: "1" else: "0"),
        "mlt_service": "timewarp", "kdenlive:id": k.sourceIds[path]})
      prod.addProps(k.streamProps(i))
      k.mlt.add(prod)

proc addChain(k: var Kdenlive, path: string,
    props: openArray[(string, string)]): int =
  ## A chain reading `path` with `props`, returning its id.
  result = k.chains
  let chain = element("chain", {"id": &"chain{k.chains}"})
  chain.addProps({"resource": path, "mlt_service": "avformat-novalidate"})
  chain.addProps(props)
  chain.addProp("kdenlive:id", k.sourceIds[path])
  k.mlt.add(chain)
  inc k.chains

proc addTrack(k: var Kdenlive, channel: int) =
  ## A track's chains (one per source), its two sub-playlists, and the
  ## tractor that plays them.
  let isAudio = channel < k.aChannels
  let i = (if isAudio: channel else: channel - k.aChannels)
  for path in k.uniquePaths:
    let id = k.addChain(path, k.streamProps(channel))
    if isAudio: k.audioChainOf[(i, path)] = id
    else: k.videoChainOf[(i, path)] = id

  for _ in 0 ..< 2:
    let playlist = element("playlist", {"id": &"playlist{k.playlists}"})
    k.clipPlaylists.add(playlist)
    if isAudio:
      playlist.addProp("kdenlive:audio_track", "1")
    k.mlt.add(playlist)
    inc k.playlists

  let tractor = element("tractor", {"id": &"tractor{channel}", "in": zeroTc,
    "out": k.globalOut})
  if isAudio:
    tractor.addProps({"kdenlive:audio_track": "1", "kdenlive:timeline_active": "1"})
    tractor.add(element("property", {"name": "kdenlive:audio_rec"}))
  else:
    tractor.addProp("kdenlive:timeline_active", "1")
  let hide = (if isAudio: "video" else: "audio")
  tractor.add(element("track", {"hide": hide, "producer": &"playlist{k.playlists - 2}"}))
  tractor.add(element("track", {"hide": hide, "producer": &"playlist{k.playlists - 1}"}))
  k.mlt.add(tractor)
  k.trackTractors.add(tractor)

proc addFilter(k: var Kdenlive, parent: XmlNode, service: string,
    params: openArray[(string, string)] = [], inOut = ("", "")) =
  let filter =
    if inOut[0].len > 0:
      element("filter", {"id": &"filter{k.filterId}", "in": inOut[0], "out": inOut[1]})
    else:
      element("filter", {"id": &"filter{k.filterId}"})
  inc k.filterId
  filter.addProps({"mlt_service": service, "kdenlive_id": service,
    "kdenlive:collapsed": "0"})
  filter.addProps(params)
  parent.add(filter)

# Animated ramps become MLT animation strings with 0-based positions, so
# the filter needs an explicit in/out matching the entry it is attached to.
template anim(effect: Action, inTc, outTc: string): (string, string) =
  (if effect.isAnimated: (inTc, outTc) else: ("", ""))

proc addAudioEffects(k: var Kdenlive, parent: XmlNode, effects: Actions,
    clipDur: int, inTc, outTc: string) =
  let fps = k.tb.float
  for effect in effects:
    case effect.kind
    of actVolume:
      if effect.kf.len > 0:
        k.addFilter(parent, "volume", [
          ("level", mltAnimValue(effect, clipDur, fps, asDb = true))],
          anim(effect, inTc, outTc))
    of actDeesser:
      k.addFilter(parent, "avfilter.deesser", [
        ("av.i", $effect.intensity), ("av.m", $effect.maxd),
        ("av.f", $effect.freq), ("av.s", "o")])
    else: discard

proc addVideoEffects(k: var Kdenlive, parent: XmlNode, effects: Actions,
    clipDur: int, inTc, outTc: string) =
  let fps = k.tb.float
  for effect in effects:
    case effect.kind
    of actInvert: k.addFilter(parent, "avfilter.negate")
    of actHflip: k.addFilter(parent, "avfilter.hflip")
    of actVflip: k.addFilter(parent, "avfilter.vflip")
    of actErosion: k.addFilter(parent, "avfilter.erosion")
    of actBlur:
      if effect.kf.len > 0:
        let sigma = mltAnimValue(effect, clipDur, fps)
        k.addFilter(parent, "avfilter.gblur", [
          ("av.sigma", sigma), ("av.sigmaV", sigma),
          ("av.steps", "1"), ("av.planes", "7")],
          anim(effect, inTc, outTc))
    of actBrightness:
      if effect.kf.len > 0:
        let expr = brightnessLutExpr(effect.kf[0])
        k.addFilter(parent, "avfilter.lutrgb", [
          ("av.r", expr), ("av.g", expr), ("av.b", expr)])
    of actLuv:
      let expr = luvLutExprs(effect.brighthue, effect.contrast,
        effect.saturation)
      k.addFilter(parent, "avfilter.lutyuv", [
        ("av.y", expr.y), ("av.u", expr.u), ("av.v", expr.v)])
    of actLens:
      k.addFilter(parent, "avfilter.lenscorrection", [
        ("av.cx", "0.5"), ("av.cy", "0.5"),
        ("av.k1", $effect.k1), ("av.k2", $effect.k2),
        ("av.i", "0"), ("av.fc", "0x00000000")])
    of actDrawbox:
      let rect = &"{effect.dbX} {effect.dbY} {effect.dbW} {effect.dbH}"
      k.addFilter(parent, "avfilter.drawbox", [
        ("kdenlive:fakerect", rect), ("av.x", $effect.dbX),
        ("av.y", $effect.dbY), ("av.w", $effect.dbW),
        ("av.h", $effect.dbH),
        ("av.color", effect.dbColor.toString.replace("#", "0x")),
        # Kdenlive declares thickness as a numeric animated parameter, so its
        # UI rejects FFmpeg's otherwise-valid `fill` token. A thickness at
        # least as large as the box fills it equivalently.
        ("av.t", $max(effect.dbW, effect.dbH)), ("av.replace", "0")])
    of actPixelate:
      k.addFilter(parent, "avfilter.pixelize", [
        ("av.width", mltAnimValue(effect, effect.pixWKf, effect.pixWKt, clipDur, fps, asInt = true)),
        ("av.height", mltAnimValue(effect, effect.pixHKf, effect.pixHKt, clipDur, fps, asInt = true)),
        ("av.mode", "avg"), ("av.planes", "7")], anim(effect, inTc, outTc))
    of actAberration:
      k.addFilter(parent, "avfilter.rgbashift", [
        ("av.rh", $effect.abRh), ("av.rv", $effect.abRv),
        ("av.gh", $effect.abGh), ("av.gv", $effect.abGv),
        ("av.bh", $effect.abBh), ("av.bv", $effect.abBv),
        ("av.edge", if effect.abWrap: "wrap" else: "smear")])
    else: discard

proc addMix(k: var Kdenlive, c: int, t: Transition, h, h2: int64, parity: int) =
  ## The luma/mix transition in track `c`'s tractor that composites a centered
  ## dissolve's overlap.
  let isAudio = c < k.aChannels
  let tr = element("transition", {"id": &"mix{k.transitionId}",
    "in": k.tcf(t.at - h), "out": k.tcf(t.at + h2 - 1)})
  inc k.transitionId
  let service = (if isAudio: "mix" else: "luma")
  tr.addProps({"mlt_service": service, "kdenlive_id": service,
    "a_track": "0", "b_track": "1", "kdenlive:mixcut": $h})
  if isAudio:
    tr.addProps({"start": "-1", "accepts_blanks": "1"})
  if parity == 0:
    # The incoming clip landed on the lower sub-playlist, so the
    # dissolve runs toward a_track instead of b_track.
    tr.addProp("reverse", "1")
  k.trackTractors[c].add(tr)

proc placeClips(k: var Kdenlive, tl: v3, c: int, base, clips: seq[Clip],
    warpedIdxOf: Table[int, int], groupChildren: var seq[seq[JsonNode]]) =
  ## Track `c`'s entries. A centered dissolve becomes a Kdenlive same-track
  ## mix: the joined clips are extended to overlap, the incoming clip moves to
  ## the track's other sub-playlist (offset with a blank), and a luma/mix
  ## transition in the track's tractor composites the overlap. Start/end-aligned
  ## dissolves become fade filters on the entry.
  let isAudio = c < k.aChannels
  var chTransitions: seq[Transition]
  if isAudio:
    if tl.at.len > 0: chTransitions = tl.at[0]
  else:
    if tl.vt.len > 0: chTransitions = tl.vt[0]
  chTransitions = sourcedTransitions(base, chTransitions)
  let chPlan = transitionPlan(clips, chTransitions)
  var parity = 0
  var cursors: array[2, int64]

  for ci, clip in clips:
    let path = $clip.src[]
    let `in` = k.tcf(clip.offset)
    let `out` = k.tcf(clip.offset + clip.dur - 1)
    let effectGroup = tl.effects[clip.effects]

    var entryIn = clip.offset
    var entryOut = clip.offset + clip.dur - 1
    var tlStart = clip.start
    var tlEnd = clip.start + clip.dur
    var fadeInDur, fadeOutDur = 0'i64

    if chPlan[ci].incoming >= 0:
      let t = chTransitions[chPlan[ci].incoming]
      if t.alignment == taCenter:
        # An imported timeline may give this clip less source preroll than
        # the dissolve half; clamp so source positions stay non-negative.
        let h = min(t.dur div 2, clip.offset)
        let h2 = t.dur - t.dur div 2
        entryIn -= h
        tlStart -= h
        parity = 1 - parity
        k.addMix(c, t, h, h2, parity)
      else:
        fadeInDur = t.dur
    if chPlan[ci].outgoing >= 0:
      let t = chTransitions[chPlan[ci].outgoing]
      if t.alignment == taCenter:
        entryOut += t.dur - t.dur div 2
        tlEnd = t.at + (t.dur - t.dur div 2)
      else:
        fadeOutDur = t.dur

    let playlist = k.clipPlaylists[2 * c + parity]
    if tlStart > cursors[parity]:
      playlist.add(element("blank", {"length": k.tcf(tlStart - cursors[parity])}))
    cursors[parity] = tlEnd

    let clipProd =
      if ci in warpedIdxOf: k.warpedProducerId(warpedIdxOf[ci], c)
      elif isAudio: &"chain{k.audioChainOf[(c, path)]}"
      else: &"chain{k.videoChainOf[(c - k.aChannels, path)]}"

    let entry = element("entry", {"producer": clipProd, "in": k.tcf(entryIn),
      "out": k.tcf(entryOut)})
    entry.addProp("kdenlive:id", k.sourceIds[path])

    let fadeIn = (k.tcf(clip.offset), k.tcf(clip.offset + fadeInDur - 1))
    let fadeOut = (k.tcf(clip.offset + clip.dur - fadeOutDur),
      k.tcf(clip.offset + clip.dur - 1))
    if isAudio:
      k.addAudioEffects(entry, effectGroup, int(clip.dur), `in`, `out`)
      if fadeInDur > 0:
        k.addFilter(entry, "volume", [("level", mltFadeAnim("-60", "0", fadeInDur))],
          fadeIn)
      if fadeOutDur > 0:
        k.addFilter(entry, "volume", [("level", mltFadeAnim("0", "-60", fadeOutDur))],
          fadeOut)
    else:
      k.addVideoEffects(entry, effectGroup, int(clip.dur), `in`, `out`)
      if fadeInDur > 0:
        k.addFilter(entry, "brightness", [("level", mltFadeAnim("0", "1", fadeInDur))],
          fadeIn)
      if fadeOutDur > 0:
        k.addFilter(entry, "brightness", [("level", mltFadeAnim("1", "0", fadeOutDur))],
          fadeOut)

    playlist.add(entry)
    groupChildren[ci].add(%*{
      "data": &"{c}:{tlStart}", "leaf": "clip", "type": "Leaf"})

proc addSequence(k: var Kdenlive, seqId: string, groups: seq[JsonNode]) =
  ## The default sequence's tractor: the black track, then every track.
  let sequence = element("tractor", {"id": seqId, "in": zeroTc, "out": zeroTc})
  sequence.addProps({"kdenlive:uuid": seqId, "kdenlive:clipname": "Sequence 1"})
  let groupsProp = element("property", {"name": "kdenlive:sequenceproperties.groups"})
  groupsProp.add(newVerbatimText(pretty(%groups, indent = 4)))
  sequence.add(groupsProp)
  sequence.add(element("track", {"producer": "producer0"}))
  for i in 0 ..< k.nch:
    sequence.add(element("track", {"producer": &"tractor{i}"}))
  k.mlt.add(sequence)

proc addBin(k: var Kdenlive, seqId: string) =
  ## The main bin: the sequence, then one bin chain per source.
  let playlistBin = element("playlist", {"id": "main_bin"})
  playlistBin.addProps({"kdenlive:docproperties.uuid": seqId,
    "kdenlive:docproperties.version": "1.1", "xml_retain": "1"})
  playlistBin.add(element("entry", {"producer": seqId, "in": zeroTc, "out": zeroTc}))
  for path in k.uniquePaths:
    playlistBin.add(element("entry", {"producer": &"chain{k.binChainOf[path]}",
      "in": zeroTc}))
  k.mlt.add(playlistBin)

proc kdenliveWrite*(output: string, tl: v3) =
  let (width, height) = tl.res
  let (num, den) = aspectRatio(width, height)
  var k = Kdenlive(tb: tl.tb, aChannels: tl.a.len, vChannels: tl.v.len,
    globalOut: toTimecode(tl.len.float / tl.tb.float, standard))
  let seqId = &"{{{genUuid()}}}"

  k.mlt = element("mlt", {"LC_NUMERIC": "C", "version": "7.22.0",
    "producer": "main_bin", "root": getCurrentDir()})
  k.mlt.add(element("profile", {
    "description": "automatic",
    "width": $width,
    "height": $height,
    "progressive": "1",
    "sample_aspect_num": "1",
    "sample_aspect_den": "1",
    "display_aspect_num": $num,
    "display_aspect_den": $den,
    "frame_rate_num": $k.tb.num,
    "frame_rate_den": $k.tb.den,
    "colorspace": "709"}))
  k.addBlackProducer()

  # A clip without a source file is left as a blank, so the background shows.
  let base = if tl.v.len > 0: tl.v[0] elif tl.a.len > 0: tl.a[0] else: @[]
  let clips = base.filterIt(it.src != nil)

  for clip in clips:
    let p = $clip.src[]
    if p notin k.uniquePaths:
      k.uniquePaths.add(p)
  for i, path in k.uniquePaths:
    k.sourceIds[path] = $(4 + i)
    k.pathDuration[path] = initMediaInfo(path).duration

  var warpedClips: seq[int] = @[]
  for i, clip in clips:
    for effect in tl.effects[clip.effects]:
      if effect.kind == actSpeed:
        warpedClips.add(i)
        break
  k.addWarpedProducers(tl, clips, warpedClips)

  for c in 0 ..< k.nch:
    k.addTrack(c)
  for path in k.uniquePaths:
    k.binChainOf[path] = k.addChain(path, {"audio_index": "1",
      "video_index": "0", "vstream": "0", "astream": "0"})

  var groupChildren = newSeq[seq[JsonNode]](clips.len)
  var warpedIdxOf = initTable[int, int]()
  for w, ci in warpedClips: warpedIdxOf[ci] = w
  for c in 0 ..< k.nch:
    k.placeClips(tl, c, base, clips, warpedIdxOf, groupChildren)

  var groups: seq[JsonNode] = @[]
  for children in groupChildren:
    groups.add(%*{"children": children, "type": "Normal"})
  k.addSequence(seqId, groups)
  k.addBin(seqId)

  # The reserved last tractor, for the project.
  let tractor = element("tractor", {"id": &"tractor{k.nch}", "in": zeroTc,
    "out": k.globalOut})
  tractor.addProp("kdenlive:projectTractor", "1")
  tractor.add(element("track", {"producer": seqId, "in": zeroTc,
    "out": k.globalOut}))
  k.mlt.add(tractor)

  writeXml(k.mlt, output)
