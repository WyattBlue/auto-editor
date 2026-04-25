#====================================================================
#
#             TinyRE - A Tiny Regex Engine for Nim
#              Copyright (c) Chen Kai-Hung, Ward
#
#====================================================================

##[
  TinyRE is a Nim wrap for a tiny regex engine based on Rob Pike's VM
  implementation. Compare to other small regex engines, this engine
  supports unicode and most of common regex syntax, in less than 10K
  code size (LOC < 1K), and guarantees that input regex will scale O(n)
  with the size of the string.

  **NOTICE: This implementation always return entire pattern as first
  capture. This is different from std/re.**

  Syntax
  ######

  .. code-block::
    ^          Match beginning of a buffer
    $          Match end of a buffer
    (...)      Grouping and substring capturing
    (?:...)    Non-capture grouping
    \s         Match whitespace [ \t\n\r\f\v]
    \S         Match non-whitespace [^ \t\n\r\f\v]
    \w         Match alphanumeric [a-zA-Z0-9_]
    \W         Match non-alphanumeric [^a-zA-Z0-9_]
    \d         Match decimal digit [0-9]
    \D         Match non-decimal digit [^0-9]
    \n         Match new line character
    \r         Match line feed character
    \f         Match form feed character
    \v         Match vertical tab character
    \t         Match horizontal tab character
    +          Match one or more times (greedy)
    +?         Match one or more times (non-greedy)
    *          Match zero or more times (greedy)
    *?         Match zero or more times (non-greedy)
    ?          Match zero or once (greedy)
    ??         Match zero or once (non-greedy)
    x|y        Match x or y (alternation operator)
    \meta      Match one of the meta character: ^$().[]{}*+?|\
    \x00       Match hex character code (exactly 2 digits)
    \u0000     Match hex character code (exactly 4 digits)
    \U00000000 Match hex character code (exactly 8 digits)
    \<, \>     Match start-of-word and end-of-word
    \b         Matches a word boundary
    \B         Matches a nonword boundary
    [...]      Match any character from set. Ranges like [a-z] or [\x00-\u0000] are supported
    [^...]     Match any character but ones from set
    {n}        Matches exactly n times
    {n,}       Matches the preceding character at least n times (greedy)
    {n,m}      Matches the preceding character at least n and at most m times (greedy)
    {n,}?      Matches the preceding character at least n times (non-greedy)
    {n,m}?     Matches the preceding character at least n and at most m times (non-greedy)

]##

when defined(js):
  {.error: "This library needs to be compiled with a c-like backend".}

{.compile: "re.c".}

type
  ReRaw = ptr object
  Re* = object
    raw: ReRaw
    global: bool

  ReFlag* = enum
    reIgnoreCase # Perform case-insensitive matching
    reGlobal     # Perform global matching
    reUtf8       # Perform utf8 matching

  ReGlobalKind = enum
    rgNone
    rgIncludeLastEmpty
    rgExcludeLastEmpty

proc re_compile(pattern: cstring, i: cint, u: cint): ReRaw {.importc, cdecl.}
proc re_free(re: ReRaw) {.importc, cdecl.}
proc re_dup(re: ReRaw): ReRaw {.importc, cdecl.}
proc re_match(re: ReRaw, text: cstring, L: cint, cont: cstring): cstringArray {.importc, cdecl.}
proc re_max_matches(re: ReRaw): cint {.importc, cdecl.}
proc re_uc_len(re: ReRaw, s: cstring): cint {.importc, cdecl.}

proc `=destroy`(re: Re) =
  if not re.raw.isNil:
    re_free(re.raw)

proc `=copy`(dest: var Re, source: Re) =
  if dest.raw == source.raw: return
  `=destroy`(dest)
  wasMoved(dest)
  dest.raw = re_dup(source.raw)
  if dest.raw.isNil: raise newException(OutOfMemDefect, "out of memory")

iterator matchRaw(s: cstring, L0: int, re: ReRaw, global: ReGlobalKind, sub: bool
  ): Slice[int] {.closure.} =

  template `===`(a, b: cstring): bool =
    # must cast to ptr to compare cstring
    cast[pointer](a) == cast[pointer](b)

  assert not re.isNil
  var
    L = L0
    p = s
    lastMatch1: cstring
    cont: cstring = nil

  while true:
    var matches = re_match(re, p, cint L, cont)
    if matches.isNil: break

    var i = 0
    while i < re_max_matches(re):
      var slice = cast[int](matches[i]) .. cast[int](matches[i + 1])
      if slice.a == 0 or slice.b == 0: # (?, ?)
        slice = -1 .. -1
      else:
        slice.a = slice.a -% cast[int](s)
        slice.b = slice.b -% cast[int](s) -% 1

      if i == 0 and lastMatch1 === matches[1] and p === lastMatch1:
        # match same anchor again, avoid to yield the same slice twice.
        # for example, match(" a", re"\<")
        # first time match "| |a", second time match " ||a"
        # but yield the same slice because the pattern has no length.
        discard
      else:
        yield slice

      if not sub:
        break
      i.inc(2)

    if p === matches[1]:
      # zero length captures, advance one character instead of break
      cont = p
      let uclen = int re_uc_len(re, p)
      L -= uclen
      p = cast[cstring](cast[int](p) +% uclen)
    else:
      L -= cast[int](matches[1]) -% cast[int](p)
      p = matches[1]
      cont = cast[cstring](cast[int](p) -% 1)

    lastMatch1 = matches[1]
    case global
    of rgNone:
      break
    of rgIncludeLastEmpty:
      if cast[int](p) >% cast[int](s) +% L0:
        break
    of rgExcludeLastEmpty:
      if cast[int](p) >=% cast[int](s) +% L0:
        break

proc re*(s: string, flags: set[ReFlag] = {}): Re =
  # Constructor of regular expressions.
  result = Re(
    raw: re_compile(s, cint(reIgnoreCase in flags), cint(reUtf8 in flags)),
    global: reGlobal in flags
  )
  if result.raw.isNil:
    raise newException(ValueError, "cannot compile pattern")

proc groupsCount*(re: Re): int =
  # Returns the number of capturing groups.
  assert not re.raw.isNil
  return re_max_matches(re.raw) div 2

iterator match*(s: string, pattern: Re, start = 0): string =
  # Yields all matching substrings of `s[start..]` that match `pattern`.
  let start0 = start # avoid to be modified during iteration
  let cs = cast[cstring](cast[int](s.cstring) +% start0)
  let rg = if pattern.global: rgIncludeLastEmpty else: rgNone
  for i in matchRaw(cs, s.len - start0, pattern.raw, rg, true):
    var slice = (i.a +% start0) .. (i.b +% start0)
    yield if slice.b >= slice.a and slice.a >= 0: s[slice] else: ""

proc match*(s: string, pattern: Re, start = 0): seq[string] =
  # Returns all matching substrings of `s[start..]` that match `pattern`.
  for m in match(s, pattern, start):
    result.add m

proc replace*(s: string, sub: Re, by: string = "", limit = 0): string =
  # Replaces `sub` in `s` by the string `by`. Captures cannot be accessed in `by`.
  let cs = s.cstring
  var
    pos = 0
    count = 0

  for slice in matchRaw(cs, s.len, sub.raw, rgExcludeLastEmpty, false):
    if slice.b >= slice.a and slice.a >= 0: # not empty match
      result.add s[pos..slice.a - 1]
      result.add by
      pos = slice.b + 1
      count.inc
      if limit > 0 and count >= limit:
        break

  result.add s[pos..^1]

proc escapeRe*(s: string): string {.raises: [].} =
  # Escapes `s` so that it can be matched verbatim.
  for c in s:
    case c
    of '\n': result.add "\\n"
    of '\r': result.add "\\r"
    of '\t': result.add "\\t"
    of '\b': result.add "\\b"
    of '\f': result.add "\\f"
    of '\v': result.add "\\v"
    of '^', '$', '(', ')', '.', '[', ']', '{', '}', '*', '+', '?', '|', '\\':
      result.add '\\'
      result.add c
    else:
      result.add c
