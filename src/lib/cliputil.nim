from std/math import round, ceil

func clipBounds*[T: SomeInteger](startFrame, endFrame: T, speed: float64): (T, T) =
  if round(float64(endFrame - startFrame) / speed) == 0:
    return (T(0), T(0))
  let offset = T(ceil(float64(startFrame) / speed))
  (offset, T(ceil(float64(endFrame) / speed)) - offset)

func cutLengths*[T: SomeInteger](clipSpans: openArray[(T, T)], inLen: T): seq[T] =
  ## Gaps between kept source-domain spans, plus the leading and trailing gap.
  if clipSpans.len > 0 and clipSpans[0][0] > 0:
    result.add clipSpans[0][0]

  for i in 0 ..< clipSpans.len - 1:
    let cutLen = clipSpans[i + 1][0] - clipSpans[i][1]
    if cutLen > 0:
      result.add cutLen

  if clipSpans.len > 0:
    let trailingCut = inLen - clipSpans[^1][1]
    if trailingCut > 0:
      result.add trailingCut
