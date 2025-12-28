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
  if a == "":
    return ['u', 'n', 'd', '\0']
  for i in 0 ..< min(4, a.len):
    result[i] = a[i]
