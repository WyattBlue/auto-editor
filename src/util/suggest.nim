when not defined(emscripten) and not defined(nimscript):
  import std/[editdistance, strutils]

func didYouMean*(input: string, choices: openArray[string]): string =
  when defined(emscripten) or defined(nimscript):
    discard input
    discard choices
    ""
  else:
    var
      best = ""
      bestDist = high(int)
    let needle = input.toLowerAscii()

    for choice in choices:
      let dist = editDistance(needle, choice.toLowerAscii())
      if dist < bestDist:
        best = choice
        bestDist = dist

    if best == "" or bestDist == 0:
      return ""

    let limit = max(2, needle.len div 3)
    if bestDist <= limit:
      "\nDid you mean " & best & "?"
    else:
      ""
