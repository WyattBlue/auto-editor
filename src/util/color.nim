import std/[math, strutils, strformat, parseutils]

proc av_get_known_color_name(color_idx: cint, rgbp: ptr ptr uint8): cstring
    {.importc, header: "<libavutil/parseutils.h>".}

type RGBColor* = object
  red*, green*, blue*: uint8
  yuv*: bool

func toString*(color: RGBColor): string =
  let
    redHex = toHex(color.red, 2)
    greenHex = toHex(color.green, 2)
    blueHex = toHex(color.blue, 2)
  let prefix = if color.yuv: "yuv#" else: "#"
  return toLowerAscii(&"{prefix}{redHex}{greenHex}{blueHex}")

func toRgb*(color: RGBColor, colorspace = 1, fullRange = false): RGBColor =
  if not color.yuv:
    return color
  let (kr, kb) = case colorspace
    of 1: (0.2126, 0.0722)
    of 9, 10: (0.2627, 0.0593)
    else: (0.299, 0.114)
  let cs = if fullRange: 255.0 else: 224.0
  let y = if fullRange: color.red.float / 255 else: (color.red.float - 16) / 219
  let cb = (color.green.float - 128) / cs
  let cr = (color.blue.float - 128) / cs
  let r = y + 2 * (1 - kr) * cr
  let b = y + 2 * (1 - kb) * cb
  let g = (y - kr * r - kb * b) / (1 - kr - kb)
  func toByte(v: float): uint8 = uint8(round(clamp(v, 0.0, 1.0) * 255))
  RGBColor(red: toByte(r), green: toByte(g), blue: toByte(b))

func findColor(name: string): RGBColor {.raises: [ValueError].} =
  var idx: cint = 0
  while true:
    var rgb: ptr uint8 = nil
    let entry = av_get_known_color_name(idx, addr rgb)
    if entry == nil:
      break
    if rgb != nil and cmpIgnoreCase($entry, name) == 0:
      let comps = cast[ptr UncheckedArray[uint8]](rgb)
      return RGBColor(red: comps[0], green: comps[1], blue: comps[2])
    inc idx
  raise newException(ValueError, "Unknown color: " & name)

func parseColor*(hexString: string): RGBColor {.raises: [ValueError].} =
  if hexString.toLowerAscii.startsWith("yuv#"):
    let hexValue = hexString.substr(4)
    if hexValue.len != 6 or parseHex[uint8](hexValue[0..1], result.red) != 2 or
        parseHex[uint8](hexValue[2..3], result.green) != 2 or
        parseHex[uint8](hexValue[4..5], result.blue) != 2:
      raise newException(ValueError, &"Invalid YUV color: {hexString}. Expected yuv#YYUUVV format.")
    result.yuv = true
    return

  if not hexString.startsWith("#"):
    try:
      return findColor(hexString)
    except ValueError:
      raise newException(ValueError, "Unknown color name: " & hexString)

  let hexValue = hexString.substr(1)
  case hexValue.len
  of 3:
    if parseHex(hexValue[0] & hexValue[0], result.red) != 2 or
        parseHex(hexValue[1] & hexValue[1], result.green) != 2 or
        parseHex(hexValue[2] & hexValue[2], result.blue) != 2:
      raise newException(ValueError, &"Invalid 3-digit hex color format: {hexString}")
  of 6:
    if parseHex[uint8](hexValue[0..1], result.red) != 2 or
        parseHex[uint8](hexValue[2..3], result.green) != 2 or
        parseHex[uint8](hexValue[4..5], result.blue) != 2:
      raise newException(ValueError, &"Invalid 6-digit hex color format: {hexString}")
  else:
    raise newException(ValueError, &"Invalid hex color string length: {hexString}. Expected #RGB or #RRGGBB format.")
