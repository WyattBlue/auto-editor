import std/hashes

import av
import ffmpeg

type
  VideoStream* = object
    duration*: float64
    bitrate*: int64
    avg_rate*: AVRational
    codec*: string
    timecode: string
    lang*: string
    timebase*: AVRational
    sar*: AVRational
    pix_fmt*: string
    width*: cint
    height*: cint
    color_range*: cint
    color_space*: cint
    color_primaries*: cint
    color_transfer*: cint

  AudioStream* = object
    duration*: float64
    bitrate*: int64
    codec*: string
    lang*: string
    layout*: string
    sampleRate*: cint
    channels*: cint

  SubtitleStream* = object
    duration*: float64
    bitrate*: int64
    codec*: string
    lang*: string

  DataStream* = object
    codec*: string
    timecode*: string

  MediaInfo* = object
    path*: string
    duration*: float64
    bitrate*: int64
    timecode*: string # In SMPTE
    recommendedTimebase*: string
    v*: seq[VideoStream]
    a*: seq[AudioStream]
    s*: seq[SubtitleStream]
    d*: seq[DataStream]


proc hash*(mi: MediaInfo): Hash =
  hash(mi.path)

proc `==`*(a, b: MediaInfo): bool =
  a.path == b.path

func getRes*(self: MediaInfo): (int, int) =
  if self.v.len > 0:
    return (self.v[0].width, self.v[0].height)
  else:
    return (1920, 1080)

proc fourccToString*(fourcc: uint32): string =
  var buf: array[5, char]
  buf[0] = char(fourcc and 0xFF)
  buf[1] = char((fourcc shr 8) and 0xFF)
  buf[2] = char((fourcc shr 16) and 0xFF)
  buf[3] = char((fourcc shr 24) and 0xFF)
  buf[4] = '\0'
  return $cast[cstring](addr buf[0])

proc initMediaInfo*(formatContext: ptr AVFormatContext,
    path: string): MediaInfo =
  result.path = path
  result.v = @[]
  result.a = @[]
  result.s = @[]
  result.d = @[]

  result.bitrate = formatContext.bit_rate
  if formatContext.duration != AV_NOPTS_VALUE:
    result.duration = float64(formatContext.duration) / AV_TIME_BASE
  else:
    result.duration = 0.0

  func getTimecode(vs: seq[VideoStream], ds: seq[DataStream]): string =
    for d in ds:
      if d.timecode.len > 0:
        return d.timecode
    for v in vs:
      if v.timecode.len > 0:
        return v.timecode
    return "00:00:00:00"

  for i in 0 ..< formatContext.nb_streams.int:
    let stream = formatContext.streams[i]
    let codecParameters = stream.codecpar
    var codecCtx = avcodec_alloc_context3(nil)
    discard avcodec_parameters_to_context(codecCtx, codecParameters)
    defer: avcodec_free_context(addr codecCtx)

    let metadata = cast[ptr AVDictionary](stream.metadata)
    let entry = av_dict_get(metadata, "language", nil, 0)
    let lang = (if entry == nil: "und" else: $entry.value)

    var duration: float64
    if stream.duration == AV_NOPTS_VALUE:
      duration = 0.0
    else:
      duration = stream.duration.float64 * av_q2d(stream.time_base)

    if codecParameters.codec_type == AVMEDIA_TYPE_VIDEO:
      let timecodeEntry = av_dict_get(metadata, "timecode", nil, 0)
      let timecodeStr = (if timecodeEntry == nil: "" else: $timecodeEntry.value)

      let sar = (if codecCtx.sample_aspect_ratio == 0: AVRational(1) else: codecCtx.sample_aspect_ratio)

      result.v.add(VideoStream(
        duration: duration,
        bitrate: codecCtx.bit_rate,
        avg_rate: stream.avg_frame_rate,
        codec: $avcodec_get_name(codecCtx.codec_id),
        timecode: timecodeStr,
        lang: lang,
        timebase: stream.time_base,
        sar: sar,
        pix_fmt: $av_get_pix_fmt_name(codecCtx.pix_fmt),
        width: codecCtx.width,
        height: codecCtx.height,
        color_range: codecCtx.color_range,
        color_space: codecCtx.colorspace,
        color_primaries: codecCtx.color_primaries,
        color_transfer: codecCtx.color_trc,
      ))
    elif codecParameters.codec_type == AVMEDIA_TYPE_AUDIO:
      var layout: array[64, char]
      discard av_channel_layout_describe(addr codecCtx.ch_layout, cast[
          cstring](addr layout[0]), sizeof(layout).csize_t)

      result.a.add(AudioStream(
        duration: duration,
        bitrate: codecCtx.bit_rate,
        codec: $avcodec_get_name(codecCtx.codec_id),
        lang: lang,
        layout: $cast[cstring](addr layout[0]),
        sampleRate: codecCtx.sample_rate,
        channels: codecParameters.ch_layout.nb_channels,
      ))
    elif codecParameters.codec_type == AVMEDIA_TYPE_SUBTITLE:
      result.s.add(SubtitleStream(
        duration: duration,
        bitrate: codecCtx.bit_rate,
        codec: $avcodec_get_name(codecCtx.codec_id),
        lang: lang,
      ))
    elif codecParameters.codec_type == AVMEDIA_TYPE_DATA:
      let timecodeEntry = av_dict_get(metadata, "timecode", nil, 0)
      let timecodeStr = (if timecodeEntry == nil: "" else: $timecodeEntry.value)
      let codec = $avcodec_get_name(codecCtx.codec_id) & " (" & fourccToString(
          codecCtx.codec_tag) & ")"
      result.d.add(DataStream(codec: codec, timecode: timecodeStr))

  result.timecode = getTimecode(result.v, result.d)


proc initMediaInfo*(path: string): MediaInfo =
  let container = av.open(path)
  result = initMediaInfo(container.formatContext, path)
  container.close()
