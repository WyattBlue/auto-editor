import std/xmltree
import std/strformat
import std/tables
import std/sets
import std/os

from std/math import ceil

import ../media
import ../timeline
import ../ffmpeg

#[
Premiere Pro uses the Final Cut Pro 7 XML Interchange Format

See docs here:
https://developer.apple.com/library/archive/documentation/AppleApplications/Reference/FinalCutPro_XML/Elements/Elements.html

Also, Premiere itself will happily output subtlety incorrect XML files that don't
come back the way they started.
]#

const DEPTH = "16"


func set_tb_ntsc(tb: AVRational): (int64, string) =
  # See chart: https://developer.apple.com/library/archive/documentation/AppleApplications/Reference/FinalCutPro_XML/FrameRate/FrameRate.html#//apple_ref/doc/uid/TP30001158-TPXREF103
  if tb == AVRational(num: 24000, den: 1001):
    return (24'i64, "TRUE")
  if tb == AVRational(num: 30000, den: 1001):
    return (30'i64, "TRUE")
  if tb == AVRational(num: 60000, den: 1001):
    return (60'i64, "TRUE")

  var ctb = int64(ceil(tb.float64))
  if ctb notin [24, 30, 60] and tb == ctb * AVRational(num: 999, den: 1000):
    return (ctb, "TRUE")

  return (tb.int64, "FALSE")


proc elem(tag, text: string): XmlNode =
  let e = newElement(tag)
  e.add newText(text)
  return e

proc param(id, name, value: string, min = "", max = ""): XmlNode =
  let p = <>parameter(authoringApp = "PremierePro")
  p.add elem("parameterid", id)
  p.add elem("name", name)
  if min != "": p.add elem("valuemin", min)
  if max != "": p.add elem("valuemax", max)
  p.add elem("value", value)
  return p

proc speedup(speed: float): XmlNode =
  let fil = newElement("filter")
  let effect = newElement("effect")
  effect.add elem("name", "Time Remap")
  effect.add elem("effectid", "timeremap")
  effect.add param("variablespeed", "variablespeed", "0", "0", "1")
  effect.add param("speed", "speed", $speed, "-100000", "100000")
  effect.add param("frameblending", "frameblending", "FALSE")
  fil.add effect

  return fil


proc media_def(filedef: XmlNode, url: string, mi: MediaInfo, tl: v3, tb: int64,
    ntsc: string) =
  filedef.add elem("name", mi.path.splitFile.name)
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

  # DaVinci Resolve needs this tag even though it's blank
  filedef.add elem("duration", "")

  let mediadef = newElement("media")

  if mi.v.len > 0:
    let videodef = newElement("video")
    let vschar = newElement("samplecharacteristics")
    let rate3 = newElement("rate")
    rate3.add elem("timebase", $tb)
    rate3.add elem("ntsc", ntsc)
    vschar.add rate3
    vschar.add elem("width", $tl.res[0])
    vschar.add elem("height", $tl.res[1])
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

proc resolve_write_audio(audio: XmlNode, make_filedef: proc(clipitem: XmlNode,
    mi: MediaInfo), tl: v3) =
  for t, alayer in tl.a.pairs:
    let track = newElement("track")
    for j, aclip in alayer.c.pairs:
      let mi = initMediaInfo(aclip.src[])

      let start_val = $aclip.start
      let end_val = $(aclip.start + aclip.dur)
      let in_val = $aclip.offset
      let out_val = $(aclip.offset + aclip.dur)

      let clip_item_num = if mi.v.len == 0: j + 1 else: alayer.c.len + 1 + j

      let clipitem = newElement("clipitem")
      clipitem.attrs = {"id": &"clipitem-{clip_item_num}"}.toXmlAttributes
      clipitem.add elem("name", mi.path.splitFile.name)
      clipitem.add elem("start", start_val)
      clipitem.add elem("end", end_val)
      clipitem.add elem("enabled", "TRUE")
      clipitem.add elem("in", in_val)
      clipitem.add elem("out", out_val)

      make_filedef(clipitem, mi)

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
        link2.add elem("linkclipref", &"clipitem-{clip_item_num}")
        clipitem.add link2

      if aclip.speed != 1:
        clipitem.add speedup(aclip.speed * 100)

      track.add clipitem
    audio.add track

proc premiere_write_audio(audio: XmlNode, make_filedef: proc(clipitem: XmlNode,
    mi: MediaInfo), tl: v3) =
  audio.add elem("numOutputChannels", "2")
  let aformat = newElement("format")
  let aschar = newElement("samplecharacteristics")
  aschar.add elem("depth", DEPTH)
  aschar.add elem("samplerate", $tl.sr)
  aformat.add aschar
  audio.add aformat

  let has_video = tl.v.len > 0 and tl.v[0].len > 0
  var t = 0
  for alayer in tl.a:
    for channelcount in 0..1: # Because "stereo" is hardcoded
      t += 1
      let track = newElement("track")
      track.attrs = {
        "currentExplodedTrackIndex": $channelcount,
        "totalExplodedTrackCount": "2", # Because "stereo" is hardcoded
        "premiereTrackType": "Stereo"
      }.toXmlAttributes

      if has_video:
        track.add elem("outputchannelindex", $(channelcount + 1))

      for j, aclip in alayer.c.pairs:
        let src = initMediaInfo(aclip.src[])

        let start_val = $aclip.start
        let end_val = $(aclip.start + aclip.dur)
        let in_val = $aclip.offset
        let out_val = $(aclip.offset + aclip.dur)

        let clip_item_num = if not has_video: j + 1 else: alayer.len + 1 + j + (
            t * alayer.len)

        let clipitem = newElement("clipitem")
        clipitem.attrs = {
          "id": &"clipitem-{clip_item_num}",
          "premiereChannelType": "stereo"
        }.toXmlAttributes
        clipitem.add elem("name", src.path.splitFile.name)
        clipitem.add elem("enabled", "TRUE")
        clipitem.add elem("start", start_val)
        clipitem.add elem("end", end_val)
        clipitem.add elem("in", in_val)
        clipitem.add elem("out", out_val)

        make_filedef(clipitem, src)

        let sourcetrack = newElement("sourcetrack")
        sourcetrack.add elem("mediatype", "audio")
        sourcetrack.add elem("trackindex", $t)
        clipitem.add sourcetrack

        let labels = newElement("labels")
        labels.add elem("label2", "Iris")
        clipitem.add labels

        if aclip.speed != 1:
          clipitem.add speedup(aclip.speed * 100)

        track.add clipitem
      audio.add track

proc fcp7_write_xml*(name: string, output: string, resolve: bool, tl: v3) =
  let (width, height) = tl.res
  let (timebase, ntsc) = set_tb_ntsc(tl.tb)

  var miToUrl = initTable[MediaInfo, string]()
  var miToId = initTable[MediaInfo, string]()
  var fileDefs = initHashSet[string]() # Contains urls

  var id_counter = 0
  for ptrSrc in tl.uniqueSources:
    id_counter += 1
    let the_id = &"file-{id_counter}"
    let src = ptrSrc[]
    let mi = initMediaInfo(src)
    miToUrl[mi] = $src.absolutePath
    miToId[mi] = the_id

  proc make_filedef(clipitem: XmlNode, mi: MediaInfo) =
    let pathurl = miToUrl[mi]
    let filedef = <>file(id = miToId[mi])
    if pathurl notin fileDefs:
      media_def(filedef, pathurl, mi, tl, timebase, ntsc)
      fileDefs.incl(pathurl)
    clipitem.add filedef

  let xmeml = <>xmeml(version = "5")
  let sequence = (if resolve: <>sequence() else: <>sequence(
      explodedTracks = "true"))

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

  if tl.v.len > 0 and tl.v[0].len > 0:
    let track = newElement("track")

    for j, clip in tl.v[0].c.pairs:
      let start_val = $clip.start
      let end_val = $(clip.start + clip.dur)
      let in_val = $clip.offset
      let out_val = $(clip.offset + clip.dur)

      let this_clipid = &"clipitem-{j + 1}"
      let clipitem = <>clipitem(id = this_clipid)
      clipitem.add elem("name", clip.src[].splitFile.name)
      clipitem.add elem("enabled", "TRUE")
      clipitem.add elem("start", start_val)
      clipitem.add elem("end", end_val)
      clipitem.add elem("in", in_val)
      clipitem.add elem("out", out_val)

      let mi = initMediaInfo(clip.src[])
      make_filedef(clipitem, mi)

      clipitem.add elem("compositemode", "normal")
      if clip.speed != 1:
        clipitem.add speedup(clip.speed * 100)

      if resolve:
        let link1 = newElement("link")
        link1.add elem("linkclipref", this_clipid)
        clipitem.add link1
        let link2 = newElement("link")
        link2.add elem("linkclipref", &"clipitem-{tl.v[0].len + j + 1}")
        clipitem.add link2
      else:
        for i in 0..<(1 + mi.a.len * 2): # `2` because stereo
          let link = newElement("link")
          link.add elem("linkclipref", &"clipitem-{(i * tl.v[0].len) + j + 1}")
          link.add elem("mediatype", if i == 0: "video" else: "audio")
          link.add elem("trackindex", $max(i, 1))
          link.add elem("clipindex", $(j + 1))
          clipitem.add link

      track.add clipitem
    video.add track

  media.add video

  # Audio definitions and clips
  let audio = newElement("audio")
  if resolve:
    resolve_write_audio(audio, make_filedef, tl)
  else:
    premiere_write_audio(audio, make_filedef, tl)

  media.add audio
  sequence.add media
  xmeml.add sequence

  if output == "-":
    echo $xmeml
  else:
    let xmlStr = "<?xml version='1.0' encoding='utf-8'?>\n" & $xmeml
    writeFile(output, xmlStr)
