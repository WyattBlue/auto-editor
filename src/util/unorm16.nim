import std/strutils

type Unorm16* = distinct uint16

func `==`*(a, b: Unorm16): bool {.borrow.}

func toUnorm16*(f: float32): Unorm16 =
  let c = max(0.0'f32, min(1.0'f32, f))
  Unorm16(uint16(c * 65535.0'f32 + 0.5'f32))

const invMax32 = 1.0'f32 / 65535.0'f32
const invMax64 = 1.0'f64 / 65535.0'f64

converter toFloat32*(u: Unorm16): float32 = uint16(u).float32 * invMax32
func toFloat64*(u: Unorm16): float64 = uint16(u).float64 * invMax64

func `$`*(u: Unorm16): string =
  # Shortest decimal that re-quantizes to the same unorm16. 1/65535 isn't a
  # round value (0.5 -> 0.5000076), so format-and-truncate would surface the
  # quantization noise; instead try increasing precision until a clean string
  # snaps back to the same bucket.
  for prec in 1 .. 5:
    result = formatFloat(toFloat64(u), ffDecimal, prec)
    result = result.strip(leading = false, chars = {'0'})
    if result.endsWith('.'): result.add '0'
    if toUnorm16(parseFloat(result).float32) == u:
      return result
