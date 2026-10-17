import std/strutils

func decodeString*(text: string, `from`, to: uint32): string =
  result = newStringOfCap(int(to - `from`))
  var pos = `from`
  while pos < to:
    if text[pos] == '\\' and pos + 1 < to:
      pos += 1
      case text[pos]
      of 'n': result.add('\n')
      of 't': result.add('\t')
      else: result.add(text[pos]) # \" \\ and others: literal
    else:
      result.add(text[pos])
    pos += 1

func decodeString*(text: string): string =
  text.decodeString(0, uint32(text.len))

func escapeText*(text: string): string =
  for c in text:
    case c
    of '\\', ':', ',': result.add '\\' & c
    of '\n': result.add "\\n"
    else: result.add c

func splitUnescaped*(val: string, sep: char, textOnly = false): seq[string] =
  result = @[""]
  var i = 0
  while i < val.len:
    var escapes = val[i] == '\\' and i + 1 < val.len
    if escapes and textOnly:
      let part = result[^1].strip(trailing = false)
      escapes = part.startsWith("text:") or part.startsWith("add:text:")
    if escapes:
      result[^1].add val[i .. i + 1]
      i += 2
    elif val[i] == sep:
      result.add ""
      i += 1
    else:
      result[^1].add val[i]
      i += 1
