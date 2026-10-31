## Pictures for edit-point transitions other than a dissolve: each blends the
## outgoing picture `a` into the incoming `b` at progress `p` (0 to 1). Where a
## transition shows neither, as around a shrunken or turned picture, `under`
## (what lies below the track) shows through.
##
## The looks follow Premiere Pro's transitions of the same names at their
## default settings.

import std/[cpuinfo, typedthreads]
from std/math import PI, arcsin, arctan2, ceil, cos, exp, floor, pow, round, sin, sqrt, tan

import ../transitions

type
  Img* = object
    w*, h*: int
    px*: seq[uint8] # RGB, rows packed without padding
  C = tuple[r, g, b: float32] # 0 to 255

const black: C = (0'f32, 0'f32, 0'f32)
const white: C = (255'f32, 255'f32, 255'f32)

func `+`(x, y: C): C {.inline.} = (x.r + y.r, x.g + y.g, x.b + y.b)
func `-`(x, y: C): C {.inline.} = (x.r - y.r, x.g - y.g, x.b - y.b)
func `*`(x: C, k: float32): C {.inline.} = (x.r * k, x.g * k, x.b * k)
func `*`(x, y: C): C {.inline.} = (x.r * y.r / 255, x.g * y.g / 255, x.b * y.b / 255)
func mix(x, y: C, t: float32): C {.inline.} = x + (y - x) * t
func luma(x: C): float32 {.inline.} = (0.2126'f32 * x.r + 0.7152'f32 * x.g +
  0.0722'f32 * x.b) / 255
func screen(x, y: C): C {.inline.} =
  (255 - (255 - x.r) * (255 - y.r) / 255, 255 - (255 - x.g) * (255 - y.g) / 255,
   255 - (255 - x.b) * (255 - y.b) / 255)

func clamp01(t: float32): float32 {.inline.} = clamp(t, 0'f32, 1'f32)
func smooth(e0, e1, x: float32): float32 {.inline.} =
  let t = clamp01((x - e0) / (e1 - e0))
  t * t * (3 - 2 * t)
func easeInOut(t: float32): float32 {.inline.} =
  let t = clamp01(t)
  if t < 0.5: 4 * t * t * t else: 1 - pow(-2 * t + 2, 3) / 2
func easeIn(t: float32): float32 {.inline.} = clamp01(t) * clamp01(t) * clamp01(t)
func easeOut(t: float32): float32 {.inline.} = 1 - pow(1 - clamp01(t), 3)
func easeInBack(t: float32): float32 =
  const c = 1.70158'f32
  (c + 1) * t * t * t - c * t * t
func easeOutBack(t: float32): float32 =
  const c = 1.70158'f32
  1 + (c + 1) * pow(t - 1, 3) + c * pow(t - 1, 2)
func bell(p: float32): float32 {.inline.} = sin(p * PI.float32)
func fract(x: float32): float32 {.inline.} = x - floor(x)

func hash(x, y, seed: uint32): float32 =
  var h = x * 374761393'u32 + y * 668265263'u32 + seed * 2246822519'u32
  h = (h xor (h shr 13)) * 1274126177'u32
  h = h xor (h shr 16)
  float32(h and 0xffffff) / float32(0x1000000)

func hashi(x, y: int, seed: uint32): float32 {.inline.} =
  hash(cast[uint32](x.int32), cast[uint32](y.int32), seed)

func noise(x, y: float32, seed: uint32): float32 =
  ## Smooth value noise, 0 to 1.
  let xi = floor(x).int
  let yi = floor(y).int
  let fx = x - xi.float32
  let fy = y - yi.float32
  let ux = fx * fx * (3 - 2 * fx)
  let uy = fy * fy * (3 - 2 * fy)
  let a = hashi(xi, yi, seed)
  let b = hashi(xi + 1, yi, seed)
  let c = hashi(xi, yi + 1, seed)
  let d = hashi(xi + 1, yi + 1, seed)
  a + (b - a) * ux + (c - a) * uy + (a - b - c + d) * ux * uy

func fbm(x, y: float32, seed: uint32): float32 =
  var amp = 0.5'f32
  var f = 1'f32
  for i in 0 ..< 4:
    result += amp * noise(x * f, y * f, seed + i.uint32)
    f *= 2
    amp *= 0.5
  result /= 0.9375

func newImg(w, h: int): Img = Img(w: w, h: h, px: newSeq[uint8](w * h * 3))

func get(im: Img, x, y: int): C {.inline.} =
  let x = clamp(x, 0, im.w - 1)
  let y = clamp(y, 0, im.h - 1)
  let i = (y * im.w + x) * 3
  (im.px[i].float32, im.px[i + 1].float32, im.px[i + 2].float32)

proc put(im: var Img, x, y: int, c: C) {.inline.} =
  let i = (y * im.w + x) * 3
  im.px[i] = uint8(clamp(c.r + 0.5'f32, 0, 255))
  im.px[i + 1] = uint8(clamp(c.g + 0.5'f32, 0, 255))
  im.px[i + 2] = uint8(clamp(c.b + 0.5'f32, 0, 255))

func sample(im: Img, x, y: float32, wrap = false): C =
  ## Bilinear, at pixel coordinates (centers on .5); edges extend, or the
  ## picture repeats across with `wrap`.
  var fx = x - 0.5'f32
  let fy = y - 0.5'f32
  if wrap: fx = fx - floor(fx / im.w.float32) * im.w.float32
  let x0 = floor(fx).int
  let y0 = floor(fy).int
  let tx = fx - x0.float32
  let ty = fy - y0.float32
  let x1 = (if wrap and x0 + 1 >= im.w: 0 else: x0 + 1)
  let top = mix(im.get(x0, y0), im.get(x1, y0), tx)
  let bot = mix(im.get(x0, y0 + 1), im.get(x1, y0 + 1), tx)
  mix(top, bot, ty)

func inside(im: Img, x, y: float32): bool {.inline.} =
  x >= 0 and y >= 0 and x < im.w.float32 and y < im.h.float32

type
  RowsBody = proc (y0, y1: int) {.closure, gcsafe.}
  RowsJob = object
    body: ptr RowsBody
    y0, y1: int

proc rowsWorker(job: ptr RowsJob) {.thread.} =
  job.body[](job.y0, job.y1)

proc eachRows(h: int, body: RowsBody) =
  ## `body` over bands of the rows, on every core. Each band writes only its
  ## own rows, and all of them finish before this returns.
  let n = clamp(min(countProcessors(), h div 16), 1, 16)
  if n == 1:
    body(0, h)
    return
  var b = body
  var jobs = newSeq[RowsJob](n)
  var threads = newSeq[Thread[ptr RowsJob]](n)
  for i in 0 ..< n:
    jobs[i] = RowsJob(body: addr b, y0: h * i div n, y1: h * (i + 1) div n)
    createThread(threads[i], rowsWorker, addr jobs[i])
  joinThreads(threads)

template eachPixel(res: var Img, w, h: int, body: untyped) =
  ## `body` sets `c` for the pixel at `x`, `y`, whose center is `u`, `v` as a
  ## fraction of the frame.
  res = newImg(w, h)
  let dst = addr res
  eachRows(h, proc (y0, y1: int) {.closure, gcsafe.} =
    for y {.inject.} in y0 ..< y1:
      for x {.inject.} in 0 ..< w:
        let u {.inject, used.} = (x.float32 + 0.5'f32) / w.float32
        let v {.inject, used.} = (y.float32 + 0.5'f32) / h.float32
        var c {.inject.}: C
        body
        dst[].put(x, y, c))

proc mixImg(a, b: Img, t: float32): Img =
  result.eachPixel(a.w, a.h):
    c = mix(a.get(x, y), b.get(x, y), t)

proc boxBlur(im: Img, rx, ry: int): Img =
  ## A box blur `rx` pixels across and `ry` down, by running sums.
  result = im
  let (w, h) = (im.w, im.h)
  if rx > 0:
    var tmp = newImg(w, h)
    let (src, dst) = (addr result, addr tmp)
    let n = 2 * rx + 1
    eachRows(h, proc (y0, y1: int) {.closure, gcsafe.} =
      for y in y0 ..< y1:
        let row = y * w * 3
        for ch in 0 .. 2:
          var s = 0
          for k in -rx .. rx: s += src.px[row + clamp(k, 0, w - 1) * 3 + ch].int
          for x in 0 ..< w:
            dst.px[row + x * 3 + ch] = uint8((s + n div 2) div n)
            s += src.px[row + min(x + rx + 1, w - 1) * 3 + ch].int -
              src.px[row + max(x - rx, 0) * 3 + ch].int)
    result = tmp
  if ry > 0:
    var tmp = newImg(w, h)
    let (src, dst) = (addr result, addr tmp)
    let n = 2 * ry + 1
    # Bands of columns, so each writes only its own.
    eachRows(w, proc (x0, x1: int) {.closure, gcsafe.} =
      for x in x0 ..< x1:
        for ch in 0 .. 2:
          let col = x * 3 + ch
          var s = 0
          for k in -ry .. ry: s += src.px[clamp(k, 0, h - 1) * w * 3 + col].int
          for y in 0 ..< h:
            dst.px[y * w * 3 + col] = uint8((s + n div 2) div n)
            s += src.px[min(y + ry + 1, h - 1) * w * 3 + col].int -
              src.px[max(y - ry, 0) * w * 3 + col].int)
    result = tmp

proc halve(im: Img): Img =
  result.eachPixel(max(1, im.w div 2), max(1, im.h div 2)):
    c = (im.get(2 * x, 2 * y) + im.get(2 * x + 1, 2 * y) +
      im.get(2 * x, 2 * y + 1) + im.get(2 * x + 1, 2 * y + 1)) * 0.25'f32

proc grow(im: Img, w, h: int): Img =
  ## `im` scaled up to `w` by `h`.
  let kx = im.w.float32 / w.float32
  let ky = im.h.float32 / h.float32
  result.eachPixel(w, h):
    c = im.sample((x.float32 + 0.5'f32) * kx, (y.float32 + 0.5'f32) * ky)

proc blur(im: Img, r: float32): Img =
  ## Close to a Gaussian of radius `r`: three box passes, at half size for a
  ## wide one, which loses nothing it would keep.
  if r >= 8 and im.w >= 16 and im.h >= 16:
    return im.halve.blur(r / 2).grow(im.w, im.h)
  let k = int(round(r / 1.7'f32))
  if k < 1: return im
  im.boxBlur(k, k).boxBlur(k, k).boxBlur(k, k)

proc motion(im: Img, bx, by: float32): Img =
  ## Motion blur over `bx` pixels across and `by` down.
  im.boxBlur(int(abs(bx) / 2), int(abs(by) / 2))

proc zoomBlur(im: Img, cx, cy, strength: float32): Img =
  ## Streaks toward (`cx`, `cy`) (fractions of the frame), each `strength`
  ## of the way there.
  if strength < 0.002: return im
  if im.w > 480: return im.halve.zoomBlur(cx, cy, strength).grow(im.w, im.h)
  let n = clamp(int(ceil(strength * 40)), 3, 16)
  let pcx = cx * im.w.float32
  let pcy = cy * im.h.float32
  result.eachPixel(im.w, im.h):
    let dx = x.float32 + 0.5'f32 - pcx
    let dy = y.float32 + 0.5'f32 - pcy
    for k in 0 ..< n:
      let f = 1 - strength * k.float32 / n.float32
      c = c + im.sample(pcx + dx * f, pcy + dy * f)
    c = c * (1 / n.float32)

proc spinBlur(im: Img, angle: float32): Img =
  ## Arcs around the center through `angle` radians.
  if abs(angle) < 0.002: return im
  if im.w > 480: return im.halve.spinBlur(angle).grow(im.w, im.h)
  let n = clamp(int(ceil(abs(angle) * 30)), 3, 16)
  let cx = im.w.float32 / 2
  let cy = im.h.float32 / 2
  result.eachPixel(im.w, im.h):
    let dx = x.float32 + 0.5'f32 - cx
    let dy = y.float32 + 0.5'f32 - cy
    for k in 0 ..< n:
      let t = angle * (k.float32 / float32(n - 1) - 0.5'f32)
      let (sn, cs) = (sin(t), cos(t))
      c = c + im.sample(cx + dx * cs - dy * sn, cy + dx * sn + dy * cs)
    c = c * (1 / n.float32)

func place(im: Img, x, y: float32, sx, sy, angle, dx, dy: float32): (C, float32) =
  ## The picture scaled by `sx`, `sy` and turned by `angle` about the center,
  ## then moved by `dx`, `dy` pixels, as seen at (`x`, `y`); with how much it
  ## covers there.
  let cx = im.w.float32 / 2
  let cy = im.h.float32 / 2
  let px = x - cx - dx
  let py = y - cy - dy
  let (sn, cs) = (sin(-angle), cos(-angle))
  let rx = (px * cs - py * sn) / sx + cx
  let ry = (px * sn + py * cs) / sy + cy
  if not im.inside(rx, ry): return (black, 0'f32)
  (im.sample(rx, ry), 1'f32)

func placeOver(under: Img, im: Img, x, y: int, sx, sy, angle, dx, dy: float32): C =
  let (c, cover) = im.place(x.float32 + 0.5'f32, y.float32 + 0.5'f32, sx, sy,
    angle, dx, dy)
  if cover > 0: c else: under.get(x, y)

func turned(im: Img, x, y: float32, angle: float32, vertical: bool,
    pivot = 0.5'f32): (C, float32) =
  ## The picture turned in 3D by `angle` about a line through it (up and down,
  ## or with `vertical` across) at `pivot`, seen in perspective.
  let (w, h) = (im.w.float32, im.h.float32)
  let (len, other) = (if vertical: (h, w) else: (w, h))
  let s = (if vertical: y else: x) / len - pivot # along the turn
  let t = (if vertical: x else: y) / other - 0.5'f32
  let k = 0.6'f32 # perspective strength
  let (sn, cs) = (sin(angle), cos(angle))
  let denom = cs - s * k * sn
  if abs(denom) < 1e-4: return (black, 0'f32)
  let ps = s / denom
  let z = ps * sn
  let pt = t * (1 + z * k)
  let ix = (if vertical: (pt + 0.5'f32) * other else: (ps + pivot) * len)
  let iy = (if vertical: (ps + pivot) * len else: (pt + 0.5'f32) * other)
  if not im.inside(ix, iy) or 1 + z * k <= 0: return (black, 0'f32)
  let shade = clamp(0.55'f32 + 0.45'f32 * abs(cs), 0, 1)
  (im.sample(ix, iy) * shade, 1'f32)

func starRadius(a: float32, outer, inner: float32): float32 =
  ## How far a five-point star reaches at angle `a`.
  const sector = 2 * PI.float32 / 5
  var t = a - floor(a / sector) * sector
  t = abs(t - sector / 2)
  let half = sector / 2
  # The edge from the inner corner (t = 0) to the tip (t = half).
  let (x0, y0) = (inner, 0'f32)
  let (x1, y1) = (outer * cos(half), outer * sin(half))
  let dx = x1 - x0
  let dy = y1 - y0
  let (cx, cy) = (cos(t), sin(t))
  let denom = cx * dy - cy * dx
  if abs(denom) < 1e-6: return inner
  (x0 * dy - y0 * dx) / denom

func leakColor(u, v, p: float32, warm: bool, seed: uint32): C =
  ## A drifting blot of colored light for leaks.
  let cx = -0.4'f32 + 1.8'f32 * p
  let cy = 0.3'f32 + 0.4'f32 * noise(p * 2, 0, seed)
  let d = sqrt((u - cx) * (u - cx) * 1.6'f32 + (v - cy) * (v - cy))
  let blot = exp(-d * d * 4) * (0.6'f32 + 0.4'f32 * fbm(u * 3 + p, v * 3, seed))
  let hue = if warm: 0.02'f32 + 0.09'f32 * u else: fract(u * 0.8'f32 + p * 0.6'f32)
  var rgb: C
  let h6 = hue * 6
  for i, off in [0'f32, 4, 2]:
    let k = h6 + off - floor((h6 + off) / 6) * 6
    let ch = 255 * (1 - 0.85'f32 * clamp01(min(k, 4 - k)))
    case i
    of 0: rgb.r = ch
    of 1: rgb.g = ch
    else: rgb.b = ch
  rgb * clamp01(blot * 1.8'f32)

proc render*(kind: TransitionKind, a, b, under: Img, p: float32, frame,
    frames: int, seed: uint32, color: C = black): Img =
  ## `frame` counts frames into the transition, of its `frames`, for flicker
  ## that changes every frame and blur that spans one. `color` is the dip
  ## color.
  let (w, h) = (a.w, a.h)
  let (fw, fh) = (w.float32, h.float32)
  let e = easeInOut(p)
  let fseed = seed + uint32(frame) * 7919'u32
  let mid = smooth(0.42, 0.58, p)

  case kind
  of tkDissolve, tkCrossDissolveLegacy:
    result = mixImg(a, b, p)

  of tkMorphCut:
    result = mixImg(a, b, smooth(0, 1, p))

  of tkAdditiveDissolve, tkAdditiveDissolveLegacy:
    let ka = min(1'f32, 2 * (1 - p))
    let kb = min(1'f32, 2 * p)
    result.eachPixel(w, h):
      c = a.get(x, y) * ka + b.get(x, y) * kb

  of tkBlurDissolve, tkVrSphericalBlur:
    let r = bell(p) * fh / 25
    result = mixImg(a.blur(r), b.blur(r), smooth(0.25, 0.75, p))

  of tkBurnAlpha:
    let first = p < 0.5
    let q = (if first: 2 * p else: 2 * p - 1)
    result.eachPixel(w, h):
      let src = (if first: a.get(x, y) else: b.get(x, y))
      let l = luma(src)
      let edge = (if first: q else: 1 - q)
      let k = (if first: smooth(edge - 0.08, edge + 0.08, l)
               else: smooth(edge - 0.08, edge + 0.08, l))
      let glow = clamp01(1 - abs(l - edge) / 0.08'f32) * bell(p)
      c = mix(under.get(x, y), src, k) + (255'f32, 130'f32, 40'f32) * (glow * 0.7'f32)

  of tkDipToBlack, tkDipToWhite, tkDipToColor:
    let dip = (if kind == tkDipToBlack: black elif kind == tkDipToWhite: white
               else: color)
    let first = p < 0.5
    let k = (if first: smooth(0, 1, 2 * p) else: 1 - smooth(0, 1, 2 * p - 1))
    let src = (if first: a else: b).blur(
      if kind == tkDipToColor: bell(p) * fh / 40 else: 0'f32)
    result.eachPixel(w, h):
      c = mix(src.get(x, y), dip, k)

  of tkFilmDissolve, tkFilmDissolveLegacy:
    var toLin: array[256, float32]
    for i in 0 .. 255: toLin[i] = pow(i.float32 / 255, 2.2'f32)
    result = newImg(w, h)
    for i in 0 ..< a.px.len:
      let l = toLin[a.px[i]] + (toLin[b.px[i]] - toLin[a.px[i]]) * p
      result.px[i] = uint8(clamp(pow(l, 1 / 2.2'f32) * 255 + 0.5'f32, 0, 255))

  of tkLumaFade:
    let t = 1.2'f32 - 1.4'f32 * p
    result.eachPixel(w, h):
      let cb = b.get(x, y)
      c = mix(a.get(x, y), cb, smooth(t - 0.2'f32, t, luma(cb)))

  of tkMosaic, tkVrRandomBlocks:
    let cells = (if kind == tkMosaic: 9 else: 8)
    let cell = max(2, h div cells)
    result.eachPixel(w, h):
      let (cx, cy) = (x div cell, y div cell)
      let th = hashi(cx, cy, seed)
      if kind == tkVrRandomBlocks:
        c = (if p > th * 0.9'f32 + 0.05'f32: b.get(x, y) else: a.get(x, y))
      else:
        let cp = clamp01((p - th * 0.7'f32) / 0.3'f32)
        if cp <= 0: c = a.get(x, y)
        elif cp >= 1: c = b.get(x, y)
        else:
          let mx = cx * cell + cell div 2
          let my = cy * cell + cell div 2
          c = mix(a.get(mx, my), b.get(mx, my), cp)

  of tkBlockMotion:
    let (cols, rows) = (8, 5)
    let bw = fw / cols.float32
    let bh = fh / rows.float32
    result.eachPixel(w, h):
      let col = min(cols - 1, int(x.float32 / bw))
      let row = min(rows - 1, int(y.float32 / bh))
      let delay = float32(col + row) / float32(cols + rows - 2) * 0.5'f32
      let t = easeInOut(clamp01((p - delay) / 0.5'f32))
      let src = (if t < 0.5: a.unsafeAddr else: b.unsafeAddr)
      let s = (if t < 0.5: 1 - 2 * t else: 2 * t - 1)
      let ccx = (col.float32 + 0.5'f32) * bw
      let ccy = (row.float32 + 0.5'f32) * bh
      let fx = ccx + (x.float32 + 0.5'f32 - ccx) / max(s, 1e-3)
      let fy = ccy + (y.float32 + 0.5'f32 - ccy) / max(s, 1e-3)
      if s > 1e-3 and abs(fx - ccx) <= bw / 2 and abs(fy - ccy) <= bh / 2:
        c = src[].sample(fx, fy)
      else:
        c = under.get(x, y)

  of tkFlipMotion, tk3dSpin, tk3dSpinback:
    let angle = PI.float32 * e
    let vertical = kind == tk3dSpinback
    let shrink = (if kind == tkFlipMotion: 0'f32 else: 0.25'f32 * bell(p))
    let first = angle < PI / 2
    let src = (if first: a.unsafeAddr else: b.unsafeAddr)
    let ang = (if first: angle else: angle - PI.float32)
    result.eachPixel(w, h):
      let sx = (x.float32 + 0.5'f32 - fw / 2) / (1 - shrink) + fw / 2
      let sy = (y.float32 + 0.5'f32 - fh / 2) / (1 - shrink) + fh / 2
      let (cc, cover) = src[].turned(sx, sy, ang, vertical)
      c = (if cover > 0: cc else: under.get(x, y))

  of tkFoldMotion:
    # A flip clock: the top half of `a` folds down over the bottom, showing
    # the bottom half of `b` on its back.
    let angle = PI.float32 * e
    result.eachPixel(w, h):
      let top = v < 0.5
      c = (if top: b.get(x, y) else: a.get(x, y))
      if angle < PI / 2 and top:
        let (cc, cover) = a.turned(x.float32 + 0.5'f32, y.float32 + 0.5'f32,
          -angle, true)
        if cover > 0: c = cc
      elif angle >= PI / 2 and not top:
        let (cc, cover) = b.turned(x.float32 + 0.5'f32, y.float32 + 0.5'f32,
          PI.float32 - angle, true)
        if cover > 0: c = cc

  of tkPopMotion:
    let first = p < 0.5
    let s = (if first: 1 - easeInBack(2 * p) else: easeOutBack(2 * p - 1))
    let src = (if first: a.unsafeAddr else: b.unsafeAddr)
    result.eachPixel(w, h):
      c = (if s > 1e-3: under.placeOver(src[], x, y, s, s, 0, 0, 0)
           else: under.get(x, y))

  of tkPullMotion, tkZoomBlur, tkCrossZoom:
    let first = p < 0.5
    let q = (if first: easeIn(2 * p) else: 1 - easeOut(2 * p - 1))
    let grow = (if kind == tkPullMotion: 1.5'f32 else: 0.6'f32)
    let s = 1 + q * grow
    let src = (if first: a.unsafeAddr else: b.unsafeAddr)
    var scaled: Img
    scaled.eachPixel(w, h):
      c = src[].sample((x.float32 + 0.5'f32 - fw / 2) / s + fw / 2,
        (y.float32 + 0.5'f32 - fh / 2) / s + fh / 2)
    let strength = q * (if kind == tkCrossZoom: 0.5'f32 else: 0.35'f32)
    let streaked = scaled.zoomBlur(0.5, 0.5, strength)
    let flash = (if kind == tkCrossZoom: bell(p) * q * 0.3'f32 else: 0'f32)
    result.eachPixel(w, h):
      c = mix(streaked.get(x, y), white, flash)

  of tkSpinMotion:
    let first = p < 0.5
    let q = (if first: easeIn(2 * p) else: 1 - easeOut(2 * p - 1))
    let angle = (if first: q else: -q) * PI.float32
    let src = (if first: a.unsafeAddr else: b.unsafeAddr)
    var turnedImg: Img
    turnedImg.eachPixel(w, h):
      c = under.placeOver(src[], x, y, 1 + 0.4'f32 * q, 1 + 0.4'f32 * q, angle, 0, 0)
    result = turnedImg.spinBlur(q * 0.6'f32)

  of tkSpringMotion:
    # Damped spring, overshooting the rest position before it settles.
    let s = 1 - exp(-4.5'f32 * p) * cos(7 * p)
    let off = (1 - s) * fh
    result.eachPixel(w, h):
      let yy = y.float32 + 0.5'f32
      if yy >= off: c = b.sample(x.float32 + 0.5'f32, yy - off)
      elif yy >= off - fh: c = a.sample(x.float32 + 0.5'f32, yy - off + fh)
      else: c = under.get(x, y)

  of tkTravelMotion, tkPush, tkWhip:
    # Push eases as a smoothstep, with motion blur over about half a frame's
    # travel.
    let speed = (if kind == tkWhip: bell(p) * fw * 0.6'f32
                 elif kind == tkPush: 6 * p * (1 - p) * fw / frames.float32 * 0.5'f32
                 else: bell(p) * fw * 0.25'f32)
    let shift = -(if kind == tkPush: smooth(0, 1, p) else: e) * fw
    let dip = (if kind == tkTravelMotion: 1 - 0.12'f32 * bell(p) else: 1'f32)
    let am = a.motion(speed, 0)
    let bm = b.motion(speed, 0)
    result.eachPixel(w, h):
      let xx = (x.float32 + 0.5'f32 - fw / 2) / dip + fw / 2
      let yy = (y.float32 + 0.5'f32 - fh / 2) / dip + fh / 2
      if yy < 0 or yy >= fh:
        c = under.get(x, y)
      elif xx - shift < fw:
        c = am.sample(xx - shift, yy)
      else:
        c = bm.sample(xx - shift - fw, yy)

  of tkChaos, tkGlitch, tkVhsDamage:
    let amp = bell(p)
    let step = frame div 2
    let bands = (if kind == tkVhsDamage: 60 else: 14)
    result.eachPixel(w, h):
      let band = int(v * bands.float32)
      let r = hashi(band, step, seed)
      var useB = p > 0.5
      if kind != tkVhsDamage and abs(p - 0.5'f32) < 0.3'f32 and
          hashi(band, step + 99, seed) < amp * 0.6'f32:
        useB = not useB
      let src = (if useB: b.unsafeAddr else: a.unsafeAddr)
      var dx = 0'f32
      case kind
      of tkChaos:
        dx = (r - 0.5'f32) * amp * fw * 0.25'f32
      of tkGlitch:
        let blk = int(u * 6)
        if hashi(band * 7 + blk, step, seed) < amp * 0.5'f32:
          dx = (hashi(band, blk + step, seed) - 0.5'f32) * fw * 0.3'f32 * amp
      else:
        let track = fract(p * 1.7'f32 + 0.2'f32)
        let inTrack = abs(v - track) < 0.06'f32
        dx = (noise(v * 40, step.float32, seed) - 0.5'f32) * fw * 0.02'f32 * amp
        if inTrack: dx += (r - 0.5'f32) * fw * 0.15'f32 * amp
      let split = amp * fw * (if kind == tkVhsDamage: 0.012'f32 else: 0.02'f32)
      let xx = x.float32 + 0.5'f32 - dx
      let yy = y.float32 + 0.5'f32
      c = (src[].sample(xx - split, yy, true).r, src[].sample(xx, yy, true).g,
        src[].sample(xx + split, yy, true).b)
      if kind == tkVhsDamage:
        let grain = (hashi(x, y + step * 997, seed) - 0.5'f32) * 60 * amp
        c = c * (1 - 0.15'f32 * amp * float32(y mod 2)) + (grain, grain, grain)
      elif kind == tkChaos:
        c = mix(c, white, clamp01(amp * (r - 0.7'f32) * 2))

  of tkEarthquake:
    let amp = bell(p) * fh * 0.05'f32
    let t = frame.float32 * 0.9'f32
    let dx = (noise(t, 0, seed) - 0.5'f32) * 2 * amp
    let dy = (noise(t, 5, seed) - 0.5'f32) * 2 * amp
    let shaken = mixImg(a, b, mid).motion(0, amp * 1.5'f32)
    result.eachPixel(w, h):
      c = shaken.sample(x.float32 + 0.5'f32 - dx, y.float32 + 0.5'f32 - dy)

  of tkFlicker:
    let r = hashi(frame, 0, seed)
    let showB = r < smooth(0.15, 0.85, p) or p > 0.85
    let flash = 1 + bell(p) * (hashi(frame, 1, seed) - 0.3'f32) * 0.9'f32
    let src = (if showB: b.unsafeAddr else: a.unsafeAddr)
    result.eachPixel(w, h):
      c = src[].get(x, y) * flash

  of tkGlass:
    let cell = fh / 5
    let amp = bell(p) * fh * 0.06'f32
    result.eachPixel(w, h):
      let gx = x.float32 / cell
      let gy = y.float32 / cell
      var best = 1e9'f32
      var second = 1e9'f32
      var id = (0, 0)
      for oy in -1 .. 1:
        for ox in -1 .. 1:
          let cx = floor(gx).int + ox
          let cy = floor(gy).int + oy
          let px = cx.float32 + hashi(cx, cy, seed)
          let py = cy.float32 + hashi(cx, cy, seed + 1)
          let d = (gx - px) * (gx - px) + (gy - py) * (gy - py)
          if d < best:
            second = best
            best = d
            id = (cx, cy)
          elif d < second:
            second = d
      let ang = hashi(id[0], id[1], seed + 2) * 2 * PI.float32
      let th = hashi(id[0], id[1], seed + 3)
      let k = smooth(th * 0.6'f32, th * 0.6'f32 + 0.4'f32, p)
      let ddx = cos(ang) * amp
      let ddy = sin(ang) * amp
      let ca = a.sample(x.float32 + 0.5'f32 + ddx, y.float32 + 0.5'f32 + ddy)
      let cb = b.sample(x.float32 + 0.5'f32 - ddx, y.float32 + 0.5'f32 - ddy)
      let edge = clamp01(1 - (sqrt(second) - sqrt(best)) * 12) * bell(p)
      c = mix(ca, cb, k) + white * (edge * 0.35'f32)

  of tkGrunge:
    result.eachPixel(w, h):
      let n = fbm(u * 5, v * 3, seed) * 0.8'f32 + hashi(x, y, seed) * 0.2'f32
      let t = p * 1.3'f32 - 0.15'f32
      let k = smooth(t - 0.04'f32, t + 0.04'f32, 1 - n)
      let edge = clamp01(1 - abs(1 - n - t) / 0.06'f32)
      let grain = (hashi(x, y, fseed) - 0.5'f32) * 50 * bell(p)
      c = mix(b.get(x, y), a.get(x, y), k) * (1 - 0.6'f32 * edge) + (grain, grain, grain)

  of tkKaleidoscope:
    let k = bell(p)
    let mixed = mixImg(a, b, mid)
    let src = mixed.unsafeAddr
    let segs = 6
    let seg = 2 * PI.float32 / segs.float32
    let rot = p * PI.float32
    result.eachPixel(w, h):
      let dx = (u - 0.5'f32) * fw / fh
      let dy = v - 0.5'f32
      let r = sqrt(dx * dx + dy * dy)
      var ang = arctan2(dy, dx) + rot
      ang = ang - floor(ang / seg) * seg
      ang = abs(ang - seg / 2)
      let zoom = 1 - 0.5'f32 * k
      let kx = (0.5'f32 + cos(ang) * r * zoom * fh / fw) * fw
      let ky = (0.5'f32 + sin(ang) * r * zoom) * fh
      c = mix(src[].get(x, y), src[].sample(kx, ky, true), smooth(0, 0.6, k))

  of tkLiquidDistortion, tkWave:
    let amp = bell(p) * (if kind == tkWave: 0.04'f32 else: 0.08'f32)
    result.eachPixel(w, h):
      var dx, dy: float32
      if kind == tkWave:
        dx = sin(v * 14 + p * 12) * amp * fw
      else:
        dx = (fbm(u * 3, v * 3 + p, seed) - 0.5'f32) * 2 * amp * fw
        dy = (fbm(u * 3 + 7, v * 3 - p, seed) - 0.5'f32) * 2 * amp * fh
      let xx = x.float32 + 0.5'f32 + dx
      let yy = y.float32 + 0.5'f32 + dy
      if kind == tkWave:
        let edge = e * 1.3'f32 - 0.15'f32 + 0.05'f32 * sin(v * 9 + p * 8)
        c = (if u < edge: b.sample(xx, yy) else: a.sample(xx, yy))
      else:
        c = mix(a.sample(xx, yy), b.sample(xx, yy), smooth(0.3, 0.7, p))

  of tkTvPower:
    let first = p < 0.5
    let q = (if first: easeIn(2 * p) else: 1 - easeOut(2 * p - 1))
    let src = (if first: a.unsafeAddr else: b.unsafeAddr)
    let sy = max(0.004'f32, 1 - clamp01(q / 0.6'f32))
    let sx = max(0.004'f32, 1 - clamp01((q - 0.6'f32) / 0.4'f32))
    let boost = 1 + q * 1.5'f32
    result.eachPixel(w, h):
      let (cc, cover) = src[].place(x.float32 + 0.5'f32, y.float32 + 0.5'f32,
        sx, sy, 0, 0, 0)
      c = (if cover > 0: mix(cc * boost, white, clamp01(q - 0.5'f32))
           else: under.get(x, y))

  of tkVrChromaLeaks, tkChromaLeak, tkVrLightLeaks, tkLightLeak:
    let warm = kind in {tkLightLeak, tkVrLightLeaks}
    let k = bell(p)
    result.eachPixel(w, h):
      let base = mix(a.get(x, y), b.get(x, y), smooth(0.35, 0.65, p))
      c = screen(base, leakColor(u, v, p, warm, seed) * k)

  of tkVrGradientWipe:
    result.eachPixel(w, h):
      let g = fbm(u * 3, v * 2, seed)
      let t = p * 1.2'f32 - 0.1'f32
      c = mix(a.get(x, y), b.get(x, y), 1 - smooth(t - 0.08'f32, t + 0.08'f32, g))

  of tkVrIrisWipe, tkRadialWipe:
    let maxR = sqrt(0.25'f32 * fw * fw / (fh * fh) + 0.25'f32)
    let r = e * maxR * 1.05'f32
    result.eachPixel(w, h):
      let dx = (u - 0.5'f32) * fw / fh
      let dy = v - 0.5'f32
      let d = sqrt(dx * dx + dy * dy)
      c = mix(a.get(x, y), b.get(x, y), 1 - smooth(r - 0.01'f32, r + 0.01'f32, d))

  of tkVrLightRays, tkRay:
    let k = bell(p)
    let base = mixImg(a, b, mid)
    var bright: Img
    bright.eachPixel(w, h):
      let cc = base.get(x, y)
      c = cc * clamp01((luma(cc) - 0.55'f32) * 3)
    let rays = bright.zoomBlur(0.5, 0.25, 0.7)
    result.eachPixel(w, h):
      c = base.get(x, y) + rays.get(x, y) * (k * 2.5'f32)

  of tkVrMobiusZoom:
    let k = bell(p)
    let mixed = mixImg(a, b, mid)
    let src = mixed.unsafeAddr
    result.eachPixel(w, h):
      let dx = (u - 0.5'f32) * fw / fh
      let dy = v - 0.5'f32
      let r = sqrt(dx * dx + dy * dy)
      let ang = arctan2(dy, dx) + k * 3 * max(0'f32, 0.8'f32 - r)
      let rr = r * (1 - 0.4'f32 * k)
      c = src[].sample((0.5'f32 + cos(ang) * rr * fh / fw) * fw,
        (0.5'f32 + sin(ang) * rr) * fh, true)

  of tkBurnChroma:
    let ex = bell(p) * 3
    let mixed = mixImg(a, b, mid)
    let src = mixed.unsafeAddr
    result.eachPixel(w, h):
      let cc = src[].get(x, y)
      let gains = [1 + ex * 1.3'f32, 1 + ex, 1 + ex * 0.7'f32]
      c = (255 * (1 - exp(-cc.r / 255 * gains[0] * 1.6'f32)) / (1 - exp(-1.6'f32)),
           255 * (1 - exp(-cc.g / 255 * gains[1] * 1.6'f32)) / (1 - exp(-1.6'f32)),
           255 * (1 - exp(-cc.b / 255 * gains[2] * 1.6'f32)) / (1 - exp(-1.6'f32)))

  of tkDirectionalBlur:
    let r = int(bell(p) * fw / 12)
    result = mixImg(a.boxBlur(r, 0).boxBlur(r, 0), b.boxBlur(r, 0).boxBlur(r, 0), mid)

  of tkFlare:
    let k = bell(p)
    let fx = -0.2'f32 + 1.4'f32 * p
    let fy = 0.35'f32
    result.eachPixel(w, h):
      let base = mix(a.get(x, y), b.get(x, y), mid)
      let dx = (u - fx) * fw / fh
      let dy = v - fy
      let core = exp(-(dx * dx + dy * dy) * 60)
      let halo = exp(-(dx * dx + dy * dy) * 6) * 0.4'f32
      let streak = exp(-dy * dy * 2500) * exp(-dx * dx * 1.5'f32) * 0.7'f32
      let gx = (u - (1 - fx)) * fw / fh
      let gy = v - (1 - fy)
      let ghost = clamp01(1 - abs(sqrt(gx * gx + gy * gy) - 0.08'f32) * 40) * 0.25'f32
      let light = (255'f32, 225'f32, 170'f32) * ((core + halo + streak + ghost) * k)
      c = screen(base, light)

  of tkFlash:
    let k = pow(bell(p), 2)
    result.eachPixel(w, h):
      c = mix(mix(a.get(x, y), b.get(x, y), mid), white, k)

  of tkGlow, tkLensBlur, tkSolarize, tkRadialBlur:
    let base = mixImg(a, b, mid)
    let k = bell(p)
    case kind
    of tkGlow:
      var bright: Img
      bright.eachPixel(w, h):
        let cc = base.get(x, y)
        c = cc * clamp01((luma(cc) - 0.4'f32) * 2)
      let bloom = bright.blur(fh / 15)
      result.eachPixel(w, h):
        c = screen(base.get(x, y) * (1 + 0.3'f32 * k), bloom.get(x, y) * (k * 2))
    of tkLensBlur:
      let r = int(k * fh / 40)
      result = base.boxBlur(r, r).boxBlur(r, r)
    of tkSolarize:
      result.eachPixel(w, h):
        let cc = base.get(x, y)
        let sol: C = ((if cc.r > 127: 255 - cc.r else: cc.r),
                      (if cc.g > 127: 255 - cc.g else: cc.g),
                      (if cc.b > 127: 255 - cc.b else: cc.b))
        c = mix(cc, sol * 2, k)
    else:
      result = base.spinBlur(k * 0.5'f32)

  of tkLightSweep:
    let center = -0.25'f32 + 1.5'f32 * e
    result.eachPixel(w, h):
      let s = (u * fw / fh + v * 0.5'f32) / (fw / fh + 0.5'f32)
      c = (if s < center: b.get(x, y) else: a.get(x, y))
      let band = exp(-pow((s - center) / 0.05'f32, 2))
      c = screen(c, white * (band * 0.9'f32))

  of tkPhosphor:
    result.eachPixel(w, h):
      let cb = b.get(x, y)
      let m = luma(cb) * 0.5'f32 + fbm(u * 6, v * 4, seed) * 0.5'f32
      let t = 1.15'f32 - p * 1.3'f32
      let k = smooth(t - 0.03'f32, t + 0.03'f32, m)
      let edge = clamp01(1 - abs(m - t) / 0.07'f32)
      c = mix(a.get(x, y), cb, k)
      c = screen(c, (255'f32, 120'f32, 20'f32) * edge + (255'f32, 230'f32, 120'f32) *
        (edge * edge))

  of tkStripe:
    let n = 12
    result.eachPixel(w, h):
      let s = u * cos(0.35'f32) + v * sin(0.35'f32) * fh / fw
      let i = int(floor(s * n.float32))
      let local = s * n.float32 - i.float32
      let t = clamp01((p * 1.6'f32 - float32(i mod n) / n.float32 * 0.6'f32))
      c = (if local < easeInOut(t): b.get(x, y) else: a.get(x, y))

  of tk3dRoll:
    # A cube turning upward: `a` leaves over the top as `b` comes up from
    # below.
    let angle = PI.float32 / 2 * e
    result.eachPixel(w, h):
      let yy = y.float32 + 0.5'f32
      let split = fh * (1 - e)
      if yy < split:
        let t = yy / max(split, 1e-3)
        let (cc, cover) = a.turned(x.float32 + 0.5'f32, t * fh, angle, true, 1)
        c = (if cover > 0: cc else: under.get(x, y))
      else:
        let t = (yy - split) / max(fh - split, 1e-3)
        let (cc, cover) = b.turned(x.float32 + 0.5'f32, t * fh,
          angle - PI.float32 / 2, true, 0)
        c = (if cover > 0: cc else: under.get(x, y))

  of tkFilmRoll, tkRoll:
    let gap = (if kind == tkFilmRoll: fh * 0.08'f32 else: 0'f32)
    let shift = e * (fh + gap)
    let blurY = bell(p) * fh * 0.25'f32
    let am = a.motion(0, blurY)
    let bm = b.motion(0, blurY)
    result.eachPixel(w, h):
      let yy = y.float32 + 0.5'f32 + shift
      if yy < fh:
        c = am.sample(x.float32 + 0.5'f32, yy)
      elif yy < fh + gap:
        let hole = kind == tkFilmRoll and (u < 0.04'f32 or u > 0.96'f32) and
          int((yy - fh) / (gap / 3)) == 1
        c = (if hole: (200'f32, 200'f32, 200'f32) else: (10'f32, 10'f32, 10'f32))
      else:
        c = bm.sample(x.float32 + 0.5'f32, yy - fh - gap)

  of tkSlide:
    let off = -(1 - easeOut(p)) * fh
    let bm = b.motion(0, (1 - p) * fh * 0.15'f32)
    result.eachPixel(w, h):
      let yy = y.float32 + 0.5'f32 - off
      c = (if yy < fh: bm.sample(x.float32 + 0.5'f32, yy) else: a.get(x, y))

  of tkSplit:
    let off = e * fw / 2
    let sb = 1.1'f32 - 0.1'f32 * e
    result.eachPixel(w, h):
      let xx = x.float32 + 0.5'f32
      if xx < fw / 2 - off: c = a.sample(xx + off, y.float32 + 0.5'f32)
      elif xx >= fw / 2 + off: c = a.sample(xx - off, y.float32 + 0.5'f32)
      else: c = under.placeOver(b, x, y, sb, sb, 0, 0, 0)

  of tkStretch:
    let edge = 1 - e
    result.eachPixel(w, h):
      if u < edge: c = a.sample(u / edge * fw, y.float32 + 0.5'f32)
      else: c = b.sample((u - edge) / max(1 - edge, 1e-3) * fw, y.float32 + 0.5'f32)

  of tkMotionCamera:
    let first = p < 0.5
    let q = (if first: easeIn(2 * p) else: 1 - easeOut(2 * p - 1))
    let src = (if first: a.unsafeAddr else: b.unsafeAddr)
    let angle = (if first: 1'f32 else: -1'f32) * q * 0.12'f32
    var moved: Img
    moved.eachPixel(w, h):
      c = under.placeOver(src[], x, y, 1 + 0.6'f32 * q, 1 + 0.6'f32 * q, angle, 0, 0)
    result = moved.zoomBlur(0.5, 0.5, q * 0.3'f32)

  of tkMotionTween:
    result.eachPixel(w, h):
      let (ca, cova) = a.place(x.float32 + 0.5'f32, y.float32 + 0.5'f32,
        1 - 0.5'f32 * e, 1 - 0.5'f32 * e, 0, -e * fw * 0.5'f32, 0)
      let (cb, covb) = b.place(x.float32 + 0.5'f32, y.float32 + 0.5'f32,
        0.5'f32 + 0.5'f32 * e, 0.5'f32 + 0.5'f32 * e, 0, (1 - e) * fw * 0.5'f32, 0)
      c = under.get(x, y)
      if cova > 0: c = mix(c, ca, 1 - e)
      if covb > 0: c = mix(c, cb, e)

  of tkShapeDissolve:
    let cell = fh / 8
    result.eachPixel(w, h):
      let cx = floor(x.float32 / cell)
      let cy = floor(y.float32 / cell)
      let d = hashi(cx.int, cy.int, seed)
      let r = clamp01(p * 1.5'f32 - d * 0.5'f32) * cell * 0.75'f32
      let dx = x.float32 + 0.5'f32 - (cx + 0.5'f32) * cell
      let dy = y.float32 + 0.5'f32 - (cy + 0.5'f32) * cell
      let dist = sqrt(dx * dx + dy * dy)
      c = mix(a.get(x, y), b.get(x, y), 1 - smooth(r - 1.5'f32, r + 1.5'f32, dist))

  of tkShapeFlow:
    let k = e * 1.15'f32
    let hw = fw / 2 * k
    let hh = fh / 2 * k
    let rad = fh * 0.1'f32 * k
    let line = fh * 0.008'f32
    result.eachPixel(w, h):
      let qx = abs(x.float32 + 0.5'f32 - fw / 2) - (hw - rad)
      let qy = abs(y.float32 + 0.5'f32 - fh / 2) - (hh - rad)
      let outside = sqrt(max(qx, 0) * max(qx, 0) + max(qy, 0) * max(qy, 0))
      let d = outside + min(max(qx, qy), 0) - rad
      c = mix(b.get(x, y), a.get(x, y), smooth(-0.75, 0.75, d))
      c = mix(c, white, clamp01(1 - abs(d - line) / line) * bell(p))

  of tkTextAnimator:
    let n = 12
    result.eachPixel(w, h):
      let i = int(u * n.float32)
      let t = easeOut(clamp01((p - i.float32 / n.float32 * 0.5'f32) / 0.5'f32))
      let yy = y.float32 + 0.5'f32 + (1 - t) * fh * 0.3'f32
      let cb = (if yy < fh: b.sample(x.float32 + 0.5'f32, yy) else: a.get(x, y))
      c = mix(a.get(x, y), cb, t)

  of tkTypewriter:
    let n = 24
    let shown = p * float32(n + 1)
    result.eachPixel(w, h):
      let i = u * n.float32
      c = (if i + 1 <= shown: b.get(x, y) else: a.get(x, y))
      let caret = floor(shown).float32
      if abs(i - caret) < 0.12'f32 and frame mod 8 < 5 and p < 0.98:
        c = white

  of tkFrame:
    let border = fh * 0.025'f32
    let sMin = 0.72'f32
    let (scale, slide) =
      if p < 0.3: (1 - (1 - sMin) * easeInOut(p / 0.3'f32), 0'f32)
      elif p < 0.7: (sMin, easeInOut((p - 0.3'f32) / 0.4'f32))
      else: (sMin + (1 - sMin) * easeInOut((p - 0.7'f32) / 0.3'f32), 1'f32)
    let pitch = fw * scale + fw * 0.08'f32
    result.eachPixel(w, h):
      c = (30'f32, 30'f32, 30'f32)
      for side in 0 .. 1:
        let dx = (if side == 0: -slide * pitch else: (1 - slide) * pitch)
        let px = x.float32 + 0.5'f32 - fw / 2 - dx
        let py = y.float32 + 0.5'f32 - fh / 2
        let hw = fw * scale / 2
        let hh = fh * scale / 2
        if abs(px) < hw + border and abs(py) < hh + border:
          if abs(px) < hw and abs(py) < hh:
            let src = (if side == 0: unsafeAddr a else: unsafeAddr b)
            c = src[].sample(px / scale + fw / 2, py / scale + fh / 2)
          else:
            c = white

  of tkLouver:
    let n = 8
    let sw = fw / n.float32
    result.eachPixel(w, h):
      let i = min(n - 1, int(x.float32 / sw))
      let t = clamp01((p * 1.4'f32 - i.float32 / n.float32 * 0.4'f32))
      let angle = PI.float32 * easeInOut(t)
      let first = angle < PI / 2
      let src = (if first: a.unsafeAddr else: b.unsafeAddr)
      let k = abs(cos(angle))
      let cx = (i.float32 + 0.5'f32) * sw
      let off = (x.float32 + 0.5'f32 - cx) / max(k, 1e-3)
      if abs(off) <= sw / 2 and k > 1e-3:
        c = src[].sample(cx + off, y.float32 + 0.5'f32) * (0.5'f32 + 0.5'f32 * k)
      else:
        c = under.get(x, y)

  of tkMirror:
    let half = e / 2
    result.eachPixel(w, h):
      let d = abs(u - 0.5'f32)
      if d < half:
        c = b.get(x, y)
      else:
        let ref1 = 0.5'f32 + (if u > 0.5: 1 else: -1) * (2 * half - d)
        let fade = clamp01(1 - (d - half) / 0.12'f32) * 0.5'f32
        c = mix(a.get(x, y), b.sample(ref1 * fw, y.float32 + 0.5'f32), fade * bell(p))

  of tkPagePeel:
    # The bottom left corner lifts and rolls up toward the top right, the
    # fold turning as it goes; the roll shows the incoming picture on its
    # back.
    let theta = (60 - 70 * p) * PI.float32 / 180
    let nx = cos(theta)
    let ny = -sin(theta)
    let r = fh * 0.14'f32
    var far = 0'f32
    for (cx, cy) in [(0'f32, 0'f32), (fw, 0'f32), (fw, fh), (0'f32, fh)]:
      far = max(far, cx * nx + (cy - fh) * ny)
    let d = smooth(0, 1, p) * (far + r) - r
    result.eachPixel(w, h):
      let qx = x.float32 + 0.5'f32
      let qy = y.float32 + 0.5'f32
      let t = qx * nx + (qy - fh) * ny
      let s = t - d
      if s < 0:
        # Shadowed where the roll is near.
        c = b.get(x, y) * (1 - 0.35'f32 * exp(s / (r * 0.6'f32)))
      elif s < r:
        # Back to where this part of the page lay before it rolled.
        let arc = r * (PI.float32 - arcsin(s / r))
        let back = t - (d - arc)
        let shade = 0.6'f32 + 0.4'f32 * sqrt(max(0'f32, 1 - (s / r) * (s / r)))
        c = b.sample(qx - back * nx, qy - back * ny) * shade
      else:
        c = a.get(x, y)

  of tkPagePeelObsolete, tkPageTurn:
    # The page lifts from the bottom right corner and folds back over itself:
    # a peel shows a pale back, a turn the picture through the page.
    let nx = 1 / sqrt(2'f32)
    let diag = sqrt(fw * fw + fh * fh)
    let reach = p * diag * 1.15'f32
    let back = (if kind == tkPageTurn: 0'f32 else: 0.55'f32)
    let ox = fw - nx * reach
    let oy = fh - nx * reach
    result.eachPixel(w, h):
      let qx = x.float32 + 0.5'f32
      let qy = y.float32 + 0.5'f32
      let s = (qx - ox) * nx + (qy - oy) * nx
      if s > 0:
        c = b.get(x, y) * (1 - 0.5'f32 * exp(-s / (fh * 0.04'f32)))
      else:
        let rx = qx - 2 * s * nx
        let ry = qy - 2 * s * nx
        if a.inside(rx, ry) and -s < reach / 2:
          c = mix(a.sample(rx, ry), white, back) * (0.75'f32 + 0.25'f32 *
            clamp01(-s / (fh * 0.1'f32)))
        else:
          c = a.get(x, y)

  of tkSlice:
    let n = 10
    let ang = 1.0'f32
    let travel = e * fh * 1.3'f32
    let am = a.motion(0, bell(p) * fh * 0.1'f32)
    result.eachPixel(w, h):
      let s = (u * cos(ang) * fw / fh + v * sin(ang))
      let i = int(floor(s * n.float32 / 1.5'f32))
      let dir = (if i mod 2 == 0: 1'f32 else: -1'f32)
      let yy = y.float32 + 0.5'f32 - dir * travel
      c = (if yy >= 0 and yy < fh: am.sample(x.float32 + 0.5'f32, yy) else: b.get(x, y))

  of tkClockWipe:
    # The hand moves as a smoothstep, its edge feathered over about ten
    # degrees either side.
    const soft = 10'f32 / 360
    let hand = smooth(0, 1, p) * (1 + 2 * soft) - soft
    result.eachPixel(w, h):
      let dx = (u - 0.5'f32) * fw / fh
      let dy = v - 0.5'f32
      var ang = arctan2(dx, -dy) / (2 * PI.float32)
      if ang < 0: ang += 1
      c = mix(a.get(x, y), b.get(x, y), 1 - smooth(hand - soft, hand + soft, ang))

  of tkLinearWipe, tkSoftWipe, tkNeonWipe:
    let soft = (if kind == tkSoftWipe: 0.25'f32 else: 0.01'f32)
    result.eachPixel(w, h):
      let s = (if kind == tkSoftWipe: (u * fw / fh + v * 0.4'f32) / (fw / fh + 0.4'f32)
               else: u)
      let edge = e * (1 + 2 * soft) - soft
      c = mix(a.get(x, y), b.get(x, y), 1 - smooth(edge - soft, edge + soft, s))
      if kind == tkNeonWipe:
        let d = (s - edge) * fw
        let glow = exp(-d * d / (fh * fh * 0.0004'f32)) * bell(p) * 1.4'f32
        let tint = mix((40'f32, 220'f32, 255'f32), (255'f32, 40'f32, 220'f32), v)
        c = screen(c, tint * glow)

  of tkPanelWipe:
    let n = 4
    result.eachPixel(w, h):
      c = a.get(x, y)
      for i in countdown(n - 1, 0):
        let t = easeInOut(clamp01((p - i.float32 / n.float32 * 0.5'f32) / 0.5'f32))
        let left = i.float32 / n.float32 + (1 - t) * (1 - i.float32 / n.float32)
        let right = left + 1 / n.float32
        if u >= left and u < right and t > 0:
          c = b.get(x, y)
          let edgeD = (u - left) * fw
          c = screen(c, white * (exp(-edgeD / (fw * 0.01'f32)) * 0.4'f32 * bell(t)))

  of tkPlateauWipe:
    let n = 6
    result.eachPixel(w, h):
      let i = min(n - 1, int(v * n.float32))
      let t = easeInOut(clamp01((p - abs(i.float32 - 2.5'f32) / 2.5'f32 * 0.4'f32) /
        0.6'f32))
      c = (if u < t: b.get(x, y) else: a.get(x, y))

  of tkStarWipe:
    let maxR = sqrt(0.25'f32 * fw * fw / (fh * fh) + 0.25'f32) * 2.2'f32
    let outer = e * maxR
    result.eachPixel(w, h):
      let dx = (u - 0.5'f32) * fw / fh
      let dy = v - 0.5'f32
      let ang = arctan2(dx, -dy)
      let r = sqrt(dx * dx + dy * dy)
      let edge = starRadius(ang + PI.float32 / 5, outer, outer * 0.45'f32)
      c = mix(a.get(x, y), b.get(x, y), 1 - smooth(edge - 0.004'f32, edge + 0.004'f32, r))

  of tkStretchWipe:
    let edge = e * 1.4'f32 - 0.2'f32
    let band = 0.2'f32
    result.eachPixel(w, h):
      if u < edge:
        let su = max(u, edge - band)
        c = b.sample(max(su, 0) * fw, y.float32 + 0.5'f32)
        if u < edge - band: c = b.get(x, y)
      else:
        let su = min(u, edge + band)
        c = (if u > edge + band: a.get(x, y) else: a.sample(clamp(su, 0, 1) * fw,
          y.float32 + 0.5'f32))

  # The legacy transitions move at a constant rate, without easing, and
  # their wipes have hard edges.
  of tkDipToBlackLegacy, tkDipToWhiteLegacy:
    let dip = (if kind == tkDipToBlackLegacy: black else: white)
    let first = p < 0.5
    let src = (if first: a.unsafeAddr else: b.unsafeAddr)
    let k = (if first: 2 * p else: 2 - 2 * p)
    result.eachPixel(w, h):
      c = mix(src[].get(x, y), dip, k)

  of tkNonAdditiveDissolve:
    # Whichever picture is brighter at a pixel shows there.
    let ka = min(1'f32, 2 * (1 - p))
    let kb = min(1'f32, 2 * p)
    result.eachPixel(w, h):
      let ca = a.get(x, y) * ka
      let cb = b.get(x, y) * kb
      c = (if luma(ca) >= luma(cb): ca else: cb)

  of tkClockWipeLegacy, tkRadialWipeLegacy:
    # A hand sweeping clockwise from twelve about the center, or a quarter
    # turn from the top about the top left corner.
    let corner = kind == tkRadialWipeLegacy
    result.eachPixel(w, h):
      let dx = (if corner: u else: u - 0.5'f32) * fw / fh
      let dy = (if corner: v else: v - 0.5'f32)
      var ang = arctan2(dx, -dy) / (2 * PI.float32)
      if ang < 0: ang += 1
      if corner: ang = clamp01((ang - 0.25'f32) * 4)
      c = (if ang < p: b.get(x, y) else: a.get(x, y))

  of tkIrisBox, tkIrisCross, tkIrisDiamond, tkIrisRound, tkBarnDoors, tkInset,
      tkWipe:
    # The incoming picture opens as a shape: points whose distance by the
    # shape's measure is under the threshold show it.
    let asp = fw / fh
    proc dist(u, v: float32): float32 =
      let dx = abs(u - 0.5'f32) * asp
      let dy = abs(v - 0.5'f32)
      case kind
      of tkIrisBox: max(dx, dy)
      of tkIrisDiamond: dx + dy
      of tkIrisRound: sqrt(dx * dx + dy * dy)
      of tkIrisCross:
        const k = 0.3'f32
        min(max(dx / k, dy), max(dx, dy / k))
      of tkBarnDoors: dx
      of tkInset: max(u * asp, v)
      else: u # tkWipe, from the left
    let far = max(dist(0, 0), max(dist(1, 0), max(dist(0, 1), dist(1, 1))))
    let thr = p * far
    result.eachPixel(w, h):
      c = (if dist(u, v) < thr: b.get(x, y) else: a.get(x, y))

  of tkCenterSplit:
    # The outgoing picture's quarters slide out to its corners.
    let ox = p * fw / 2
    let oy = p * fh / 2
    result.eachPixel(w, h):
      let xx = x.float32 + 0.5'f32
      let yy = y.float32 + 0.5'f32
      let sx = (if xx < fw / 2: xx + ox else: xx - ox)
      let sy = (if yy < fh / 2: yy + oy else: yy - oy)
      let inside = (xx < fw / 2) == (sx < fw / 2) and (yy < fh / 2) == (sy < fh / 2)
      c = (if inside: a.sample(sx, sy) else: b.get(x, y))

  of tkSplitLegacy:
    # The outgoing picture's halves slide out to the sides.
    let off = p * fw / 2
    result.eachPixel(w, h):
      let xx = x.float32 + 0.5'f32
      let sx = (if xx < fw / 2: xx + off else: xx - off)
      let inside = (xx < fw / 2) == (sx < fw / 2)
      c = (if inside: a.sample(sx, y.float32 + 0.5'f32) else: b.get(x, y))

  of tkPushLegacy, tkWhipLegacy, tkSlideLegacy:
    # From the west: the incoming picture enters from the left, pushing the
    # outgoing one out, or sliding over it.
    let t = (if kind == tkWhipLegacy: easeInOut(p) else: p)
    let shift = t * fw
    let r = (if kind == tkWhipLegacy: bell(p) * fw / 24 else: 0'f32)
    let am = a.motion(r * 2, 0)
    let bm = b.motion(r * 2, 0)
    result.eachPixel(w, h):
      let xx = x.float32 + 0.5'f32
      let yy = y.float32 + 0.5'f32
      if xx < shift: c = bm.sample(xx - shift + fw, yy)
      elif kind == tkSlideLegacy: c = a.get(x, y)
      else: c = am.sample(xx - shift, yy)

  of tkCrossZoomLegacy:
    # Zooms into the outgoing picture, then out of the incoming one.
    let z = 1 + 3 * (1 - abs(2 * p - 1))
    let src = (if p < 0.5: a.unsafeAddr else: b.unsafeAddr)
    var zoomed: Img
    zoomed.eachPixel(w, h):
      c = src[].sample((x.float32 + 0.5'f32 - fw / 2) / z + fw / 2,
        (y.float32 + 0.5'f32 - fh / 2) / z + fh / 2)
    result = zoomed.blur((z - 1) * fw / 320)

  of tkBandSlide:
    # Bands of the incoming picture slide in from alternate sides.
    const n = 6
    let off = (1 - p) * fw
    result.eachPixel(w, h):
      let band = min(n - 1, int(v * n))
      let xx = x.float32 + 0.5'f32 + (if band mod 2 == 0: off else: -off)
      c = (if xx >= 0 and xx < fw: b.sample(xx, y.float32 + 0.5'f32)
           else: a.get(x, y))

  of tkCheckerWipe:
    # Each square of a checkerboard wipes across, every other one half a
    # step behind.
    const n = 8
    result.eachPixel(w, h):
      let cell = int(u * n) + int(v * n)
      let t = clamp01(p * 2 - (if cell mod 2 == 0: 0'f32 else: 0.5'f32))
      c = (if fract(u * n) < t: b.get(x, y) else: a.get(x, y))

  of tkVenetianBlinds:
    const n = 10
    result.eachPixel(w, h):
      c = (if fract(v * n) < p: b.get(x, y) else: a.get(x, y))

  of tkGradientWipe:
    # A soft-edged wipe along a diagonal gradient.
    const soft = 0.12'f32
    result.eachPixel(w, h):
      let g = clamp01(u * 0.7'f32 + v * 0.3'f32)
      c = mix(a.get(x, y), b.get(x, y), clamp01((p * (1 + soft) - g) / soft))

  of tkFlipOver:
    # The picture turns over about its middle, showing the incoming one on
    # its back.
    let angle = PI.float32 * p
    let first = angle < PI / 2
    let src = (if first: a.unsafeAddr else: b.unsafeAddr)
    let ang = (if first: angle else: angle - PI.float32)
    result.eachPixel(w, h):
      let (cc, cover) = src[].turned(x.float32 + 0.5'f32, y.float32 + 0.5'f32,
        ang, false)
      c = (if cover > 0: cc else: under.get(x, y))

  of tkCubeSpin:
    # A cube as wide and deep as the frame turns a quarter turn about its
    # vertical axis, carrying the outgoing picture on its front face away to
    # the left and bringing the incoming one in on its right face. The camera
    # has After Effects' default 50 mm view and sees the front face fill the
    # frame at rest; each pixel shows the nearest face its ray meets.
    let cam = fw / 2 / tan(19.8'f32 * PI.float32 / 180)
    let phi = p * PI.float32 / 2
    let (sn, cs) = (sin(phi), cos(phi))
    # (x, z) turned about the cube's center, which is half a frame deep.
    template turn(x, z: float32): (float32, float32) =
      (x * cs + z * sn, -x * sn + z * cs)
    # Each face: its center, the direction its picture runs across, and its
    # outward normal, all as turned.
    let (ax, az) = turn(0'f32, -fw / 2)
    let (aux, auz) = turn(1'f32, 0'f32)
    let (anx, anz) = turn(0'f32, -1'f32)
    let (bx, bz) = turn(fw / 2, 0'f32)
    let (bux, buz) = turn(0'f32, 1'f32)
    let (bnx, bnz) = turn(1'f32, 0'f32)
    result.eachPixel(w, h):
      # The ray from the camera through this pixel on the plane z = 0, with the
      # cube's center at z = fw / 2.
      let dx = x.float32 + 0.5'f32 - fw / 2
      let dy = y.float32 + 0.5'f32 - fh / 2
      let dz = cam
      var bestT = Inf.float32
      c = under.get(x, y)
      for face in 0 .. 1:
        let (px, pz, ux, uz, nx, nz) =
          if face == 0: (ax, az + fw / 2, aux, auz, anx, anz)
          else: (bx, bz + fw / 2, bux, buz, bnx, bnz)
        let facing = dx * nx + dz * nz
        if facing >= 0: continue # seen from behind
        # Where the ray, from (0, 0, -cam), meets the face's plane.
        let t = (px * nx + (pz + cam) * nz) / facing
        if t <= 0 or t >= bestT: continue
        let hx = dx * t - px
        let hz = dz * t - cam - pz
        let fu = hx * ux + hz * uz
        let fv = dy * t
        if abs(fu) > fw / 2 or abs(fv) > fh / 2: continue
        bestT = t
        let src = (if face == 0: a.unsafeAddr else: b.unsafeAddr)
        c = src[].sample(fu + fw / 2, fv + fh / 2)

  of tkConstantPower, tkExponentialFade:
    result = mixImg(a, b, p)
