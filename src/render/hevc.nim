import std/[algorithm, strformat, strutils]
from std/math import round

import ../[action, av, ffmpeg, log, timeline]
import ../util/rational
import ./smart

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

func nalType(data: ptr UncheckedArray[uint8], pos, size: int): int =
  if pos >= size: -1 else: int((data[pos] shr 1) and 0x3f)

proc annexBParameterSets(data: ptr uint8, size: int): seq[uint8] =
  let bytes = cast[ptr UncheckedArray[uint8]](data)
  var pos = 0
  while pos < size:
    let codeLen = startCodeLen(bytes, size, pos)
    if codeLen == 0:
      inc pos
      continue
    let nalStart = pos + codeLen
    var next = nalStart
    while next < size and startCodeLen(bytes, size, next) == 0:
      inc next
    if bytes.nalType(nalStart, size) in 32..34:
      result.appendNal(bytes, nalStart, next)
    pos = next

proc annexBToLengthPrefixed(data: ptr uint8, size: int): seq[uint8] =
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

proc parameterSetsToHvcc*(data: ptr uint8, size: int): seq[uint8] =
  ## Return VPS/SPS/PPS NAL units with four-byte lengths. Encoder extradata is
  ## commonly Annex B, while an MP4/Matroska source normally carries hvcC.
  if data == nil or size <= 0:
    return @[]
  let bytes = cast[ptr UncheckedArray[uint8]](data)
  if bytes[0] != 1:
    return annexBParameterSets(data, size)
  if size < 23:
    return @[]

  var pos = 23
  let arrayCount = int(bytes[22])
  for _ in 0..<arrayCount:
    if pos + 3 > size:
      return @[]
    let typ = int(bytes[pos] and 0x3f)
    let nalCount = int(bytes[pos + 1]) shl 8 or int(bytes[pos + 2])
    pos += 3
    for _ in 0..<nalCount:
      if pos + 2 > size:
        return @[]
      let nalLen = int(bytes[pos]) shl 8 or int(bytes[pos + 1])
      pos += 2
      if nalLen <= 0 or pos + nalLen > size:
        return @[]
      if typ in 32..34:
        result.appendNal(bytes, pos, pos + nalLen)
      pos += nalLen

func hasRequiredParameterSets*(data: openArray[uint8]): bool =
  var found = [false, false, false]
  var pos = 0
  while pos + 4 <= data.len:
    let nalLen = int(data[pos]) shl 24 or int(data[pos + 1]) shl 16 or
      int(data[pos + 2]) shl 8 or int(data[pos + 3])
    pos += 4
    if nalLen <= 0 or pos + nalLen > data.len:
      return false
    let typ = int((data[pos] shr 1) and 0x3f)
    if typ in 32..34:
      found[typ - 32] = true
    pos += nalLen
  pos == data.len and found[0] and found[1] and found[2]

proc normalizeHvcc(packet: ptr AVPacket, parameterSets: openArray[uint8]) =
  let bytes = cast[ptr UncheckedArray[uint8]](packet.data)
  var start = 0
  while start < packet.size.int and
      startCodeLen(bytes, packet.size.int, start) == 0:
    inc start
  if start == packet.size.int and parameterSets.len == 0:
    return

  let payload = annexBToLengthPrefixed(packet.data, packet.size.int)
  let pts = packet.pts
  let dts = packet.dts
  let duration = packet.duration
  let flags = packet.flags
  let streamIndex = packet.stream_index
  let timeBase = packet.time_base
  av_packet_unref(packet)
  let total = parameterSets.len + payload.len
  if av_new_packet(packet, total.cint) < 0:
    error "Could not allocate normalized HEVC packet"
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

func hevcNalIsCopyBoundary*(typ: int): bool =
  typ in 16..20

func hasRandomAccessPoint(data: ptr uint8, size: int): bool =
  ## Only closed HEVC random-access pictures are safe splice boundaries. CRA
  ## (type 21) may be followed in decode order by RASL pictures that display
  ## before it, so treating CRA as a complete-GOP boundary can drop frames.
  if data == nil or size <= 0:
    return false
  let bytes = cast[ptr UncheckedArray[uint8]](data)
  let annexB = size >= 3 and startCodeLen(bytes, size, 0) > 0
  var pos = 0
  while pos < size:
    if annexB:
      let codeLen = startCodeLen(bytes, size, pos)
      if codeLen == 0:
        inc pos
        continue
      let nal = pos + codeLen
      let typ = bytes.nalType(nal, size)
      if typ.hevcNalIsCopyBoundary:
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
      let typ = bytes.nalType(pos, size)
      if typ.hevcNalIsCopyBoundary:
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
          hasRandomAccessPoint(packet.data, packet.size.int):
        result.keyframes.add frame
    av_packet_unref(packet)

  result.keyframes.sort()
  var write = 0
  for keyframe in result.keyframes:
    if write == 0 or result.keyframes[write - 1] != keyframe:
      result.keyframes[write] = keyframe
      inc write
  result.keyframes.setLen(write)

func encoderSupports(encoder: ptr AVCodec, format: AVPixelFormat): bool =
  if encoder == nil:
    return false
  if encoder.pix_fmts == nil:
    return true
  var i = 0
  while encoder.pix_fmts[i] != AV_PIX_FMT_NONE:
    if encoder.pix_fmts[i] == format:
      return true
    inc i
  false

proc partialLosslessHevcPlan*(output: OutputContainer, tl: v3,
    args: mainArgs): seq[SmartSpan] =
  ## Only timing- and pixel-preserving edits qualify. Complete IRAP-delimited
  ## GOPs are copied; partial GOPs at edit boundaries are re-encoded.
  if args.noPartialLossless or args.scale != 1.0 or args.pixFmt != "" or
      args.vprofile != "":
    return @[]
  let encoder = initCodec(args.videoCodec)
  if encoder == nil or encoder.id != ID_HEVC:
    return @[]
  let formatName = $output.formatCtx.oformat.name
  let isIsoBmff = "mp4" in formatName or "mov" in formatName
  let isMatroska = "matroska" in formatName
  if not isIsoBmff and not isMatroska:
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
  if stream.codecpar.codec_id != ID_HEVC or
      stream.codecpar.width != tl.res[0] or stream.codecpar.height != tl.res[1] or
      not encoder.encoderSupports(AVPixelFormat(stream.codecpar.format)) or
      not stream.avg_frame_rate.isValid or stream.avg_frame_rate != tl.tb:
    return @[]

  # Partial-lossless samples are normalized to four-byte lengths. hvcC stores
  # lengthSizeMinusOne in byte 21; reject sources that declare another size.
  let extra = stream.codecpar.extradata
  if extra == nil or stream.codecpar.extradata_size < 23 or extra[] != 1 or
      (cast[ptr UncheckedArray[uint8]](extra)[21] and 3) != 3:
    return @[]
  let sourceParameterSets = parameterSetsToHvcc(extra,
    stream.codecpar.extradata_size)
  if not sourceParameterSets.hasRequiredParameterSets:
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
    debug &"Skipping HEVC partial-lossless rendering: copying {stats.copiedFrames}/{tl.len} frames across {plan.len} spans would not offset {stats.encodeRuns} encoder runs"
    return @[]
  return plan

proc initPartialHevcEncoder(args: mainArgs, par: ptr AVCodecParameters,
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
  encoder.applyPartialEncoderArgs(args)
  encoder.open()
  return encoder

proc makePartialLosslessHevc*(output: var OutputContainer, tl: v3,
    args: mainArgs, spans: seq[SmartSpan]):
    (ptr AVStream, iterator(): (ptr AVPacket, int64)) =
  let sourcePath = tl.v[0][0].src[]
  var templateInput = try: av.open(sourcePath)
                      except IOError as e: error e.msg
  let sourceStream = templateInput.video[0]
  let sourceParameterSets = parameterSetsToHvcc(sourceStream.codecpar.extradata,
    sourceStream.codecpar.extradata_size)
  let stats = smartPlanStats(spans)
  if stats.copiedFrames == 0:
    templateInput.close()
    error "Partial-lossless HEVC renderer selected without a complete GOP"

  let outputStream = output.addStreamFromTemplate(sourceStream)
  if sourceStream.metadata != nil:
    discard av_dict_copy(addr outputStream.metadata, sourceStream.metadata, 0)
  outputStream.time_base = sourceStream.time_base
  outputStream.avg_frame_rate = tl.tb
  outputStream.duration = av_rescale_q(tl.len, av_inv_q(tl.tb),
      outputStream.time_base)
  if "matroska" notin $output.formatCtx.oformat.name:
    # Mixed copied and re-encoded regions carry boundary VPS/SPS/PPS in-band.
    # `hev1` permits that; `hvc1` requires parameter sets to live only in hvcC.
    outputStream.codecpar.codec_tag = fourccToInt("hev1")
  templateInput.close()

  debug &"Using HEVC partial-lossless rendering: copying {stats.copiedFrames}/{tl.len} frames across {spans.len} spans and {stats.encodeRuns} encoder runs"

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
        error "Could not allocate partial-lossless HEVC frame/packet"
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
        var copied = 0'i64
        let reorderDelay = max(stream.codecpar.video_delay.int64, 0)
        while av_read_frame(input.formatContext, input.packet) >= 0:
          let sourcePacket = input.packet
          if sourcePacket.stream_index != stream.index or
              sourcePacket.pts == AV_NOPTS_VALUE:
            av_packet_unref(sourcePacket)
            continue
          let sourceFrame = frameAt(sourcePacket.pts, stream.time_base, tl.tb)
          # Stop at the next closed random-access picture, not merely at the
          # first packet whose presentation timestamp belongs to the next GOP.
          if sourceFrame >= span.srcEnd and
              hasRandomAccessPoint(sourcePacket.data, sourcePacket.size.int):
            av_packet_unref(sourcePacket)
            break
          if sourceFrame < span.srcStart or sourceFrame >= span.srcEnd:
            av_packet_unref(sourcePacket)
            continue
          if first and ((sourcePacket.flags and AV_PKT_FLAG_KEY) == 0 or
              not hasRandomAccessPoint(sourcePacket.data,
                  sourcePacket.size.int)):
            av_packet_unref(sourcePacket)
            continue
          let firstPacket = first
          first = false
          let outPacket = av_packet_clone(sourcePacket)
          if outPacket == nil:
            error "Could not clone HEVC packet"
          # Normalize copied timing to the CFR timeline. Rebuilding DTS in
          # decode order avoids carrying CRA/RASL preroll offsets across an
          # edit boundary and matches the encoder's configured reorder delay.
          outPacket.pts = span.outStart + sourceFrame - span.srcStart
          outPacket.dts = span.outStart - reorderDelay + copied
          outPacket.duration = 1
          outPacket.time_base = frameTb
          inc copied
          outPacket.stream_index = outputStream.index
          if firstPacket:
            outPacket.normalizeHvcc(sourceParameterSets)
          let orderTs = if outPacket.dts != AV_NOPTS_VALUE:
              outPacket.dts else: outPacket.pts
          let orderFrame = max(0'i64,
            frameAt(orderTs, stream.time_base, tl.tb))
          av_packet_unref(sourcePacket)
          yield (outPacket, orderFrame)
      else:
        if encoder == nil:
          encoder = initPartialHevcEncoder(args, stream.codecpar, frameTb, tl.tb)
          encodedParameterSets = parameterSetsToHvcc(encoder.extradata,
            encoder.extradata_size)
          if not encodedParameterSets.hasRequiredParameterSets:
            error "HEVC encoder did not provide VPS/SPS/PPS for partial-lossless rendering"
          firstPacket = true
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
              error "Could not clone encoded HEVC packet"
            outPacket.flags = outPacket.flags and not AV_PKT_FLAG_DISCARD
            outPacket.time_base = encoder.time_base
            outPacket.stream_index = outputStream.index
            outPacket.normalizeHvcc(if firstPacket: encodedParameterSets else: @[])
            firstPacket = false
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
              error "Could not clone held HEVC packet"
            outPacket.flags = outPacket.flags and not AV_PKT_FLAG_DISCARD
            outPacket.time_base = encoder.time_base
            outPacket.stream_index = outputStream.index
            outPacket.normalizeHvcc(if firstPacket: encodedParameterSets else: @[])
            firstPacket = false
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
              error "Could not clone flushed HEVC packet"
            outPacket.flags = outPacket.flags and not AV_PKT_FLAG_DISCARD
            outPacket.time_base = encoder.time_base
            outPacket.stream_index = outputStream.index
            outPacket.normalizeHvcc(if firstPacket: encodedParameterSets else: @[])
            firstPacket = false
            let orderTs = if outPacket.dts != AV_NOPTS_VALUE:
                outPacket.dts else: outPacket.pts
            yield (outPacket, max(0'i64, orderTs))
            av_packet_unref(encodedPacket)
          avcodec_free_context(addr encoder)
  )
