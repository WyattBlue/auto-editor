import std/strformat
import std/tables
import std/os
import std/memfiles

import ../log
import ../timeline
import ../[av, ffmpeg]
import ../resampler

const AV_CH_LAYOUT_STEREO = 3
const AV_CH_LAYOUT_MONO = 1

type
  Getter = ref object
    container*: InputContainer
    stream*: ptr AVStream
    decoderCtx*: ptr AVCodecContext
    rate*: int

  AudioBuffer = ref object
    memFile*: MemFile
    data*: ptr UncheckedArray[int16]
    size*: int
    channels*: int
    samples*: int
    tempFilePath*: string

proc newAudioBuffer(index: int32, samples: int, channels: int): AudioBuffer =
  result = new(AudioBuffer)
  result.samples = samples
  result.channels = channels
  result.size = samples * channels * sizeof(int16)
  result.tempFilePath = tempDir / &"{index}.map"

  # Memory map the file
  result.memFile = memfiles.open(result.tempFilePath, mode = fmReadWrite,
      newFileSize = result.size)
  result.data = cast[ptr UncheckedArray[int16]](result.memFile.mem)

  # Initialize with silence
  for i in 0..<(result.size div sizeof(int16)):
    result.data[i] = 0

proc `[]`*(buffer: AudioBuffer, index: int): int16 {.inline.} =
  buffer.data[index]

proc `[]=`*(buffer: AudioBuffer, index: int, value: int16) {.inline.} =
  buffer.data[index] = value

proc len(buffer: AudioBuffer): int {.inline.} =
  ## Get total number of samples (all channels)
  buffer.size div sizeof(int16)

proc newGetter(path: string, stream: int, rate: int): Getter =
  result = new(Getter)
  result.container = av.open(path)
  result.stream = result.container.audio[stream]
  result.rate = rate
  result.decoderCtx = initDecoder(result.stream.codecpar)

proc close(getter: Getter) =
  avcodec_free_context(addr getter.decoderCtx)
  getter.container.close()

proc get(getter: Getter, start: int, endSample: int): seq[seq[int16]] =
  # start/end is in samples
  let container = getter.container
  let stream = getter.stream
  let decoderCtx = getter.decoderCtx

  let targetSamples = endSample - start

  # Initialize result with proper size and zero-filled data
  result = @[newSeq[int16](targetSamples), newSeq[int16](targetSamples)]

  # Fill with silence initially
  for ch in 0..<result.len:
    for i in 0..<targetSamples:
      result[ch][i] = 0

  # Convert sample position to time and seek
  let sampleRate = stream.codecpar.sample_rate
  let timeBase = stream.time_base
  let startTimeInSeconds = start.float / sampleRate.float
  let startPts = int64(startTimeInSeconds / (timeBase.num.float /
      timeBase.den.float))

  # Seek to the approximate position
  if av_seek_frame(container.formatContext, stream.index, startPts,
      AVSEEK_FLAG_BACKWARD) < 0:
    # If seeking fails, fall back to reading from beginning
    discard av_seek_frame(container.formatContext, stream.index, 0, AVSEEK_FLAG_BACKWARD)

  # Flush decoder after seeking
  avcodec_flush_buffers(decoderCtx)

  var packet = av_packet_alloc()
  var frame = av_frame_alloc()
  defer:
    av_packet_free(addr packet)
    av_frame_free(addr frame)

  var totalSamples = 0
  var samplesProcessed = 0

  # Decode frames until we have enough samples
  while av_read_frame(container.formatContext, packet) >= 0 and totalSamples < targetSamples:
    defer: av_packet_unref(packet)

    if packet.stream_index == stream.index:
      if avcodec_send_packet(decoderCtx, packet) >= 0:
        while avcodec_receive_frame(decoderCtx, frame) >= 0 and totalSamples < targetSamples:
          let channels = min(frame.ch_layout.nb_channels.int, 2) # Limit to stereo
          let samples = frame.nb_samples.int

          # Convert frame PTS to sample position
          let frameSamplePos = if frame.pts != AV_NOPTS_VALUE:
            int64(frame.pts.float * timeBase.num.float / timeBase.den.float *
                sampleRate.float)
          else:
            samplesProcessed.int64

          # If this frame is before our target start, skip it
          if frameSamplePos + samples.int64 <= start.int64:
            samplesProcessed += samples
            continue

          # Calculate how many samples to skip in this frame
          let samplesSkippedInFrame = max(0, start - frameSamplePos.int)
          let samplesInFrame = samples - samplesSkippedInFrame
          let samplesToProcess = min(samplesInFrame, targetSamples - totalSamples)

          # Process audio samples based on format
          if frame.format == AV_SAMPLE_FMT_S16.cint:
            # Interleaved 16-bit
            let audioData = cast[ptr UncheckedArray[int16]](frame.data[0])
            for i in 0..<samplesToProcess:
              let frameIndex = samplesSkippedInFrame + i
              for ch in 0..<channels:
                if totalSamples + i < targetSamples:
                  result[ch][totalSamples + i] = audioData[frameIndex *
                      channels + ch]

          elif frame.format == AV_SAMPLE_FMT_S16P.cint:
            # Planar 16-bit
            for i in 0..<samplesToProcess:
              let frameIndex = samplesSkippedInFrame + i
              for ch in 0..<channels:
                if totalSamples + i < targetSamples and frame.data[ch] != nil:
                  let channelData = cast[ptr UncheckedArray[int16]](frame.data[ch])
                  result[ch][totalSamples + i] = channelData[frameIndex]

          elif frame.format == AV_SAMPLE_FMT_FLT.cint:
            # Interleaved float
            let audioData = cast[ptr UncheckedArray[cfloat]](frame.data[0])
            for i in 0..<samplesToProcess:
              let frameIndex = samplesSkippedInFrame + i
              for ch in 0..<channels:
                if totalSamples + i < targetSamples:
                  # Convert float to 16-bit int with proper clamping
                  let floatSample = audioData[frameIndex * channels + ch]
                  let clampedSample = max(-1.0, min(1.0, floatSample))
                  result[ch][totalSamples + i] = int16(clampedSample * 32767.0)

          elif frame.format == AV_SAMPLE_FMT_FLTP.cint:
            # Planar float
            for i in 0..<samplesToProcess:
              let frameIndex = samplesSkippedInFrame + i
              for ch in 0..<channels:
                if totalSamples + i < targetSamples and frame.data[ch] != nil:
                  let channelData = cast[ptr UncheckedArray[cfloat]](frame.data[ch])
                  # Convert float to 16-bit int with proper clamping
                  let floatSample = channelData[frameIndex]
                  let clampedSample = max(-1.0, min(1.0, floatSample))
                  result[ch][totalSamples + i] = int16(clampedSample * 32767.0)
          else:
            # Unsupported format - samples already initialized to silence
            discard

          totalSamples += samplesToProcess
          samplesProcessed += samples

  # If we have mono input, duplicate to second channel
  if result.len >= 2 and result[0].len > 0 and result[1].len > 0:
    # Check if second channel is all zeros (mono source)
    var isSecondChannelEmpty = true
    for i in 0..<min(100, result[1].len): # Check first 100 samples
      if result[1][i] != 0:
        isSecondChannelEmpty = false
        break

    if isSecondChannelEmpty:
      # Copy first channel to second for stereo output
      for i in 0..<result[0].len:
        result[1][i] = result[0][i]

proc createAudioFilterGraph(clip: Clip, sr: int, layout: string): (ptr AVFilterGraph,
    ptr AVFilterContext, ptr AVFilterContext) =
  var filterGraph: ptr AVFilterGraph = avfilter_graph_alloc()
  var bufferSrc: ptr AVFilterContext = nil
  var bufferSink: ptr AVFilterContext = nil

  if filterGraph == nil:
    error "Could not allocate audio filter graph"

  let bufferArgs = &"sample_rate={sr}:sample_fmt=s16p:channel_layout={layout}:time_base=1/{sr}"
  var ret = avfilter_graph_create_filter(addr bufferSrc, avfilter_get_by_name("abuffer"),
                                        "in", bufferArgs.cstring, nil, filterGraph)
  if ret < 0:
    error fmt"Cannot create audio buffer source: {ret}"

  # Create buffer sink
  ret = avfilter_graph_create_filter(addr bufferSink, avfilter_get_by_name("abuffersink"),
                                    "out", nil, nil, filterGraph)
  if ret < 0:
    error fmt"Cannot create audio buffer sink: {ret}"

  var filterChain = ""
  var needsFilters = false

  if clip.speed != 1.0:
    needsFilters = true
    let clampedSpeed = max(0.5, min(100.0, clip.speed))
    if filterChain != "":
      filterChain &= ","
    filterChain &= fmt"atempo={clampedSpeed}"

  if clip.volume != 1.0:
    needsFilters = true
    if filterChain != "":
      filterChain &= ","
    filterChain &= fmt"volume={clip.volume}"

  if not needsFilters:
    filterChain = "anull"

  var inputs = avfilter_inout_alloc()
  var outputs = avfilter_inout_alloc()
  if inputs == nil or outputs == nil:
    error "Could not allocate filter inputs/outputs"

  outputs.name = av_strdup("in")
  outputs.filter_ctx = bufferSrc
  outputs.pad_idx = 0
  outputs.next = nil

  inputs.name = av_strdup("out")
  inputs.filter_ctx = bufferSink
  inputs.pad_idx = 0
  inputs.next = nil

  ret = avfilter_graph_parse_ptr(filterGraph, filterChain.cstring, addr inputs,
      addr outputs, nil)
  if ret < 0:
    error fmt"Could not parse audio filter graph: {ret}"

  ret = avfilter_graph_config(filterGraph, nil)
  if ret < 0:
    error fmt"Could not configure audio filter graph: {ret}"

  avfilter_inout_free(addr inputs)
  avfilter_inout_free(addr outputs)

  return (filterGraph, bufferSrc, bufferSink)

proc processAudioClip(clip: Clip, data: seq[seq[int16]], sr: cint): seq[seq[int16]] =
  if clip.speed == 1.0 and clip.volume == 1.0:
    return data
  if data.len == 0 or data[0].len == 0:
    return data

  let actualChannels = data.len
  let channels = if actualChannels == 1: 1 else: 2 # Determine if we have mono or stereo
  let samples = data[0].len

  let layout = (if channels == 1: "mono" else: "stereo")
  let (filterGraph, bufferSrc, bufferSink) = createAudioFilterGraph(clip, sr, layout)
  defer:
    if filterGraph != nil:
      avfilter_graph_free(addr filterGraph)

  # Create audio frame with input data
  var inputFrame = av_frame_alloc()
  if inputFrame == nil:
    error "Could not allocate input audio frame"
  defer: av_frame_free(addr inputFrame)

  inputFrame.nb_samples = samples.cint
  inputFrame.format = AV_SAMPLE_FMT_S16P.cint
  inputFrame.ch_layout.nb_channels = channels.cint
  inputFrame.ch_layout.order = 0
  inputFrame.ch_layout.u.mask = (if channels ==
      1: AV_CH_LAYOUT_MONO else: AV_CH_LAYOUT_STEREO)
  inputFrame.sample_rate = sr
  inputFrame.pts = AV_NOPTS_VALUE # Let the filter handle timing

  if av_frame_get_buffer(inputFrame, 0) < 0:
    error "Could not allocate input audio frame buffer"

  # Copy input data to frame (planar format)
  for ch in 0..<channels:
    let channelData = cast[ptr UncheckedArray[int16]](inputFrame.data[ch])
    for i in 0..<samples:
      if ch == 0:
        # Always copy first channel
        if i < data[0].len:
          channelData[i] = data[0][i]
        else:
          channelData[i] = 0
      elif ch == 1:
        # For second channel: use second channel if available, otherwise duplicate first
        if actualChannels >= 2 and i < data[1].len:
          channelData[i] = data[1][i]
        elif i < data[0].len:
          channelData[i] = data[0][i] # Duplicate mono to stereo
        else:
          channelData[i] = 0
      else:
        # Should not happen with our logic, but just in case
        channelData[i] = 0

  # Process through filter graph
  var outputFrames: seq[ptr AVFrame] = @[]
  defer:
    for frame in outputFrames:
      av_frame_free(addr frame)

  # Send frame to filter
  if av_buffersrc_write_frame(bufferSrc, inputFrame) < 0:
    error "Error adding frame to audio filter"

  # Flush filter by sending null frame
  if av_buffersrc_write_frame(bufferSrc, nil) < 0:
    error "Error flushing audio filter"

  # Collect output frames
  while true:
    var outputFrame = av_frame_alloc()
    if outputFrame == nil:
      error "Could not allocate output audio frame"

    let ret = av_buffersink_get_frame(bufferSink, outputFrame)
    if ret < 0:
      av_frame_free(addr outputFrame)
      break

    outputFrames.add(outputFrame)

  # Convert output frames back to seq[seq[int16]]
  if outputFrames.len == 0:
    # No output frames, return empty data
    result = @[newSeq[int16](0), newSeq[int16](0)]
    return

  # Calculate total output samples
  var totalSamples = 0
  for frame in outputFrames:
    totalSamples += frame.nb_samples.int


  # Initialize result with proper size
  result = @[newSeq[int16](totalSamples), newSeq[int16](totalSamples)]

  # Copy data from output frames
  var sampleOffset = 0
  for frame in outputFrames:
    let frameSamples = frame.nb_samples.int
    let frameChannels = min(frame.ch_layout.nb_channels.int, 2)

    # Handle different output formats from the filter
    if frame.format == AV_SAMPLE_FMT_S16P.cint:
      # Planar format - each channel has its own data array
      for ch in 0..<min(result.len, frameChannels):
        if frame.data[ch] != nil:
          let channelData = cast[ptr UncheckedArray[int16]](frame.data[ch])
          for i in 0..<frameSamples:
            if sampleOffset + i < result[ch].len:
              result[ch][sampleOffset + i] = channelData[i]
    elif frame.format == AV_SAMPLE_FMT_S16.cint:
      # Interleaved format - all channels in one data array
      let audioData = cast[ptr UncheckedArray[int16]](frame.data[0])
      for i in 0..<frameSamples:
        for ch in 0..<min(result.len, frameChannels):
          if sampleOffset + i < result[ch].len:
            result[ch][sampleOffset + i] = audioData[i * frameChannels + ch]
    else:
      # Unsupported format - skip this frame or convert
      error fmt"Unsupported output frame format: {frame.format}"

    sampleOffset += frameSamples

  # If we have mono input, duplicate to second channel
  if result.len >= 2 and result[0].len > 0 and result[1].len > 0:
    var isSecondChannelEmpty = true
    for i in 0..<min(100, result[1].len):
      if result[1][i] != 0:
        isSecondChannelEmpty = false
        break

    if isSecondChannelEmpty:
      for i in 0..<result[0].len:
        result[1][i] = result[0][i]


proc makeAudioFrames(fmt: AVSampleFormat, tl: v3, frameSize: int, layerIndices: seq[
    int], mixLayers: bool): iterator(): (ptr AVFrame, int) =
  var samples: Table[(string, int32), Getter]
  let targetChannels = 2

  let tb = tl.tb
  let sr = tl.sr

  # Collect all unique audio sources from specified layers
  for layerIndex in layerIndices:
    if layerIndex < tl.a.len:
      let layer = tl.a[layerIndex]
      for clip in layer.clips:
        let key = (clip.src[], clip.stream)
        if key notin samples:
          samples[key] = newGetter(clip.src[], clip.stream.int, sr)

  # Calculate total duration across specified layers
  var totalDuration = 0
  for layerIndex in layerIndices:
    if layerIndex < tl.a.len:
      let layer = tl.a[layerIndex]
      for clip in layer.clips:
        totalDuration = max(totalDuration, clip.start + clip.dur)

  let totalSamples = int(totalDuration * sr.int64 * tb.den div tb.num)

  # Create memory-mapped buffer
  let bufferIndex = if mixLayers: -1.int32 else: layerIndices[0].int32
  var audioBuffer = newAudioBuffer(bufferIndex, totalSamples, targetChannels)

  # Process each layer and either mix or replace samples
  for layerIndex in layerIndices:
    if layerIndex < tl.a.len:
      let layer = tl.a[layerIndex]

      # Process each clip in this layer
      for clip in layer.clips:
        let key = (clip.src[], clip.stream)
        if key in samples:
          let sampStart = int(clip.offset.float64 * clip.speed * sr.float64 / tb)
          let sampEnd = int(float64(clip.offset + clip.dur) * clip.speed * sr.float64 / tb)

          let getter = samples[key]
          let srcData = getter.get(sampStart, sampEnd)

          let startSample = int(clip.start * sr.int64 * tb.den div tb.num)
          let durSamples = int(clip.dur * sr.int64 * tb.den div tb.num)
          let processedData = processAudioClip(clip, srcData, sr)

          if processedData.len > 0:
            let numChannels = min(targetChannels, processedData.len)
            for i in 0 ..< min(durSamples, processedData[0].len):
              let outputSampleIndex = startSample + i
              if outputSampleIndex < totalSamples:
                # Calculate the base index in the memory-mapped array for this sample
                let baseIndex = outputSampleIndex * targetChannels

                for ch in 0 ..< numChannels:
                  let flatIndex = baseIndex + ch
                  if flatIndex < audioBuffer.len and i < processedData[ch].len:
                    if mixLayers:
                      # Mix: add new sample to existing
                      let currentSample = audioBuffer[flatIndex].int32
                      let newSample = processedData[ch][i].int32
                      let mixed = currentSample + newSample
                      # Clamp to 16-bit range to prevent overflow distortion
                      audioBuffer[flatIndex] = int16(max(-32768, min(32767, mixed)))
                    else:
                      # Replace: direct assignment (for single layer)
                      audioBuffer[flatIndex] = processedData[ch][i]

                # If source has fewer channels than target, duplicate the last channel
                if numChannels < targetChannels:
                  for ch in numChannels ..< targetChannels:
                    let flatIndex = baseIndex + ch
                    let sourceChannel = numChannels - 1 # Use the last available channel
                    let sourceFlatIndex = baseIndex + sourceChannel
                    if flatIndex < audioBuffer.len and sourceFlatIndex <
                        audioBuffer.len:
                      audioBuffer[flatIndex] = audioBuffer[sourceFlatIndex]

  # Yield audio frames in chunks
  var samplesYielded = 0
  var frameIndex = 0
  var resampler = newAudioResampler(fmt, "stereo", sr)
  var frame = av_frame_alloc()
  if frame == nil:
    error "Could not allocate audio frame"

  return iterator(): (ptr AVFrame, int) =
    while samplesYielded < totalSamples:
      let currentFrameSize = min(frameSize, totalSamples - samplesYielded)

      frame.nb_samples = currentFrameSize.cint
      frame.format = AV_SAMPLE_FMT_S16P.cint # Planar format
      frame.ch_layout.nb_channels = targetChannels.cint
      frame.ch_layout.order = 0
      frame.ch_layout.u.mask = AV_CH_LAYOUT_STEREO
      frame.sample_rate = sr.cint
      frame.pts = samplesYielded.int64
      frame.time_base = AVRational(num: 1, den: sr.cint)

      if av_frame_get_buffer(frame, 0) < 0:
        error "Could not allocate audio frame buffer"

      # Copy audio data from memory-mapped buffer to frame (convert to planar format)
      for ch in 0 ..< targetChannels:
        let channelData = cast[ptr UncheckedArray[int16]](frame.data[ch])
        for i in 0..<currentFrameSize:
          let srcSampleIndex = samplesYielded + i
          if srcSampleIndex < totalSamples:
            # Calculate index in memory-mapped interleaved array
            let flatIndex = srcSampleIndex * targetChannels + ch
            if flatIndex < audioBuffer.len:
              channelData[i] = audioBuffer[flatIndex]
            else:
              channelData[i] = 0
          else:
            channelData[i] = 0

      for newFrame in resampler.resample(frame):
        yield (newFrame, frameIndex)
        frameIndex += 1
      samplesYielded += currentFrameSize

    # Ensure cleanup happens when iterator is done
    defer:
      av_frame_free(addr frame)
      for getter in samples.values:
        getter.close()
      audioBuffer.memFile.close()

proc makeMixedAudioFrames*(fmt: AVSampleFormat, tl: v3, frameSize: int): iterator(): (
    ptr AVFrame, int) =
  # Create sequence of all layer indices
  var allLayerIndices: seq[int] = @[]
  for i in 0..<tl.a.len:
    allLayerIndices.add(i)
  return makeAudioFrames(fmt, tl, frameSize, allLayerIndices, mixLayers = true)

proc makeNewAudioFrames*(fmt: AVSampleFormat, index: int32, tl: v3,
    frameSize: int): iterator(): (ptr AVFrame, int) =
  return makeAudioFrames(fmt, tl, frameSize, @[index.int], mixLayers = false)

