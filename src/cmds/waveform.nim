import std/[options, sequtils, strformat, strutils]

import ../util/[bar, rational]
import ../lib/dnorm16
import ../[av, cache, cli, ffmpeg, log]
import ../analyze/audio
import ../lib/audioutil
import ./help

const waveformArgumentOptions = {
  coStream, coChannel, coSamplesPerBucket, coStartSample, coLengthSamples,
  coDisplay,
}

assertArgumentOptions(waveformOptions, waveformArgumentOptions)

type WaveWindow* = object
  ## Audio peaks for a stretch of one channel, one (lo, hi) pair per bucket.
  sampleRate*: int
  samplesPerBucket*: int
  firstSample*: int64 ## sample index of peaks[0]
  peaks*: seq[tuple[lo, hi: float32]]

proc streamPeaks*(input: string, stream, samplesPerBucket: int,
    startSample = 0'i64, lengthSamples = -1'i64): seq[WaveWindow] =
  ## Peaks for every channel of audio `stream`, one window each in the
  ## layout's order, from a single decode that seeks to `startSample`.
  ## A negative `lengthSamples` runs to the end.
  if samplesPerBucket < 1: error "samples-per-bucket must be positive"
  var container = (try: av.open(input) except IOError as e: error e.msg)
  defer: container.close()
  if stream < 0 or stream >= container.audio.len:
    error "Audio stream out of range: " & $stream
  let audioStream = container.audio[stream]
  let rate = audioStream.codecpar.sample_rate
  if rate <= 0: error "Audio stream has invalid sample rate"
  let n = audioStream.codecpar.ch_layout.nb_channels.int
  var channels: seq[int]
  for c in 0 ..< n: channels.add c
  var processor = AudioProcessor(codecCtx: initDecoder(audioStream.codecpar),
    audioIndex: audioStream.index,
    chunkDuration: samplesPerBucket.float64 / rate.float64)
  if startSample > 0:
    let tb = audioStream.time_base
    container.seek((startSample * int64(tb.den)) div (int64(rate) * int64(tb.num)),
      stream = audioStream)
    avcodec_flush_buffers(processor.codecCtx)
  let endSample = if lengthSamples < 0: int64.high else: startSample + lengthSamples
  for c in 0 ..< n:
    result.add WaveWindow(sampleRate: rate, samplesPerBucket: samplesPerBucket,
      firstSample: -1)
  let bar = initBar(BarType.none) # for the cancel flag
  for (bucketStart, peaks) in processor.channelPeaks(container, audioStream, channels):
    bar.tick(0)
    if bucketStart + samplesPerBucket <= startSample: continue
    if bucketStart >= endSample: break
    for c in 0 ..< min(n, peaks.len):
      if result[c].firstSample < 0: result[c].firstSample = bucketStart
      result[c].peaks.add peaks[c]
  for w in result.mitems:
    if w.firstSample < 0: w.firstSample = startSample

proc main*(strArgs: seq[string]) =
  var
    inputFile = ""
    userStream: int16 = 0
    channel = ""
    samplesPerBucket: int32 = 256
    startSample: int64 = 0
    lengthSamples: int64 = -1
    display = "float"

  parseArgs(strArgs, waveformOptions, "<file> [options]", "--"):
    case expecting
    of coNone:
      if inputFile != "":
        error &"Input file is already set: {key}"
      inputFile = key
    of coStream:
      try: userStream = parseInt(key).int16
      except ValueError: error &"Invalid stream index: {key}"
    of coChannel: channel = key
    of coSamplesPerBucket:
      try: samplesPerBucket = parseInt(key).int32
      except ValueError: error &"Invalid samples-per-bucket: {key}"
    of coStartSample:
      try: startSample = parseBiggestInt(key).int64
      except ValueError: error &"Invalid start-sample: {key}"
    of coLengthSamples:
      try: lengthSamples = parseBiggestInt(key).int64
      except ValueError: error &"Invalid length-samples: {key}"
    of coDisplay:
      display = key
    else:
      discard
    expecting = coNone

  if expecting != coNone:
    error &"--{expecting} needs argument."

  if display notin ["float", "d16"]:
    error &"Unknown display format: {display}"

  if inputFile == "":
    error "Expecting an input file."

  if userStream < 0:
    error "Stream must be positive"

  if samplesPerBucket < 1:
    error "samples-per-bucket must be positive"

  if startSample < 0:
    error "start-sample must be non-negative"

  if channel == "":
    error "--channel needs at least one named audio channel"
  let channelNames = channel.split(',')
  if channelNames.len == 0 or channelNames.anyIt(
      it == "" or audioChannelCode(it) == ""):
    error &"Unknown audio channel list: {channel}"

  av_log_set_level(AV_LOG_QUIET)

  let windowed = startSample > 0 or lengthSamples >= 0
  let cacheTb = AVRational(num: 1, den: 1)
  let cacheArgs = &"{userStream},{channel},{samplesPerBucket}"

  proc emitPair(lo, hi: Snorm16) =
    if display == "d16": echo &"{int16(lo)},{int16(hi)}"
    else: echo &"{lo},{hi}"

  proc formatValue(value: Snorm16): string =
    if display == "d16": $int16(value) else: $value

  echo "\n@start"

  if not windowed and not noCache:
    let cacheData = readCache[Snorm16](inputFile, cacheTb, "waveform", cacheArgs)
    if cacheData.isSome:
      echo "@offset 0"
      let flat = cacheData.get()
      var i = 0
      let valuesPerBucket = channelNames.len * 2
      while i + valuesPerBucket <= flat.len:
        var values: seq[string] = @[]
        for j in 0 ..< valuesPerBucket:
          values.add formatValue(flat[i + j])
        echo values.join(",")
        i += valuesPerBucket
      echo ""
      return

  var container: InputContainer
  try:
    container = av.open(inputFile)
  except IOError as e:
    error e.msg
  defer: container.close()

  if container.audio.len == 0:
    error "No audio stream"
  if container.audio.len <= userStream:
    error &"Audio stream out of range: {userStream}"

  let audioStream: ptr AVStream = container.audio[userStream]
  var channelIndices: seq[int] = @[]
  for name in channelNames:
    let channelIndex = resolveAudioChannelOrDefault(
      addr audioStream.codecpar.ch_layout, name)
    if channelIndex < -1:
      error &"Audio channel '{name}' does not exist in stream {userStream} ({addr audioStream.codecpar.ch_layout})."
    channelIndices.add channelIndex
  let sampleRate = audioStream.codecpar.sample_rate
  if sampleRate <= 0:
    error "Audio stream has invalid sample rate"

  var processor = AudioProcessor(
    codecCtx: initDecoder(audioStream.codecpar),
    audioIndex: audioStream.index,
    channel: channelIndices[0],
    chunkDuration: float64(samplesPerBucket) / float64(sampleRate),
  )

  if startSample > 0:
    let tb = audioStream.time_base
    let pts = (startSample * int64(tb.den)) div (int64(sampleRate) * int64(tb.num))
    container.seek(pts, stream = audioStream)
    avcodec_flush_buffers(processor.codecCtx)

  let endSample: int64 =
    if lengthSamples < 0: high(int64)
    else: startSample + lengthSamples

  var flat: seq[Snorm16] = @[]
  var offsetEmitted = false

  if channelIndices.len == 1:
    for (bucketStart, lo, hi) in processor.peaks(container, audioStream):
      if bucketStart + int64(samplesPerBucket) <= startSample:
        continue
      if bucketStart >= endSample:
        break
      if not offsetEmitted:
        echo &"@offset {bucketStart}"
        offsetEmitted = true
      let slo = toSnorm16(lo)
      let shi = toSnorm16(hi)
      emitPair(slo, shi)
      flat.add slo
      flat.add shi
  else:
    for (bucketStart, peaks) in processor.channelPeaks(
      container, audioStream, channelIndices):
      if bucketStart + int64(samplesPerBucket) <= startSample:
        continue
      if bucketStart >= endSample:
        break
      if not offsetEmitted:
        echo &"@offset {bucketStart}"
        offsetEmitted = true
      var values: seq[string] = @[]
      for (lo, hi) in peaks:
        let slo = toSnorm16(lo)
        let shi = toSnorm16(hi)
        values.add formatValue(slo)
        values.add formatValue(shi)
        flat.add slo
        flat.add shi
      echo values.join(",")

  if not offsetEmitted:
    echo "@offset 0"
  echo ""

  if not windowed and not noCache and decodeErrors == 0:
    writeCache(flat, cacheTb, inputFile, "waveform", cacheArgs)
