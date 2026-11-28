import std/[algorithm, deques, strformat, strutils]
from std/math import round
import ../[action, av, ffmpeg, log, timeline]
import ../util/rational
import ./[h264, hevc, smart]
from ./video import reformat

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

proc isNalCodec(codecId: AVCodecID): bool =
  ## H.264 and HEVC carry parameter sets in NAL units, so copied and re-encoded
  ## regions have to agree on a length-prefixed layout. VP9 and AV1 don't.
  codecId == ID_H264 or codecId == ID_HEVC

proc parameterSetsFor(codecId: AVCodecID, data: ptr uint8, size: int): seq[uint8] =
  if codecId == ID_H264: parameterSetsToAvcc(data, size)
  elif codecId == ID_HEVC: parameterSetsToHvcc(data, size)
  else: @[]

proc supportsContainer(codecId: AVCodecID, formatName: string): bool =
  let isWebm = formatName == "webm"
  let isMatroska = "matroska" in formatName
  if codecId == ID_H264 or codecId == ID_HEVC:
    formatName.isIsoBmff or isMatroska
  elif codecId == ID_VP9:
    isWebm
  elif codecId == ID_AV1:
    isWebm or isMatroska or formatName.isIsoBmff
  else:
    false

proc sourceHeader(input: InputContainer, stream: ptr AVStream,
    codecId: AVCodecID): seq[uint8] =
  ## The stream's extradata, or else the parameter sets of its first packet
  ## that has them: MPEG-TS carries them only in-band. Leaves the demuxer at
  ## the start.
  let par = stream.codecpar
  if par.extradata != nil and par.extradata_size > 0:
    result = newSeq[uint8](par.extradata_size)
    copyMem(addr result[0], par.extradata, par.extradata_size)
    return
  var seen = 0
  while seen < 300 and av_read_frame(input.formatContext, input.packet) >= 0:
    let packet = input.packet
    if packet.stream_index == stream.index:
      inc seen
      result =
        if codecId == ID_HEVC: hevcInBandParameterSets(packet.data, packet.size.int)
        else: annexBParameterSets(packet.data, packet.size.int)
    av_packet_unref(packet)
    if result.len > 0: break
  discard av_seek_frame(input.formatContext, -1, 0, AVSEEK_FLAG_BACKWARD)

proc seekToKeyBefore(input: InputContainer, stream: ptr AVStream, ts: int64) =
  ## Seek so the next keyframe read is at or before `ts`. MPEG-TS seeks by
  ## estimate and can land past it, which would drop the frames between, so
  ## back off a second at a time, doubling, until it doesn't. Even a seek to
  ## its start time can skip the first keyframe; one before it can't.
  let second = av_rescale_q(1, AVRational(num: 1, den: 1), stream.time_base)
  var margin = 0'i64
  while true:
    let target = ts - margin
    input.seek(target, stream = stream)
    var key = AV_NOPTS_VALUE
    while key == AV_NOPTS_VALUE and
        av_read_frame(input.formatContext, input.packet) >= 0:
      let packet = input.packet
      if packet.stream_index == stream.index and
          (packet.flags and AV_PKT_FLAG_KEY) != 0:
        key = (if packet.pts != AV_NOPTS_VALUE: packet.pts else: packet.dts)
      av_packet_unref(packet)
    if (key != AV_NOPTS_VALUE and key <= ts) or target < input.startPts(stream):
      input.seek(target, stream = stream)
      return
    margin = (if margin == 0: second else: margin * 2)

proc supportsStream(input: InputContainer, stream: ptr AVStream,
    encoder: ptr AVCodec, codecId: AVCodecID): bool =
  let pixelFormat = AVPixelFormat(stream.codecpar.format)
  if codecId == ID_H264:
    h264SupportsPartialLossless(stream.codecpar.format,
      sourceHeader(input, stream, codecId))
  elif codecId == ID_HEVC:
    hevcSupportsPartialLossless(stream.codecpar.format, encoder,
      sourceHeader(input, stream, codecId))
  elif codecId == ID_VP9:
    pixelFormat == AV_PIX_FMT_YUV420P
  elif codecId == ID_AV1:
    encoder.encoderSupports(pixelFormat)
  else:
    false

proc packetIsCopyBoundary(codecId: AVCodecID, data: ptr uint8, size: int): bool =
  ## FFmpeg's AV1 parser marks only independently decodable packets as key.
  ## VP9's container flag is less strict, so also inspect its frame header.
  if codecId == ID_H264:
    h264IsCopyBoundary(data, size)
  elif codecId == ID_HEVC:
    hevcIsCopyBoundary(data, size)
  elif codecId == ID_VP9:
    vp9IsKeyframe(data, size)
  elif codecId == ID_AV1:
    true
  else:
    false

proc codecLabel(codecId: AVCodecID): string =
  if codecId == ID_H264: "H.264" else: ($avcodec_get_name(codecId)).toUpperAscii

proc fillLeadingDts*(packets: openArray[ptr AVPacket], nextDts, frameDuration: int64) =
  ## Matroska leaves DTS unset on the packets a reordering H.264 decoder has to
  ## take in before it can output: the first two of a B-frame GOP, say. Space
  ## them a frame apart up to `nextDts`, the next packet's, or, when nothing
  ## after them has one, up to their earliest PTS so none decodes after it shows.
  var last = nextDts
  if last == AV_NOPTS_VALUE:
    last = high(int64)
    for p in packets: last = min(last, p.pts)
    last += frameDuration
  for i, p in packets:
    p.dts = last - (packets.len - i).int64 * frameDuration

proc scanGops(input: InputContainer, stream: ptr AVStream, fps: AVRational,
    codecId: AVCodecID): tuple[keyframes: seq[int64], sourceEnd: int64] =
  let start = input.startPts(stream)
  while av_read_frame(input.formatContext, input.packet) >= 0:
    let packet = input.packet
    if packet.stream_index == stream.index and packet.pts != AV_NOPTS_VALUE:
      let frame = frameAt(packet.pts - start, stream.time_base, fps)
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
    video: VideoSettings, codecId: AVCodecID):
    tuple[spans: seq[SmartSpan], keyframes: seq[int64]] =
  ## The spans to copy and to encode, with the source's keyframes, or no spans
  ## when the render has to encode every frame.
  if args.noPartialLossless:
    return

  # A render that could have copied and didn't is otherwise only slower.
  template skip(reason: string) =
    debug "Skipping " & codecId.codecLabel & " partial-lossless rendering: " & reason
    return

  if video.scale != 1.0: skip "the output is scaled"
  if video.pixFmt != "": skip "a pixel format was asked for"
  if video.profile != "": skip "a profile was asked for"

  let encoder = initCodec(video.codec)
  if encoder == nil or encoder.id != codecId:
    return
  # The web build's WebCodecs encoders (h264_web and the like) don't splice
  # into copied packets: their output decodes as garbage between copied spans.
  if ($encoder.name).endsWith("_web"):
    skip &"{encoder.name} can't splice into copied packets"
  let formatName = $output.formatCtx.oformat.name
  if not codecId.supportsContainer(formatName):
    skip &"{formatName} can't hold a mix of copied and encoded packets"
  if tl.v.len != 1 or tl.v[0].len == 0:
    skip "the timeline isn't a single video layer"

  let source = tl.v[0][0].src
  if source == nil:
    skip "the first clip has no source"
  var expectedStart = 0'i64
  for clip in tl.v[0]:
    if clip.src != source or clip.stream != 0:
      skip "the clips aren't all of one source's first video stream"
    if clip.start != expectedStart:
      skip "the clips leave a gap or overlap"
    if not tl.effects[clip.effects].isEmpty:
      skip "a clip has effects"
    expectedStart = clip.start + clip.dur
  if expectedStart != tl.len:
    skip "the clips end before the timeline does"

  var input = try: av.open(source[])
              except IOError: return
  defer: input.close()
  if input.video.len == 0:
    return

  let stream = input.video[0]
  if stream.codecpar.codec_id != codecId:
    skip "the source is " & $avcodec_get_name(stream.codecpar.codec_id)
  if stream.codecpar.width != tl.res[0] or stream.codecpar.height != tl.res[1]:
    skip &"the source is {stream.codecpar.width}x{stream.codecpar.height}, " &
      &"the timeline {tl.res[0]}x{tl.res[1]}"
  if not input.supportsStream(stream, encoder, codecId):
    skip "the source's pixel format or headers can't be matched by the encoder"
  # Packets are placed by rounding their time to a timeline frame, which only
  # gives each its own frame when the two rates are the same.
  if not stream.avg_frame_rate.isValid or stream.avg_frame_rate != tl.tb:
    skip &"the source averages {stream.avg_frame_rate} fps, the timeline is {tl.tb}"

  # Re-encoded frames are deinterlaced, so copying an interlaced source's GOPs
  # would leave its output interlaced or not depending on where cuts fall.
  if stream.codecpar.field_order notin [0.cint, 1]:
    skip "the source is interlaced"

  let (keyframes, sourceEnd) = scanGops(input, stream, tl.tb, codecId)
  for clip in tl.v[0]:
    if clip.offset < 0 or clip.offset >= sourceEnd or
        clip.offset + clip.dur > sourceEnd + 1:
      skip "a clip reaches outside the source's frames"

  let plan = smartRenderPlan(tl.v[0], keyframes, sourceEnd)
  let stats = smartPlanStats(plan)
  let averageGop = averageGopFrames(keyframes, sourceEnd)
  if not smartPlanIsWorthwhile(stats, tl.len, sourceEnd, averageGop):
    let label = codecId.codecLabel
    debug &"Skipping {label} partial-lossless rendering: copying " &
      &"{stats.copiedFrames}/{tl.len} frames across {plan.len} spans " &
      &"would not offset {stats.encodeRuns} encoder runs"
    return
  return (plan, keyframes)

proc initPartialEncoder(video: VideoSettings, par: ptr AVCodecParameters,
    frameTb, fps: AVRational, codecId: AVCodecID): ptr AVCodecContext =
  var (_, encoder) = initEncoder(video.codec)
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
  # FFmpeg's default is one thread, which only encoders with their own
  # default (libx264) override. The web build's workers come from a fixed
  # pool, so it keeps the default.
  when not defined(emscripten):
    encoder.thread_count = 0
  # A little over the source's rate holds re-encoded frames up beside copied
  # ones. A low or unknown rate is left to the encoder's own quality target,
  # as a full render's is: a run is short and opens on an I frame, which a
  # small average starves, and a fixed rate in its place gives a screen
  # recording many times the bits it had.
  let matched = par.bit_rate * 6 div 5
  encoder.bit_rate = (if matched >= 1_000_000: matched else: 0)
  if codecId.isNalCodec:
    # VideoToolbox reorders a B-pyramid two deep whatever it's asked for, and
    # FFmpeg's wrapper shifts its DTS by one, so a B-frame lands with its DTS
    # past its PTS. It encodes in order instead; emitEncoded shifts the DTS.
    encoder.max_b_frames =
      if ($encoder.codec.name).endsWith("_videotoolbox"): 0
      else: max(par.video_delay, 0)
    encoder.flags |= AV_CODEC_FLAG_GLOBAL_HEADER
  elif codecId == ID_AV1 and video.crf >= 0 and video.bitrate < 0:
    # SVT-AV1 rejects CRF mode when a target bitrate is also configured. The
    # bitrate above is only an automatic fallback, so do not let it conflict
    # with an explicit quality target.
    encoder.bit_rate = 0
  resolveEncoderContext(encoder)
  encoder.applyPartialEncoderArgs(video)
  # Every run starts on a forced I frame, and one that reuses the encoder
  # has to be an IDR to be cut against copied GOPs.
  encoder.priv_data.setOpt("forced-idr", 1)
  encoder.open()
  return encoder

func holdsFrames(tb, frameTb: AVRational): bool =
  ## Whether a time base counts whole frames exactly. Matroska's milliseconds
  ## don't for 30 fps: a frame is 33 or 34 of them.
  (frameTb.num.int64 * tb.den.int64) mod (frameTb.den.int64 * tb.num.int64) == 0

proc makePartialLossless*(output: var OutputContainer, tl: v3, video: VideoSettings,
    spans: seq[SmartSpan], keyframes: seq[int64], codecId: AVCodecID):
    (ptr AVStream, iterator(): (ptr AVPacket, int64)) =
  let label = codecId.codecLabel
  let isNal = codecId.isNalCodec
  let sourcePath = tl.v[0][0].src[]
  var templateInput = try: av.open(sourcePath) except IOError as e: error e.msg
  let sourceStream = templateInput.video[0]
  let header =
    if isNal: sourceHeader(templateInput, sourceStream, codecId)
    else:
      let par = sourceStream.codecpar
      var bytes = newSeq[uint8](max(par.extradata_size, 0))
      if bytes.len > 0: copyMem(addr bytes[0], par.extradata, bytes.len)
      bytes
  let sourceParameterSets =
    if header.len == 0: newSeq[uint8]()
    else: parameterSetsFor(codecId, addr header[0], header.len)

  let stats = smartPlanStats(spans)
  if stats.copiedFrames == 0:
    templateInput.close()
    error &"Partial-lossless {label} renderer selected without a complete GOP"

  let outputStream = output.addStreamFromTemplate(sourceStream)
  let sourceAnnexB = header.len > 0 and isAnnexB(addr header[0], header.len)
  if sourceAnnexB and isNal:
    # The muxer reads Annex B extradata as Annex B samples, but every sample
    # here is length-prefixed, so it gets an avcC or hvcC instead.
    let record =
      if codecId == ID_H264: annexBToAvcC(addr header[0], header.len)
      else: annexBToHvcC(addr header[0], header.len)
    let par = outputStream.codecpar
    av_freep(addr par.extradata)
    par.extradata = cast[ptr uint8](av_mallocz(csize_t(record.len + 64)))
    if par.extradata == nil:
      error &"Could not allocate {label} header"
    copyMem(par.extradata, addr record[0], record.len)
    par.extradata_size = record.len.cint
  if sourceStream.metadata != nil:
    discard av_dict_copy(addr outputStream.metadata, sourceStream.metadata, 0)
  # Copied packets carry the source's timestamps. Where those can't land on
  # whole frames, the packets are retimed to frames, or the output's frame
  # rate would only come near the timeline's.
  let retime = not holdsFrames(sourceStream.time_base, av_inv_q(tl.tb))
  outputStream.time_base =
    if retime: av_inv_q(tl.tb) else: sourceStream.time_base
  outputStream.avg_frame_rate = tl.tb
  # A SAR the container sets over the bitstream's goes with the copy.
  let sar = av_guess_sample_aspect_ratio(templateInput.formatContext, sourceStream, nil)
  if sar.isValid:
    outputStream.sample_aspect_ratio = sar
    outputStream.codecpar.sample_aspect_ratio = sar
  outputStream.duration = av_rescale_q(tl.len, av_inv_q(tl.tb),
      outputStream.time_base)
  if isNal and "matroska" notin $output.formatCtx.oformat.name:
    # Mixed copied and re-encoded regions carry boundary parameter sets in-band.
    # QuickTime's player expects the conventional avc1 sample entry for H.264;
    # for HEVC, `hev1` permits in-band sets where `hvc1` requires them in hvcC.
    outputStream.codecpar.codec_tag =
      if codecId == ID_H264: fourccToInt("avc1") else: fourccToInt("hev1")
  let sourceDelay = max(sourceStream.codecpar.video_delay, 0).int64
  templateInput.close()

  debug &"Using {label} partial-lossless rendering: copying " &
    &"{stats.copiedFrames}/{tl.len} frames across {spans.len} spans " &
    &"and {stats.encodeRuns} encoder runs"

  return (outputStream, iterator(): (ptr AVPacket, int64) =
    let frameTb = av_inv_q(tl.tb)
    let noParameterSets: seq[uint8] = @[]
    var input = try: av.open(sourcePath)
                except IOError as e: error e.msg
    defer: input.close()
    let stream = input.video[0]

    # Encoding reads its own input, so a run can pause across copied spans.
    var encInput: InputContainer
    var decoder: ptr AVCodecContext = nil
    var frame: ptr AVFrame = nil
    var packet: ptr AVPacket = nil
    var encoder: ptr AVCodecContext = nil
    if stats.encodeSpans > 0:
      encInput = try: av.open(sourcePath)
                 except IOError as e: error e.msg
      decoder = initDecoder(stream.codecpar)
      frame = av_frame_alloc()
      packet = av_packet_alloc()
      if frame == nil or packet == nil:
        error &"Could not allocate partial-lossless {label} frame/packet"
    defer:
      if encoder != nil: avcodec_free_context(addr encoder)
      if packet != nil: av_packet_free(addr packet)
      if frame != nil: av_frame_free(addr frame)
      if decoder != nil: avcodec_free_context(addr decoder)
      if stats.encodeSpans > 0: encInput.close()

    # Runs of consecutive encode spans: each one's first and last span.
    var runFirst, runLast: seq[int]
    for i, span in spans:
      if span.kind == ssEncode:
        if i > 0 and spans[i - 1].kind == ssEncode:
          runLast[^1] = i
        else:
          runFirst.add i
          runLast.add i
    # The range each fed run's packets take among all the encoded packets.
    var runStart, runEnd: seq[int64]

    # libx264 stays open across runs, each starting on a forced IDR: a fresh
    # encoder per run faults its couple hundred megabytes of frames in again,
    # and a NULL flush stops x264's lookahead thread for good. A run's last
    # packets then come out only as the next run goes in, so enough of that
    # run is encoded before the copied GOPs between them, and their DTS are
    # set as a fresh encoder's would be. x264 sees one frame after another, as its rate
    # control reads a frame's duration from the next one's PTS: across a copied
    # stretch, that frame would be given minutes' worth of bits.
    var reuse = false
    var encodedParameterSets: seq[uint8] = @[]
    var encodedAnnexB = true
    var sent = 0'i64
    var received = 0'i64
    var emitted = 0'i64
    var recvRun = 0
    var reorderFrames = 0'i64
    var encoded: Deque[(ptr AVPacket, int64)] # received, awaiting their turn
    var ready: Deque[(ptr AVPacket, int64)]

    # Clone an encoder packet onto the output stream. The first packet of an
    # encode run carries the encoder's parameter sets so a decoder can switch
    # between copied and re-encoded regions.
    template receive(encodedPacket: ptr AVPacket) =
      while recvRun + 1 < runStart.len and received >= runStart[recvRun + 1]:
        inc recvRun
      let k = received - runStart[recvRun]
      if received == 0 and encodedPacket.dts != AV_NOPTS_VALUE:
        # The first frame's PTS is 0, so a fresh encoder's first DTS is minus
        # its reorder delay. has_b_frames can't say: libx264 reports 2 for a
        # pyramid x264 turns off with a single B-frame.
        reorderFrames = -encodedPacket.dts
      let outPacket = av_packet_clone(encodedPacket)
      if outPacket == nil:
        error &"Could not clone encoded {label} packet"
      outPacket.flags = outPacket.flags and not AV_PKT_FLAG_DISCARD
      outPacket.time_base = encoder.time_base
      if reuse and outPacket.pts != AV_NOPTS_VALUE:
        outPacket.pts += spans[runFirst[recvRun]].outStart - runStart[recvRun]
      if encoder.max_b_frames == 0 and outPacket.pts != AV_NOPTS_VALUE:
        # An encoder that doesn't reorder still has to leave the copied GOPs'
        # decode delay between DTS and PTS, as one with B-frames does.
        outPacket.dts = outPacket.pts - sourceDelay
      elif reuse:
        outPacket.dts = spans[runFirst[recvRun]].outStart - reorderFrames + k
      outPacket.stream_index = outputStream.index
      if isNal:
        outPacket.normalizeLengthPrefixed(
          if k == 0: encodedParameterSets else: noParameterSets, label,
          encodedAnnexB)
      let orderTs =
        if outPacket.dts != AV_NOPTS_VALUE: outPacket.dts
        else: outPacket.pts
      encoded.addLast (outPacket, max(0'i64, orderTs))
      inc received
      av_packet_unref(encodedPacket)

    template send(f: ptr AVFrame) =
      let sentFrame: ptr AVFrame = f
      for encodedPacket in encoder.encode(sentFrame, packet):
        receive(encodedPacket)
      if sentFrame != nil: inc sent

    # The last source frame the decoder gave, or -1 when it has to seek.
    var decodedTo = -1'i64
    # The frames to encode for run `genRun`, one at a time.
    var genRun = 0
    var gen: iterator(): ptr AVFrame = nil
    template newGen(): iterator(): ptr AVFrame =
      iterator(): ptr AVFrame =
        let encStream = encInput.video[0]
        var firstFrameInRun = true
        for fedSpan in runFirst[genRun] .. runLast[genRun]:
          let span = spans[fedSpan]
          # A seek decodes again from the keyframe before the span. A decoder
          # already past that keyframe, as after a cut within one GOP, has
          # only the frames between left to go through.
          let key = keyframes[max(upperBound(keyframes, span.srcStart) - 1, 0)]
          if decodedTo < 0 or decodedTo >= span.srcStart or key > decodedTo + 1:
            encInput.seekToKeyBefore(encStream,
              av_rescale_q(span.srcStart, frameTb, encStream.time_base) +
              encInput.startPts(encStream))
            avcodec_flush_buffers(decoder)
          var count = 0'i64
          var lastDecoded: ptr AVFrame = nil
          var flushed = false
          var finished = false
          while not finished:
            var src: ptr AVFrame = nil
            var upTo = 0'i64
            let ret = avcodec_receive_frame(decoder, frame)
            if ret == 0:
              let sourceFrame = int64(round((frame.time(encStream.time_base) -
                float(encInput.startPts(encStream) * encStream.time_base)) *
                float(tl.tb)))
              decodedTo = sourceFrame
              if sourceFrame < span.srcStart:
                continue
              # A WebCodecs decoder hands over whatever layout the browser
              # picked (NV12 from hardware decoders), while the encoder was
              # opened for the stream's own format.
              src = frame.reformat(encoder.pix_fmt)
              if lastDecoded != nil:
                av_frame_free(addr lastDecoded)
              lastDecoded = av_frame_clone(src)
              # Like the normal renderer, a frame with no picture of its own,
              # as before a stream that starts late, shows the next one decoded.
              upTo = min(sourceFrame, span.srcEnd - 1)
              finished = sourceFrame >= span.srcEnd - 1
            elif ret == AVERROR_EAGAIN and not flushed:
              if av_read_frame(encInput.formatContext, encInput.packet) < 0:
                discard avcodec_send_packet(decoder, nil)
                flushed = true
              else:
                if encInput.packet.stream_index == encStream.index:
                  discard avcodec_send_packet(decoder, encInput.packet)
                av_packet_unref(encInput.packet)
              continue
            else:
              # Container duration rounding can leave the timeline one frame
              # longer than the final decoded timestamp. Match the normal
              # renderer by holding the last picture to the span's end.
              finished = true
              if lastDecoded == nil:
                break
              src = lastDecoded
              upTo = span.srcEnd - 1
            while span.srcStart + count <= upTo:
              let slot = av_frame_clone(src)
              slot.pts = span.outStart + count
              slot.time_base = frameTb
              slot.duration = 1
              slot.pict_type =
                if firstFrameInRun: AV_PICTURE_TYPE_I
                else: AV_PICTURE_TYPE_NONE
              firstFrameInRun = false
              inc count
              yield slot
            if src != frame and src != lastDecoded:
              av_frame_free(addr src)
          if lastDecoded != nil:
            av_frame_free(addr lastDecoded)
          # A drained decoder gives nothing more until it's flushed.
          if flushed: decodedTo = -1

    # Send one more frame to the encoder, starting the next run if none is
    # under way, and finishing the run when it has no frames left.
    template feedStep() =
      if gen == nil:
        if encoder == nil:
          encoder = initPartialEncoder(video, stream.codecpar, frameTb, tl.tb,
            codecId)
          reuse = $encoder.codec.name == "libx264"
          if isNal:
            encodedParameterSets = parameterSetsFor(codecId, encoder.extradata,
              encoder.extradata_size)
            # With a global header, an avcC/hvcC one means its packets are
            # length-prefixed already.
            encodedAnnexB = encoder.extradata == nil or
              isAnnexB(encoder.extradata, encoder.extradata_size)
            let complete =
              if codecId == ID_H264: encodedParameterSets.len > 0
              else: encodedParameterSets.hasRequiredParameterSets
            if not complete:
              error &"{label} encoder did not provide parameter sets for partial-lossless rendering"
        genRun = runStart.len
        runStart.add(if reuse: sent else: received)
        gen = newGen()
      var slot = gen()
      if finished(gen):
        gen = nil
        if not reuse or runStart.len == runFirst.len:
          send(nil)
          if not reuse: avcodec_free_context(addr encoder)
        runEnd.add(if reuse: sent else: received)
      else:
        if reuse: slot.pts = sent
        send(slot)
        av_frame_free(addr slot)

    var spanIndex = 0
    var run = 0
    var copying = false
    var first = true
    var copied = 0'i64
    var shift = 0'i64
    var sawDts = false
    var undated: seq[ptr AVPacket] # leading packets awaiting a DTS
    let frameDuration = max(1'i64, av_rescale_q(1, frameTb, stream.time_base))
    let reorderDelay = max(stream.codecpar.video_delay.int64, 0)

    template queueCopied(p: ptr AVPacket) =
      if retime and p.time_base != frameTb:
        # Each is within a rounding of a whole frame, the nearest one.
        if p.pts != AV_NOPTS_VALUE: p.pts = av_rescale_q(p.pts, p.time_base, frameTb)
        if p.dts != AV_NOPTS_VALUE: p.dts = av_rescale_q(p.dts, p.time_base, frameTb)
        p.duration = 1
        p.time_base = frameTb
      let orderTs = if p.dts != AV_NOPTS_VALUE: p.dts else: p.pts
      # In the packet's time base: HEVC's are retimed to frames by now.
      ready.addLast (p, max(0'i64, frameAt(orderTs, p.time_base, tl.tb)))

    template flushUndated(nextDts: int64) =
      fillLeadingDts(undated, nextDts, frameDuration)
      for p in undated: queueCopied(p)
      undated.setLen(0)

    template endCopy() =
      if undated.len > 0: flushUndated(AV_NOPTS_VALUE)
      copying = false
      inc spanIndex

    while true:
      if ready.len > 0:
        yield ready.popFirst()
        continue
      if spanIndex >= spans.len:
        break
      let span = spans[spanIndex]

      if span.kind == ssEncode:
        # Packets go out as soon as they're this run's; until then, the
        # encoder is fed, the next run too when this one's tail is still in it.
        if encoded.len > 0 and (run + 1 >= runStart.len or
            emitted < runStart[run + 1]):
          ready.addLast encoded.popFirst()
          inc emitted
        elif run < runEnd.len and emitted >= runEnd[run]:
          spanIndex = runLast[run] + 1
          inc run
        elif gen != nil or runStart.len < runFirst.len:
          feedStep()
        else:
          error &"The {label} encoder returned fewer packets than frames"
        continue

      if not copying:
        input.seekToKeyBefore(stream,
          av_rescale_q(span.srcStart, frameTb, stream.time_base) +
          input.startPts(stream))
        copying = true
        first = true
        copied = 0
        shift = 0
        sawDts = false

      if av_read_frame(input.formatContext, input.packet) < 0:
        endCopy()
        continue
      let sourcePacket = input.packet
      if sourcePacket.stream_index != stream.index or
          sourcePacket.pts == AV_NOPTS_VALUE:
        av_packet_unref(sourcePacket)
        continue
      let sourceFrame = frameAt(sourcePacket.pts - input.startPts(stream),
        stream.time_base, tl.tb)
      if sourceFrame >= span.srcEnd:
        # HEVC stops at the next closed random-access picture, not merely at
        # the first packet whose presentation timestamp belongs to the next
        # GOP: reordering can place an in-range picture after this one.
        let atBoundary = codecId != ID_HEVC or
          packetIsCopyBoundary(codecId, sourcePacket.data,
            sourcePacket.size.int)
        av_packet_unref(sourcePacket)
        if atBoundary:
          endCopy()
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
        outPacket.time_base = stream.time_base
      outPacket.stream_index = outputStream.index
      if isFirst and isNal:
        outPacket.normalizeLengthPrefixed(sourceParameterSets, label,
          sourceAnnexB)
      elif sourceAnnexB:
        outPacket.normalizeLengthPrefixed(noParameterSets, label, true)
      av_packet_unref(sourcePacket)
      if codecId == ID_H264 and not sawDts and outPacket.dts == AV_NOPTS_VALUE:
        undated.add outPacket
        continue
      sawDts = true
      if undated.len > 0: flushUndated(outPacket.dts)
      queueCopied(outPacket)
  )
