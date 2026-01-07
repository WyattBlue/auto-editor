import std/[options, strformat, strutils]

import ../[av, cache, ffmpeg, log]
import ../analyze/[audio, motion, subtitle]

import tinyre

proc parseEdit(editStr: string): (string, string, int32, int32, int32) =
  var
    stream: int32 = 0
    pattern = ""
    width: int32 = 400
    blur: int32 = 9

  let colonPos = editStr.find(':')
  if colonPos == -1:
    return (editStr, pattern, stream, width, blur)

  let kind = editStr[0 ..< colonPos]
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
      error &"No parameter found. Expected this format: method:key=value"

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
      of "stream": stream = parseInt(value).int32
      of "width": width = parseInt(value).int32
      of "blur": blur = parseInt(value).int32
      of "pattern": pattern = value
      of "threshold": error "threshold parameter not allowed for levels command"
      else: error &"Unknown parameter: {paramName}"

    # Skip comma
    if i < paramsStr.len and paramsStr[i] == ',':
      inc i

  return (kind, pattern, stream, width, blur)


proc main*(strArgs: seq[string]) =
  var
    expecting = ""
    inputFile = ""
    edit = "audio"
    tb = AVRational(num: 30, den: 1)
    noCache = false

  for key in strArgs:
    case key
    of "--no-cache":
      noCache = true
    of "-tb":
      expecting = "timebase"
    of "--timebase", "--edit":
      expecting = key[2..^1]
    else:
      if key.startsWith("--"):
        error &"Unknown option: {key}"

      case expecting
      of "":
        if inputFile != "":
          error &"Input file is already set: {key}"
        inputFile = key
      of "timebase":
        try: tb = AVRational(key)
        except ValueError: error &"Invalid rational number: {key}"
      of "edit":
        edit = key
      expecting = ""

  if expecting != "":
    error &"--{expecting} needs argument."

  if inputFile == "":
    error "Expecting an input file."

  av_log_set_level(AV_LOG_QUIET)
  let chunkDuration: float64 = av_inv_q(tb)
  let (editMethod, pattern, userStream, width, blur) = parseEdit(edit)

  if editMethod notin ["audio", "motion", "subtitle", "word", "regex"]:
    error &"Unknown editing method: {editMethod}"
  if userStream < 0:
    error "Stream must be positive"

  let cacheArgs = if editMethod == "audio": $userStream else: &"{userStream},{width},{blur}"

  echo "\n@start"

  if not noCache:
    let cacheData = readCache(inputFile, tb, editMethod, cacheArgs)
    if cacheData.isSome:
      for loudnessValue in cacheData.get():
        echo loudnessValue
      echo ""
      return

  var container: InputContainer
  var data: seq[float32] = @[]

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

    for loudnessValue in processor.loudness(container):
      echo loudnessValue
      data.add loudnessValue
    echo ""

  elif editMethod == "motion":
    if container.video.len == 0:
      error "No audio stream"
    if container.video.len <= userStream:
      error &"Video stream out of range: {userStream}"

    let videoStream: ptr AVStream = container.video[userStream]
    var processor = VideoProcessor(
      formatCtx: container.formatContext,
      codecCtx: initDecoder(videoStream.codecpar),
      tb: tb,
      videoIndex: videoStream.index,
    )

    for value in processor.motionness(width, blur):
      echo value
      data.add value
    echo ""

  elif editMethod in ["subtitle", "word", "regex"]:
    if container.subtitle.len == 0:
      error "No Subtitle stream"

    var regPattern: Re
    try:
      regPattern = if editMethod == "word": re("\\b" & escapeRe(pattern) & "\\b") else: re(pattern)
    except ValueError:
      error &"Invalid regex expression: {pattern}"

    let (ret, values) = subtitle(container, tb, regPattern, userStream)
    if ret != -1:
      error &"Subtitle stream out of range: {ret}"
    for value in values:
      echo (if value: "1" else: "0")

  if not noCache and editMethod notin ["subtitle", "word", "regex"]:
    writeCache(data, inputFile, tb, editMethod, cacheArgs)
