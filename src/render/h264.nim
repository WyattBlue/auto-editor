import std/[algorithm, strformat, strutils]
from std/math import round

import ../[action, av, ffmpeg, log, timeline]
import ../util/rational

type
  H264SpanKind* = enum
    hsEncode, hsCopy
  H264Span* = object
    kind*: H264SpanKind
    srcStart*, srcEnd*: int64
    outStart*: int64
  H264PlanStats* = object
    copiedFrames*, encodedFrames*: int64
    copySpans*, encodeSpans*, encodeRuns*: int

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

func hasIdr(data: ptr uint8, size: int): bool =
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

proc scanGops(input: InputContainer, stream: ptr AVStream, fps: AVRational):
    tuple[keyframes: seq[int64], sourceEnd: int64] =
  while av_read_frame(input.formatContext, input.packet) >= 0:
    let packet = input.packet
    if packet.stream_index == stream.index and packet.pts != AV_NOPTS_VALUE:
      let frame = frameAt(packet.pts, stream.time_base, fps)
      result.sourceEnd = max(result.sourceEnd, frame + 1)
      if (packet.flags and AV_PKT_FLAG_KEY) != 0 and
          hasIdr(packet.data, packet.size.int):
        result.keyframes.add frame
    av_packet_unref(packet)

  result.keyframes.sort()
  var write = 0
  for keyframe in result.keyframes:
    if write == 0 or result.keyframes[write - 1] != keyframe:
      result.keyframes[write] = keyframe
      inc write
  result.keyframes.setLen(write)

func addSpan(spans: var seq[H264Span], kind: H264SpanKind,
    srcStart, srcEnd, outStart: int64) =
  if srcEnd <= srcStart:
    return
  if spans.len > 0:
    let prev = spans[^1]
    let prevLen = prev.srcEnd - prev.srcStart
    if prev.kind == kind and prev.srcEnd == srcStart and
        prev.outStart + prevLen == outStart:
      spans[^1].srcEnd = srcEnd
      return
  spans.add H264Span(kind: kind, srcStart: srcStart, srcEnd: srcEnd,
    outStart: outStart)

func h264RenderPlan*(clips: openArray[Clip], keyframes: openArray[int64],
    sourceEnd: int64): seq[H264Span] =
  ## Copy only complete GOPs. The partial GOPs touching either side of an edit
  ## are re-encoded so the output still begins and ends on the requested frame.
  for clip in clips:
    let clipSrcEnd = clip.offset + clip.dur
    var cursor = clip.offset
    var i = lowerBound(keyframes, clip.offset)
    while i < keyframes.len:
      let keyframe = keyframes[i]
      if keyframe >= clipSrcEnd:
        break
      let gopEnd = if i + 1 < keyframes.len: keyframes[i + 1] else: sourceEnd
      let finalGopNeedsHold = i + 1 == keyframes.len and clipSrcEnd > sourceEnd
      if gopEnd > clipSrcEnd or gopEnd <= keyframe or
          finalGopNeedsHold:
        inc i
        continue
      result.addSpan(hsEncode, cursor, keyframe, clip.start + cursor - clip.offset)
      result.addSpan(hsCopy, keyframe, gopEnd,
        clip.start + keyframe - clip.offset)
      cursor = gopEnd
      inc i
    result.addSpan(hsEncode, cursor, clipSrcEnd,
      clip.start + cursor - clip.offset)

func h264PlanStats*(spans: openArray[H264Span]): H264PlanStats =
  var inEncodeRun = false
  for span in spans:
    let frames = span.srcEnd - span.srcStart
    case span.kind
    of hsCopy:
      result.copiedFrames += frames
      inc result.copySpans
      inEncodeRun = false
    of hsEncode:
      result.encodedFrames += frames
      inc result.encodeSpans
      if not inEncodeRun:
        inc result.encodeRuns
      inEncodeRun = true

func averageGopFrames(keyframes: openArray[int64], sourceEnd: int64): int64 =
  var frames, count = 0'i64
  for i, keyframe in keyframes:
    let gopEnd = if i + 1 < keyframes.len: keyframes[i + 1] else: sourceEnd
    if gopEnd > keyframe:
      frames += gopEnd - keyframe
      inc count
  if count == 0: return max(sourceEnd, 1)
  return max(frames div count, 1)

func h264PlanIsWorthwhile*(stats: H264PlanStats, timelineFrames,
    sourceFrames, averageGop: int64): bool =
  ## Estimate work in full-render frame equivalents. Demuxing the source is
  ## substantially cheaper than decoding and encoding it, while restarting an
  ## encoder costs about one GOP of useful work. Be conservative: the feature
  ## is primarily valuable when it can preserve a meaningful amount of video.
  if stats.copiedFrames <= 0 or timelineFrames <= 0:
    return false
  let scanCost = max(sourceFrames, 0) div 32
  let restartCost = int64(stats.encodeRuns) * max(averageGop, 1)
  return stats.encodedFrames + scanCost + restartCost < timelineFrames

proc partialLosslessH264Plan*(output: OutputContainer, tl: v3,
    args: mainArgs): seq[H264Span] =
  ## This path must be indistinguishable from the normal renderer except for
  ## compression. Anything that changes pixels, timing, or source topology uses
  ## the regular decode/filter/encode path.
  if args.noPartialLossless or args.videoCodec != "h264" or
      args.scale != 1.0 or args.pixFmt != "" or
      args.vprofile != "" or args.preset != "" or args.crf >= 0 or
      args.videoBitrate >= 0:
    return @[]
  let formatName = $output.formatCtx.oformat.name
  if "mp4" notin formatName and "mov" notin formatName:
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
  if stream.codecpar.codec_id != ID_H264 or
      stream.codecpar.width != tl.res[0] or stream.codecpar.height != tl.res[1] or
      stream.codecpar.format != AV_PIX_FMT_YUV420P.cint or
      not stream.avg_frame_rate.isValid or stream.avg_frame_rate != tl.tb:
    return @[]
  # Smart-rendered samples are normalized to four-byte AVCC. Match that to the
  # source's avcC length-size field rather than silently mixing layouts.
  let extra = stream.codecpar.extradata
  if extra == nil or stream.codecpar.extradata_size < 5 or extra[] != 1 or
      (cast[ptr UncheckedArray[uint8]](extra)[4] and 3) != 3:
    return @[]
  if parameterSetsToAvcc(extra, stream.codecpar.extradata_size).len == 0:
    return @[]
  let (keyframes, sourceEnd) = scanGops(input, stream, tl.tb)
  for clip in tl.v[0]:
    if clip.offset < 0 or clip.offset >= sourceEnd or
        clip.offset + clip.dur > sourceEnd + 1:
      return @[]
  let plan = h264RenderPlan(tl.v[0], keyframes, sourceEnd)
  let stats = plan.h264PlanStats
  let averageGop = averageGopFrames(keyframes, sourceEnd)
  if not stats.h264PlanIsWorthwhile(tl.len, sourceEnd, averageGop):
    debug &"Skipping H.264 partial-lossless rendering: copying {stats.copiedFrames}/{tl.len} frames across {plan.len} spans would not offset {stats.encodeRuns} encoder runs"
    return @[]
  return plan

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
  encoder.open()
  return encoder

proc makePartialLosslessH264*(output: var OutputContainer, tl: v3,
    args: mainArgs, spans: seq[H264Span]):
    (ptr AVStream, iterator(): (ptr AVPacket, int64)) =
  let sourcePath = tl.v[0][0].src[]
  var templateInput = try: av.open(sourcePath)
                      except IOError as e: error e.msg
  let sourceStream = templateInput.video[0]
  let sourceParameterSets = parameterSetsToAvcc(sourceStream.codecpar.extradata,
    sourceStream.codecpar.extradata_size)

  let stats = spans.h264PlanStats
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
  # avc3 explicitly permits SPS/PPS updates in media samples at smart-render
  # boundaries, unlike avc1 which assumes the sample description never changes.
  outputStream.codecpar.codec_tag = fourccToInt("avc3")
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
      if span.kind == hsCopy:
        let seekTs = av_rescale_q(span.srcStart, frameTb, stream.time_base)
        input.seek(seekTs, stream = stream)
        var first = true
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
          let sourceBase = av_rescale_q(span.srcStart, frameTb,
              stream.time_base)
          let outputBase = av_rescale_q(span.outStart, frameTb,
              stream.time_base)
          let shift = outputBase - sourceBase
          if outPacket.pts != AV_NOPTS_VALUE: outPacket.pts += shift
          if outPacket.dts != AV_NOPTS_VALUE: outPacket.dts += shift
          outPacket.time_base = stream.time_base
          outPacket.stream_index = outputStream.index
          if firstPacket:
            outPacket.normalizeAvcc(sourceParameterSets)
          let orderTs = if outPacket.dts !=
              AV_NOPTS_VALUE: outPacket.dts else: outPacket.pts
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
          decoded.pict_type = if firstFrameInRun:
              AV_PICTURE_TYPE_I else: AV_PICTURE_TYPE_NONE
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
            let orderTs = if outPacket.dts !=
                AV_NOPTS_VALUE: outPacket.dts else: outPacket.pts
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
            let orderTs = if outPacket.dts !=
                AV_NOPTS_VALUE: outPacket.dts else: outPacket.pts
            yield (outPacket, max(0'i64, orderTs))
            av_packet_unref(encodedPacket)
          av_frame_free(addr held)
          inc encoded

        if lastDecoded != nil:
          av_frame_free(addr lastDecoded)

        let endsRun = spanIndex + 1 == spans.len or
          spans[spanIndex + 1].kind == hsCopy
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
            let orderTs = if outPacket.dts !=
                AV_NOPTS_VALUE: outPacket.dts else: outPacket.pts
            yield (outPacket, max(0'i64, orderTs))
            av_packet_unref(encodedPacket)
          avcodec_free_context(addr encoder)
  )
