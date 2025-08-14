import ../ffmpeg
import std/[strutils, strformat]
import std/parseutils

type RGBColor* = object
  red*: uint8
  green*: uint8
  blue*: uint8

func toString*(color: RGBColor): string =
  let
    redHex = toHex(color.red, 2)
    greenHex = toHex(color.green, 2)
    blueHex = toHex(color.blue, 2)
  result = fmt"#{redHex}{greenHex}{blueHex}".toLowerAscii

proc findColor(name: string): RGBColor =
  var rgba: array[4, uint8]
  let parseResult = av_parse_color(cast[ptr uint8](addr rgba[0]), cstring(name), -1, nil)
  if parseResult >= 0:
    return RGBColor(red: rgba[0], green: rgba[1], blue: rgba[2])
  else:
    raise newException(ValueError, "Unknown color: " & name)

proc parseColor*(hexString: string): RGBColor =
  if not hexString.startsWith("#"):
    try:
      return findColor(hexString)
    except ValueError:
      raise newException(ValueError, "Unknown color name: " & hexString)

  let hexValue = hexString.substr(1)
  case hexValue.len
  of 3:
    try:
      discard parseHex(hexValue[0] & hexValue[0], result.red)
      discard parseHex(hexValue[1] & hexValue[1], result.green)
      discard parseHex(hexValue[2] & hexValue[2], result.blue)
    except:
      raise newException(ValueError, fmt"Invalid 3-digit hex color format: {hexString}")
  of 6:
    try:
      discard parseHex[uint8](hexValue[0..1], result.red)
      discard parseHex[uint8](hexValue[2..3], result.green)
      discard parseHex[uint8](hexValue[4..5], result.blue)
    except:
      raise newException(ValueError, fmt"Invalid 6-digit hex color format: {hexString}")
  else:
    raise newException(ValueError, fmt"Invalid hex color string length: {hexString}. Expected #RGB or #RRGGBB format.")

