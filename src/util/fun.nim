import std/[base64, os, strutils, strformat]
from std/math import round, trunc, gcd

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

func splitext*(val: string): (string, string) =
  let (dir, name, ext) = splitFile(val)
  return (dir & "/" & name, ext)

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

func aspectRatio*(width, height: int): tuple[w, h: int] =
  if height == 0:
    return (0, 0)
  let c = gcd(width, height)
  return (width div c, height div c)

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
