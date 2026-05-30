import std/[json, sets, strformat, strutils, tables]

import ../[av, ffmpeg, log, media, timeline]
import ../util/[fun, lang, rational]

proc genericTrack(lang: Lang, bitrate: int64) =
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
    let (ratioWidth, ratioHeight) = aspectRatio(v.width, v.height, v.sar.num, v.sar.den)

    echo &"   - track {track}:"
    echo &"     - codec: {$avcodec_get_name(v.codecId)}"
    echo &"     - fps: {v.avg_rate}"
    echo &"     - resolution: {v.width}x{v.height}"
    echo &"     - aspect ratio: {ratioWidth}:{ratioHeight}"
    echo &"     - pixel aspect ratio: {v.sar}"
    if v.duration != 0.0:
      echo &"     - duration: {v.duration}"
    echo &"     - pix fmt: {v.pix_fmt}"

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

  if fileInfo.i.len > 0:
    echo " - image:"
  for track, i in fileInfo.i:
    let (ratioWidth, ratioHeight) = aspectRatio(i.width, i.height, i.sar.num, i.sar.den)

    echo &"   - track {track}:"
    echo &"     - codec: {$avcodec_get_name(i.codecId)}"
    echo &"     - resolution: {i.width}x{i.height}"
    echo &"     - aspect ratio: {ratioWidth}:{ratioHeight}"
    echo &"     - pixel aspect ratio: {i.sar}"
    echo &"     - pix fmt: {i.pix_fmt}"

    if i.color_range == 1:
      echo "     - color range: 1 (tv)"
    elif i.color_range == 2:
      echo "     - color range: 2 (pc)"
    elif i.color_range != 0:
      echo &"     - color range: {i.color_range}"

    if i.color_space != 2:
      echo &"     - color space: {i.color_space.bt709}"
    if i.color_primaries != 2:
      echo &"     - color primaries: {i.color_primaries.bt709}"
    if i.color_transfer != 2:
      echo &"     - color transfer: {i.color_transfer.bt709}"
    genericTrack(i.lang, i.bitrate)

  echo " - container:"
  if fileInfo.duration != 0.0:
    echo &"   - duration: {fileInfo.duration}"
  echo &"   - bitrate: {fileInfo.bitrate}"


func getJsonInfo(fileInfo: MediaInfo): JsonNode =
  var varr, aarr, sarr, iarr: seq[JsonNode] = @[]
  var tb = AVRational(30)
  if fileInfo.v.len > 0:
    tb = makeSaneTimebase(fileInfo.v[0].avg_rate)

  for v in fileInfo.v:
    let (ratioWidth, ratioHeight) = aspectRatio(v.width, v.height, v.sar.num, v.sar.den)
    varr.add( %* {
      "codec": $avcodec_get_name(v.codecId),
      "fps": $v.avg_rate,
      "resolution": [v.width, v.height],
      "aspect_ratio": [ratioWidth, ratioHeight],
      "pixel_aspect_ratio": $v.sar,
      "duration": v.duration,
      "pix_fmt": $v.pix_fmt,
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

  for i in fileInfo.i:
    let (ratioWidth, ratioHeight) = aspectRatio(i.width, i.height, i.sar.num, i.sar.den)
    iarr.add( %* {
      "codec": $avcodec_get_name(i.codecId),
      "resolution": [i.width, i.height],
      "aspect_ratio": [ratioWidth, ratioHeight],
      "pixel_aspect_ratio": $i.sar,
      "pix_fmt": $i.pix_fmt,
      "color_range": i.color_range,
      "color_space": i.color_space,
      "color_primaries": i.color_primaries,
      "color_transfer": i.color_transfer,
      "lang": i.lang
    })

  result = %* {
    "type": "media",
    "recommendedTimebase": $tb.num & "/" & $tb.den,
    "video": varr,
    "audio": aarr,
    "subtitle": sarr,
    "image": iarr,
    "container": {
      "duration": fileInfo.duration,
      "bitrate": fileInfo.bitrate
    }
  }


type CodecListKind = enum clkEncoders, clkDecoders, clkCodecs

var hwDeviceCache: Table[AVHWDeviceType, bool]

proc hwDeviceAvailable(t: AVHWDeviceType): bool =
  if t in hwDeviceCache:
    return hwDeviceCache[t]
  var ctx: ptr AVBufferRef = nil
  let ok = av_hwdevice_ctx_create(addr ctx, t, nil, nil, 0) >= 0
  if ctx != nil:
    av_buffer_unref(addr ctx)
  hwDeviceCache[t] = ok
  return ok

proc hwDeviceForEncoder(codec: ptr AVCodec): AVHWDeviceType =
  # Ask the encoder which hw device type it needs.
  var i: cint = 0
  while true:
    let cfg = avcodec_get_hw_config(codec, i)
    if cfg == nil: break
    if cfg.device_type != AV_HWDEVICE_TYPE_NONE:
      return cfg.device_type
    inc i
  return AV_HWDEVICE_TYPE_NONE  # software encoder

proc hwEncoderUsable(codec: ptr AVCodec): bool =
  let deviceType = hwDeviceForEncoder(codec)
  if deviceType == AV_HWDEVICE_TYPE_NONE:
    return true
  if not hwDeviceAvailable(deviceType):
    return false
  if codec.`type` != AVMEDIA_TYPE_VIDEO:
    return true
  var ctx = avcodec_alloc_context3(codec)
  if ctx == nil:
    return false
  ctx.width = 1280
  ctx.height = 720
  ctx.bit_rate = 2_000_000
  ctx.time_base = AVRational(num: 1, den: 25)
  ctx.framerate = AVRational(num: 25, den: 1)
  ctx.pix_fmt = AV_PIX_FMT_YUV420P
  if codec.pix_fmts != nil and codec.pix_fmts[0] != AV_PIX_FMT_NONE:
    ctx.pix_fmt = codec.pix_fmts[0]
  let ok = avcodec_open2(ctx, codec, nil) >= 0
  avcodec_free_context(addr ctx)
  return ok

proc printCodecList(ofmt: ptr AVOutputFormat, kind: CodecListKind) =
  var videos, audios, subs, others: seq[string]
  var seen: HashSet[AVCodecID]

  var bestVideo = ofmt.video_codec
  var bestAudio = ofmt.audio_codec
  var bestSubtitle = ofmt.subtitle_codec
  if kind in {clkCodecs, clkEncoders}:
    let fmtName = $ofmt.name
    if fmtName == "mp4" or fmtName == "matroska":
      let d = avcodec_descriptor_get_by_name("opus")
      if d != nil: bestAudio = d.id
    if fmtName == "mp4":
      let d = avcodec_descriptor_get_by_name("mov_text")
      if d != nil: bestSubtitle = d.id

  var opaque: pointer = nil
  while true:
    let codec = av_codec_iterate(addr opaque)
    if codec == nil: break

    case kind
    of clkEncoders:
      if av_codec_is_encoder(codec) == 0: continue
      if not hwEncoderUsable(codec): continue
    of clkDecoders:
      if av_codec_is_decoder(codec) == 0: continue
    of clkCodecs:
      if codec.id in seen: continue
      if avcodec_find_encoder(codec.id) == nil: continue

    if avformat_query_codec(ofmt, codec.id, FF_COMPLIANCE_EXPERIMENTAL) <= 0:
      continue
    if kind == clkCodecs:
      seen.incl(codec.id)

    var name = if kind == clkCodecs: $avcodec_get_name(codec.id) else: $codec.name
    if not noColor and
        avformat_query_codec(ofmt, codec.id, FF_COMPLIANCE_STRICT) <= 0:
      name = "\e[31m" & name & "\e[0m"

    template bucket(list, best) =
      if kind in {clkCodecs, clkEncoders} and codec.id == best: list.insert(name, 0)
      else: list.add name

    case codec.`type`
    of AVMEDIA_TYPE_VIDEO: bucket(videos, bestVideo)
    of AVMEDIA_TYPE_AUDIO: bucket(audios, bestAudio)
    of AVMEDIA_TYPE_SUBTITLE: bucket(subs, bestSubtitle)
    else: others.add name

  echo "v: " & videos.join(",")
  echo "a: " & audios.join(",")
  echo "s: " & subs.join(",")
  echo "other: " & others.join(",")

proc main*(args: seq[string]) =
  av_log_set_level(AV_LOG_QUIET)

  var isJson = false
  var queryExt = ""
  var queryKind: CodecListKind
  var inputFiles: seq[string] = @[]

  var i = 0
  while i < args.len:
    let key = args[i]
    if key == "--json":
      isJson = true
    elif key in ["-encoders", "-decoders", "-codecs"]:
      inc i
      if i >= args.len:
        error &"{key} requires a format argument"
      queryExt = args[i]
      queryKind = case key
        of "-encoders": clkEncoders
        of "-decoders": clkDecoders
        else: clkCodecs
    else:
      if key.startsWith("--"):
        error &"Unknown option: {key}"
      inputFiles.add key
    inc i

  if queryExt != "":
    let ofmt = av_guess_format(nil, ("." & queryExt).cstring, nil)
    if ofmt == nil:
      error &"Unknown format: {queryExt}"
    printCodecList(ofmt, queryKind)
    return

  var fileInfo: JsonNode = %* {}
  for inputFile in inputFiles:
    try:
      let formatCtx = av.openFormatCtx(inputFile.cstring)
      let mediaInfo = initMediaInfo(formatCtx, inputFile)
      avformat_close_input(addr formatCtx)

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
