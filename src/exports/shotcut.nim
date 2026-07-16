import std/[strformat, strutils, xmltree]

import ./mlt
import ../[action, ffmpeg, timeline]
import ../util/[color, fun, rational]


#[

Shotcut uses the MLT timeline format

See docs here:
https://mltframework.org/docs/mltxml/

]#

proc addFilter(parent: XmlNode, service: string,
    params: openArray[(string, string)] = [], shotcutFilter = "",
    inOut = ("", "")) =
  let filter = newElement("filter")
  if inOut[0].len > 0:
    filter.attrs = {"in": inOut[0], "out": inOut[1]}.toXmlAttributes()
  filter.addProp("mlt_service", service)
  if shotcutFilter.len > 0:
    filter.addProp("shotcut:filter", shotcutFilter)
  for (name, value) in params:
    filter.addProp(name, value)
  parent.add(filter)

proc addActionFilters(parent: XmlNode, effects: Actions, clipDur: int,
    fps: float64, inTc, outTc: string) =
  # Animated ramps become MLT animation strings with 0-based positions, so
  # the filter needs an explicit in/out matching the played section.
  template anim(effect: Action): (string, string) =
    (if effect.isAnimated: (inTc, outTc) else: ("", ""))
  for effect in effects:
    case effect.kind
    of actVolume:
      if effect.kf.len > 0 and not (effect.kf.len == 1 and effect.kf[0] == 1.0):
        parent.addFilter("volume", [
          ("level", mltAnimValue(effect, clipDur, fps, asDb = true))],
          "audioGain", anim(effect))
    of actDeesser:
      parent.addFilter("avfilter.deesser", [
        ("av.i", $effect.intensity), ("av.m", $effect.maxd),
        ("av.f", $effect.freq), ("av.s", "o")])
    of actInvert: parent.addFilter("invert")
    of actHflip: parent.addFilter("avfilter.hflip")
    of actVflip: parent.addFilter("avfilter.vflip")
    of actErosion: parent.addFilter("avfilter.erosion")
    of actBlur:
      if effect.kf.len > 0:
        let sigma = mltAnimValue(effect, clipDur, fps)
        parent.addFilter("avfilter.gblur", [
          ("av.sigma", sigma), ("av.sigmaV", sigma),
          ("av.steps", "1"), ("av.planes", "7")], "blur_gaussian_av",
          anim(effect))
    of actBrightness:
      if effect.kf.len > 0:
        let expr = brightnessLutExpr(effect.kf[0])
        parent.addFilter("avfilter.lutrgb", [
          ("av.r", expr), ("av.g", expr), ("av.b", expr)])
    of actLuv:
      let expr = luvLutExprs(effect.brighthue, effect.contrast,
        effect.saturation)
      parent.addFilter("avfilter.lutyuv", [
        ("av.y", expr.y), ("av.u", expr.u), ("av.v", expr.v)])
    of actLens:
      parent.addFilter("avfilter.lenscorrection", [
        ("av.cx", "0.5"), ("av.cy", "0.5"),
        ("av.k1", $effect.k1), ("av.k2", $effect.k2),
        ("av.i", "0"), ("av.fc", "0x00000000")])
    of actDrawbox:
      parent.addFilter("avfilter.drawbox", [
        ("av.x", $effect.dbX), ("av.y", $effect.dbY),
        ("av.w", $effect.dbW), ("av.h", $effect.dbH),
        ("av.color", effect.dbColor.toString.replace("#", "0x")),
        ("av.t", $max(effect.dbW, effect.dbH)), ("av.replace", "0")])
    of actPixelate:
      parent.addFilter("avfilter.pixelize", [
        ("av.width", $effect.pixW), ("av.height", $effect.pixH),
        ("av.mode", "avg"), ("av.planes", "7")])
    of actAberration:
      parent.addFilter("avfilter.rgbashift", [
        ("av.rh", $effect.abRh), ("av.rv", $effect.abRv),
        ("av.gh", $effect.abGh), ("av.gv", $effect.abGv),
        ("av.bh", $effect.abBh), ("av.bv", $effect.abBv),
        ("av.edge", if effect.abWrap: "wrap" else: "smear")])
    else: discard

proc shotcutWriteMlt*(output: string, tl: v3) =
  let mlt = newElement("mlt")
  mlt.attrs = {
    "LC_NUMERIC": "C",
    "version": "7.33.0",
    "title": "Shotcut version 25.10.31",
    "producer": "main_bin"
  }.toXmlAttributes()

  let (width, height) = tl.res
  let (num, den) = aspectRatio(width, height)
  let tb = tl.tb

  let profile = newElement("profile")
  profile.attrs = {
    "description": "automatic",
    "width": $width,
    "height": $height,
    "progressive": "1",
    "sample_aspect_num": "1",
    "sample_aspect_den": "1",
    "display_aspect_num": $num,
    "display_aspect_den": $den,
    "frame_rate_num": $tb.num,
    "frame_rate_den": $tb.den,
    "colorspace": "709"
  }.toXmlAttributes()
  mlt.add(profile)

  let playlistBin = newElement("playlist")
  playlistBin.attrs = {"id": "main_bin"}.toXmlAttributes()
  playlistBin.addProp("xml_retain", "1")
  mlt.add(playlistBin)

  let global_out = toTimecode(float(tl.len / tl.tb), Code.standard)
  let global_last = toTimecode(float((tl.len - 1) / tl.tb), Code.standard)

  let producer = newElement("producer")
  producer.attrs = {"id": "bg"}.toXmlAttributes()
  producer.addProp("length", global_out)
  producer.addProp("eof", "pause")
  producer.addProp("resource", tl.bg.toString)
  producer.addProp("mlt_service", "color")
  producer.addProp("mlt_image_format", "rgba")
  producer.addProp("aspect_ratio", "1")

  mlt.add(producer)

  let playlist = newElement("playlist")
  playlist.attrs = {"id": "background"}.toXmlAttributes()
  let entry = newElement("entry")
  entry.attrs = {
    "producer": "bg",
    "in": "00:00:00.000",
    "out": global_last
  }.toXmlAttributes()
  entry.add(newText("1"))
  playlist.add(entry)
  mlt.add(playlist)

  var clipTagNames: seq[string] = @[]

  var layer: seq[Clip]
  var transitions: seq[Transition]
  if tl.v.len > 0:
    layer = tl.v[0]
    if tl.vt.len > 0: transitions = tl.vt[0]
  elif tl.a.len > 0:
    layer = tl.a[0]
    if tl.at.len > 0: transitions = tl.at[0]
  let plan = transitionPlan(layer, transitions)

  template tc(f: int64): string = toTimecode(float(f / tb), Code.standard)

  # A centered dissolve becomes a Shotcut same-track transition: the entries of
  # the joined clips are trimmed back from the edit point, and a two-track
  # sub-tractor plays clip A's tail against clip B's head with luma (video
  # dissolve) and mix (audio crossfade) transitions. Start/end-aligned
  # dissolves become fade filters on the clip itself.
  type ClipPlan = object
    entryIn, entryOut: int64   # source frames the plain entry still covers
    postroll: int64            # extra source frames the chain must expose
    fadeInDur, fadeOutDur: int64
    outCenter: int             # centered transition leaving this clip, or -1

  var plans = newSeq[ClipPlan](layer.len)
  for i, clip in layer:
    plans[i] = ClipPlan(entryIn: clip.offset,
      entryOut: clip.offset + clip.dur - 1, outCenter: -1)
    if plan[i].incoming >= 0:
      let t = transitions[plan[i].incoming]
      if t.alignment == taCenter:
        plans[i].entryIn += t.dur - t.dur div 2
      else:
        plans[i].fadeInDur = t.dur
    if plan[i].outgoing >= 0:
      let t = transitions[plan[i].outgoing]
      if t.alignment == taCenter:
        plans[i].entryOut -= t.dur div 2
        plans[i].postroll = t.dur - t.dur div 2
        plans[i].outCenter = plan[i].outgoing
      else:
        plans[i].fadeOutDur = t.dur

  proc addFadeFilters(parent: XmlNode, clip: Clip, fadeInDur, fadeOutDur: int64) =
    if fadeInDur > 0:
      let io = (tc(clip.offset), tc(clip.offset + fadeInDur - 1))
      if tl.v.len > 0:
        parent.addFilter("brightness", [("level", &"0=0;{fadeInDur - 1}=1")],
          "fadeInBrightness", io)
      if tl.a.len > 0:
        parent.addFilter("volume", [("level", &"0=-60;{fadeInDur - 1}=0")],
          "fadeInVolume", io)
    if fadeOutDur > 0:
      let fadeStart = clip.offset + clip.dur - fadeOutDur
      let io = (tc(fadeStart), tc(clip.offset + clip.dur - 1))
      if tl.v.len > 0:
        parent.addFilter("brightness", [("level", &"0=1;{fadeOutDur - 1}=0")],
          "fadeOutBrightness", io)
      if tl.a.len > 0:
        parent.addFilter("volume", [("level", &"0=0;{fadeOutDur - 1}=-60")],
          "fadeOutVolume", io)

  proc addSourceProducer(id: string, clip: Clip, srcEnd: int64,
      fadeInDur, fadeOutDur: int64) =
    ## A dedicated chain (or timewarp producer) for one use of a clip's
    ## source. A tractor track sets in/out on the producer object itself
    ## (unlike a playlist entry, which plays a cut), so a producer shared
    ## between the main playlist and a transition track breaks playback —
    ## every use gets its own copy, matching what Shotcut itself writes.
    let src = clip.src[]
    let effectGroup = tl.effects[clip.effects]
    let inTc = tc(clip.offset)
    let outTc = tc(clip.offset + clip.dur - 1)

    # Calculate combined speed from all speed/varispeed effects
    var speedVal = 1.0
    var lastSpeedWasVarispeed = false
    for effect in effectGroup:
      if effect.kind == actSpeed:
        speedVal *= effect.val
        lastSpeedWasVarispeed = false
      elif effect.kind == actVarispeed:
        speedVal *= effect.val
        lastSpeedWasVarispeed = true

    var node: XmlNode
    if speedVal != 1.0:
      # Create producer with timewarp for speed effects
      node = newElement("producer")
      node.attrs = {"id": id, "out": tc(srcEnd - 1)}.toXmlAttributes()
      node.addProp("length", tc(srcEnd))
      node.addProp("eof", "pause")
      node.addProp("resource", &"{speedVal}:{src}")
      node.addProp("warp_speed", $speedVal)
      node.addProp("warp_resource", src)
      node.addProp("mlt_service", "timewarp")
      node.addProp("shotcut:producer", "avformat")
      if not lastSpeedWasVarispeed:
        node.addProp("warp_pitch", "1")
      node.addProp("shotcut:caption", &"{agSplitFile(src).name} ({speedVal}x)")
    else:
      # Create chain without speed effects
      node = newElement("chain")
      node.attrs = {"id": id, "out": tc(srcEnd - 1)}.toXmlAttributes()
      node.addProp("length", tc(srcEnd))
      node.addProp("eof", "pause")
      node.addProp("resource", src)
      node.addProp("mlt_service", "avformat")
      node.addProp("caption", agSplitFile(src).name)

    node.addActionFilters(effectGroup, int(clip.dur), tb.float, inTc, outTc)
    node.addFadeFilters(clip, fadeInDur, fadeOutDur)
    mlt.add(node)

  for i, clip in layer:
    let tagName = &"chain{i}"
    addSourceProducer(tagName, clip, clip.offset + clip.dur + plans[i].postroll,
      plans[i].fadeInDur, plans[i].fadeOutDur)
    clipTagNames.add(tagName)

  # Sub-tractors for centered dissolves. Defined after the chains they play
  # because the MLT XML parser cannot resolve forward references.
  var transitionTags = newSeq[string](layer.len)
  for i, clip in layer:
    if plans[i].outCenter == -1: continue
    let t = transitions[plans[i].outCenter]
    let h = t.dur div 2
    let h2 = t.dur - h
    let next = layer[i + 1]

    let tag = &"transition{i}"
    transitionTags[i] = tag
    let tagA = tag & "a"
    let tagB = tag & "b"
    addSourceProducer(tagA, clip, clip.offset + clip.dur + plans[i].postroll, 0, 0)
    addSourceProducer(tagB, next, next.offset + next.dur, 0, 0)

    let tr = newElement("tractor")
    tr.attrs = {"id": tag, "in": "00:00:00.000",
      "out": tc(t.dur - 1)}.toXmlAttributes()
    tr.addProp("shotcut:transition", "lumaMix")

    var track = newElement("track")
    track.attrs = {"producer": tagA,
      "in": tc(clip.offset + clip.dur - h),
      "out": tc(clip.offset + clip.dur + h2 - 1)}.toXmlAttributes()
    tr.add(track)
    track = newElement("track")
    track.attrs = {"producer": tagB,
      "in": tc(next.offset - h),
      "out": tc(next.offset + h2 - 1)}.toXmlAttributes()
    tr.add(track)

    # Frames inside the sub-tractor carry 0-based positions. A transition
    # without explicit in/out computes its progress against the b-producer's
    # full source range instead, which breaks the fade ramp.
    let trIo = {"in": "00:00:00.000", "out": tc(t.dur - 1)}.toXmlAttributes()
    if tl.v.len > 0:
      let luma = newElement("transition")
      luma.attrs = trIo
      luma.addProp("a_track", "0")
      luma.addProp("b_track", "1")
      luma.addProp("factory", "loader")
      luma.addProp("mlt_service", "luma")
      tr.add(luma)
    if tl.a.len > 0:
      let mix = newElement("transition")
      mix.attrs = trIo
      mix.addProp("a_track", "0")
      mix.addProp("b_track", "1")
      mix.addProp("start", "-1")
      mix.addProp("accepts_blanks", "1")
      mix.addProp("mlt_service", "mix")
      tr.add(mix)
    mlt.add(tr)

  let main_playlist = newElement("playlist")
  main_playlist.attrs = {"id": "playlist0"}.toXmlAttributes()
  main_playlist.addProp("shotcut:video", "1")
  main_playlist.addProp("shotcut:name", "V1")

  for i, clip in layer:
    if plans[i].entryOut >= plans[i].entryIn:
      let playlist_entry = newElement("entry")
      playlist_entry.attrs = {
        "producer": clipTagNames[i],
        "in": tc(plans[i].entryIn),
        "out": tc(plans[i].entryOut)
      }.toXmlAttributes()
      main_playlist.add(playlist_entry)

    if plans[i].outCenter != -1:
      let t = transitions[plans[i].outCenter]
      let trEntry = newElement("entry")
      trEntry.attrs = {
        "producer": transitionTags[i],
        "in": "00:00:00.000",
        "out": tc(t.dur - 1)
      }.toXmlAttributes()
      main_playlist.add(trEntry)

  mlt.add(main_playlist)

  let tractor = newElement("tractor")
  tractor.attrs = {
    "id": "tractor0",
    "in": "00:00:00.000",
    "out": global_last
  }.toXmlAttributes()

  tractor.addProp("shotcut", "1")
  tractor.addProp("shotcut:projectAudioChannels", "2")

  let bg_track = newElement("track")
  bg_track.attrs = {"producer": "background"}.toXmlAttributes()
  tractor.add(bg_track)

  let main_track = newElement("track")
  main_track.attrs = {"producer": "playlist0"}.toXmlAttributes()
  tractor.add(main_track)

  mlt.add(tractor)

  if output == "-":
    echo $mlt
  else:
    let xmlStr = "<?xml version='1.0' encoding='utf-8'?>\n" & $mlt
    writeFile(output, xmlStr)
