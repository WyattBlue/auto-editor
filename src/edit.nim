import std/[math, options, os, sequtils, strformat, strutils]
import ./[av, editexpr, editlexer, editparse, ffmpeg, log]
import ./analyze/[audio, blackdetect, motion, subtitle]
import ./lib/[audioutil, dnorm16]
import ./util/[bar, fun, rational]

import ./vendor/tinyre/tinyre

type
  NormSymbol = enum
    nsUnknown, nsEbu, nsPeak

  EditSymbol = enum
    esUnknown, esZero, esOne, esOr, esAnd, esXor, esNot, esAudio, esMotion,
    esBlackdetect, esSubtitle, esRegex, esWord, esNone, esAll

func normSymbol(expr: Expr, text: string): NormSymbol =
  if expr.symbolEquals(text, "ebu"): nsEbu
  elif expr.symbolEquals(text, "peak"): nsPeak
  else: nsUnknown

func editSymbol(expr: Expr, text: string): EditSymbol =
  if expr.numberEquals(text, "0"): esZero
  elif expr.numberEquals(text, "1"): esOne
  elif expr.symbolEquals(text, "or"): esOr
  elif expr.symbolEquals(text, "and"): esAnd
  elif expr.symbolEquals(text, "xor"): esXor
  elif expr.symbolEquals(text, "not"): esNot
  elif expr.symbolEquals(text, "audio"): esAudio
  elif expr.symbolEquals(text, "motion"): esMotion
  elif expr.symbolEquals(text, "blackdetect"): esBlackdetect
  elif expr.symbolEquals(text, "subtitle"): esSubtitle
  elif expr.symbolEquals(text, "regex"): esRegex
  elif expr.symbolEquals(text, "word"): esWord
  elif expr.symbolEquals(text, "none"): esNone
  elif expr.symbolEquals(text, "all"): esAll
  else: esUnknown

func `or`(a, b: seq[bool]): seq[bool] =
  result = newSeq[bool](max(a.len, b.len))
  for i in 0 ..< result.len:
    let aVal = if i < a.len: a[i] else: false
    let bVal = if i < b.len: b[i] else: false
    result[i] = aVal or bVal

func `and`(a, b: seq[bool]): seq[bool] =
  result = newSeq[bool](min(a.len, b.len))
  for i in 0 ..< result.len:
    result[i] = a[i] and b[i]

func `xor`(a, b: seq[bool]): seq[bool] =
  result = newSeq[bool](max(a.len, b.len))
  for i in 0 ..< result.len:
    let aVal = if i < a.len: a[i] else: false
    let bVal = if i < b.len: b[i] else: false
    result[i] = aVal xor bVal

func `not`(a: seq[bool]): seq[bool] =
  result = newSeq[bool](a.len)
  for i in 0 ..< a.len:
    result[i] = not a[i]

proc orWithThreshold(result: var seq[bool], levels: seq[Unorm16], t: Unorm16) =
  if result.len == 0:
    result = newSeq[bool](levels.len)
    for i in 0 ..< levels.len:
      result[i] = levels[i] >= t
  else:
    let n = min(result.len, levels.len)
    for i in 0 ..< n:
      result[i] = result[i] or (levels[i] >= t)
    for i in result.len ..< levels.len:
      result.add levels[i] >= t

proc parseFloatInRange(val: string, min, max: float32): float32 {.raises: [AutoEditorError].} =
  try:
    result = parseFloat(val)
  except ValueError:
    error &"Invalid number: {val}"
  # `not (>= and <=)` instead of `< or >` so NaN is rejected too; it would
  # otherwise flow into unchecked float->int conversions downstream.
  if not (result >= min and result <= max):
    error &"value {result} is outside range [{min}, {max}]"

proc parseNat(val: string): int32 =
  let n = (
    try: parseInt(val)
    except ValueError: error &"Invalid natural: {val}"
  )
  if n < 0 or n > high(int32).int: error &"Invalid natural: {val}"
  result = int32(n)

proc parseStream(val: string): int16 =
  if val == "all":
    return -1
  let n = (try: parseInt(val) except ValueError: error &"Invalid stream: {val}")
  if n > 1000 or n < 0: error &"Invalid stream: {val}"
  result = int16(n)

proc parseBool(val: string): bool =
  if val == "#t" or val == "true":
    return true
  if val == "#f" or val == "false":
    return false
  error "Invalid boolean (expected true or false): " & val

proc checkedArgs(expressions: openArray[Expr], text: string,
    argOrder: openArray[string]): seq[BoundEditArg] =
  try:
    bindEditArgs(expressions, text, argOrder)
  except ValueError as e:
    error e.msg

proc checkedMethodArgs(name: string, expressions: openArray[Expr],
    text: string): seq[BoundEditArg] =
  try:
    bindEditMethodArgs(name, expressions, text)
  except ValueError as e:
    error e.msg


proc parseNorm*(norm: string): Norm =
  if norm == "#f" or norm == "false":
    return Norm(kind: nkNull)

  var lexer = initLexer("--audio-normalize", norm)
  var parser: Parser
  let expressions: seq[Expr] = (
    try:
      parser = initParser(lexer) # lexes the first token, so it can raise too
      parser.parse()
    except ValueError as e: error &"--audio-normalize: {e.msg}"
  )
  if expressions.len == 0:
    error "--audio-normalize: expression is empty"
  let expr = expressions[^1]
  if expr.kind != ExprList:
    error "Should never happen"

  proc normEval(expr: Expr, text: string): Norm =
    if expr.kind != ExprList or expr.elements.len == 0:
      error "Bad kind"

    let node = expr.elements
    if node[0].kind == ExprList and node.len == 1:
      return normEval(node[0], text)

    if node[0].kind == ExprSym:
      case node[0].normSymbol(text)
      of nsEbu:
        let argOrder = @["i", "lra", "tp", "gain"]
        var
          i: float32 = -24.0
          lra: float32 = 7.0
          tp: float32 = -2.0
          gain: float32 = 0.0
        for (argPos, val) in checkedArgs(node[1 ..< node.len], text, argOrder):
          case argPos:
          of 0: i = parseFloatInRange(val, -70.0, 5.0)
          of 1: lra = parseFloatInRange(val, 1.0, 50.0)
          of 2: tp = parseFloatInRange(val, -9.0, 0.0)
          of 3: gain = parseFloatInRange(val, -99.0, 99.0)
          else: error "Too many args"

        return Norm(kind: nkEbu, i: i, lra: lra, tp: tp, gain: gain)
      of nsPeak:
        let argOrder = @["t"]
        var t: float32 = -8.0
        for (argPos, val) in checkedArgs(node[1 ..< node.len], text, argOrder):
          case argPos:
          of 0: t = parseFloatInRange(val, -99.0, 0.0)
          else: error "Too many args"

        return Norm(kind: nkPeak, t: t)
      of nsUnknown:
        error &"Unknown audio norm: {text[node[0].`from` ..< node[0].to]}"
    else:
      error "Invalid audio norm expression."

  return normEval(expr, parser.lexer.sourceText)

proc findExternSubs(input: string): Option[InputContainer] {.raises: [].} =
  try:
    some(av.open(input.changeFileExt("srt")))
  except IOError:
    try:
      some(av.open(input.changeFileExt("ass")))
    except IOError:
      none(InputContainer)

proc parseEdit*(source: string, filename = "--edit"): EditExpr =
  ## The CLI's `--edit` syntax as an EditExpr. Every syntax and argument error
  ## is raised here; only what depends on the file (a stream or channel it
  ## doesn't have) waits for `interpretEdit`.
  proc toExpr(expr: Expr, text: string): EditExpr =
    if expr.kind in {ExprSym, ExprNum}:
      # A bare method inside an operator, e.g. `(or audio motion)`: invoke it
      # with its default arguments.
      return toExpr(Expr(kind: ExprList, elements: @[expr],
        `from`: expr.`from`, to: expr.to), text)
    if expr.kind != ExprList or expr.elements.len == 0:
      error "Bad kind"

    let node = expr.elements
    if node[0].kind == ExprList and node.len == 1:
      return toExpr(node[0], text)

    if node[0].kind == ExprNum:
      case node[0].editSymbol(text)
      of esZero: return edit(allMethod())
      of esOne: return edit(noneMethod())
      else: error "We only support 0 or 1 right now."
    if node[0].kind != ExprSym:
      error &"`--edit` expects a valid expression: {node[0].sourceText(text)}"

    let editSymbol = node[0].editSymbol(text)
    let operandCount = node.len - 1
    if editSymbol == esNot and operandCount != 1:
      error &"--edit: 'not' expects exactly 1 operand; got {operandCount}"
    if editSymbol in {esOr, esAnd, esXor} and operandCount < 1:
      let operator = node[0].sourceText(text)
      error &"--edit: '{operator}' expects at least 1 operand; got {operandCount}"

    case editSymbol
    of esOr, esAnd, esXor, esNot:
      result = EditExpr(op: (case editSymbol
        of esOr: eoOr
        of esAnd: eoAnd
        of esXor: eoXor
        else: eoNot))
      for i in 1 ..< node.len:
        result.operands.add toExpr(node[i], text)
    of esAudio:
      var m = audioMethod()
      for (argPos, val) in checkedMethodArgs("audio", node[1 ..< node.len], text):
        case argPos:
        of 0: m.threshold = parseThres(val)
        of 1: m.stream = parseStream(val)
        of 2: m.channel = val
        else: error "Too many args"
      if m.channel != "all" and audioChannelCode(m.channel) == "":
        error &"audio: unknown channel '{m.channel}'."
      return edit(m)
    of esMotion:
      var m = motionMethod()
      for (argPos, val) in checkedMethodArgs("motion", node[1 ..< node.len], text):
        case argPos:
        of 0: m.threshold = parseThres(val)
        of 1: m.stream = parseStream(val)
        of 2: m.width = parseNat(val)
        of 3: m.blur = parseNat(val)
        of 4: m.region.x = parseFloatInRange(val, 0.0, 1.0)
        of 5: m.region.y = parseFloatInRange(val, 0.0, 1.0)
        of 6: m.region.w = parseFloatInRange(val, 0.0, 1.0)
        of 7: m.region.h = parseFloatInRange(val, 0.0, 1.0)
        else: error "Too many args"
      if m.stream < 0:
        error "motion: 'all' stream is not supported"
      return edit(m)
    of esBlackdetect:
      var m = blackdetectMethod()
      for (argPos, val) in checkedMethodArgs("blackdetect", node[1 ..< node.len], text):
        case argPos:
        of 0: m.threshold = parseThres(val)
        of 1: m.stream = parseStream(val)
        of 2: m.pixelBlack = parseFloatInRange(val, 0.0, 1.0)
        else: error "Too many args"
      if m.stream < 0:
        error "blackdetect: 'all' stream is not supported"
      return edit(m)
    of esSubtitle, esRegex:
      var m = subtitleMethod("")
      for (argPos, val) in checkedMethodArgs("subtitle", node[1 ..< node.len], text):
        case argPos:
        of 0: m.pattern = val
        of 1: m.stream = parseStream(val)
        of 2: m.ignoreCase = parseBool(val)
        else: error "Too many args"
      if m.stream < 0:
        error "subtitle: 'all' stream is not supported"
      return edit(m)
    of esWord:
      var m = wordMethod("")
      for (argPos, val) in checkedMethodArgs("word", node[1 ..< node.len], text):
        case argPos:
        of 0: m.pattern = val
        of 1: m.stream = parseStream(val)
        of 2: m.ignoreCase = parseBool(val)
        else: error "Too many args"
      if m.pattern == "":
        error "word: value required"
      if m.stream < 0:
        error "word: 'all' stream is not supported"
      return edit(m)
    of esNone: return edit(noneMethod())
    of esAll: return edit(allMethod())
    else:
      error &"Unknown function: {text[node[0].`from` ..< node[0].to]}"

  var lexer = initLexer(filename, source)
  var parser: Parser
  let expressions: seq[Expr] = (
    try:
      parser = initParser(lexer) # lexes the first token, so it can raise too
      parser.parse()
    except ValueError as e: error &"{filename}: {e.msg}"
  )
  if expressions.len == 0:
    error &"{filename}: expression is empty"
  let expr = expressions[^1]
  if expr.kind != ExprList:
    error "Should never happen"
  toExpr(expr, parser.lexer.sourceText)

proc evalEdit(e: EditExpr, container: InputContainer, input: string,
    tb: AVRational, bar: Bar): seq[bool] =
  ## Which frames of `input` at `tb` `e` marks active.
  case e.op
  of eoOr:
    result = evalEdit(e.operands[0], container, input, tb, bar)
    for i in 1 ..< e.operands.len:
      result = result or evalEdit(e.operands[i], container, input, tb, bar)
  of eoAnd:
    result = evalEdit(e.operands[0], container, input, tb, bar)
    for i in 1 ..< e.operands.len:
      result = result and evalEdit(e.operands[i], container, input, tb, bar)
  of eoXor:
    result = evalEdit(e.operands[0], container, input, tb, bar)
    for i in 1 ..< e.operands.len:
      result = result xor evalEdit(e.operands[i], container, input, tb, bar)
  of eoNot:
    return not evalEdit(e.operands[0], container, input, tb, bar)
  of eoMethod:
    let m = e.m
    case m.kind
    of ekAudio:
      func streamChannel(i: int): int {.raises: [].} =
        let audioStream = container.audio[i]
        resolveAudioChannelOrDefault(addr audioStream.codecpar.ch_layout, m.channel)

      if m.stream == -1:
        var matched = false
        var undecodable = 0
        for i in 0 ..< container.audio.len:
          let codecId = container.audio[i].codecpar.codec_id
          if not canDecode(codecId):
            inc undecodable
            # Analyzing "all" streams shouldn't fail on a track no decoder
            # can read, like the `apac` one in iPhone Spatial Audio files.
            debug &"audio: skipping stream {i}, no decoder for " &
              $avcodec_get_name(codecId)
            continue
          let channelIndex = streamChannel(i)
          if channelIndex >= -1:
            result.orWithThreshold(
              audio(bar, container, input, tb, i.int16, channelIndex), m.threshold)
            matched = true
        if not matched:
          if undecodable > 0 and undecodable == container.audio.len:
            error "audio: no audio stream in this file can be decoded."
          error &"audio: channel '{m.channel}' does not exist in any audio stream."
      else:
        if m.stream >= container.audio.len:
          error &"audio: audio stream '{m.stream}' does not exist."
        let channelIndex = streamChannel(m.stream)
        if channelIndex < -1:
          let layout = $addr container.audio[m.stream].codecpar.ch_layout
          error &"audio: channel '{m.channel}' does not exist in stream {m.stream} ({layout})."
        result.orWithThreshold(
          audio(bar, container, input, tb, m.stream.int16, channelIndex), m.threshold)
    of ekMotion:
      let r = m.region
      result.orWithThreshold(motion(bar, container, input, tb, m.stream.int16,
        m.width.int32, m.blur.int32, packUnorm24x4(r.x, r.y, r.w, r.h)), m.threshold)
    of ekBlackdetect:
      result.orWithThreshold(blackdetect(bar, container, input, tb,
        m.stream.int16, m.pixelBlack), m.threshold)
    of ekSubtitle, ekWord:
      let name = if m.kind == ekWord: "word" else: "regex"
      var flags: set[ReFlag]
      if m.kind == ekSubtitle: flags.incl reUtf8
      if m.ignoreCase: flags.incl reIgnoreCase
      let regexPattern =
        if m.kind == ekWord: re("\\b" & escapeRe(m.pattern) & "\\b", flags)
        else: re(m.pattern, flags)
      let stream = m.stream.int16
      let (ret, val) = subtitle(container, tb, regexPattern, stream)
      if ret != -1:
        let subcontainer = findExternSubs(input)
        if subcontainer.isNone():
          error &"{name}: subtitle stream '{ret}' does not exist."
        let external = subcontainer.unsafeGet()
        defer: external.close()
        let index = int16(stream - container.subtitle.len)
        let (ret2, val2) = subtitle(external, tb, regexPattern, index)
        if ret2 != -1:
          error &"{name}: subtitle stream '{ret2}' does not exist."
        return val2
      return val
    of ekNone:
      let length = mediaLength(container)
      let tbLength = (round((length * tb).float64)).int
      return newSeqWith(tbLength, true)
    of ekAll:
      return @[]

proc interpretEdit*(args: mainArgs, container: InputContainer, input: string,
    tb: AVRational, bar: Bar): seq[uint8] =
  # Label 1: the default `--edit` method. Maps the boolean mask onto 0/1.
  let base = evalEdit(args.edit, container, input, tb, bar)
  result = newSeq[uint8](base.len)
  for i in 0 ..< base.len:
    if base[i]:
      result[i] = 1'u8

  # Labels >= 2: higher label wins on overlap (priority max). A label's mask may
  # be longer than the running result (e.g. differing stream lengths); extend
  # with 0 (silent) so the merge covers every sample.
  for le in args.labeledEdits:
    let mask = evalEdit(le.expr, container, input, tb, bar)
    if mask.len > result.len:
      result.setLen(mask.len)
    let lbl = uint8(le.label)
    for i in 0 ..< mask.len:
      if mask[i] and lbl > result[i]:
        result[i] = lbl
