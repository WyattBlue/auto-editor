import std/[strutils, strformat]
import std/os
from std/math import round, trunc, gcd

import ../log

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
    error fmt"Invalid number: '{val}'"
  return (floatNum, unit)

proc parseBitrate*(input: string): int =
  if input == "auto":
    return -1

  let (val, unit) = split_num_str(input)
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

proc parseTime*(val: string): PackedInt =
  if val == "start":
    return pack(false, 0)
  if val == "end":
    return pack(false, 0x3FFFFFFFFFFFFFFF)

  let tb = 1000.0
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

func toTb*(val: PackedInt, tb: float64): int64 =
  if val.getFlag:
    return int64(val.getNumber / 1000 * tb)
  return val.getNumber

proc mutRemoveSmall*(arr: var seq[bool], lim: int, replace, with: bool) =
  var startP = 0
  var active = false
  for j, item in arr.pairs:
    if item == replace:
      if not active:
        startP = j
        active = true

      if j == len(arr) - 1 and j - startP < lim:
        for i in startP ..< arr.len:
          arr[i] = with
    elif active:
      if j - startP < lim:
        for i in startP ..< j:
          arr[i] = with
      active = false


proc mutMargin*(arr: var seq[bool], startM, endM: int) =
  # Find start and end indexes
  var startIndex: seq[int] = @[]
  var endIndex: seq[int] = @[]
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
