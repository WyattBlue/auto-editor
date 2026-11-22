## The pattern the `word` edit method matches subtitles with. Kept apart from
## the CLI so other programs can match exactly as auto-editor does.

import ../vendor/tinyre/tinyre

func lastCharStart(s: string): int =
  ## The byte where the last UTF-8 character of `s` starts.
  result = s.high
  while result > 0 and (s[result].uint8 and 0xC0) == 0x80:
    dec result

proc wordRe*(word: string, ignoreCase: bool): Re =
  ## Matches `word` (a word or phrase, taken literally) as a whole word: a
  ## side of it that begins or ends with a word character, as `\b` counts
  ## them, can't run into another word character. So `really?` matches
  ## "really?" but not "unreally?", and `(sic)` needs no boundary at all.
  var pattern = escapeRe(word)
  if word.isWordChar(0):
    pattern = "\\b" & pattern
  if word.len > 0 and word.isWordChar(word.lastCharStart):
    pattern.add "\\b"
  re(pattern, (if ignoreCase: {reUtf8, reIgnoreCase} else: {reUtf8}))
