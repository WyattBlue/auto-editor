import std/[base64, strutils, strformat]
from std/math import gcd, `mod`, round, trunc

import ../log

func hexToBytes*(hex: string): seq[byte] =
  result = newSeq[byte](hex.len div 2)
  for i in 0 ..< result.len:
    result[i] = parseHexInt(hex[i * 2 .. i * 2 + 1]).byte

func b64urlDecode*(s: string): seq[byte] =
  var padded = s.replace('-', '+').replace('_', '/')
  while padded.len mod 4 != 0:
    padded &= "="
  cast[seq[byte]](base64.decode(padded))

func visibleLen(s: string): int =
  # Count only visible characters, skipping OSC escape sequences (\e]...\e\)
  var i = 0
  while i < s.len:
    if s[i] == '\e' and i + 1 < s.len and s[i + 1] == ']':
      i += 2
      while i < s.len:
        if s[i] == '\e' and i + 1 < s.len and s[i + 1] == '\\':
          i += 2
          break
        i += 1
    else:
      result += 1
      i += 1

func wrapText*(text: string, width, indent: int): string =
  let text = text.strip(leading = true, trailing = true, chars = {'\n'})
  if text.len == 0:
    return ""
  let indentStr = " ".repeat(indent)
  var outLines: seq[string] = @[]
  var isFirst = true

  for line in text.split("\n"):
    if line.len == 0:
      outLines.add("")
      continue

    # Detect leading whitespace
    var leadingSpaces = 0
    for c in line:
      if c == ' ':
        leadingSpaces += 1
      else:
        break
    let lineIndent = " ".repeat(leadingSpaces)
    let content = line[leadingSpaces .. ^1]

    var currentLine = ""
    for word in content.splitWhitespace():
      if currentLine.len == 0:
        currentLine = word
      elif leadingSpaces + visibleLen(currentLine) + 1 + visibleLen(word) <= width:
        currentLine &= " " & word
      else:
        if isFirst:
          outLines.add(lineIndent & currentLine)
          isFirst = false
        else:
          outLines.add(indentStr & lineIndent & currentLine)
        currentLine = word
    if currentLine.len > 0:
      if isFirst:
        outLines.add(lineIndent & currentLine)
        isFirst = false
      else:
        outLines.add(indentStr & lineIndent & currentLine)

  result = outLines.join("\n")

type Code* = enum
  standard, ass, display

func toTimecode*(secs: float, fmt: Code): string =
  var sign = ""
  var seconds = secs
  if seconds < 0:
    sign = "-"
    seconds = -seconds

  let totalSeconds = seconds
  let mFloat = totalSeconds / 60.0
  let hFloat = mFloat / 60.0

  let h = int(hFloat)
  let m = int(mFloat) mod 60
  let s = totalSeconds mod 60.0

  case fmt:
  of standard:
    &"{sign}{h:02d}:{m:02d}:{s:06.3f}"
  of ass:
    &"{sign}{h:d}:{m:02d}:{s:05.2f}"
  of display:
    &"{sign}{h:d}:{m:02d}:{s.round.int:02d}"

func agSplitFile*(path: string): tuple[dir, name, ext: string] =
  ## Platform-independent splitFile. Treats both '/' and '\' as path separators
  ## on every OS, so results don't drift between Linux, macOS, and Windows.
  var namePos = 0
  var dotPos = 0
  for i in countdown(path.len - 1, 0):
    if path[i] == '.' and dotPos == 0:
      dotPos = i
    elif path[i] == '/' or path[i] == '\\':
      if namePos == 0:
        namePos = i + 1
      if dotPos > namePos and dotPos < path.len - 1:
        result.name = substr(path, namePos, dotPos - 1)
        result.ext = substr(path, dotPos)
      else:
        result.name = substr(path, namePos)
      result.dir = substr(path, 0, max(0, namePos - 2))
      return
  if dotPos > 0 and dotPos < path.len - 1:
    result.name = substr(path, 0, dotPos - 1)
    result.ext = substr(path, dotPos)
  else:
    result.name = path

const
  commonAspectRatios = [
    (1, 1), (5, 4), (4, 3), (3, 2), (16, 10), (16, 9), (2, 1), (64, 27)
  ]
  # Max drift, in stored pixels, between a dimension and what a common ratio
  # would produce for us to treat the difference as codec-friendly rounding
  # rather than a deliberate ratio. Absolute (not relative) so the snap stays
  # tight at high resolutions where a percentage would be many pixels wide.
  aspectSnapDrift = 2.0

func aspectRatio*(width, height: int, sarNum = 1, sarDen = 1): tuple[w, h: int] =
  if width <= 0 or height <= 0:
    return (0, 0)

  # Fold the sample (pixel) aspect ratio into the dimensions so anamorphic video
  # reports its true display aspect ratio, the way ffmpeg's DAR does.
  let
    sn = max(sarNum, 1)
    sd = max(sarDen, 1)
    dispW = width * sn
    dispH = height * sd
    c = gcd(dispW, dispH)
  result = (dispW div c, dispH div c)

  # A clean, small reduction is already a meaningful ratio (16:9, 4:3, 8:5...).
  if max(result.w, result.h) <= 50:
    return

  let (w, h) = (width.float, height.float)
  var bestDrift = aspectSnapDrift
  for (cw, ch) in commonAspectRatios:
    for (a, b) in [(cw, ch), (ch, cw)]:
      # Stored dimensions that would yield this display ratio for the given SAR.
      let
        ta = float(a * sd)  # storage-width units
        tb = float(b * sn)  # storage-height units
        drift = max(abs(w - h * ta / tb), abs(h - w * tb / ta))
      if drift < bestDrift:
        bestDrift = drift
        result = (a, b)

proc splitNumStr*(val: string): (float64, string) =
  var index = 0
  for char in val:
    if char notin "0123456789_ .-":
      break
    index += 1
  let (num, unit) = (val[0 ..< index], val[index .. ^1])
  var floatNum: float64
  try:
    floatNum = parseFloat(num.replace(" ", ""))
  except:
    error &"Invalid number: '{val}'"
  return (floatNum, unit)

proc parseBitrate*(input: string): int =
  if input == "auto":
    return -1

  let (val, unit) = splitNumStr(input)
  if unit.toLowerAscii() == "k":
    return int(val * 1000)
  if unit == "M":
    return int(val * 1_000_000)
  if unit == "G":
    return int(val * 1_000_000_000)
  if unit == "":
    return int(val)

  error &"Unknown bitrate: {input}"

proc parseTimeSimple*(val: string): PackedInt =
  const tb = 1000.0
  let (num, unit) = splitNumStr(val)
  if unit in ["s", "sec", "secs", "second", "seconds"]:
    return pack(true, round(num * tb).int64)
  if unit in ["min", "mins", "minute", "minutes"]:
    return pack(true, round(num * tb * 60).int64)
  if unit == "hour":
    return pack(true, round(num * tb * 3600).int64)
  if unit != "":
    error &"'{val}': Time format got unknown unit: `{unit}`"

  if num != trunc(num):
    error &"'{val}': Time format expects an integer"
  return pack(false, num.int64)

proc parseTime*(val: string): PackedInt =
  if val == "start":
    return pack(false, 0)
  if val == "end":
    return pack(false, 0x3FFFFFFFFFFFFFFF)
  return parseTimeSimple(val)

func toTb*(val: PackedInt, tb: float64): int =
  if val.getFlag:
    return int(val.getNumber.float64 / 1000.0 * tb)
  return int(val.getNumber)

proc smoothing*(val: var seq[bool], mincut, minclip: int) =
  var prev: seq[bool]
  while prev != val:
    prev = val
    var next = prev
    var startP = 0
    var active = false

    for j, item in prev.pairs:
      if item == true:
        if not active:
          startP = j
          active = true

        if j == len(prev) - 1 and j - startP < minclip:
          for i in startP ..< prev.len:
            next[i] = false
      elif active:
        if j - startP < minclip:
          for i in startP ..< j:
            next[i] = false
        active = false

    startP = 0
    active = false

    for j, item in prev.pairs:
      if item == false:
        if not active:
          startP = j
          active = true

        if j == len(prev) - 1 and j - startP < mincut:
          for i in startP ..< prev.len:
            next[i] = true
      elif active:
        if j - startP < mincut:
          for i in startP ..< j:
            next[i] = true
        active = false

    val = next

proc mutMargin*(arr: var seq[bool], startM, endM: int) =
  # Find start and end indexes
  var startIndex = newSeqOfCap[int](32)
  var endIndex = newSeqOfCap[int](32)
  let arrlen = len(arr)
  for j in 1 ..< arrlen:
    if arr[j] != arr[j - 1]:
      if arr[j]:
        startIndex.add j
      else:
        endIndex.add j

  # Apply margin
  if startM > 0:
    for i in startIndex:
      for k in max(i - startM, 0) ..< i:
        arr[k] = true

  if startM < 0:
    for i in startIndex:
      for k in i ..< min(i - startM, arrlen):
        arr[k] = false

  if endM > 0:
    for i in endIndex:
      for k in i ..< min(i + endM, arrlen):
        arr[k] = true

  if endM < 0:
    for i in endIndex:
      for k in max(i + endM, 0) ..< i:
        arr[k] = false
