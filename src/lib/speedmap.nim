## Where in its media a clip with a speed ramp is at each point of its time.
##
## A ramp's `val` is its mean speed, so a ramped clip's length and offset are
## reckoned as at a constant speed; this map places frames and samples within
## that span the way the ramp moves through it.

import std/algorithm
from std/math import round

import ../action

type SpeedMap* = object
  mean*: float64     # the clip's speed as its length and offset reckon it
  ramp*: bool        # whether any of its speed actions is a ramp
  tau: seq[float64]  # time fraction reached at media fraction i / speedSteps
  scale: float64     # media fraction per time fraction, over the speed
  first, last: float64 # the speed at either end, past which it holds

func speedOf*(effects: Actions, u: float64, varispeed: set[bool] = {false, true}):
    float64 =
  ## The speed of `effects`' speed actions (those whose `varispeed` is in the
  ## set) `u` (0 to 1) of the way through the clip's media.
  result = 1.0
  for a in effects:
    if a.kind == actSpeed and a.varispeed in varispeed:
      result *= a.speedAt(u)

func initSpeedMap*(effects: Actions): SpeedMap =
  result.mean = 1.0
  for a in effects:
    if a.kind == actSpeed:
      result.mean *= a.val
      if a.sKf.len > 0: result.ramp = true
  if not result.ramp: return
  # Time spent on each slice of the media is its length over the speed there.
  result.tau = newSeq[float64](speedSteps + 1)
  for i in 0 ..< speedSteps:
    let u = (i.float64 + 0.5) / speedSteps
    result.tau[i + 1] = result.tau[i] + 1 / effects.speedOf(u)
  let total = result.tau[^1]
  for t in result.tau.mitems: t /= total
  result.scale = total / speedSteps
  result.first = effects.speedOf(0)
  result.last = effects.speedOf(1)

func mediaAt*(m: SpeedMap, t: float64): float64 =
  ## How far through the clip's media (as a fraction) it is `t` of the way
  ## through its time. Before and after the clip, the end speeds continue.
  if not m.ramp: return t
  if t <= 0: return t * m.first * m.scale
  if t >= 1: return 1 + (t - 1) * m.last * m.scale
  let i = max(1, m.tau.upperBound(t)) - 1
  let span = m.tau[i + 1] - m.tau[i]
  let f = (if span > 0: (t - m.tau[i]) / span else: 0.0)
  (i.float64 + f) / speedSteps

func mediaAt(points: seq[(float64, float64)], time: float64): float64 =
  ## A time map's media time at a clip time, straight between its points and
  ## at the last slope past them.
  if points.len == 1: return points[0][1] + time - points[0][0]
  var k = 1
  while k < points.len - 1 and points[k][0] < time: inc k
  let (t0, v0) = points[k - 1]
  let (t1, v1) = points[k]
  if t1 <= t0: v1 else: v0 + (v1 - v0) * (time - t0) / (t1 - t0)

func speedFromMap*(points: seq[(float64, float64)], inTime, len: float64):
    tuple[speed: Action, mediaIn: float64, ok: bool] =
  ## The speed a time map (clip times to media times, in one unit) plays a
  ## clip at, from `inTime` for `len`: constant, or a ramp when it changes
  ## within the clip; and the media time at the clip's in point. Not `ok`
  ## when the map stands still or runs backward there.
  result.speed = Action(kind: actSpeed, val: 1)
  result.ok = true
  if points.len == 0 or len <= 0:
    result.mediaIn = inTime
    return
  const n = 32
  var media = newSeq[float64](n + 1)
  for k in 0 .. n:
    media[k] = points.mediaAt(inTime + len * k.float64 / n)
  result.mediaIn = media[0]
  var slopes = newSeq[float64](n)
  for k in 0 ..< n:
    slopes[k] = (media[k + 1] - media[k]) / (len / n)
  var constant = true
  for s in slopes:
    if abs(s - slopes[0]) > 1e-4: constant = false
    if s <= 0: result.ok = false
  if not result.ok: return
  if constant:
    result.speed.val = float32(slopes[0])
    return
  let span = media[^1] - media[0]
  for k in 0 .. n:
    let slope = (if k == 0: slopes[0] elif k == n: slopes[^1]
                 else: (slopes[k - 1] + slopes[k]) / 2)
    result.speed.sKf.add float32(slope)
    result.speed.sKt.add KfTime(at: float32(round((media[k] - media[0]) / span * 100, 2)),
      unit: kuPercent)
  # Speeds between the samples are a guess, so scale them to cover exactly
  # the map's media in the clip's time.
  let scale = span / len / result.speed.meanSpeed
  for v in result.speed.sKf.mitems: v = float32(round(v * scale, 3))
  result.speed.val = float32(span / len)
