import std/[options, os, parseutils, sequtils, strformat, strutils]
when not defined(emscripten):
  import std/osproc
  import cmds/completion
when defined(emscripten):
  {.emit: """
extern int main(int argc, char** argv, char** env);
int __main_argc_argv(int argc, char** argv) {
  return main(argc, argv, (char**)0);
}
""".}
when not defined(windows) and not defined(emscripten):
  import std/posix_utils

import ./[about, action, cli, conductor, edit, ffmpeg, license, log, media]
import cmds/[info, desc, cache, levels, subdump, waveform, whisper]
import util/[color, fun, term, rational]

import vendor/tinyre/tinyre

proc ctrlc() {.noconv.} =
  error "Keyboard Interrupt"

setControlCHook(ctrlc)

when defined(debug) and not defined(emscripten) and not defined(windows):
  import std/[posix, strutils]
  proc sigsegvHandler(sig: cint) {.noconv.} =
    writeStackTrace()
    exitnow(1)
  discard signal(SIGSEGV, sigsegvHandler)


proc printHelp() {.noreturn.} =
  let termWidth = max(terminalWidth(), 40)
  let optWidth = min(32, termWidth div 3)
  let helpWidth = termWidth - optWidth - 4

  echo "Usage: [file | url ...] [options]\n"
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

proc parseTwoLengths(val, opt: string): (PackedInt, PackedInt) =
  var vals = val.strip().split(",")
  if vals.len == 1:
    vals.add vals[0]
  if vals.len != 2:
    error &"--{opt} has too many arguments."
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

proc parseResolution(val, opt: string): (int32, int32) =
  let vals = val.strip().split(",")
  if len(vals) != 2:
    error &"'{val}': --{opt} takes two numbers"

  var a, b: int
  discard parseSaturatedNatural(vals[0], a)
  discard parseSaturatedNatural(vals[1], b)
  if a < 1 or b < 1:
    error &"--{opt} must be positive"
  if a > high(int32) or b > high(int32):
    error &"--{opt} got an invalid/too high number"
  return (a.int32, b.int32)

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

when not defined(emscripten):
  proc wantStreams(args: mainArgs): (bool, bool) =
    ## Decide whether the video and/or audio streams are worth downloading,
    ## based on what the output format holds and what --edit needs to analyze.
    let (editV, editA) = editNeeds(args.edit)

    var outV = true
    var outA = true
    if args.preview:
      (outV, outA) = (false, false) # --stats/--preview writes no output file.
    elif args.output notin ["", "-"]:
      let fmt = av_guess_format(nil, cstring(args.output), nil)
      if fmt != nil:
        outV = not args.vn and fmt.video_codec notin [ID_NONE, ID_PNG]
        outA = not args.an and fmt.audio_codec != ID_NONE

    result = (outV or editV, outA or editA)
    if result == (false, false):
      result[1] = true # Always fetch something to read media duration from.

  proc downloadVideo(myInput: string, args: mainArgs): string =
    let (wantVideo, wantAudio) = wantStreams(args)
    conwrite(if wantVideo: "Downloading video..." else: "Downloading audio...")

    let maxHeight = args.resolution[1]
    var downloadFormat = ""
    let vid = (if maxHeight != 0: &"bestvideo[height<={maxHeight}]" else: "bestvideo")
    if wantVideo and wantAudio:
      downloadFormat = vid & "+bestaudio"
    elif wantVideo:
      downloadFormat = vid
    else:
      downloadFormat = "bestaudio"

    var outputFormat: string
    if args.outputFormat != "":
      outputFormat = args.outputFormat
    else:
      let (dir, name, _) = agSplitFile(myInput)
      outputFormat = replace(dir & "/" & name, re"\W+", "-") & ".%(ext)s"

    var cmd: seq[string] = @[]
    if downloadFormat != "":
      cmd.add(@["-f", downloadFormat])

    cmd.add(@["-o", outputFormat, myInput])
    if args.ytDlpExtras != "":
      cmd.add(args.ytDlpExtras.split(" "))

    let ytDlpPath = args.ytDlpLocation
    var location: string
    try:
      location = execProcess(ytDlpPath,
        args = @["--get-filename", "--no-warnings"] & cmd,
        options = {poUsePath}).strip()
    except OSError:
      error "Program `yt-dlp` must be installed and on PATH."

    # Only reuse an existing download if it already has the streams we need.
    var reusable = false
    try:
      let mi = initMediaInfo(location)
      reusable = (not wantAudio or mi.a.len > 0) and
                 (not wantVideo or mi.v.len > 0)
    except IOError:
      discard

    if not reusable:
      try: removeFile(location)
      except OSError: error &"Couldn't remove old download: {location}"

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

proc parseActions(val: string): Actions =
  try:
    return action.parseActions(val)
  except ActionParseError as e:
    error e.msg

proc extractAdds(val: string, selector, setActionRef: int, args: var mainArgs): string =
  ## Pull `add:` tokens out of an action value and record them on `args.adds`;
  ## return the remaining action string (atf-8 effects) for the base layer.
  ## `add` is a virtual action, removed before the rest is parsed. Actions chained
  ## after an `add:` token apply to that overlay layer, not the base; actions
  ## before the first `add:` stay base-layer effects. Each `add:` is one
  ## comma-field (colon-separated). Forms: `add:path` (fit-and-center) or
  ## `add:path:x:y:scale` (placed via a `pos` action). Placement is detected by
  ## the trailing three fields parsing as `x` (int), `y` (int), `scale` (float);
  ## everything before them is the path. This keeps Windows paths working (the
  ## drive-letter colon in `C:\dir\img.png` is part of the path), with or without
  ## placement.
  var keep: seq[string]
  var curAdd = -1   # index in args.adds that trailing actions attach to; -1 = base
  for field in val.split(","):
    let f = field.strip()
    if f.startsWith("add:"):
      let rest = f[4 .. ^1]
      let segs = rest.split(":")
      var spec = AddSpec(selector: selector, setActionRef: setActionRef, scale: 1.0'f32)
      # Need at least one path field plus x:y:scale to be a placement.
      var hasPlacement = false
      if segs.len >= 4:
        try:
          spec.x = int32(parseInt(segs[^3].strip()))
          spec.y = int32(parseInt(segs[^2].strip()))
          spec.scale = parseFloat(segs[^1].strip()).float32
          hasPlacement = true
        except ValueError:
          hasPlacement = false   # trailing fields aren't numeric => part of path
      if hasPlacement:
        spec.hasPos = true
        spec.path = segs[0 ..< segs.len - 3].join(":")
        if spec.scale <= 0.0'f32:
          error "add: scale must be greater than 0.0"
      else:
        spec.path = rest
      if spec.path.len == 0:
        error "add: missing path"
      args.adds.add spec
      curAdd = args.adds.len - 1
    elif curAdd == -1:
      keep.add field
    else:
      # Chain onto the overlay layer of the most recent `add:`.
      if args.adds[curAdd].effects.len > 0:
        args.adds[curAdd].effects.add ","
      args.adds[curAdd].effects.add f
  keep.join(",")

proc parseSpeed(val, opt: string): float64 =
  result = parseNum(val, opt)
  if result <= 0.0 or result > 99999.0:
    result = 99999.0

proc actionFromUserSpeed(val: float64): Actions =
  if val == 1.0: aNil
  elif val <= 0.0 or val >= 99999.0: aCut
  else: newActions([Action(kind: actSpeed, val: val)])

proc parseSpeedRange(val: string): (Actions, PackedInt, PackedInt) =
  let vals = val.strip().split(",")
  if vals.len < 3:
    error "--set-speed has too few arguments"
  if vals.len > 3:
    error "--set-speed has too many arguments"

  let speed = parseSpeed(vals[0], "set-speed")
  let action = actionFromUserSpeed(speed)
  return (action, parseTime(vals[1]), parseTime(vals[2]))

proc parseActionAndRange(val: string, args: var mainArgs): (Actions, PackedInt, PackedInt) =
  let parts = val.strip().split(",")
  if parts.len < 3:
    error "--set-action has too few arguments"
  let actionStr = parts[0 ..< parts.len - 2].join(",")
  let startTime = parseTime(parts[^2])
  let endTime = parseTime(parts[^1])
  # `add` works here too: link it to this set-action's range (its index is the
  # length now, since the caller appends the returned tuple next).
  let rest = extractAdds(actionStr, -1, args.setAction.len, args).strip()
  let acts = (if rest == "": aNil else: parseActions(rest))
  return (acts, startTime, endTime)

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
  for key in cmdLineParams:
    if genCliMacro(key, args, mainOptions):
      continue
    if key in ["-h", "--help"]:
      printHelp()
    if key.startsWith("--"):
      error &"Unknown option: {key}"
    case expecting
    of "":
      args.inputs.add key
    of "edit":
      args.edit = key
    of "export":
      args.`export` = key
    of "output":
      args.output = key
    of "when-silent":
      let rest = extractAdds(key, 0, -1, args)
      if rest.strip() != "":
        args.whenSilent = parseActions(rest)
    of "when-normal":
      let rest = extractAdds(key, 1, -1, args)
      if rest.strip() != "":
        args.whenNormal = parseActions(rest)
    of "silent-speed":
      args.whenSilent = actionFromUserSpeed(parseSpeed(key, expecting))
    of "video-speed":
      args.whenNormal = actionFromUserSpeed(parseSpeed(key, expecting))
    of "add-in":
      block:
        let span = parseTimeRange(key, expecting)
        args.setAction.add (aNil, span[0], span[1])
    of "cut-out":
      block:
        let span = parseTimeRange(key, expecting)
        args.setAction.add (aCut, span[0], span[1])
    of "set-speed":
      args.setAction.add parseSpeedRange(key)
    of "set-action":
      args.setAction.add parseActionAndRange(key, args)
    of "yt-dlp-location":
      args.ytDlpLocation = key
    of "output-format":
      args.outputFormat = key
    of "yt-dlp-extras":
      args.ytDlpExtras = key
    of "scale":
      args.scale = parseNum(key, expecting)
    of "resolution":
      args.resolution = parseResolution(key, expecting)
    of "background":
      try: args.background = some(parseColor(key))
      except ValueError as e: error e.msg
    of "sample-rate":
      args.sampleRate = parseSampleRate(key)
    of "frame-rate":
      args.frameRate = parseFrameRate(key)
    of "vcodec":
      args.videoCodec = key
    of "video-bitrate":
      args.videoBitrate = parseBitrate(key)
    of "crf":
      var val: int
      discard parseSaturatedNatural(key, val)
      if val >= 65: error "constant rate factor is too high: " & key
      args.crf = val.int8
    of "vprofile":
      args.vprofile = key
    of "preset":
      args.preset = key
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
      args.margin = parseTwoLengths(key, expecting)
    of "smooth":
      args.smooth = parseTwoLengths(key, expecting)
    of "key":
      args.licenseKey = key
    of "tempdir":
      tempDir = key
    expecting = ""

  if expecting != "":
    error &"{cmdLineParams[^1]} needs argument."

  if showVersion:
    echo version
    quit(0)

  if args.inputs.len == 0 and isDebug:
    echo "Auto-Editor: ", version
    when defined(windows):
      echo "OS: Windows ", when hostCPU == "amd64": "x86_64" else: hostCPU
    elif defined(emscripten):
      echo (when hostCPU == "wasm32": "OS: wasm32" else: "OS: wasm64")
    else:
      let plat = uname()
      echo "OS: ", plat.sysname, " ", plat.release, " ", plat.machine
    echo listAvailableFilters()
    quit(0)

  # Fail fast on `add` (a CLI-only signal) before any expensive analysis. Using
  # multiple inputs is gated too, but via the multi-source render/export check in
  # conductor.editMedia, which also covers timelines imported from a file/stdin.
  if args.adds.len > 0:
    requireLicense(args, "use the `add` action")

  for i, myInput in args.inputs:
    if myInput.startsWith("http://") or myInput.startsWith("https://"):
      when defined(emscripten):
        error "URL inputs are not supported in the wasm build."
      else:
        args.inputs[i] = downloadVideo(myInput, args)
        args.urlInput = true
    elif agSplitFile(myInput).ext == "":
      if dirExists(myInput):
        error "Input must be a file or a URL, not a directory."
      if myInput.startsWith("-"):
        error &"Option/Input file doesn't exist: {myInput}"
      error &"Input file must have an extension: {myInput}"

  editMedia(args)

when isMainModule:
  main()
