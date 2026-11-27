func windowPeak(samples: openArray[float32], start, win: int): float32 =
  for i in start ..< min(start + win, samples.len):
    result = max(result, abs(samples[i]))

func loudSamples*(samples: openArray[float32], win: int,
    threshold: float32): int =
  ## How many samples lie in `win`-sized windows that peak at `threshold` or
  ## above.
  var start = 0
  while start < samples.len:
    if windowPeak(samples, start, win) >= threshold:
      result += min(win, samples.len - start)
    start += win

func quietestCut*(samples: openArray[float32], win: int,
    threshold: float32): int =
  ## The index to split `samples` at so the cut does the least harm to speech:
  ## the middle of the longest pause, or of the quietest stretch when nothing
  ## falls below `threshold`. The latest candidate wins a tie.
  let n = samples.len div win
  if n == 0:
    return samples.len

  var peaks = newSeq[float32](n)
  for i in 0 ..< n:
    peaks[i] = windowPeak(samples, i * win, win)

  var pauseStart = 0
  var pauseLen = 0
  var run = 0
  for i in 0 ..< n:
    run = (if peaks[i] < threshold: run + 1 else: 0)
    if run > 0 and run >= pauseLen:
      pauseLen = run
      pauseStart = i - run + 1
  if pauseLen > 0:
    # Mid-pause leaves each side some silence around its speech.
    return pauseStart * win + pauseLen * win div 2

  # Rank a window by its neighbors too, so a lone dip between two loud
  # windows (a zero crossing, not a lull) loses to a wider one.
  var best = 0
  var bestScore = float32.high
  for i in 0 ..< n:
    let score = max(peaks[i], max(peaks[max(i - 1, 0)], peaks[min(i + 1, n - 1)]))
    if score <= bestScore:
      bestScore = score
      best = i
  best * win + win div 2
