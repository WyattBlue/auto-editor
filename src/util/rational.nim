type AVRational* {.importc, completeStruct, header: "<libavutil/rational.h>", bycopy.} = object
  num*: cint
  den*: cint

func isValid*(r: AVRational): bool =
  ## A usable time base: positive and non-degenerate.
  r.num > 0 and r.den > 0

func toAVRational*(num: int): AVRational =
  AVRational(num: num.cint, den: 1)

func `$`*(a: AVRational): string =
  if a.den == 1:
    return $a.num
  else:
    return $a.num & "/" & $a.den
