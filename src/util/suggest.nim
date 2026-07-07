when not defined(emscripten) and not defined(nimscript):
  import std/[editdistance]

func didYouMean*(input: string, choices: openArray[string]): string =
  when defined(emscripten) or defined(nimscript):
    ""
  else:
    var
      best = ""
      bestDist = high(int)

    for choice in choices:
      let dist = editDistance(input, choice)
      if dist < bestDist:
        best = choice
        bestDist = dist

    if best == "" or bestDist == 0:
      return ""

    let limit = max(3, input.len div 3)
    if bestDist <= limit:
      "\nDid you mean " & best & "?"
    else:
      ""
