import std/[math, options, strformat]

import ../[av, cache, ffmpeg, log, resampler]
import ../util/[bar, rational, dnorm16]

when defined(arm64) or defined(aarch64):
  type
    Vec16x8 {.importc: "int16x8_t", header: "<arm_neon.h>".} = object

  proc neonLoad16(p: ptr int16): Vec16x8 {.importc: "vld1q_s16", header: "<arm_neon.h>".}
  proc neonDup16(x: int16): Vec16x8 {.importc: "vdupq_n_s16", header: "<arm_neon.h>".}
  # Saturating abs: clamps -32768 -> 32767 rather than wrapping
  proc neonQAbs16(v: Vec16x8): Vec16x8 {.importc: "vqabsq_s16", header: "<arm_neon.h>".}
  proc neonMax16(a, b: Vec16x8): Vec16x8 {.importc: "vmaxq_s16", header: "<arm_neon.h>".}
  proc neonMaxAcross16(v: Vec16x8): int16 {.importc: "vmaxvq_s16", header: "<arm_neon.h>".}

elif defined(emscripten):
  type
    V128 {.importc: "v128_t", header: "<wasm_simd128.h>".} = object

  proc wasmSplat16(x: int16): V128 {.importc: "wasm_i16x8_splat", header: "<wasm_simd128.h>".}
  proc wasmLoad(p: pointer): V128 {.importc: "wasm_v128_load", header: "<wasm_simd128.h>".}
  proc wasmStore(p: pointer, v: V128) {.importc: "wasm_v128_store", header: "<wasm_simd128.h>".}
  proc wasmSubSat16(a, b: V128): V128 {.importc: "wasm_i16x8_sub_sat", header: "<wasm_simd128.h>".}
  proc wasmMax16(a, b: V128): V128 {.importc: "wasm_i16x8_max", header: "<wasm_simd128.h>".}
  # Saturating abs: max(v, 0 - v). wasm_i16x8_abs would wrap -32768, so use
  # sub_sat instead, which clamps -32768 -> 32767.
  proc wasmAbs16(v: V128): V128 {.inline.} = wasmMax16(v, wasmSubSat16(wasmSplat16(0), v))

elif defined(amd64) or defined(i386):
  type
    M128i {.importc: "__m128i", header: "<emmintrin.h>".} = object

  proc sseZero(): M128i {.importc: "_mm_setzero_si128", header: "<emmintrin.h>".}
  proc sseLoad(p: pointer): M128i {.importc: "_mm_loadu_si128", header: "<emmintrin.h>".}
  proc sseStore(p: pointer, v: M128i) {.importc: "_mm_storeu_si128", header: "<emmintrin.h>".}
  proc sseSubs16(a, b: M128i): M128i {.importc: "_mm_subs_epi16", header: "<emmintrin.h>".}
  proc sseMax16(a, b: M128i): M128i {.importc: "_mm_max_epi16", header: "<emmintrin.h>".}
  # Saturating abs: max(v, 0 - v) clamps -32768 -> 32767 (subs saturates).
  proc sseAbs16(v: M128i): M128i {.inline.} = sseMax16(v, sseSubs16(sseZero(), v))

type
  AudioIterator = ref object
    resampler: AudioResampler
    fifo: ptr AVAudioFifo
    exactSize: float64
    accumulatedError: float64
    sampleRate: cint
    channelCount: cint
    targetFormat: AVSampleFormat
    readBuffer: ptr uint8
    maxBufferSize: int
    totalFramesProcessed: int = 0
    totalSamplesWritten: int = 0
    isInitialized: bool = false

  AudioProcessor* = object
    `iterator`*: AudioIterator
    codecCtx*: ptr AVCodecContext
    audioIndex*: cint
    chunkDuration*: float64

proc newAudioIterator(sampleRate: cint, channelLayout: ptr AVChannelLayout,
    chunkDuration: float64): AudioIterator =
  result = AudioIterator()
  result.sampleRate = sampleRate
  result.channelCount = channelLayout.nb_channels
  result.targetFormat = AV_SAMPLE_FMT_S16
  result.exactSize = chunkDuration * float64(sampleRate)
  result.accumulatedError = 0.0
  var layoutRef: ref AVChannelLayout
  new(layoutRef)
  discard av_channel_layout_copy(addr layoutRef[], channelLayout)
  result.resampler = newAudioResampler(AV_SAMPLE_FMT_S16, layoutRef, sampleRate)

  # Initialize audio FIFO
  result.fifo = av_audio_fifo_alloc(result.targetFormat, result.channelCount, 1024)
  if result.fifo == nil:
    error "Could not allocate audio FIFO"

  # Pre-allocate buffer for reading chunks
  result.maxBufferSize = int(result.exactSize)
  let ret = av_samples_alloc(addr result.readBuffer, nil, result.channelCount,
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
    error &"Error resampling audio frame: {e.msg}"

proc hasChunk(iter: AudioIterator): bool =
  let availableSamples = av_audio_fifo_size(iter.fifo)
  let needed = ceil(iter.exactSize).int
  return availableSamples >= needed

proc readChunk(iter: AudioIterator): Unorm16 =
  # Calculate chunk size with accumulated error
  let sizeWithError = iter.exactSize + iter.accumulatedError
  let currentSize = round(sizeWithError).int
  iter.accumulatedError = sizeWithError - float64(currentSize)

  let samples = cast[ptr UncheckedArray[int16]](iter.readBuffer)
  let samplesRead = av_audio_fifo_read(
    iter.fifo, cast[pointer](addr iter.readBuffer), currentSize.cint
  )
  let totalSamples = samplesRead * iter.channelCount

  var maxAbs: int32 = 0
  when defined(arm64) or defined(aarch64):
    # Four independent accumulators hide the latency of the abs/max chain.
    var v0 = neonDup16(0'i16)
    var v1 = neonDup16(0'i16)
    var v2 = neonDup16(0'i16)
    var v3 = neonDup16(0'i16)
    var i = 0
    while i + 32 <= totalSamples:
      v0 = neonMax16(v0, neonQAbs16(neonLoad16(addr samples[i])))
      v1 = neonMax16(v1, neonQAbs16(neonLoad16(addr samples[i + 8])))
      v2 = neonMax16(v2, neonQAbs16(neonLoad16(addr samples[i + 16])))
      v3 = neonMax16(v3, neonQAbs16(neonLoad16(addr samples[i + 24])))
      i += 32
    var vmax = neonMax16(neonMax16(v0, v1), neonMax16(v2, v3))
    while i + 8 <= totalSamples:
      vmax = neonMax16(vmax, neonQAbs16(neonLoad16(addr samples[i])))
      i += 8
    maxAbs = int32(neonMaxAcross16(vmax))
    while i < totalSamples:
      let v = abs(int32(samples[i]))
      if v > maxAbs: maxAbs = v
      i += 1
  elif defined(emscripten):
    var v0 = wasmSplat16(0)
    var v1 = wasmSplat16(0)
    var i = 0
    while i + 16 <= totalSamples:
      v0 = wasmMax16(v0, wasmAbs16(wasmLoad(addr samples[i])))
      v1 = wasmMax16(v1, wasmAbs16(wasmLoad(addr samples[i + 8])))
      i += 16
    var vmax = wasmMax16(v0, v1)
    while i + 8 <= totalSamples:
      vmax = wasmMax16(vmax, wasmAbs16(wasmLoad(addr samples[i])))
      i += 8
    var lanes: array[8, int16]
    wasmStore(addr lanes[0], vmax)
    for lane in lanes:
      if int32(lane) > maxAbs: maxAbs = int32(lane)
    while i < totalSamples:
      let v = abs(int32(samples[i]))
      if v > maxAbs: maxAbs = v
      i += 1
  elif defined(amd64) or defined(i386):
    var v0 = sseZero()
    var v1 = sseZero()
    var i = 0
    while i + 16 <= totalSamples:
      v0 = sseMax16(v0, sseAbs16(sseLoad(addr samples[i])))
      v1 = sseMax16(v1, sseAbs16(sseLoad(addr samples[i + 8])))
      i += 16
    var vmax = sseMax16(v0, v1)
    while i + 8 <= totalSamples:
      vmax = sseMax16(vmax, sseAbs16(sseLoad(addr samples[i])))
      i += 8
    var lanes: array[8, int16]
    sseStore(addr lanes[0], vmax)
    for lane in lanes:
      if int32(lane) > maxAbs: maxAbs = int32(lane)
    while i < totalSamples:
      let v = abs(int32(samples[i]))
      if v > maxAbs: maxAbs = v
      i += 1
  else:
    for i in 0 ..< totalSamples:
      let v = abs(int32(samples[i]))
      if v > maxAbs:
        maxAbs = v
        if maxAbs >= 32767: break

  return toUnorm16(float32(maxAbs) / 32767.0'f32)

proc readPeaks(iter: AudioIterator): tuple[lo, hi: float32] =
  let sizeWithError = iter.exactSize + iter.accumulatedError
  let currentSize = round(sizeWithError).int
  iter.accumulatedError = sizeWithError - float64(currentSize)

  let samples = cast[ptr UncheckedArray[int16]](iter.readBuffer)
  let samplesRead = av_audio_fifo_read(
    iter.fifo, cast[pointer](addr iter.readBuffer), currentSize.cint
  )
  let totalSamples = samplesRead * iter.channelCount

  var minV: int32 = 0
  var maxV: int32 = 0
  for i in 0 ..< totalSamples:
    let v = int32(samples[i])
    if v < minV: minV = v
    if v > maxV: maxV = v
  return (float32(minV) / 32768.0'f32, float32(maxV) / 32768.0'f32)

proc flushResampler(iter: AudioIterator) =
  # Flush the resampler by passing nil frame
  let flushedFrames = iter.resampler.resample(nil)

  for flushedFrame in flushedFrames:
    let ret = av_audio_fifo_write(iter.fifo, cast[pointer](addr flushedFrame.data[0]),
                                flushedFrame.nb_samples)
    if ret < flushedFrame.nb_samples:
      error "Could not write flushed data to FIFO"
    iter.totalSamplesWritten += flushedFrame.nb_samples
    av_frame_free(addr flushedFrame)

iterator peaks*(processor: var AudioProcessor, container: InputContainer,
    audioStream: ptr AVStream): tuple[startSample: int64, lo, hi: float32] =
  var frame = av_frame_alloc()
  if frame == nil:
    error "Could not allocate frame"

  defer:
    av_frame_free(addr frame)
    if processor.`iterator` != nil:
      processor.`iterator`.cleanup()
    avcodec_free_context(addr processor.codecCtx)

  var firstSamplePos: int64 = 0
  var bucketIdx: int64 = 0
  var spb: int64 = 0

  for decodedFrame in container.decode(processor.audioIndex, processor.codecCtx, frame):
    if processor.`iterator` == nil:
      processor.`iterator` = newAudioIterator(decodedFrame.sample_rate,
        addr decodedFrame.ch_layout, processor.chunkDuration)
      spb = round(processor.chunkDuration * float64(decodedFrame.sample_rate)).int64
      let tb = audioStream.time_base
      let pts = (if decodedFrame.pts == AV_NOPTS_VALUE: 0'i64 else: decodedFrame.pts)
      firstSamplePos = (pts * int64(decodedFrame.sample_rate) * int64(tb.num)) div int64(tb.den)

    processor.`iterator`.writeFrame(decodedFrame)

    while processor.`iterator`.hasChunk():
      let (lo, hi) = processor.`iterator`.readPeaks()
      yield (firstSamplePos + bucketIdx * spb, lo, hi)
      bucketIdx += 1

  if processor.`iterator` != nil:
    processor.`iterator`.flushResampler()
    while processor.`iterator`.hasChunk():
      let (lo, hi) = processor.`iterator`.readPeaks()
      yield (firstSamplePos + bucketIdx * spb, lo, hi)
      bucketIdx += 1

iterator loudness*(processor: var AudioProcessor, container: InputContainer): Unorm16 =
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
        addr decodedFrame.ch_layout, processor.chunkDuration)

    processor.`iterator`.writeFrame(decodedFrame)

    while processor.`iterator`.hasChunk():
      yield processor.`iterator`.readChunk()

  if processor.`iterator` != nil:
    processor.`iterator`.flushResampler()
    while processor.`iterator`.hasChunk():
      yield processor.`iterator`.readChunk()

proc audio*(bar: Bar, container: InputContainer, path: string, tb: AVRational,
    stream: int32): seq[Unorm16] =
  if not noCache:
    let cacheData = readCache[Unorm16](path, tb, "audio", $stream)
    if cacheData.isSome:
      return cacheData.get()

  if stream < 0 or stream >= container.audio.len:
    error &"audio: audio stream '{stream}' does not exist."

  let audioStream: ptr AVStream = container.audio[stream]
  # Rewind so a shared container can be re-read for additional streams.
  container.seek(0)

  var processor = AudioProcessor(
    codecCtx: initDecoder(audioStream.codecpar),
    audioIndex: audioStream.index,
    chunkDuration: av_inv_q(tb),
  )

  var inaccurateDur: float = 1024.0
  var knownDur = true
  if audioStream.duration != AV_NOPTS_VALUE and audioStream.time_base != AV_NOPTS_VALUE:
    inaccurateDur = float(audioStream.duration) * float(audioStream.time_base * tb)
  elif container.duration != 0.0:
    inaccurateDur = container.duration / float(tb)
  else:
    knownDur = false

  if knownDur:
    bar.start(inaccurateDur, "Analyzing audio volume")
  else:
    bar.startIndeterminate("Analyzing audio volume")
  result = newSeqOfCap[Unorm16](int(inaccurateDur) + 1)
  var i: float = 0
  for value in processor.loudness(container):
    result.add value
    bar.tick(i)
    i += 1

  bar.`end`()

  if not noCache:
    writeCache(result, tb, path, "audio", $stream)
