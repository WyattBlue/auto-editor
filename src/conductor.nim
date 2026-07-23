import std/[options, os, sets, sequtils, strformat, strutils, terminal, times]
when not defined(emscripten):
  from std/browsers import openDefaultBrowser
from std/math import round

import ./[av, action, edit, ffmpeg, license, log, media, timeline]
import util/[color, bar, fun, lang, rules, rational]

import imports/[fcp7, json]
import exports/[fcp7, fcp11, json, shotcut, kdenlive, otio]
import render/format
import render/subtitle
import stats


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
    while i < paramsStr.len and paramsStr[i] notin {'=', ','}:
      inc i

    if i >= paramsStr.len or paramsStr[i] == ',':
      error &"--export: expected 'key=value', got '{paramsStr[paramStart ..< i]}'"

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

    if i < paramsStr.len and paramsStr[i] == ',':
      inc i

  return (kind, name, version)

func normalizeRange(span: (PackedInt, PackedInt), tb: float64, arrayLen: int): (int, int) =
  var start = toTb(span[0], tb)
  var stop = toTb(span[1], tb)
  if start < 0:
    start = max(0, arrayLen + start)
  if stop < 0:
    stop = max(0, arrayLen + stop)
  return (start, stop)

proc applyToRange(actionIndex: var seq[int], span: (PackedInt, PackedInt), tb: float64,
  value: int, maxLen: int) =
  let len = if maxLen > 0: maxLen else: actionIndex.len
  let (start, stop) = normalizeRange(span, tb, len)
  if start >= stop:
    error &"Invalid range: start (frame {start}) must come before stop (frame {stop})"
  let cappedStop: int = min(stop, len)
  if cappedStop > actionIndex.len:
    actionIndex.setLen(cappedStop)
  for i in start ..< min(stop, actionIndex.len):
    actionIndex[i] = value

proc setOutput(userOut, `export`, path: string, isUrl = false): (string, string) =
  var dir, name, ext: string
  if userOut == "" or userOut == "-":
    if path == "":
      error "`--output` must be set." # When a timeline file is the input.
    (dir, name, ext) = agSplitFile(path)
    if isUrl:
      ext = "" # Don't inherit the downloaded file's container.
  else:
    (dir, name, ext) = agSplitFile(userOut)

  let root = dir / name

  if ext == "":
    # Use `mkv` as the default, because it can handle any encoder.
    ext = (if isUrl or path == "": ".mkv" else: agSplitFile(path).ext)

  var myExport = `export`
  if myExport == "":
    case ext:
      of ".xml": myExport = "premiere"
      of ".fcpxml": myExport = "final-cut-pro"
      of ".mlt": myExport = "shotcut"
      of ".kdenlive": myExport = "kdenlive"
      of ".otio": myExport = "premiere-otio"
      of ".json", ".v1": myExport = "v1"
      of ".v2": myExport = "v2"
      of ".v3": myExport = "v3"
      else: myExport = "default"

  case myExport:
    of "premiere", "resolve-fcp7": ext = ".xml"
    of "final-cut-pro", "resolve": ext = ".fcpxml"
    of "shotcut": ext = ".mlt"
    of "kdenlive": ext = ".kdenlive"
    of "premiere-otio": ext = ".otio"
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

func setVideoCodec(inCodec: string, src: MediaInfo, rule: Rules, isUrl = false): string =
  if inCodec != "auto":
    return inCodec

  let codecId =
    if isUrl or src.v.len == 0: ID_H264 else: src.v[0].codecId

  if rule.defaultVid == ID_NONE or rule.allowsCodec(codecId):
    return $avcodec_get_name(codecId)
  return $avcodec_get_name(rule.defaultVid)

proc applyAdds(tl: var v3, args: mainArgs, interner: var StringInterner) =
  ## Inject `add:` overlays as new video layers. Each spec overlays its source on
  ## every base-layer (v[0]) clip whose section matches the spec's selector
  ## (0 = silent, 1 = normal), spanning the same timeline range. With
  ## `follow-base` (default), the overlay mirrors the base clip's source offset,
  ## so it follows the base layer's cuts and stays time-synced like a second
  ## camera angle (matching the app); with `follow-base=0` it restarts from frame
  ## 0 each section (logo/gif use). Placement (when given) is carried by a `pos`
  ## action in the overlay clip's effects group.
  if args.adds.len == 0:
    return

  # Audio-only timeline: synthesize a background base video track so the
  # overlays have a canvas — but only if some kept section matches an add's
  # selector. With no "active" portion (e.g. `--edit all` + `-w:1 add`), there
  # is nothing to draw on, so no video stream is produced.
  if tl.v.len == 0:
    if tl.a.len == 0:
      return
    var matches = false
    for spec in args.adds:
      for clip in tl.a[0]:
        if clip.effects.int == spec.selector:
          matches = true
          break
      if matches: break
    if not matches:
      return
    var base: seq[Clip]
    for clip in tl.a[0]:
      base.add Clip(src: nil, start: clip.start, dur: clip.dur,
        offset: clip.offset, effects: clip.effects, stream: 0)
    tl.langs.insert(toLang("und"), 0)  # video lang precedes audio langs
    tl.v.add base

  for spec in args.adds:
    let srcPtr = interner.intern(spec.path)
    # The overlay's effects group: an optional `pos` placement action followed by
    # any actions chained after `add:` (which apply to this layer, not the base).
    var acts: seq[Action]
    if spec.hasPos:
      acts.add Action(kind: actPos, pxKf: spec.xKf, pyKf: spec.yKf,
        pscaleKf: spec.scaleKf)
    if spec.effects.len > 0:
      try:
        for a in parseActions(spec.effects):
          acts.add a
      except ActionParseError as e:
        error e.msg
    let group = (if acts.len > 0: newActions(acts) else: aNil)
    var idx = tl.effects.find(group)
    if idx == -1:
      tl.effects.add group
      idx = tl.effects.len - 1
    let eIdx = uint32(idx)
    var track: seq[Clip]
    for clip in tl.v[0]:
      if clip.effects.int == spec.selector:
        track.add Clip(src: srcPtr, start: clip.start, dur: clip.dur,
          offset: (if spec.followBase: clip.offset else: 0), effects: eIdx,
          stream: 0)
    if track.len == 0:
      continue
    tl.langs.insert(toLang("und"), tl.v.len)  # keep video langs before audio
    tl.v.add track
  tl.updateNumberOfSrc()

proc editMedia*(args: var mainArgs) =
  av_log_set_level(AV_LOG_QUIET)

  var tlV3: v3
  var interner: StringInterner
  var output: string
  var usePath: string = ""
  var mi: MediaInfo
  defer: interner.cleanup()

  if args.progress == BarType.machine and args.output != "-":
    conwrite "Starting"

  let bar = initBar(args.progress)

  if args.inputs.len == 0 and not stdin.isatty():
    let stdinContent = readAll(stdin)
    tlV3 = readJson(stdinContent, interner)
    tlV3.applyArgs(args)
  else:
    if args.inputs.len == 0:
      error "You need to give auto-editor an input file."
    let input = args.inputs[0]
    let inputExt = agSplitFile(input).ext

    if inputExt in [".v1", ".v2", ".v3", ".json"]:
      tlV3 = readJson(readFile(input), interner)
      tlV3.applyArgs(args)
    elif inputExt == ".xml":
      tlV3 = fcp7ReadXml(input, interner)
      tlV3.applyArgs(args)
      usePath = input
    else:
      usePath = input
      var tb = AVRational(num: 30, den: 1)
      if args.frameRate != AVRational(num: 0, den: 0):
        tb = args.frameRate

      let bg = args.background.get(RGBColor(red: 0, green: 0, blue: 0))
      var tlInitialized = false

      for i in 0 ..< args.inputs.len:
        var container = (try: av.open(args.inputs[i]) except IOError as e: error e.msg)
        defer: container.close()

        if i == 0 and args.frameRate == AVRational(num: 0, den: 0):
          if container.video.len > 0:
            let avgFr = container.video[0].avg_frame_rate
            if avgFr.isValid:
              tb = makeSaneTimebase(avgFr)

        var labels = interpretEdit(args, container, args.inputs[i], tb, bar)
        let tbf = tb.float64
        let startMargin = toTb(args.margin[0], tbf)
        let endMargin = toTb(args.margin[1], tbf)
        let mincut = toTb(args.smooth[0], tbf)
        let minclip = toTb(args.smooth[1], tbf)

        # Margin and smoothing act on the binary keep/cut boundary (active = any
        # non-silent label). Run them on that mask, then fold the result back into
        # the labels: where margin/mincut turned silence active, call it label 1
        # (normal); where minclip cut a short active clip, set it silent (0). With
        # only labels 0/1 present this reproduces the previous behavior exactly.
        var active = newSeq[bool](labels.len)
        for i in 0 ..< labels.len:
          active[i] = labels[i] != 0'u8

        mutMargin(active, startMargin, endMargin)
        smoothing(active, mincut, minclip)

        for i in 0 ..< labels.len:
          if not active[i]:
            labels[i] = 0'u8
          elif labels[i] == 0'u8:
            labels[i] = 1'u8

        # actionMap is indexed by label: 0 = silent, 1 = normal, >= 2 come from
        # --when:N (defaulting to aNil = keep). --set-action ranges append unique
        # indices beyond maxLabel below, so they never collide with a label.
        var maxLabel = 1
        for le in args.labeledEdits:
          maxLabel = max(maxLabel, le.label)
        for lw in args.labeledWhens:
          maxLabel = max(maxLabel, lw.label)
        var actionMap = newSeq[Actions](maxLabel + 1)
        actionMap[0] = args.whenInactive
        actionMap[1] = args.whenActive
        for lw in args.labeledWhens:
          actionMap[lw.label] = lw.action
        var actionIndex: seq[int] = labels.map(proc(x: uint8): int = int(x))

        var conLen = 0
        proc getConLen(): int =
          if conLen == 0: conLen = int(round((mediaLength(container) * tb).float64))
          conLen

        for sIdx in 0 ..< args.setAction.len:
          let actionRange = args.setAction[sIdx]
          let span = (actionRange[1], actionRange[2])
          # A set-action range is an explicit override, conceptually distinct
          # from the `-w:0`/`-w:1` (silent/normal) sections. Give it a unique
          # effects index (never deduping into indices 0/1) so an `add` selector
          # matches only what it should: `-w:1 add` overlays genuine active
          # sections, not a `--set-action`/`--add-in` range, and a set-action's
          # own `add` matches just that range.
          actionMap.add actionRange[0]
          let aIdx = actionMap.len - 1
          applyToRange(actionIndex, span, tbf, aIdx, getConLen())
          if i == 0:
            for a in args.adds.mitems:
              if a.setActionRef == sIdx:
                a.selector = aIdx

        let inputMi = initMediaInfo(container.formatContext, args.inputs[i])

        if not tlInitialized:
          mi = inputMi
          tlV3 = initLinearTimeline(interner.intern(args.inputs[i]), tb, bg, mi, actionMap, actionIndex)
          tlInitialized = true
        else:
          appendLinearTimeline(tlV3, interner.intern(args.inputs[i]), inputMi, actionIndex)

      applyAdds(tlV3, args, interner)
      tlV3.applyArgs(args)
      if args.transition.getNumber > 0:
        tlV3.addDissolveTransitions(
          toTb(args.transition, tlV3.tb.float).int64,
          toTb(args.transitionMinCut, tlV3.tb.float).int64)

  var exportKind, tlName, fcpVersion: string
  if args.`export` == "":
    (output, exportKind) = setOutput(args.output, "", usePath, args.urlInput)
    tlName = "Auto-Editor Media Group"
    fcpVersion = "11"
  else:
    (exportKind, tlName, fcpVersion) = parseExportString(args.`export`)
    (output, _) = setOutput(args.output, exportKind, usePath, args.urlInput)

  if args.preview:
    preview(tlV3)
    return

  # Timeline/project exports that draw from more than one source remain a paid
  # feature. Rendered media is handled in makeMedia, where an unlicensed render
  # can continue at SD resolution. This also covers timelines imported from a
  # file/stdin, which never pass through the CLI-level checks.
  if tlV3.numberOfSrc > 1 and
      exportKind notin ["default", "clip-sequence"]:
    requireLicense(args, "export a timeline with multiple sources")

  case exportKind:
  of "v1", "v2", "v3":
    exportJsonTl(tlV3, exportKind, output)
    return
  of "premiere":
    fcp7WriteXml(tlName, output, false, tlV3)
    return
  of "resolve-fcp7":
    # Resolve reads only a file's first audio stream from FCP7 XML
    # (sourcetrack/trackindex is not honored across streams), so split
    # multi-track audio into per-stream wavs like the fcpxml resolve export.
    tlV3.setStreamTo0(interner)
    fcp7WriteXml(tlName, output, true, tlV3)
    return
  of "final-cut-pro":
    fcp11WriteXml(tlName, fcpVersion, output, false, tlV3)
    return
  of "resolve":
    tlV3.setStreamTo0(interner)
    fcp11WriteXml(tlName, fcpVersion, output, true, tlV3)
    return
  of "shotcut":
    shotcutWriteMlt(output, tlV3)
    return
  of "kdenlive":
    kdenliveWrite(output, tlV3)
    return
  of "premiere-otio":
    otioWrite(tlName, output, tlV3)
    return
  of "default", "clip-sequence":
    discard
  else:
    error &"Unknown export format: {exportKind}"

  if output == "-":
    error "Exporting media files to stdout is not supported."

  let rule = initRules(output)
  args.videoCodec = setVideoCodec(args.videoCodec, mi, rule, args.urlInput)

  if args.`export` == "clip-sequence":
    if not tlV3.isLinear:
      error "Timeline too complex to use clip-sequence export"

    func appendFilename(path, val: string): string =
      let (dir, name, ext) = agSplitFile(path)
      return (dir / name) & val & ext

    var clips2: seq[Clip2] = @[]
    for clip in tlV3.clips2:
      if not tlV3.effects[clip.effect].isCut:
        clips2.add(clip)

    let unique = tlV3.uniqueSources()
    if unique.len > 1:
      error "clip-sequence export only supports one input source"
    var src: ptr string
    for u in unique:
      src = u
      break
    if src == nil:
      error "Trying to render an empty timeline"
    var cache = newMediaCache()
    defer: cache.close()

    let mi = initMediaInfo(cache.getContainer(src).formatContext, src[])

    for clipNum, clip2 in clips2.pairs:
      var myTimeline = toNonLinear2(src, tlV3.tb, mi, @[clip2], tlV3.effects)
      applyArgs(myTimeline, args)
      makeMedia(args, myTimeline, appendFilename(output, &"-{clipNum}"), rule, bar, cache)
  else:
    makeMedia(args, tlV3, output, rule, bar)

  # Retiming embedded subtitles is handled by makeMedia. Also retime every
  # subtitle-only sibling of each original media input into its own sidecar.
  for input in args.inputs:
    let (inputDir, inputName, _) = agSplitFile(input)
    var inputLayer: seq[Clip]
    let baseLayer =
      if tlV3.v.len > 0: tlV3.v[0]
      elif tlV3.a.len > 0: tlV3.a[0]
      else: @[]
    for clip in baseLayer:
      if clip.src != nil and clip.src[] == input:
        inputLayer.add clip

    if inputLayer.len == 0:
      continue

    for sibling in walkFiles((inputDir / inputName) & ".*"):
      if sibling == input:
        continue
      var sidecar: InputContainer
      try:
        sidecar = av.open(sibling)
      except IOError:
        continue
      let isSubtitleOnly = sidecar.subtitle.len > 0 and
        sidecar.video.len == 0 and sidecar.audio.len == 0
      sidecar.close()
      if not isSubtitleOnly:
        continue

      let (subDir, subName, subExt) = agSplitFile(sibling)
      makeAlteredSubtitle(sibling, (subDir / subName) & "_ALTERED" & subExt,
        inputLayer, tlV3.tb)

  bar.destroy()

  let seconds = round(epochTime() - start, 2)
  echo &"Finished. took {seconds} seconds ({toTimecode(seconds, Code.display)})"

  if args.noOpen:
    discard
  elif args.open:
    when not defined(emscripten):
      openDefaultBrowser(output)
