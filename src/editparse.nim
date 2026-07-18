import ./[editlexer, editmethods]

type
  BoundEditArg* = tuple[position: int, value: string]
  ParsedEditMethod* = object
    name*: string
    args*: seq[BoundEditArg]

func isSymbol(expr: Expr, name, text: string): bool =
  expr.kind == ExprSym and name == text[expr.`from` ..< expr.to]

proc bindEditArgs*(expressions: openArray[Expr], text: string,
    argOrder: openArray[string]): seq[BoundEditArg] =
  ## Bind positional and keyword arguments to their position in `argOrder`.
  ## Values remain strings so each consumer can apply its own semantic policy.
  var
    positional = 0
    sawKeyword = false

  for expr in expressions:
    var
      position = positional
      value: string

    if expr.kind == ExprList and expr.elements.len > 0 and
        expr.elements[0].isSymbol("=", text):
      let node = expr.elements
      let key = text[node[1].`from` ..< node[1].to]
      sawKeyword = true
      position = argOrder.find(key)
      if position == -1:
        raise newException(ValueError,
          "got an unexpected keyword argument: " & key)
      value = text[node[2].`from` ..< node[2].to]
    else:
      if sawKeyword:
        raise newException(ValueError,
          "Positional arguments must never come after keyword arguments")
      if position >= argOrder.len:
        raise newException(ValueError, "Too many args")
      value = text[expr.`from` ..< expr.to]
      positional += 1

    result.add((position, value))

proc bindEditMethodArgs*(name: string, expressions: openArray[Expr],
    text: string): seq[BoundEditArg] =
  bindEditArgs(expressions, text, argOrderOf(name))

proc parseSingleEditMethod*(filename, source: string): ParsedEditMethod =
  ## Parse exactly one edit method. Operators and constants belong to the full
  ## `--edit` expression evaluator and are intentionally rejected here.
  var lexer = initLexer(filename, source)
  var parser = initParser(lexer)
  let expressions = parser.parse()
  if expressions.len == 0:
    raise newException(ValueError, "expression is empty")

  var expr = expressions[^1]
  while expr.kind == ExprList and expr.elements.len == 1 and
      expr.elements[0].kind == ExprList:
    expr = expr.elements[0]

  if expr.kind != ExprList or expr.elements.len == 0 or
      expr.elements[0].kind != ExprSym:
    raise newException(ValueError, "expected one editing method")

  let text = parser.lexer.text # mutated buffer: quoted escapes are decoded
  result.name = text[expr.elements[0].`from` ..< expr.elements[0].to]
  if isEditOperator(result.name):
    raise newException(ValueError,
      "expected one editing method, got operator '" & result.name & "'")
  if editMediaOf(result.name) == {}:
    raise newException(ValueError, "Unknown editing method: " & result.name)

  if expr.elements.len > 1:
    result.args = bindEditMethodArgs(result.name,
      expr.elements.toOpenArray(1, expr.elements.high), text)
