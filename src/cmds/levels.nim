import std/[options, strformat, strutils]

import ../util/[rational, dnorm16]
import ../[av, cache, cli, editparse, ffmpeg, log]
import ../analyze/[audio, blackdetect, motion, subtitle]
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

type LevelsMethod = object
  name: string
  pattern: string
  stream: int16
  channel: string
  width: int32
  blur: int32
  pixelBlack: float32
  ignoreCase: bool
  x, y, w, h: float32

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

proc parseLevelsMethod(editStr: string): LevelsMethod =
  let parsed = (
    try: parseSingleEditMethod("levels --edit", editStr)
    except ValueError as e: error &"levels --edit: {e.msg}"
  )

  result = LevelsMethod(
    name: parsed.name,
    stream: 0,
    channel: "all",
    width: 400,
    blur: 9,
    pixelBlack: 0.10,
    ignoreCase: parsed.name == "word",
    x: 0.0,
    y: 0.0,
    w: 1.0,
    h: 1.0,
  )

  for (position, value) in parsed.args:
    case result.name
    of "audio":
      case position
      of 0: error "threshold parameter not allowed for levels command"
      of 1: result.stream = parseStream(value)
      of 2: result.channel = value
      else: error "Too many args"
    of "motion":
      case position
      of 0: error "threshold parameter not allowed for levels command"
      of 1: result.stream = parseStream(value)
      of 2: result.width = parseNatural("width", value, positive = true)
      of 3: result.blur = parseNatural("blur", value)
      of 4: result.x = parseUnitFloat("x", value)
      of 5: result.y = parseUnitFloat("y", value)
      of 6: result.w = parseUnitFloat("w", value)
      of 7: result.h = parseUnitFloat("h", value)
      else: error "Too many args"
    of "blackdetect":
      case position
      of 0: error "threshold parameter not allowed for levels command"
      of 1: result.stream = parseStream(value)
      of 2: result.pixelBlack = parseUnitFloat("pixel-black", value)
      else: error "Too many args"
    of "subtitle", "regex", "word":
      case position
      of 0: result.pattern = value
      of 1: result.stream = parseStream(value)
      of 2: result.ignoreCase = parseBool(value)
      else: error "Too many args"
    else:
      error &"Unknown editing method: {result.name}"

proc main*(strArgs: seq[string]) =
  var
    expecting = ""
    inputFile = ""
    edit = "audio"
    display = "float"
    tb = AVRational(num: 30, den: 1)
    parseOptions = true

  for key in strArgs:
    if parseOptions and expecting == "" and key == "--":
      parseOptions = false
      continue
    if parseOptions:
      if genCliMacro(key, strArgs, levelsOptions):
        continue
      if key in ["-h", "--help"]:
        printHelp("<file> [options]", levelsOptions)
      if key.startsWith("--"):
        error &"Unknown option: {key}{optionDidYouMean(key, levelsOptions)}"

    case expecting
    of "":
      if inputFile != "":
        error &"Input file is already set: {key}"
      inputFile = key
    of "timebase":
      try: tb = toAVRational(key)
      except ValueError as e: error e.msg
    of "edit":
      edit = key
    of "display":
      display = key
    expecting = ""

  if expecting != "":
    error &"--{expecting} needs argument."

  if display notin ["float", "d16"]:
    error &"Unknown display format: {display}"

  if inputFile == "":
    error "Expecting an input file."

  av_log_set_level(AV_LOG_QUIET)
  let chunkDuration: float64 = av_inv_q(tb)
  let parsedMethod = parseLevelsMethod(edit)
  let editMethod = parsedMethod.name
  let userStream = parsedMethod.stream
  let rect = packUnorm24x4(
    parsedMethod.x, parsedMethod.y, parsedMethod.w, parsedMethod.h)

  if userStream < 0:
    error "Stream must be positive"
  if editMethod == "audio" and parsedMethod.channel != "all" and
      audioChannelCode(parsedMethod.channel) == "":
    error &"audio: unknown channel '{parsedMethod.channel}'."

  template emit(u: Unorm16) =
    if display == "d16": echo uint16(u) else: echo u

  var container: InputContainer
  var data: seq[Unorm16] = @[]

  try:
    container = av.open(inputFile)
  except IOError as e:
    error e.msg
  defer: container.close()

  var channelIndex = -1
  if editMethod == "audio":
    if container.audio.len == 0:
      error "No audio stream"
    if container.audio.len <= userStream:
      error &"Audio stream out of range: {userStream}"
    let audioStream = container.audio[userStream]
    channelIndex = resolveAudioChannelOrDefault(
      addr audioStream.codecpar.ch_layout, parsedMethod.channel)
    if channelIndex < -1:
      let layout = $addr audioStream.codecpar.ch_layout
      error &"audio: channel '{parsedMethod.channel}' does not exist in stream {userStream} ({layout})."

  # Must stay in sync with the cacheArgs formats in src/analyze/*.nim.
  let cacheArgs =
    if editMethod == "audio": $userStream & ":" & $channelIndex
    elif editMethod == "blackdetect": &"{userStream},{parsedMethod.pixelBlack}"
    else: &"{userStream},{parsedMethod.width},{parsedMethod.blur},{rect}"

  echo "\n@start"

  if not noCache:
    let cacheData = readCache[Unorm16](inputFile, tb, editMethod, cacheArgs)
    if cacheData.isSome:
      for loudnessValue in cacheData.get():
        emit loudnessValue
      echo ""
      return

  if editMethod == "audio":
    let audioStream: ptr AVStream = container.audio[userStream]
    var processor = AudioProcessor(
      codecCtx: initDecoder(audioStream.codecpar),
      audioIndex: audioStream.index,
      channel: channelIndex,
      chunkDuration: chunkDuration
    )

    for u in processor.loudness(container):
      emit u
      data.add u
    echo ""

  elif editMethod == "motion":
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

    for u in processor.motionness(parsedMethod.width, parsedMethod.blur, rect):
      emit u
      data.add u
    echo ""

  elif editMethod == "blackdetect":
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

    for u in processor.blackness(parsedMethod.pixelBlack):
      emit u
      data.add u
    echo ""

  elif editMethod in ["subtitle", "word", "regex"]:
    if container.subtitle.len == 0:
      error "No Subtitle stream"

    # subtitle/regex match utf8; ignoreCase already carries word's default.
    var flags: set[ReFlag]
    if editMethod != "word":
      flags.incl reUtf8
    if parsedMethod.ignoreCase:
      flags.incl reIgnoreCase

    var regPattern: Re
    try:
      regPattern =
        if editMethod == "word":
          re("\\b" & escapeRe(parsedMethod.pattern) & "\\b", flags)
        else:
          re(parsedMethod.pattern, flags)
    except ValueError:
      error &"Invalid regex expression: {parsedMethod.pattern}"

    let (ret, values) = subtitle(container, tb, regPattern, userStream)
    if ret != -1:
      error &"Subtitle stream out of range: {ret}"
    for value in values:
      echo (if value: "1" else: "0")

  if not noCache and editMethod notin ["subtitle", "word", "regex"]:
    writeCache(data, tb, inputFile, editMethod, cacheArgs)
