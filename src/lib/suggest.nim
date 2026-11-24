when not defined(emscripten) and not defined(nimscript):
  import std/[editdistance]

func didYouMean*(input: string, choices: openArray[string]): string =
  when defined(emscripten) or defined(nimscript):
    ""
  else:
    var best = ""
    var bestDist = high(int)
    for choice in choices:
      let dist = editDistanceAscii(input, choice)
      if dist < bestDist:
        best = choice
        bestDist = dist

    if best == "" or bestDist == 0:
      return ""

    let limit = max(3, input.len div 3)
    # Short choices are within `limit` of anything, so require some overlap.
    if bestDist <= limit and bestDist < best.len: "\nDid you mean " & best & "?"
    else: ""
