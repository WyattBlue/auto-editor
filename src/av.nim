import std/[strformat, strutils, sequtils, tables, sets]

import ffmpeg
import log
import util/dict

proc `|=`*[T](a: var T, b: T) =
  a = a or b

# func pretty(ctx: ptr AVCodecContext): string =
#   if ctx == nil:
#     return "nil"
#   return &"<AVCodecContext width: {ctx.width}, height: {ctx.height}, bit_rate={ctx.bit_rate}, framerate={ctx.framerate}>"

proc initCodec*(name: string): ptr AVCodec =
  result = avcodec_find_encoder_by_name(name.cstring)
  if result == nil:
    let desc = avcodec_descriptor_get_by_name(name.cstring)
    if desc != nil:
      result = avcodec_find_encoder(desc.id)

proc initEnCtx(codec: ptr AVCodec): ptr AVCodecContext =
  let encoderCtx = avcodec_alloc_context3(codec)
  if encoderCtx == nil:
    error "Could not allocate encoder context"

  if codec.sample_fmts != nil:
    encoderCtx.sample_fmt = codec.sample_fmts[0]

  return encoderCtx

proc initEncoder*(id: AVCodecID): (ptr AVCodec, ptr AVCodecContext) =
  let codec: ptr AVCodec = avcodec_find_encoder(id)
  if codec == nil:
    error "Encoder not found: " & $id
  return (codec, initEnCtx(codec))

proc initEncoder*(name: string): (ptr AVCodec, ptr AVCodecContext) =
  let codec = initCodec(name)
  if codec == nil:
    error "Codec not found: " & name
  return (codec, initEnCtx(codec))

proc initDecoder*(codecpar: ptr AVCodecParameters): ptr AVCodecContext =
  let codec: ptr AVCodec = avcodec_find_decoder(codecpar.codec_id)
  if codec == nil:
    error "Decoder not found"

  result = avcodec_alloc_context3(codec)
  if result == nil:
    error "Could not allocate decoder ctx"

  result.thread_count = 0 # Auto-detect CPU cores
  if result.codec_type == AVMEDIA_TYPE_VIDEO:
    result.thread_type = FF_THREAD_FRAME or FF_THREAD_SLICE

  let ret = avcodec_parameters_to_context(result, codecpar)
  if ret < 0:
    error &"Failed to copy codec parameters: {av_err2str(ret)}"

  if avcodec_open2(result, codec, nil) < 0:
    error "Could not open codec"

type InputContainer* = object
  formatContext*: ptr AVFormatContext
  packet*: ptr AVPacket
  video*: seq[ptr AVStream]
  audio*: seq[ptr AVStream]
  subtitle*: seq[ptr AVStream]
  streams*: seq[ptr AVStream]

proc open*(filename: string): InputContainer =
  result = InputContainer()
  result.packet = av_packet_alloc()

  if avformat_open_input(addr result.formatContext, filename.cstring, nil,
      nil) != 0:
    raise newException(IOError, "Could not open input file: " & filename)

  if avformat_find_stream_info(result.formatContext, nil) < 0:
    avformat_close_input(addr result.formatContext)
    raise newException(IOError, "Could not find stream information")

  for i in 0 ..< result.formatContext.nb_streams.int:
    let stream: ptr AVStream = result.formatContext.streams[i]
    result.streams.add(stream)
    case stream.codecpar.codecType
    of AVMEDIA_TYPE_VIDEO:
      result.video.add(stream)
    of AVMEDIA_TYPE_AUDIO:
      result.audio.add(stream)
    of AVMEDIA_TYPE_SUBTITLE:
      result.subtitle.add(stream)
    else:
      discard


iterator demux*(self: InputContainer, index: int): var AVPacket =
  while av_read_frame(self.formatContext, self.packet) >= 0:
    if self.packet.stream_index.int == index:
      yield self.packet[]
    av_packet_unref(self.packet)


func duration*(container: InputContainer): float64 =
  if container.formatContext.duration != AV_NOPTS_VALUE:
    return float64(container.formatContext.duration) / AV_TIME_BASE
  return 0.0

func bitRate*(container: InputContainer): int64 =
  return container.formatContext.bit_rate

proc mediaLength*(container: InputContainer): AVRational =
  # Get the mediaLength in seconds.

  var formatCtx = container.formatContext
  var audioStreamIndex = (if container.audio.len == 0: -1 else: container.audio[0].index)
  var videoStreamIndex = (if container.video.len == 0: -1 else: container.video[0].index)

  if audioStreamIndex != -1:
    var time_base: AVRational
    var packet = ffmpeg.av_packet_alloc()
    var biggest_pts: int64

    while ffmpeg.av_read_frame(formatCtx, packet) >= 0:
      if packet.stream_index == audioStreamIndex:
        if packet.pts != ffmpeg.AV_NOPTS_VALUE and packet.pts > biggest_pts:
          biggest_pts = packet.pts

      ffmpeg.av_packet_unref(packet)

    if packet != nil:
      ffmpeg.av_packet_free(addr packet)

    time_base = formatCtx.streams[audioStreamIndex].time_base
    return biggest_pts * time_base

  if videoStreamIndex != -1:
    var video = container.video[0]
    if video.duration == AV_NOPTS_VALUE or video.time_base == AV_NOPTS_VALUE:
      return AVRational(0)
    else:
      return video.duration * video.time_base

  error "No audio or video stream found"

iterator decode*(container: InputContainer, index: cint, codecCtx: ptr AVCodecContext, frame: ptr AVFrame): ptr AVFrame =
  var ret: cint
  var packet = container.packet
  while av_read_frame(container.formatContext, packet) >= 0:
    defer: av_packet_unref(packet)

    if packet.stream_index == index:
      ret = avcodec_send_packet(codecCtx, packet)
      if ret < 0 and ret != AVERROR_EAGAIN:
        error &"Error sending packet to decoder: {av_err2str(ret)}"

      while true:
        ret = avcodec_receive_frame(codecCtx, frame)
        if ret == AVERROR_EAGAIN or ret == AVERROR_EOF:
          break
        elif ret < 0:
          error &"Error receiving frame from decoder: {av_err2str(ret)}"

        yield frame

iterator flushDecode*(container: InputContainer, index: cint, codecCtx: ptr AVCodecContext, frame: ptr AVFrame): ptr AVFrame =
  var ret: cint
  var packet = container.packet
  var flushing = false

  while not flushing:
    ret = av_read_frame(container.formatContext, packet)
    if ret < 0:
      flushing = true
      ret = avcodec_send_packet(codecCtx, nil)  # Flush
    else:
      if packet.stream_index == index:
        ret = avcodec_send_packet(codecCtx, packet)
      av_packet_unref(packet)

    # Only try to receive frames if we're processing the right stream or flushing
    if (not flushing and packet.stream_index == index) or flushing:
      while true:
        ret = avcodec_receive_frame(codecCtx, frame)
        if ret == AVERROR_EAGAIN or ret == AVERROR_EOF:
          break
        elif ret < 0:
          break
        else:
          yield frame

proc seek*(container: InputContainer, offset: int64, backward: bool = true, stream: ptr AVStream = nil) =
  var flags: cint = 0

  if backward:
    flags |= AVSEEK_FLAG_BACKWARD

  var stream_index: cint = (if stream == nil: -1 else: stream.index)
  var ret = av_seek_frame(container.formatContext, stream_index, offset, flags)
  if ret < 0:
    error "Error seeking frame"
  # Callers need to call `avcodec_flush_buffers()` after.

proc close*(container: InputContainer) =
  if container.packet != nil:
    av_packet_free(addr container.packet)
  avformat_close_input(addr container.formatContext)


type OutputContainer* = object
  file: string
  streams: seq[ptr AVStream] = @[]
  video*: seq[ptr AVStream] = @[]
  options*: Table[string, string]
  formatCtx*: ptr AVFormatContext
  packet: ptr AVPacket
  started: bool = false

proc openWrite*(file: string): OutputContainer =
  let formatCtx: ptr AVFormatContext = nil
  discard avformat_alloc_output_context2(addr formatCtx, nil, nil, file.cstring)
  if formatCtx == nil:
    error "Could not create output context"

  for i in 0 ..< formatCtx.nb_streams.int:
    if formatCtx.streams[i].codecpar.codec_type == AVMEDIA_TYPE_VIDEO:
      result.video.add formatCtx.streams[i]

  result.file = file
  result.formatCtx = formatCtx
  result.packet = av_packet_alloc()

proc addStreamFromTemplate*(self: var OutputContainer,
    streamT: ptr AVStream): ptr AVStream =
  let format = self.formatCtx

  let ctxT = initDecoder(streamT.codecpar)
  let codec: ptr AVCodec = ctxT.codec
  defer: avcodec_free_context(addr ctxT)

  # Assert that this format supports the requested codec.
  if avformat_query_codec(format.oformat, codec.id, FF_COMPLIANCE_NORMAL) == 0:
    let formatName = if format.oformat.name != nil: $format.oformat.name else: "unknown"
    let codecName = if codec.name != nil: $codec.name else: "unknown"
    error &"Format '{formatName}' does not support codec '{codecName}'"

  let stream: ptr AVStream = avformat_new_stream(format, codec)
  self.streams.add stream
  let ctx: ptr AVCodecContext = avcodec_alloc_context3(codec)

  # Reset the codec tag assuming we are remuxing.
  discard avcodec_parameters_to_context(ctx, streamT.codecpar)
  ctx.codec_tag = 0

  # Some formats want stream headers to be separate
  if (format.oformat.flags and AVFMT_GLOBALHEADER) != 0:
    ctx.flags |= AV_CODEC_FLAG_GLOBAL_HEADER

  # Initialize stream codec parameters to populate the codec type. Subsequent changes to
  # the codec context will be applied just before encoding starts in `start_encoding()`.
  if avcodec_parameters_from_context(stream.codecpar, ctx) < 0:
    error "Could not set ctx parameters"

  return stream

proc addStream*(self: var OutputContainer, codecName: string, rate: AVRational, width: cint = 640, height: cint = 480, layout: string = "", metadata: Table[string, string] = initTable[string, string]()): (
    ptr AVStream, ptr AVCodecContext) =
  let codec = initCodec(codecName)
  if codec == nil:
    error "Codec not found: " & codecName
  let format = self.formatCtx

  # Assert that this format supports the requested codec.
  if avformat_query_codec(format.oformat, codec.id, FF_COMPLIANCE_NORMAL) == 0:
    let formatName = if format.oformat.name != nil: $format.oformat.name else: "unknown"
    error &"Format '{formatName}' does not support codec '{codecName}'"

  let stream: ptr AVStream = avformat_new_stream(format, codec)
  if stream == nil:
    error "Could not allocate new stream"
  self.streams.add stream
  let ctx: ptr AVCodecContext = avcodec_alloc_context3(codec)
  if ctx == nil:
    error "Could not allocate encoder context"

  # Now lets set some more sane video defaults
  if codec.`type` == AVMEDIA_TYPE_VIDEO:
    ctx.pix_fmt = AV_PIX_FMT_YUV420P
    ctx.width = width
    ctx.height = height
    ctx.bit_rate = 0
    ctx.bit_rate_tolerance = 128000
    ctx.framerate = rate
    ctx.time_base = av_inv_q(rate)
    stream.avg_frame_rate = ctx.framerate
    stream.time_base = ctx.time_base
  # Some sane audio defaults
  elif codec.`type` == AVMEDIA_TYPE_AUDIO:
    ctx.sample_fmt = codec.sample_fmts[0]
    ctx.bit_rate = 0
    ctx.bit_rate_tolerance = 32000
    ctx.sample_rate = rate.num div rate.den
    stream.time_base = ctx.time_base
    if layout == "":
      av_channel_layout_default(addr ctx.ch_layout, 2)
    else:
      if av_channel_layout_from_string(addr ctx.ch_layout, layout.cstring) < 0:
        error &"Unknown layout: {layout}"

  # Some formats want stream headers to be separate
  if (format.oformat.flags and AVFMT_GLOBALHEADER) != 0:
    ctx.flags |= AV_CODEC_FLAG_GLOBAL_HEADER

  # Initialize stream codec parameters to populate the codec type. Subsequent changes to
  # the codec context will be applied just before encoding starts in `startEncoding()`.
  if avcodec_parameters_from_context(stream.codecpar, ctx) < 0:
    error "Could not set ctx parameters"

  if metadata.len > 0:
    dictToAvdict(addr stream.metadata, metadata)

  return (stream, ctx)

proc startEncoding*(self: var OutputContainer) =
  if self.started:
    return

  self.started = true
  let outputCtx = self.formatCtx

  # Open the output file, if needed.
  if (outputCtx.oformat.flags and AVFMT_NOFILE) == 0:
    if avio_open(addr outputCtx.pb, self.file.cstring, AVIO_FLAG_WRITE) < 0:
      error &"Could not open output file '{self.file}'"

  let options: ptr AVDictionary = nil
  dictToAvdict(addr options, self.options)

  var ret = avformat_write_header(outputCtx, addr options)
  if ret < 0:
    error &"Write header: {av_err2str(ret)}"

  let remainOptions = avdict_to_dict(options)
  var usedOptions: HashSet[string]
  for k, v in self.options:
    if k notin remainOptions:
      usedOptions.incl k

  av_dict_free(addr options)

  var unusedOptions = initTable[string, string]()
  for k, v in self.options:
    if k notin usedOptions:
      unusedOptions[k] = v

  if unusedOptions.len > 0:
    debug &"Some options weren't used: {unusedOptions}"

proc open*(ctx: ptr AVCodecContext) =
  # Only for encoders
  if ctx.time_base == 0:
    if ctx.codec_type == AVMEDIA_TYPE_VIDEO:
      if ctx.framerate == 0:
        ctx.time_base = AVRational(num: 1, den: AV_TIME_BASE)
      else:
        ctx.time_base = av_inv_q(ctx.framerate)
    elif ctx.codec_type == AVMEDIA_TYPE_AUDIO:
      ctx.time_base = AVRational(num: 1, den: ctx.sample_rate)
    else:
      ctx.time_base = AVRational(num: 1, den: AV_TIME_BASE)
  if avcodec_open2(ctx, ctx.codec, nil) < 0:
    error "Could not open encoder"

proc setProfileOrErr*(ctx: ptr AVCodecContext, to: string) =
  if ctx.codec == nil:
    error "This codec does not support profiles"

  let desc = avcodec_descriptor_get(ctx.codec.id)
  if desc == nil or desc.profiles == nil:
    error "This codec does not support profiles"

  const FF_PROFILE_UNKNOWN = -99

  var allProfiles: seq[string] = @[]
  var i = 0
  let profiles = cast[ptr UncheckedArray[AVProfile]](desc.profiles)
  while profiles[i].profile != FF_PROFILE_UNKNOWN:
    allProfiles.add $profiles[i].name
    if to.toLowerAscii == ($profiles[i].name).toLowerAscii:
      ctx.profile = profiles[i].profile
      return
    inc i

  let allow = allProfiles.mapIt("\"" & it.toLowerAscii & "\"").join(" ")
  let encName = $ctx.codec.name
  error &"`{to}` is not a valid profile for encoder: {encName}\nprofiles supported: {allow}"

proc mux*(self: var OutputContainer, packet: var AVPacket) =
  self.startEncoding()

  if packet.stream_index < 0 or cuint(packet.stream_index) >= self.formatCtx.nb_streams:
    error "Bad packet stream_index"

  let stream: ptr AVStream = self.streams[int(packet.stream_index)]

  # Rebase packet time
  let dst = stream.time_base
  if packet.time_base == 0:
    packet.time_base = dst
  elif packet.time_base == dst:
    discard
  else:
    av_packet_rescale_ts(addr packet, packet.time_base, dst)

  # Make another reference to the packet, as `av_interleaved_write_frame()`
  # takes ownership of the reference.
  if av_packet_ref(self.packet, addr packet) < 0:
    error "Failed to reference packet"

  discard av_interleaved_write_frame(self.formatCtx, self.packet)
  # if ret < 0:
  #   echo &"Failed to write packet: {ret}"

iterator encode*(encoderCtx: ptr AVCodecContext, frame: ptr AVFrame, packet: ptr AVPacket): ptr AVPacket =
  let isFlush: bool = frame == nil

  var ret = avcodec_send_frame(encoderCtx, frame)
  if ret < 0:
    error &"Error sending frame to encoder: {ret}"

  while true:
    let receiveRet = avcodec_receive_packet(encoderCtx, packet)
    if receiveRet == AVERROR_EAGAIN or receiveRet == AVERROR_EOF:
      break
    elif receiveRet < 0:
      if isFlush:
        break
      else:
        error "Error receiving packet from encoder"

    yield packet # Nim requres iterator yield values

proc close*(outputCtx: ptr AVFormatContext) =
  discard av_write_trailer(outputCtx)

  if (outputCtx.oformat.flags and AVFMT_NOFILE) == 0:
    discard avio_closep(addr outputCtx.pb)
  avformat_free_context(outputCtx)

proc close*(self: OutputContainer) =
  if self.packet != nil:
    av_packet_free(addr self.packet)
  close(self.formatCtx)


func name*(stream: ptr AVStream): string =
  if stream == nil or stream.codecpar == nil:
    return ""

  let codec = avcodec_find_decoder(stream.codecpar.codec_id)
  if codec != nil and codec.name != nil:
    return $codec.name

  # Fallback to codec descriptor if codec not found
  # let desc = avcodec_descriptor_get(stream.codecpar.codec_id)
  # if desc != nil and desc.name != nil:
  #   return $desc.name

  return ""


func canonicalName*(codec: ptr AVCodec): string =
  return $avcodec_get_name(codec.id)

func time*(frame: ptr AVFrame, tb: AVRational): float64 =
  # `tb` should be AVStream.time_base
  if frame.pts == AV_NOPTS_VALUE:
    return -1.0
  return float(frame.pts) * float(tb.num) / float(tb.den)

func prettyFrame*(frame: ptr AVFrame): string =
  func pixFmtName(format: cint): string =
    let name = av_get_pix_fmt_name(AVPixelFormat(format))
    (if name != nil: $name else: "Unknown(" & $format & ")")

  func sampFmtName(format: cint): string =
    let name = av_get_sample_fmt_name(format)
    (if name != nil: $name else: "Unknown(" & $format & ")")

  if frame == nil:
    return "<AVFrame nil>"
  if frame.width > 2:
    return &"<AVFrame format={pixFmtName(frame.format)} width={frame.width} height={frame.height} base={frame.time_base}>"

  return &"<AVFrame format={sampFmtName(frame.format)} samples={frame.nb_samples}>"

func dialogue*(assText: string): string =
  let textLen = assText.len
  var
    i: int64 = 0
    curChar: char
    nextChar: char
    commaCount: int8 = 0
    state = false

  while commaCount < 8 and i < textLen:
    if assText[i] == ',':
      commaCount += 1
    i += 1

  while i < textLen:
    curChar = assText[i]
    nextChar = (if i + 1 >= textLen: '\0' else: assText[i + 1])

    if curChar == '\\' and nextChar == 'N':
      result &= "\n"
      i += 2
      continue

    if not state:
      if curChar == '{' and nextChar != '\\':
        state = true
      else:
        result &= curChar
    elif curChar == '}':
      state = false
    i += 1
