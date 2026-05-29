import std/[options, strformat, strutils]

import ../util/[rational, dnorm16]
import ../[av, cache, ffmpeg, log]
import ../analyze/audio

proc main*(strArgs: seq[string]) =
  var
    expecting = ""
    inputFile = ""
    userStream: int32 = 0
    samplesPerBucket: int32 = 256
    startSample: int64 = 0
    lengthSamples: int64 = -1
    display = "float"

  for key in strArgs:
    case key
    of "--no-cache":
      noCache = true
    of "--stream", "--samples-per-bucket", "--start-sample", "--length-samples", "--display":
      expecting = key[2..^1]
    else:
      if key.startsWith("--"):
        error &"Unknown option: {key}"

      case expecting
      of "":
        if inputFile != "":
          error &"Input file is already set: {key}"
        inputFile = key
      of "stream":
        try: userStream = parseInt(key).int32
        except ValueError: error &"Invalid stream index: {key}"
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

  av_log_set_level(AV_LOG_QUIET)

  let windowed = startSample > 0 or lengthSamples >= 0
  let cacheTb = AVRational(num: 1, den: 1)
  let cacheArgs = &"{userStream},{samplesPerBucket}"

  proc emitPair(lo, hi: Snorm16) =
    if display == "d16": echo &"{int16(lo)},{int16(hi)}"
    else: echo &"{lo},{hi}"

  echo "\n@start"

  if not windowed and not noCache:
    let cacheData = readCache[Snorm16](inputFile, cacheTb, "waveform", cacheArgs)
    if cacheData.isSome:
      echo "@offset 0"
      let flat = cacheData.get()
      var i = 0
      while i + 1 < flat.len:
        emitPair(flat[i], flat[i+1])
        i += 2
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
  let sampleRate = audioStream.codecpar.sample_rate
  if sampleRate <= 0:
    error "Audio stream has invalid sample rate"

  var processor = AudioProcessor(
    codecCtx: initDecoder(audioStream.codecpar),
    audioIndex: audioStream.index,
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

  if not offsetEmitted:
    echo "@offset 0"
  echo ""

  if not windowed and not noCache:
    writeCache(flat, cacheTb, inputFile, "waveform", cacheArgs)
