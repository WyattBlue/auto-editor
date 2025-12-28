import std/xmltree
import std/strformat
import ../timeline
import ../ffmpeg
import ../log
import ../util/[color, fun]
from std/os import splitFile
from std/math import log10

#[

Shotcut uses the MLT timeline format

See docs here:
https://mltframework.org/docs/mltxml/

]#

proc addProp(parent: XmlNode, name: string, value: string) =
  let prop = newElement("property")
  prop.attrs = {"name": name}.toXmlAttributes()
  prop.add(newText(value))
  parent.add(prop)

proc shotcut_write_mlt*(output: string, tl: v3) =
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

  let playlist_bin = newElement("playlist")
  playlist_bin.attrs = {"id": "main_bin"}.toXmlAttributes()
  playlist_bin.addProp("xml_retain", "1")
  mlt.add(playlist_bin)

  let global_out = toTimecode(float(tl.len / tl.tb), Code.standard)

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
    "out": global_out
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

    let effectGroup = tl.effects[clip.effects]

    # Calculate combined speed from all speed/varispeed effects
    var speedVal = 1.0
    var lastSpeedWasVarispeed = false
    var volumeVal = 1.0
    for effect in effectGroup:
      if effect.kind == actSpeed:
        speedVal *= effect.val
        lastSpeedWasVarispeed = false
      elif effect.kind == actVarispeed:
        speedVal *= effect.val
        lastSpeedWasVarispeed = true
      elif effect.kind == actVolume:
        volumeVal *= effect.val

    let tagName = &"chain{chains}"
    inc chains

    if speedVal != 1.0:
      # Create producer with timewarp for speed effects
      let producer = newElement("producer")
      producer.attrs = {"id": tagName, "out": length}.toXmlAttributes()
      producer.addProp("length", length)
      producer.addProp("eof", "pause")
      producer.addProp("resource", fmt"{speedVal}:{src}")
      producer.addProp("warp_speed", $speedVal)
      producer.addProp("warp_resource", src)
      producer.addProp("mlt_service", "timewarp")
      producer.addProp("shotcut:producer", "avformat")
      if not lastSpeedWasVarispeed:
        producer.addProp("warp_pitch", "1")
      producer.addProp("shotcut:caption", fmt"{splitFile(src).name} ({speedVal}x)")

      # Add volume filter if needed
      if volumeVal != 1.0:
        let filter = newElement("filter")
        let volumeDb = 20.0 * log10(volumeVal)
        filter.addProp("mlt_service", "volume")
        filter.addProp("level", $volumeDb)
        producer.add(filter)

      mlt.add(producer)
    else:
      # Create chain without speed effects
      let chain = newElement("chain")
      chain.attrs = {"id": tagName, "out": length}.toXmlAttributes()
      chain.addProp("length", length)
      chain.addProp("eof", "pause")
      chain.addProp("resource", src)
      chain.addProp("mlt_service", "avformat")
      chain.addProp("caption", splitFile(src).name)

      # Add volume filter if needed
      if volumeVal != 1.0:
        let filter = newElement("filter")
        let volumeDb = 20.0 * log10(volumeVal)
        filter.addProp("mlt_service", "volume")
        filter.addProp("level", $volumeDb)
        chain.add(filter)

      mlt.add(chain)

    clipTagNames.add(tagName)

  let main_playlist = newElement("playlist")
  main_playlist.attrs = {"id": "playlist0"}.toXmlAttributes()
  main_playlist.addProp("shotcut:video", "1")
  main_playlist.addProp("shotcut:name", "V1")

  for i, clip in layer:
    let in_time = to_timecode(float(clip.offset / tb), Code.standard)
    let out_time = to_timecode(float((clip.offset + clip.dur) / tb), Code.standard)

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
    "out": global_out
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
