import std/[os, osproc, parseutils, sequtils, strformat, strutils, terminal, uri]
when not defined(windows):
  import std/posix_utils

import about
import cli
import edit
import log
import ffmpeg
import cmds/[info, desc, cache, levels, subdump, whisper]
import util/[color, fun]
import palet/edit

import tinyre

proc ctrlc() {.noconv.} =
  error "Keyboard Interrupt"

setControlCHook(ctrlc)

proc wrapText(text: string, width, indent: int): string =
  let text = text.strip(leading = true, trailing = true, chars = {'\n'})
  if text.len == 0:
    return ""
  let indentStr = " ".repeat(indent)
  var outLines: seq[string] = @[]
  var isFirst = true

  for line in text.split("\n"):
    if line.len == 0:
      outLines.add("")
      continue

    # Detect leading whitespace
    var leadingSpaces = 0
    for c in line:
      if c == ' ':
        leadingSpaces += 1
      else:
        break
    let lineIndent = " ".repeat(leadingSpaces)
    let content = line[leadingSpaces .. ^1]

    var currentLine = ""
    for word in content.splitWhitespace():
      if currentLine.len == 0:
        currentLine = word
      elif leadingSpaces + currentLine.len + 1 + word.len <= width:
        currentLine &= " " & word
      else:
        if isFirst:
          outLines.add(lineIndent & currentLine)
          isFirst = false
        else:
          outLines.add(indentStr & lineIndent & currentLine)
        currentLine = word
    if currentLine.len > 0:
      if isFirst:
        outLines.add(lineIndent & currentLine)
        isFirst = false
      else:
        outLines.add(indentStr & lineIndent & currentLine)

  result = outLines.join("\n")

proc categoryName(c: Categories): string =
  case c
  of cEdit: "Editing Options"
  of cTl: "Timeline Options"
  of cUrl: "URL Download Options"
  of cDis: "Display Options"
  of cCon: "Container Settings"
  of cVid: "Video Rendering"
  of cAud: "Audio Rendering"
  of cMis: "Miscellaneous"

proc printHelp() {.noreturn.} =
  let termWidth = max(terminalWidth(), 40)
  let optWidth = min(32, termWidth div 3)
  let helpWidth = termWidth - optWidth - 4

  echo "usage: [file | url ...] [options]\n"
  echo "Commands:"
  echo "  " & commands.mapIt(it.name).join(" ") & "\n"
  echo "Options:"

  var currentCat: Categories = cEdit
  var first = true

  for opt in mainOptions:
    if opt.help == "":
      continue

    if opt.c != currentCat or first:
      currentCat = opt.c
      if first:
        first = false
      else:
        echo ""
      echo "  " & categoryName(currentCat) & ":"

    var optStr = "    " & opt.names
    if opt.metavar != "":
      optStr &= " " & opt.metavar

    if optStr.len >= optWidth:
      echo optStr
      let wrapped = wrapText(opt.help, helpWidth, 0)
      for line in wrapped.split("\n"):
        echo " ".repeat(optWidth) & line
    else:
      let padding = optWidth - optStr.len
      let wrapped = wrapText(opt.help, helpWidth, optWidth)
      let helpLines = wrapped.split("\n")
      echo optStr & " ".repeat(padding) & helpLines[0]
      for i in 1 ..< helpLines.len:
        echo helpLines[i]

  echo "\n    -h, --help" & " ".repeat(optWidth - 14) &
    wrapText("Show info about this program then exit", helpWidth, optWidth)
  echo ""

  quit(0)

proc parseMargin(val: string): (PackedInt, PackedInt) =
  var vals = val.strip().split(",")
  if vals.len == 1:
    vals.add vals[0]
  if vals.len != 2:
    error "--margin has too many arguments."
  if "end" in vals:
    error "Invalid number: 'end'"
  if "start" in vals:
    error "Invalid number: 'start'"
  return (parseTime(vals[0]), parseTime(vals[1]))

proc parseTimeRange(val, opt: string): (PackedInt, PackedInt) =
  var vals = val.strip().split(",")
  if vals.len < 2:
    error &"--{opt} has too few arguments"
  if vals.len > 2:
    error &"--{opt} has too many arguments"
  return (parseTime(vals[0]), parseTime(vals[1]))

proc parseNum(val, opt: string): float64 =
  let (num, unit) = splitNumStr(val)
  if unit == "%":
    result = num / 100.0
  elif unit == "":
    result = num
  else:
    error &"--{opt} has unknown unit: {unit}"

proc parseResolution(val, opt: string): (int, int) =
  let vals = val.strip().split(",")
  if len(vals) != 2:
    error &"'{val}': --{opt} takes two numbers"

  discard parseSaturatedNatural(vals[0], result[0])
  discard parseSaturatedNatural(vals[1], result[1])
  if result[0] < 1 or result[1] < 1:
    error &"--{opt} must be positive"

proc parseSpeed(val, opt: string): float64 =
  result = parseNum(val, opt)
  if result <= 0.0 or result > 99999.0:
    result = 99999.0

proc parseSpeedRange(val: string): (float64, PackedInt, PackedInt) =
  let vals = val.strip().split(",")
  if vals.len < 3:
    error &"--set-speed has too few arguments"
  if vals.len > 3:
    error &"--set-speed has too many arguments"
  return (parseSpeed(vals[0], "set-speed"), parseTime(vals[1]), parseTime(vals[2]))


proc parseSampleRate(val: string): cint =
  let (num, unit) = splitNumStr(val)
  if unit == "kHz" or unit == "KHz":
    result = cint(num * 1000)
  elif unit notin ["", "Hz"]:
    error &"Unknown unit: '{unit}'"
  else:
    result = cint(num)
  if result < 1:
    error "Samplerate must be positive"

proc parseFrameRate(val: string): AVRational =
  if val == "ntsc":
    return AVRational(num: 30000, den: 1001)
  if val == "ntsc_film":
    return AVRational(num: 24000, den: 1001)
  if val == "pal":
    return AVRational(num: 25, den: 1)
  if val == "film":
    return AVRational(num: 24, den: 1)
  return AVRational(val)


proc downloadVideo(myInput: string, args: mainArgs): string =
  conwrite("Downloading video...")

  proc getDomain(url: string): string =
    let parsed = parseUri(url)
    var hostname = parsed.hostname
    if hostname.startsWith("www."):
      hostname = hostname[4..^1]
    return hostname

  var downloadFormat = args.downloadFormat
  if downloadFormat == "" and getDomain(myInput) == "youtube.com":
    downloadFormat = "bestvideo[ext=mp4]+bestaudio[ext=m4a]"

  var outputFormat: string
  if args.outputFormat == "":
    outputFormat = replacef(splitext(myInput)[0], re"\W+", "-") & ".%(ext)s"
  else:
    outputFormat = args.outputFormat

  var cmd: seq[string] = @[]
  if downloadFormat != "":
    cmd.add(@["-f", downloadFormat])

  cmd.add(@["-o", outputFormat, myInput])
  if args.yt_dlp_extras != "":
    cmd.add(args.ytDlpExtras.split(" "))

  let ytDlpPath = args.ytDlpLocation
  var location: string
  try:
    location = execProcess(ytDlpPath,
      args = @["--get-filename", "--no-warnings"] & cmd,
      options = {poUsePath}).strip()
  except OSError:
    error "Program `yt-dlp` must be installed and on PATH."

  if not fileExists(location):
    let p = startProcess(ytDlpPath, args = cmd, options = {poUsePath, poParentStreams})
    defer: p.close()
    discard p.waitForExit()

  if not fileExists(location):
    error &"Download file wasn't created: {location}"

  return location

proc listAvailableFilters(): string =
  result = "Filters:"
  var opaque: pointer = nil
  var filter: ptr AVFilter = av_filter_iterate(addr opaque)

  while filter != nil:
    if filter.name != nil:
      result &= &" {filter.name}"
    filter = av_filter_iterate(addr opaque)

proc parseActions(val: string): seq[Action] =
  try:
    let parts = val.strip().split(",")

    for part in parts:
      let trimmedPart = part.strip()

      if trimmedPart == "nil":
        discard
      elif trimmedPart == "cut":
        result.add Action(kind: actCut)
      elif trimmedPart.startsWith("speed:"):
        try:
          let value = parseFloat(trimmedPart[6 ..< trimmedPart.len])
          result.add Action(kind: actSpeed, val: value)
        except ValueError:
          error &"Invalid speed value in action: {trimmedPart}"
      elif trimmedPart.startsWith("varispeed:"):
        try:
          let value = parseFloat(trimmedPart[10 ..< trimmedPart.len])
          result.add Action(kind: actVarispeed, val: value)
        except ValueError:
          error &"Invalid varispeed value in action: {trimmedPart}"
      elif trimmedPart.startsWith("volume:"):
        try:
          let value = parseFloat(trimmedPart[7 ..< trimmedPart.len])
          result.add Action(kind: actVolume, val: value)
        except ValueError:
          error &"Invalid volume value in action: {trimmedPart}"
      else:
        error &"Invalid action: {trimmedPart}"
  except Exception as e:
    error &"Error parsing actions '{val}': {e.msg}"

func actionFromUserSpeed(val: float64): seq[Action] =
  if val == 1.0:
    return @[]
  elif val <= 0.0 or val >= 99999.0:
    return @[Action(kind: actCut)]
  else:
    return @[Action(kind: actSpeed, val: val)]

proc main() =
  if paramCount() < 1:
    if stdin.isatty():
      echo """Auto-Editor is an automatic video/audio creator and editor. By default, it
will detect silence and create a new video with those sections cut out. By
changing some of the options, you can export to a traditional editor like
Premiere Pro and adjust the edits there, adjust the pacing of the cuts, and
change the method of editing like using audio loudness and video motion to
judge making cuts.
"""
      quit(0)
  else:
    genCmdCases(paramStr(1))

  var args = mainArgs()
  var showVersion: bool = false
  var expecting: string = ""

  let cmdLineParams = commandLineParams()
  for rawKey in cmdLineParams:
    let key = handleKey(rawKey)

    if genCliMacro(key, args):
      continue

    case key:
    of "-h", "--help":
      printHelp()
    else:
      if key.startsWith("--"):
        error &"Unknown option: {key}"

      case expecting
      of "":
        args.input = key
      of "edit":
        args.edit = key
      of "export":
        args.`export` = key
      of "output":
        args.output = key
      of "when-silent":
        args.whenSilent = parseActions(key)
      of "when-normal":
        args.whenNormal = parseActions(key)
      of "silent-speed":
        args.whenSilent = actionFromUserSpeed(parseSpeed(key, expecting))
      of "video-speed":
        args.whenNormal = actionFromUserSpeed(parseSpeed(key, expecting))
      of "add-in":
        args.addIn.add parseTimeRange(key, expecting)
      of "cut-out":
        args.cutOut.add parseTimeRange(key, expecting)
      of "set-speed":
        args.setSpeed.add parseSpeedRange(key)
      of "yt-dlp-location":
        args.ytDlpLocation = key
      of "download-format":
        args.downloadFormat = key
      of "output-format":
        args.outputFormat = key
      of "yt-dlp-extras":
        args.ytDlpExtras = key
      of "scale":
        args.scale = parseNum(key, expecting)
      of "resolution":
        args.resolution = parseResolution(key, expecting)
      of "background":
        args.background = parseColor(key)
      of "sample-rate":
        args.sampleRate = parseSampleRate(key)
      of "frame-rate":
        args.frameRate = parseFrameRate(key)
      of "vcodec":
        args.videoCodec = key
      of "video-bitrate":
        args.videoBitrate = parseBitrate(key)
      of "vprofile":
        args.vprofile = key
      of "acodec":
        args.audioCodec = key
      of "layout":
        args.audioLayout = key
      of "audio-normalize":
        args.audioNormalize = parseNorm(key)
      of "audio-bitrate":
        args.audioBitrate = parseBitrate(key)
      of "progress":
        try:
          args.progress = parseEnum[BarType](key)
        except ValueError:
          error &"{key} is not a choice for --progress\nchoices are:\n  modern, classic, ascii, machine, none"
      of "margin":
        args.margin = parseMargin(key)
      of "tempdir":
        tempDir = key
      expecting = ""

  if expecting != "":
    error &"{cmdLineParams[^1]} needs argument."

  if showVersion:
    echo version
    quit(0)

  if args.input == "" and isDebug:
    echo "Auto-Editor: ", version
    when defined(windows):
      var cpuArchitecture: string
      when defined(amd64) or defined(x86_64):
        cpuArchitecture = "x86_64"
      elif defined(i386):
        cpuArchitecture = "i386"
      elif defined(arm64) or defined(aarch64):
        cpuArchitecture = "aarch64"
      else:
        cpuArchitecture = "unknown"
      echo "OS: Windows ", cpuArchitecture
    else:
      let plat = uname()
      echo "OS: ", plat.sysname, " ", plat.release, " ", plat.machine
    echo listAvailableFilters()
    quit(0)

  let myInput = args.input
  if myInput.startswith("http://") or myInput.startswith("https://"):
    args.input = downloadVideo(myInput, args)
  elif splitFile(myInput).ext == "":
    if dirExists(myInput):
      error &"Input must be a file or a URL, not a directory."
    if myInput.startswith("-"):
      error &"Option/Input file doesn't exist: {myInput}"
    error &"Input file must have an extension: {myInput}"

  editMedia(args)

when isMainModule:
  main()
