type AVRational* {.importc, completeStruct, header: "<libavutil/rational.h>", bycopy.} = object
  num*: cint
  den*: cint

# Implicit AVRational->int64 coercion; relied on by comparisons like
# `time_base == AV_NOPTS_VALUE` (no textual call site, so it reads as unused).
converter toInt64*(r: AVRational): int64 =
  (r.num div r.den).int64

func toAVRational*(num: int): AVRational =
  AVRational(num: num.cint, den: 1)

func `$`*(a: AVRational): string =
  if a.den == 1:
    return $a.num
  else:
    return $a.num & "/" & $a.den
