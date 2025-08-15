import std/options
import std/[strformat, strutils]

import ../av
import ../ffmpeg
import ../analyze/[audio, motion, subtitle]
import ../log
import ../cache
import ../palet/edit

type levelArgs* = object
  timebase*: string = "30/1"
  edit*: string = "audio"
  noCache*: bool = false

proc main*(strArgs: seq[string]) =
  if strArgs.len < 1:
    echo "Display loudness over time"
    quit(0)

  var args = levelArgs()
  var expecting: string = ""
  var inputFile: string = ""

  for key in strArgs:
    case key
    of "--no-cache":
      args.noCache = true
    of "-tb":
      expecting = "timebase"
    of "--timebase", "--edit":
      expecting = key[2..^1]
    else:
      if key.startsWith("--"):
        error(fmt"Unknown option: {key}")

      case expecting
      of "":
        inputFile = key
      of "timebase":
        args.timebase = key
      of "edit":
        args.edit = key
      expecting = ""

  if expecting != "":
    error(fmt"--{expecting} needs argument.")

  if inputFile == "":
    error("Expecting an input file.")

  av_log_set_level(AV_LOG_QUIET)
  let tb = AVRational(args.timebase)
  let chunkDuration: float64 = av_inv_q(tb)
  let (editMethod, _, userStream, width, blur, pattern) = parseEditString2(args.edit)
  if editMethod notin ["audio", "motion", "subtitle"]:
    error fmt"Unknown editing method: {editMethod}"

  let cacheArgs = (if editMethod == "audio": $userStream else: &"{userStream},{width},{blur}")

  if userStream < 0:
    error "Stream must be positive"

  echo "\n@start"

  if not args.noCache:
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
      error fmt"Audio stream out of range: {userStream}"

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
      error fmt"Video stream out of range: {userStream}"

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

  elif editMethod == "subtitle":
    if container.subtitle.len == 0:
      error "No Subtitle stream"
    if container.subtitle.len <= userStream:
      error fmt"Subtitle stream out of range: {userStream}"

    for value in subtitle(container, tb, pattern, userStream):
      echo (if value: "1" else: "0")

  if editMethod != "subtitle" and not args.noCache:
    writeCache(data, inputFile, tb, editMethod, cacheArgs)
