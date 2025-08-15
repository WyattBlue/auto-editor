import std/strformat

import av
import ffmpeg
import log
import resampler

type AudioBuffer = object
  fifo: ptr AVAudioFifo
  frameSize: cint

proc initAudioBuffer(sampleFmt: AVSampleFormat, channels: cint,
    frameSize: cint): AudioBuffer =
  result.fifo = av_audio_fifo_alloc(sampleFmt, channels, frameSize * 2) # Buffer extra space
  result.frameSize = frameSize
  if result.fifo == nil:
    error "Could not allocate audio FIFO"

proc createResampler(encoderCtx: ptr AVCodecContext): AudioResampler =
  # Create resampler based on encoder format requirements
  let outputLayout = if encoderCtx.ch_layout.nb_channels == 1: "mono" else: "stereo" 
  return newAudioResampler(
    encoderCtx.sample_fmt,
    outputLayout,
    encoderCtx.sample_rate,
    if encoderCtx.frame_size > 0: encoderCtx.frame_size else: 1024
  )

proc addSamplesToBuffer(buffer: var AudioBuffer, frame: ptr AVFrame): cint =
  return av_audio_fifo_write(buffer.fifo, cast[ptr pointer](addr frame.data[0]),
      frame.nb_samples)

proc readSamplesFromBuffer(buffer: var AudioBuffer,
    outputFrame: ptr AVFrame): bool =
  if av_audio_fifo_size(buffer.fifo) < buffer.frameSize:
    return false

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
      # Frame is already in target format, add directly to buffer
      if addSamplesToBuffer(audioBuffer, inputFrame) < 0:
        error "Failed to add samples to buffer"
    else:
      try:
        # Use the AudioResampler to convert the frame
        let resampledFrames = audioResampler.resample(inputFrame)
        
        # Add all resampled frames to buffer
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
  encoderFrame.ch_layout = encoderCtx.ch_layout
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


proc muxAudio*(inputPath, outputPath: string, index: int) =
  var c = av.open(inputPath)
  defer: c.close()
  var output = openWrite(outputPath)
  defer: output.close()

  let audioStream = c.audio[index]
  discard output.addStreamFromTemplate(audioStream)
  for packet in c.demux(audioStream.index):
    packet.stream_index = 0 # Always 0 for single-stream output
    output.mux(packet)


proc transcodeAudio*(inputPath, outputPath: string, streamIndex: int64) =
  var ret: cint
  var container: InputContainer
  try:
    container = av.open(inputPath)
  except OSError as e:
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

  let (encoder, encoderCtx) = initEncoder(outputCtx.oformat.audio_codec)
  encoderCtx.sample_rate = decoderCtx.sample_rate
  encoderCtx.ch_layout = decoderCtx.ch_layout
  encoderCtx.time_base = AVRational(num: 1, den: encoderCtx.sample_rate)

  if (outputCtx.oformat.flags and AVFMT_GLOBALHEADER) != 0:
    encoderCtx.flags = encoderCtx.flags or AV_CODEC_FLAG_GLOBAL_HEADER

  if avcodec_open2(encoderCtx, encoder, nil) < 0:
    error "Could not open encoder"
  defer: avcodec_free_context(addr encoderCtx)

  let requiredFrameSize = if encoderCtx.frame_size >
      0: encoderCtx.frame_size else: 1024

  var audioBuffer = initAudioBuffer(
    encoderCtx.sample_fmt, encoderCtx.ch_layout.nb_channels, requiredFrameSize
  )
  defer:
    if audioBuffer.fifo != nil:
      av_audio_fifo_free(audioBuffer.fifo)

  var audioResampler = createResampler(encoderCtx)

  let outputStream: ptr AVStream = avformat_new_stream(outputCtx, nil)
  if outputStream == nil:
    error "Could not allocate output stream"

  if avcodec_parameters_from_context(outputStream.codecpar, encoderCtx) < 0:
    error "Could not copy encoder parameters"

  outputStream.time_base = AVRational(num: 1, den: encoderCtx.sample_rate)
  outputStream.codecpar.codec_tag = 0

  if (outputCtx.oformat.flags and AVFMT_NOFILE) == 0:
    ret = avio_open(addr outputCtx.pb, outputPath.cstring, AVIO_FLAG_WRITE)
    if ret < 0:
      error fmt"Could not open output file '{outputPath}'"

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

  # Process any remaining buffered samples (pad with silence if needed)
  let remainingSamples = av_audio_fifo_size(audioBuffer.fifo)
  if remainingSamples > 0:
    let silenceSamples = requiredFrameSize - remainingSamples
    if silenceSamples > 0:
      var silenceFrame = av_frame_alloc()
      if silenceFrame != nil:
        silenceFrame.format = encoderCtx.sample_fmt.cint
        silenceFrame.ch_layout = encoderCtx.ch_layout
        silenceFrame.sample_rate = encoderCtx.sample_rate
        silenceFrame.nb_samples = silenceSamples

        if av_frame_get_buffer(silenceFrame, 0) >= 0:
          discard av_samples_set_silence(addr silenceFrame.data[0], 0, silenceSamples,
                                        encoderCtx.ch_layout.nb_channels,
                                        encoderCtx.sample_fmt)

          discard processAndEncodeFrame(audioResampler, encoderCtx, outputCtx,
            outputStream,
            audioBuffer, currentPts, silenceFrame)

        av_frame_free(addr silenceFrame)

  # Flush encoder
  for packet in encoderCtx.encode(nil, packet):
    packet.stream_index = outputStream.index
    av_packet_rescale_ts(packet, encoderCtx.time_base, outputStream.time_base)
    discard av_interleaved_write_frame(outputCtx, packet)
    av_packet_unref(packet)
