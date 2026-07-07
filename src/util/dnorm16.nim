import std/[math, strutils]

type Unorm16* = distinct uint16
type Unorm24* = distinct uint32
type Unorm24x4* = array[3, uint32]

func `==`*(a, b: Unorm16): bool {.borrow.}
func `<=`*(a, b: Unorm16): bool {.borrow.}
func `+`*(a, b: Unorm16): Unorm16 {.borrow.}
func `-`*(a, b: Unorm16): Unorm16 {.borrow.}
func high*(T: typedesc[Unorm16]): Unorm16 = Unorm16(high(uint16))

const invMax32 = 1.0'f32 / 65535.0'f32
const invMax64 = 1.0'f64 / 65535.0'f64
const unorm24Max = 0xFFFFFF'u32
const unorm24InvMax32 = 1.0'f32 / unorm24Max.float32

converter toUnorm16*(f: float32): Unorm16 =
  if f != f: return Unorm16(0)  # NaN passes min/max; uint16(NaN) is UB
  let c = max(0.0'f32, min(1.0'f32, f))
  Unorm16(uint16(c * 65535.0'f32 + 0.5'f32))

converter toFloat32*(u: Unorm16): float32 = uint16(u).float32 * invMax32
func toFloat64*(u: Unorm16): float64 = uint16(u).float64 * invMax64

func toUnorm24*(f: float32): Unorm24 =
  if f != f: return Unorm24(0)
  let c = max(0.0'f32, min(1.0'f32, f)).float64
  Unorm24(uint32(round(c * unorm24Max.float64)))

func toFloat32*(u: Unorm24): float32 = uint32(u).float32 * unorm24InvMax32

func packUnorm24x4*(x, y, w, h: float32): Unorm24x4 =
  let
    ux = uint32(toUnorm24(x))
    uy = uint32(toUnorm24(y))
    uw = uint32(toUnorm24(w))
    uh = uint32(toUnorm24(h))

  [
    ux or ((uy and 0x0000FF'u32) shl 24),
    (uy shr 8) or ((uw and 0x00FFFF'u32) shl 16),
    (uw shr 16) or (uh shl 8),
  ]

func unpackUnorm24x4*(r: Unorm24x4): tuple[x, y, w, h: float32] =
  let
    ux = r[0] and unorm24Max
    uy = ((r[0] shr 24) or ((r[1] and 0x0000FFFF'u32) shl 8)) and unorm24Max
    uw = ((r[1] shr 16) or ((r[2] and 0x000000FF'u32) shl 16)) and unorm24Max
    uh = (r[2] shr 8) and unorm24Max
  (Unorm24(ux).toFloat32, Unorm24(uy).toFloat32,
   Unorm24(uw).toFloat32, Unorm24(uh).toFloat32)

func `$`*(r: Unorm24x4): string =
  r[0].toHex(8) & "," & r[1].toHex(8) & "," & r[2].toHex(8)

const halfUnorm16* = toUnorm16(0.5'f32)

func `$`*(u: Unorm16): string =
  # Shortest decimal that re-quantizes to the same unorm16. 1/65535 isn't a
  # round value (0.5 -> 0.5000076), so format-and-truncate would surface the
  # quantization noise; instead build the rounded decimal in integer math at
  # increasing precision and return the first that snaps back to this bucket.
  let n = uint16(u).int
  const d = 65535
  for prec in 1 .. 5:
    let scale = 10 ^ prec
    let rounded = (n * scale + d div 2) div d # round(n/d * 10^prec)
    let f = rounded.float32 / scale.float32
    if toUnorm16(f) == u:
      var s = $rounded
      while s.len <= prec: s = "0" & s # zero-pad mantissa
      let dot = s.len - prec
      result = s[0 ..< dot] & "." & s[dot ..< s.len]
      result = result.strip(leading = false, chars = {'0'})
      if result.endsWith('.'): result.add '0'
      return result

# Signed sibling of Unorm16: maps [-1.0, 1.0] onto int16 [-32767, 32767].
type Snorm16* = distinct int16

func `==`*(a, b: Snorm16): bool {.borrow.}
func `<=`*(a, b: Snorm16): bool {.borrow.}
func `+`*(a, b: Snorm16): Snorm16 {.borrow.}
func `-`*(a, b: Snorm16): Snorm16 {.borrow.}

const sinvMax32 = 1.0'f32 / 32767.0'f32
const sinvMax64 = 1.0'f64 / 32767.0'f64

converter toSnorm16*(f: float32): Snorm16 =
  if f != f: return Snorm16(0)  # NaN passes min/max; int16(NaN) is UB
  let c = max(-1.0'f32, min(1.0'f32, f))
  Snorm16(int16(round(c * 32767.0'f32)))

converter toFloat32*(s: Snorm16): float32 =
  max(-1.0'f32, int16(s).float32 * sinvMax32)

func toFloat64*(s: Snorm16): float64 = max(-1.0'f64, int16(s).float64 * sinvMax64)

func `$`*(s: Snorm16): string =
  # Shortest decimal that re-quantizes to the same snorm16 (see Unorm16's `$`).
  let raw = int16(s).int
  const d = 32767
  let neg = raw < 0
  let n = abs(raw)
  for prec in 1 .. 5:
    let scale = 10 ^ prec
    let rounded = (n * scale + d div 2) div d
    let f = (if neg: -rounded.float32 else: rounded.float32) / scale.float32
    if toSnorm16(f) == s:
      var t = $rounded
      while t.len <= prec: t = "0" & t
      let dot = t.len - prec
      result = t[0 ..< dot] & "." & t[dot ..< t.len]
      result = result.strip(leading = false, chars = {'0'})
      if result.endsWith('.'): result.add '0'
      if neg: result = "-" & result
      return result
