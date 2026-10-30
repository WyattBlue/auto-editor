## A write-only XML tree for the editor exporters. std/xmltree stores each
## element's attributes in a StringTable that starts at 64 slots (~4 KB), which
## dominates memory on large timelines; a seq of pairs costs only what it holds.
## Output matches xmltree's `$` except that attributes keep insertion order.

import std/macros except error
import ../log

type
  XmlAttributes* = seq[(string, string)]

  XmlNodeKind = enum
    xnElement
    xnText
    xnVerbatimText # written without escaping

  XmlNode* = ref object
    kind: XmlNodeKind
    tag: string # the element name, or a text node's text
    attrs*: XmlAttributes
    children: seq[XmlNode]

func newElement*(tag: string): XmlNode =
  XmlNode(tag: tag)

func newText*(text: string): XmlNode =
  XmlNode(kind: xnText, tag: text)

func newVerbatimText*(text: string): XmlNode =
  XmlNode(kind: xnVerbatimText, tag: text)

func newXmlTree*(tag: string, children: openArray[XmlNode],
    attrs: XmlAttributes = @[]): XmlNode =
  XmlNode(tag: tag, attrs: attrs, children: @children)

func toXmlAttributes*(pairs: varargs[(string, string)]): XmlAttributes =
  @pairs

func add*(parent, child: XmlNode) =
  parent.children.add child

func len*(n: XmlNode): int =
  ## The number of children.
  n.children.len

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
    w.buf.addEscaped n.tag
    return
  of xnVerbatimText:
    w.buf.add n.tag
    return
  of xnElement: discard
  if indent > 0 and not lastNodeIsText:
    w.buf.addIndent(indent, addNewLines)
  let inline = n.hasText
  let addNewLines = addNewLines and not inline

  w.buf.add '<'
  w.buf.add n.tag
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
  w.buf.add n.tag
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
