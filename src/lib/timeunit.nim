## The units a written time may carry, shared by command-line times and
## action durations so the two accept the same spellings.

type TimeUnit* = enum
  tuFrames, tuSeconds, tuMinutes, tuHours

func parseTimeUnit*(suffix: string, unit: var TimeUnit): bool {.raises: [].} =
  ## The unit `suffix` names; a bare number ("") counts frames.
  case suffix
  of "", "f", "frame", "frames": unit = tuFrames
  of "s", "sec", "secs", "second", "seconds": unit = tuSeconds
  of "min", "mins", "minute", "minutes": unit = tuMinutes
  of "hour", "hours": unit = tuHours
  else: return false
  true

func seconds*(unit: TimeUnit): float64 {.raises: [].} =
  ## How many seconds one of `unit` is. Frames have no fixed length.
  case unit
  of tuFrames: 0.0
  of tuSeconds: 1.0
  of tuMinutes: 60.0
  of tuHours: 3600.0

func splitTimeUnit*(s: string): tuple[num, suffix: string] {.raises: [].} =
  ## "30frames" -> ("30", "frames"): the trailing letters are the unit.
  var i = s.len
  while i > 0 and s[i - 1] in {'a'..'z', 'A'..'Z'}:
    dec i
  (s[0 ..< i], s[i .. ^1])
