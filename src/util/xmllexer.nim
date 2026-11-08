## The events of std/parsexml with its default options. parsexml appends
## each character to its token one at a time, which dominates reading large
## timelines; this copies each run at once. Its states, error handling and
## text rules are parsexml's, so a document reads the same, including its
## quirks: whitespace that starts a text run outside character data is
## dropped, attribute values collapse whitespace runs to one space, and a
## NUL byte ends the input. One parsexml bug is left out: it moves the
## space before a '/' in an attribute value to after it.
##
## The file is read a window at a time. An event that ends too near the
## window's end to have seen all it may look at is read again over a larger
## window, so every event sees exactly the bytes it would in the whole file.

import std/unicode

type
  XmlEventKind* = enum
    xmlError, xmlEof, xmlCharData, xmlWhitespace, xmlComment, xmlPI,
    xmlElementStart, xmlElementEnd, xmlElementOpen, xmlAttribute,
    xmlElementClose, xmlCData, xmlEntity, xmlSpecial

  XmlErrorKind = enum
    errNone, errEndOfCDataExpected, errNameExpected, errSemicolonExpected,
    errQmGtExpected, errGtExpected, errEqExpected, errQuoteExpected,
    errEndOfCommentExpected

  LexState = enum
    stateStart, stateNormal, stateCharData, stateAttr, stateEmptyElementTag,
    stateError

  XmlLexer* = object
    f: File
    buf: string # a window of the file, then NULs for lookahead
    dataLen: int # bytes of the file in buf
    offset: int # where in the file buf starts
    eof: bool # whether buf holds the rest of the file
    pos: int
    start: int # where in the file the text begins: past a byte order mark
    a, b, c: string
    kind: XmlEventKind
    err: XmlErrorKind
    state: LexState
    cIsEmpty: bool
    filename: string

const
  errorMessages: array[XmlErrorKind, string] = [
    "no error",
    "']]>' expected",
    "name expected",
    "';' expected",
    "'?>' expected",
    "'>' expected",
    "'=' expected",
    "'\"' or \"'\" expected",
    "'-->' expected",
  ]
  NameStartChar = {'A'..'Z', 'a'..'z', '_', ':', '\128'..'\255'}
  NameChar = {'A'..'Z', 'a'..'z', '0'..'9', '.', '-', '_', ':', '\128'..'\255'}
  # An event reads at most 8 bytes past where it ends, so one that ends
  # this far from the data's end has seen only data.
  padding = 16
  windowSize {.intdefine: "xmlWindowSize".} = 1 shl 20

proc fill(L: var XmlLexer) {.raises: [IOError].} =
  ## Drops what is before `pos` and reads more, at least doubling what is
  ## kept so an event of any length eventually fits.
  let keep = L.dataLen - L.pos
  if keep > 0: moveMem(addr L.buf[0], addr L.buf[L.pos], keep)
  L.offset += L.pos
  L.pos = 0
  let want = max(windowSize, keep)
  L.buf.setLen(keep + want + padding)
  let got = L.f.readBuffer(addr L.buf[keep], want)
  L.dataLen = keep + got
  L.eof = got < want
  L.buf.setLen(L.dataLen + padding)
  zeroMem(addr L.buf[L.dataLen], padding)

proc open*(L: var XmlLexer, path: string) {.raises: [IOError].} =
  if not L.f.open(path):
    raise newException(IOError, "cannot open: " & path)
  L.fill()
  while L.dataLen < 3 and not L.eof: L.fill()
  if L.buf[0] == '\xEF' and L.buf[1] == '\xBB' and L.buf[2] == '\xBF':
    L.pos = 3
  L.start = L.pos
  L.filename = path
  L.state = stateStart
  L.kind = xmlError
  L.cIsEmpty = true

func kind*(L: XmlLexer): XmlEventKind {.inline.} = L.kind

template charData*(L: XmlLexer): string = L.a
template elementName*(L: XmlLexer): string = L.a
template entityName*(L: XmlLexer): string = L.a
template attrKey*(L: XmlLexer): string = L.a
template attrValue*(L: XmlLexer): string = L.b

proc close*(L: var XmlLexer) =
  if L.f != nil: L.f.close()
  L.f = nil

proc lineCol(L: XmlLexer): (int, int) =
  ## The line, from 1, and column of the position, counting lines as
  ## parsexml does: CR LF, CR and LF each end one. Only errors need these,
  ## so the file is read again from the start rather than tracked.
  let target = L.offset + L.pos
  var line = 1
  var lineStart = L.start
  var afterCR = false
  try:
    let resume = L.f.getFilePos()
    defer: L.f.setFilePos(resume)
    L.f.setFilePos(L.start)
    var chunk = newString(1 shl 16)
    var at = L.start
    while at < target:
      let n = L.f.readBuffer(addr chunk[0], min(chunk.len, target - at))
      if n <= 0: break
      for i in 0 ..< n:
        let ch = chunk[i]
        if ch == '\L' and afterCR:
          lineStart = at + i + 1
        elif ch in {'\c', '\L'}:
          inc line
          lineStart = at + i + 1
        afterCR = ch == '\c'
      at += n
  except IOError:
    discard
  (line, target - lineStart)

proc errorMsg*(L: XmlLexer, msg: string): string =
  let (line, col) = L.lineCol
  L.filename & "(" & $line & ", " & $col & ") Error: " & msg

proc errorMsg*(L: XmlLexer): string =
  L.errorMsg(errorMessages[L.err])

proc markError(L: var XmlLexer, kind: XmlErrorKind) {.inline.} =
  L.err = kind
  L.state = stateError

proc addRun(dest: var string, buf: string, first, last: int) {.inline.} =
  ## Appends buf[first ..< last].
  let n = last - first
  if n > 0:
    let old = dest.len
    dest.setLen(old + n)
    copyMem(addr dest[old], unsafeAddr buf[first], n)

func skipNewline(L: XmlLexer, pos: int): int {.inline.} =
  ## Past the newline at `pos`, CR LF counting as one.
  if L.buf[pos] == '\c' and L.buf[pos + 1] == '\L': pos + 2 else: pos + 1

proc parseCDATA(L: var XmlLexer) =
  var pos = L.pos + len("<![CDATA[")
  while true:
    let first = pos
    while L.buf[pos] notin {']', '\0', '\c'}: inc pos
    L.a.addRun(L.buf, first, pos)
    case L.buf[pos]
    of ']':
      if L.buf[pos + 1] == ']' and L.buf[pos + 2] == '>':
        inc(pos, 3)
        break
      L.a.add ']'
      inc pos
    of '\0':
      L.markError(errEndOfCDataExpected)
      break
    else: # CR
      pos = L.skipNewline(pos)
      L.a.add '\L'
  L.pos = pos
  L.kind = xmlCData

proc parseComment(L: var XmlLexer) =
  var pos = L.pos + len("<!--")
  while true:
    while L.buf[pos] notin {'-', '\0'}: inc pos
    if L.buf[pos] == '\0':
      L.markError(errEndOfCommentExpected)
      break
    if L.buf[pos + 1] == '-' and L.buf[pos + 2] == '>':
      inc(pos, 3)
      break
    inc pos
  L.pos = pos
  L.kind = xmlComment

proc parseWhitespace(L: var XmlLexer, skip = false) =
  var pos = L.pos
  while true:
    case L.buf[pos]
    of ' ', '\t':
      if not skip: L.a.add L.buf[pos]
      inc pos
    of '\c', '\L':
      pos = L.skipNewline(pos)
      if not skip: L.a.add '\L'
    else:
      break
  L.pos = pos

proc parseName(L: var XmlLexer, dest: var string) =
  var pos = L.pos
  if L.buf[pos] in NameStartChar:
    inc pos
    while L.buf[pos] in NameChar: inc pos
    dest.addRun(L.buf, L.pos, pos)
    L.pos = pos
  else:
    L.markError(errNameExpected)

proc parseEntity(L: var XmlLexer, dest: var string) =
  var pos = L.pos + 1
  L.kind = xmlCharData
  if L.buf[pos] == '#':
    var r = 0
    inc pos
    if L.buf[pos] == 'x':
      inc pos
      while true:
        case L.buf[pos]
        of '0'..'9': r = (r shl 4) or (ord(L.buf[pos]) - ord('0'))
        of 'a'..'f': r = (r shl 4) or (ord(L.buf[pos]) - ord('a') + 10)
        of 'A'..'F': r = (r shl 4) or (ord(L.buf[pos]) - ord('A') + 10)
        else: break
        inc pos
    else:
      while L.buf[pos] in {'0'..'9'}:
        r = r * 10 + (ord(L.buf[pos]) - ord('0'))
        inc pos
    dest.add toUTF8(Rune(r))
  elif L.buf[pos] == 'l' and L.buf[pos + 1] == 't' and L.buf[pos + 2] == ';':
    dest.add '<'
    inc(pos, 2)
  elif L.buf[pos] == 'g' and L.buf[pos + 1] == 't' and L.buf[pos + 2] == ';':
    dest.add '>'
    inc(pos, 2)
  elif L.buf[pos] == 'a' and L.buf[pos + 1] == 'm' and L.buf[pos + 2] == 'p' and
      L.buf[pos + 3] == ';':
    dest.add '&'
    inc(pos, 3)
  elif L.buf[pos] == 'a' and L.buf[pos + 1] == 'p' and L.buf[pos + 2] == 'o' and
      L.buf[pos + 3] == 's' and L.buf[pos + 4] == ';':
    dest.add '\''
    inc(pos, 4)
  elif L.buf[pos] == 'q' and L.buf[pos + 1] == 'u' and L.buf[pos + 2] == 'o' and
      L.buf[pos + 3] == 't' and L.buf[pos + 4] == ';':
    dest.add '"'
    inc(pos, 4)
  else:
    L.pos = pos
    var name = ""
    L.parseName(name)
    pos = L.pos
    if L.err != errNameExpected and L.buf[pos] == ';':
      L.kind = xmlEntity
    else:
      dest.add '&'
    dest.add name
  if L.buf[pos] == ';':
    inc pos
  else:
    L.err = errSemicolonExpected # benign, as in parsexml: the state stays
  L.pos = pos

proc parsePI(L: var XmlLexer) =
  inc(L.pos, len("<?"))
  L.parseName(L.a)
  var pos = L.pos
  while true:
    while L.buf[pos] notin {'?', '\0'}: inc pos
    if L.buf[pos] == '\0':
      L.markError(errQmGtExpected)
      break
    if L.buf[pos + 1] == '>':
      inc(pos, 2)
      break
    inc pos
  L.pos = pos
  L.kind = xmlPI

proc parseSpecial(L: var XmlLexer) =
  ## Things that start with `<!`.
  var pos = L.pos + 2
  var opentags = 0
  while true:
    case L.buf[pos]
    of '\0':
      L.markError(errGtExpected)
      break
    of '<':
      inc opentags
      inc pos
    of '>':
      inc pos
      if opentags <= 0: break
      dec opentags
    else:
      inc pos
  L.pos = pos
  L.kind = xmlSpecial

proc parseTag(L: var XmlLexer) =
  inc L.pos
  L.parseName(L.a)
  # Without a name, the '<' is text.
  if L.a.len == 0:
    L.kind = xmlCharData
    L.a.add '<'
    return
  L.parseWhitespace(skip = true)
  if L.buf[L.pos] in NameStartChar:
    L.kind = xmlElementOpen
    L.state = stateAttr
    L.c.setLen 0
    L.c.add L.a
    L.cIsEmpty = false
  else:
    L.kind = xmlElementStart
    let slash = L.buf[L.pos] == '/'
    if slash: inc L.pos
    if slash and L.buf[L.pos] == '>':
      inc L.pos
      L.state = stateEmptyElementTag
      L.c.setLen 0
      L.cIsEmpty = true
    elif L.buf[L.pos] == '>':
      inc L.pos
    else:
      L.markError(errGtExpected)

proc parseEndTag(L: var XmlLexer) =
  inc(L.pos, 2)
  L.parseName(L.a)
  L.parseWhitespace(skip = true)
  if L.buf[L.pos] == '>':
    inc L.pos
  else:
    L.markError(errGtExpected)
  L.kind = xmlElementEnd

proc parseAttribute(L: var XmlLexer) =
  L.kind = xmlAttribute
  L.a.setLen 0
  L.b.setLen 0
  L.parseName(L.a)
  if L.a.len == 0:
    L.markError(errGtExpected)
    return

  L.parseWhitespace(skip = true)
  if L.buf[L.pos] != '=':
    L.markError(errEqExpected)
    return

  inc L.pos
  L.parseWhitespace(skip = true)

  var pos = L.pos
  if L.buf[pos] in {'\'', '"'}:
    let quote = L.buf[pos]
    var pendingSpace = false
    inc pos
    while true:
      let first = pos
      while L.buf[pos] notin {'\0', '&', ' ', '\t', '\c', '\L', quote}: inc pos
      if pos > first:
        if pendingSpace:
          L.b.add ' '
          pendingSpace = false
        L.b.addRun(L.buf, first, pos)
      case L.buf[pos]
      of '\0':
        L.markError(errQuoteExpected)
        break
      of '&':
        if pendingSpace:
          L.b.add ' '
          pendingSpace = false
        L.pos = pos
        L.parseEntity(L.b)
        L.kind = xmlAttribute # parseEntity sets the kind
        pos = L.pos
      of ' ', '\t':
        pendingSpace = true
        inc pos
      of '\c', '\L':
        pos = L.skipNewline(pos)
        pendingSpace = true
      else: # the quote
        inc pos
        break
  else:
    L.markError(errQuoteExpected)
    # As parsexml, guess what was meant.
    let first = pos
    while L.buf[pos] != '>' and L.buf[pos] > ' ': inc pos
    L.b.addRun(L.buf, first, pos)
  L.pos = pos
  L.parseWhitespace(skip = true)

proc parseCharData(L: var XmlLexer) =
  var pos = L.pos
  while true:
    let first = pos
    while L.buf[pos] notin {'\0', '<', '&', '\c'}: inc pos
    L.a.addRun(L.buf, first, pos)
    if L.buf[pos] != '\c': break
    pos = L.skipNewline(pos)
    L.a.add '\L'
  L.pos = pos
  L.kind = xmlCharData

proc rawGetTok(L: var XmlLexer) =
  L.kind = xmlError
  L.a.setLen 0
  let pos = L.pos
  case L.buf[pos]
  of '<':
    case L.buf[pos + 1]
    of '/':
      L.parseEndTag()
    of '!':
      if L.buf[pos + 2] == '[' and L.buf[pos + 3] == 'C' and
          L.buf[pos + 4] == 'D' and L.buf[pos + 5] == 'A' and
          L.buf[pos + 6] == 'T' and L.buf[pos + 7] == 'A' and
          L.buf[pos + 8] == '[':
        L.parseCDATA()
      elif L.buf[pos + 2] == '-' and L.buf[pos + 3] == '-':
        L.parseComment()
      else:
        L.parseSpecial()
    of '?':
      L.parsePI()
    else:
      L.parseTag()
  of ' ', '\t', '\c', '\L':
    L.parseWhitespace()
    L.kind = xmlWhitespace
  of '\0':
    L.kind = xmlEof
  of '&':
    L.parseEntity(L.a)
  else:
    L.parseCharData()

proc getTok(L: var XmlLexer) =
  while true:
    L.rawGetTok()
    case L.kind
    of xmlComment: discard
    of xmlWhitespace:
      # Whitespace within character data is part of it; otherwise it only
      # separates markup.
      if L.state == stateCharData: break
    else: break

proc trackCharData(L: var XmlLexer) =
  ## Character data continues until markup other than a comment.
  if L.state in {stateNormal, stateCharData}:
    case L.kind
    of xmlCharData, xmlEntity: L.state = stateCharData
    of xmlComment, xmlWhitespace: discard
    else: L.state = stateNormal

proc nextInWindow(L: var XmlLexer) =
  case L.state
  of stateNormal, stateCharData:
    L.getTok()
    L.trackCharData()
  of stateStart:
    L.state = stateNormal
    L.getTok()
    if L.kind == xmlPI and L.a == "xml":
      L.getTok() # the <?xml ?> declaration
    L.trackCharData()
  of stateAttr:
    if L.buf[L.pos] == '>':
      L.kind = xmlElementClose
      inc L.pos
      L.state = stateNormal
    elif L.buf[L.pos] == '/':
      inc L.pos
      if L.buf[L.pos] == '>':
        L.kind = xmlElementClose
        inc L.pos
        L.state = stateEmptyElementTag
      else:
        L.markError(errGtExpected)
    else:
      L.parseAttribute()
  of stateEmptyElementTag:
    L.state = stateNormal
    L.kind = xmlElementEnd
    if not L.cIsEmpty:
      L.a.setLen 0
      L.a.add L.c
  of stateError:
    L.kind = xmlError
    L.state = stateNormal

proc next*(L: var XmlLexer) {.raises: [IOError].} =
  let (kind, err, state) = (L.kind, L.err, L.state)
  while true:
    let pos = L.pos
    L.nextInWindow()
    if L.eof or L.pos + padding <= L.dataLen: return
    # Read the event again from its start, over more of the file. Of what
    # it changed, `c` is set again by the same reading.
    (L.pos, L.kind, L.err, L.state) = (pos, kind, err, state)
    L.fill()
