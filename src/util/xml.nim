## An XML tree for the editor exporters and the FCP7 importer. std/xmltree
## stores each element's attributes in a StringTable that starts at 64 slots
## (~4 KB), which dominates memory on large timelines; a seq of pairs costs only
## what it holds. Output matches xmltree's `$` except that attributes keep
## insertion order.

import std/[parsexml, streams]
import std/macros except error
import ../log

type
  XmlAttributes* = seq[(string, string)]

  XmlNodeKind* = enum
    xnElement
    xnText
    xnVerbatimText # written without escaping

  XmlNode* = ref object
    kind*: XmlNodeKind
    str: string # the element name, or a text node's text
    attrs*: XmlAttributes
    children: seq[XmlNode]

func newElement*(tag: string): XmlNode =
  XmlNode(str: tag)

func newText*(text: string): XmlNode =
  XmlNode(kind: xnText, str: text)

func newVerbatimText*(text: string): XmlNode =
  XmlNode(kind: xnVerbatimText, str: text)

func newXmlTree*(tag: string, children: openArray[XmlNode],
    attrs: XmlAttributes = @[]): XmlNode =
  XmlNode(str: tag, attrs: attrs, children: @children)

func toXmlAttributes*(pairs: varargs[(string, string)]): XmlAttributes =
  @pairs

func add*(parent, child: XmlNode) =
  parent.children.add child

func len*(n: XmlNode): int =
  ## The number of children.
  n.children.len

func tag*(n: XmlNode): string =
  n.str

iterator items*(n: XmlNode): XmlNode =
  for c in n.children:
    yield c

func attr*(n: XmlNode, name: string): string =
  ## The value of attribute `name`, or "" if `n` has none.
  for (key, val) in n.attrs:
    if key == name: return val
  ""

func innerText*(n: XmlNode): string =
  ## The text of `n` and everything under it, in document order.
  if n.kind != xnElement: return n.str
  for c in n.children:
    result.add c.innerText

macro `<>`*(x: untyped): untyped =
  ## `<>tag(key = value, child)` builds an element, as in std/xmltree.
  if x.kind != nnkCall:
    return newCall(bindSym"newXmlTree", toStrLit(x), newNimNode(nnkBracket))
  var children = newNimNode(nnkBracket)
  var attrs = newNimNode(nnkBracket)
  for i in 1 ..< x.len:
    if x[i].kind == nnkExprEqExpr:
      attrs.add newTree(nnkTupleConstr, newStrLitNode($x[i][0]), x[i][1])
    else:
      children.add x[i]
  result = newCall(bindSym"newXmlTree", newStrLitNode($x[0]), children)
  if attrs.len > 0:
    result.add newCall(bindSym"toXmlAttributes", attrs)

type XmlWriter = object
  f: File # nil when only building a string
  buf: string

const flushSize = 1 shl 16

proc addEscaped(buf: var string, s: string) =
  for c in s:
    case c
    of '<': buf.add "&lt;"
    of '>': buf.add "&gt;"
    of '&': buf.add "&amp;"
    of '"': buf.add "&quot;"
    of '\'': buf.add "&apos;"
    else: buf.add c

proc addEscapedAttr(buf: var string, s: string) =
  # A parser turns a literal tab, line feed or carriage return in an attribute
  # value into a space, so those are written as character references.
  for c in s:
    case c
    of '<': buf.add "&lt;"
    of '>': buf.add "&gt;"
    of '&': buf.add "&amp;"
    of '"': buf.add "&quot;"
    of '\t': buf.add "&#9;"
    of '\n': buf.add "&#10;"
    of '\r': buf.add "&#13;"
    else: buf.add c

func hasText(n: XmlNode): bool =
  for c in n.children:
    if c.kind != xnElement: return true
  false

proc addIndent(buf: var string, indent: int, addNewLines: bool) =
  if addNewLines:
    buf.add '\n'
  for _ in 1 .. indent:
    buf.add ' '

proc write(w: var XmlWriter, n: XmlNode, indent: int, addNewLines,
    lastNodeIsText: bool) {.raises: [IOError].} =
  # Mirrors xmltree's layout: an element holding text keeps all its children on
  # one line, and indentation stops growing at 80 columns.
  case n.kind
  of xnText:
    w.buf.addEscaped n.str
    return
  of xnVerbatimText:
    w.buf.add n.str
    return
  of xnElement: discard
  if indent > 0 and not lastNodeIsText:
    w.buf.addIndent(indent, addNewLines)
  let inline = n.hasText
  let addNewLines = addNewLines and not inline

  w.buf.add '<'
  w.buf.add n.str
  for (key, val) in n.attrs:
    w.buf.add ' '
    w.buf.add key
    w.buf.add "=\""
    w.buf.addEscapedAttr val
    w.buf.add '"'
  if n.children.len == 0:
    w.buf.add " />"
    return
  w.buf.add '>'

  let indentNext = if inline: indent else: min(indent + 2, max(indent, 80))
  var lastNodeIsText = false
  for c in n.children:
    w.write(c, indentNext, addNewLines, lastNodeIsText)
    lastNodeIsText = c.kind != xnElement
  if not inline:
    w.buf.addIndent(indent, addNewLines)
  w.buf.add "</"
  w.buf.add n.str
  w.buf.add '>'

  if w.f != nil and w.buf.len >= flushSize:
    w.f.write w.buf
    w.buf.setLen 0

proc `$`*(n: XmlNode): string =
  var w = XmlWriter()
  try:
    w.write(n, 0, true, false)
  except IOError:
    discard # unreachable: nothing is written to a file without one
  w.buf

proc writeXml*(root: XmlNode, output: string) {.raises: [AutoEditorError].} =
  ## Streams `root` to `output` with an XML declaration, or to stdout without
  ## one when `output` is "-".
  if output == "-":
    try:
      var w = XmlWriter(f: stdout)
      w.write(root, 0, true, false)
      w.buf.add '\n'
      stdout.write w.buf
      stdout.flushFile()
    except IOError:
      error "Cannot write to stdout"
    return
  var f: File
  if not open(f, output, fmWrite):
    error "Cannot write to: " & output
  try:
    var w = XmlWriter(f: f)
    w.buf.add "<?xml version='1.0' encoding='utf-8'?>\n"
    w.write(root, 0, true, false)
    f.write w.buf
  except IOError:
    error "Cannot write to: " & output
  finally:
    f.close()

# As in std/xmlparser: deeper documents could exhaust the stack.
const xmlMaxDepth = 256

type XmlTooDeep = object of CatchableError

proc parseElement(x: var XmlParser, errors: var seq[string], depth: int):
    XmlNode {.raises: [IOError, OSError, ValueError, XmlTooDeep].}

proc addText(parent: XmlNode, text: string) =
  # Adjacent runs share one node: innerText reads the same, with fewer nodes.
  if parent.children.len > 0 and parent.children[^1].kind == xnText:
    parent.children[^1].str.add text
  else:
    parent.children.add newText(text)

proc parseChildren(x: var XmlParser, n: XmlNode, errors: var seq[string],
    depth: int) {.raises: [IOError, OSError, ValueError, XmlTooDeep].} =
  if depth > xmlMaxDepth:
    raise newException(XmlTooDeep, "")
  while true:
    case x.kind
    of xmlElementEnd:
      if x.elementName == n.str:
        x.next()
      else:
        errors.add errorMsg(x, "</" & n.str & "> expected")
      return
    of xmlEof:
      errors.add errorMsg(x, "</" & n.str & "> expected")
      return
    of xmlCharData, xmlWhitespace, xmlCData:
      n.addText x.charData
      x.next()
    of xmlEntity:
      # As in std/xmltree's innerText, an unknown entity reads as its name.
      n.addText x.entityName
      x.next()
    of xmlComment, xmlPI, xmlSpecial:
      x.next()
    of xmlError:
      errors.add errorMsg(x)
      x.next()
    of xmlElementStart, xmlElementOpen:
      n.children.add parseElement(x, errors, depth)
    of xmlAttribute, xmlElementClose:
      errors.add errorMsg(x, "<some_tag> expected")
      x.next()

proc parseElement(x: var XmlParser, errors: var seq[string], depth: int):
    XmlNode {.raises: [IOError, OSError, ValueError, XmlTooDeep].} =
  result = newElement(x.elementName)
  if x.kind == xmlElementOpen:
    x.next()
    while true:
      case x.kind
      of xmlAttribute:
        result.attrs.add (x.attrKey, x.attrValue)
        x.next()
      of xmlElementClose:
        x.next()
        break
      of xmlError:
        errors.add errorMsg(x)
        x.next()
        break
      else:
        errors.add errorMsg(x, "'>' expected")
        x.next()
        break
  else:
    x.next()
  x.parseChildren(result, errors, depth + 1)

proc parseXmlFile*(path: string): XmlNode {.raises: [AutoEditorError].} =
  ## Reads the XML file at `path`, streaming it rather than loading it whole.
  ## CDATA reads as text; comments and processing instructions are left out.
  var s: FileStream
  try:
    s = openFileStream(path)
  except IOError:
    error "Cannot read: " & path
  var x: XmlParser
  var errors: seq[string]
  try:
    x.open(s, path)
    while true:
      x.next()
      case x.kind
      of xmlElementOpen, xmlElementStart:
        try:
          result = x.parseElement(errors, 0)
        except XmlTooDeep:
          errors.add errorMsg(x, "elements nested deeper than " & $xmlMaxDepth &
            " levels")
        break
      of xmlWhitespace, xmlSpecial, xmlPI: discard
      of xmlError:
        errors.add errorMsg(x)
      else:
        errors.add errorMsg(x, "<some_tag> expected")
        break
    x.close()
  except IOError, OSError, ValueError:
    error "Cannot read: " & path
  if errors.len > 0:
    error "Failed to parse XML: " & errors[0]
