import std/[algorithm, strformat, strutils]
from std/math import round

import ../[action, av, ffmpeg, log, timeline]
import ../util/rational
import ./[h264, hevc, smart]

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

func isNalCodec(codecId: AVCodecID): bool =
  ## H.264 and HEVC carry parameter sets in NAL units, so copied and re-encoded
  ## regions have to agree on a length-prefixed layout. VP9 and AV1 don't.
  codecId == ID_H264 or codecId == ID_HEVC

func parameterSetsFor(codecId: AVCodecID, data: ptr uint8, size: int): seq[uint8] =
  if codecId == ID_H264: parameterSetsToAvcc(data, size)
  elif codecId == ID_HEVC: parameterSetsToHvcc(data, size)
  else: @[]

func supportsContainer(codecId: AVCodecID, formatName: string): bool =
  let isWebm = formatName == "webm"
  let isMatroska = "matroska" in formatName
  case codecId
  of ID_H264, ID_HEVC:
    formatName.isIsoBmff or isMatroska
  of ID_VP9:
    isWebm
  of ID_AV1:
    isWebm or isMatroska or formatName.isIsoBmff
  else:
    false

func supportsStream(stream: ptr AVStream, encoder: ptr AVCodec,
    codecId: AVCodecID): bool =
  let pixelFormat = AVPixelFormat(stream.codecpar.format)
  case codecId
  of ID_H264:
    stream.h264SupportsPartialLossless
  of ID_HEVC:
    stream.hevcSupportsPartialLossless(encoder)
  of ID_VP9:
    pixelFormat == AV_PIX_FMT_YUV420P
  of ID_AV1:
    encoder.encoderSupports(pixelFormat)
  else:
    false

func packetIsCopyBoundary(codecId: AVCodecID, data: ptr uint8, size: int): bool =
  ## FFmpeg's AV1 parser marks only independently decodable packets as key.
  ## VP9's container flag is less strict, so also inspect its frame header.
  case codecId
  of ID_H264:
    h264IsCopyBoundary(data, size)
  of ID_HEVC:
    hevcIsCopyBoundary(data, size)
  of ID_VP9:
    vp9IsKeyframe(data, size)
  of ID_AV1:
    true
  else:
    false

func codecLabel(codecId: AVCodecID): string =
  if codecId == ID_H264: "H.264" else: ($avcodec_get_name(codecId)).toUpperAscii

func normalizedCopyDts*(codecId: AVCodecID, first: bool, pts, dts: int64): int64 =
  ## Matroska can leave DTS unset on the first H.264 packet returned after a
  ## seek. A closed random-access packet has no decode dependency before it, so
  ## its shifted PTS is also the decode-time anchor for the copied span.
  if codecId == ID_H264 and first and dts == AV_NOPTS_VALUE: pts else: dts

proc scanGops(input: InputContainer, stream: ptr AVStream, fps: AVRational,
    codecId: AVCodecID): tuple[keyframes: seq[int64], sourceEnd: int64] =
  while av_read_frame(input.formatContext, input.packet) >= 0:
    let packet = input.packet
    if packet.stream_index == stream.index and packet.pts != AV_NOPTS_VALUE:
      let frame = frameAt(packet.pts, stream.time_base, fps)
      result.sourceEnd = max(result.sourceEnd, frame + 1)
      if (packet.flags and AV_PKT_FLAG_KEY) != 0 and
          packetIsCopyBoundary(codecId, packet.data, packet.size.int):
        result.keyframes.add frame
    av_packet_unref(packet)

  result.keyframes.sort()
  var write = 0
  for keyframe in result.keyframes:
    if write == 0 or result.keyframes[write - 1] != keyframe:
      result.keyframes[write] = keyframe
      inc write
  result.keyframes.setLen(write)

proc partialLosslessPlan*(output: OutputContainer, tl: v3, args: mainArgs,
    codecId: AVCodecID): seq[SmartSpan] =
  if args.noPartialLossless or args.scale != 1.0 or args.pixFmt != "" or
      args.vprofile != "":
    return

  let encoder = initCodec(args.videoCodec)
  if encoder == nil or encoder.id != codecId:
    return
  let formatName = $output.formatCtx.oformat.name
  if not codecId.supportsContainer(formatName):
    return
  if tl.v.len != 1 or tl.v[0].len == 0:
    return

  let source = tl.v[0][0].src
  if source == nil:
    return
  var expectedStart = 0'i64
  for clip in tl.v[0]:
    if clip.src != source or clip.stream != 0 or clip.start != expectedStart or
        not tl.effects[clip.effects].isEmpty:
      return
    expectedStart = clip.start + clip.dur
  if expectedStart != tl.len:
    return

  var input = try: av.open(source[])
              except IOError: return
  defer: input.close()
  if input.video.len == 0:
    return

  let stream = input.video[0]
  if stream.codecpar.codec_id != codecId or
      stream.codecpar.width != tl.res[0] or
      stream.codecpar.height != tl.res[1] or
      not stream.supportsStream(encoder, codecId) or
      not stream.avg_frame_rate.isValid or stream.avg_frame_rate != tl.tb:
    return

  let (keyframes, sourceEnd) = scanGops(input, stream, tl.tb, codecId)
  for clip in tl.v[0]:
    if clip.offset < 0 or clip.offset >= sourceEnd or
        clip.offset + clip.dur > sourceEnd + 1:
      return

  let plan = smartRenderPlan(tl.v[0], keyframes, sourceEnd)
  let stats = smartPlanStats(plan)
  let averageGop = averageGopFrames(keyframes, sourceEnd)
  if not smartPlanIsWorthwhile(stats, tl.len, sourceEnd, averageGop):
    let label = codecId.codecLabel
    debug &"Skipping {label} partial-lossless rendering: copying {stats.copiedFrames}/{tl.len} frames across {plan.len} spans would not offset {stats.encodeRuns} encoder runs"
    return
  return plan

proc initPartialEncoder(args: mainArgs, par: ptr AVCodecParameters,
    frameTb, fps: AVRational, codecId: AVCodecID): ptr AVCodecContext =
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
  if codecId.isNalCodec:
    encoder.max_b_frames = max(par.video_delay, 0)
    encoder.flags |= AV_CODEC_FLAG_GLOBAL_HEADER
  elif codecId == ID_AV1 and args.crf >= 0 and args.videoBitrate < 0:
    # SVT-AV1 rejects CRF mode when a target bitrate is also configured. The
    # bitrate above is only an automatic fallback, so do not let it conflict
    # with an explicit quality target.
    encoder.bit_rate = 0
  resolveEncoderContext(encoder)
  encoder.applyPartialEncoderArgs(args)
  encoder.open()
  return encoder

proc makePartialLossless*(output: var OutputContainer, tl: v3, args: mainArgs,
    spans: seq[SmartSpan], codecId: AVCodecID):
    (ptr AVStream, iterator(): (ptr AVPacket, int64)) =
  let label = codecId.codecLabel
  let isNal = codecId.isNalCodec
  let sourcePath = tl.v[0][0].src[]
  var templateInput = try: av.open(sourcePath) except IOError as e: error e.msg
  let sourceStream = templateInput.video[0]
  let sourceParameterSets = parameterSetsFor(codecId,
    sourceStream.codecpar.extradata, sourceStream.codecpar.extradata_size)

  let stats = smartPlanStats(spans)
  if stats.copiedFrames == 0:
    templateInput.close()
    error &"Partial-lossless {label} renderer selected without a complete GOP"

  let outputStream = output.addStreamFromTemplate(sourceStream)
  if sourceStream.metadata != nil:
    discard av_dict_copy(addr outputStream.metadata, sourceStream.metadata, 0)
  outputStream.time_base = sourceStream.time_base
  outputStream.avg_frame_rate = tl.tb
  outputStream.duration = av_rescale_q(tl.len, av_inv_q(tl.tb),
      outputStream.time_base)
  if isNal and "matroska" notin $output.formatCtx.oformat.name:
    # Mixed copied and re-encoded regions carry boundary parameter sets in-band.
    # QuickTime's player expects the conventional avc1 sample entry for H.264;
    # for HEVC, `hev1` permits in-band sets where `hvc1` requires them in hvcC.
    outputStream.codecpar.codec_tag =
      if codecId == ID_H264: fourccToInt("avc1") else: fourccToInt("hev1")
  templateInput.close()

  debug &"Using {label} partial-lossless rendering: copying {stats.copiedFrames}/{tl.len} frames across {spans.len} spans and {stats.encodeRuns} encoder runs"

  return (outputStream, iterator(): (ptr AVPacket, int64) =
    let frameTb = av_inv_q(tl.tb)
    let noParameterSets: seq[uint8] = @[]
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
        error &"Could not allocate partial-lossless {label} frame/packet"
    defer:
      if packet != nil: av_packet_free(addr packet)
      if frame != nil: av_frame_free(addr frame)
      if decoder != nil: avcodec_free_context(addr decoder)

    var encoder: ptr AVCodecContext = nil
    var encodedParameterSets: seq[uint8] = @[]
    var firstPacket = false
    var firstFrameInRun = false

    # Clone an encoder packet onto the output stream and hand it to the muxer.
    # The first packet of an encode run carries the encoder's parameter sets so
    # a decoder can switch between copied and re-encoded regions.
    template emitEncoded(encodedPacket: ptr AVPacket) =
      let outPacket = av_packet_clone(encodedPacket)
      if outPacket == nil:
        error &"Could not clone encoded {label} packet"
      outPacket.flags = outPacket.flags and not AV_PKT_FLAG_DISCARD
      outPacket.time_base = encoder.time_base
      outPacket.stream_index = outputStream.index
      if isNal:
        outPacket.normalizeLengthPrefixed(
          if firstPacket: encodedParameterSets else: noParameterSets, label)
      firstPacket = false
      let orderTs =
        if outPacket.dts != AV_NOPTS_VALUE: outPacket.dts
        else: outPacket.pts
      yield (outPacket, max(0'i64, orderTs))
      av_packet_unref(encodedPacket)

    for spanIndex, span in spans:
      if span.kind == ssCopy:
        let seekTs = av_rescale_q(span.srcStart, frameTb, stream.time_base)
        input.seek(seekTs, stream = stream)
        var first = true
        var copied = 0'i64
        var shift = 0'i64
        let reorderDelay = max(stream.codecpar.video_delay.int64, 0)
        while av_read_frame(input.formatContext, input.packet) >= 0:
          let sourcePacket = input.packet
          if sourcePacket.stream_index != stream.index or
              sourcePacket.pts == AV_NOPTS_VALUE:
            av_packet_unref(sourcePacket)
            continue
          let sourceFrame = frameAt(sourcePacket.pts, stream.time_base, tl.tb)
          if sourceFrame >= span.srcEnd:
            # HEVC stops at the next closed random-access picture, not merely at
            # the first packet whose presentation timestamp belongs to the next
            # GOP: reordering can place an in-range picture after this one.
            let atBoundary = codecId != ID_HEVC or
              packetIsCopyBoundary(codecId, sourcePacket.data,
                sourcePacket.size.int)
            av_packet_unref(sourcePacket)
            if atBoundary:
              break
            continue
          if sourceFrame < span.srcStart:
            av_packet_unref(sourcePacket)
            continue
          if first and ((sourcePacket.flags and AV_PKT_FLAG_KEY) == 0 or
              not packetIsCopyBoundary(codecId, sourcePacket.data,
                sourcePacket.size.int)):
            av_packet_unref(sourcePacket)
            continue
          let isFirst = first
          first = false
          let outPacket = av_packet_clone(sourcePacket)
          if outPacket == nil:
            error &"Could not clone {label} packet"
          if codecId == ID_HEVC:
            # Normalize copied timing to the CFR timeline. Rebuilding DTS in
            # decode order avoids carrying CRA/RASL preroll offsets across an
            # edit boundary and matches the encoder's configured reorder delay.
            outPacket.pts = span.outStart + sourceFrame - span.srcStart
            outPacket.dts = span.outStart - reorderDelay + copied
            outPacket.duration = 1
            outPacket.time_base = frameTb
            inc copied
          else:
            if isFirst:
              let outputBase = av_rescale_q(span.outStart, frameTb,
                  stream.time_base)
              # Matroska can carry a constant sub-frame timestamp offset. H.264
              # anchors the GOP to its actual key packet instead of preserving
              # that input offset between re-encoded and copied regions.
              shift =
                if codecId == ID_H264: outputBase - outPacket.pts
                else: outputBase - av_rescale_q(span.srcStart, frameTb,
                  stream.time_base)
            if outPacket.pts != AV_NOPTS_VALUE: outPacket.pts += shift
            if outPacket.dts != AV_NOPTS_VALUE: outPacket.dts += shift
            outPacket.dts = normalizedCopyDts(codecId, isFirst,
              outPacket.pts, outPacket.dts)
            outPacket.time_base = stream.time_base
          outPacket.stream_index = outputStream.index
          if isFirst and isNal:
            outPacket.normalizeLengthPrefixed(sourceParameterSets, label)
          let orderTs =
            if outPacket.dts != AV_NOPTS_VALUE: outPacket.dts
            else: outPacket.pts
          let orderFrame = max(0'i64, frameAt(orderTs, stream.time_base, tl.tb))
          av_packet_unref(sourcePacket)
          yield (outPacket, orderFrame)
      else:
        if encoder == nil:
          encoder = initPartialEncoder(args, stream.codecpar, frameTb, tl.tb,
            codecId)
          if isNal:
            encodedParameterSets = parameterSetsFor(codecId, encoder.extradata,
              encoder.extradata_size)
            let complete =
              if codecId == ID_H264: encodedParameterSets.len > 0
              else: encodedParameterSets.hasRequiredParameterSets
            if not complete:
              error &"{label} encoder did not provide parameter sets for partial-lossless rendering"
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
          decoded.pict_type =
            if firstFrameInRun: AV_PICTURE_TYPE_I
            else: AV_PICTURE_TYPE_NONE
          firstFrameInRun = false
          for encodedPacket in encoder.encode(decoded, packet):
            emitEncoded(encodedPacket)
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
            emitEncoded(encodedPacket)
          av_frame_free(addr held)
          inc encoded

        if lastDecoded != nil:
          av_frame_free(addr lastDecoded)

        let endsRun = spanIndex + 1 == spans.len or
          spans[spanIndex + 1].kind == ssCopy
        if endsRun:
          for encodedPacket in encoder.encode(nil, packet):
            emitEncoded(encodedPacket)
          avcodec_free_context(addr encoder)
  )
