import std/strutils

type
  TokenKind = enum
    Lparen, Rparen, Sym, Num, Colon, Comma, Equal, Eof

  Token = object
    kind: TokenKind
    `from`: uint32
    to: uint32

  Lexer* = object
    filename: string
    text: string
    pos: uint32
    `char`: char

  Parser* = object
    lexer: Lexer
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

    if self.`char` in "0123456789.":
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
  return Parser(lexer: lexer, currentToken: lexer.getNextToken())

proc eat(self: var Parser) =
  self.currentToken = self.lexer.getNextToken()

proc peek(self: var Parser): Token =
  let savedPos = self.lexer.pos
  let savedChar = self.lexer.`char`
  result = self.lexer.getNextToken()
  self.lexer.pos = savedPos
  self.lexer.`char` = savedChar

# Forward declaration
proc expr(self: var Parser): Expr


proc list(self: var Parser): Expr =
  let startPos = self.currentToken.`from`
  self.eat()

  var elements: seq[Expr] = @[]

  while self.currentToken.kind != Rparen and self.currentToken.kind != Eof:
    elements.add(self.expr())

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
          let equalExpr = Expr(kind: ExprSym, `from`: self.currentToken.`from` - 1, to: self.currentToken.`from`)
          let value = self.expr()
          arg = Expr(kind: ExprList, elements: @[equalExpr, arg, value], `from`: arg.`from`, to: value.to)

        elements.add(arg)

        if self.currentToken.kind == Comma:
          self.eat() # consume the comma
        else:
          break

      return Expr(kind: ExprList, elements: elements, `from`: token.`from`, to: self.currentToken.`from`)
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

  # If we have multiple tokens at the top level, wrap them in a list
  if tokens.len > 1:
    tokens.delete(0)  # Delete extra Symbol
    result.add(Expr(kind: ExprList, elements: tokens, `from`: 0, to: uint32(self.lexer.text.len)))
  else:
    result = tokens

# Pretty printing functions
proc printExpr*(expr: Expr, text: string): string =
  case expr.kind:
  of ExprNum:
    return "Num:" & text[expr.`from` ..< expr.to]
  of ExprSym:
    return text[expr.`from` ..< expr.to]
  of ExprList:
    var parts: seq[string] = @[]
    for elem in expr.elements:
      parts.add(elem.printExpr(text))
    return "(" & parts.join(" ") & ")"
