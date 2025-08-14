import std/[strformat, strutils]
import std/sequtils
import std/math

import lexer
import ../av
import ../log
import ../ffmpeg
import ../util/bar
import ../analyze/[audio, motion, subtitle]
import ../util/fun

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
    result[i] = a[i] or b[i]

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
    result =  float32(num)
  else:
    error &"Unknown unit: {unit}"

  if result < 0 or result > 1:
    error &"Invalid threshold: {val}"

proc parseNat(val: string): int32 =
  result = int32(parseInt(val))
  if result < 0:
    error "Invalid natural: " & val

proc interpretEdit*(args: mainArgs, container: InputContainer, tb: AVRational, bar: Bar): seq[bool] =
  var lexer = initLexer("--edit", args.edit)
  var parser = initParser(lexer)

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

    if node[0].isSymbol("or", text):
      result = editEval(node[1], text)
      for i in 2 ..< node.len:
        result = result or editEval(node[i], text)
    elif node[0].isSymbol("and", text):
      result = editEval(node[1], text)
      for i in 2 ..< node.len:
        result = result and editEval(node[i], text)
    elif node[0].isSymbol("xor", text):
      result = editEval(node[1], text)
      for i in 2 ..< node.len:
        result = result xor editEval(node[i], text)
    elif node[0].isSymbol("not", text):
      if node.len != 2:
        error "Wrong arity"
      return not editEval(node[1], text)
    elif node[0].isSymbol("audio", text):
      var threshold: float32 = 0.04
      var stream: int32 = -1
      var mincut = 6
      var minclip = 3

      var isKey = false
      var argPos = 0
      let argOrder = ["threshold", "stream", "mincut", "minclip"]

      for expr in node[1 ..< node.len]:
        var val: string
        if expr.kind == ExprList and expr.elements[0].isSymbol("=", text):
          let node = expr.elements
          let key = text[node[1].`from` ..< node[1].to]
          isKey = true
          argPos = argOrder.find(key)
          if argPos == -1:
            error &"got an unexpected keyword argument: {key}"
          val = text[node[2].`from` ..< node[2].to]
        else:
          if isKey:
            error "Positional arguments must never come after keyword arguments"
          val = text[expr.`from` ..< expr.to]

        case argPos:
        of 0: threshold = parseThres(val)
        of 1: stream = (if val == "all": -1 else: parseNat(val))
        of 2: mincut = parseNat(val)
        of 3: minclip = parseNat(val)
        else: error &"Too many args"

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
    elif node[0].isSymbol("motion", text):
      var threshold: float32 = 0.02
      var stream: int32 = 0
      var width: int32 = 400
      var blur: int32 = 9

      var isKey = false
      var argPos = 0
      let argOrder = ["threshold", "stream", "width", "blur"]

      for expr in node[1 ..< node.len]:
        var val: string
        if expr.kind == ExprList and expr.elements[0].isSymbol("=", text):
          let node = expr.elements
          let key = text[node[1].`from` ..< node[1].to]
          isKey = true
          argPos = argOrder.find(key)
          if argPos == -1:
            error &"got an unexpected keyword argument: {key}"
          val = text[node[2].`from` ..< node[2].to]
        else:
          if isKey:
            error "Positional arguments must never come after keyword arguments"
          val = text[expr.`from` ..< expr.to]

        case argPos:
        of 0: threshold = parseThres(val)
        of 1: stream = parseNat(val)
        of 2: width = parseNat(val)
        of 3: blur = parseNat(val)
        else: error &"Too many args"

        if not isKey:
          argPos += 1
      let levels = motion(bar, container, args.input, tb, stream, width, blur)
      return levels.mapIt(it >= threshold)

    elif node[0].isSymbol("subtitle", text):
      var pattern: Re = re("")
      let stream: int32 = 0
      # FIXME
      return subtitle(container, tb, pattern, stream)
    elif node[0].isSymbol("none", text):
      let length = mediaLength(container)
      let tbLength = (round((length * tb).float64)).int64

      return newSeqWith(tbLength, true)
    elif node[0].isSymbol("all", text) or node[0].isSymbol("all/e", text):
      let length = mediaLength(container)
      let tbLength = (round((length * tb).float64)).int64

      return newSeqWith(tbLength, false)
    else:
      error &"Unknown function: {text[node[0].`from` ..< node[0].to]}"

  return editEval(expr, args.edit)


proc parseEditString2*(exportStr: string): (string, float32, int32, int32, int32, Re) =
  var
    kind = exportStr
    threshold: float32 = 0.04
    stream: int32 = 0
    width: int32 = 400
    blur: int32 = 9
    pattern: Re = re("")

  let colonPos = exportStr.find(':')
  if colonPos == -1:
    return (kind, threshold, stream, width, blur, pattern)

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
      of "stream": stream = parseInt(value).int32
      of "threshold": threshold = parseFloat(value).float32
      of "width": width = parseInt(value).int32
      of "blur": blur = parseInt(value).int32
      of "pattern":
        try:
          pattern = re(value)
        except ValueError:
          error &"Invalid regex expression: {value}"
      else: error &"Unknown paramter: {paramName}"

    # Skip comma
    if i < paramsStr.len and paramsStr[i] == ',':
      inc i

  return (kind, threshold, stream, width, blur, pattern)
