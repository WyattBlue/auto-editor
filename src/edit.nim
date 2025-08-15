import std/[os, options, times, terminal, browsers]
import std/[strutils, strformat]
import std/sequtils
import std/[sets, tables]
import std/random
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
      else: error &"Unknown paramter: {paramName}"

    # Skip comma
    if i < paramsStr.len and paramsStr[i] == ',':
      inc i

  return (kind, name, version)


# Turn long silent/loud array to formatted chunk list.
# Example: [1, 1, 1, 2, 2], {1: 1.0, 2: 1.5} => [(0, 3, 1.0), (3, 5, 1.5)]
proc chunkify(arr: seq[int], smap: Table[int, float64]): seq[(int64, int64, float64)] =
  if arr.len == 0:
    return @[]

  var start: int64 = 0
  var j: int64 = 1
  while j < arr.len:
    if arr[j] != arr[j - 1]:
      result.add (start, j, smap[arr[j - 1]])
      start = j
    inc j
  result.add (start, arr.len.int64, smap[arr[j - 1]])

func normalizeRange(span: (PackedInt, PackedInt), tb: float64, arrayLen: int): (int64, int64) =
  var start = toTb(span[0], tb)
  var stop = toTb(span[1], tb)
  if start < 0:
    start = max(0, arrayLen + start)
  if stop < 0:
    stop = max(0, arrayLen + stop)
  return (start, stop)

proc applyToRange(speedIndex: var seq[int], span: (PackedInt, PackedInt), tb: float64, value: int) =
  let (start, stop) = normalizeRange(span, tb, speedIndex.len)
  for i in start ..< min(stop, speedIndex.len):
    speedIndex[i] = value

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
      codec = "aac"
    else:
      codec = src.a[0].codec
      let avCodec = initCodec(codec)
      if avCodec == nil or avCodec.sample_fmts == nil:
        codec = "aac"
    if codec notin rule.acodecs.mapIt($it.name) and rule.defaultAud != "none":
      codec = rule.defaultAud

  return codec

proc setVideoCodec(codec: var string, ext: string, src: MediaInfo, rule: Rules): string =
  if codec == "auto":
    codec = (if src.v.len == 0: "h264" else: src.v[0].codec)
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

    if inputExt in [".v1", ".v3", ".json"]:
      tlV3 = readJson(readFile(args.input), interner)
      applyArgs(tlV3, args)
    else:
      # Make `timeline` from media file
      var container = av.open(args.input)
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

      var chunks: seq[(int64, int64, float64)] = @[]

      var speedIndex = hasLoud.map(proc(x: bool): int = int(x))
      var speedMap = @[args.silentSpeed, args.videoSpeed]
      var speedHash = {0: args.silentSpeed, 1: args.videoSpeed}.toTable

      proc getSpeedIndex(speed: float64): int =
        if speed in speedMap:
          return speedMap.find(speed)
        speedMap.add(speed)
        speedHash[speedMap.len - 1] = speed
        return speedMap.len - 1

      for span in args.cutOut:
        applyToRange(speedIndex, span, tb.float64, getSpeedIndex(99999.0))

      for span in args.addIn:
        applyToRange(speedIndex, span, tb.float64, 1)

      for speedRange in args.setSpeed:
        let speed = speedRange[0]
        let span = (speedRange[1], speedRange[2])
        applyToRange(speedIndex, span, tb.float64, getSpeedIndex(speed))

      chunks = chunkify(speedIndex, speedHash)
      mi = initMediaInfo(container.formatContext, args.input)
      tlV3 = toNonLinear(addr args.input, tb, args.background, mi, chunks)
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
  of "v1", "v3":
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
    if not isSome(tlV3.chunks):
      error "Timeline too complex to use clip-sequence export"

    let chunks: seq[(int64, int64, float64)] = tlV3.chunks.unsafeGet()

    proc padChunk(chunk: (int64, int64, float64), total: int64): seq[(int64, int64, float64)] =
      let start = (if chunk[0] == 0'i64: @[] else: @[(0'i64, chunk[0], 99999.0)])
      let `end` = (if chunk[1] == total: @[] else: @[(chunk[1], total, 99999.0)])
      return start & @[chunk] & `end`

    func appendFilename(path: string, val: string): string =
      let (dir, name, ext) = splitFile(path)
      return (dir / name) & val & ext

    const black = RGBColor(red: 0, green: 0, blue: 0)
    let totalFrames: int64 = chunks[^1][1] - 1
    var clipNum = 0

    let unique = tlV3.uniqueSources()
    var src: ptr string
    for u in unique:
      src = u
      break
    if src == nil:
      error "Trying to render an empty timeline"
    let mi = initMediaInfo(src[])

    for chunk in chunks:
      if chunk[2] <= 0 or chunk[2] >= 99999:
        continue

      let paddedChunks = padChunk(chunk, totalFrames)
      var myTimeline = toNonLinear(src, tlV3.tb, black, mi, paddedChunks)
      applyArgs(myTimeline, args)
      makeMedia(args, myTimeline, appendFilename(output, &"-{clipNum}"), rule, bar)
      clipNum += 1
  else:
    makeMedia(args, tlV3, output, rule, bar)

  stopTimer()

  if not args.noOpen and exportKind == "default":
    openDefaultBrowser(output)
  closeTempDir()
