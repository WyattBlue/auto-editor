import strutils
import std/strformat

type
  TokenKind = enum
    tk_bar,
    tk_keyval,
    tk_text,
    tk_h1,
    tk_h2,
    tk_h3,
    tk_newline,
    tk_tick,
    tk_list,
    tk_ul,
    tk_block,
    tk_link,
    tk_eof,
  Token = ref object
    kind: TokenKind
    value: string

proc error(msg: string) =
  write(stderr, msg)
  system.quit(1)

# error(&"{line}:{col} Expected {kind}, got {actual_kind} {actual_val}")

type
  State = enum
    just_start,
    in_head,
    normal_state,
    link_state,
  Lexer = ref object
    text: string
    current_char: char
    state: State
    pos: int
    line: int
    col: int

proc Lexer_init(text: string): Lexer = 
  return Lexer(text: text, current_char: text[0], state: just_start, pos: 0, line: 1, col: 1)

proc advance(self: Lexer) = 
  self.pos += 1
  if self.pos > len(self.text) - 1:
    self.current_char = '\0'
  else:
    if self.current_char == '\n':
      self.line += 1
      self.col = 1
    else:
      self.col += 1

    self.current_char = self.text[self.pos]

proc peek(self: Lexer): char = 
  let peak_pos = self.pos + 1
  if peak_pos > len(self.text) - 1:
    return '\0'
  else:
    return self.text[peak_pos]

proc make_token(kind: TokenKind, value: string): Token =
#  echo kind, " \"", value, "\""
  return Token(kind: kind, value: value)


proc get_next_token(self: Lexer): Token = 
  var rod = ""
  var levels = 0
  while self.current_char != '\0':
    if self.state == link_state:
      rod = ""
      while self.current_char != ')':
        rod = rod & self.current_char
        advance(self)
      advance(self)
      self.state = normal_state
      return make_token(tk_text, rod)  # return link ref
    if self.current_char == '\n':
      advance(self)
      return make_token(tk_newline, "")

    if self.state == normal_state and self.current_char == '[':  # Handle links
      advance(self)
      rod = ""
      while self.current_char != ']':
        rod = rod & self.current_char 
        advance(self)
      advance(self)
      if self.current_char != '(':
        error("link expected ref")
      advance(self)
      self.state = link_state
      return make_token(tk_link, rod)

    if self.state == normal_state and self.current_char == '`':  # Handle code ticks
      while self.current_char == '`':
        levels += 1
        advance(self)

      if levels == 1:
        rod = ""
        while self.current_char != '`':
          rod = rod & self.current_char
          advance(self)
        advance(self)

        if rod.strip() == "":
          error("Tick can't be blank")

        return make_token(tk_tick, rod)
      elif levels == 3:
        return make_token(tk_block, "")
      elif levels != 0:
        error(&"Wrong number of `s, ({levels})")

    rod = rod & self.current_char

    if self.state == in_head and self.current_char == ':':
      advance(self)  # then go to ` ` 
      while self.current_char == ' ':
        advance(self)

      rod = ""
      while self.current_char != '\n':
        if self.current_char == '\0':
          error("Got EOF on key-value pair")

        if self.current_char != '\n':
          rod = rod & self.current_char

        advance(self)

      advance(self)
      return make_token(tk_keyval, rod)

    if rod == "---":
      advance(self)
      advance(self)
      if self.state == just_start:
        self.state = in_head
      elif self.state == in_head:
        self.state = normal_state
      return make_token(tk_bar, "")

    var break_token = false
    if peek(self) == '\n':
      break_token = true
    elif self.state == normal_state and peek(self) == '`':
      break_token = true
    elif self.state == normal_state and peek(self) == '[':
      break_token = true
    elif self.state == in_head and peek(self) == ':':
      break_token = true

    if break_token:
      advance(self)
      if rod.strip() == "":
        continue
      else:
        return make_token(tk_text, rod)

    levels = 0
    
    if self.col == 1 and self.current_char == ' ' and peek(self) == '*':
      advance(self)
      advance(self)
      advance(self)
      return make_token(tk_list, "")

    if self.current_char == '#' and self.col == 1:
      while self.current_char == '#':
        levels += 1
        advance(self)
      
      if self.current_char != ' ':
        error("Expected space after header")
      advance(self)

      if levels == 3:
        return make_token(tk_h3, "")
      elif levels == 2:
        return make_token(tk_h2, "")
      elif levels == 1:
        return make_token(tk_h1, "")
      elif levels != 0:
        error("Too many #s")

    advance(self)

  return make_token(tk_eof, "")



proc sanitize(v: string): string =
  return v.replace("<", "&lt;").replace(">", "&gt;")


proc convert(text: string, path: string) =
  var lexer = Lexer_init(text)

  if get_next_token(lexer).kind != tk_bar:
    error("Expected --- at start")

  proc parse_keyval(key: string): string = 
    var token = get_next_token(lexer)
    if token.kind != tk_text:
      error("head: expected text")
    if token.value != key:
      error(&"Expected {key}, got {token.value}")
    token = get_next_token(lexer)
    if token.kind != tk_keyval:
      error("head: expected keyval")
    return token.value
      

  let
    title = parse_keyval("title")
    author = parse_keyval("author")
    date = parse_keyval("date")

  if get_next_token(lexer).kind != tk_bar:
    error("head: expected end ---")
  var output = &"""{{{{ comp.header "{title}" }}}}
<body>
{{{{ comp.nav }}}}
<section class="section">
<div class="container">
    <h1>{title}</h1>
    <p class="author">Author: <b>{author}</b></p>
    <p class="date">Date: <b>{date}</b></p>
"""

  let f = open(path, fmWrite)
  f.write(output)

  let blocks: seq[TokenKind] = @[tk_text, tk_h1, tk_h2, tk_h3, tk_list, tk_ul]
  let headers: seq[TokenKind] = @[tk_h1, tk_h2, tk_h3, tk_list]

  proc to_tag(t: TokenKind): string = 
    if t == tk_text:
      result = "p"
    elif t == tk_h1:
      result = "h1"
    elif t == tk_h2:
      result = "h2"
    elif t == tk_h3:
      result = "h3"
    elif t == tk_tick:
      result = "code"
    elif t == tk_list:
      result = "li"
    elif t == tk_ul:
      result = "ul"
    else:
      error("to_tag got bad value")

  var obj = get_next_token(lexer)
  var ends: seq[TokenKind] = @[]

  proc write_end() = 
    if len(ends) > 0:
      if ends[^1] in blocks:
        if ends[^1] == tk_ul:
          f.write(&"    </{to_tag(ends[^1])}>\n")
        else:
          f.write(&"</{to_tag(ends[^1])}>\n")
      else:
        f.write(&"</{to_tag(ends[^1])}>")
      discard ends.pop()

  while obj.kind != tk_eof:
    if obj.kind in @[tk_h1, tk_h2, tk_h3]:
      ends.add(obj.kind)
      f.write(&"    <{to_tag(ends[^1])}>")
    elif obj.kind == tk_tick:
      if len(ends) == 0:
        f.write("    <p>")
        ends.add(tk_text)

      f.write(&"<code>{sanitize(obj.value)}</code>")
    elif obj.kind == tk_text:
      if len(ends) > 0:
        f.write(sanitize(obj.value))
      else:
        f.write(&"    <p>{sanitize(obj.value)}")
        ends.add(obj.kind)
    elif obj.kind == tk_list:
      if len(ends) == 0:
        f.write("    <ul>\n")
        ends.add(tk_ul)

      f.write("        <li>")
      ends.add(tk_list)

    elif obj.kind == tk_block:
      f.write("    <pre><code>")
      obj = get_next_token(lexer)
      while obj.kind != tk_block:
        if len(ends) > 0:
          error("code block must not be indented")
        if obj.kind == tk_h1:
          obj = get_next_token(lexer)
          f.write(&"<i>{sanitize(obj.value)}</i>\n")
        elif obj.kind == tk_text:
          f.write(sanitize(obj.value))
          f.write("\n")
        obj = get_next_token(lexer)

      f.write("</pre></code>\n")
    elif obj.kind == tk_link:
      var link_text = sanitize(obj.value)
      obj = get_next_token(lexer)
      f.write(&"<a href=\"{obj.value}\">{link_text}</a>")
    elif obj.kind == tk_bar:
      f.write("    <hr>\n")
    elif obj.kind == tk_newline:
      write_end()
    else:
      error(&"unexpected obj.kind: {obj.kind}")

    obj = get_next_token(lexer)

  while len(ends) > 0:
    write_end()

  f.write("</div>\n</section>\n</body>\n</html>\n")
  f.close()


var text: string
text = readFile("src/blog/source.md")
convert(text, "src/blog/source.html")
  
text = readFile("src/blog/supporting-davinci-resolve-again.md")
convert(text, "src/blog/supporting-davinci-resolve-again.html")

text = readFile("src/blog/silent-threshold.md")
convert(text, "src/blog/silent-threshold.html")
