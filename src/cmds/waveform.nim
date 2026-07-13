import std/[options, sequtils, strformat, strutils]

import ../util/[rational, dnorm16]
import ../[av, cache, cli, ffmpeg, log]
import ../analyze/audio
import ./help

proc main*(strArgs: seq[string]) =
  var
    expecting = ""
    inputFile = ""
    userStream: int16 = 0
    channel = ""
    samplesPerBucket: int32 = 256
    startSample: int64 = 0
    lengthSamples: int64 = -1
    display = "float"

  for key in strArgs:
    if genCliMacro(key, strArgs, waveformOptions):
      continue
    if key in ["-h", "--help"]:
      printHelp("<file> [options]", waveformOptions)
    if key.startsWith("--"):
      error &"Unknown option: {key}{optionDidYouMean(key, waveformOptions)}"

    case expecting
    of "":
      if inputFile != "":
        error &"Input file is already set: {key}"
      inputFile = key
    of "stream":
      try: userStream = parseInt(key).int16
      except ValueError: error &"Invalid stream index: {key}"
    of "channel": channel = key
    of "samples-per-bucket":
      try: samplesPerBucket = parseInt(key).int32
      except ValueError: error &"Invalid samples-per-bucket: {key}"
    of "start-sample":
      try: startSample = parseBiggestInt(key).int64
      except ValueError: error &"Invalid start-sample: {key}"
    of "length-samples":
      try: lengthSamples = parseBiggestInt(key).int64
      except ValueError: error &"Invalid length-samples: {key}"
    of "display":
      display = key
    expecting = ""

  if expecting != "":
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
    container.seek(pts, backward = true, stream = audioStream)
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

  if not windowed and not noCache:
    writeCache(flat, cacheTb, inputFile, "waveform", cacheArgs)
