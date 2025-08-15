import std/xmltree
import std/strformat
import ../timeline
import ../ffmpeg
import ../log
import ../util/[color, fun]
from std/os import splitFile

#[

Shotcut uses the MLT timeline format

See docs here:
https://mltframework.org/docs/mltxml/

]#


proc shotcut_write_mlt*(output: string, tl: v3) =
  let mlt = newElement("mlt")
  mlt.attrs = {
    "LC_NUMERIC": "C",
    "version": "7.9.0",
    "title": "Shotcut version 22.09.23",
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
  let xml_retain_prop = newElement("property")
  xml_retain_prop.attrs = {"name": "xml_retain"}.toXmlAttributes()
  xml_retain_prop.add(newText("1"))
  playlist_bin.add(xml_retain_prop)
  mlt.add(playlist_bin)

  let global_out = toTimecode(float(tl.len / tl.tb), Code.standard)

  let producer = newElement("producer")
  producer.attrs = {"id": "bg"}.toXmlAttributes()

  let length_prop = newElement("property")
  length_prop.attrs = {"name": "length"}.toXmlAttributes()
  length_prop.add(newText(global_out))
  producer.add(length_prop)

  let eof_prop = newElement("property")
  eof_prop.attrs = {"name": "eof"}.toXmlAttributes()
  eof_prop.add(newText("pause"))
  producer.add(eof_prop)

  let resource_prop = newElement("property")
  resource_prop.attrs = {"name": "resource"}.toXmlAttributes()
  resource_prop.add(newText(tl.background.toString))
  producer.add(resource_prop)

  let service_prop = newElement("property")
  service_prop.attrs = {"name": "mlt_service"}.toXmlAttributes()
  service_prop.add(newText("color"))
  producer.add(service_prop)

  let format_prop = newElement("property")
  format_prop.attrs = {"name": "mlt_image_format"}.toXmlAttributes()
  format_prop.add(newText("rgba"))
  producer.add(format_prop)

  let aspect_prop = newElement("property")
  aspect_prop.attrs = {"name": "aspect_ratio"}.toXmlAttributes()
  aspect_prop.add(newText("1"))
  producer.add(aspect_prop)

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
  var producers = 0

  var layer: ClipLayer
  if tl.v.len > 0:
    layer = tl.v[0]
  elif tl.a.len > 0:
    layer = tl.a[0]

  for clip in layer.clips:
    let src = clip.src[]
    let length = to_timecode(float((clip.offset + clip.dur) / tb), Code.standard)

    var chain: XmlNode
    var resource: string
    var caption: string

    if clip.speed == 1.0:
      resource = src
      caption = splitFile(src).name
      chain = newElement("chain")
      chain.attrs = {
        "id": fmt"chain{chains}",
        "out": length
      }.toXmlAttributes()
    else:
      chain = newElement("producer")
      chain.attrs = {
        "id": fmt"producer{producers}",
        "out": length
      }.toXmlAttributes()
      resource = fmt"{clip.speed}:{src}"
      caption = fmt"{splitFile(src).name} ({clip.speed}x)"
      inc producers

    let chain_length_prop = newElement("property")
    chain_length_prop.attrs = {"name": "length"}.toXmlAttributes()
    chain_length_prop.add(newText(length))
    chain.add(chain_length_prop)

    let chain_resource_prop = newElement("property")
    chain_resource_prop.attrs = {"name": "resource"}.toXmlAttributes()
    chain_resource_prop.add(newText(resource))
    chain.add(chain_resource_prop)

    if clip.speed != 1.0:
      let warp_speed_prop = newElement("property")
      warp_speed_prop.attrs = {"name": "warp_speed"}.toXmlAttributes()
      warp_speed_prop.add(newText($clip.speed))
      chain.add(warp_speed_prop)

      let warp_pitch_prop = newElement("property")
      warp_pitch_prop.attrs = {"name": "warp_pitch"}.toXmlAttributes()
      warp_pitch_prop.add(newText("1"))
      chain.add(warp_pitch_prop)

      let timewarp_service_prop = newElement("property")
      timewarp_service_prop.attrs = {"name": "mlt_service"}.toXmlAttributes()
      timewarp_service_prop.add(newText("timewarp"))
      chain.add(timewarp_service_prop)

    let caption_prop = newElement("property")
    caption_prop.attrs = {"name": "caption"}.toXmlAttributes()
    caption_prop.add(newText(caption))
    chain.add(caption_prop)

    mlt.add(chain)
    inc chains

  let main_playlist = newElement("playlist")
  main_playlist.attrs = {"id": "playlist0"}.toXmlAttributes()

  let video_prop = newElement("property")
  video_prop.attrs = {"name": "shotcut:video"}.toXmlAttributes()
  video_prop.add(newText("1"))
  main_playlist.add(video_prop)

  let name_prop = newElement("property")
  name_prop.attrs = {"name": "shotcut:name"}.toXmlAttributes()
  name_prop.add(newText("V1"))
  main_playlist.add(name_prop)

  producers = 0
  for i, clip in layer.clips:
    let in_time = to_timecode(float(clip.offset / tb), Code.standard)
    let out_time = to_timecode(float((clip.offset + clip.dur) / tb), Code.standard)

    var tag_name = fmt"chain{i}"
    if clip.speed != 1.0:
      tag_name = fmt"producer{producers}"
      inc producers

    let playlist_entry = newElement("entry")
    playlist_entry.attrs = {
      "producer": tag_name,
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

  let shotcut_prop = newElement("property")
  shotcut_prop.attrs = {"name": "shotcut"}.toXmlAttributes()
  shotcut_prop.add(newText("1"))
  tractor.add(shotcut_prop)

  let audio_channels_prop = newElement("property")
  audio_channels_prop.attrs = {"name": "shotcut:projectAudioChannels"}.toXmlAttributes()
  audio_channels_prop.add(newText("2"))
  tractor.add(audio_channels_prop)

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
