type
  TokenKind = enum
    Lparen, Rparen, Sym, Num, Colon, Comma, Equal, Eof

  Token = object
    kind: TokenKind
    `from`: uint32
    to: uint32

  Lexer* = object
    filename: string
    text*: string
    pos: uint32
    `char`: char

  Parser* = object
    lexer*: Lexer
    currentToken: Token

  # AST node types
  ExprKind* = enum
    ExprNum, ExprSym, ExprList

  Expr* = ref object
    case kind*: ExprKind
    of ExprSym, ExprNum:
      discard
    of ExprList:
      elements*: seq[Expr]
    `from`*: uint32
    to*: uint32

func initLexer*(filename, text: string): Lexer =
  result.filename = filename
  result.text = text
  result.pos = 0
  result.`char` = (if text.len == 0: '\0' else: text[0])

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
      return Token(kind: if par in "({[": Lparen else: Rparen, `from`: self.pos - 1, to: self.pos)

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
      var writePos = self.pos
      while self.`char` != '\0' and self.`char` != '"':
        if self.`char` == '\\' and self.pos + 1 < uint32(self.text.len):
          self.advance()
          case self.`char`
          of 'n': self.text[writePos] = '\n'
          of 't': self.text[writePos] = '\t'
          else: self.text[writePos] = self.`char` # \" \\ and others: literal
        else:
          self.text[writePos] = self.`char`
        writePos += 1
        self.advance()
      if self.`char` != '"':
        raise newException(ValueError, "Unterminated string literal")
      let `to` = writePos
      self.advance()
      return Token(kind: Sym, `from`: `from`, to: `to`)

    if self.`char` in "0123456789." or (self.`char` == '-' and self.pos + 1 < uint32(
        self.text.len) and self.text[self.pos + 1] in "0123456789."):
      let `from` = self.pos
      while self.`char` notin "()[]{}\",:;\0 \t\n\r\x0b\x0c":
        self.advance()
      return Token(kind: Num, `from`: `from`, to: self.pos)

    let `from` = self.pos
    var writePos = self.pos
    while self.`char` notin "'.()[]{}=\",:;\0 \t\n\r\x0b\x0c":
      # `\"` is a literal quote; other backslashes stay literal.
      if self.`char` == '\\' and self.pos + 1 < uint32(self.text.len) and
          self.text[self.pos + 1] == '"':
        self.advance()
      self.text[writePos] = self.`char`
      writePos += 1
      self.advance()

    return Token(kind: Sym, `from`: `from`, to: writePos)

  return Token(kind: Eof)

proc initParser*(lexer: var Lexer): Parser =
  result = Parser(lexer: lexer)
  result.currentToken = result.lexer.getNextToken()

proc eat(self: var Parser) =
  self.currentToken = self.lexer.getNextToken()

proc peek(self: var Parser): Token =
  # Lex from a copy: string tokens unescape self.text in place.
  var tmp = self.lexer
  result = tmp.getNextToken()

# Forward declaration
proc expr(self: var Parser): Expr


proc list(self: var Parser): Expr =
  let startPos = self.currentToken.`from`
  self.eat()

  var elements: seq[Expr] = @[]

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
  of Sym:
    let symExpr = Expr(kind: ExprSym, `from`: token.`from`, to: token.to)
    self.eat()

    # Check if this symbol is followed by a colon (function call syntax)
    if self.currentToken.kind == Colon:
      self.eat()
      var elements: seq[Expr] = @[symExpr]

      while self.currentToken.kind in {Num, Sym}:
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
          if self.currentToken.kind notin {Num, Sym, Lparen}:
            let key = self.lexer.text[arg.`from`.int ..< arg.to.int]
            raise newException(ValueError, "'" & key & "=' is missing a value")
          let equalExpr = Expr(kind: ExprSym, `from`: self.currentToken.`from` - 1,
              to: self.currentToken.`from`)
          let value = self.expr()
          arg = Expr(kind: ExprList, elements: @[equalExpr, arg, value], `from`: arg.`from`, to: value.to)

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
  var tokens: seq[Expr] = @[]

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
