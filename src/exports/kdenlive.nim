import std/[json, os, tables, strformat, xmltree, sysrand, strutils]
from std/math import log10
import ../[action, media, timeline]
import ../util/[color, fun]

proc addProp(parent: XmlNode, name, value: string) =
  let prop = newElement("property")
  prop.attrs = {"name": name}.toXmlAttributes()
  prop.add(newText(value))
  parent.add(prop)

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

proc kdenliveWrite*(output: string, tl: v3) =
  let mlt = newElement("mlt")
  mlt.attrs = {
    "LC_NUMERIC": "C",
    "version": "7.22.0",
    "producer": "main_bin",
    "root": getCurrentDir()
  }.toXmlAttributes()

  let (width, height) = tl.res
  let (num, den) = aspectRatio(width, height)
  let tb = tl.tb
  let seqUuid = genUuid()

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

  # Reserved producer0
  let globalOut = toTimecode(tl.len.float / tb.float, standard)
  let producer = newElement("producer")
  producer.attrs = {"id": "producer0"}.toXmlAttributes()

  var prop = newElement("property")
  prop.attrs = {"name": "length"}.toXmlAttributes()
  prop.add(newText(globalOut))
  producer.add(prop)

  prop = newElement("property")
  prop.attrs = {"name": "eof"}.toXmlAttributes()
  prop.add(newText("continue"))
  producer.add(prop)

  prop = newElement("property")
  prop.attrs = {"name": "resource"}.toXmlAttributes()
  prop.add(newText("black"))
  producer.add(prop)

  prop = newElement("property")
  prop.attrs = {"name": "mlt_service"}.toXmlAttributes()
  prop.add(newText("color"))
  producer.add(prop)

  prop = newElement("property")
  prop.attrs = {"name": "kdenlive:playlistid"}.toXmlAttributes()
  prop.add(newText("black_track"))
  producer.add(prop)

  prop = newElement("property")
  prop.attrs = {"name": "mlt_image_format"}.toXmlAttributes()
  prop.add(newText("rgba"))
  producer.add(prop)

  prop = newElement("property")
  prop.attrs = {"name": "aspect_ratio"}.toXmlAttributes()
  prop.add(newText("1"))
  producer.add(prop)

  mlt.add(producer)

  # Get all clips
  var clips: seq[Clip]
  if tl.v.len > 0:
    clips = tl.v[0]
  elif tl.a.len > 0:
    clips = tl.a[0]
  else:
    clips = @[]

  # Collect unique source paths in order of first appearance
  var uniquePaths: seq[string] = @[]
  for clip in clips:
    let p = $clip.src[]
    if p notin uniquePaths:
      uniquePaths.add(p)

  var sourceIds = initTable[string, string]()
  var pathDuration = initTable[string, float64]()
  var sourceId = 4
  for path in uniquePaths:
    sourceIds[path] = $sourceId
    pathDuration[path] = initMediaInfo(path).duration
    inc sourceId

  var clipPlaylists: seq[XmlNode] = @[]
  var chains = 0
  var playlists = 0
  var producers = 1
  let aChannels = tl.a.len
  let vChannels = tl.v.len
  var warpedClips: seq[int] = @[]

  # Map (channel, source path) -> chain id, per-track type
  var audioChainOf = initTable[(int, string), int]()
  var videoChainOf = initTable[(int, string), int]()
  var binChainOf = initTable[string, int]()

  for i, clip in clips:
    let effectGroup = tl.effects[clip.effects]
    for effect in effectGroup:
      if effect.kind in [actSpeed, actVarispeed]:
        warpedClips.add(i)
        break

  # create all producers for warped clips
  for clipIdx in warpedClips:
    for i in 0 ..< (aChannels + vChannels):
      let clip = clips[clipIdx]
      let path = $clip.src[]

      let effectGroup = tl.effects[clip.effects]
      var speedVal = 1.0
      var warpPitch = false
      for effect in effectGroup:
        if effect.kind == actSpeed or effect.kind == actVarispeed:
          speedVal = effect.val
          warpPitch = effect.kind == actSpeed
          break

      let prod = newElement("producer")
      prod.attrs = {
        "id": &"producer{producers}",
        "in": "00:00:00.000",
        # A timewarp producer is as long as the warped source, not the
        # timeline; clamping to timeline length freezes any clip whose warped
        # source position lies past it.
        "out": toTimecode(pathDuration[path] / speedVal, standard)
      }.toXmlAttributes()

      var prodProp = newElement("property")
      prodProp.attrs = {"name": "resource"}.toXmlAttributes()
      prodProp.add(newText(&"{speedVal}:{path}"))
      prod.add(prodProp)

      prodProp = newElement("property")
      prodProp.attrs = {"name": "warp_speed"}.toXmlAttributes()
      prodProp.add(newText($speedVal))
      prod.add(prodProp)

      prodProp = newElement("property")
      prodProp.attrs = {"name": "warp_resource"}.toXmlAttributes()
      prodProp.add(newText(path))
      prod.add(prodProp)

      prodProp = newElement("property")
      prodProp.attrs = {"name": "warp_pitch"}.toXmlAttributes()
      prodProp.add(newText(if warpPitch: "1" else: "0"))
      prod.add(prodProp)

      prodProp = newElement("property")
      prodProp.attrs = {"name": "mlt_service"}.toXmlAttributes()
      prodProp.add(newText("timewarp"))
      prod.add(prodProp)

      prodProp = newElement("property")
      prodProp.attrs = {"name": "kdenlive:id"}.toXmlAttributes()
      prodProp.add(newText(sourceIds[path]))
      prod.add(prodProp)

      if i < aChannels:
        prodProp = newElement("property")
        prodProp.attrs = {"name": "vstream"}.toXmlAttributes()
        prodProp.add(newText("0"))
        prod.add(prodProp)

        prodProp = newElement("property")
        prodProp.attrs = {"name": "astream"}.toXmlAttributes()
        prodProp.add(newText($(aChannels - 1 - i)))
        prod.add(prodProp)

        prodProp = newElement("property")
        prodProp.attrs = {"name": "set.test_audio"}.toXmlAttributes()
        prodProp.add(newText("0"))
        prod.add(prodProp)

        prodProp = newElement("property")
        prodProp.attrs = {"name": "set.test_video"}.toXmlAttributes()
        prodProp.add(newText("1"))
        prod.add(prodProp)
      else:
        prodProp = newElement("property")
        prodProp.attrs = {"name": "vstream"}.toXmlAttributes()
        prodProp.add(newText($(vChannels - 1 - (i - aChannels))))
        prod.add(prodProp)

        prodProp = newElement("property")
        prodProp.attrs = {"name": "astream"}.toXmlAttributes()
        prodProp.add(newText("0"))
        prod.add(prodProp)

        prodProp = newElement("property")
        prodProp.attrs = {"name": "set.test_audio"}.toXmlAttributes()
        prodProp.add(newText("1"))
        prod.add(prodProp)

        prodProp = newElement("property")
        prodProp.attrs = {"name": "set.test_video"}.toXmlAttributes()
        prodProp.add(newText("0"))
        prod.add(prodProp)

      mlt.add(prod)
      inc producers

  # create chains, playlists and tractors for audio channels
  for i, audio in tl.a:
    for path in uniquePaths:
      audioChainOf[(i, path)] = chains
      let chain = newElement("chain")
      chain.attrs = {"id": &"chain{chains}"}.toXmlAttributes()

      var chainProp = newElement("property")
      chainProp.attrs = {"name": "resource"}.toXmlAttributes()
      chainProp.add(newText(path))
      chain.add(chainProp)

      chainProp = newElement("property")
      chainProp.attrs = {"name": "mlt_service"}.toXmlAttributes()
      chainProp.add(newText("avformat-novalidate"))
      chain.add(chainProp)

      chainProp = newElement("property")
      chainProp.attrs = {"name": "vstream"}.toXmlAttributes()
      chainProp.add(newText("0"))
      chain.add(chainProp)

      chainProp = newElement("property")
      chainProp.attrs = {"name": "astream"}.toXmlAttributes()
      chainProp.add(newText($(aChannels - 1 - i)))
      chain.add(chainProp)

      chainProp = newElement("property")
      chainProp.attrs = {"name": "set.test_audio"}.toXmlAttributes()
      chainProp.add(newText("0"))
      chain.add(chainProp)

      chainProp = newElement("property")
      chainProp.attrs = {"name": "set.test_video"}.toXmlAttributes()
      chainProp.add(newText("1"))
      chain.add(chainProp)

      chainProp = newElement("property")
      chainProp.attrs = {"name": "kdenlive:id"}.toXmlAttributes()
      chainProp.add(newText(sourceIds[path]))
      chain.add(chainProp)

      mlt.add(chain)
      inc chains

    for _ in 0 ..< 2:
      let playlist = newElement("playlist")
      playlist.attrs = {"id": &"playlist{playlists}"}.toXmlAttributes()
      clipPlaylists.add(playlist)

      var playlistProp = newElement("property")
      playlistProp.attrs = {"name": "kdenlive:audio_track"}.toXmlAttributes()
      playlistProp.add(newText("1"))
      playlist.add(playlistProp)

      mlt.add(playlist)
      inc playlists

    let tractor = newElement("tractor")
    tractor.attrs = {
      "id": &"tractor{i}",
      "in": "00:00:00.000",
      "out": globalOut
    }.toXmlAttributes()

    var tractorProp = newElement("property")
    tractorProp.attrs = {"name": "kdenlive:audio_track"}.toXmlAttributes()
    tractorProp.add(newText("1"))
    tractor.add(tractorProp)

    tractorProp = newElement("property")
    tractorProp.attrs = {"name": "kdenlive:timeline_active"}.toXmlAttributes()
    tractorProp.add(newText("1"))
    tractor.add(tractorProp)

    tractorProp = newElement("property")
    tractorProp.attrs = {"name": "kdenlive:audio_rec"}.toXmlAttributes()
    tractor.add(tractorProp)

    var track = newElement("track")
    track.attrs = {"hide": "video", "producer": &"playlist{playlists - 2}"}.toXmlAttributes()
    tractor.add(track)

    track = newElement("track")
    track.attrs = {"hide": "video", "producer": &"playlist{playlists - 1}"}.toXmlAttributes()
    tractor.add(track)

    mlt.add(tractor)

  # create chains, playlists and tractors for video channels
  for i, video in tl.v:
    for path in uniquePaths:
      videoChainOf[(i, path)] = chains
      let chain = newElement("chain")
      chain.attrs = {"id": &"chain{chains}"}.toXmlAttributes()

      var chainProp = newElement("property")
      chainProp.attrs = {"name": "resource"}.toXmlAttributes()
      chainProp.add(newText(path))
      chain.add(chainProp)

      chainProp = newElement("property")
      chainProp.attrs = {"name": "mlt_service"}.toXmlAttributes()
      chainProp.add(newText("avformat-novalidate"))
      chain.add(chainProp)

      chainProp = newElement("property")
      chainProp.attrs = {"name": "vstream"}.toXmlAttributes()
      chainProp.add(newText($(vChannels - 1 - i)))
      chain.add(chainProp)

      chainProp = newElement("property")
      chainProp.attrs = {"name": "astream"}.toXmlAttributes()
      chainProp.add(newText("0"))
      chain.add(chainProp)

      chainProp = newElement("property")
      chainProp.attrs = {"name": "set.test_audio"}.toXmlAttributes()
      chainProp.add(newText("1"))
      chain.add(chainProp)

      chainProp = newElement("property")
      chainProp.attrs = {"name": "set.test_video"}.toXmlAttributes()
      chainProp.add(newText("0"))
      chain.add(chainProp)

      chainProp = newElement("property")
      chainProp.attrs = {"name": "kdenlive:id"}.toXmlAttributes()
      chainProp.add(newText(sourceIds[path]))
      chain.add(chainProp)

      mlt.add(chain)
      inc chains

    for _ in 0 ..< 2:
      let playlist = newElement("playlist")
      playlist.attrs = {"id": &"playlist{playlists}"}.toXmlAttributes()
      clipPlaylists.add(playlist)
      mlt.add(playlist)
      inc playlists

    let tractor = newElement("tractor")
    tractor.attrs = {
      "id": &"tractor{aChannels + i}",
      "in": "00:00:00.000",
      "out": globalOut
    }.toXmlAttributes()

    var tractorProp = newElement("property")
    tractorProp.attrs = {"name": "kdenlive:timeline_active"}.toXmlAttributes()
    tractorProp.add(newText("1"))
    tractor.add(tractorProp)

    var track = newElement("track")
    track.attrs = {"hide": "audio", "producer": &"playlist{playlists - 2}"}.toXmlAttributes()
    tractor.add(track)

    track = newElement("track")
    track.attrs = {"hide": "audio", "producer": &"playlist{playlists - 1}"}.toXmlAttributes()
    tractor.add(track)

    mlt.add(tractor)

  # final chain for the project bin (one per unique source)
  for path in uniquePaths:
    binChainOf[path] = chains
    let chain = newElement("chain")
    chain.attrs = {"id": &"chain{chains}"}.toXmlAttributes()

    var chainProp = newElement("property")
    chainProp.attrs = {"name": "resource"}.toXmlAttributes()
    chainProp.add(newText(path))
    chain.add(chainProp)

    chainProp = newElement("property")
    chainProp.attrs = {"name": "mlt_service"}.toXmlAttributes()
    chainProp.add(newText("avformat-novalidate"))
    chain.add(chainProp)

    chainProp = newElement("property")
    chainProp.attrs = {"name": "audio_index"}.toXmlAttributes()
    chainProp.add(newText("1"))
    chain.add(chainProp)

    chainProp = newElement("property")
    chainProp.attrs = {"name": "video_index"}.toXmlAttributes()
    chainProp.add(newText("0"))
    chain.add(chainProp)

    chainProp = newElement("property")
    chainProp.attrs = {"name": "vstream"}.toXmlAttributes()
    chainProp.add(newText("0"))
    chain.add(chainProp)

    chainProp = newElement("property")
    chainProp.attrs = {"name": "astream"}.toXmlAttributes()
    chainProp.add(newText("0"))
    chain.add(chainProp)

    chainProp = newElement("property")
    chainProp.attrs = {"name": "kdenlive:id"}.toXmlAttributes()
    chainProp.add(newText(sourceIds[path]))
    chain.add(chainProp)

    mlt.add(chain)
    inc chains

  var groups: seq[JsonNode] = @[]
  producers = 1
  var filterId = 0

  proc addFilter(parent: XmlNode, service: string,
      params: openArray[(string, string)] = []) =
    let filter = newElement("filter")
    filter.attrs = {"id": &"filter{filterId}"}.toXmlAttributes()
    inc filterId
    filter.addProp("mlt_service", service)
    filter.addProp("kdenlive_id", service)
    filter.addProp("kdenlive:collapsed", "0")
    for (name, value) in params:
      filter.addProp(name, value)
    parent.add(filter)

  proc addAudioEffects(parent: XmlNode, effects: Actions) =
    for effect in effects:
      case effect.kind
      of actVolume:
        if effect.kf.len > 0:
          let gain = effect.kf[0].float64
          let db = (if gain <= 0.0: -100.0 else: max(-100.0, 20.0 * log10(gain)))
          parent.addFilter("volume", [("level", $db)])
      of actDeesser:
        parent.addFilter("avfilter.deesser", [
          ("av.i", $effect.intensity), ("av.m", $effect.maxd),
          ("av.f", $effect.freq), ("av.s", "o")])
      else: discard

  proc addVideoEffects(parent: XmlNode, effects: Actions) =
    for effect in effects:
      case effect.kind
      of actInvert: parent.addFilter("avfilter.negate")
      of actHflip: parent.addFilter("avfilter.hflip")
      of actVflip: parent.addFilter("avfilter.vflip")
      of actErosion: parent.addFilter("avfilter.erosion")
      of actBlur:
        if effect.kf.len > 0:
          let sigma = $effect.kf[0]
          parent.addFilter("avfilter.gblur", [
            ("av.sigma", sigma), ("av.sigmaV", sigma),
            ("av.steps", "1"), ("av.planes", "7")])
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
        let rect = &"{effect.dbX} {effect.dbY} {effect.dbW} {effect.dbH}"
        parent.addFilter("avfilter.drawbox", [
          ("kdenlive:fakerect", rect), ("av.x", $effect.dbX),
          ("av.y", $effect.dbY), ("av.w", $effect.dbW),
          ("av.h", $effect.dbH),
          ("av.color", effect.dbColor.toString.replace("#", "0x")),
          # Kdenlive declares thickness as a numeric animated parameter, so its
          # UI rejects FFmpeg's otherwise-valid `fill` token. A thickness at
          # least as large as the box fills it equivalently.
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

  for clip in clips:
    var groupChildren: seq[JsonNode] = @[]
    let `in` = toTimecode((clip.offset.float / tb.float), standard)
    let `out` = toTimecode(((clip.offset + clip.dur - 1).float / tb.float), standard)
    let path = $clip.src[]

    for i, playlist in clipPlaylists:
      if i mod 2 == 0:
        groupChildren.add(%*{
          "data": &"{i div 2}:{clip.start}",
          "leaf": "clip",
          "type": "Leaf"
        })
        var clipProd = ""

        # Must match the warpedClips predicate above, or entry producer
        # numbering drifts out of sync with the created producers.
        let effectGroup = tl.effects[clip.effects]
        var hasSpeed = false
        for effect in effectGroup:
          if effect.kind in [actSpeed, actVarispeed]:
            hasSpeed = true
            break

        if hasSpeed:
          clipProd = &"producer{producers}"
          inc producers
        else:
          let channelIdx = i div 2
          let chainIdx = if channelIdx < aChannels:
                           audioChainOf[(channelIdx, path)]
                         else:
                           videoChainOf[(channelIdx - aChannels, path)]
          clipProd = &"chain{chainIdx}"

        let entry = newElement("entry")
        entry.attrs = {
          "producer": clipProd,
          "in": `in`,
          "out": `out`
        }.toXmlAttributes()

        var entryProp = newElement("property")
        entryProp.attrs = {"name": "kdenlive:id"}.toXmlAttributes()
        entryProp.add(newText(sourceIds[path]))
        entry.add(entryProp)

        let channelIdx = i div 2
        if channelIdx < aChannels:
          entry.addAudioEffects(effectGroup)
        else:
          entry.addVideoEffects(effectGroup)

        playlist.add(entry)

    groups.add(%*{"children": groupChildren, "type": "Normal"})

  # default sequence tractor
  let sequence = newElement("tractor")
  sequence.attrs = {
    "id": &"{{{seqUuid}}}",
    "in": "00:00:00.000",
    "out": "00:00:00.000"
  }.toXmlAttributes()

  var seqProp = newElement("property")
  seqProp.attrs = {"name": "kdenlive:uuid"}.toXmlAttributes()
  seqProp.add(newText(&"{{{seqUuid}}}"))
  sequence.add(seqProp)

  seqProp = newElement("property")
  seqProp.attrs = {"name": "kdenlive:clipname"}.toXmlAttributes()
  seqProp.add(newText("Sequence 1"))
  sequence.add(seqProp)

  seqProp = newElement("property")
  seqProp.attrs = {"name": "kdenlive:sequenceproperties.groups"}.toXmlAttributes()
  seqProp.add(newVerbatimText(pretty(%groups, indent = 4)))
  sequence.add(seqProp)

  var seqTrack = newElement("track")
  seqTrack.attrs = {"producer": "producer0"}.toXmlAttributes()
  sequence.add(seqTrack)

  for i in 0 ..< (aChannels + vChannels):
    seqTrack = newElement("track")
    seqTrack.attrs = {"producer": &"tractor{i}"}.toXmlAttributes()
    sequence.add(seqTrack)

  mlt.add(sequence)

  # main bin
  let playlistBin = newElement("playlist")
  playlistBin.attrs = {"id": "main_bin"}.toXmlAttributes()

  var binProp = newElement("property")
  binProp.attrs = {"name": "kdenlive:docproperties.uuid"}.toXmlAttributes()
  binProp.add(newText(&"{{{seqUuid}}}"))
  playlistBin.add(binProp)

  binProp = newElement("property")
  binProp.attrs = {"name": "kdenlive:docproperties.version"}.toXmlAttributes()
  binProp.add(newText("1.1"))
  playlistBin.add(binProp)

  binProp = newElement("property")
  binProp.attrs = {"name": "xml_retain"}.toXmlAttributes()
  binProp.add(newText("1"))
  playlistBin.add(binProp)

  var binEntry = newElement("entry")
  binEntry.attrs = {
    "producer": &"{{{seqUuid}}}",
    "in": "00:00:00.000",
    "out": "00:00:00.000"
  }.toXmlAttributes()
  playlistBin.add(binEntry)

  for path in uniquePaths:
    binEntry = newElement("entry")
    binEntry.attrs = {
      "producer": &"chain{binChainOf[path]}",
      "in": "00:00:00.000"
    }.toXmlAttributes()
    playlistBin.add(binEntry)

  mlt.add(playlistBin)

  # reserved last tractor for project
  let tractor = newElement("tractor")
  tractor.attrs = {
    "id": &"tractor{aChannels + vChannels}",
    "in": "00:00:00.000",
    "out": globalOut
  }.toXmlAttributes()

  var tractorProp = newElement("property")
  tractorProp.attrs = {"name": "kdenlive:projectTractor"}.toXmlAttributes()
  tractorProp.add(newText("1"))
  tractor.add(tractorProp)

  var tractorTrack = newElement("track")
  tractorTrack.attrs = {
    "producer": &"{{{seqUuid}}}",
    "in": "00:00:00.000",
    "out": globalOut
  }.toXmlAttributes()
  tractor.add(tractorTrack)

  mlt.add(tractor)

  if output == "-":
    echo $mlt
  else:
    let xmlStr = "<?xml version='1.0' encoding='utf-8'?>\n" & $mlt
    writeFile(output, xmlStr)
