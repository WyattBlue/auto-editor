type AVRational* {.importc, completeStruct, header: "<libavutil/rational.h>", bycopy.} = object
  num*: cint
  den*: cint

converter toInt64*(r: AVRational): int64 =
  (r.num div r.den).int64

converter toInt32*(r: AVRational): int32 =
  (r.num div r.den).int32

converter toAVRational*(num: int): AVRational =
  AVRational(num: num.cint, den: 1)

func `$`*(a: AVRational): string =
  if a.den == 1:
    return $a.num
  else:
    return $a.num & "/" & $a.den
