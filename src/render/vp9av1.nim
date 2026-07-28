import std/[strformat, strutils]
from std/math import round

import ../[av, ffmpeg, log, timeline]
import ../util/rational
import ./smart

func frameAt(ts: int64, tb, fps: AVRational): int64 =
  int64(round(float(ts) * float(tb) * float(fps)))

func readBit(data: ptr UncheckedArray[uint8], size: int, pos: var int): int =
  if pos >= size * 8:
    return -1
  result = int((data[pos shr 3] shr (7 - (pos and 7))) and 1)
  inc pos

func vp9IsKeyframe*(data: ptr uint8, size: int): bool =
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

func packetIsCopyBoundary(codecId: AVCodecID, data: ptr uint8, size: int): bool =
  ## FFmpeg's AV1 parser marks only independently decodable packets as key.
  ## VP9's container flag is less strict, so also inspect its frame header.
  codecId == ID_AV1 or (codecId == ID_VP9 and vp9IsKeyframe(data, size))

func codecLabel(codecId: AVCodecID): string =
  ($avcodec_get_name(codecId)).toUpperAscii

proc initPartialEncoder(args: mainArgs, par: ptr AVCodecParameters,
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
  # SVT-AV1 rejects CRF mode when a target bitrate is also configured. The
  # bitrate above is only an automatic fallback, so do not let it conflict
  # with an explicit quality target.
  if encoder.codec_id == ID_AV1 and args.crf >= 0 and args.videoBitrate < 0:
    encoder.bit_rate = 0
  resolveEncoderContext(encoder)
  encoder.applyPartialEncoderArgs(args)
  encoder.open()
  return encoder

proc makePartialLossless*(output: var OutputContainer, tl: v3, args: mainArgs,
    spans: seq[SmartSpan], codecId: AVCodecID):
    (ptr AVStream, iterator(): (ptr AVPacket, int64)) =
  let codecLabel = codecId.codecLabel
  let sourcePath = tl.v[0][0].src[]
  var templateInput = try: av.open(sourcePath) except IOError as e: error e.msg
  let sourceStream = templateInput.video[0]
  let stats = smartPlanStats(spans)
  if stats.copiedFrames == 0:
    templateInput.close()
    error &"Partial-lossless {codecLabel} renderer selected without a complete GOP"

  let outputStream = output.addStreamFromTemplate(sourceStream)
  if sourceStream.metadata != nil:
    discard av_dict_copy(addr outputStream.metadata, sourceStream.metadata, 0)
  outputStream.time_base = sourceStream.time_base
  outputStream.avg_frame_rate = tl.tb
  outputStream.duration = av_rescale_q(tl.len, av_inv_q(tl.tb), outputStream.time_base)
  templateInput.close()

  debug &"Using {codecLabel} partial-lossless rendering: copying {stats.copiedFrames}/{tl.len} frames across {spans.len} spans and {stats.encodeRuns} encoder runs"

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
        error &"Could not allocate partial-lossless {codecLabel} frame/packet"
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
              not packetIsCopyBoundary(codecId, sourcePacket.data,
                sourcePacket.size.int)):
            av_packet_unref(sourcePacket)
            continue
          first = false
          let outPacket = av_packet_clone(sourcePacket)
          if outPacket == nil:
            error &"Could not clone {codecLabel} packet"
          let sourceBase = av_rescale_q(span.srcStart, frameTb, stream.time_base)
          let outputBase = av_rescale_q(span.outStart, frameTb, stream.time_base)
          let shift = outputBase - sourceBase
          if outPacket.pts != AV_NOPTS_VALUE: outPacket.pts += shift
          if outPacket.dts != AV_NOPTS_VALUE: outPacket.dts += shift
          outPacket.time_base = stream.time_base
          outPacket.stream_index = outputStream.index
          let orderTs =
            if outPacket.dts != AV_NOPTS_VALUE: outPacket.dts
            else: outPacket.pts
          let orderFrame = max(0'i64, frameAt(orderTs, stream.time_base, tl.tb))
          av_packet_unref(sourcePacket)
          yield (outPacket, orderFrame)
      else:
        if encoder == nil:
          encoder = initPartialEncoder(args, stream.codecpar, frameTb, tl.tb)
          firstFrameInRun = true

        let seekTs = av_rescale_q(span.srcStart, frameTb, stream.time_base)
        input.seek(seekTs, stream = stream)
        avcodec_flush_buffers(decoder)
        var encoded = 0'i64
        var lastDecoded: ptr AVFrame = nil
        for decoded in input.flushDecode(stream.index, decoder, frame):
          let sourceFrame = int64(round(decoded.time(stream.time_base) * float(tl.tb)))
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
          decoded.pict_type =
            if firstFrameInRun: AV_PICTURE_TYPE_I
            else: AV_PICTURE_TYPE_NONE
          firstFrameInRun = false
          for encodedPacket in encoder.encode(decoded, packet):
            let outPacket = av_packet_clone(encodedPacket)
            if outPacket == nil:
              error &"Could not clone encoded {codecLabel} packet"
            outPacket.time_base = encoder.time_base
            outPacket.stream_index = outputStream.index
            let orderTs =
              if outPacket.dts != AV_NOPTS_VALUE: outPacket.dts
              else: outPacket.pts
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
              error &"Could not clone held {codecLabel} packet"
            outPacket.time_base = encoder.time_base
            outPacket.stream_index = outputStream.index
            let orderTs =
              if outPacket.dts != AV_NOPTS_VALUE: outPacket.dts
              else: outPacket.pts
            yield (outPacket, max(0'i64, orderTs))
            av_packet_unref(encodedPacket)
          av_frame_free(addr held)
          inc encoded

        if lastDecoded != nil:
          av_frame_free(addr lastDecoded)

        let endsRun = spanIndex + 1 == spans.len or spans[spanIndex + 1].kind == ssCopy
        if endsRun:
          for encodedPacket in encoder.encode(nil, packet):
            let outPacket = av_packet_clone(encodedPacket)
            if outPacket == nil:
              error &"Could not clone flushed {codecLabel} packet"
            outPacket.time_base = encoder.time_base
            outPacket.stream_index = outputStream.index
            let orderTs =
              if outPacket.dts != AV_NOPTS_VALUE: outPacket.dts
              else: outPacket.pts
            yield (outPacket, max(0'i64, orderTs))
            av_packet_unref(encodedPacket)
          avcodec_free_context(addr encoder)
  )
