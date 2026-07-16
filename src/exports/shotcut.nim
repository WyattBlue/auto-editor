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

  var chains = 0
  var clipTagNames: seq[string] = @[]

  var layer: seq[Clip]
  if tl.v.len > 0:
    layer = tl.v[0]
  elif tl.a.len > 0:
    layer = tl.a[0]

  for clip in layer:
    let src = clip.src[]
    let length = to_timecode(float((clip.offset + clip.dur) / tb), Code.standard)
    let lastFrame = to_timecode(float((clip.offset + clip.dur - 1) / tb), Code.standard)

    let effectGroup = tl.effects[clip.effects]
    let inTc = to_timecode(float(clip.offset / tb), Code.standard)
    let outTc = to_timecode(float((clip.offset + clip.dur - 1) / tb), Code.standard)

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

    let tagName = &"chain{chains}"
    inc chains

    if speedVal != 1.0:
      # Create producer with timewarp for speed effects
      let producer = newElement("producer")
      producer.attrs = {"id": tagName, "out": lastFrame}.toXmlAttributes()
      producer.addProp("length", length)
      producer.addProp("eof", "pause")
      producer.addProp("resource", &"{speedVal}:{src}")
      producer.addProp("warp_speed", $speedVal)
      producer.addProp("warp_resource", src)
      producer.addProp("mlt_service", "timewarp")
      producer.addProp("shotcut:producer", "avformat")
      if not lastSpeedWasVarispeed:
        producer.addProp("warp_pitch", "1")
      producer.addProp("shotcut:caption", &"{agSplitFile(src).name} ({speedVal}x)")

      producer.addActionFilters(effectGroup, int(clip.dur), tb.float, inTc, outTc)

      mlt.add(producer)
    else:
      # Create chain without speed effects
      let chain = newElement("chain")
      chain.attrs = {"id": tagName, "out": lastFrame}.toXmlAttributes()
      chain.addProp("length", length)
      chain.addProp("eof", "pause")
      chain.addProp("resource", src)
      chain.addProp("mlt_service", "avformat")
      chain.addProp("caption", agSplitFile(src).name)

      chain.addActionFilters(effectGroup, int(clip.dur), tb.float, inTc, outTc)

      mlt.add(chain)

    clipTagNames.add(tagName)

  let main_playlist = newElement("playlist")
  main_playlist.attrs = {"id": "playlist0"}.toXmlAttributes()
  main_playlist.addProp("shotcut:video", "1")
  main_playlist.addProp("shotcut:name", "V1")

  for i, clip in layer:
    let in_time = to_timecode(float(clip.offset / tb), Code.standard)
    let out_time = to_timecode(float((clip.offset + clip.dur - 1) / tb), Code.standard)

    let playlist_entry = newElement("entry")
    playlist_entry.attrs = {
      "producer": clipTagNames[i],
      "in": in_time,
      "out": out_time
    }.toXmlAttributes()
    main_playlist.add(playlist_entry)

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
