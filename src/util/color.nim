import std/[strutils, strformat, parseutils]

proc av_get_known_color_name(color_idx: cint, rgbp: ptr ptr uint8): cstring
    {.importc, header: "<libavutil/parseutils.h>".}

type RGBColor* = object
  red*, green*, blue*: uint8

func toString*(color: RGBColor): string =
  let
    redHex = toHex(color.red, 2)
    greenHex = toHex(color.green, 2)
    blueHex = toHex(color.blue, 2)
  return toLowerAscii(&"#{redHex}{greenHex}{blueHex}")

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
