import std/[math, os, strformat, tables]

import ../[av, ffmpeg, log, resampler]

type
  IRMatrix = object
    ## taps[o][i] is what input channel i contributes to output channel o; an
    ## empty seq is no path at all.
    taps: seq[seq[seq[float32]]]

  Spectra = object
    n: int     # FFT size
    blockLen: int # input samples per FFT, so a block plus the IR tail fits in n
    h: seq[seq[seq[AVComplexFloat]]]

const matrixNames = [["H_LL.wav", "H_LR.wav"], ["H_RL.wav", "H_RR.wav"]]

# A timeline usually has many sections sharing one IR, and each would otherwise
# decode, resample, and transform it again. Per thread, so it needs no lock
# wherever audio renders.
var spectraCache {.threadvar.}: Table[(string, cint, int), Spectra]

proc decodeIR(path: string, sr: cint): seq[seq[float32]] =
  ## Every channel of `path`'s first audio stream as float, resampled to `sr`.
  let container = (try: av.open(path) except IOError as e: error e.msg)
  defer: container.close()
  if container.audio.len == 0:
    error &"convolve: {path} has no audio"
  let stream = container.audio[0]
  var decoderCtx = initDecoder(stream.codecpar)
  defer: avcodec_free_context(addr decoderCtx)
  var frame = av_frame_alloc()
  if frame == nil:
    error "Could not allocate frame"
  defer: av_frame_free(addr frame)

  var layout: ref AVChannelLayout
  new(layout)
  discard av_channel_layout_copy(addr layout[], addr stream.codecpar.ch_layout)
  let channels = layout.nb_channels.int
  result = newSeq[seq[float32]](channels)
  var resampler = newAudioResampler(AV_SAMPLE_FMT_FLTP, layout, sr)

  proc take(frames: seq[ptr AVFrame], dst: var seq[seq[float32]]) =
    for f in frames:
      var f = f
      for ch in 0 ..< channels:
        let src = cast[ptr UncheckedArray[cfloat]](f.data[ch])
        let start = dst[ch].len
        dst[ch].setLen(start + f.nb_samples)
        for k in 0 ..< f.nb_samples.int:
          dst[ch][start + k] = src[k]
      av_frame_free(addr f)

  var inRate = stream.codecpar.sample_rate
  for f in container.decode(stream.index, decoderCtx, frame):
    inRate = f.sample_rate
    take(resampler.resample(f), result)
  # Only a rate change holds samples back; a same-rate resampler passes frames
  # straight through and has nothing to flush.
  if inRate != sr:
    take(resampler.resample(nil), result)

  if result.len == 0 or result[0].len == 0:
    error &"convolve: {path} has no samples"
  # Resampling keeps sample values, so the sum of the taps (and with it the
  # IR's gain) would grow with the rate. Scale it back to the IR's own level.
  if inRate != sr and inRate > 0:
    let k = float32(inRate.float / sr.float)
    for ch in result.mitems:
      for v in ch.mitems: v *= k

proc fold(m: IRMatrix, channels: int): IRMatrix =
  ## A true-stereo matrix as heard by audio that isn't stereo: the same signal
  ## goes into both inputs and both outputs are averaged.
  var h: seq[float32]
  for row in m.taps:
    for t in row:
      if t.len > h.len: h.setLen(t.len)
      for k, v in t: h[k] += v * 0.5'f32
  result.taps = newSeq[seq[seq[float32]]](channels)
  for c in 0 ..< channels:
    result.taps[c] = newSeq[seq[float32]](channels)
    result.taps[c][c] = h

proc diagonal(irs: seq[seq[float32]], channels: int): IRMatrix =
  result.taps = newSeq[seq[seq[float32]]](channels)
  for c in 0 ..< channels:
    result.taps[c] = newSeq[seq[float32]](channels)
    result.taps[c][c] = irs[(if irs.len == 1: 0 else: c)]

proc loadIR(path: string, sr: cint, channels: int): IRMatrix =
  var stereo: IRMatrix
  if dirExists(path):
    stereo.taps = @[newSeq[seq[float32]](2), newSeq[seq[float32]](2)]
    var found = false
    for o in 0 .. 1:
      for i in 0 .. 1:
        let file = path / matrixNames[o][i]
        if fileExists(file):
          let irs = decodeIR(file, sr)
          if irs.len != 1:
            error &"convolve: {file} should be mono, but has {irs.len} channels"
          stereo.taps[o][i] = irs[0]
          found = true
    if not found:
      error &"convolve: {path} has none of H_LL.wav, H_LR.wav, H_RL.wav, H_RR.wav"
  else:
    if not fileExists(path):
      error &"convolve: {path} doesn't exist"
    let irs = decodeIR(path, sr)
    if irs.len == 1 or irs.len == channels:
      return diagonal(irs, channels)
    if irs.len != 4:
      error &"convolve: {path} has {irs.len} channels, but the audio has {channels}; " &
        "use a mono IR, one with as many channels, or a 4-channel true-stereo IR"
    stereo.taps = @[@[irs[0], irs[1]], @[irs[2], irs[3]]]
  if channels == 2: stereo else: fold(stereo, channels)

proc newTx(inv: bool, n: int, scale: float32): (ptr AVTXContext, av_tx_fn) =
  var s = scale
  if av_tx_init(addr result[0], addr result[1], AV_TX_FLOAT_RDFT, cint(inv),
      n.cint, addr s, AV_TX_UNALIGNED) < 0:
    error "Could not set up the FFT"

proc spectraFor(path: string, sr: cint, channels: int): Spectra =
  let key = (path, sr, channels)
  if key in spectraCache:
    return spectraCache[key]

  let m = loadIR(path, sr, channels)
  var taps = 0
  for row in m.taps:
    for t in row: taps = max(taps, t.len)
  var n = 256
  while n < 2 * taps: n *= 2
  result.n = n
  result.blockLen = n - taps + 1

  var (fwd, fwdFn) = newTx(false, n, 1.0'f32)
  defer: av_tx_uninit(addr fwd)
  var buf = newSeq[float32](n)
  result.h = newSeq[seq[seq[AVComplexFloat]]](channels)
  for o in 0 ..< channels:
    result.h[o] = newSeq[seq[AVComplexFloat]](channels)
    for i in 0 ..< channels:
      let t = m.taps[o][i]
      if t.len == 0: continue
      for k in 0 ..< n: buf[k] = (if k < t.len: t[k] else: 0'f32)
      result.h[o][i] = newSeq[AVComplexFloat](n div 2 + 1)
      fwdFn(fwd, addr result.h[o][i][0], addr buf[0], sizeof(float32))
  spectraCache[key] = result

proc applyConvolve*(data: var seq[int16], path: string, channels: int, sr: cint) =
  ## Replace interleaved `data` with its convolution by the IR at `path`,
  ## cut to the same length (overlap-add, one FFT per block and channel).
  let frames = data.len div channels
  if frames == 0:
    return
  let sp = spectraFor(path, sr, channels)
  let n = sp.n
  let bins = n div 2 + 1

  var used = newSeq[bool](channels)
  for o in 0 ..< channels:
    for i in 0 ..< channels:
      if sp.h[o][i].len > 0: used[i] = true

  var (fwd, fwdFn) = newTx(false, n, 1.0'f32)
  defer: av_tx_uninit(addr fwd)
  var (inv, invFn) = newTx(true, n, 1.0'f32 / n.float32)
  defer: av_tx_uninit(addr inv)

  var outp = newSeq[float32](frames * channels)
  var buf = newSeq[float32](n)
  var x = newSeq[seq[AVComplexFloat]](channels)
  for i in 0 ..< channels:
    if used[i]: x[i] = newSeq[AVComplexFloat](bins)
  var acc = newSeq[AVComplexFloat](bins)

  var pos = 0
  while pos < frames:
    let count = min(sp.blockLen, frames - pos)
    for i in 0 ..< channels:
      if not used[i]: continue
      for k in 0 ..< n:
        buf[k] = (if k < count: data[(pos + k) * channels + i].float32 / 32768'f32
                  else: 0'f32)
      fwdFn(fwd, addr x[i][0], addr buf[0], sizeof(float32))
    for o in 0 ..< channels:
      for b in 0 ..< bins: acc[b] = AVComplexFloat()
      var any = false
      for i in 0 ..< channels:
        let h = sp.h[o][i]
        if h.len == 0: continue
        any = true
        for b in 0 ..< bins:
          let xr = x[i][b].re
          let xi = x[i][b].im
          acc[b].re += xr * h[b].re - xi * h[b].im
          acc[b].im += xr * h[b].im + xi * h[b].re
      if not any: continue
      invFn(inv, addr buf[0], addr acc[0], sizeof(AVComplexFloat))
      for k in 0 ..< min(n, frames - pos):
        outp[(pos + k) * channels + o] += buf[k]
    pos += count

  for k in 0 ..< outp.len:
    data[k] = int16(clamp(round(outp[k] * 32768'f32), -32768'f32, 32767'f32))
