import std/json

type Lang* = array[4, char]

func `$`*(lang: Lang): string =
  for i in 0 ..< 4:
    if lang[i] == '\0':
      break
    result.add lang[i]

func `%`*(lang: Lang): JsonNode =
  %($lang)

func toLang*(a: string): Lang =
  ## The ISO 639 code that `a` starts with, before any region subtag as in
  ## "en-US", or "und" when it isn't two or three ASCII letters.
  var n = 0
  while n < a.len and a[n] notin {'-', '_'}: inc n
  if n notin 2..3: return ['u', 'n', 'd', '\0']
  for i in 0 ..< n:
    if a[i] notin {'a'..'z', 'A'..'Z'}: return ['u', 'n', 'd', '\0']
    result[i] = a[i]
