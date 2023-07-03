import strutils
import std/os
import std/strformat

type
  PragmaKind = enum
    blogType,
    explainerType,

  TokenKind = enum
    tkBar,
    keyval,
    tkText,
    tkH1,
    tkH2,
    tkH3,
    tkNewline,
    tkTick,
    tkList,
    tkUl,
    tkBlock,
    tkLink,
    tkEOF,

  Token = ref object
    kind: TokenKind
    value: string

  State = enum
    startState,
    headState,
    normalState,
    blockState,
    linkState,

  Lexer = ref object
    name: string
    text: string
    currentChar: char
    state: State
    pos: int
    line: int
    col: int

func initLexer(name: string, text: string): Lexer =
  return Lexer(name: name, text: text, currentChar: text[0], state: startState, pos: 0, line: 1, col: 1)

proc error(self: Lexer, msg: string) =
  write(stderr, &"{self.name}:{self.line}:{self.col} {msg}")
  system.quit(1)

proc advance(self: Lexer) = 
  self.pos += 1
  if self.pos > len(self.text) - 1:
    self.currentChar = '\0'
  else:
    if self.currentChar == '\n':
      self.line += 1
      self.col = 1
    else:
      self.col += 1

    self.currentChar = self.text[self.pos]

func peek(self: Lexer): char =
  let peakPos = self.pos + 1
  if peakPos > len(self.text) - 1:
    return '\0'
  else:
    return self.text[peakPos]

func longPeek(self: Lexer, pos: int): char =
  let peakPos = self.pos + pos
  if peakPos > len(self.text) - 1:
    return '\0'
  else:
    return self.text[peakPos]

func initToken(kind: TokenKind, value: string): Token =
  return Token(kind: kind, value: value)

proc getNextToken(self: Lexer): Token =
  var rod = ""
  var levels = 0
  while self.currentChar != '\0':
    if self.state == linkState:
      rod = ""
      while self.currentChar != ')':
        rod &= self.currentChar
        self.advance()
      self.advance()
      self.state = normalState
      return initToken(tkText, rod)  # return link ref
    if self.currentChar == '\n':
      self.advance()
      return initToken(tkNewline, "")

    if self.state == normalState and self.currentChar == '[':  # Handle links
      self.advance()
      rod = ""
      while self.currentChar != ']':
        rod &= self.currentChar
        self.advance()
      self.advance()
      if self.currentChar != '(':
        self.error("link expected ref")
      self.advance()
      self.state = linkState
      return initToken(tkLink, rod)

    if self.state == normalState and self.currentChar == '`':  # Handle code ticks
      while self.currentChar == '`':
        levels += 1
        self.advance()

      if levels == 1:
        rod = ""
        while self.currentChar != '`':
          rod &= self.currentChar
          self.advance()
        self.advance()

        if rod.strip() == "":
          self.error("Tick can't be blank")

        return initToken(tkTick, rod)
      elif levels == 3:
        self.state = blockState
        while not (self.currentChar in @['\n', '\0']):
          self.advance()
        return initToken(tkBlock, "")
      elif levels != 0:
        self.error(&"Wrong number of `s, ({levels})")

    if self.state == blockState and self.currentChar == '`':
      levels = 0
      while longPeek(self, levels) == '`':
        levels += 1
        if levels == 5:
          break

      if levels == 3:
        self.advance()
        self.advance()
        self.advance()
        self.state = normalState
        return initToken(tkBlock, "")
      else:
        while levels > 0:
          levels -= 1
          rod &= '`'
          self.advance()

    rod &= self.currentChar

    if self.state == headState and self.currentChar == ':':
      self.advance()  # then go to ` `
      while self.currentChar == ' ':
        self.advance()

      rod = ""
      while self.currentChar != '\n':
        if self.currentChar == '\0':
          self.error("Got EOF on key-value pair")

        if self.currentChar != '\n':
          rod &= self.currentChar

        self.advance()

      self.advance()
      return initToken(keyval, rod)

    if self.state in @[startState, headState, normalState] and rod == "---":
      self.advance()
      self.advance()
      if self.state == startState:
        self.state = headState
      elif self.state == headState:
        self.state = normalState
      return initToken(tkBar, "")

    var breakToken = false
    if self.peek() == '\n':
      breakToken = true
    elif self.state == normalState and self.peek() == '`':
      breakToken = true
    elif self.state == normalState and self.peek() == '[':
      breakToken = true
    elif self.state == blockState and self.peek() == '#':
      breakToken = true
    elif self.state == headState and self.peek() == ':':
      breakToken = true

    if breakToken:
      self.advance()
      if rod.strip() == "":
        continue
      else:
        return initToken(tkText, rod)

    if self.state == blockState and self.currentChar == '#' and self.peek() == ' ':
      self.advance()
      return initToken(tkH1, "")  # Italicize comments

    if self.state == normalState:
      if self.col == 1 and self.currentChar == ' ' and self.peek() == '*':
        self.advance()
        self.advance()
        self.advance()
        return initToken(tkList, "")

      levels = 0
      if self.currentChar == '#' and self.col == 1:
        while self.currentChar == '#':
          levels += 1
          self.advance()

        if self.currentChar != ' ':
          self.error("Expected space after header")
        self.advance()

        if levels == 3:
          return initToken(tkH3, "")
        elif levels == 2:
          return initToken(tkH2, "")
        elif levels == 1:
          return initToken(tkH1, "")
        elif levels != 0:
          self.error("Too many #s")

    self.advance()

  return initToken(tkEOF, "")


func sanitize(v: string): string =
  return v.replace("<", "&lt;").replace(">", "&gt;")


proc convert(pragma: PragmaKind, file: string, path: string) =
  let text = readFile(file)
  var
    lexer = initLexer(file, text)
    author = ""
    date = ""

  if getNextToken(lexer).kind != tkBar:
    error(lexer, "Expected --- at start")

  proc parse_keyval(key: string): string = 
    var token = getNextToken(lexer)
    if token.kind != tkText:
      error(lexer, "head: expected text")
    if token.value != key:
      error(lexer, &"Expected {key}, got {token.value}")
    token = getNextToken(lexer)
    if token.kind != keyval:
      error(lexer, "head: expected keyval")
    return token.value
      
  let title = parse_keyval("title")

  if pragma == blogType:
    author = parse_keyval("author")
    date = parse_keyval("date")

  if getNextToken(lexer).kind != tkBar:
    error(lexer, "head: expected end ---")

  var output = ""
  if pragma == blogType:
    output = &"""{{{{ comp.header "{title}" }}}}
<body>
{{{{ comp.nav }}}}
<section class="section">
<div class="container">
    <h1>{title}</h1>
    <p class="author-date">{author}&nbsp;&nbsp;&nbsp;{date}</p>
"""
  else:
    output = &"""{{{{ comp.header "{title}" }}}}
<body>
{{{{ comp.nav }}}}
<section class="section">
<div class="container">
    <h2 class="left">{title}</h2>
"""

  let f = open(path, fmWrite)
  f.write(output)

  let blocks: seq[TokenKind] = @[tkText, tkH1, tkH2, tkH3, tkList, tkUl]

  proc toTag(t: TokenKind): string =
    if t == tkText:
      result = "p"
    elif t == tkH1:
      result = "h1"
    elif t == tkH2:
      result = "h2"
    elif t == tkH3:
      result = "h3"
    elif t == tkTick:
      result = "code"
    elif t == tkList:
      result = "li"
    elif t == tkUl:
      result = "ul"
    else:
      error(lexer, "toTag got bad value")

  var obj = getNextToken(lexer)
  var ends: seq[TokenKind] = @[]

  proc writeEnd() =
    if len(ends) > 0:
      if ends[^1] in blocks:
        if ends[^1] == tkUl:
          f.write(&"    </{toTag(ends[^1])}>\n")
        else:
          f.write(&"</{toTag(ends[^1])}>\n")
      else:
        f.write(&"</{toTag(ends[^1])}>")
      discard ends.pop()

  while obj.kind != tkEOF:
    if obj.kind in @[tkH1, tkH2, tkH3]:
      ends.add(obj.kind)
      f.write(&"    <{toTag(ends[^1])}>")
    elif obj.kind == tkTick:
      if len(ends) == 0:
        f.write("    <p>")
        ends.add(tkText)

      f.write(&"<code>{sanitize(obj.value)}</code>")
    elif obj.kind == tkText:
      if len(ends) > 0:
        f.write(sanitize(obj.value))
      else:
        f.write(&"    <p>{sanitize(obj.value)}")
        ends.add(obj.kind)
    elif obj.kind == tkList:
      if len(ends) == 0:
        f.write("    <ul>\n")
        ends.add(tkUl)

      f.write("        <li>")
      ends.add(tkList)

    elif obj.kind == tkBlock:
      f.write("    <pre><code>")
      obj = getNextToken(lexer)
      var has_text = false
      while obj.kind != tkEOF and obj.kind != tkBlock:
        if len(ends) > 0:
          error(lexer, "code block must not be indented")
        if obj.kind == tkH1:
          obj = getNextToken(lexer)
          f.write(&"<i># {sanitize(obj.value).strip()}</i>")
          has_text = true
        elif obj.kind == tkText:
          f.write(sanitize(obj.value))
          has_text = true
        elif obj.kind == tkNewline and has_text:
          f.write("\n")
        obj = getNextToken(lexer)

      f.write("</pre></code>\n")
    elif obj.kind == tkLink:
      var link_text = sanitize(obj.value)
      obj = getNextToken(lexer)
      f.write(&"<a href=\"{obj.value}\">{link_text}</a>")
    elif obj.kind == tkBar:
      f.write("    <hr>\n")
    elif obj.kind == tkNewline:
      writeEnd()
    else:
      error(lexer, &"unexpected obj.kind: {obj.kind}")

    obj = getNextToken(lexer)

  while len(ends) > 0:
    writeEnd()

  f.write("</div>\n</section>\n</body>\n</html>\n")
  f.close()

for file in walkFiles("src/blog/*.md"):
  convert(blogType, file, file.changeFileExt("html"))

for file in walkFiles("src/docs/subcommands/*.md"):
  convert(explainerType, file, file.changeFileExt("html"))
