import strutils
import std/os
import std/strformat
import sequtils

func shouldProcessFile(path: string): bool =
  if path.endsWith(".DS_Store"):
    return false

  let ext = path.splitFile().ext.toLowerAscii()
  return ext notin [".webp", ".png", ".jpeg", ".jpg", ".svg"]

proc parseTemplate(content: string, compName: string, compContent: string): string =
  var newContent = content
  var startIdx = 0
  while true:
    let openIdx = newContent.find("{{ " & compName, startIdx)
    if openIdx == -1:
      break
    let closeIdx = newContent.find(" }}", openIdx)
    if closeIdx == -1 and openIdx != -1:
      stderr.writeLine("error! Unclosed template for " & compName)
      quit(1)
    if closeIdx == -1:
      break

    let fullMatch = newContent[openIdx .. closeIdx + 2]
    let argsStr = newContent[openIdx + compName.len + 3 .. closeIdx - 1].strip()
    let args = argsStr.split('"').filterIt(it.strip() != "")

    var replacedContent = compContent
    for i, arg in args:
      replacedContent = replacedContent.replace("{{ $" & $(i+1) & " }}", arg)

    newContent = newContent.replace(fullMatch, replacedContent)
    startIdx = openIdx + replacedContent.len

  return newContent

proc processFile(path: string) =
  if not shouldProcessFile(path):
    return

  var content = readFile(path)

  for kind, comp in walkDir("components"):
    let compName = comp.extractFilename().changeFileExt("")
    if kind == pcFile and not compName.startsWith("."):
      let compContent = readFile(comp).strip()
      content = parseTemplate(content, compName, compContent)
  
  var outputPath = path
  if path.endsWith("index.html"):
    outputPath = path
  elif path.endsWith(".html"):
    outputPath = path.splitFile().dir / path.splitFile().name

  writeFile(outputPath, content)
  
  if outputPath != path:
    removeFile(path)
    echo "Processed and renamed: ", path, " -> ", outputPath
  else:
    echo "Processed: ", path

proc processDirectory(dir: string) =
  for kind, path in walkDir(dir):
    if kind == pcFile:
      processFile(path)
    elif kind == pcDir:
      processDirectory(path)

################################
#  Markdown -> HTML converter  #
################################

type
  PragmaKind = enum
    normalType,
    blogType,

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
    langName: string
    pos: int
    line: int
    col: int

func initLexer(name: string, text: string): Lexer =
  return Lexer(name: name, text: text, currentChar: text[0],
               state: startState, langName: "", pos: 0, line: 1, col: 1)

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
  return (if peakPos > len(self.text) - 1: '\0' else: self.text[peakPos])

func longPeek(self: Lexer, pos: int): char =
  let peakPos = self.pos + pos
  return (if peakPos > len(self.text) - 1: '\0' else: self.text[peakPos])

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

        var langName = ""
        while not (self.currentChar in @['\n', '\0']):
          langName &= self.currentChar
          self.advance()

        self.langName = langName
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

func paintJson(v: string): string =
  # paint TypeScript code one line at a time.
  let myInput = sanitize(v)
  var i = 0
  var old_i = -1

  while i < len(myInput):
    while true:
      if myInput[i ..< i + 2] == "//":
        i += 2
        var bar = ""
        while i < len(myInput):
          bar &= myInput[i]
          i += 1

        result &= "<span class=\"comment\">//" & bar & "</span>"

      if myInput[i] == '"':
        i += 1
        var bar = ""
        while myInput[i] != '"':
          bar &= myInput[i]
          i += 1

        i += 1
        result &= "<span class=\"string\">\"" & bar & "\"</span>"

      for bar in @[",", ":"]:
        if myInput[i .. ^1].startsWith(bar):
          result &= "<span class=\"terminator\">" & bar & "</span>"
          i += len(bar)

      if old_i == i:
        break

      old_i = i

    result &= myInput[i]
    i += 1


func paintTS(v: string): string =
  # paint TypeScript code one line at a time.
  let myInput = sanitize(v)
  var i = 0
  var old_i = -1

  while i < len(myInput):
    while true:
      if myInput[i ..< i + 2] == "//":
        i += 2
        var bar = ""
        while i < len(myInput):
          bar &= myInput[i]
          i += 1

        result &= "<span class=\"comment\">//" & bar & "</span>"

      if myInput[i] == '"':
        i += 1
        var bar = ""
        while myInput[i] != '"':
          bar &= myInput[i]
          i += 1

        i += 1
        result &= "<span class=\"string\">\"" & bar & "\"</span>"

      for bar in @["&lt;", "&gt;"]:
        if myInput[i .. ^1].startsWith(bar):
          result &= bar
          i += len(bar)

      for bar in @["interface"]:
        if myInput[i .. ^1].startsWith(bar):
          result &= "<span class=\"keyword\">" & bar & "</span>"
          i += len(bar)

      for bar in @[":", ",", ";"]:
        if myInput[i .. ^1].startsWith(bar):
          result &= "<span class=\"terminator\">" & bar & "</span>"
          i += len(bar)

      for bar in @["string", "number", "Array", "Chunk"]:
        if myInput[i .. ^1].startsWith(bar):
          result &= "<span class=\"type-primitive\">" & bar & "</span>"
          i += len(bar)

      if old_i == i:
        break

      old_i = i

    result &= myInput[i]
    i += 1


func paintPython(v: string): string =
  # paint Python code one line at a time.
  let myInput = sanitize(v)
  var i = 0
  var old_i = -1

  while i < len(myInput):
    while true:
      if myInput[i] == '"':
        i += 1
        var bar = ""
        while myInput[i] != '"':
          bar &= myInput[i]
          i += 1

        i += 1
        result &= "<span class=\"string\">\"" & bar & "\"</span>"

      for bar in @["&lt;", "&gt;", "dataclass"]:
        if myInput[i .. ^1].startsWith(bar):
          result &= bar
          i += len(bar)

      for bar in @["def", "class"]:
        if myInput[i .. ^1].startsWith(bar):
          result &= "<span class=\"keyword\">" & bar & "</span>"
          i += len(bar)

      for bar in @["if", "from", "import"]:
        if myInput[i .. ^1].startsWith(bar):
          result &= "<span class=\"keyword-import\">" & bar & "</span>"
          i += len(bar)

      for bar in @[":", ",", "->"]:
        if myInput[i .. ^1].startsWith(bar):
          result &= "<span class=\"terminator\">" & bar & "</span>"
          i += len(bar)

      for bar in @["bool", "int", "float", "str", "list", "tuple", "Literal"]:
        if myInput[i .. ^1].startsWith(bar):
          result &= "<span class=\"type-primitive\">" & bar & "</span>"
          i += len(bar)

      for bar in @["and", "or"]:
        if myInput[i .. ^1].startsWith(bar):
          result &= "<span class=\"operator\">" & bar & "</span>"
          i += len(bar)

      if old_i == i:
        break

      old_i = i

    result &= myInput[i]
    i += 1


func paintPalet(v: string): string =
  let myInput = v
  var i = 0
  var old_i = -1

  while i < len(myInput):
    while true:
      if myInput[i] == ';':
        i += 1
        var bar = ""
        while i < len(myInput):
          bar &= myInput[i]
          i += 1

        result &= "<span class=\"comment\">;" & bar.sanitize & "</span>"

      if myInput[i] == '"':
        i += 1
        var bar = ""
        while myInput[i] != '"':
          bar &= myInput[i]
          i += 1

        i += 1
        result &= "<span class=\"string\">\"" & bar.sanitize & "\"</span>"

      for bar in @["define/c", "define", "let"]:
        if myInput[i .. ^1].startsWith(bar):
          result &= "<span class=\"keyword\">" & bar & "</span>"
          i += len(bar)

      for bar in @["when", "if"]:
        if myInput[i .. ^1].startsWith(bar):
          result &= "<span class=\"keyword-import\">" & bar & "</span>"
          i += len(bar)

      for bar in @["map", "lambda"]:
        if myInput[i .. ^1].startsWith(bar):
          result &= "<span class=\"function-name\">" & bar & "</span>"
          i += len(bar)

      for bar in @[".", "->"]:
        if myInput[i .. ^1].startsWith(bar):
          result &= "<span class=\"terminator\">" & bar.sanitize & "</span>"
          i += len(bar)

      for bar in @["bool?", "int?", "float?", "nat?", "str?", "list?", "threshold?"]:
        if myInput[i .. ^1].startsWith(bar):
          result &= "<span class=\"type-primitive\">" & bar.sanitize & "</span>"
          i += len(bar)

      for bar in @["and", "or", "equal?", ">=", "<=", "=", ">", "<", "/"]:
        if myInput[i .. ^1].startsWith(bar):
          result &= "<span class=\"operator\">" & bar.sanitize & "</span>"
          i += len(bar)

      if old_i == i:
        break

      old_i = i

    result &= myInput[i]
    i += 1


proc convert(pragma: PragmaKind, file: string, path: string) =
  let text = readFile(file)
  var
    lexer = initLexer(file, text)
    author = ""
    date = ""
    desc = ""

  if getNextToken(lexer).kind != tkBar:
    error(lexer, "Expected --- at start")

  proc parse_keyval(key: string): string =
    var token = getNextToken(lexer)
    if token.kind != tkText:
      lexer.error("head: expected text")

    if token.value != key:
      lexer.error(&"Expected {key}, got {token.value}")

    token = getNextToken(lexer)
    if token.kind != keyval:
      lexer.error("head: expected keyval")

    return token.value

  let title = parse_keyval("title")

  if pragma == blogType:
    author = parse_keyval("author")
    date = parse_keyval("date")
    desc = parse_keyval("desc")

  if getNextToken(lexer).kind != tkBar:
    lexer.error("head: expected end ---")

  let f = open(path, fmWrite)

  f.write(&"""
<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1.0">
  <title>{title}</title>""")

  if desc != "no-index":
    f.write(&"""

  <meta property="og:title" content="{title}">""")

  if desc != "" and desc != "no-index":
    f.write(&"\n  <meta name=\"description\" content=\"{desc}\">")

  if desc != "no-index":
    var url = path.replace("src/", "")
    if url.endswith("/index.html"):
      url = url.replace("/index.html", "")
    else:
      url = url.replace(".html", "")
    f.write(&"""

  <link rel="canonical" href="https://auto-editor.com/{url}">
  <meta property="og:url" content="https://auto-editor.com/{url}">""")
  else:
    f.write("\n  <meta name=\"robots\" content=\"noindex\">")

  f.write(&"""

  <link rel="stylesheet" href="/style.css?v=1.12.0">
  <link rel="apple-touch-icon" sizes="180x180" href="/favicon/apple-touch-icon.png">
  <link rel="icon" type="image/png" sizes="32x32" href="/favicon/favicon-32x32.png">
  <link rel="icon" type="image/png" sizes="16x16" href="/favicon/favicon-16x16.png">
  <link rel="manifest" href="/favicon/site.webmanifest">
</head>
<body>
{{{{ nav }}}}
<section class="section">
<div class="container">
""")

  if pragma == blogType:
    f.write(&"""
    <h1>{title}</h1>
    <p class="author-date">{author}&nbsp;&nbsp;&nbsp;{date}</p>
""")

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
          if lexer.langName == "ts":
            f.write(paintTS(obj.value))
          elif lexer.langName == "json":
            f.write(paintJson(obj.value))
          elif lexer.langName == "python":
            f.write(paintPython(obj.value))
          elif lexer.langName == "palet":
            f.write(paintPalet(obj.value))
          else:
            f.write(sanitize(obj.value))
          has_text = true
        elif obj.kind == tkNewline and has_text:
          f.write("\n")
        obj = getNextToken(lexer)

      f.write("</pre></code>\n")
    elif obj.kind == tkLink:
      if len(ends) == 0:
        f.write("    <p>")
        ends.add(tkText)
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

  removeFile file


proc main() =
  convert(normalType, "public/blog/index.md", "public/blog/index.html")
  convert(normalType, "public/ref/index.md", "public/ref/index.html")
  for file in walkFiles("public/blog/*.md"):
    convert(blogType, file, file.changeFileExt("html"))

  for file in walkFiles("public/docs/*.md"):
    convert(normalType, file, file.changeFileExt("html"))

  for file in walkFiles("public/docs/subcommands/*.md"):
    convert(normalType, file, file.changeFileExt("html"))

  processDirectory("public")
  echo "done building"

main()
