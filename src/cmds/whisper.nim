import std/[os, strformat, strutils]
import ../[av, cli, ffmpeg, log, transcribe]
import ../util/[dnorm16, fun]
import ./help
when defined(macosx):
  import ../mic

var ctrlcStop = false
proc onCtrlC() {.noconv.} =
  ctrlcStop = true

proc main*(cArgs: seq[string]) =
  var inputPath: string = ""
  var model: string = ""
  var isDebug = false
  var splitWords = false
  var language = "auto"
  var translate = false # to English
  var format = "text"
  var formatExplicit = false
  var output = "-"
  var queue: int = 30
  var prompt: string = ""
  var threads: cint = 4
  var threshold: float32 = 0.04

  var expecting: string = ""
  for key in cArgs:
    if genCliMacro(key, args, whisperOptions):
      continue
    if key in ["-h", "--help"]:
      printHelp("<file|:mic> <model> [options]", whisperOptions)
    if key.startsWith("--"):
      error &"Unknown option: {key}{optionDidYouMean(key, whisperOptions)}"
    case expecting:
    of "":
      if inputPath == "":
        inputPath = key
      elif model == "":
        model = key
      else:
        error "Got too many arguments\nUsage: <file|:mic> <model> [options]"
    of "language":
      language = key
    of "format":
      format = key
      formatExplicit = true
    of "output":
      output = key
    of "queue":
      queue = (
        try: parseInt(key)
        except ValueError: error &"Invalid --queue: {key}"
      )
    of "prompt":
      prompt = key
    of "threads":
      let n = (
        try: parseInt(key)
        except ValueError: error &"Invalid --threads: {key}"
      )
      if n < 1 or n > 1024:
        error &"--threads must be in range [1, 1024], got: {key}"
      threads = n.cint
    of "threshold":
      threshold = parseThres(key).toFloat32
    expecting = ""

  if inputPath == "":
    error "A media file is needed"
  if model == "":
    error "A model is needed, you came find them here: https://huggingface.co/ggerganov/whisper.cpp\n" &
      "Or use 'apple' for the built-in macOS 26+ transcriber"
  if model == "apple":
    if translate:
      error "--translate is not supported with the apple model"
    if prompt != "":
      error "--prompt is not supported with the apple model"

  let isMic = (inputPath == ":mic")
  # Install early so Ctrl-C is graceful even during the (slow) model load.
  setControlCHook(onCtrlC)

  if queue < 1 or queue > 86400:
    error &"Invalid queue value: {queue}"
  if output != "-" and not formatExplicit:
    case output.splitFile.ext.toLowerAscii
    of ".srt": format = "srt"
    of ".json": format = "json"
    of ".txt", ".text": format = "text"
    else: discard
  if format notin ["text", "srt", "json"]:
    error &"Invalid format: {format}. Choices: text, srt, json"

  av_log_set_level(if isDebug: AV_LOG_DEBUG else: AV_LOG_ERROR)

  var fmtCtx: ptr AVFormatContext
  var audioStream: ptr AVStream
  var input: InputContainer

  if isMic:
    when defined(macosx):
      let (devName, warnMsg) = chooseMicDevice()
      if devName == "":
        error "No microphone found"
      if warnMsg != "":
        warning warnMsg

      avdevice_register_all()
      let avf = av_find_input_format("avfoundation")
      if avf == nil:
        error "Could not find avfoundation input device"
      # ":<name>" selects audio only (empty video field); avfoundation matches
      # the name against each device's localizedName.
      if avformat_open_input(addr fmtCtx, (":" & devName).cstring, avf, nil) < 0:
        error &"Could not open microphone \"{devName}\""
      if avformat_find_stream_info(fmtCtx, nil) < 0:
        error "Could not read microphone stream info"
      for i in 0 ..< fmtCtx.nb_streams.int:
        if fmtCtx.streams[i].codecpar.codec_type == AVMEDIA_TYPE_AUDIO:
          audioStream = fmtCtx.streams[i]
          break
      if audioStream == nil:
        error "Microphone has no audio stream"
      stderr.writeLine(&"Listening on \"{devName}\"... (press Ctrl-C to stop)")
    else:
      error "Microphone capture (:mic) is only supported on macOS"
  else:
    input = (try: av.open(inputPath) except: error "Invalid media file")
    if input.audio.len == 0:
      error "No audio stream found"
    audioStream = input.audio[0]
    fmtCtx = input.formatContext

  defer:
    if isMic: avformat_close_input(addr fmtCtx)
    else: input.close()

  transcribe.run(fmtCtx, audioStream, model, language, translate, format, output,
                 queue, threshold, prompt, threads, splitWords, isDebug, addr ctrlcStop)
  if isMic:
    stderr.writeLine("")
