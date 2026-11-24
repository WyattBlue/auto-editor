import std/strformat

func srtTime*(ms: int64): string =
  ## An SRT cue time, `HH:MM:SS,mmm`, for a nonnegative `ms`.
  &"{ms div 3600000:02}:{(ms div 60000) mod 60:02}:{(ms div 1000) mod 60:02},{ms mod 1000:03}"
