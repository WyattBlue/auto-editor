import std/[options, strformat, strutils]

import ../util/rational
import ../lib/dnorm16
import ../[av, cache, cli, editparse, ffmpeg, log]
import ../analyze/[audio, blackdetect, motion, subtitle]
import ../lib/audioutil
import ./help

import ../vendor/tinyre/tinyre

proc parseUnitFloat(name, value: string): float32 =
  let f = (
    try: parseFloat(value)
    except ValueError: error &"Invalid {name}: {value}"
  )
  # `not (>= and <=)` so NaN is rejected too.
  if not (f >= 0.0 and f <= 1.0): error &"{name} must be in range [0, 1]"
  result = f.float32

proc parseStream(value: string): int16 =
  let n = (
    try: parseInt(value)
    except ValueError: error &"Invalid stream: {value}"
  )
  if n < 0 or n > 1000: error &"Invalid stream: {value}"
  result = n.int16

proc parseNatural(name, value: string, positive = false): int32 =
  let n = (
    try: parseInt(value)
    except ValueError: error &"Invalid {name}: {value}"
  )
  if (positive and n < 1) or n < 0 or n > high(int32):
    error &"Invalid {name}: {value}"
  result = n.int32

proc parseBool(value: string): bool =
  case value
  of "#t", "true": true
  of "#f", "false": false
  else: error &"Invalid boolean (expected true or false): {value}"

proc parseLevelsMethod(editStr: string): EditMethod =
  ## `levels --edit`: one method, without a threshold (levels are what a
  ## threshold would be compared against).
  let parsed = (
    try: parseSingleEditMethod("levels --edit", editStr)
    except ValueError as e: error &"levels --edit: {e.msg}"
  )

  result = case parsed.name
    of "audio": audioMethod(stream = 0)
    of "motion": motionMethod()
    of "blackdetect": blackdetectMethod()
    of "word": wordMethod("")
    else: subtitleMethod("")

  for (position, value) in parsed.args:
    case result.kind
    of ekAudio:
      case position
      of 0: error "threshold parameter not allowed for levels command"
      of 1: result.stream = parseStream(value)
      of 2: result.channel = value
      else: error "Too many args"
    of ekMotion:
      case position
      of 0: error "threshold parameter not allowed for levels command"
      of 1: result.stream = parseStream(value)
      of 2: result.width = parseNatural("width", value, positive = true)
      of 3: result.blur = parseNatural("blur", value)
      of 4: result.region.x = parseUnitFloat("x", value)
      of 5: result.region.y = parseUnitFloat("y", value)
      of 6: result.region.w = parseUnitFloat("w", value)
      of 7: result.region.h = parseUnitFloat("h", value)
      else: error "Too many args"
    of ekBlackdetect:
      case position
      of 0: error "threshold parameter not allowed for levels command"
      of 1: result.stream = parseStream(value)
      of 2: result.pixelBlack = parseUnitFloat("pixel-black", value)
      else: error "Too many args"
    of ekSubtitle, ekWord:
      case position
      of 0: result.pattern = value
      of 1: result.stream = parseStream(value)
      of 2: result.ignoreCase = parseBool(value)
      else: error "Too many args"
    of ekNone, ekAll:
      discard

const levelsArgumentOptions = {coEdit, coTimebase, coDisplay}

assertArgumentOptions(levelsOptions, levelsArgumentOptions)

type LevelsJob = object
  ## An opened, validated levels request; see `openLevels`.
  input: string
  tb: AVRational
  m: EditMethod
  container: InputContainer
  channelIndex: int
  cacheArgs: string
  rect: Unorm24x4

func cacheName(m: EditMethod): string =
  ## The analysis cache's name for the method.
  case m.kind
  of ekAudio: "audio"
  of ekMotion: "motion"
  of ekBlackdetect: "blackdetect"
  of ekWord: "word"
  else: "subtitle"

proc openLevels(inputFile: string, m: EditMethod, tb: AVRational): LevelsJob =
  ## Levels of one stream of `inputFile` at `tb`, for audio, motion and
  ## blackdetect; subtitle methods only open the file (see `main`). The
  ## method's threshold is ignored.
  let userStream = m.stream
  result = LevelsJob(input: inputFile, tb: tb, m: m, channelIndex: -1)
  if m.kind == ekMotion:
    let r = m.region
    result.rect = packUnorm24x4(r.x, r.y, r.w, r.h)

  if userStream < 0:
    error "Stream must be positive"
  if m.kind == ekAudio and m.channel != "all" and audioChannelCode(m.channel) == "":
    error &"audio: unknown channel '{m.channel}'."

  try:
    result.container = av.open(inputFile)
  except IOError as e:
    error e.msg

  if m.kind == ekAudio:
    if result.container.audio.len == 0:
      result.container.close()
      error "No audio stream"
    if result.container.audio.len <= userStream:
      result.container.close()
      error &"Audio stream out of range: {userStream}"
    let audioStream = result.container.audio[userStream]
    result.channelIndex = resolveAudioChannelOrDefault(
      addr audioStream.codecpar.ch_layout, m.channel)
    if result.channelIndex < -1:
      let layout = $addr audioStream.codecpar.ch_layout
      result.container.close()
      error &"audio: channel '{m.channel}' does not exist in stream {userStream} ({layout})."

  # Must stay in sync with the cacheArgs formats in src/analyze/*.nim.
  result.cacheArgs = case m.kind
    of ekAudio: $userStream & ":" & $result.channelIndex
    of ekBlackdetect: &"{userStream},{m.pixelBlack}"
    of ekMotion: &"{userStream},{m.width},{m.blur},{result.rect}"
    else: ""

proc close(job: var LevelsJob) = job.container.close()

proc computeLevels(job: var LevelsJob): tuple[data: seq[Unorm16], decodeErrors: int] =
  ## Levels for audio, motion and blackdetect, via the analysis cache. The
  ## caller decides what incomplete data (decodeErrors > 0) means.
  let tb = job.tb
  let editMethod = job.m.cacheName
  let userStream = job.m.stream
  let container = job.container
  let chunkDuration: float64 = av_inv_q(tb)

  if not noCache:
    let cacheData = readCache[Unorm16](job.input, tb, editMethod, job.cacheArgs)
    if cacheData.isSome:
      return (cacheData.get(), 0)

  let errorsBefore = decodeErrors
  var data: seq[Unorm16]
  case job.m.kind
  of ekAudio:
    let audioStream: ptr AVStream = container.audio[userStream]
    var processor = AudioProcessor(
      codecCtx: initDecoder(audioStream.codecpar),
      audioIndex: audioStream.index,
      channel: job.channelIndex,
      chunkDuration: chunkDuration
    )
    for u in processor.loudness(container):
      data.add u

  of ekMotion, ekBlackdetect:
    if container.video.len == 0:
      error "No video stream"
    if container.video.len <= userStream:
      error &"Video stream out of range: {userStream}"

    let videoStream: ptr AVStream = container.video[userStream]
    var processor = VideoProcessor(
      formatCtx: container.formatContext,
      codecCtx: initDecoder(videoStream.codecpar),
      tb: tb,
      videoIndex: videoStream.index,
    )
    if job.m.kind == ekMotion:
      for u in processor.motionness(job.m.width.int32, job.m.blur.int32, job.rect):
        data.add u
    else:
      for u in processor.blackness(job.m.pixelBlack):
        data.add u
  else:
    error &"{editMethod} has no levels; it matches subtitles instead"

  let errs = decodeErrors - errorsBefore
  if not noCache and errs == 0:
    writeCache(data, tb, job.input, editMethod, job.cacheArgs)
  (data, errs)

proc main*(strArgs: seq[string]) =
  var
    inputFile = ""
    edit = "audio"
    display = "float"
    tb = AVRational(num: 30, den: 1)

  parseArgs(strArgs, levelsOptions, "<file> [options]", "--"):
    case expecting
    of coNone:
      if inputFile != "":
        error &"Input file is already set: {key}"
      inputFile = key
    of coTimebase:
      try: tb = toAVRational(key)
      except ValueError as e: error e.msg
    of coEdit:
      edit = key
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

  av_log_set_level(AV_LOG_QUIET)
  var job = openLevels(inputFile, parseLevelsMethod(edit), tb)
  defer: job.close()

  echo "\n@start"

  if job.m.kind in {ekSubtitle, ekWord}:
    let parsedMethod = job.m
    let container = job.container
    if container.subtitle.len == 0:
      error "No Subtitle stream"

    # subtitle/regex match utf8; ignoreCase already carries word's default.
    var flags: set[ReFlag]
    if parsedMethod.kind != ekWord:
      flags.incl reUtf8
    if parsedMethod.ignoreCase:
      flags.incl reIgnoreCase

    var regPattern: Re
    try:
      regPattern =
        if parsedMethod.kind == ekWord:
          re("\\b" & escapeRe(parsedMethod.pattern) & "\\b", flags)
        else:
          re(parsedMethod.pattern, flags)
    except ValueError:
      error &"Invalid regex expression: {parsedMethod.pattern}"

    let (ret, values) = subtitle(container, tb, regPattern, parsedMethod.stream.int16)
    if ret != -1:
      error &"Subtitle stream out of range: {ret}"
    for value in values:
      echo (if value: "1" else: "0")
    return

  let (data, errs) = computeLevels(job)
  for u in data:
    if display == "d16": echo uint16(u) else: echo u
  echo ""

  if errs > 0:
    error &"Could not decode {errs} packet(s); levels are incomplete."
