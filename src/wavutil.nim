import std/strformat

import ./[av, ffmpeg, log, resampler]
import ./util/rational

type AudioBuffer = object
  fifo: ptr AVAudioFifo
  frameSize: cint

func resolveRecordingCodec*(keepRecording: bool, audioCodec: string): string =
  if not keepRecording: "auto"
  elif audioCodec == "auto": "flac"
  else: audioCodec

func nearestRate(requested: cint, rates: openArray[cint]): cint =
  result = rates[0]
  var bestDistance = abs(result - requested)
  for rate in rates:
    let distance = abs(rate - requested)
    if distance < bestDistance:
      result = rate
      bestDistance = distance

proc selectEncoderRate(ctx: ptr AVCodecContext, requested: cint): cint =
  var configPtr: pointer = nil
  var num: cint = 0
  discard avcodec_get_supported_config(ctx, nil, AV_CODEC_CONFIG_SAMPLE_RATE,
      0.cuint, addr configPtr, addr num)

  if configPtr != nil and num > 0:
    let rates = cast[ptr UncheckedArray[cint]](configPtr)
    result = rates[0]
    var bestDistance = abs(result - requested)
    for i in 0..<num:
      if rates[i] == requested:
        return requested
      let distance = abs(rates[i] - requested)
      if distance < bestDistance:
        result = rates[i]
        bestDistance = distance
    return

  # Some AAC encoders do not publish their supported-rate configuration.
  if ctx.codec.id == ID_AAC:
    const aacRates = [8000.cint, 11025, 12000, 16000, 22050, 24000,
                      32000, 44100, 48000]
    return nearestRate(requested, aacRates)
  return requested

proc selectEncoderLayout(ctx: ptr AVCodecContext,
    inputLayout: ptr AVChannelLayout) =
  var configPtr: pointer = nil
  var num: cint = 0
  discard avcodec_get_supported_config(ctx, nil, AV_CODEC_CONFIG_CHANNEL_LAYOUT,
      0.cuint, addr configPtr, addr num)

  if configPtr == nil or num <= 0:
    discard av_channel_layout_copy(addr ctx.ch_layout, inputLayout)
    return

  let layouts = cast[ptr UncheckedArray[AVChannelLayout]](configPtr)
  var selected = 0
  var bestDistance = abs(layouts[0].nb_channels - inputLayout.nb_channels)
  for i in 0..<num:
    if av_channel_layout_compare(addr layouts[i], inputLayout) == 0:
      selected = i
      break
    let distance = abs(layouts[i].nb_channels - inputLayout.nb_channels)
    if distance < bestDistance:
      selected = i
      bestDistance = distance
  discard av_channel_layout_copy(addr ctx.ch_layout, addr layouts[selected])

proc checkAudioEncoder(codec: ptr AVCodec, format: ptr AVOutputFormat,
    requestedName: string) =
  if codec.`type` != AVMEDIA_TYPE_AUDIO:
    error &"Encoder '{requestedName}' is not an audio encoder"
  if avformat_query_codec(format, codec.id, FF_COMPLIANCE_NORMAL) == 0:
    let formatName = if format.name != nil: $format.name else: "unknown"
    let encoderName = if codec.name != nil: $codec.name else: requestedName
    error &"Format '{formatName}' does not support codec '{encoderName}'"

proc validateAudioCodec*(codecName, outputPath: string) =
  let codec = initCodec(codecName)
  if codec == nil:
    error "Unknown encoder: " & codecName

  let outputCtx: ptr AVFormatContext = nil
  discard avformat_alloc_output_context2(addr outputCtx, nil, nil,
      outputPath.cstring)
  if outputCtx == nil:
    error "Could not create output context"
  defer: avformat_free_context(outputCtx)

  checkAudioEncoder(codec, outputCtx.oformat, codecName)

proc initAudioBuffer(sampleFmt: AVSampleFormat, channels: cint,
    frameSize: cint): AudioBuffer =
  result.fifo = av_audio_fifo_alloc(sampleFmt, channels, frameSize * 2) # Buffer extra space
  result.frameSize = frameSize
  if result.fifo == nil:
    error "Could not allocate audio FIFO"

proc addSamplesToBuffer(buffer: var AudioBuffer, frame: ptr AVFrame): cint =
  return av_audio_fifo_write(buffer.fifo, cast[ptr pointer](addr frame.data[0]),
      frame.nb_samples)

proc readSamplesFromBuffer(buffer: var AudioBuffer,
    outputFrame: ptr AVFrame): bool =
  if av_audio_fifo_size(buffer.fifo) < buffer.frameSize:
    return false

  if av_frame_make_writable(outputFrame) < 0:
    error "Could not make frame writable"

  let samplesRead = av_audio_fifo_read(buffer.fifo, cast[ptr pointer](
      addr outputFrame.data[0]), buffer.frameSize)
  if samplesRead != buffer.frameSize:
    return false

  outputFrame.nb_samples = buffer.frameSize
  return true

proc processAndEncodeFrame(
  audioResampler: var AudioResampler, encoderCtx: ptr AVCodecContext,
  outputCtx: ptr AVFormatContext, outputStream: ptr AVStream,
  audioBuffer: var AudioBuffer, currentPts: var int64,
  inputFrame: ptr AVFrame = nil): bool =

  var ret: cint

  # Handle input data
  if inputFrame != nil:
    # Check if frame is already in encoder format (bypass resampler)
    if (inputFrame.format == encoderCtx.sample_fmt.cint and
        inputFrame.ch_layout.nb_channels == encoderCtx.ch_layout.nb_channels and
        inputFrame.sample_rate == encoderCtx.sample_rate):
      if addSamplesToBuffer(audioBuffer, inputFrame) < 0:
        error "Failed to add samples to buffer"
    else:
      try:
        let resampledFrames = audioResampler.resample(inputFrame)

        for resampledFrame in resampledFrames:
          if addSamplesToBuffer(audioBuffer, resampledFrame) < 0:
            error "Failed to add samples to buffer"

          # Free resampled frames if they're different from input frame
          if resampledFrame != inputFrame:
            av_frame_free(addr resampledFrame)
      except Exception as e:
        error &"Error during resampling: {e.msg}"

  # Process all complete frames from buffer
  var encoderFrame = av_frame_alloc()
  if encoderFrame == nil:
    return false
  defer: av_frame_free(addr encoderFrame)

  # Set up encoder frame properties
  encoderFrame.format = encoderCtx.sample_fmt.cint
  discard av_channel_layout_copy(addr encoderFrame.ch_layout, addr encoderCtx.ch_layout)
  encoderFrame.sample_rate = encoderCtx.sample_rate
  encoderFrame.nb_samples = audioBuffer.frameSize

  if av_frame_get_buffer(encoderFrame, 0) < 0:
    return false

  var outPacket = av_packet_alloc()
  if outPacket == nil:
    error "Can't alloc packet"
  defer: av_packet_free(addr outPacket)

  var processedAny = false
  while readSamplesFromBuffer(audioBuffer, encoderFrame):
    encoderFrame.pts = currentPts
    currentPts += audioBuffer.frameSize

    for outPacket in encoderCtx.encode(encoderFrame, outPacket):
      outPacket.stream_index = outputStream.index
      av_packet_rescale_ts(outPacket, encoderCtx.time_base, outputStream.time_base)
      ret = av_interleaved_write_frame(outputCtx, outPacket)
      if ret < 0:
        error &"Error writing packet: {ret}"
      av_packet_unref(outPacket)

    processedAny = true

  return processedAny


proc transcodeAudio*(inputPath, outputPath: string, streamIndex: int32,
    sampleRate: cint = -1, codecName: string = "auto") =
  var ret: cint
  var container: InputContainer
  try:
    container = av.open(inputPath)
  except IOError as e:
    error e.msg
  defer: container.close()

  if streamIndex < 0 or streamIndex >= container.audio.len:
    error "Stream index out of range"

  let inputStream: ptr AVStream = container.audio[streamIndex]
  let audioStreamIdx = inputStream.index
  let decoderCtx = initDecoder(inputStream.codecpar)
  defer: avcodec_free_context(addr decoderCtx)

  let outputCtx: ptr AVFormatContext = nil
  ret = avformat_alloc_output_context2(addr outputCtx, nil, nil,
      outputPath.cstring)
  if outputCtx == nil:
    error "Could not create output context"

  defer:
    outputCtx.close()

  let (encoder, encoderCtx) =
    if codecName != "auto": initEncoder(codecName)
    elif sampleRate > 0: initEncoder(ID_PCM_S16LE)
    else: initEncoder(outputCtx.oformat.audio_codec)
  defer: avcodec_free_context(addr encoderCtx)
  checkAudioEncoder(encoder, outputCtx.oformat, codecName)
  let requestedRate = if sampleRate > 0: sampleRate else: decoderCtx.sample_rate
  encoderCtx.sample_rate = selectEncoderRate(encoderCtx, requestedRate)
  if encoderCtx.sample_rate != requestedRate:
    debug &"{encoder.name}: snapping sample rate {requestedRate} -> {encoderCtx.sample_rate}"
  selectEncoderLayout(encoderCtx, addr decoderCtx.ch_layout)
  encoderCtx.time_base = AVRational(num: 1, den: encoderCtx.sample_rate)

  if (outputCtx.oformat.flags and AVFMT_GLOBALHEADER) != 0:
    encoderCtx.flags = encoderCtx.flags or AV_CODEC_FLAG_GLOBAL_HEADER

  if avcodec_open2(encoderCtx, encoder, nil) < 0:
    error "Could not open encoder"

  let frameSize: cint = if encoderCtx.frame_size > 0: encoderCtx.frame_size else: 1024
  var audioBuffer = initAudioBuffer(
    encoderCtx.sample_fmt, encoderCtx.ch_layout.nb_channels, frameSize
  )
  defer:
    if audioBuffer.fifo != nil:
      av_audio_fifo_free(audioBuffer.fifo)

  var layoutRef: ref AVChannelLayout
  new(layoutRef)
  discard av_channel_layout_copy(addr layoutRef[], addr encoderCtx.ch_layout)
  var audioResampler = newAudioResampler(
    encoderCtx.sample_fmt, layoutRef, encoderCtx.sample_rate, frameSize
  )
  let outputStream: ptr AVStream = avformat_new_stream(outputCtx, nil)
  if outputStream == nil:
    error "Could not allocate output stream"
  if avcodec_parameters_from_context(outputStream.codecpar, encoderCtx) < 0:
    error "Could not copy encoder parameters"

  outputStream.time_base = AVRational(num: 1, den: encoderCtx.sample_rate)
  outputStream.codecpar.codec_tag = 0

  if (outputCtx.oformat.flags and AVFMT_NOFILE) == 0:
    if avio_open(addr outputCtx.pb, outputPath.cstring, AVIO_FLAG_WRITE) < 0:
      error &"Could not open output file '{outputPath}'"

  if avformat_write_header(outputCtx, nil) < 0:
    error "Error occurred when opening output file"

  var packet = av_packet_alloc()
  var frame = av_frame_alloc()

  if packet == nil or frame == nil:
    error "Could not allocate packet or frames"

  defer: av_packet_free(addr packet)
  defer: av_frame_free(addr frame)

  var currentPts: int64 = 0

  # Read and process frames
  while av_read_frame(container.formatContext, packet) >= 0:
    defer: av_packet_unref(packet)

    if packet.stream_index == audioStreamIdx:
      ret = avcodec_send_packet(decoderCtx, packet)
      if ret < 0 and ret != AVERROR_EAGAIN:
        error &"Error sending packet to decoder (error code: {ret})"

      while true:
        ret = avcodec_receive_frame(decoderCtx, frame)
        if ret == AVERROR_EAGAIN or ret == AVERROR_EOF:
          break
        elif ret < 0:
          error &"Error during decoding: {ret}"

        discard processAndEncodeFrame(audioResampler, encoderCtx, outputCtx,
          outputStream,
          audioBuffer, currentPts, frame)
        av_frame_unref(frame)

  # Flush decoder
  ret = avcodec_send_packet(decoderCtx, nil)
  if ret >= 0:
    while true:
      ret = avcodec_receive_frame(decoderCtx, frame)
      if ret == AVERROR_EOF or ret == AVERROR_EAGAIN:
        break
      elif ret < 0:
        break

      discard processAndEncodeFrame(audioResampler, encoderCtx, outputCtx, outputStream,
        audioBuffer, currentPts, frame)
      av_frame_unref(frame)

  # Flush any remaining samples from resampler
  try:
    let finalFrames = audioResampler.resample(nil)
    for resampledFrame in finalFrames:
      if addSamplesToBuffer(audioBuffer, resampledFrame) >= 0:
        discard processAndEncodeFrame(audioResampler, encoderCtx, outputCtx, outputStream,
          audioBuffer, currentPts, nil)
      av_frame_free(addr resampledFrame)
  except Exception as e:
    error &"Error during resampler flush: {e.msg}"

  let remainingSamples = av_audio_fifo_size(audioBuffer.fifo)
  if remainingSamples > 0:
    var tailFrame = av_frame_alloc()
    if tailFrame == nil:
      error "Could not allocate frame"
    defer: av_frame_free(addr tailFrame)
    tailFrame.format = encoderCtx.sample_fmt.cint
    discard av_channel_layout_copy(addr tailFrame.ch_layout, addr encoderCtx.ch_layout)
    tailFrame.sample_rate = encoderCtx.sample_rate
    tailFrame.nb_samples = remainingSamples
    if av_frame_get_buffer(tailFrame, 0) < 0:
      error "Could not allocate frame buffer"
    if av_audio_fifo_read(audioBuffer.fifo,
        cast[ptr pointer](addr tailFrame.data[0]), remainingSamples) != remainingSamples:
      error "Could not read final samples"
    tailFrame.pts = currentPts
    currentPts += remainingSamples

    for outPacket in encoderCtx.encode(tailFrame, packet):
      outPacket.stream_index = outputStream.index
      av_packet_rescale_ts(outPacket, encoderCtx.time_base, outputStream.time_base)
      ret = av_interleaved_write_frame(outputCtx, outPacket)
      if ret < 0:
        error &"Error writing packet: {ret}"
      av_packet_unref(outPacket)

  # Flush encoder
  for packet in encoderCtx.encode(nil, packet):
    packet.stream_index = outputStream.index
    av_packet_rescale_ts(packet, encoderCtx.time_base, outputStream.time_base)
    ret = av_interleaved_write_frame(outputCtx, packet)
    if ret < 0:
      error &"Error writing packet: {ret}"
    av_packet_unref(packet)
