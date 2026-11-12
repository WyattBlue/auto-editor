## Second-order IIR filters from the Audio EQ Cookbook (R. Bristow-Johnson),
## run over interleaved int16 audio.

import std/math

type
  BiquadKind* = enum
    bqHighpass, bqLowpass, bqNotch

  Biquad* = object
    b0, b1, b2, a1, a2: float64 # normalized so a0 = 1

func initBiquad*(kind: BiquadKind, freq, q, sr: float64): Biquad =
  # Past Nyquist the coefficients fold back, so keep the corner below it.
  let w0 = 2.0 * PI * min(freq, sr * 0.49) / sr
  let cw = cos(w0)
  let alpha = sin(w0) / (2.0 * q)
  let a0 = 1.0 + alpha
  var b0, b1, b2: float64
  case kind
  of bqHighpass:
    b0 = (1.0 + cw) / 2.0
    b1 = -(1.0 + cw)
    b2 = b0
  of bqLowpass:
    b0 = (1.0 - cw) / 2.0
    b1 = 1.0 - cw
    b2 = b0
  of bqNotch:
    b0 = 1.0
    b1 = -2.0 * cw
    b2 = 1.0
  Biquad(b0: b0 / a0, b1: b1 / a0, b2: b2 / a0, a1: -2.0 * cw / a0,
    a2: (1.0 - alpha) / a0)

proc applyBiquads*(data: var seq[int16], filters: openArray[Biquad],
    channels: int) =
  ## Run `filters` in series over each channel of interleaved `data`.
  if filters.len == 0 or channels <= 0: return
  let frames = data.len div channels
  # Transposed direct form II: two state values per filter and channel.
  var s1 = newSeq[float64](filters.len)
  var s2 = newSeq[float64](filters.len)
  for ch in 0 ..< channels:
    for k in 0 ..< filters.len:
      s1[k] = 0.0
      s2[k] = 0.0
    for i in 0 ..< frames:
      let idx = i * channels + ch
      var x = data[idx].float64
      for k, f in filters:
        let y = f.b0 * x + s1[k]
        s1[k] = f.b1 * x - f.a1 * y + s2[k]
        s2[k] = f.b2 * x - f.a2 * y
        x = y
      data[idx] = int16(clamp(round(x), -32768.0, 32767.0))
