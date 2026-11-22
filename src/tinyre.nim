#====================================================================
#
#             TinyRE - A Tiny Regex Engine for Nim
#              Copyright (c) Chen Kai-Hung, Ward
#
#====================================================================
#
# Copyright (c) Chen Kai-Hung, Ward
#
# Permission is hereby granted, free of charge, to any person obtaining a copy
# of this software and associated documentation files (the "Software"), to
# deal in the Software without restriction, including without limitation the
# rights to use, copy, modify, merge, publish, distribute, sublicense, and/or
# sell copies of the Software, and to permit persons to whom the Software is
# furnished to do so, subject to the following conditions:
#
# The above copyright notice and this permission notice shall be included in
# all copies or substantial portions of the Software.
#
# THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
# IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
# FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
# AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
# LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING
# FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS
# IN THE SOFTWARE.

##[
  TinyRE is a tiny regex engine based on Rob Pike's VM, ported to Nim from
  its C implementation. Compared to other small regex engines, it
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

# Copyright 2007-2009 Russ Cox. Copyright 2020-2021 Kyryl Melekhin. The VM's
# design and much of its compiler come from their BSD-licensed pikevm.

type
  Prog = object
    code: seq[int]  # instructions; each split's operand is its relative jump
    nsubs: int      # capturing groups
    splitIds: int   # one past the largest split id, for the seen-set
    slots: int      # capture slots: a start and an end for the match and each group

  Re* = object
    prog: Prog
    insensitive, utf8, global: bool

  ReFlag* = enum
    reIgnoreCase # Perform case-insensitive matching
    reGlobal     # Perform global matching
    reUtf8       # Perform utf8 matching

  ReErrorKind* = enum
    ## Why a pattern didn't compile.
    reeNone             ## (not an error)
    reeTrailingBackslash ## the pattern ends in a lone `\`
    reeBadEscape        ## `\x`, `\u` or `\U` without enough hex digits
    reeUnclosedSet      ## a `[` with no `]`
    reeBadRange         ## a class like `\d` as one end of a range in a set
    reeUnsupportedGroup ## `(?` not followed by `:`
    reeUnclosedGroup    ## a `(` with no `)`
    reeUnmatchedParen   ## a `)` with no `(`
    reeBadRepeat        ## a `{` that isn't `{n}`, `{n,}` or `{n,m}`
    reeRepeatTooLarge   ## a repeat count over 65535
    reeNothingToRepeat  ## `?`, `*` or `+` with nothing before it
    reeTooNested        ## too many nested groups or alternatives
    reeTooLarge         ## the compiled pattern is too large
    reeNoMemory         ## out of memory

  ReError* = object of ValueError
    ## A pattern that didn't compile: why, and where, as a byte offset into
    ## the pattern.
    kind*: ReErrorKind
    pos*: int

  ReGlobalKind = enum
    rgNone
    rgIncludeLastEmpty
    rgExcludeLastEmpty

const
  # Instructions that consume a character come first: `op < opWbeg`.
  opChar = 1
  opClass = 2
  opMatch = 3
  opAny = 4
  opWbeg = 5
  opWend = 6
  opWb = 7
  opNotb = 8
  opBol = 9
  opEol = 10
  opSave = 11
  opJmp = 12
  opSplit = 13 # compiled to an odd id >= opSplit; prefers the next instruction
  opRsplit = 14 # compiled to minus such an id; prefers its jump

  # Caps the code size so counting it can't overflow.
  maxCode = 1 shl 20
  # The C matcher kept its thread lists on the stack, and refused patterns
  # needing more than this; kept so the same patterns compile.
  maxMatchStack = 256 * 1024
  altMax = 4096

# Text and patterns read like C strings: past the end is a NUL.
template at(s: string, i: int): int =
  (if i < s.len: int(s[i].uint8) else: 0)

const utf8Length: array[256, int8] = block:
  var t: array[256, int8]
  for i in 0 .. 255:
    t[i] = (if i < 0xC0: 1 elif i < 0xE0: 2 elif i < 0xF0: 3 elif i < 0xF8: 4 else: 1)
  t

func ucLen(s: string, i: int, utf8: bool): int =
  ## The length of the character at `i`. A lead byte missing any of its
  ## continuation bytes counts as one byte.
  if not utf8: return 1
  let n = utf8Length[s.at(i)].int
  for k in 1 ..< n:
    if (s.at(i + k) and 0xC0) != 0x80: return 1
  n

func ucCode(s: string, i: int, utf8: bool): int =
  ## The code point of the character at `i`.
  result = s.at(i)
  if ucLen(s, i, utf8) > 1:
    let d = result
    if d < 192: discard
    elif d < 224: result = ((d and 0x1f) shl 6) or (s.at(i+1) and 0x3f)
    elif d < 240:
      result = ((d and 0x0f) shl 12) or ((s.at(i+1) and 0x3f) shl 6) or
        (s.at(i+2) and 0x3f)
    elif d < 248:
      result = ((d and 0x07) shl 18) or ((s.at(i+1) and 0x3f) shl 12) or
        ((s.at(i+2) and 0x3f) shl 6) or (s.at(i+3) and 0x3f)
    else: result = 0

func isUniPunct(u: int): bool =
  ## Whether code point `u` is a space or punctuation from the blocks
  ## subtitles use: Latin-1's (but not its ª, µ, º), General and Supplemental
  ## Punctuation, CJK punctuation, and the fullwidth ASCII punctuation.
  if u in 0xA0 .. 0xBF: return u notin [0xAA, 0xB5, 0xBA]
  if u in [0xD7, 0xF7]: return true
  if u in 0x2000 .. 0x206F or u in 0x2E00 .. 0x2E7F: return true
  if u in 0x3000 .. 0x303F: return u notin 0x3005 .. 0x3007
  u in 0xFF01 .. 0xFF0F or u in 0xFF1A .. 0xFF20 or u in 0xFF3B .. 0xFF40 or
    u in 0xFF5B .. 0xFF65

func isAsciiWord(c: int): bool =
  c in ord('a') .. ord('z') or c in ord('A') .. ord('Z') or c in ord('0') .. ord('9') or
    c == ord('_')

func isAsciiDigit(c: int): bool = c in ord('0') .. ord('9')
func isAsciiSpace(c: int): bool = c == ord(' ') or c in 9 .. 13

func isWordAt(s: string, i: int): bool =
  ## What `\b` counts as a word character: ASCII letters, digits and `_`, and
  ## any other character but Unicode spaces and punctuation. A byte inside a
  ## UTF-8 character counts as one, so there's never a boundary within it.
  let c = s.at(i)
  if c < 128: return isAsciiWord(c)
  if c < 0xC0: return true
  not isUniPunct(ucCode(s, i, true))

func isWordChar*(s: string, i: int): bool =
  ## Whether the character starting at byte `i` of `s` is one `\b` counts as
  ## part of a word: ASCII letters, digits and `_`, and any other character
  ## but Unicode spaces and punctuation.
  i in 0 ..< s.len and isWordAt(s, i)

# Unicode simple case folding (one character to one) for the scripts
# subtitles mostly use. In each range of alternating case, the capital is on
# the even (or odd) code point and its small letter is the next one.
const alternating = [
  (0x0100, 0x012F, 0), (0x0132, 0x0137, 0), (0x0139, 0x0148, 1),
  (0x014A, 0x0177, 0), (0x0179, 0x017E, 1), (0x01A0, 0x01A5, 0),
  (0x01CD, 0x01DC, 1), (0x01DE, 0x01EF, 0), (0x01F8, 0x021F, 0),
  (0x0222, 0x0233, 0), (0x03D8, 0x03EF, 0), (0x0460, 0x0481, 0),
  (0x048A, 0x04BF, 0), (0x04C1, 0x04CE, 1), (0x04D0, 0x052F, 0),
  (0x1E00, 0x1E95, 0), (0x1EA0, 0x1EFF, 0)]

func fold(c: int, utf8: bool): int =
  ## The case-folded form of character `c`: its small letter, for the
  ## scripts above. Without `utf8`, `c` is a byte and only ASCII folds,
  ## since a byte past 127 is part of a UTF-8 character, not Latin-1.
  if c < 128 or not utf8:
    return (if c in ord('A') .. ord('Z'): c + 32 else: c)
  if c <= 0xDE: return (if c >= 0xC0 and c != 0xD7: c + 32 else: c)
  if c < 0x100: return c
  for (lo, hi, capitalParity) in alternating:
    if c >= lo and c <= hi:
      return (if (c and 1) == capitalParity: c + 1 else: c)
  case c
  of 0x0178: 0x00FF          # Ÿ
  of 0x017F: ord('s')        # long s
  of 0x0386: 0x03AC          # Ά
  of 0x0388 .. 0x038A: c + 37
  of 0x038C: 0x03CC
  of 0x038E, 0x038F: c + 63
  of 0x0391 .. 0x03A1, 0x03A3 .. 0x03AB: c + 32 # Greek capitals
  of 0x03C2: 0x03C3          # final sigma
  of 0x0400 .. 0x040F: c + 80
  of 0x0410 .. 0x042F: c + 32 # Cyrillic capitals
  of 0x04C0: 0x04CF
  of 0x0531 .. 0x0556: c + 48 # Armenian capitals
  of 0x1E9E: 0x00DF          # capital sharp s
  of 0xFF21 .. 0xFF3A: c + 32 # fullwidth Latin capitals
  else: c

func classMatch(code: openArray[int], pc0: int, c: int): bool =
  ## Whether `c` is in the class whose "positive" flag is at `pc0`. Ignoring
  ## case, `c` and the class's ranges are already folded.
  var pc = pc0
  let positive = code[pc] != 0
  let cnt = code[pc + 1]
  pc += 2
  for _ in 0 ..< cnt:
    if code[pc] == -1:
      let hit =
        case chr(code[pc + 1])
        of 'd': isAsciiDigit(c)
        of 'D': not isAsciiDigit(c)
        of 's': isAsciiSpace(c)
        of 'S': not isAsciiSpace(c)
        of 'w': isAsciiWord(c)
        of 'W': not isAsciiWord(c)
        else: false
      if hit: return positive
    elif c >= code[pc] and c <= code[pc + 1]: return positive
    pc += 2
  not positive

func hexDigit(c: int): int =
  if c in ord('0') .. ord('9'): c - ord('0')
  elif c in ord('a') .. ord('f'): c - ord('a') + 10
  elif c in ord('A') .. ord('F'): c - ord('A') + 10
  else: -1

func hexCode(re: string, i, n: int): int =
  ## The value of the `n` hex digits after `i`, or -1.
  for k in 1 .. n:
    let d = hexDigit(re.at(i + k))
    if d < 0: return -1
    result = (result shl 4) or d
  # C's int overflowed past this, and the negative value read as an error.
  if result > 0x7FFFFFFF: return -1

func token(re: string, i0: int, forward: var int, utf8: bool): int =
  ## A character of a set: its code, minus a class letter for `\d` and the
  ## like, or -1 at the end or on a bad escape.
  var i = i0
  if re.at(i) == 0: return -1
  if re.at(i) == ord('\\'):
    inc i
    if re.at(i) == 0: return -1
    forward = 2
    case chr(re.at(i))
    of 'd', 'D', 'w', 'W', 's', 'S': return -re.at(i)
    of 'n': return ord('\n')
    of 'r': return ord('\r')
    of 't': return ord('\t')
    of 'f': return ord('\f')
    of 'v': return ord('\v')
    of 'x', 'u', 'U':
      forward = (if re.at(i) == ord('x'): 2 elif re.at(i) == ord('u'): 4 else: 8)
      let ch = hexCode(re, i, forward)
      if ch < 0: return -1
      forward += 2
      return ch
    else: discard # an escaped character stands for itself
  forward = i - i0 + ucLen(re, i, utf8)
  ucCode(re, i, utf8)

type CompileError = object
  kind: ReErrorKind
  pos: int

func tooMuchMemory(ninstr: int): bool =
  ## Whether a program of `ninstr` instructions is sure to need more memory
  ## to match than maxMatchStack, as `compile` sizes it at the end: each
  ## instruction costs at least this much whatever its kind or the groups.
  # From compile's sum, with presub at least rsubSize + 2 pointers and every
  # instruction a split at most; `len` counts two more for the match.
  let len = ninstr + 2
  let least = (if sizeof(pointer) == 8: 56 * len + 148 else: 32 * len + 100)
  least > maxMatchStack

func instructions(code: openArray[int], a, b: int): int =
  ## The instructions in `code[a ..< b]` that the matcher sizes its memory by:
  ## every one but the assertions.
  var i = a
  while i < b:
    case code[i]
    of opClass:
      inc result
      i += 3 + 2 * code[i + 2]
    of opChar, opSave, opJmp, opSplit, opRsplit:
      inc result
      i += 2
    of opAny:
      inc result
      inc i
    else: inc i

func compileCode(re: string, prog: var Prog, utf8: bool, err: var CompileError): bool =
  ## Compile `re` into `prog.code`, false with `err` set on failure.
  template code: untyped = prog.code
  template pc: int = code.len
  template emit(v: int) = code.add v
  template fail(k: ReErrorKind, where: int) =
    err = CompileError(kind: k, pos: where)
    return false
  # Every insertion makes room for one jump or split.
  template insertCode(where, num: int) =
    for _ in 0 ..< num: code.insert(0, where)
    inc ninstr
  template emitOp(v: int) =
    code.add v
    inc ninstr
  template rel(a, b: int): int = b - a - 2
  # The C sizing pass, which made the size errors, counted from 3.
  template tooLarge: bool = pc + 3 > maxCode or tooMuchMemory(ninstr)

  var i = 0
  var ninstr = 0
  var start = pc
  var term = pc
  var altLabel = 0
  var altStack: seq[int]
  var capStack: seq[int]   # five entries a group
  var openStack: seq[int]  # where each open group starts, for errors
  # The C sizing pass never lowered its count of alternatives at `)`, so its
  # limit applied to the whole pattern.
  var allAlts = 0

  while re.at(i) != 0:
    case chr(re.at(i))
    of '\\':
      inc i
      if re.at(i) == 0: fail(reeTrailingBackslash, i - 1)
      let e = chr(re.at(i))
      case e
      of '<', '>', 'B', 'b':
        emit(if e == '<': opWbeg elif e == '>': opWend elif e == 'B': opNotb else: opWb)
        term = pc
      of 'd', 'D', 's', 'S', 'w', 'W':
        term = pc
        emitOp opClass; emit 1; emit 1; emit -1; emit ord(e)
      of 'n', 'r', 't', 'f', 'v':
        term = pc
        emitOp opChar
        emit(if e == 'n': ord('\n') elif e == 'r': ord('\r') elif e == 't': ord('\t')
             elif e == 'f': ord('\f') else: ord('\v'))
      of 'x', 'u', 'U':
        let n = (if e == 'x': 2 elif e == 'u': 4 else: 8)
        term = pc
        let ch = hexCode(re, i, n)
        if ch < 0: fail(reeBadEscape, i - 1)
        i += n
        emitOp opChar; emit ch
      else:
        term = pc
        emitOp opChar; emit ucCode(re, i, utf8)
    of '.':
      term = pc
      emitOp opAny
    of '[':
      let setStart = i
      term = pc
      inc i
      emitOp opClass
      let neg = re.at(i) == ord('^')
      emit(if neg: 0 else: 1)
      if neg: inc i
      emit 0 # the number of pairs, filled in below
      var cnt = 0
      while re.at(i) != ord(']'):
        var forward = 0
        var tok = token(re, i, forward, utf8)
        if tok == -1:
          if re.at(i) == 0 or (re.at(i) == ord('\\') and re.at(i+1) == 0):
            fail(reeUnclosedSet, setStart)
          fail(reeBadEscape, i)
        i += forward
        if tok < 0: # \d\D\s\S\w\W
          emit -1; emit -tok
          inc cnt
          continue
        emit tok
        if re.at(i) == ord('-') and re.at(i+1) != ord(']'):
          inc i
          tok = token(re, i, forward, utf8)
          if tok < 0: # a class can't end a range
            if re.at(i) == 0 or (re.at(i) == ord('\\') and re.at(i+1) == 0):
              fail(reeUnclosedSet, setStart)
            fail(if tok == -1: reeBadEscape else: reeBadRange, i)
          i += forward
        emit tok
        inc cnt
      code[term + 2] = cnt
    of '(':
      term = pc
      var capture = true
      let groupStart = i
      if re.at(i+1) == ord('?'):
        i += 2
        if re.at(i) == ord(':'): capture = false
        else: fail(reeUnsupportedGroup, groupStart)
      if capture:
        inc prog.nsubs
        emitOp opSave; emit prog.nsubs
      if capStack.len + 5 > altMax * 5: fail(reeTooNested, groupStart)
      openStack.add groupStart
      capStack.add [(if capture: prog.nsubs else: 0), term, altLabel, start, altStack.len]
      altLabel = 0
      start = pc
    of ')':
      if capStack.len < 5: fail(reeUnmatchedParen, i)
      let groupAlts = capStack.pop
      if altLabel != 0:
        code[altLabel] = rel(altLabel, pc) + 1
        let alts = altStack.len
        var altc = alts
        while altc > groupAlts:
          let where = altStack[groupAlts + alts - altc] + (altc - groupAlts) * 2
          code[where] = rel(where, pc) + 1
          dec altc
        altStack.setLen(groupAlts)
      start = capStack.pop
      altLabel = capStack.pop
      term = capStack.pop
      discard openStack.pop
      let group = capStack.pop
      if group != 0:
        # The end's slot follows every start's, so it waits on the group count.
        emitOp opSave; emit -group
    of '{':
      var maxcnt = 0
      var mincnt = 0
      let size = pc - term
      var split = opSplit
      var rsplit = opRsplit
      let brace = i
      inc i
      if not isAsciiDigit(re.at(i)): fail(reeBadRepeat, brace)
      while isAsciiDigit(re.at(i)):
        mincnt = mincnt * 10 + re.at(i) - ord('0')
        inc i
        if mincnt > 65535: fail(reeRepeatTooLarge, brace)
      if re.at(i) == ord('}'):
        maxcnt = mincnt
      elif re.at(i) == ord(','):
        inc i
        if re.at(i) == ord('}'):
          maxcnt = -1
        elif isAsciiDigit(re.at(i)):
          while isAsciiDigit(re.at(i)):
            maxcnt = maxcnt * 10 + re.at(i) - ord('0')
            inc i
            if maxcnt > 65535: fail(reeRepeatTooLarge, brace)
          if re.at(i) != ord('}'): fail(reeBadRepeat, brace)
        else:
          fail(reeBadRepeat, brace)
      else:
        fail(reeBadRepeat, brace)
      if re.at(i+1) == ord('?'): # non-greedy
        swap(split, rsplit)
        inc i
      for _ in 0 ..< mincnt - 1:
        if tooLarge: fail(reeTooLarge, i)
        for k in 0 ..< size: emit code[term + k]
        ninstr += instructions(code, term, term + size)
      if maxcnt < 0:
        emitOp rsplit
        emit rel(pc - 1, pc - 1 - size)
      elif maxcnt > 0:
        let diff = (if mincnt == 0: 1 else: 0)
        var k = maxcnt - mincnt - diff
        while k > 0:
          if tooLarge: fail(reeTooLarge, i)
          emitOp split
          emit rel(pc, pc + (size + 2) * k)
          for m in 0 ..< size: emit code[term + m]
          ninstr += instructions(code, term, term + size)
          dec k
      if mincnt == 0:
        insertCode(term, 2)
        code[term] = (if maxcnt == 0: opJmp else: split)
        code[term + 1] = rel(term, pc)
        term = pc
    of '?':
      if pc == term: fail(reeNothingToRepeat, i)
      insertCode(term, 2)
      code[term] = (if re.at(i+1) == ord('?'): opRsplit else: opSplit)
      if re.at(i+1) == ord('?'): inc i
      code[term + 1] = rel(term, pc)
      term = pc
    of '*':
      if pc == term: fail(reeNothingToRepeat, i)
      insertCode(term, 2)
      emitOp opJmp
      emit rel(pc - 1, term)
      code[term] = (if re.at(i+1) == ord('?'): opRsplit else: opSplit)
      if re.at(i+1) == ord('?'): inc i
      code[term + 1] = rel(term, pc)
      term = pc
    of '+':
      if pc == term: fail(reeNothingToRepeat, i)
      emitOp(if re.at(i+1) == ord('?'): opSplit else: opRsplit)
      if re.at(i+1) == ord('?'): inc i
      emit rel(pc - 1, term)
      term = pc
    of '|':
      if altLabel != 0:
        if allAlts >= altMax: fail(reeTooNested, i)
        inc allAlts
        altStack.add altLabel
      insertCode(start, 2)
      emitOp opJmp
      altLabel = pc
      emit 0
      code[start] = opSplit
      code[start + 1] = rel(start, pc)
      term = pc
    of '^', '$':
      emit(if re.at(i) == ord('^'): opBol else: opEol)
      term = pc
    else:
      term = pc
      emitOp opChar; emit ucCode(re, i, utf8)
    if tooLarge: fail(reeTooLarge, i)
    i += ucLen(re, i, utf8)

  if altLabel != 0:
    code[altLabel] = rel(altLabel, pc) + 1
    let alts = altStack.len
    var altc = alts
    while altc > 0:
      let where = altStack[alts - altc] + altc * 2
      code[where] = rel(where, pc) + 1
      dec altc
  if capStack.len > 0: fail(reeUnclosedGroup, openStack[^1])
  true

func compile(pattern: string, utf8: bool, err: var CompileError): Prog =
  ## Compile `pattern`; `err.kind` is reeNone on success.
  # A C string ends at its first NUL, and so did patterns.
  let nul = pattern.find('\0')
  let re = (if nul >= 0: pattern[0 ..< nul] else: pattern)
  if not compileCode(re, result, utf8, err):
    return
  # Number the splits for the matcher's seen-set, counting instructions as
  # the C matcher sized its thread lists.
  var icnt = 0
  var scnt = opSplit
  var i = 0
  template code: untyped = result.code
  while i < code.len:
    case code[i]
    of opClass:
      i += code[i + 2] * 2 + 2
      inc icnt
    of opSplit:
      code[i] = scnt
      inc i
      scnt += 2
      inc icnt
    of opRsplit:
      code[i] = -scnt
      scnt += 2
      inc i
      inc icnt
    of opJmp, opSave, opChar:
      if code[i] == opSave and code[i + 1] < 0:
        code[i + 1] = -code[i + 1] + result.nsubs + 1
      inc i
      inc icnt
    of opAny:
      inc icnt
    else: discard
    inc i
  code.add [opSave, result.nsubs + 1, opMatch]
  let splits = (scnt - opSplit) div 2
  let len = icnt + 2
  let ptrSize = sizeof(pointer)
  let rsubSize = (if ptrSize == 8: 16 else: 8)
  let presub = rsubSize + ptrSize * (result.nsubs + 1) * 2
  let subsz = presub * (len - splits + 3)
  let stack = subsz + splits * 2 * ptrSize + scnt * 4 + 2 * len * 2 * ptrSize
  if stack > maxMatchStack:
    err = CompileError(kind: reeTooLarge, pos: 0)
    return
  result.splitIds = scnt
  result.slots = (result.nsubs + 1) * 2

type
  Thread = object
    pc: int
    sub: int # index of its captures in the pool

  Scratch = object
    ## The matcher's working memory, kept between matches of one search.
    pool: seq[int]      # captures, `slots` ints a set
    refs: seq[int]      # threads sharing each set
    freeSubs: seq[int]
    seen: seq[int]      # the step a split was last taken in
    step: int
    clist, nlist: seq[Thread] # in use up to clen and nlen
    clen, nlen: int
    stack: seq[(int, int)]    # in use up to top

func pikevm(re: Re, s: string, start: int, caps: var seq[int], cont: int,
    sc: var Scratch): bool =
  ## Leftmost-first match of `re` in `s[start..]`. `caps` gets each slot's
  ## byte offset in `s`, or -1: the starts of the match and its groups, then
  ## their ends. `cont` is where the character before `start` begins, when
  ## matching resumes after an earlier match, or -1.
  template code: untyped = re.prog.code
  let nslots = re.prog.slots
  let half = nslots div 2
  sc.pool.setLen(0)
  sc.refs.setLen(0)
  sc.freeSubs.setLen(0)
  if sc.seen.len < re.prog.splitIds: sc.seen.setLen(re.prog.splitIds)
  sc.clen = 0
  var matched = -1
  var top = 0

  template newSub(): int =
    var n: int
    if sc.freeSubs.len > 0:
      n = sc.freeSubs.pop
    else:
      n = sc.refs.len
      sc.refs.add 0
      sc.pool.setLen(sc.pool.len + nslots)
    sc.refs[n] = 1
    n

  template decref(sub: int) =
    let d = sub
    dec sc.refs[d]
    if sc.refs[d] == 0: sc.freeSubs.add d

  # Follow the non-consuming instructions from `pc`, adding the threads that
  # wait on a character to `list` in priority order. `pos` is where they
  # stand; `prev` is where the character before them starts.
  template push(list: var seq[Thread], count: var int, t: Thread) =
    if count == list.len: list.add t else: list[count] = t
    inc count
  template pushAlt(x: (int, int)) =
    if top == sc.stack.len: sc.stack.add x else: sc.stack[top] = x
    inc top

  template addThread(list: var seq[Thread], count: var int, pc0, sub0, pos, prev: int,
      first: bool) =
    top = 0
    pushAlt((pc0, sub0))
    while top > 0:
      dec top
      var (pc, sub) = sc.stack[top]
      while true:
        let op = code[pc]
        if op >= 0 and op < opWbeg:
          push(list, count, Thread(pc: pc, sub: sub))
          break
        if op > opJmp or op < 0:
          let id = abs(op)
          if sc.seen[id] == sc.step:
            decref(sub)
            break
          sc.seen[id] = sc.step
          inc sc.refs[sub]
          let target = pc + 2 + code[pc + 1]
          if op > 0:
            pushAlt((target, sub))
            pc += 2
          else:
            pushAlt((pc + 2, sub))
            pc = target
          continue
        if op == opSave:
          if sc.refs[sub] > 1:
            dec sc.refs[sub]
            let copy = newSub()
            for k in 0 ..< nslots: sc.pool[copy * nslots + k] = sc.pool[sub * nslots + k]
            sub = copy
          sc.pool[sub * nslots + code[pc + 1]] = pos
          pc += 2
          continue
        if op == opJmp:
          pc += 2 + code[pc + 1]
          continue
        template wordBefore: bool =
          if first: cont >= 0 and isWordAt(s, cont) else: isWordAt(s, prev)
        let pass =
          case op
          of opWb: wordBefore != isWordAt(s, pos)
          of opNotb: wordBefore == isWordAt(s, pos)
          of opWbeg: not wordBefore and isWordAt(s, pos)
          of opWend: wordBefore and not isWordAt(s, pos)
          of opBol: first and pos == start and cont < 0
          of opEol: pos >= s.len
          else: false
        if not pass:
          decref(sub)
          break
        inc pc

  var sp = start
  inc sc.step
  block:
    let sub = newSub()
    for k in 0 ..< nslots: sc.pool[sub * nslots + k] = -1
    sc.pool[sub * nslots] = start
    addThread(sc.clist, sc.clen, 0, sub, start, -1, true)
  while true:
    let atEnd = sp >= s.len
    var c = (if atEnd: 0 else: ucCode(s, sp, re.utf8))
    if re.insensitive: c = fold(c, re.utf8)
    let next = (if atEnd: sp else: sp + ucLen(s, sp, re.utf8))
    inc sc.step
    sc.nlen = 0
    var i = 0
    while i < sc.clen:
      let t = sc.clist[i]
      inc i
      let op = code[t.pc]
      var npc = -1
      case op
      of opChar:
        if not atEnd and c == code[t.pc + 1]:
          npc = t.pc + 2
      of opClass:
        if not atEnd and classMatch(code, t.pc + 1, c):
          npc = t.pc + code[t.pc + 2] * 2 + 3
      of opAny:
        if not atEnd: npc = t.pc + 1
      of opMatch:
        if matched >= 0: decref(matched)
        matched = t.sub
        # The rest of the list is lower priority than this match.
        for k in i ..< sc.clen: decref(sc.clist[k].sub)
        break
      else: discard
      if npc < 0:
        decref(t.sub)
      else:
        addThread(sc.nlist, sc.nlen, npc, t.sub, next, sp, false)
    if atEnd: break
    if matched < 0:
      let sub = newSub()
      for k in 0 ..< nslots: sc.pool[sub * nslots + k] = -1
      sc.pool[sub * nslots] = next
      addThread(sc.nlist, sc.nlen, 0, sub, next, sp, false)
    elif sc.nlen == 0:
      break
    swap(sc.clist, sc.nlist)
    swap(sc.clen, sc.nlen)
    sp = next
  if matched < 0: return false
  caps.setLen(nslots)
  for k in 0 ..< half:
    caps[2 * k] = sc.pool[matched * nslots + k]
    caps[2 * k + 1] = sc.pool[matched * nslots + half + k]
  true

iterator matchRaw(s: string, start: int, re: Re, global: ReGlobalKind, sub: bool
  ): Slice[int] {.closure.} =
  let start = clamp(start, 0, s.len)
  var
    p = start
    lastEnd = -1
    cont = -1
    caps: seq[int]
    scratch: Scratch

  while true:
    if not pikevm(re, s, p, caps, cont, scratch): break

    var i = 0
    while i < re.prog.slots:
      let slice =
        if caps[i] < 0 or caps[i + 1] < 0: -1 .. -1
        else: caps[i] .. caps[i + 1] - 1
      if i == 0 and lastEnd == caps[1] and p == lastEnd:
        # An empty match at the same place as the last one's end, as `\<`
        # matches both sides of a restart: don't yield it twice.
        discard
      else:
        yield slice
      if not sub:
        break
      i += 2

    if p == caps[1]:
      # An empty match: step over a character instead of stopping.
      cont = p
      p += ucLen(s, p, re.utf8)
    else:
      p = caps[1]
      # The character before `p`, from its first byte, so `\b` sees all of it.
      var before = p - 1
      while before > start and (s.at(before) and 0xC0) == 0x80:
        dec before
      cont = before

    lastEnd = caps[1]
    case global
    of rgNone:
      break
    of rgIncludeLastEmpty:
      if p > s.len:
        break
    of rgExcludeLastEmpty:
      if p >= s.len:
        break

const reErrorMessages: array[ReErrorKind, string] = [
  "no error", "trailing backslash", "bad escape", "unclosed set",
  "bad range in set", "unsupported group", "unclosed group",
  "unmatched parenthesis", "bad repeat", "repeat count too large",
  "nothing to repeat", "too many nested groups", "pattern too large",
  "out of memory"]

func message*(kind: ReErrorKind): string =
  ## A short English description of `kind`.
  reErrorMessages[kind]

proc re*(s: string, flags: set[ReFlag] = {}): Re =
  ## Constructor of regular expressions. Raises ReError (a ValueError) saying
  ## why and where `s` didn't compile.
  var err: CompileError
  let prog = compile(s, reUtf8 in flags, err)
  if err.kind != reeNone:
    var e = newException(ReError,
      "cannot compile pattern: " & err.kind.message & " at byte " & $err.pos)
    e.kind = err.kind
    e.pos = err.pos
    raise e
  result = Re(prog: prog, insensitive: reIgnoreCase in flags,
    utf8: reUtf8 in flags, global: reGlobal in flags)
  if result.insensitive:
    # Fold the pattern's characters once here; matching folds the text's.
    template code: untyped = result.prog.code
    var i = 0
    while i < code.len:
      case code[i]
      of opChar:
        code[i + 1] = fold(code[i + 1], result.utf8)
        i += 2
      of opClass:
        for k in 0 ..< code[i + 2]:
          let at = i + 3 + 2 * k
          if code[at] != -1:
            code[at] = fold(code[at], result.utf8)
            code[at + 1] = fold(code[at + 1], result.utf8)
        i += 3 + 2 * code[i + 2]
      of opSave, opJmp: i += 2
      else:
        i += (if code[i] > opJmp or code[i] < 0: 2 else: 1)

proc groupsCount*(re: Re): int =
  ## Returns the number of capturing groups, counting the whole match.
  re.prog.slots div 2

iterator match*(s: string, pattern: Re, start = 0): string =
  ## Yields all matching substrings of `s[start..]` that match `pattern`.
  let rg = if pattern.global: rgIncludeLastEmpty else: rgNone
  for slice in matchRaw(s, start, pattern, rg, true):
    yield if slice.b >= slice.a and slice.a >= 0: s[slice] else: ""

iterator matchBounds*(s: string, pattern: Re, start = 0): Slice[int] =
  ## The byte bounds in `s` of every whole match in `s[start..]`, whether or
  ## not the pattern has reGlobal. An empty match comes out as `a ..< a`,
  ## that is with `b == a - 1`, once at each position it occurs, including
  ## one at the end of `s`.
  for slice in matchRaw(s, start, pattern, rgIncludeLastEmpty, false):
    yield slice

proc match*(s: string, pattern: Re, start = 0): seq[string] =
  ## Returns all matching substrings of `s[start..]` that match `pattern`.
  for m in match(s, pattern, start):
    result.add m

proc replace*(s: string, sub: Re, by: string = "", limit = 0): string =
  ## Replaces `sub` in `s` by the string `by`. Captures cannot be accessed in `by`.
  var
    pos = 0
    count = 0

  for slice in matchRaw(s, 0, sub, rgExcludeLastEmpty, false):
    if slice.b >= slice.a and slice.a >= 0: # not empty match
      result.add s[pos..slice.a - 1]
      result.add by
      pos = slice.b + 1
      count.inc
      if limit > 0 and count >= limit:
        break

  result.add s[pos..^1]

proc escapeRe*(s: string): string {.raises: [].} =
  ## Escapes `s` so that it can be matched verbatim.
  for c in s:
    case c
    of '\n': result.add "\\n"
    of '\r': result.add "\\r"
    of '\t': result.add "\\t"
    of '\f': result.add "\\f"
    of '\v': result.add "\\v"
    of '^', '$', '(', ')', '.', '[', ']', '{', '}', '*', '+', '?', '|', '\\':
      result.add '\\'
      result.add c
    else:
      result.add c
