type
  TokenKind = enum
    Lparen, Rparen, Sym, Str, Num, Colon, Comma, Equal, Eof

  Token = object
    `from`: uint32
    to: uint32
    case kind: TokenKind
    of Str:
      decoded: bool
      strVal: string
    else:
      discard

  Lexer* = object
    filename: string
    text: string
    pos: uint32
    `char`: char

  Parser* = object
    lexer*: Lexer
    currentToken: Token
    nextToken: Token

  # AST node types
  ExprKind* = enum
    ExprNum, ExprSym, ExprStr, ExprList

  Expr* = object
    case kind*: ExprKind
    of ExprSym, ExprNum:
      discard
    of ExprStr:
      decoded*: bool
      strVal*: string
    of ExprList:
      elements*: seq[Expr]
    `from`*: uint32
    to*: uint32

func initLexer*(filename, text: string): Lexer =
  result.filename = filename
  result.text = text
  result.pos = 0
  result.`char` = (if text.len == 0: '\0' else: text[0])

func sourceText*(self: Lexer): lent string =
  self.text

proc advance(self: var Lexer) =
  self.pos += 1
  if self.pos == high(uint32) or self.pos > uint32(self.text.len - 1):
    self.`char` = '\0'
  else:
    self.`char` = self.text[self.pos]

func isWhiteSpace(c: char): bool =
  c in "\0 \t\n\r\x0b\x0c"

proc getNextToken(self: var Lexer): Token =
  while self.`char` != '\0':
    while self.`char` != '\0' and isWhiteSpace(self.`char`):
      self.advance()
    if self.`char` == '\0':
      continue

    if self.`char` == ';':
      while self.`char` != '\0' and self.`char` != '\n':
        self.advance()
      continue

    if self.`char` in "(){}[]":
      let par = self.`char`
      self.advance()
      return Token(kind: if par in "({[": Lparen else: Rparen,
          `from`: self.pos - 1, to: self.pos)

    if self.`char` == ':':
      self.advance()
      return Token(kind: Colon, `from`: self.pos - 1, to: self.pos)

    if self.`char` == '=':
      self.advance()
      return Token(kind: Equal, `from`: self.pos - 1, to: self.pos)

    if self.`char` == ',':
      self.advance()
      return Token(kind: Comma, `from`: self.pos - 1, to: self.pos)

    if self.`char` == '"':
      self.advance()
      let `from` = self.pos
      var
        decoded = false
        value: string
      while self.`char` != '\0' and self.`char` != '"':
        if self.`char` == '\\' and self.pos + 1 < uint32(self.text.len):
          if not decoded:
            decoded = true
            value = newStringOfCap(int(self.pos - `from`) + 16)
            for i in `from` ..< self.pos:
              value.add(self.text[i])
          self.advance()
          case self.`char`
          of 'n': value.add('\n')
          of 't': value.add('\t')
          else: value.add(self.`char`) # \" \\ and others: literal
        elif decoded:
          value.add(self.`char`)
        self.advance()
      if self.`char` != '"':
        raise newException(ValueError, "Unterminated string literal")
      let `to` = self.pos
      self.advance()
      return Token(kind: Str, `from`: `from`, to: `to`, decoded: decoded,
        strVal: value)

    if self.`char` in "0123456789." or (self.`char` == '-' and self.pos + 1 <
        uint32(self.text.len) and self.text[self.pos + 1] in "0123456789."):
      let `from` = self.pos
      while self.`char` notin "()[]{}\",:;\0 \t\n\r\x0b\x0c":
        self.advance()
      return Token(kind: Num, `from`: `from`, to: self.pos)

    let `from` = self.pos
    while self.`char` notin "'.()[]{}=\",:;\0 \t\n\r\x0b\x0c":
      self.advance()

    return Token(kind: Sym, `from`: `from`, to: self.pos)

  return Token(kind: Eof)

proc initParser*(lexer: var Lexer): Parser =
  result = Parser(lexer: lexer)
  result.currentToken = result.lexer.getNextToken()
  result.nextToken = result.lexer.getNextToken()

proc eat(self: var Parser) =
  self.currentToken = self.nextToken
  self.nextToken = self.lexer.getNextToken()

func peek(self: Parser): Token =
  self.nextToken

func atomText*(expr: Expr, text: string): string =
  case expr.kind
  of ExprSym, ExprNum:
    text[expr.`from` ..< expr.to]
  of ExprStr:
    if expr.decoded: expr.strVal else: text[expr.`from` ..< expr.to]
  of ExprList:
    raise newException(ValueError, "A list does not have atom text")

func spanEquals(text: string, `from`, to: uint32, expected: string): bool =
  let length = int(to - `from`)
  if length != expected.len:
    return false
  for i in 0 ..< length:
    if text[int(`from`) + i] != expected[i]:
      return false
  return true

func symbolEquals*(expr: Expr, text, expected: string): bool =
  ## Compare a symbol without allocating a source slice.
  expr.kind == ExprSym and text.spanEquals(expr.`from`, expr.to, expected)

func numberEquals*(expr: Expr, text, expected: string): bool =
  ## Compare a numeric atom without allocating a source slice.
  expr.kind == ExprNum and text.spanEquals(expr.`from`, expr.to, expected)

# Forward declaration
proc expr(self: var Parser): Expr


proc list(self: var Parser): Expr =
  let startPos = self.currentToken.`from`
  self.eat()

  var elements = newSeqOfCap[Expr](4)

  while self.currentToken.kind != Rparen and self.currentToken.kind != Eof:
    elements.add(self.expr())

  if self.currentToken.kind == Eof:
    raise newException(ValueError, "Missing closing parenthesis")

  let endPos = self.currentToken.to
  self.eat()

  return Expr(kind: ExprList, elements: elements, `from`: startPos, to: endPos)

proc expr(self: var Parser): Expr =
  let token = self.currentToken
  case token.kind:
  of Lparen:
    return self.list()
  of Num:
    self.eat()
    return Expr(kind: ExprNum, `from`: token.`from`, to: token.to)
  of Str:
    self.eat()
    return Expr(kind: ExprStr, decoded: token.decoded, strVal: token.strVal,
      `from`: token.`from`, to: token.to)
  of Sym:
    let symExpr = Expr(kind: ExprSym, `from`: token.`from`, to: token.to)
    self.eat()

    # Check if this symbol is followed by a colon (function call syntax)
    if self.currentToken.kind == Colon:
      self.eat()
      var elements = newSeqOfCap[Expr](4)
      elements.add(symExpr)

      while self.currentToken.kind in {Num, Sym, Str}:
        # Check if this is another function call (symbol followed by colon)
        if self.currentToken.kind == Sym:
          let nextToken = self.peek()
          if nextToken.kind == Colon:
            # This is another function call, stop processing arguments for current function
            break

        var arg = self.expr()

        # Check if this argument is followed by = (assignment syntax)
        if self.currentToken.kind == Equal:
          self.eat()
          if self.currentToken.kind notin {Num, Sym, Str, Lparen}:
            let key = arg.atomText(self.lexer.text)
            raise newException(ValueError, "'" & key & "=' is missing a value")
          let equalExpr = Expr(kind: ExprSym, `from`: self.currentToken.`from` -
              1, to: self.currentToken.`from`)
          let value = self.expr()
          arg = Expr(kind: ExprList, elements: @[equalExpr, arg, value],
              `from`: arg.`from`, to: value.to)

        elements.add(arg)

        if self.currentToken.kind == Comma:
          self.eat() # consume the comma
        else:
          break

      return Expr(kind: ExprList, elements: elements, `from`: token.`from`,
          to: self.currentToken.`from`)
    else:
      return symExpr
  of Equal:
    self.eat()
    return Expr(kind: ExprSym, `from`: token.`from`, to: token.to)
  else:
    # This should not happen with valid input
    raise newException(ValueError, "Unexpected token")

proc parse*(self: var Parser): seq[Expr] =
  var tokens = newSeqOfCap[Expr](4)

  while self.currentToken.kind != Eof:
    let expr = self.expr()
    tokens.add(expr)

  if tokens.len == 0:
    return @[]

  # A bare atom (`audio`, `1`) or several top-level exprs (`or audio:3%
  # motion:6%`) are an implicit call form; evaluators expect a list.
  if tokens.len > 1 or tokens[0].kind != ExprList:
    return @[Expr(kind: ExprList, elements: tokens, `from`: 0,
        to: uint32(self.lexer.text.len))]
  return tokens
