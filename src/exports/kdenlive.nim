import std/[json, os, tables, strformat, xmltree, sysrand, strutils]
import ../timeline
import ../util/fun
import ../log

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
    clips = tl.v[0].clips
  elif tl.a.len > 0:
    clips = tl.a[0].clips
  else:
    clips = @[]

  var sourceIds = initTable[string, string]()
  var sourceId = 4
  var clipPlaylists: seq[XmlNode] = @[]
  var chains = 0
  var playlists = 0
  var producers = 1
  let aChannels = tl.a.len
  let vChannels = tl.v.len
  var warpedClips: seq[int] = @[]

  for i, clip in clips:
    if clip.speed != 1.0:
      warpedClips.add(i)

  # create all producers for warped clips
  for clipIdx in warpedClips:
    for i in 0 ..< (aChannels + vChannels):
      let clip = clips[clipIdx]
      let path = $clip.src[]

      if path notin sourceIds:
        sourceIds[path] = $sourceId
        inc sourceId

      let prod = newElement("producer")
      prod.attrs = {
        "id": &"producer{producers}",
        "in": "00:00:00.000",
        "out": globalOut
      }.toXmlAttributes()

      var prodProp = newElement("property")
      prodProp.attrs = {"name": "resource"}.toXmlAttributes()
      prodProp.add(newText(&"{clip.speed}:{path}"))
      prod.add(prodProp)

      prodProp = newElement("property")
      prodProp.attrs = {"name": "warp_speed"}.toXmlAttributes()
      prodProp.add(newText($clip.speed))
      prod.add(prodProp)

      prodProp = newElement("property")
      prodProp.attrs = {"name": "warp_resource"}.toXmlAttributes()
      prodProp.add(newText(path))
      prod.add(prodProp)

      prodProp = newElement("property")
      prodProp.attrs = {"name": "warp_pitch"}.toXmlAttributes()
      prodProp.add(newText("0"))
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
    let path = $audio.clips[0].src[]

    if path notin sourceIds:
      sourceIds[path] = $sourceId
      inc sourceId

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
      "id": &"tractor{chains}",
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
    inc chains

  # create chains, playlists and tractors for video channels
  for i, video in tl.v:
    let path = $video.clips[0].src[]

    if path notin sourceIds:
      sourceIds[path] = $sourceId
      inc sourceId

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

    for _ in 0 ..< 2:
      let playlist = newElement("playlist")
      playlist.attrs = {"id": &"playlist{playlists}"}.toXmlAttributes()
      clipPlaylists.add(playlist)
      mlt.add(playlist)
      inc playlists

    let tractor = newElement("tractor")
    tractor.attrs = {
      "id": &"tractor{chains}",
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
    inc chains

  # final chain for the project bin
  if clips.len > 0:
    let path = $clips[0].src[]
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

  var groups: seq[JsonNode] = @[]
  var groupCounter = 0
  producers = 1

  for clip in clips:
    var groupChildren: seq[JsonNode] = @[]
    let `in` = toTimecode((clip.offset.float / tb.float), standard)
    let `out` = toTimecode(((clip.offset + clip.dur).float / tb.float), standard)
    let path = $clip.src[]

    for i, playlist in clipPlaylists:
      if i mod 2 == 0:
        groupChildren.add(%*{
          "data": &"{i div 2}:{clip.start + groupCounter}",
          "leaf": "clip",
          "type": "Leaf"
        })
        var clipProd = ""

        if clip.speed == 1.0:
          clipProd = &"chain{i div 2}"
        else:
          clipProd = &"producer{producers}"
          inc producers

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

        playlist.add(entry)

    groups.add(%*{"children": groupChildren, "type": "Normal"})
    inc groupCounter

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

  for i in 0 ..< chains:
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

  binEntry = newElement("entry")
  binEntry.attrs = {
    "producer": &"chain{chains}",
    "in": "00:00:00.000"
  }.toXmlAttributes()
  playlistBin.add(binEntry)

  mlt.add(playlistBin)

  # reserved last tractor for project
  let tractor = newElement("tractor")
  tractor.attrs = {
    "id": &"tractor{chains}",
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
