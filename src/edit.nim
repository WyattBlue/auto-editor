import std/[os, options, times, terminal, browsers]
import std/[strutils, strformat]
import std/sequtils
import std/[random, sets]
from std/math import round

import av
import log
import media
import ffmpeg
import timeline
import palet/edit
import util/[color, bar, fun, rules]

import imports/json
import exports/[fcp7, fcp11, json, shotcut, kdenlive]
import preview
import render/format

proc stopTimer() =
  let secondLen: float = round(epochTime() - start, 2)
  let minuteLen = toTimecode(secondLen, display)

  echo &"Finished. took {secondLen} seconds ({minuteLen})"


proc parseExportString*(exportStr: string): (string, string, string) =
  var kind = exportStr
  var name = "Auto-Editor Media Group"
  var version = "11"

  let colonPos = exportStr.find(':')
  if colonPos == -1:
    return (kind, name, version)

  kind = exportStr[0..colonPos-1]
  let paramsStr = exportStr[colonPos+1..^1]

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
      break

    let paramName = paramsStr[paramStart..i-1]
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
      of "name": name = value
      of "version": version = value
      else: error &"Unknown parameter: {paramName}"

    # Skip comma
    if i < paramsStr.len and paramsStr[i] == ',':
      inc i

  return (kind, name, version)

func normalizeRange(span: (PackedInt, PackedInt), tb: float64, arrayLen: int): (int64, int64) =
  var start = toTb(span[0], tb)
  var stop = toTb(span[1], tb)
  if start < 0:
    start = max(0, arrayLen + start)
  if stop < 0:
    stop = max(0, arrayLen + stop)
  return (start, stop)

proc applyToRange(actionIndex: var seq[int], span: (PackedInt, PackedInt), tb: float64, value: int) =
  let (start, stop) = normalizeRange(span, tb, actionIndex.len)
  for i in start ..< min(stop, actionIndex.len):
    actionIndex[i] = value

proc setOutput(userOut, `export`, path: string): (string, string) =
  var dir, name, ext: string
  if userOut == "" or userOut == "-":
    if path == "":
      error "`--output` must be set." # When a timeline file is the input.
    (dir, name, ext) = splitFile(path)
  else:
    (dir, name, ext) = splitFile(userOut)

  let root = dir / name

  if ext == "":
    # Use `mp4` as the default, because it is most compatible.
    ext = (if path == "": ".mp4" else: splitFile(path).ext)

  var myExport = `export` # Create mutable copy
  if myExport == "":
    case ext:
      of ".xml": myExport = "premiere"
      of ".fcpxml": myExport = "final-cut-pro"
      of ".mlt": myExport = "shotcut"
      of ".kdenlive": myExport = "kdenlive"
      of ".json", ".v1": myExport = "v1"
      of ".v2": myExport = "v2"
      of ".v3": myExport = "v3"
      else: myExport = "default"

  case myExport:
    of "premiere", "resolve-fcp7": ext = ".xml"
    of "final-cut-pro", "resolve": ext = ".fcpxml"
    of "shotcut": ext = ".mlt"
    of "kdenlive": ext = ".kdenlive"
    of "v1":
      if ext != ".json":
        ext = ".v1"
    of "v2": ext = ".v2"
    of "v3": ext = ".v3"
    else: discard

  if userOut == "-":
    return ("-", myExport)
  if userOut == "":
    return (&"{root}_ALTERED{ext}", myExport)

  return (&"{root}{ext}", myExport)


proc setAudioCodec(codec: var string, ext: string, src: MediaInfo, rule: Rules): string =
  if codec == "auto":
    if src.a.len == 0:
      codec = rule.defaultAud
    else:
      codec = $avcodec_get_name(src.a[0].codecId)
      let avCodec = initCodec(codec)
      if avCodec == nil or avCodec.sample_fmts == nil:
        codec = "aac"

      # For PCM-based containers (WAV, etc.), prefer PCM even if other codecs are supported
      if ext in [".wav", ".aiff", ".au"] and rule.defaultAud.startsWith("pcm_"):
        codec = rule.defaultAud
      elif codec notin rule.acodecs.mapIt($it.name):
        if rule.defaultAud != "none":
          codec = rule.defaultAud
        else:
          codec = "aac"

  if codec != "none" and codec notin rule.acodecs.mapIt($it.name):
    let avCodec = initCodec(codec)
    if avCodec == nil:
      error &"Unknown encoder: {codec}"

    # Normalize encoder names
    if not rule.acodecs.anyIt(it.id == avCodec.id):
      error &"'{avCodec.name}' audio encoder is not supported in the '{ext}' container"

  return codec

proc setVideoCodec(codec: var string, ext: string, src: MediaInfo, rule: Rules): string =
  if codec == "auto":
    codec = (if src.v.len == 0: "h264" else: $avcodec_get_name(src.v[0].codecId))
    if codec notin rule.vcodecs.mapIt($it.name) and rule.defaultVid != "none":
      return rule.default_vid
    return codec

  if codec notin rule.vcodecs.mapIt($it.name):
    let avCodec = initCodec(codec)
    if avCodec == nil:
      error &"Unknown encoder: {codec}"

    # Normalize encoder names
    if not rule.vcodecs.anyIt(it.id == avCodec.id):
      error &"'{avCodec.name}' video encoder is not supported in the '{ext}' container"

  return codec

proc editMedia*(args: var mainArgs) =
  av_log_set_level(AV_LOG_QUIET)

  var tlV3: v3
  var interner = newStringInterner()
  var output: string
  var usePath: string = ""
  var mi: MediaInfo
  defer: interner.cleanup()

  if args.progress == BarType.machine and args.output != "-":
    conwrite("Starting")

  let bar = initBar(args.progress)

  if args.input == "" and not stdin.isatty():
    let stdinContent = readAll(stdin)
    tlV3 = readJson(stdinContent, interner)
    applyArgs(tlV3, args)
  else:
    if args.input == "":
      error "You need to give auto-editor an input file."
    let inputExt = splitFile(args.input).ext

    if inputExt in [".v1", ".v2", ".v3", ".json"]:
      tlV3 = readJson(readFile(args.input), interner)
      applyArgs(tlV3, args)
    else:
      # Make `timeline` from media file
      var container = (
        try: av.open(args.input) except IOError: error &"Input file doesn't exist: {args.input}"
      )
      defer: container.close()

      usePath = args.input
      var tb = AVRational(30)
      if args.frameRate != AVRational(num: 0, den: 0):
        tb = args.frameRate
      elif container.video.len > 0:
        tb = makeSaneTimebase(container.video[0].avg_frame_rate)

      var hasLoud = interpretEdit(args, container, tb, bar)
      let startMargin = toTb(args.margin[0], tb.float64)
      let endMargin = toTb(args.margin[1], tb.float64)
      mutMargin(hasLoud, startMargin, endMargin)

      var actionMap: seq[seq[Action]] = @[]
      actionMap.add(args.whenSilent)
      actionMap.add(args.whenNormal)
      var actionIndex: seq[int] = hasLoud.map(proc(x: bool): int = int(x))

      proc getActionIndex(actions: seq[Action]): int =
        let index = actionMap.find(actions)
        if index == -1:
          actionMap.add(actions)
          return actionMap.len - 1
        else:
          return index

      let cut = @[Action(kind: actCut)]
      let myNil: seq[Action] = @[]

      for span in args.cutOut:
        applyToRange(actionIndex, span, tb.float64, getActionIndex(cut))

      for span in args.addIn:
        applyToRange(actionIndex, span, tb.float64, getActionIndex(myNil))

      for speedRange in args.setSpeed:
        let speed = speedRange[0]
        let span = (speedRange[1], speedRange[2])
        let action = (if speed == 1.0: myNil else: @[Action(kind: actSpeed, val: speed)])
        applyToRange(actionIndex, span, tb.float64, getActionIndex(action))

      let bg = args.background
      mi = initMediaInfo(container.formatContext, args.input)
      tlV3 = initLinearTimeline(addr args.input, tb, bg, mi, actionMap, actionIndex)
      applyArgs(tlV3, args)

  var exportKind, tlName, fcpVersion: string
  if args.`export` == "":
    (output, exportKind) = setOutput(args.output, "", usePath)
    tlName = "Auto-Editor Media Group"
    fcpVersion = "11"
  else:
    (exportKind, tlName, fcpVersion) = parseExportString(args.`export`)
    (output, _) = setOutput(args.output, exportKind, usePath)

  if args.preview:
    preview(tlV3)
    return

  case exportKind:
  of "v1", "v2", "v3":
    exportJsonTl(tlV3, exportKind, output)
    return
  of "premiere":
    fcp7_write_xml(tlName, output, false, tlV3)
    return
  of "resolve-fcp7":
    fcp7_write_xml(tlName, output, true, tlV3)
    return
  of "final-cut-pro":
    fcp11_write_xml(tlName, fcpVersion, output, false, tlV3)
    return
  of "resolve":
    tlV3.setStreamTo0(interner)
    fcp11_write_xml(tlName, fcpVersion, output, true, tlV3)
    return
  of "shotcut":
    shotcut_write_mlt(output, tlV3)
    return
  of "kdenlive":
    kdenliveWrite(output, tlV3)
    return
  of "default", "clip-sequence":
    discard
  else:
    error &"Unknown export format: {exportKind}"

  if output == "-":
    error "Exporting media files to stdout is not supported."

  let (_, _, outExt) = splitFile(output)
  let rule = initRules(outExt.toLowerAscii)
  args.videoCodec = setVideoCodec(args.videoCodec, outExt, mi, rule)
  args.audioCodec = setAudioCodec(args.audioCodec, outExt, mi, rule)

  proc createAlphanumTempDir(length: int = 8): string =
    const chars = "abcdefghijklmnopqrstuvwxyz0123456789"
    const prefix = "tmp"
    var suffix = ""
    for i in 0..<length:
      suffix.add(chars[rand(chars.len - 1)])

    let dirName = prefix & suffix
    let fullPath = getTempDir() / dirName
    createDir(fullPath)
    return fullPath

  if tempDir == "":
    randomize()
    tempDir = createAlphanumTempDir()
  else:
    if fileExists(tempDir):
      error "Temp directory cannot be an already existing file."
    if dirExists(tempDir):
      discard
    else:
      createDir(tempDir)

  debug &"Temp Directory: {tempDir}"

  if args.`export` == "clip-sequence":
    if not isSome(tlV3.clips2):
      error "Timeline too complex to use clip-sequence export"

    func appendFilename(path, val: string): string =
      let (dir, name, ext) = splitFile(path)
      return (dir / name) & val & ext

    let allClips2: seq[Clip2] = tlV3.clips2.unsafeGet()
    var clips2: seq[Clip2] = @[]
    for clip in allClips2:
      let effectGroup = tlV3.effects[clip.effect]
      var isCut = false
      for effect in effectGroup:
        if effect.kind == actCut:
          isCut = true
          break
      if not isCut:
        clips2.add(clip)

    let unique = tlV3.uniqueSources()
    var src: ptr string
    for u in unique:
      src = u
      break
    if src == nil:
      error "Trying to render an empty timeline"
    let mi = initMediaInfo(src[])
    const black = RGBColor(red: 0, green: 0, blue: 0)

    for clipNum, clip2 in clips2.pairs:
      var myTimeline = toNonLinear2(src, tlV3.tb, black, mi, @[clip2], tlV3.effects)
      applyArgs(myTimeline, args)
      makeMedia(args, myTimeline, appendFilename(output, &"-{clipNum}"), rule, bar)
  else:
    makeMedia(args, tlV3, output, rule, bar)

  bar.destroy()
  stopTimer()

  if not args.noOpen and exportKind == "default":
    openDefaultBrowser(output)
  closeTempDir()
