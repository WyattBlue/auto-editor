import std/[math, options, os, sequtils, strformat, strutils]
import ./[av, editlexer, editmethods, ffmpeg, log]
import ./analyze/[audio, blackdetect, motion, subtitle]
import ./util/[bar, dnorm16, fun, rational]

import ./vendor/tinyre/tinyre

func isSymbol(self: Expr, name, text: string): bool =
  self.kind == ExprSym and name == text[self.`from` ..< self.to]

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

const
  defaultAudioThres = toUnorm16(0.04)
  defaultMotionThres = toUnorm16(0.02)
  defaultBlackThres = toUnorm16(0.98)

proc parseFloatInRange(val: string, min, max: float32): float32 {.raises: [].} =
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
  let n = (
    try: parseInt(val)
    except ValueError: error &"Invalid stream: {val}"
  )
  if n > 1000 or n < 0: error &"Invalid stream: {val}"
  result = int16(n)

proc parseBool(val: string): bool =
  if val == "#t" or val == "true":
    return true
  if val == "#f" or val == "false":
    return false
  error "Invalid boolean (expected true or false): " & val

proc parseColFunc(argPos: var int, isKey: var bool, argOrder: seq[string], expr: Expr,
    text: string): string =
  if expr.kind == ExprList and expr.elements[0].isSymbol("=", text):
    let node = expr.elements
    let key = text[node[1].`from` ..< node[1].to]
    isKey = true
    argPos = argOrder.find(key)
    if argPos == -1:
      error &"got an unexpected keyword argument: {key}"
    return text[node[2].`from` ..< node[2].to]
  else:
    if isKey:
      error "Positional arguments must never come after keyword arguments"
    return text[expr.`from` ..< expr.to]


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

  var
    isKey = false
    argPos = 0

  proc normEval(expr: Expr, text: string): Norm =
    if expr.kind != ExprList or expr.elements.len == 0:
      error "Bad kind"

    let node = expr.elements
    if node[0].kind == ExprList and node.len == 1:
      return normEval(node[0], text)

    if node[0].kind == ExprSym:
      case text[node[0].`from` ..< node[0].to]:
      of "ebu":
        let argOrder = @["i", "lra", "tp", "gain"]
        var
          i: float32 = -24.0
          lra: float32 = 7.0
          tp: float32 = -2.0
          gain: float32 = 0.0
        for expr in node[1 ..< node.len]:
          let val = parseColFunc(argPos, isKey, argOrder, expr, text)

          case argPos:
          of 0: i = parseFloatInRange(val, -70.0, 5.0)
          of 1: lra = parseFloatInRange(val, 1.0, 50.0)
          of 2: tp = parseFloatInRange(val, -9.0, 0.0)
          of 3: gain = parseFloatInRange(val, -99.0, 99.0)
          else: error "Too many args"

          if not isKey:
            argPos += 1

        return Norm(kind: nkEbu, i: i, lra: lra, tp: tp, gain: gain)
      of "peak":
        let argOrder = @["t"]
        var t: float32 = -8.0
        for expr in node[1 ..< node.len]:
          let val = parseColFunc(argPos, isKey, argOrder, expr, text)

          case argPos:
          of 0: t = parseFloatInRange(val, -99.0, 0.0)
          else: error "Too many args"

          if not isKey:
            argPos += 1

        return Norm(kind: nkPeak, t: t)
      else:
        error &"Unknown audio norm: {text[node[0].`from` ..< node[0].to]}"
    else:
      error "Invalid audio norm expression."

  return normEval(expr, parser.lexer.text) # mutated buffer: escapes unescaped

proc findExternSubs(input: string): Option[InputContainer] {.raises: [].} =
  try:
    some(av.open(input.changeFileExt("srt")))
  except IOError:
    try:
      some(av.open(input.changeFileExt("ass")))
    except IOError:
      none(InputContainer)

proc editNeeds*(edit: string): tuple[video, audio: bool] =
  ## Report whether an --edit expression analyzes video and/or audio frames, so
  ## callers can avoid fetching streams no editing method will look at. Subtitle
  ## methods read the subtitle stream, so they report neither.
  var lexer = initLexer("--edit", edit)
  var parser: Parser
  let expressions =
    try:
      parser = initParser(lexer)
      parser.parse()
    except CatchableError:
      return (true, true) # Malformed; interpretEdit will report the real error.
  if expressions.len == 0:
    return (false, false)

  var video = false
  var audio = false

  proc walk(e: Expr) =
    if e.kind == ExprList:
      if e.elements.len == 0:
        return
      let head = e.elements[0]
      if head.kind == ExprSym and isEditOperator(edit[head.`from` ..< head.to]):
        for i in 1 ..< e.elements.len:
          walk(e.elements[i])
      else:
        walk(head)
    elif e.kind == ExprSym:
      for m in editMediaOf(edit[e.`from` ..< e.to]):
        case m
        of emVideo: video = true
        of emAudio: audio = true
        of emSubtitle: discard # analyzed from the subtitle stream, not v/a frames

  walk(expressions[^1])
  return (video, audio)

proc interpretEdit*(args: mainArgs, container: InputContainer, input: string, tb: AVRational, bar: Bar): seq[uint8] =

  proc editEval(expr: Expr, text: string): seq[bool] =
    if expr.kind in {ExprSym, ExprNum}:
      # A bare method inside an operator, e.g. `(or audio motion)`: invoke it
      # with its default arguments.
      return editEval(Expr(kind: ExprList, elements: @[expr],
        `from`: expr.`from`, to: expr.to), text)
    if expr.kind != ExprList or expr.elements.len == 0:
      error "Bad kind"

    let node = expr.elements
    if node[0].kind == ExprList and node.len == 1:
      return editEval(node[0], text)

    var
      threshold: Unorm16 = defaultAudioThres
      stream: int16 = 0
      width: int32 = 400
      blur: int32 = 9
      isKey = false
      argPos = 0

    if node[0].kind == ExprNum:
      case text[node[0].`from` ..< node[0].to]:
      of "0":
        return @[]
      of "1":
        let length = mediaLength(container)
        let tbLength = (round((length * tb).float64)).int

        return newSeqWith(tbLength, true)
      else:
        error "We only support 0 or 1 right now."
    elif node[0].kind == ExprSym:
      case text[node[0].`from` ..< node[0].to]:
      of "or":
        result = editEval(node[1], text)
        for i in 2 ..< node.len:
          result = result or editEval(node[i], text)
      of "and":
        result = editEval(node[1], text)
        for i in 2 ..< node.len:
          result = result and editEval(node[i], text)
      of "xor":
        result = editEval(node[1], text)
        for i in 2 ..< node.len:
          result = result xor editEval(node[i], text)
      of "not":
        if node.len != 2:
          error "Wrong arity"
        return not editEval(node[1], text)
      of "audio":
        stream = -1 # Set to "all" by default
        var channel = "all"
        let argOrder = argOrderOf("audio")

        for expr in node[1 ..< node.len]:
          let val = parseColFunc(argPos, isKey, argOrder, expr, text)

          case argPos:
          of 0: threshold = parseThres(val)
          of 1: stream = parseStream(val)
          of 2: channel = val
          else: error "Too many args"

          if not isKey:
            argPos += 1

        if channel != "all" and audioChannelCode(channel) == "":
          error &"audio: unknown channel '{channel}'."

        func streamChannel(i: int16): int {.raises: [].} =
          let audioStream = container.audio[i]
          resolveAudioChannelOrDefault(addr audioStream.codecpar.ch_layout, channel)

        if stream == -1:
          var matched = false
          for i in 0 ..< container.audio.len:
            let channelIndex = streamChannel(i.int16)
            if channelIndex >= -1:
              result.orWithThreshold(
                audio(bar, container, input, tb, i.int16, channelIndex), threshold)
              matched = true
          if not matched:
            error &"audio: channel '{channel}' does not exist in any audio stream."
        else:
          if stream >= container.audio.len:
            error &"audio: audio stream '{stream}' does not exist."
          let channelIndex = streamChannel(stream)
          if channelIndex < -1:
            let layout = $addr container.audio[stream].codecpar.ch_layout
            error &"audio: channel '{channel}' does not exist in stream {stream} ({layout})."
          result.orWithThreshold(
            audio(bar, container, input, tb, stream, channelIndex), threshold)
        return result
      of "motion":
        threshold = defaultMotionThres
        var
          x: float32 = 0.0
          y: float32 = 0.0
          w: float32 = 1.0
          h: float32 = 1.0
        let argOrder = argOrderOf("motion")

        for expr in node[1 ..< node.len]:
          let val = parseColFunc(argPos, isKey, argOrder, expr, text)

          case argPos:
          of 0: threshold = parseThres(val)
          of 1: stream = parseStream(val)
          of 2: width = parseNat(val)
          of 3: blur = parseNat(val)
          of 4: x = parseFloatInRange(val, 0.0, 1.0)
          of 5: y = parseFloatInRange(val, 0.0, 1.0)
          of 6: w = parseFloatInRange(val, 0.0, 1.0)
          of 7: h = parseFloatInRange(val, 0.0, 1.0)
          else: error "Too many args"

          if not isKey:
            argPos += 1

        if stream < 0:
          error "motion: 'all' stream is not supported"
        let rect = packUnorm24x4(x, y, w, h)
        result.orWithThreshold(
          motion(bar, container, input, tb, stream, width, blur, rect), threshold)
        return result
      of "blackdetect":
        threshold = defaultBlackThres
        var pixelBlack: float32 = 0.10
        let argOrder = argOrderOf("blackdetect")

        for expr in node[1 ..< node.len]:
          let val = parseColFunc(argPos, isKey, argOrder, expr, text)

          case argPos:
          of 0: threshold = parseThres(val)
          of 1: stream = parseStream(val)
          of 2: pixelBlack = parseFloatInRange(val, 0.0, 1.0)
          else: error "Too many args"

          if not isKey:
            argPos += 1

        if stream < 0:
          error "blackdetect: 'all' stream is not supported"
        result.orWithThreshold(blackdetect(bar, container, input, tb, stream, pixelBlack), threshold)
        return result
      of "subtitle", "regex":
        let argOrder = argOrderOf("subtitle")
        var pattern = ""
        var flags = {reUtf8}

        for expr in node[1 ..< node.len]:
          let val = parseColFunc(argPos, isKey, argOrder, expr, text)
          case argPos:
          of 0: pattern = val
          of 1: stream = parseStream(val)
          of 2:
            if parseBool(val):
              flags.incl reIgnoreCase
          else: error "Too many args"

          if not isKey:
            argPos += 1

        if stream < 0:
          error "subtitle: 'all' stream is not supported"
        let regexPattern = re(pattern, flags)
        let (ret, val) = subtitle(container, tb, regexPattern, stream)
        if ret != -1:
          let subcontainer = findExternSubs(input)
          if subcontainer.isNone():
            error &"regex: subtitle stream '{ret}' does not exist."

          let index = int16(stream - container.subtitle.len)
          let (ret2, val2) = subtitle(subcontainer.unsafeGet(), tb, regexPattern, index)
          if ret2 != -1:
            error &"regex: subtitle stream '{ret2}' does not exist."
          return val2
        return val
      of "word":
        let argOrder = argOrderOf("word")
        var pattern = ""
        var ignoreCase = true
        var flags: set[ReFlag]

        for expr in node[1 ..< node.len]:
          let val = parseColFunc(argPos, isKey, argOrder, expr, text)
          case argPos:
          of 0: pattern = escapeRe(val)
          of 1: stream = parseStream(val)
          of 2: ignoreCase = parseBool(val)
          else: error "Too many args"

          if not isKey:
            argPos += 1

        if pattern == "":
          error "word: value required"
        if stream < 0:
          error "word: 'all' stream is not supported"

        pattern = "\\b" & pattern & "\\b"
        if ignoreCase:
          flags.incl reIgnoreCase

        let regexPattern = re(pattern, flags)
        let (ret, val) = subtitle(container, tb, regexPattern, stream)
        if ret != -1:
          let subcontainer = findExternSubs(input)
          if subcontainer.isNone():
            error &"word: subtitle stream '{ret}' does not exist."

          let index = int16(stream - container.subtitle.len)
          let (ret2, val2) = subtitle(subcontainer.unsafeGet(), tb, regexPattern, index)
          if ret2 != -1:
            error &"word: subtitle stream '{ret2}' does not exist."
          return val2
        return val
      of "none":
        let length = mediaLength(container)
        let tbLength = (round((length * tb).float64)).int

        return newSeqWith(tbLength, true)
      of "all":
        return @[]
      else:
        error &"Unknown function: {text[node[0].`from` ..< node[0].to]}"
    else:
      error &"`--edit` expects a valid expression: {text[node[0].`from` ..< node[0].to]}"

  proc evalEditString(editStr: string): seq[bool] =
    var lexer = initLexer("--edit", editStr)
    var parser: Parser
    let expressions: seq[Expr] = (
      try:
        parser = initParser(lexer) # lexes the first token, so it can raise too
        parser.parse()
      except ValueError as e: error &"--edit: {e.msg}"
    )
    if expressions.len == 0:
      error "--edit: expression is empty"
    let expr = expressions[^1]
    if expr.kind != ExprList:
      error "Should never happen"
    return editEval(expr, parser.lexer.text) # mutated buffer: escapes unescaped

  # Label 1: the default `--edit` method. Maps the boolean mask onto 0/1.
  let base = evalEditString(args.edit)
  result = newSeq[uint8](base.len)
  for i in 0 ..< base.len:
    if base[i]:
      result[i] = 1'u8

  # Labels >= 2: higher label wins on overlap (priority max). A label's mask may
  # be longer than the running result (e.g. differing stream lengths); extend
  # with 0 (silent) so the merge covers every sample.
  for le in args.labeledEdits:
    let mask = evalEditString(le.expr)
    if mask.len > result.len:
      result.setLen(mask.len)
    let lbl = uint8(le.label)
    for i in 0 ..< mask.len:
      if mask[i] and lbl > result[i]:
        result[i] = lbl
