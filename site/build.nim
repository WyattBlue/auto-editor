import strutils
import std/strformat

type
  TokenKind = enum
    tk_bar,
    tk_m_col,
    tk_h1,
    tk_h2,
    tk_h3,
    tk_newline,
    tk_text,
    tk_tick,
    tk_list,
    tk_block,
    tkEOF,
  Token = ref object
    kind: TokenKind
    value: string


  ObjectKind = enum
    obj_keyval,
    obj_text,
    obj_h1,
    obj_h2,
    obj_h3,
    obj_newline,
    obj_tick,
    obj_ul,
    obj_list,
    obj_eof,
  Object = ref object
    kind: ObjectKind
    value: string

proc error(msg: string) =
  write(stderr, msg)
  system.quit(1)

let text = readFile("src/blog/source.md")

## LEXER
var
  pos = 0
  line = 1
  col = 1
  current_char = text[0]

proc advance() = 
  pos += 1
  if pos > len(text) - 1:
    current_char = '\0'
  else:
    if current_char == '\n':
      line += 1
      col = 1
    else:
      col += 1

    current_char = text[pos]

proc peek(): char = 
  let peak_pos = pos + 1
  if peak_pos > len(text) - 1:
    return '\0'
  else:
    return text[peak_pos]

proc make_token(kind: TokenKind, value: string): Token =
  echo kind, " \"", value, "\""
  return Token(kind: kind, value: value)


proc get_next_token(in_m: bool): Token = 
  var rod = ""
  var levels = 0
  while current_char != '\0':
    if current_char == '\n':
      advance()
      return make_token(tk_newline, "")

    if not in_m and current_char == '`':
      while current_char == '`':
        levels += 1
        advance()

      if levels == 1:
        return make_token(tk_tick, "")
      elif levels == 3:
        return make_token(tk_block, "")
      elif levels != 0:
        error(&"Wrong number of `s, ({levels})")

    rod = rod & current_char

    if in_m and peek() == ':':
      advance()  # Go to `:`
      advance()  # then skip the space
      advance()
      return make_token(tk_m_col, rod)

    if (in_m and rod == "---"):
      advance()
      advance() 
      return make_token(tk_bar, "")

    if (not in_m and peek() == '`') or peek() == '\n':
      advance()
      if rod.strip() == "":
        continue
      else:
        return make_token(tk_text, rod)

    levels = 0
    
    if col == 1 and current_char == ' ' and peek() == '*':
      advance()
      advance()
      advance()
      return make_token(tk_list, "")

    if current_char == '#' and col == 1:
      while current_char == '#':
        levels += 1
        advance()
      
      if current_char != ' ':
        error("Expected space after header")
      advance()

      if levels == 3:
        return make_token(tk_h3, "")
      elif levels == 2:
        return make_token(tk_h2, "")
      elif levels == 1:
        return make_token(tk_h1, "")
      elif levels != 0:
        error("Too many #s")


    advance()

  return make_token(tkEOF, "")

## PARSER
  
var
  start_head = true
  in_head = true
  current_token = Token(kind: tk_text, value:"") # Like a `None` value

proc eat(kind: TokenKind, in_head: bool) = 
  current_token = get_next_token(in_head)
  if current_token.kind != kind:
    error(&"{line}:{col} Expected {kind}, got {current_token.kind} {current_token.value}")

proc make_obj(kind: ObjectKind, value: string): Object =
#  echo kind, " \"", value, "\""
  return Object(kind: kind, value: value)

proc expr(): Object =
  while current_token.kind != tkEOF:
    current_token = get_next_token(in_head)

    if start_head:
      if current_token.kind != tk_bar:
        error("Expected --- at start")
      else:
        start_head = false
        continue

    if in_head:
      if current_token.kind == tk_bar:
        in_head = false
        continue

      eat(tk_text, in_head)
      let value = current_token.value
      eat(tk_newline, in_head)
      return make_obj(obj_key_val, value)

    if current_token.kind == tk_h3:
      return make_obj(obj_h3, "")

    if current_token.kind == tk_h2:
      return make_obj(obj_h2, "")

    if current_token.kind == tk_h1:
      return make_obj(obj_h1, "")

    if current_token.kind == tk_newline:
      return make_obj(obj_newline, "")

    if current_token.kind == tk_tick:
      eat(tk_text, in_head)
      let text = current_token.value
      if text == "":
        error("tick text is blank")
      eat(tk_tick, in_head)
      return make_obj(obj_tick, text)

    if current_token.kind == tk_list:
      return make_obj(obj_list, "")
    
    if current_token.value != "":
      return make_obj(obj_text, current_token.value)

  return make_obj(obj_eof, "")


proc sanitize(v: string): string =
  return v.replace("<", "&lt;").replace(">", "&gt;")

proc convert(path: string) =
  let
    title = expr().value
    author = expr().value
    date = expr().value
    f = open(path, fmWrite)
  var output = &"""{{{{ comp.header "{title}" }}}}
<body>
{{{{ comp.nav }}}}
<section class="section">
<div class="container">
    <h1>{title}</h1>
    <p class="author">Author: <b>{author}</b></p>
    <p class="date">Date: <b>{date}</b></p>
    <hr>
"""

  f.write(output)

  let blocks: seq[ObjectKind] = @[obj_text, obj_h1, obj_h2, obj_h3, obj_list, obj_ul]
  let headers: seq[ObjectKind] = @[obj_h1, obj_h2, obj_h3, obj_list]

  proc to_tag(t: ObjectKind): string = 
    if t == obj_text:
      result = "p"
    elif t == obj_h1:
      result = "h1"
    elif t == obj_h2:
      result = "h2"
    elif t == obj_h3:
      result = "h3"
    elif t == obj_tick:
      result = "code"
    elif t == obj_list:
      result = "li"
    elif t == obj_ul:
      result = "ul"
    else:
      result = "unknown"

  var obj = expr()
  var ends: seq[ObjectKind] = @[]

  proc write_end() = 
    if len(ends) > 0:
      if ends[^1] in blocks:
        if ends[^1] == obj_ul:
          f.write(&"    </{to_tag(ends[^1])}>\n")
        else:
          f.write(&"</{to_tag(ends[^1])}>\n")
      else:
        f.write(&"</{to_tag(ends[^1])}>")
      let _ = ends.pop()

  while obj.kind != obj_eof:
    if obj.kind in @[obj_h1, obj_h2, obj_h3]:
      ends.add(obj.kind)
      f.write(&"    <{to_tag(ends[^1])}>")
    elif obj.kind == obj_tick:
      f.write(&"<code>{sanitize(obj.value)}</code>")
    elif obj.kind == obj_text:
      if len(ends) > 0:
        f.write(sanitize(obj.value))
      else:
        f.write(&"    <p>{sanitize(obj.value)}")
        ends.add(obj.kind)
    elif obj.kind == obj_list:
      if len(ends) == 0:
        f.write("    <ul>\n")
        ends.add(obj_ul)

      f.write("        <li>")
      ends.add(obj.kind)
    elif obj.kind == obj_newline:
      write_end()
    else:
      error("Very bad!")

    obj = expr()

  while len(ends) > 0:
    write_end()

  f.write("</div>\n</section>\n</body>\n</html>\n")
  f.close()

convert("src/blog/source.html")
  
