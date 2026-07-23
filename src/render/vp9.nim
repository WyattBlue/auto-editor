import std/[algorithm, strformat]
from std/math import round

import ../[action, av, ffmpeg, log, timeline]
import ../util/rational
import smart

func frameAt(ts: int64, tb, fps: AVRational): int64 =
  int64(round(float(ts) * float(tb) * float(fps)))

func readBit(data: ptr UncheckedArray[uint8], size: int, pos: var int): int =
  if pos >= size * 8:
    return -1
  result = int((data[pos shr 3] shr (7 - (pos and 7))) and 1)
  inc pos

func vp9IsKeyframe(data: ptr uint8, size: int): bool =
  ## Read the fixed portion of VP9's uncompressed header. Matroska's key flag
  ## should already reflect this, but checking the bitstream avoids treating a
  ## malformed cue or an intra-only frame as a random-access GOP boundary.
  if data == nil or size <= 0:
    return false
  let bytes = cast[ptr UncheckedArray[uint8]](data)
  var pos = 0
  let markerHi = readBit(bytes, size, pos)
  let markerLo = readBit(bytes, size, pos)
  if markerHi != 1 or markerLo != 0:
    return false
  let profileLow = readBit(bytes, size, pos)
  let profileHigh = readBit(bytes, size, pos)
  if profileLow < 0 or profileHigh < 0:
    return false
  let profile = profileLow or (profileHigh shl 1)
  if profile == 3:
    let reserved = readBit(bytes, size, pos)
    if reserved != 0:
      return false
  let showExisting = readBit(bytes, size, pos)
  if showExisting != 0:
    return false
  return readBit(bytes, size, pos) == 0

proc scanGops(input: InputContainer, stream: ptr AVStream, fps: AVRational):
    tuple[keyframes: seq[int64], sourceEnd: int64] =
  while av_read_frame(input.formatContext, input.packet) >= 0:
    let packet = input.packet
    if packet.stream_index == stream.index and packet.pts != AV_NOPTS_VALUE:
      let frame = frameAt(packet.pts, stream.time_base, fps)
      result.sourceEnd = max(result.sourceEnd, frame + 1)
      if (packet.flags and AV_PKT_FLAG_KEY) != 0 and
          vp9IsKeyframe(packet.data, packet.size.int):
        result.keyframes.add frame
    av_packet_unref(packet)

  result.keyframes.sort()
  var write = 0
  for keyframe in result.keyframes:
    if write == 0 or result.keyframes[write - 1] != keyframe:
      result.keyframes[write] = keyframe
      inc write
  result.keyframes.setLen(write)

proc partialLosslessVp9Plan*(output: OutputContainer, tl: v3,
    args: mainArgs): seq[SmartSpan] =
  if args.noPartialLossless or args.scale != 1.0 or args.pixFmt != "" or
      args.vprofile != "":
    return @[]
  let encoder = initCodec(args.videoCodec)
  if encoder == nil or encoder.id != ID_VP9:
    return @[]
  if $output.formatCtx.oformat.name != "webm":
    return @[]
  if tl.v.len != 1 or tl.v[0].len == 0:
    return @[]

  let source = tl.v[0][0].src
  if source == nil:
    return @[]
  var expectedStart = 0'i64
  for clip in tl.v[0]:
    if clip.src != source or clip.stream != 0 or clip.start != expectedStart or
        not tl.effects[clip.effects].isEmpty:
      return @[]
    expectedStart = clip.start + clip.dur
  if expectedStart != tl.len:
    return @[]

  var input = try: av.open(source[])
              except IOError: return @[]
  defer: input.close()
  if input.video.len == 0:
    return @[]
  let stream = input.video[0]
  if stream.codecpar.codec_id != ID_VP9 or
      stream.codecpar.width != tl.res[0] or
      stream.codecpar.height != tl.res[1] or
      stream.codecpar.format != AV_PIX_FMT_YUV420P.cint or
      not stream.avg_frame_rate.isValid or stream.avg_frame_rate != tl.tb:
    return @[]

  let (keyframes, sourceEnd) = scanGops(input, stream, tl.tb)
  for clip in tl.v[0]:
    if clip.offset < 0 or clip.offset >= sourceEnd or
        clip.offset + clip.dur > sourceEnd + 1:
      return @[]
  let plan = smartRenderPlan(tl.v[0], keyframes, sourceEnd)
  let stats = smartPlanStats(plan)
  let averageGop = averageGopFrames(keyframes, sourceEnd)
  if not smartPlanIsWorthwhile(stats, tl.len, sourceEnd, averageGop):
    debug &"Skipping VP9 partial-lossless rendering: copying {stats.copiedFrames}/{tl.len} frames across {plan.len} spans would not offset {stats.encodeRuns} encoder runs"
    return @[]
  return plan

proc initPartialVp9Encoder(args: mainArgs, par: ptr AVCodecParameters,
    frameTb, fps: AVRational): ptr AVCodecContext =
  var (_, encoder) = initEncoder(args.videoCodec)
  encoder.width = par.width
  encoder.height = par.height
  encoder.pix_fmt = AVPixelFormat(par.format)
  encoder.time_base = frameTb
  encoder.framerate = fps
  encoder.sample_aspect_ratio = par.sample_aspect_ratio
  encoder.color_range = par.color_range
  encoder.color_primaries = par.color_primaries
  encoder.color_trc = par.color_trc
  encoder.colorspace = par.color_space
  encoder.profile = par.profile
  encoder.bit_rate = max(par.bit_rate * 6 div 5, 1_000_000)
  encoder.applyPartialEncoderArgs(args)
  encoder.open()
  return encoder

proc makePartialLosslessVp9*(output: var OutputContainer, tl: v3,
    args: mainArgs, spans: seq[SmartSpan]):
    (ptr AVStream, iterator(): (ptr AVPacket, int64)) =
  let sourcePath = tl.v[0][0].src[]
  var templateInput = try: av.open(sourcePath)
                      except IOError as e: error e.msg
  let sourceStream = templateInput.video[0]
  let stats = smartPlanStats(spans)
  if stats.copiedFrames == 0:
    templateInput.close()
    error "Partial-lossless VP9 renderer selected without a complete GOP"

  let outputStream = output.addStreamFromTemplate(sourceStream)
  if sourceStream.metadata != nil:
    discard av_dict_copy(addr outputStream.metadata, sourceStream.metadata, 0)
  outputStream.time_base = sourceStream.time_base
  outputStream.avg_frame_rate = tl.tb
  outputStream.duration = av_rescale_q(tl.len, av_inv_q(tl.tb),
      outputStream.time_base)
  templateInput.close()

  debug &"Using VP9 partial-lossless rendering: copying {stats.copiedFrames}/{tl.len} frames across {spans.len} spans and {stats.encodeRuns} encoder runs"

  return (outputStream, iterator(): (ptr AVPacket, int64) =
    let frameTb = av_inv_q(tl.tb)
    var input = try: av.open(sourcePath)
                except IOError as e: error e.msg
    defer: input.close()
    let stream = input.video[0]

    var decoder: ptr AVCodecContext = nil
    var frame: ptr AVFrame = nil
    var packet: ptr AVPacket = nil
    if stats.encodeSpans > 0:
      decoder = initDecoder(stream.codecpar)
      frame = av_frame_alloc()
      packet = av_packet_alloc()
      if frame == nil or packet == nil:
        error "Could not allocate partial-lossless VP9 frame/packet"
    defer:
      if packet != nil: av_packet_free(addr packet)
      if frame != nil: av_frame_free(addr frame)
      if decoder != nil: avcodec_free_context(addr decoder)

    var encoder: ptr AVCodecContext = nil
    var firstFrameInRun = false

    for spanIndex, span in spans:
      if span.kind == ssCopy:
        let seekTs = av_rescale_q(span.srcStart, frameTb, stream.time_base)
        input.seek(seekTs, stream = stream)
        var first = true
        while av_read_frame(input.formatContext, input.packet) >= 0:
          let sourcePacket = input.packet
          if sourcePacket.stream_index != stream.index or
              sourcePacket.pts == AV_NOPTS_VALUE:
            av_packet_unref(sourcePacket)
            continue
          let sourceFrame = frameAt(sourcePacket.pts, stream.time_base, tl.tb)
          if sourceFrame >= span.srcEnd:
            av_packet_unref(sourcePacket)
            break
          if sourceFrame < span.srcStart:
            av_packet_unref(sourcePacket)
            continue
          if first and ((sourcePacket.flags and AV_PKT_FLAG_KEY) == 0 or
              not vp9IsKeyframe(sourcePacket.data, sourcePacket.size.int)):
            av_packet_unref(sourcePacket)
            continue
          first = false
          let outPacket = av_packet_clone(sourcePacket)
          if outPacket == nil:
            error "Could not clone VP9 packet"
          let sourceBase = av_rescale_q(span.srcStart, frameTb,
              stream.time_base)
          let outputBase = av_rescale_q(span.outStart, frameTb,
              stream.time_base)
          let shift = outputBase - sourceBase
          if outPacket.pts != AV_NOPTS_VALUE: outPacket.pts += shift
          if outPacket.dts != AV_NOPTS_VALUE: outPacket.dts += shift
          outPacket.time_base = stream.time_base
          outPacket.stream_index = outputStream.index
          let orderTs = if outPacket.dts != AV_NOPTS_VALUE:
              outPacket.dts else: outPacket.pts
          let orderFrame = max(0'i64,
            frameAt(orderTs, stream.time_base, tl.tb))
          av_packet_unref(sourcePacket)
          yield (outPacket, orderFrame)
      else:
        if encoder == nil:
          encoder = initPartialVp9Encoder(args, stream.codecpar, frameTb, tl.tb)
          firstFrameInRun = true

        let seekTs = av_rescale_q(span.srcStart, frameTb, stream.time_base)
        input.seek(seekTs, stream = stream)
        avcodec_flush_buffers(decoder)
        var encoded = 0'i64
        var lastDecoded: ptr AVFrame = nil
        for decoded in input.flushDecode(stream.index, decoder, frame):
          let sourceFrame = int64(round(
            decoded.time(stream.time_base) * float(tl.tb)))
          if sourceFrame < span.srcStart:
            continue
          if sourceFrame >= span.srcEnd:
            break
          if lastDecoded != nil:
            av_frame_free(addr lastDecoded)
          lastDecoded = av_frame_clone(decoded)
          decoded.pts = span.outStart + encoded
          decoded.time_base = frameTb
          decoded.duration = 1
          decoded.pict_type = if firstFrameInRun:
              AV_PICTURE_TYPE_I else: AV_PICTURE_TYPE_NONE
          firstFrameInRun = false
          for encodedPacket in encoder.encode(decoded, packet):
            let outPacket = av_packet_clone(encodedPacket)
            if outPacket == nil:
              error "Could not clone encoded VP9 packet"
            outPacket.time_base = encoder.time_base
            outPacket.stream_index = outputStream.index
            let orderTs = if outPacket.dts != AV_NOPTS_VALUE:
                outPacket.dts else: outPacket.pts
            yield (outPacket, max(0'i64, orderTs))
            av_packet_unref(encodedPacket)
          inc encoded

        while encoded < span.srcEnd - span.srcStart and lastDecoded != nil:
          let held = av_frame_clone(lastDecoded)
          held.pts = span.outStart + encoded
          held.time_base = frameTb
          held.duration = 1
          held.pict_type = AV_PICTURE_TYPE_NONE
          for encodedPacket in encoder.encode(held, packet):
            let outPacket = av_packet_clone(encodedPacket)
            if outPacket == nil:
              error "Could not clone held VP9 packet"
            outPacket.time_base = encoder.time_base
            outPacket.stream_index = outputStream.index
            let orderTs = if outPacket.dts != AV_NOPTS_VALUE:
                outPacket.dts else: outPacket.pts
            yield (outPacket, max(0'i64, orderTs))
            av_packet_unref(encodedPacket)
          av_frame_free(addr held)
          inc encoded

        if lastDecoded != nil:
          av_frame_free(addr lastDecoded)

        let endsRun = spanIndex + 1 == spans.len or
          spans[spanIndex + 1].kind == ssCopy
        if endsRun:
          for encodedPacket in encoder.encode(nil, packet):
            let outPacket = av_packet_clone(encodedPacket)
            if outPacket == nil:
              error "Could not clone flushed VP9 packet"
            outPacket.time_base = encoder.time_base
            outPacket.stream_index = outputStream.index
            let orderTs = if outPacket.dts != AV_NOPTS_VALUE:
                outPacket.dts else: outPacket.pts
            yield (outPacket, max(0'i64, orderTs))
            av_packet_unref(encodedPacket)
          avcodec_free_context(addr encoder)
  )
