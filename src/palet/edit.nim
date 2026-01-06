import std/[math, options, os, sequtils, strformat, strutils]
import lexer
import ../[av, ffmpeg, log]
import ../analyze/[audio, motion, subtitle]
import ../util/[bar, fun]

import tinyre


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

proc parseThres(val: string): float32 =
  let (num, unit) = splitNumStr(val)
  if unit == "%":
    result = float32(num / 100)
  elif unit == "dB":
    result = float32(pow(10, num / 20))
  elif unit == "":
    result = float32(num)
  else:
    error &"Unknown unit: {unit}"

  if result < 0 or result > 1:
    error &"Threshold not in range: {val} ({result})"

proc parseFloatInRange(val: string, min, max: float32): float32 {.raises:[].} =
  try:
    result = parseFloat(val)
  except ValueError:
    error &"Invalid number: {val}"
  if result < min or result > max:
    error &"value {result} is outside range [{min}, {max}]"

proc parseNat(val: string): int32 =
  result = int32(parseInt(val))
  if result < 0:
    error "Invalid natural: " & val

proc parseBool(val: string): bool =
  if val == "#t" or val == "true":
    return true
  if val == "#f" or val == "false":
    return false
  error "Invalid boolean (expected true or false): " & val

proc parseColFunc(argPos: var int, isKey: var bool, argOrder: seq[string], expr: Expr, text: string): string =
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
  var parser = initParser(lexer)
  let expressions: seq[Expr] = parser.parse()
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

  return normEval(expr, norm)

proc findExternSubs(input: string): Option[InputContainer] =
  try:
    some(av.open(input.changeFileExt("srt")))
  except IOError:
    try:
      some(av.open(input.changeFileExt("ass")))
    except IOError:
      none(InputContainer)

proc interpretEdit*(args: mainArgs, container: InputContainer, tb: AVRational, bar: Bar): seq[bool] =
  var lexer = initLexer("--edit", args.edit)
  var parser = initParser(lexer)
  let tbFloat = float64(tb)

  let expressions: seq[Expr] = parser.parse()
  let expr = expressions[^1]
  if expr.kind != ExprList:
    error "Should never happen"

  proc editEval(expr: Expr, text: string): seq[bool] =
    if expr.kind != ExprList or expr.elements.len == 0:
      error "Bad kind"

    let node = expr.elements
    if node[0].kind == ExprList and node.len == 1:
      return editEval(node[0], text)

    var
      threshold: float32 = 0.04
      stream: int32 = 0
      mincut = 6
      minclip = 3
      width: int32 = 400
      blur: int32 = 9
      isKey = false
      argPos = 0

    if node[0].kind == ExprSym:
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
        let argOrder = @["threshold", "stream", "mincut", "minclip"]

        for expr in node[1 ..< node.len]:
          let val = parseColFunc(argPos, isKey, argOrder, expr, text)

          case argPos:
          of 0: threshold = parseThres(val)
          of 1: stream = (if val == "all": -1 else: parseNat(val))
          of 2: mincut = parseTimeSimple(val).toTb(tbFloat)
          of 3: minclip = parseTimeSimple(val).toTb(tbFloat)
          else: error "Too many args"

          if not isKey:
            argPos += 1

        if stream == -1:
          for i in 0 ..< max(container.audio.len, 1): # Trigger err when no streams pres.
            let levels = audio(bar, container, args.input, tb, i.int32)
            if result.len == 0:
              result = levels.mapIt(it >= threshold)
            else:
              result = result or levels.mapIt(it >= threshold)
        else:
          let levels = audio(bar, container, args.input, tb, stream)
          result = levels.mapIt(it >= threshold)

        mutRemoveSmall(result, minclip, true, false)
        mutRemoveSmall(result, mincut, false, true)
        return result
      of "motion":
        threshold = 0.02 # Reduce default threshold
        let argOrder = @["threshold", "stream", "width", "blur"]

        for expr in node[1 ..< node.len]:
          let val = parseColFunc(argPos, isKey, argOrder, expr, text)

          case argPos:
          of 0: threshold = parseThres(val)
          of 1: stream = parseNat(val)
          of 2: width = parseNat(val)
          of 3: blur = parseNat(val)
          else: error "Too many args"

          if not isKey:
            argPos += 1
        let levels = motion(bar, container, args.input, tb, stream, width, blur)
        return levels.mapIt(it >= threshold)
      of "subtitle", "regex":
        let argOrder = @["pattern", "stream", "ignore-case"] # "max-count"]
        var pattern = ""
        var flags: set[ReFlag]

        for expr in node[1 ..< node.len]:
          let val = parseColFunc(argPos, isKey, argOrder, expr, text)
          case argPos:
          of 0: pattern = val
          of 1: stream = parseNat(val)
          of 2:
            if parseBool(val):
              flags.incl reIgnoreCase
          else: error "Too many args"

        if pattern == "":
          error &"{text[node[0].`from` ..< node[0].to]}: pattern required"

        let regexPattern = re(pattern, flags)
        let (ret, val) = subtitle(container, tb, regexPattern, stream)
        if ret != -1:
          let subcontainer = findExternSubs(args.input)
          if subcontainer.isNone():
            error &"regex: subtitle stream '{ret}' does not exist."

          let index = int32(stream - container.subtitle.len)
          let (ret, val) = subtitle(subcontainer.unsafeGet(), tb, regexPattern, index)
          if ret != -1:
            error &"regex: subtitle stream '{ret}' does not exist."
          return val
        else:
          return val
      of "word":
        let argOrder = @["value", "stream", "ignore-case"]
        var pattern = ""
        var ignoreCase = true
        var flags: set[ReFlag]

        for expr in node[1 ..< node.len]:
          let val = parseColFunc(argPos, isKey, argOrder, expr, text)
          case argPos:
          of 0: pattern = escapeRe(val)
          of 1: stream = parseNat(val)
          of 2: ignoreCase = parseBool(val)
          else: error "Too many args"

        if pattern == "":
          error "word: value required"

        pattern = "\\b" & pattern & "\\b"
        if ignoreCase:
          flags.incl reIgnoreCase

        let regexPattern = re(pattern, flags)
        let (ret, val) = subtitle(container, tb, regexPattern, stream)
        if ret != -1:
          let subcontainer = findExternSubs(args.input)
          if subcontainer.isNone():
            error &"word: subtitle stream '{ret}' does not exist."

          let index = int32(stream - container.subtitle.len)
          let (ret, val) = subtitle(subcontainer.unsafeGet(), tb, regexPattern, index)
          if ret != -1:
            error &"word: subtitle stream '{ret}' does not exist."
          return val
        else:
          return val
      of "none":
        let length = mediaLength(container)
        let tbLength = (round((length * tb).float64)).int64

        return newSeqWith(tbLength, true)
      of "all", "all/e":
        let length = mediaLength(container)
        let tbLength = (round((length * tb).float64)).int64

        return newSeqWith(tbLength, false)
      else:
        error &"Unknown function: {text[node[0].`from` ..< node[0].to]}"
    else:
      error "Expected a function"

  return editEval(expr, args.edit)
