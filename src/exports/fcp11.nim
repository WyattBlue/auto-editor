import std/os
import std/xmltree
import std/algorithm
import std/[sets, tables]
import std/[strformat, strutils]
from std/math import round

import ../media
import ../log
import ../ffmpeg
import ../timeline

#[
Export a FCPXML 11 file readable with Final Cut Pro 10.6.8 or later.

See docs here:
https://developer.apple.com/documentation/professional_video_applications/fcpxml_reference

]#


func getColorspace(mi: MediaInfo): string =
  # See: https://developer.apple.com/documentation/professional_video_applications/fcpxml_reference/asset#3686496

  if mi.v.len == 0:
    return "1-1-1 (Rec. 709)"

  let s = mi.v[0]
  if s.pix_fmt == "rgb24":
    return "sRGB IEC61966-2.1"
  if s.color_space == 5: # "bt470bg"
    return "5-1-6 (Rec. 601 PAL)"
  if s.color_space == 6: # "smpte170m"
    return "6-1-6 (Rec. 601 NTSC)"
  if s.color_primaries == 9: # "bt2020"
    # See: https://video.stackexchange.com/questions/22059/how-to-identify-hdr-video
    if s.color_transfer == 16 or s.color_transfer == 18: # "smpte2084" "arib-std-b67"
      return "9-18-9 (Rec. 2020 HLG)"
    return "9-1-9 (Rec. 2020)"

  return "1-1-1 (Rec. 709)"

func makeName(mi: MediaInfo, tb: AVRational): string =
  if mi.getRes()[1] == 720 and tb == 30:
    return "FFVideoFormat720p30"
  if mi.getRes()[1] == 720 and tb == 25:
    return "FFVideoFormat720p25"
  if mi.getRes() == (3840, 2160) and tb == AVRational(num: 24000, den: 1001):
    return "FFVideoFormat3840x2160p2398"
  return "FFVideoFormatRateUndefined"

func pathToUri(a: string): string =
  return "file://" & a

proc parseSMPTE*(val: string, fps: AVRational): int =
  if val.len == 0:
    return 0

  try:
    var parts = val.split(":")
    if len(parts) != 4:
      raise newException(ValueError, &"Invalid SMPTE format: {val}")

    let hours = parseInt(parts[0])
    let minutes = parseInt(parts[1])
    let seconds = parseInt(parts[2])
    let frames = parseInt(parts[3])

    if hours < 0 or minutes < 0 or minutes >= 60 or seconds < 0 or seconds >=
        60 or frames < 0:
      raise newException(ValueError, &"Invalid SMPTE values: {val}")

    let timecodeFps = int(round(fps.num / fps.den))
    if frames >= timecodeFps:
      raise newException(ValueError, &"Frame count {frames} exceeds timecode fps {timecodeFps}")

    return (hours * 3600 + minutes * 60 + seconds) * timecodeFps + frames
  except ValueError as e:
    error(&"Cannot parse SMPTE timecode '{val}': {e.msg}")

proc fcp11_write_xml*(groupName, version, output: string, resolve: bool, tl: v3) =
  func fraction(val: int): string =
    if val == 0:
      return "0s"
    return &"{val * tl.tb.den.int}/{tl.tb.num}s"

  var verStr: string
  if version == "11":
    verStr = "1.11"
  elif version == "10":
    verStr = "1.10"
  else:
    error(&"Unknown final cut pro version: {version}")

  let fcpxml = <>fcpxml(version = verStr)
  let resources = newElement("resources")
  fcpxml.add(resources)

  var srcDur = 0
  var tlDur = (if resolve: 0 else: tl.len)
  var projName: string

  var ptrToMi = initTable[ptr string, MediaInfo]()
  var i = 0

  for ptrSrc in tl.uniqueSources:
    let mi = initMediaInfo(ptrSrc[])
    ptrToMi[ptrSrc] = mi

    if i == 0:
      projName = splitFile(mi.path).name
      srcDur = int(mi.duration * tl.tb)
      if resolve:
        tlDur = srcDur

    let id = "r" & $(i * 2 + 1)
    let width = $tl.res[0]
    let height = $tl.res[1]
    resources.add(<>format(id = id, name = makeName(mi, tl.tb),
        frameDuration = fraction(1), width = width, height = height,
        colorSpace = getColorspace(mi)))

    let id2 = "r" & $(i * 2 + 2)
    let hasVideo = (if mi.v.len > 0: "1" else: "0")
    let hasAudio = (if mi.a.len > 0: "1" else: "0")
    let audioChannels = (if mi.a.len == 0: "2" else: $mi.a[0].channels)

    let startPoint = parseSMPTE(mi.timecode, tl.tb)
    let r2 = <>asset(id = id2, name = splitFile(mi.path).name,
        start = fraction(startPoint), hasVideo = hasVideo, format = id,
        hasAudio = hasAudio, audioSources = "1",
        audioChannels = audioChannels, duration = fraction(tlDur))

    let mediaRep = newElement("media-rep")
    mediaRep.attrs = {"kind": "original-media", "src": mi.path.absolutePath().pathToUri()}.toXmlAttributes

    r2.add mediaRep
    resources.add r2

    i += 1

  let lib = <>library()
  let evt = <>event(name = group_name)
  let proj = <>project(name = projName)
  let sequence = <>sequence(format = "r1", tcStart = "0s", tcFormat = "NDF",
      audioLayout = tl.layout, audioRate = (if tl.sr ==
      44100: "44.1k" else: "48k"))
  let spine = <>spine()

  sequence.add spine
  proj.add sequence
  evt.add proj
  lib.add evt
  fcpxml.add lib

  proc make_clip(`ref`: string, clip: Clip) =
    let src = ptrToMi[clip.src]
    let startPoint = parseSMPTE(src.timecode, tl.tb)

    let asset = newElement("asset-clip")
    asset.attrs = {
      "name": projName,
      "ref": `ref`,
      "offset": fraction(clip.start + startPoint),
      "duration": fraction(clip.dur),
      "start": fraction(clip.offset + startPoint),
      "tcFormat": "NDF"
    }.toXmlAttributes

    spine.add(asset)

    if clip.speed != 1:
      # See the "Time Maps" section.
      # https://developer.apple.com/documentation/professional_video_applications/fcpxml_reference/story_elements/timemap/

      let timemap = newElement("timeMap")
      let timept1 = newElement("timept")
      timept1.attrs = {"time": "0s", "value": "0s",
          "interp": "smooth2"}.toXmlAttributes
      timemap.add(timept1)

      let timept2 = newElement("timept")
      timept2.attrs = {
        "time": fraction(int(srcDur.float / clip.speed)),
        "value": fraction(srcDur),
        "interp": "smooth2"
      }.toXmlAttributes
      timemap.add(timept2)

      asset.add(timemap)

  var clips: ClipLayer
  if tl.v.len > 0 and tl.v[0].len > 0:
    clips = tl.v[0]
  elif tl.a.len > 0 and tl.a[0].len > 0:
    clips = tl.a[0]

  var all_refs: seq[string] = @["r2"]
  if resolve:
    for i in 1 ..< tl.a.len:
      all_refs.add("r" & $((i + 1) * 2))

  for my_ref in all_refs.reversed:
    for clip in clips.c:
      make_clip(my_ref, clip)

  if output == "-":
    echo $fcpxml
  else:
    let xmlStr = "<?xml version='1.0' encoding='utf-8'?>\n" & $fcpxml
    writeFile(output, xmlStr)
