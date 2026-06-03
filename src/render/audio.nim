import std/[json, math, strformat, strutils, sequtils, tables]

import ../[action, av, ffmpeg, graph, log, resampler, timeline]
import ../util/[dnorm16, rational]

# Import C string functions for JSON capture
proc strchr(s: cstring, c: cint): cstring {.importc, header: "<string.h>".}
proc strlen(s: cstring): csize_t {.importc, header: "<string.h>".}

# `va_copy` / `va_end` are macros that require lvalue access to their va_list
# argument, so they can't be imported directly when Nim passes `var VaList`
# as a pointer. Wrap them in tiny C helpers that dereference for us.
{.emit: """#include <stdarg.h>
static void nim_va_copy(va_list *dst, va_list src) { va_copy(*dst, src); }
static void nim_va_end(va_list *ap) { va_end(*ap); }
""".}
proc va_copy(dest: var VaList, src: VaList) {.importc: "nim_va_copy", nodecl.}
proc va_end(ap: var VaList) {.importc: "nim_va_end", nodecl.}

type LoudnormCapture = ref object
  buffer: array[16384, char]
  used: int

# Pointer to the currently active capture session, or nil. The C log callback
# has no user-data parameter, so we have to route through a single global, but
# the actual buffer state lives in a per-session object — concurrent or stale
# captures can't clobber each other's storage.
var activeCapture: LoudnormCapture = nil

proc loudnormLogCallbackWrapper(avcl: pointer, level: cint, fmt: ConstCString, vl: VaList) {.cdecl.} =
  let cap = activeCapture
  if cap == nil:
    av_log_default_callback(avcl, level, fmt, vl)
    return

  # vsnprintf consumes its VaList, so format into our local buffer using a copy
  # and leave `vl` untouched for the default callback below.
  var vlCopy: VaList
  va_copy(vlCopy, vl)
  var buffer: array[4096, char]
  discard vsnprintf(cast[cstring](addr buffer[0]), 4096, fmt, vlCopy)
  va_end(vlCopy)

  # Look for JSON content and append to the session's buffer
  let bufStr = cast[cstring](addr buffer[0])
  if strchr(bufStr, ord('{').cint) != nil and strchr(bufStr, ord('}').cint) != nil:
    let msgLen = strlen(bufStr).int
    let remaining = cap.buffer.len - cap.used - 1
    if remaining > 0 and msgLen > 0:
      let toCopy = min(msgLen, remaining)
      copyMem(addr cap.buffer[cap.used], bufStr, toCopy)
      cap.used += toCopy
      cap.buffer[cap.used] = '\0'

  av_log_default_callback(avcl, level, fmt, vl)

proc beginLoudnormCapture(): LoudnormCapture =
  if activeCapture != nil:
    error "loudnorm capture is already active"
  result = LoudnormCapture(used: 0)
  result.buffer[0] = '\0'
  activeCapture = result
  av_log_set_callback(loudnormLogCallbackWrapper)

proc endLoudnormCapture(cap: LoudnormCapture) =
  av_log_set_callback(av_log_default_callback)
  if activeCapture == cap:
    activeCapture = nil

proc getCaptured(cap: LoudnormCapture): string =
  result = newString(cap.used)
  if cap.used > 0:
    copyMem(addr result[0], addr cap.buffer[0], cap.used)

proc parseLoudnormValue(node: JsonNode, field: string): float32 =
  if node.hasKey(field):
    let value = node[field]
    if value.kind == JString:
      let strVal = value.getStr()
      if strVal == "-inf":
        return -99.0
      elif strVal == "inf":
        return 0.0
      else:
        return parseFloat(strVal).float32
    if value.kind == JFloat:
      let valNum = value.getFloat()
      if valNum == -Inf:
        return -99.0
      if valNum == Inf:
        return 0.0
      return valNum.float32
    elif value.kind == JInt:
      return value.getInt().float32
  return 0.0

type
  Getter = ref object
    container*: InputContainer
    stream*: ptr AVStream
    decoderCtx*: ptr AVCodecContext
    layout*: ref AVChannelLayout
    rate*: cint

func clamp16(v: int32): int16 {.inline.} =
  int16(max(-32768'i32, min(32767'i32, v)))

func channels(self: Getter): cint =
  self.layout.nb_channels

proc newGetter(path: string, stream: int32, rate: cint): Getter =
  result = new(Getter)
  result.container = av.open(path)
  result.stream = result.container.audio[stream]
  result.container.setActiveStream(result.stream.index)
  result.rate = rate
  result.decoderCtx = initDecoder(result.stream.codecpar)
  new(result.layout)
  discard av_channel_layout_copy(
    addr result.layout[], addr result.stream.codecpar.ch_layout
  )

proc close(getter: Getter) =
  avcodec_free_context(addr getter.decoderCtx)
  getter.container.close()

proc get(getter: Getter, start, endSample: int): seq[int16] =
  # start/end is in samples
  let container = getter.container
  let stream = getter.stream
  let decoderCtx = getter.decoderCtx

  let targetSamples = endSample - start
  if targetSamples <= 0:
    return @[]

  # Initialize result with proper size for interleaved multi-channel (default zero-filled)
  result = newSeq[int16](targetSamples * getter.channels)

  # Convert sample position to time and seek
  let sampleRate = stream.codecpar.sample_rate
  let timeBase = stream.time_base
  if sampleRate <= 0 or timeBase.num == 0:
    error "Invalid stream time base or sample rate"
  let startTimeInSeconds = start.float / sampleRate.float
  let startPts = int64(startTimeInSeconds * timeBase.den.float / timeBase.num.float)

  # Seek to the approximate position
  if av_seek_frame(container.formatContext, stream.index, startPts,
      AVSEEK_FLAG_BACKWARD) < 0:
    # If seeking fails, fall back to reading from beginning
    discard av_seek_frame(container.formatContext, stream.index, 0, AVSEEK_FLAG_BACKWARD)

  # Flush decoder after seeking
  avcodec_flush_buffers(decoderCtx)

  var packet = av_packet_alloc()
  if packet == nil:
    error "Could not allocate packet"
  var frame = av_frame_alloc()
  if frame == nil:
    av_packet_free(addr packet)
    error "Could not allocate frame"
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
          let channels = frame.ch_layout.nb_channels
          let samples = frame.nb_samples

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
            let sourceOffset = samplesSkippedInFrame * channels
            let destOffset = totalSamples * channels
            let bytesToCopy = samplesToProcess * channels * sizeof(int16)
            copyMem(addr result[destOffset], addr audioData[sourceOffset], bytesToCopy)

          elif frame.format == AV_SAMPLE_FMT_S16P.cint:
            # Planar 16-bit
            for i in 0..<samplesToProcess:
              let frameIndex = samplesSkippedInFrame + i
              let resultIndex = (totalSamples + i) * channels
              for ch in 0 ..< channels:
                if frame.data[ch] != nil:
                  let channelData = cast[ptr UncheckedArray[int16]](frame.data[ch])
                  result[resultIndex + ch] = channelData[frameIndex]

          elif frame.format == AV_SAMPLE_FMT_FLT.cint:
            # Interleaved float
            let audioData = cast[ptr UncheckedArray[cfloat]](frame.data[0])
            for i in 0..<samplesToProcess:
              let frameIndex = samplesSkippedInFrame + i
              let resultIndex = (totalSamples + i) * channels
              for ch in 0 ..< channels:
                # Convert float to 16-bit int with proper clamping
                let floatSample = audioData[frameIndex * channels + ch]
                let clampedSample = max(-1.0, min(1.0, floatSample))
                result[resultIndex + ch] = int16(clampedSample * 32767.0)

          elif frame.format == AV_SAMPLE_FMT_FLTP.cint:
            # Planar float
            for i in 0..<samplesToProcess:
              let frameIndex = samplesSkippedInFrame + i
              let resultIndex = (totalSamples + i) * channels
              for ch in 0 ..< channels:
                if frame.data[ch] != nil:
                  let channelData = cast[ptr UncheckedArray[cfloat]](frame.data[ch])
                  # Convert float to 16-bit int with proper clamping
                  let floatSample = channelData[frameIndex]
                  let clampedSample = max(-1.0, min(1.0, floatSample))
                  result[resultIndex + ch] = int16(clampedSample * 32767.0)

          elif frame.format == AV_SAMPLE_FMT_S32.cint:
            # Interleaved 32-bit
            let audioData = cast[ptr UncheckedArray[int32]](frame.data[0])
            for i in 0..<samplesToProcess:
              let frameIndex = samplesSkippedInFrame + i
              let resultIndex = (totalSamples + i) * channels
              for ch in 0 ..< channels:
                result[resultIndex + ch] = int16(ashr(audioData[frameIndex * channels + ch], 16))

          elif frame.format == AV_SAMPLE_FMT_S32P.cint:
            # Planar 32-bit
            for i in 0..<samplesToProcess:
              let frameIndex = samplesSkippedInFrame + i
              let resultIndex = (totalSamples + i) * channels
              for ch in 0 ..< channels:
                if frame.data[ch] != nil:
                  let channelData = cast[ptr UncheckedArray[int32]](frame.data[ch])
                  result[resultIndex + ch] = int16(ashr(channelData[frameIndex], 16))
          else:
            error &"Unsupported audio format: {av_get_sample_fmt_name(frame.format)}"

          totalSamples += samplesToProcess
          samplesProcessed += samples

proc createFilterGraph(effects: Actions, sr: cint, layout: ref AVChannelLayout):
  (ptr AVFilterGraph, ptr AVFilterContext, ptr AVFilterContext) =

  let filterGraph: ptr AVFilterGraph = avfilter_graph_alloc()
  if filterGraph == nil:
    error "Could not allocate audio filter graph"

  let abuffer = avfilter_get_by_name("abuffer")
  let asink = avfilter_get_by_name("abuffersink")

  let bufferArgs = &"sample_rate={sr}:sample_fmt=s16p:channel_layout={layout}:time_base=1/{sr}"
  var bufferSrc: ptr AVFilterContext = nil
  var ret = avfilter_graph_create_filter(addr bufferSrc, abuffer, nil,
                                         bufferArgs.cstring, nil, filterGraph)
  if ret < 0:
    error &"Cannot create audio buffer source: {ret}"

  var bufferSink: ptr AVFilterContext = nil
  ret = avfilter_graph_create_filter(addr bufferSink, asink, nil, nil, nil, filterGraph)
  if ret < 0:
    error &"Cannot create audio buffer sink: {ret}"

  var filters: seq[string] = @[]
  # Build filter chain from all effects in the group
  for effect in effects:
    case effect.kind
    of actSpeed:
      const maxAtempo = 6.0
      const minAtempo = 0.5
      var remainingSpeed = effect.val
      while remainingSpeed > maxAtempo:
        filters.add &"atempo={maxAtempo}"
        remainingSpeed = remainingSpeed / maxAtempo
      while remainingSpeed < minAtempo:
        filters.add &"atempo={minAtempo}"
        remainingSpeed = remainingSpeed / minAtempo

      if remainingSpeed != 1.0:
        filters.add &"atempo={remainingSpeed}"

    of actVarispeed:
      let clampedSpeed = max(0.2, min(100.0, effect.val))
      filters.add &"asetrate={sr}*{clampedSpeed}"
      filters.add &"aresample={sr}"
    of actVolume:
      filters.add &"volume={effect.val}"
    of actDeesser:
      filters.add &"deesser=i={effect.intensity}:m={effect.maxd}:f={effect.freq}"
    else: discard

  # Pin the chain's output to s16p. Some filters (e.g. deesser) emit dblp, which
  # the frame-readback in processAudioClip can't convert, yielding silence.
  let filterChain = (
    if filters.len == 0: "anull"
    else: filters.join(",") & ",aformat=sample_fmts=s16p"
  )

  var inputs = avfilter_inout_alloc()
  if inputs == nil:
    error "Could not allocate filter inputs"
  var outputs = avfilter_inout_alloc()
  if outputs == nil:
    avfilter_inout_free(addr inputs)
    error "Could not allocate filter outputs"

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
    error &"Could not parse audio filter graph: {ret}"

  ret = avfilter_graph_config(filterGraph, nil)
  if ret < 0:
    error &"Could not configure audio filter graph: {ret}"

  avfilter_inout_free(addr inputs)
  avfilter_inout_free(addr outputs)

  return (filterGraph, bufferSrc, bufferSink)

# Returns seq[int16] where channel data is interleaved: [ch0, ch1, ..., ch0, ch1, ...] etc.
proc processAudioClip(ef: seq[Actions], clip: Clip, data: seq[int16], sourceSr, targetSr: cint,
    layout: ref AVChannelLayout): seq[int16] =
  if data.len == 0:
    return @[]

  # First apply speed/volume processing at source sample rate (if needed)
  var processedData = data

  let channels = layout.nb_channels
  let effectGroup = ef[clip.effects]
  var needsFiltering = false
  for effect in effectGroup:
    if effect.kind in [actSpeed, actVarispeed, actVolume, actDeesser]:
      needsFiltering = true
      break

  if needsFiltering:
    let samples = data.len div channels
    let (filterGraph, bufferSrc, bufferSink) = createFilterGraph(effectGroup, sourceSr, layout)
    defer: avfilter_graph_free(addr filterGraph)

    # Create audio frame with input data
    var inputFrame = av_frame_alloc()
    if inputFrame == nil:
      error "Could not allocate input audio frame"
    defer: av_frame_free(addr inputFrame)

    inputFrame.nb_samples = samples.cint
    inputFrame.format = AV_SAMPLE_FMT_S16P.cint
    discard av_channel_layout_copy(addr inputFrame.ch_layout, addr layout[])
    inputFrame.sample_rate = sourceSr
    inputFrame.pts = AV_NOPTS_VALUE

    if av_frame_get_buffer(inputFrame, 0) < 0:
      error "Could not allocate input audio frame buffer"

    # Copy input data to frame (convert from interleaved to planar format)
    for ch in 0..<channels:
      let channelData = cast[ptr UncheckedArray[int16]](inputFrame.data[ch])
      for i in 0..<samples:
        let srcIndex = i * channels + ch
        if srcIndex < data.len:
          channelData[i] = data[srcIndex]
        else:
          channelData[i] = 0

    # Process through filter graph
    var outputFrames: seq[ptr AVFrame] = @[]
    defer:
      for frame in outputFrames:
        av_frame_free(addr frame)

    if av_buffersrc_write_frame(bufferSrc, inputFrame) < 0:
      error "Error adding frame to audio filter"
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

    # Convert output frames back to interleaved seq[int16]
    if outputFrames.len == 0:
      processedData = @[]
    else:
      var totalSamples = 0
      for frame in outputFrames:
        totalSamples += frame.nb_samples.int

      processedData = newSeq[int16](totalSamples * channels)

      var sampleOffset = 0
      for frame in outputFrames:
        let frameSamples = frame.nb_samples.int
        let frameChannels = frame.ch_layout.nb_channels

        if frame.format == AV_SAMPLE_FMT_S16P.cint:
          # Convert from planar to interleaved
          for i in 0..<frameSamples:
            let interleavedIndex = (sampleOffset + i) * channels
            for ch in 0..<min(frameChannels, channels):
              if frame.data[ch] != nil and interleavedIndex + ch < processedData.len:
                let channelData = cast[ptr UncheckedArray[int16]](frame.data[ch])
                processedData[interleavedIndex + ch] = channelData[i]
        elif frame.format == AV_SAMPLE_FMT_S16.cint:
          # Already interleaved, just copy
          let audioData = cast[ptr UncheckedArray[int16]](frame.data[0])
          for i in 0..<frameSamples:
            let interleavedIndex = (sampleOffset + i) * channels
            for ch in 0..<min(frameChannels, channels):
              if interleavedIndex + ch < processedData.len:
                processedData[interleavedIndex + ch] = audioData[i * frameChannels + ch]
        elif frame.format == AV_SAMPLE_FMT_FLTP.cint:
          # Planar float - convert to int16
          for i in 0..<frameSamples:
            let interleavedIndex = (sampleOffset + i) * channels
            for ch in 0..<min(frameChannels, channels):
              if frame.data[ch] != nil and interleavedIndex + ch < processedData.len:
                let channelData = cast[ptr UncheckedArray[cfloat]](frame.data[ch])
                let floatSample = channelData[i]
                let clampedSample = max(-1.0, min(1.0, floatSample))
                processedData[interleavedIndex + ch] = int16(clampedSample * 32767.0)
        elif frame.format == AV_SAMPLE_FMT_FLT.cint:
          # Interleaved float - convert to int16
          let audioData = cast[ptr UncheckedArray[cfloat]](frame.data[0])
          for i in 0..<frameSamples:
            let interleavedIndex = (sampleOffset + i) * channels
            for ch in 0..<min(frameChannels, channels):
              if interleavedIndex + ch < processedData.len:
                let floatSample = audioData[i * frameChannels + ch]
                let clampedSample = max(-1.0, min(1.0, floatSample))
                processedData[interleavedIndex + ch] = int16(clampedSample * 32767.0)

        sampleOffset += frameSamples

  # Now resample from source to target sample rate
  if sourceSr == targetSr:
    # Data is already in interleaved format
    return processedData

  if processedData.len == 0:
    return @[]

  let samples = processedData.len div channels
  var resampler = newAudioResampler(AV_SAMPLE_FMT_S16P, layout, targetSr)
  var inputFrame = av_frame_alloc()
  if inputFrame == nil:
    error "Could not allocate input frame for resampling"
  defer: av_frame_free(addr inputFrame)

  inputFrame.nb_samples = samples.cint
  inputFrame.format = AV_SAMPLE_FMT_S16P.cint
  discard av_channel_layout_copy(addr inputFrame.ch_layout, addr layout[])
  inputFrame.sample_rate = sourceSr
  inputFrame.pts = AV_NOPTS_VALUE

  if av_frame_get_buffer(inputFrame, 0) < 0:
    error "Could not allocate input frame buffer for resampling"

  # Copy data to input frame (convert from interleaved to planar)
  for ch in 0..<channels:
    let channelData = cast[ptr UncheckedArray[int16]](inputFrame.data[ch])
    for i in 0..<samples:
      let srcIndex = i * channels + ch
      if srcIndex < processedData.len:
        channelData[i] = processedData[srcIndex]
      else:
        channelData[i] = 0

  # Resample
  let outputFrames = resampler.resample(inputFrame)

  # Convert back to interleaved seq[int16]
  var tempChannelData = newSeq[seq[int16]](channels)

  for frame in outputFrames:
    let frameSamples = frame.nb_samples.int
    let frameChannels = frame.ch_layout.nb_channels

    # Extend temp arrays
    let currentLen = tempChannelData[0].len
    for ch in 0..<channels:
      tempChannelData[ch].setLen(currentLen + frameSamples)

    # Copy frame data
    if frame.format == AV_SAMPLE_FMT_S16P:
      for ch in 0..<min(frameChannels, channels):
        if frame.data[ch] != nil:
          let channelData = cast[ptr UncheckedArray[int16]](frame.data[ch])
          for i in 0..<frameSamples:
            tempChannelData[ch][currentLen + i] = channelData[i]

    av_frame_free(addr frame)

  # Convert from channel-separated to interleaved format
  let totalSamples = tempChannelData[0].len
  result = newSeq[int16](totalSamples * channels)
  for i in 0..<totalSamples:
    for ch in 0..<channels:
      result[i * channels + ch] = tempChannelData[ch][i]


# Micro-fade applied at every clip edge to kill cut pops. A splice between two
# clips is an instantaneous amplitude step (a click); ramping each edge to/from
# zero over a few ms removes the discontinuity. ~3 ms is inaudible as a fade.
const audioFadeMs = 3.0

proc makeAudioFrames(fmt: AVSampleFormat, tl: v3, frameSize: int, layerIndices: seq[
    int], mixLayers: bool, norm: Norm,
    cache: MediaCache = nil): iterator(): (ptr AVFrame, int64) =

  var samples: Table[(string, int32), Getter]
  let targetChannels = tl.layout.nb_channels
  let tb = tl.tb
  let sr = tl.sr
  let fadeSamples = max(1, int(audioFadeMs / 1000.0 * sr.float64))

  if tb.num == 0:
    error "Timeline timebase has zero numerator"

  # Collect all unique audio sources from specified layers.
  # Audio's getter calls av_seek_frame / av_read_frame on its container, so it
  # must have an AVFormatContext that's independent of the video decoder's —
  # otherwise interleaved video+audio reads desync and the video stream emits
  # black frames after the first GOP.
  for layerIndex in layerIndices:
    if layerIndex < tl.a.len:
      for clip in tl.a[layerIndex]:
        let key = (clip.src[], clip.stream)
        if key notin samples:
          samples[key] = newGetter(clip.src[], clip.stream, sr)

  # Calculate total duration across specified layers
  var totalDuration: int64 = 0
  for layerIndex in layerIndices:
    if layerIndex < tl.a.len:
      for clip in tl.a[layerIndex]:
        totalDuration = max(totalDuration, clip.start + clip.dur)

  let totalSamples = int(totalDuration * sr.int64 * tb.den div tb.num)

  # Re-runnable streaming producer: yields the assembled, mixed, fade-applied
  # timeline as interleaved int16 chunks of up to `frameSize` sample-frames, in
  # time order, zero-padded out to `totalSamples`. Memory stays bounded by the
  # largest in-flight clip plus any cross-layer overlap — never the whole
  # timeline (`mixLayers` is implicit: clips from every active layer are summed).
  proc newTimelineProducer(): iterator(): seq[int16] =
    return iterator(): seq[int16] =
      var activeLayers: seq[int] = @[]
      for li in layerIndices:
        if li < tl.a.len and tl.a[li].len > 0:
          activeLayers.add li
      var cursors = newSeq[int](tl.a.len)

      var acc: seq[int32] = @[]   # interleaved accumulator over [bufStart, ...)
      var bufStart = 0            # output sample-frame index mapped to acc[0]

      template startOf(li: int): int =
        int(tl.a[li][cursors[li]].start * sr.int64 * tb.den div tb.num)

      # Emit finalized sample-frames below `boundary` as `frameSize` chunks
      # (the whole remainder when `final`), then drop them from `acc`.
      template flushUpTo(boundaryArg: int, final: bool) =
        let boundary = min(boundaryArg, totalSamples)
        if (boundary - bufStart) * targetChannels > acc.len:
          acc.setLen((boundary - bufStart) * targetChannels)
        var emitFrames = 0
        if final:
          emitFrames = max(0, boundary - bufStart)
        else:
          while bufStart + emitFrames + frameSize <= boundary:
            emitFrames += frameSize
        var off = 0
        while off < emitFrames:
          let cf = min(frameSize, emitFrames - off)
          var chunk = newSeq[int16](cf * targetChannels)
          for k in 0 ..< cf * targetChannels:
            chunk[k] = clamp16(acc[off * targetChannels + k])
          off += cf
          yield chunk
        if emitFrames > 0:
          acc = (if emitFrames * targetChannels < acc.len: acc[emitFrames * targetChannels .. ^1] else: @[])
          bufStart += emitFrames

      while true:
        # Pick the not-yet-processed clip with the smallest start across layers.
        var bestLi = -1
        for li in activeLayers:
          if cursors[li] < tl.a[li].len and (bestLi == -1 or startOf(li) < startOf(bestLi)):
            bestLi = li
        if bestLi == -1:
          break

        let clip = tl.a[bestLi][cursors[bestLi]]
        inc cursors[bestLi]

        let key = (clip.src[], clip.stream)
        let effectGroup = tl.effects[clip.effects]
        var speed = 1.0
        for effect in effectGroup:
          if effect.kind in [actSpeed, actVarispeed]:
            speed *= effect.val

        if key in samples:
          let getter = samples[key]
          let sourceSr = getter.stream.codecpar.sample_rate.float64
          let sampStart = int(clip.offset.float64 * speed * sourceSr / tb)
          let sampEnd = int(float64(clip.offset + clip.dur) * speed * sourceSr / tb)
          let srcData = getter.get(sampStart, sampEnd)
          let startSample = int(clip.start * sr.int64 * tb.den div tb.num)
          let durSamples = int(clip.dur * sr.int64 * tb.den div tb.num)

          let processedData = processAudioClip(tl.effects, clip, srcData,
              getter.stream.codecpar.sample_rate, sr, getter.layout)

          if processedData.len > 0:
            let sourceChannels = getter.channels
            let numSamples = processedData.len div sourceChannels
            let n = min(durSamples, numSamples)
            let neededFrames = startSample + n - bufStart
            if neededFrames * targetChannels > acc.len:
              acc.setLen(neededFrames * targetChannels)
            for i in 0 ..< n:
              let outputSampleIndex = startSample + i
              if outputSampleIndex < totalSamples:
                let fadeIn = (
                  if i < fadeSamples: (i.float32 + 0.5) / fadeSamples.float32
                  else: 1.0'f32
                )
                let tailDist = max(0, n - 1 - i)
                let fadeOut = (
                  if tailDist < fadeSamples: (tailDist.float32 + 0.5) / fadeSamples.float32
                  else: 1.0'f32
                )
                let gain = min(1.0'f32, min(fadeIn, fadeOut))
                let baseIndex = (outputSampleIndex - bufStart) * targetChannels
                for ch in 0 ..< min(targetChannels, sourceChannels):
                  let sourceIndex = i * sourceChannels + ch
                  if sourceIndex < processedData.len:
                    acc[baseIndex + ch] += int32(round(processedData[sourceIndex].float32 * gain))

        # Everything below the next clip's start can receive no further writes.
        var hasRemaining = false
        var safeBoundary = totalSamples
        for li in activeLayers:
          if cursors[li] < tl.a[li].len:
            hasRemaining = true
            safeBoundary = min(safeBoundary, startOf(li))
        if hasRemaining:
          flushUpTo(safeBoundary, final = false)

      flushUpTo(totalSamples, final = true)

  var resampler = newAudioResampler(fmt, tl.layout, sr)
  var samplesYielded = 0
  var frameIndex = 0'i64

  # Wrap an interleaved int16 chunk as an S16P frame, resample to the output
  # format, and return the resulting (frame, index) pairs. Advances pts state.
  proc emitChunk(chunk: seq[int16]): seq[(ptr AVFrame, int64)] =
    let chunkFrames = chunk.len div targetChannels
    if chunkFrames == 0:
      return @[]
    var frame = av_frame_alloc()
    if frame == nil:
      error "Could not allocate audio frame"
    defer: av_frame_free(addr frame)
    frame.nb_samples = chunkFrames.cint
    frame.format = AV_SAMPLE_FMT_S16P.cint
    discard av_channel_layout_copy(addr frame.ch_layout, addr tl.layout[])
    frame.sample_rate = sr
    frame.pts = samplesYielded.int64
    frame.time_base = AVRational(num: 1, den: sr)
    if av_frame_get_buffer(frame, 0) < 0:
      error "Could not allocate audio frame buffer"
    for ch in 0 ..< targetChannels:
      let channelData = cast[ptr UncheckedArray[int16]](frame.data[ch])
      for i in 0 ..< chunkFrames:
        channelData[i] = chunk[i * targetChannels + ch]
    for newFrame in resampler.resample(frame):
      result.add (newFrame, frameIndex)
      frameIndex += 1
    samplesYielded += chunkFrames

  # Wrap an interleaved int16 chunk as a planar-float (FLTP) frame for loudnorm.
  var fltpPts = 0'i64
  proc chunkToFltpFrame(chunk: seq[int16]): ptr AVFrame =
    let nFrames = chunk.len div targetChannels
    var frame = av_frame_alloc()
    if frame == nil:
      error "Could not allocate loudnorm input frame"
    frame.nb_samples = nFrames.cint
    frame.format = AV_SAMPLE_FMT_FLTP.cint
    discard av_channel_layout_copy(addr frame.ch_layout, addr tl.layout[])
    frame.sample_rate = sr.cint
    frame.pts = fltpPts
    fltpPts += nFrames
    if av_frame_get_buffer(frame, 0) < 0:
      error "Could not allocate loudnorm input frame buffer"
    for ch in 0 ..< targetChannels:
      let channelData = cast[ptr UncheckedArray[cfloat]](frame.data[ch])
      for i in 0 ..< nFrames:
        channelData[i] = chunk[i * targetChannels + ch].cfloat / 32768.0
    return frame

  # Convert a loudnorm output frame (one of several sample formats) to an
  # interleaved int16 chunk.
  proc loudnormOutToChunk(outF: ptr AVFrame): seq[int16] =
    let frameSamples = outF.nb_samples.int
    let frameChannels = min(outF.ch_layout.nb_channels.int, targetChannels)
    result = newSeq[int16](frameSamples * targetChannels)
    if outF.format == AV_SAMPLE_FMT_DBL.cint:
      let audioData = cast[ptr UncheckedArray[cdouble]](outF.data[0])
      for i in 0 ..< frameSamples:
        for ch in 0 ..< frameChannels:
          let s = max(-1.0, min(1.0, audioData[i * frameChannels + ch]))
          result[i * targetChannels + ch] = int16(s * 32767.0)
    elif outF.format == AV_SAMPLE_FMT_FLT.cint:
      let audioData = cast[ptr UncheckedArray[cfloat]](outF.data[0])
      for i in 0 ..< frameSamples:
        for ch in 0 ..< frameChannels:
          let s = max(-1.0'f32, min(1.0'f32, audioData[i * frameChannels + ch]))
          result[i * targetChannels + ch] = int16(s * 32767.0)
    elif outF.format == AV_SAMPLE_FMT_FLTP.cint:
      for i in 0 ..< frameSamples:
        for ch in 0 ..< frameChannels:
          if outF.data[ch] != nil:
            let channelData = cast[ptr UncheckedArray[cfloat]](outF.data[ch])
            let s = max(-1.0'f32, min(1.0'f32, channelData[i]))
            result[i * targetChannels + ch] = int16(s * 32767.0)
    elif outF.format == AV_SAMPLE_FMT_S16P.cint:
      for i in 0 ..< frameSamples:
        for ch in 0 ..< frameChannels:
          if outF.data[ch] != nil:
            let channelData = cast[ptr UncheckedArray[int16]](outF.data[ch])
            result[i * targetChannels + ch] = channelData[i]
    else:
      error &"Unexpected output format from loudnorm: {outF.format}"

  # EBU's loudnorm may emit a slightly different sample count than the timeline;
  # cap the apply pass to `totalSamples` so output duration is preserved.
  var ebuEmitted = 0
  proc emitCapped(chunk: seq[int16]): seq[(ptr AVFrame, int64)] =
    if ebuEmitted >= totalSamples:
      return @[]
    var c = chunk
    let avail = totalSamples - ebuEmitted
    if c.len div targetChannels > avail:
      c.setLen(avail * targetChannels)
    ebuEmitted += c.len div targetChannels
    return emitChunk(c)

  return iterator(): (ptr AVFrame, int64) =
    defer:
      for getter in samples.values:
        getter.close()

    case norm.kind
    of nkNull:
      let produce = newTimelineProducer()
      for chunk in produce():
        for fr in emitChunk(chunk):
          yield fr

    of nkPeak:
      # Pass 1: stream the timeline to find the global peak.
      var maxPeakLevel = -99.0'f32
      block:
        let produce = newTimelineProducer()
        for chunk in produce():
          for s in chunk:
            let amplitude = abs(s.float32 / 32768.0)
            if amplitude > 0.0:
              let peakLevel = 20.0 * log10(amplitude)
              if peakLevel > maxPeakLevel:
                maxPeakLevel = peakLevel
      let peakAdjustment = norm.t - maxPeakLevel
      debug &"current peak level: {maxPeakLevel}"
      debug &"peak adjustment: {peakAdjustment:.3f}dB"
      let gainLinear = pow(10.0, peakAdjustment / 20.0)

      # Pass 2: stream the timeline again, applying the gain.
      let produce2 = newTimelineProducer()
      for chunk in produce2():
        var c = chunk
        if peakAdjustment != 0.0:
          for k in 0 ..< c.len:
            c[k] = int16(max(-32768.0, min(32767.0, c[k].float32 * gainLinear)))
        for fr in emitChunk(c):
          yield fr

    of nkEbu:
      let layoutDesc = $tl.layout
      let bufferArgs = &"sample_rate={sr}:sample_fmt=fltp:channel_layout={layoutDesc}:time_base=1/{sr}"

      # First pass: stream chunks through loudnorm to measure loudness.
      let capture = beginLoudnormCapture()
      let firstPass = &"i={norm.i}:lra={norm.lra}:tp={norm.tp}:offset={norm.gain}:print_format=json"
      var analysisGraph = newGraph()
      let analysisSrc = analysisGraph.add("abuffer", bufferArgs)
      let analysisFilter = analysisGraph.add("loudnorm", firstPass)
      let analysisSink = analysisGraph.add("abuffersink")
      analysisGraph.linkNodes(@[analysisSrc, analysisFilter, analysisSink]).configure()

      fltpPts = 0
      block:
        let produce = newTimelineProducer()
        for chunk in produce():
          var f = chunkToFltpFrame(chunk)
          analysisGraph.push(f)
          av_frame_free(addr f)
          while analysisGraph.pullTransient() != nil:
            discard
      analysisGraph.flush()
      while analysisGraph.pullTransient() != nil:
        discard
      analysisGraph.cleanup()
      endLoudnormCapture(capture)

      var measuredI = norm.i
      var measuredLRA = norm.lra
      var measuredTP = norm.tp
      var measuredThresh = -70.0'f32
      let capturedJson = capture.getCaptured()
      let jsonStart = capturedJson.find('{')
      let jsonEnd = capturedJson.rfind('}')
      if capturedJson.len > 0 and jsonStart >= 0 and jsonEnd > jsonStart:
        let jsonStr = capturedJson[jsonStart..jsonEnd]
        try:
          let jsonData = parseJson(jsonStr)
          measuredI = parseLoudnormValue(jsonData, "input_i")
          measuredLRA = parseLoudnormValue(jsonData, "input_lra")
          measuredTP = parseLoudnormValue(jsonData, "input_tp")
          measuredThresh = parseLoudnormValue(jsonData, "input_thresh")
          debug &"Measured: i={measuredI:.2f} lra={measuredLRA:.2f} tp={measuredTP:.2f} thresh={measuredThresh:.2f}"
        except JsonParsingError, KeyError, ValueError:
          error "Error processing loudnorm output"
      else:
        error "Error processing loudnorm output"

      # Second pass: stream chunks through loudnorm applying the measured gain.
      let secondPass = &"i={norm.i}:lra={norm.lra}:tp={norm.tp}:offset={norm.gain}:linear=true:measured_i={measuredI}:measured_lra={measuredLRA}:measured_tp={measuredTP}:measured_thresh={measuredThresh}:print_format=none"
      debug &"EBU norm: {secondPass}"
      var loudnormGraph = newGraph()
      let bufferSrc = loudnormGraph.add("abuffer", bufferArgs)
      let loudnormFilter = loudnormGraph.add("loudnorm", secondPass)
      let aformat = loudnormGraph.add("aformat", &"sample_rates={sr}")
      let bufferSink = loudnormGraph.add("abuffersink")
      loudnormGraph.linkNodes(@[bufferSrc, loudnormFilter, aformat, bufferSink]).configure()

      fltpPts = 0
      block:
        let produce = newTimelineProducer()
        for chunk in produce():
          var f = chunkToFltpFrame(chunk)
          loudnormGraph.push(f)
          av_frame_free(addr f)
          while true:
            let outF = loudnormGraph.pullTransient()
            if outF == nil:
              break
            for fr in emitCapped(loudnormOutToChunk(outF)):
              yield fr
      loudnormGraph.flush()
      while true:
        let outF = loudnormGraph.pullTransient()
        if outF == nil:
          break
        for fr in emitCapped(loudnormOutToChunk(outF)):
          yield fr
      loudnormGraph.cleanup()

      # Pad with silence if loudnorm produced fewer samples than the timeline.
      if ebuEmitted < totalSamples:
        let pad = newSeq[int16]((totalSamples - ebuEmitted) * targetChannels)
        ebuEmitted = totalSamples
        for fr in emitChunk(pad):
          yield fr

proc makeMixedAudioFrames*(fmt: AVSampleFormat, tl: v3, frameSize: int, norm: Norm,
    cache: MediaCache = nil): iterator(): (ptr AVFrame, int64) =

  let allLayerIndices = toSeq(0..<tl.a.len)
  return makeAudioFrames(fmt, tl, frameSize, allLayerIndices, mixLayers = true, norm, cache)

proc makeNewAudioFrames*(fmt: AVSampleFormat, index: int32, tl: v3,
    frameSize: int, norm: Norm, cache: MediaCache = nil): iterator(): (ptr AVFrame, int64) =

  return makeAudioFrames(fmt, tl, frameSize, @[index.int], mixLayers = false, norm, cache)

