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

type YuvMatrix* = enum bt601, bt709, bt2020

const yuvCoeffs*: array[YuvMatrix, tuple[kr, kb: float]] =
  [(0.299, 0.114), (0.2126, 0.0722), (0.2627, 0.0593)]

func yuvMatrix*(colorspace: int): YuvMatrix =
  case colorspace
  of 1: bt709
  of 9, 10: bt2020
  else: bt601

func yuvToRgb*(y, cb, cr: float, matrix: YuvMatrix, fullRange: bool):
    tuple[r, g, b: float] =
  let (kr, kb) = yuvCoeffs[matrix]
  let luma = if fullRange: y / 255 else: (y - 16) / 219
  let cs = if fullRange: 255.0 else: 224.0
  let u = (cb - 128) / cs
  let v = (cr - 128) / cs
  let r = luma + 2 * (1 - kr) * v
  let b = luma + 2 * (1 - kb) * u
  (r, (luma - kr * r - kb * b) / (1 - kr - kb), b)

func rgbToYuv*(r, g, b: float, matrix: YuvMatrix, fullRange: bool):
    tuple[y, cb, cr: float] =
  let (kr, kb) = yuvCoeffs[matrix]
  let y = kr * r + (1 - kr - kb) * g + kb * b
  let cb = (b - y) / (2 * (1 - kb))
  let cr = (r - y) / (2 * (1 - kr))
  let (ys, yOff, cs) = if fullRange: (255.0, 0.0, 255.0) else: (219.0, 16.0, 224.0)
  (yOff + y * ys, 128 + cb * cs, 128 + cr * cs)

func toRgb*(color: RGBColor, colorspace = 1, fullRange = false): RGBColor =
  if not color.yuv:
    return color
  let (r, g, b) = yuvToRgb(color.red.float, color.green.float, color.blue.float,
    yuvMatrix(colorspace), fullRange)
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
