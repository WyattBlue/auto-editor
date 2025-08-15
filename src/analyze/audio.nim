import std/math
import std/strformat
import std/options

import ../av
import ../log
import ../cache
import ../ffmpeg
import ../util/bar
import ../resampler

# Enable project wide
{.passC: "-fno-signaling-nans -fno-math-errno -fno-trapping-math -freciprocal-math".}
{.passL: "-flto".}

type
  AudioIterator = ref object
    resampler: AudioResampler
    fifo: ptr AVAudioFifo
    exactSize: float64
    accumulatedError: float64
    sampleRate: cint
    channelCount: cint
    targetFormat: AVSampleFormat
    isInitialized: bool
    totalFramesProcessed: int
    totalSamplesWritten: int
    readBuffer: ptr uint8
    maxBufferSize: int

  AudioProcessor* = object
    `iterator`*: AudioIterator
    codecCtx*: ptr AVCodecContext
    audioIndex*: cint
    chunkDuration*: float64

proc newAudioIterator(sampleRate: cint, channelLayout: AVChannelLayout,
    chunkDuration: float64): AudioIterator =
  result = AudioIterator()
  result.sampleRate = sampleRate
  result.channelCount = channelLayout.nb_channels
  result.targetFormat = AV_SAMPLE_FMT_FLT # 32-bit float, interleaved
  result.exactSize = chunkDuration * float64(sampleRate)
  result.accumulatedError = 0.0
  result.isInitialized = false
  result.totalFramesProcessed = 0
  result.totalSamplesWritten = 0

  # Initialize AudioResampler to convert to float format
  let layoutName = if channelLayout.nb_channels == 1: "mono" else: "stereo"
  result.resampler = newAudioResampler(format = AV_SAMPLE_FMT_FLT, layout = layoutName,
      rate = sampleRate.int)

  # Initialize audio FIFO
  result.fifo = av_audio_fifo_alloc(result.targetFormat, result.channelCount, 1024)
  if result.fifo == nil:
    error "Could not allocate audio FIFO"

  # Pre-allocate buffer for reading chunks
  result.maxBufferSize = int(result.exactSize)
  let ret = av_samples_alloc(addr result.readBuffer, nil, result.channelCount.cint,
                           result.maxBufferSize.cint, result.targetFormat, 0)
  if ret < 0:
    error "Could not allocate read buffer"

proc cleanup(iter: AudioIterator) =
  if iter.fifo != nil:
    av_audio_fifo_free(iter.fifo)
    iter.fifo = nil

  if iter.readBuffer != nil:
    av_freep(addr iter.readBuffer)
    iter.readBuffer = nil

proc writeFrame(iter: AudioIterator, frame: ptr AVFrame) =
  iter.totalFramesProcessed += 1

  try:
    # Use AudioResampler to process the frame
    let resampledFrames = iter.resampler.resample(frame)

    # Write all resampled frames to FIFO
    for resampledFrame in resampledFrames:
      let ret = av_audio_fifo_write(iter.fifo, cast[pointer](addr resampledFrame.data[0]),
                                  resampledFrame.nb_samples)
      if ret < resampledFrame.nb_samples:
        error "Could not write data to FIFO"
      iter.totalSamplesWritten += resampledFrame.nb_samples

      # Free the resampled frame (since AudioResampler allocated it)
      av_frame_free(addr resampledFrame)

  except ValueError as e:
    error fmt"Error resampling audio frame: {e.msg}"

proc hasChunk(iter: AudioIterator): bool =
  let availableSamples = av_audio_fifo_size(iter.fifo)
  let needed = ceil(iter.exactSize).int
  return availableSamples >= needed

proc readChunk(iter: AudioIterator): float32 =
  # Calculate chunk size with accumulated error
  let sizeWithError = iter.exactSize + iter.accumulatedError
  let currentSize = round(sizeWithError).int
  iter.accumulatedError = sizeWithError - float64(currentSize)

  # Use pre-allocated buffer - no allocation needed!
  let samples = cast[ptr UncheckedArray[float32]](iter.readBuffer)
  let samplesRead = av_audio_fifo_read(iter.fifo, cast[pointer](
      addr iter.readBuffer), currentSize.cint)
  let totalSamples = samplesRead * iter.channelCount

  # Process 4 floats at once using SIMD-like operations
  let simdWidth = 4
  let simdSamples = totalSamples and not (simdWidth - 1) # Round down to multiple of 4

  var maxAbs: float32 = 0.0

  # Apply fast-math locally: see https://simonbyrne.github.io/notes/fastmath/
  {.push optimization: speed.}
  {.passC: "-ffast-math".}

  # SIMD-style loop (unrolled)
  for i in countup(0, simdSamples - 1, simdWidth):
    let v0 = abs(samples[i])
    let v1 = abs(samples[i + 1])
    let v2 = abs(samples[i + 2])
    let v3 = abs(samples[i + 3])

    maxAbs = max(maxAbs, max(max(v0, v1), max(v2, v3)))

  # Handle remaining samples
  for i in simdSamples ..< totalSamples:
    maxAbs = max(maxAbs, abs(samples[i]))

  {.pop.}

  return maxAbs

proc flushResampler(iter: AudioIterator) =
  # Flush the resampler by passing nil frame
  try:
    let flushedFrames = iter.resampler.resample(nil)

    # Write all flushed frames to FIFO
    for flushedFrame in flushedFrames:
      let ret = av_audio_fifo_write(iter.fifo, cast[pointer](addr flushedFrame.data[0]),
                                  flushedFrame.nb_samples)
      if ret < flushedFrame.nb_samples:
        error "Could not write flushed data to FIFO"
      iter.totalSamplesWritten += flushedFrame.nb_samples

      # Free the flushed frame
      av_frame_free(addr flushedFrame)

  except ValueError as e:
    error fmt"Error flushing audio resampler: {e.msg}"

iterator loudness*(processor: var AudioProcessor, container: InputContainer): float32 =
  var frame = av_frame_alloc()
  if frame == nil:
    error "Could not allocate frame"

  defer:
    av_frame_free(addr frame)
    if processor.`iterator` != nil:
      processor.`iterator`.cleanup()
    avcodec_free_context(addr processor.codecCtx)

  for decodedFrame in container.decode(processor.audioIndex, processor.codecCtx, frame):
    if processor.`iterator` == nil:
      processor.`iterator` = newAudioIterator(decodedFrame.sample_rate,
        decodedFrame.ch_layout, processor.chunkDuration)

    processor.`iterator`.writeFrame(decodedFrame)

    while processor.`iterator`.hasChunk():
      yield processor.`iterator`.readChunk()

  if processor.`iterator` != nil:
    processor.`iterator`.flushResampler()
    while processor.`iterator`.hasChunk():
      yield processor.`iterator`.readChunk()

proc audio*(bar: Bar, container: InputContainer, path: string, tb: AVRational,
    stream: int32): seq[float32] =
  let cacheData = readCache(path, tb, "audio", $stream)
  if cacheData.isSome:
    return cacheData.get()

  if stream < 0 or stream >= container.audio.len:
    error fmt"audio: audio stream '{stream}' does not exist."

  let audioStream: ptr AVStream = container.audio[stream]

  var processor = AudioProcessor(
    codecCtx: initDecoder(audioStream.codecpar),
    audioIndex: audioStream.index,
    chunkDuration: av_inv_q(tb),
  )

  var inaccurateDur: float = 1024.0
  if audioStream.duration != AV_NOPTS_VALUE and audioStream.time_base != AV_NOPTS_VALUE:
    inaccurateDur = float(audioStream.duration) * float(audioStream.time_base * tb)
  elif container.duration != 0.0:
    inaccurateDur = container.duration / float(tb)

  bar.start(inaccurateDur, "Analyzing audio volume")
  var i: float = 0
  for value in processor.loudness(container):
    result.add value
    bar.tick(i)
    i += 1

  bar.`end`()

  writeCache(result, path, tb, "audio", $stream)
