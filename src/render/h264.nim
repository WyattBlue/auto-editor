import std/[strformat, strutils]
from std/math import round

import ../[av, ffmpeg, log, timeline]
import ../util/rational
import smart

func startCodeLen(data: ptr UncheckedArray[uint8], size, pos: int): int =
  if pos + 3 <= size and data[pos] == 0 and data[pos + 1] == 0:
    if data[pos + 2] == 1:
      return 3
    if pos + 4 <= size and data[pos + 2] == 0 and data[pos + 3] == 1:
      return 4
  0

proc appendNal(result: var seq[uint8], data: ptr UncheckedArray[uint8],
    first, last: int) =
  let size = last - first
  if size <= 0:
    return
  result.add uint8(size shr 24)
  result.add uint8(size shr 16)
  result.add uint8(size shr 8)
  result.add uint8(size)
  for i in first..<last:
    result.add data[i]

proc annexBToAvcc(data: ptr uint8, size: int): seq[uint8] =
  let bytes = cast[ptr UncheckedArray[uint8]](data)
  var pos = 0
  while pos < size and startCodeLen(bytes, size, pos) == 0:
    inc pos
  if pos == size:
    result.setLen(size)
    if size > 0:
      copyMem(addr result[0], data, size)
    return

  while pos < size:
    let codeLen = startCodeLen(bytes, size, pos)
    if codeLen == 0:
      inc pos
      continue
    let nalStart = pos + codeLen
    var next = nalStart
    while next < size and startCodeLen(bytes, size, next) == 0:
      inc next
    result.appendNal(bytes, nalStart, next)
    pos = next

proc parameterSetsToAvcc(data: ptr uint8, size: int): seq[uint8] =
  if data == nil or size <= 0:
    return @[]
  let bytes = cast[ptr UncheckedArray[uint8]](data)
  if bytes[0] != 1:
    return annexBToAvcc(data, size)
  if size < 7:
    return @[]

  var pos = 6
  let spsCount = int(bytes[5] and 0x1f)
  for _ in 0..<spsCount:
    if pos + 2 > size: return @[]
    let nalLen = int(bytes[pos]) shl 8 or int(bytes[pos + 1])
    pos += 2
    if pos + nalLen > size: return @[]
    result.appendNal(bytes, pos, pos + nalLen)
    pos += nalLen
  if pos >= size:
    return
  let ppsCount = int(bytes[pos])
  inc pos
  for _ in 0..<ppsCount:
    if pos + 2 > size: return @[]
    let nalLen = int(bytes[pos]) shl 8 or int(bytes[pos + 1])
    pos += 2
    if pos + nalLen > size: return @[]
    result.appendNal(bytes, pos, pos + nalLen)
    pos += nalLen

proc normalizeAvcc(packet: ptr AVPacket, parameterSets: openArray[uint8]) =
  let bytes = cast[ptr UncheckedArray[uint8]](packet.data)
  var start = 0
  while start < packet.size.int and
      startCodeLen(bytes, packet.size.int, start) == 0:
    inc start
  if start == packet.size.int and parameterSets.len == 0:
    return

  let payload = annexBToAvcc(packet.data, packet.size.int)
  let pts = packet.pts
  let dts = packet.dts
  let duration = packet.duration
  let flags = packet.flags
  let streamIndex = packet.stream_index
  let timeBase = packet.time_base
  av_packet_unref(packet)
  let total = parameterSets.len + payload.len
  if av_new_packet(packet, total.cint) < 0:
    error "Could not allocate normalized H.264 packet"
  if parameterSets.len > 0:
    copyMem(packet.data, unsafeAddr parameterSets[0], parameterSets.len)
  if payload.len > 0:
    copyMem(cast[pointer](cast[int](packet.data) + parameterSets.len),
      unsafeAddr payload[0], payload.len)
  packet.pts = pts
  packet.dts = dts
  packet.duration = duration
  packet.flags = flags
  packet.stream_index = streamIndex
  packet.time_base = timeBase

func frameAt(ts: int64, tb, fps: AVRational): int64 =
  int64(round(float(ts) * float(tb) * float(fps)))

func h264IsCopyBoundary*(data: ptr uint8, size: int): bool =
  let bytes = cast[ptr UncheckedArray[uint8]](data)
  var pos = 0
  let annexB = size >= 3 and startCodeLen(bytes, size, 0) > 0
  while pos < size:
    if annexB:
      let codeLen = startCodeLen(bytes, size, pos)
      if codeLen == 0:
        inc pos
        continue
      let nal = pos + codeLen
      if nal < size and (bytes[nal] and 0x1f) == 5:
        return true
      pos = nal + 1
    else:
      if pos + 4 > size:
        break
      let nalLen = int(bytes[pos]) shl 24 or int(bytes[pos + 1]) shl 16 or
        int(bytes[pos + 2]) shl 8 or int(bytes[pos + 3])
      pos += 4
      if nalLen <= 0 or pos + nalLen > size:
        return false
      if (bytes[pos] and 0x1f) == 5:
        return true
      pos += nalLen
  return false

func h264SupportsPartialLossless*(stream: ptr AVStream): bool =
  if stream.codecpar.format != AV_PIX_FMT_YUV420P.cint:
    return false
  # Smart-rendered samples are normalized to four-byte AVCC. Match that to the
  # source's avcC length-size field rather than silently mixing layouts.
  let extra = stream.codecpar.extradata
  if extra == nil or stream.codecpar.extradata_size < 5 or extra[] != 1 or
      (cast[ptr UncheckedArray[uint8]](extra)[4] and 3) != 3:
    return false
  parameterSetsToAvcc(extra, stream.codecpar.extradata_size).len > 0

proc initPartialH264Encoder(args: mainArgs, par: ptr AVCodecParameters,
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
  encoder.max_b_frames = max(par.video_delay, 0)
  encoder.bit_rate = max(par.bit_rate * 6 div 5, 1_000_000)
  encoder.flags |= AV_CODEC_FLAG_GLOBAL_HEADER
  resolveEncoderContext(encoder)
  encoder.applyPartialEncoderArgs(args)
  encoder.open()
  return encoder

proc makePartialLosslessH264*(output: var OutputContainer, tl: v3,
    args: mainArgs, spans: seq[SmartSpan]):
    (ptr AVStream, iterator(): (ptr AVPacket, int64)) =
  let sourcePath = tl.v[0][0].src[]
  var templateInput = try: av.open(sourcePath)
                      except IOError as e: error e.msg
  let sourceStream = templateInput.video[0]
  let sourceParameterSets = parameterSetsToAvcc(sourceStream.codecpar.extradata,
    sourceStream.codecpar.extradata_size)

  let stats = smartPlanStats(spans)
  if stats.copiedFrames == 0:
    templateInput.close()
    error "Partial-lossless H.264 renderer selected without a complete GOP"

  let outputStream = output.addStreamFromTemplate(sourceStream)
  if sourceStream.metadata != nil:
    discard av_dict_copy(addr outputStream.metadata, sourceStream.metadata, 0)
  outputStream.time_base = sourceStream.time_base
  outputStream.avg_frame_rate = tl.tb
  outputStream.duration = av_rescale_q(tl.len, av_inv_q(tl.tb),
      outputStream.time_base)
  if "matroska" notin $output.formatCtx.oformat.name:
    # QuickTime's file player expects the conventional avc1 sample entry. Keep
    # the boundary SPS/PPS in-band so decoders can still switch between copied
    # and re-encoded GOPs without changing the track's sample description.
    outputStream.codecpar.codec_tag = fourccToInt("avc1")
  templateInput.close()

  debug &"Using H.264 partial-lossless rendering: copying {stats.copiedFrames}/{tl.len} frames across {spans.len} spans and {stats.encodeRuns} encoder runs"

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
        error "Could not allocate partial-lossless H.264 frame/packet"
    defer:
      if packet != nil: av_packet_free(addr packet)
      if frame != nil: av_frame_free(addr frame)
      if decoder != nil: avcodec_free_context(addr decoder)

    var encoder: ptr AVCodecContext = nil
    var encodedParameterSets: seq[uint8] = @[]
    var firstPacket = false
    var firstFrameInRun = false

    for spanIndex, span in spans:
      if span.kind == ssCopy:
        let seekTs = av_rescale_q(span.srcStart, frameTb, stream.time_base)
        input.seek(seekTs, stream = stream)
        var first = true
        var shift = 0'i64
        while av_read_frame(input.formatContext, input.packet) >= 0:
          let packet = input.packet
          if packet.stream_index != stream.index or packet.pts == AV_NOPTS_VALUE:
            av_packet_unref(packet)
            continue
          let sourceFrame = frameAt(packet.pts, stream.time_base, tl.tb)
          if sourceFrame >= span.srcEnd:
            av_packet_unref(packet)
            break
          if sourceFrame < span.srcStart:
            av_packet_unref(packet)
            continue
          if first and (packet.flags and AV_PKT_FLAG_KEY) == 0:
            av_packet_unref(packet)
            continue
          let firstPacket = first
          first = false
          let outPacket = av_packet_clone(packet)
          if outPacket == nil:
            error "Could not clone H.264 packet"
          if firstPacket:
            let outputBase = av_rescale_q(span.outStart, frameTb,
                stream.time_base)
            # Matroska can carry a constant sub-frame timestamp offset. Anchor
            # the GOP to its actual key packet instead of preserving that input
            # offset between re-encoded and copied regions.
            shift = outputBase - outPacket.pts
          if outPacket.pts != AV_NOPTS_VALUE: outPacket.pts += shift
          if outPacket.dts != AV_NOPTS_VALUE: outPacket.dts += shift
          outPacket.time_base = stream.time_base
          outPacket.stream_index = outputStream.index
          if firstPacket:
            outPacket.normalizeAvcc(sourceParameterSets)
          let orderTs =
            if outPacket.dts != AV_NOPTS_VALUE: outPacket.dts
            else: outPacket.pts
          let orderFrame = max(0'i64, frameAt(orderTs, stream.time_base, tl.tb))
          av_packet_unref(packet)
          yield (outPacket, orderFrame)
      else:
        if encoder == nil:
          encoder = initPartialH264Encoder(args, stream.codecpar, frameTb, tl.tb)
          encodedParameterSets = parameterSetsToAvcc(encoder.extradata,
            encoder.extradata_size)
          if encodedParameterSets.len == 0:
            error "H.264 encoder did not provide SPS/PPS for partial-lossless rendering"
          firstPacket = true
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
              error "Could not clone encoded H.264 packet"
            outPacket.flags = outPacket.flags and not AV_PKT_FLAG_DISCARD
            outPacket.time_base = encoder.time_base
            outPacket.stream_index = outputStream.index
            outPacket.normalizeAvcc(if firstPacket: encodedParameterSets else: @[])
            firstPacket = false
            let orderTs =
              if outPacket.dts != AV_NOPTS_VALUE: outPacket.dts
              else: outPacket.pts
            yield (outPacket, max(0'i64, orderTs))
            av_packet_unref(encodedPacket)
          inc encoded

        # Container duration rounding can leave the timeline one frame longer
        # than the final decoded timestamp. Match the normal renderer by holding
        # the last picture for that final timeline frame.
        while encoded < span.srcEnd - span.srcStart and lastDecoded != nil:
          let held = av_frame_clone(lastDecoded)
          held.pts = span.outStart + encoded
          held.time_base = frameTb
          held.duration = 1
          held.pict_type = AV_PICTURE_TYPE_NONE
          for encodedPacket in encoder.encode(held, packet):
            let outPacket = av_packet_clone(encodedPacket)
            if outPacket == nil:
              error "Could not clone held H.264 packet"
            outPacket.flags = outPacket.flags and not AV_PKT_FLAG_DISCARD
            outPacket.time_base = encoder.time_base
            outPacket.stream_index = outputStream.index
            outPacket.normalizeAvcc(if firstPacket: encodedParameterSets else: @[])
            firstPacket = false
            let orderTs =
              if outPacket.dts != AV_NOPTS_VALUE: outPacket.dts
              else: outPacket.pts
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
              error "Could not clone flushed H.264 packet"
            outPacket.flags = outPacket.flags and not AV_PKT_FLAG_DISCARD
            outPacket.time_base = encoder.time_base
            outPacket.stream_index = outputStream.index
            outPacket.normalizeAvcc(if firstPacket: encodedParameterSets else: @[])
            firstPacket = false
            let orderTs =
              if outPacket.dts != AV_NOPTS_VALUE: outPacket.dts
              else: outPacket.pts
            yield (outPacket, max(0'i64, orderTs))
            av_packet_unref(encodedPacket)
          avcodec_free_context(addr encoder)
  )
