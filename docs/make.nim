import strutils
import std/os
import std/strformat
import std/osproc
import sequtils

var reload = ""
if paramCount() > 0 and paramStr(1) == "--dev":
  reload = """<script>var bfr = '';
setInterval(function () {
    fetch(window.location).then((response) => {
        return response.text();
    }).then(r => {
        if (bfr != '' && bfr != r) {
            setTimeout(function() {
                window.location.reload();
            }, 1000);
        }
        else {
            bfr = r;
        }
    });
}, 1000);</script>"""

func shouldProcessFile(path: string): bool =
  if path.endsWith(".DS_Store"):
    return false

  let ext = path.splitFile().ext.toLowerAscii()
  return ext notin [".avif", ".webp", ".png", ".jpeg", ".jpg", ".svg"]

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

      if self.col == 1 and self.currentChar == ' ' and self.peek() == '-':
        self.advance()
        self.advance()
        return initToken(tkUl, "")

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
  {{{{ init_head }}}}
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
{{{{ head_icon }}}}
<style>
{{{{ core_style }}}}
</style>
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

  let forPandoc = text[lexer.pos..^1]
  f.write(execCmdEx("pandoc --from markdown --to html5", input = forPandoc).output)

  if pragma == blogType:
    f.write("<hr><a href=\"./\">Blog Index</a>\n")
  f.write("</div>\n</section>\n</body>\n</html>\n")
  f.close()

  removeFile file


proc main() =
  convert(normalType, "public/ref/index.md", "public/ref/index.html")
  for file in walkFiles("public/docs/*.md"):
    convert(normalType, file, file.changeFileExt("html"))
  for file in walkFiles("public/docs/subcommands/*.md"):
    convert(normalType, file, file.changeFileExt("html"))

  processDirectory("public")
  echo "done building"

main()
