import std/[options, strformat, strutils]

import ../util/[rational, dnorm16]
import ../[av, cache, cli, ffmpeg, log]
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

proc parseEdit(editStr: string): (string, string, int16, int32, int32, float32,
    bool, float32, float32, float32, float32) =
  var
    stream: int16 = 0
    pattern = ""
    width: int32 = 400
    blur: int32 = 9
    pixelBlack: float32 = 0.10
    x: float32 = 0.0
    y: float32 = 0.0
    w: float32 = 1.0
    h: float32 = 1.0

  let colonPos = editStr.find(':')
  let kind = if colonPos == -1: editStr else: editStr[0 ..< colonPos]
  var ignoreCase = kind == "word"  # word matches case-insensitively by default

  if colonPos == -1:
    return (kind, pattern, stream, width, blur, pixelBlack, ignoreCase, x, y, w, h)

  let paramsStr = editStr[colonPos+1..^1]

  var i = 0
  while i < paramsStr.len:
    while i < paramsStr.len and paramsStr[i] == ' ':
      inc i

    if i >= paramsStr.len:
      break

    var paramStart = i
    while i < paramsStr.len and paramsStr[i] != '=':
      inc i

    if i >= paramsStr.len:
      error "No parameter found. Expected this format: method:key=value"

    let paramName = paramsStr[paramStart..<i]
    inc i

    var value = ""
    if i < paramsStr.len and paramsStr[i] == '"':
      inc i
      while i < paramsStr.len:
        if paramsStr[i] == '\\' and i + 1 < paramsStr.len:
          # Handle escape sequences
          inc i
          case paramsStr[i]:
            of '"': value.add('"')
            of '\\': value.add('\\')
            else:
              value.add('\\')
              value.add(paramsStr[i])
        elif paramsStr[i] == '"':
          inc i
          break
        else:
          value.add(paramsStr[i])
        inc i
    else:
      # Unquoted value (until comma or end)
      while i < paramsStr.len and paramsStr[i] != ',':
        value.add(paramsStr[i])
        inc i

    case paramName:
      of "stream":
        let n = (
          try: parseInt(value)
          except ValueError: error &"Invalid stream: {value}"
        )
        if n < 0 or n > 1000: error &"Invalid stream: {value}"
        stream = n.int16
      of "width":
        let n = (
          try: parseInt(value)
          except ValueError: error &"Invalid width: {value}"
        )
        if n < 1 or n > high(int32): error &"Invalid width: {value}"
        width = n.int32
      of "blur":
        let n = (
          try: parseInt(value)
          except ValueError: error &"Invalid blur: {value}"
        )
        if n < 0 or n > high(int32): error &"Invalid blur: {value}"
        blur = n.int32
      of "pixel-black": pixelBlack = parseUnitFloat("pixel-black", value)
      of "x": x = parseUnitFloat("x", value)
      of "y": y = parseUnitFloat("y", value)
      of "w": w = parseUnitFloat("w", value)
      of "h": h = parseUnitFloat("h", value)
      of "pattern": pattern = value
      of "ignore-case":
        case value
        of "#t", "true": ignoreCase = true
        of "#f", "false": ignoreCase = false
        else: error &"Invalid boolean (expected true or false): {value}"
      of "threshold": error "threshold parameter not allowed for levels command"
      else: error &"Unknown parameter: {paramName}"

    # Skip comma
    if i < paramsStr.len and paramsStr[i] == ',':
      inc i

  return (kind, pattern, stream, width, blur, pixelBlack, ignoreCase, x, y, w, h)


proc main*(strArgs: seq[string]) =
  var
    expecting = ""
    inputFile = ""
    edit = "audio"
    display = "float"
    tb = AVRational(num: 30, den: 1)

  for key in strArgs:
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
  let (editMethod, pattern, userStream, width, blur, pixelBlack, ignoreCase,
    x, y, w, h) = parseEdit(edit)

  if editMethod notin ["audio", "motion", "blackdetect", "subtitle", "word", "regex"]:
    error &"Unknown editing method: {editMethod}"
  if userStream < 0:
    error "Stream must be positive"

  # Must stay in sync with the cacheArgs formats in src/analyze/*.nim.
  let cacheArgs =
    if editMethod == "audio": $userStream
    elif editMethod == "blackdetect": &"{userStream},{pixelBlack}"
    else: &"{userStream},{width},{blur},{x},{y},{w},{h}"

  template emit(u: Unorm16) =
    if display == "d16": echo uint16(u) else: echo u

  echo "\n@start"

  if not noCache:
    let cacheData = readCache[Unorm16](inputFile, tb, editMethod, cacheArgs)
    if cacheData.isSome:
      for loudnessValue in cacheData.get():
        emit loudnessValue
      echo ""
      return

  var container: InputContainer
  var data: seq[Unorm16] = @[]

  try:
    container = av.open(inputFile)
  except IOError as e:
    error e.msg
  defer: container.close()

  if editMethod == "audio":
    if container.audio.len == 0:
      error "No audio stream"
    if container.audio.len <= userStream:
      error &"Audio stream out of range: {userStream}"

    let audioStream: ptr AVStream = container.audio[userStream]
    var processor = AudioProcessor(
      codecCtx: initDecoder(audioStream.codecpar),
      audioIndex: audioStream.index,
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

    for u in processor.motionness(width, blur, x, y, w, h):
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

    for u in processor.blackness(pixelBlack):
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
    if ignoreCase:
      flags.incl reIgnoreCase

    var regPattern: Re
    try:
      regPattern =
        if editMethod == "word": re("\\b" & escapeRe(pattern) & "\\b", flags)
        else: re(pattern, flags)
    except ValueError:
      error &"Invalid regex expression: {pattern}"

    let (ret, values) = subtitle(container, tb, regPattern, userStream)
    if ret != -1:
      error &"Subtitle stream out of range: {ret}"
    for value in values:
      echo (if value: "1" else: "0")

  if not noCache and editMethod notin ["subtitle", "word", "regex"]:
    writeCache(data, tb, inputFile, editMethod, cacheArgs)
