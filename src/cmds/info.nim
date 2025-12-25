import std/json
import std/[strformat, strutils]

import ../av
import ../ffmpeg
import ../timeline
import ../media
import ../log
import ../util/fun

func `%`*(lang: Lang): JsonNode =
  %($lang)

proc genericTrack(lang: Lang, bitrate: int) =
  if bitrate != 0:
    echo &"     - bitrate: {bitrate}"
  if lang != ['u', 'n', 'd', '\0']:
    echo &"     - lang: {lang}"

func bt709(val: int): string =
  if val == 1:
    return "1 (bt709)"
  return $val

func fourccToString(fourcc: uint32): string =
  var buf: array[5, char]
  buf[0] = char(fourcc and 0xFF)
  buf[1] = char((fourcc shr 8) and 0xFF)
  buf[2] = char((fourcc shr 16) and 0xFF)
  buf[3] = char((fourcc shr 24) and 0xFF)
  buf[4] = '\0'
  return $cast[cstring](addr buf[0])

proc printYamlInfo(fileInfo: MediaInfo) =
  var tb = AVRational(30)
  if fileInfo.v.len > 0:
    tb = makeSaneTimebase(fileInfo.v[0].avg_rate)
  echo &"{fileInfo.path}:\n - recommendedTimebase: {tb.num}/{tb.den}"

  if fileInfo.v.len > 0:
    echo " - video:"
  for track, v in fileInfo.v:
    let (ratioWidth, ratioHeight) = aspectRatio(v.width, v.height)

    echo &"   - track {track}:"
    echo &"     - codec: {$avcodec_get_name(v.codecId)}"
    echo &"     - fps: {v.avg_rate}"
    echo &"     - resolution: {v.width}x{v.height}"
    echo &"     - aspect ratio: {ratioWidth}:{ratioHeight}"
    echo &"     - pixel aspect ratio: {v.sar}"
    if v.duration != 0.0:
      echo &"     - duration: {v.duration}"
    echo &"     - pix fmt: {av_get_pix_fmt_name(v.pix_fmt)}"

    if v.color_range == 1:
      echo "     - color range: 1 (tv)"
    elif v.color_range == 2:
      echo "     - color range: 2 (pc)"
    elif v.color_range != 0:
      echo &"     - color range: {v.color_range}"

    if v.color_space != 2:
      echo &"     - color space: {v.color_space.bt709}"
    if v.color_primaries != 2:
      echo &"     - color primaries: {v.color_primaries.bt709}"
    if v.color_transfer != 2:
      echo &"     - color transfer: {v.color_transfer.bt709}"
    echo &"     - timebase: {v.timebase}"
    genericTrack(v.lang, v.bitrate)


  if fileInfo.a.len > 0:
    echo " - audio:"
  for track, a in fileInfo.a:
    echo &"   - track {track}:"
    echo &"     - codec: {$avcodec_get_name(a.codecId)}"
    echo &"     - layout: {a.layout}"
    echo &"     - samplerate: {a.samplerate}"
    if a.duration != 0.0:
      echo &"     - duration: {a.duration}"
    genericTrack(a.lang, a.bitrate)

  if fileInfo.s.len > 0:
    echo " - subtitle:"
  for track, s in fileInfo.s:
    echo &"   - track {track}:"
    echo &"     - codec: {$avcodec_get_name(s.codecId)}"
    genericTrack(s.lang, 0)

  if fileInfo.d.len > 0:
    echo " - data:"
  for track, d in fileInfo.d:
    echo &"   - track {track}:"
    echo &"     - codec: {$avcodec_get_name(d.codecId)} ({fourccToString(d.tag)})"
    echo &"     - timecode: {d.timecode}"

  echo " - container:"
  if fileInfo.duration != 0.0:
    echo &"   - duration: {fileInfo.duration}"
  echo &"   - bitrate: {fileInfo.bitrate}"


func getJsonInfo(fileInfo: MediaInfo): JsonNode =
  var
    varr: seq[JsonNode] = @[]
    aarr: seq[JsonNode] = @[]
    sarr: seq[JsonNode] = @[]

  var tb = AVRational(30)
  if fileInfo.v.len > 0:
    tb = makeSaneTimebase(fileInfo.v[0].avg_rate)

  for v in fileInfo.v:
    let (ratioWidth, ratioHeight) = aspectRatio(v.width, v.height)
    varr.add( %* {
      "codec": $avcodec_get_name(v.codecId),
      "fps": $v.avg_rate,
      "resolution": [v.width, v.height],
      "aspect_ratio": [ratioWidth, ratioHeight],
      "pixel_aspect_ratio": v.sar,
      "duration": v.duration,
      "pix_fmt": $av_get_pix_fmt_name(v.pix_fmt),
      "color_range": v.color_range,
      "color_space": v.color_space,
      "color_primaries": v.color_primaries,
      "color_transfer": v.color_transfer,
      "timebase": $v.timebase,
      "bitrate": v.bitrate,
      "lang": v.lang
    })

  for a in fileInfo.a:
    aarr.add( %* {"codec": $avcodec_get_name(a.codecId), "layout": a.layout,
        "samplerate": a.sampleRate, "duration": a.duration,
        "bitrate": a.bitrate, "lang": a.lang})

  for s in fileInfo.s:
    sarr.add( %* s)

  result = %* {
    "type": "media",
    "recommendedTimebase": $tb.num & "/" & $tb.den,
    "video": varr,
    "audio": aarr,
    "subtitle": sarr,
    "container": {
      "duration": fileInfo.duration,
      "bitrate": fileInfo.bitrate
    }
  }


proc main*(args: seq[string]) =
  if args.len < 1:
    echo "Retrieve information and properties about media files"
    quit(0)

  av_log_set_level(AV_LOG_QUIET)

  var isJson = false
  var inputFiles: seq[string] = @[]

  for key in args:
    if key == "--json":
      isJson = true
    else:
      if key.startsWith("--"):
        error &"Unknown option: {key}"
      inputFiles.add key

  var fileInfo: JsonNode = %* {}
  for inputFile in inputFiles:
    try:
      var container = av.open(inputFile)
      let mediaInfo = initMediaInfo(container.formatContext, inputFile)
      container.close()

      if isJson:
        fileInfo[inputFile] = getJsonInfo(mediaInfo)
      else:
        printYamlInfo(mediaInfo)
        echo ""

    except IOError:
      if isJson:
        fileInfo[inputFile] = %* {"type": "invalid"}
      else:
        echo inputFile & "\n - Invalid\n"

  if isJson:
    echo pretty(fileInfo)
