## x264 and x265 both assemble their AVX-512 kernels whenever x86 asm is
## enabled; unlike libvpx, SVT-AV1 and FFmpeg neither has a configure switch to
## leave them out. The dispatchers only call them when the CPU reports AVX-512,
## but the code is still emitted into the static library and linked in.
##
## Wrap every AVX-512 line of x86inc-style assembly in a guard nasm skips when
## it targets macho64, so Intel macOS builds assemble none of it. Other output
## formats are untouched, which keeps a cross-build from the same source tree in
## step with the C-side guards in patches/x264.patch and patches/x265.patch.

import std/[os, sets, strutils, tables]

const
  marker = "AVX-512 stripped on Intel macOS"
  guardOpen = "%ifnidn __OUTPUT_FORMAT__,macho64 ; " & marker
  guardClose = "%endif ; " & marker

  ## Assembler state, not code. These show up both inside AVX-512 sections and
  ## after the last function of one, so they must survive the strip; treating
  ## them as the end of the section keeps whatever follows (a struc's fields,
  ## the next block of functions) out of the guard. A later INIT_*_avx512
  ## starts a new section for the ones that appear mid-section.
  sectionEnders = ["struc", "endstruc", "cextern", "DECLARE_REG",
                   "DECLARE_REG_TMP", "align", "alignb", "ALIGN"]

proc isInit(line: string): bool =
  line.startsWith("INIT_MMX") or line.startsWith("INIT_XMM") or
    line.startsWith("INIT_YMM") or line.startsWith("INIT_ZMM")

proc isAvx512(line: string): bool =
  line.toLowerAscii().contains("avx512")

proc isMacroStart(line: string): bool =
  line.startsWith("%macro ") or line.startsWith("%imacro ")

proc endsSection(token: string): bool =
  token.startsWith("SECTION") or token in sectionEnders

proc firstToken(line: string): string =
  if line.len == 0: "" else: line.splitWhitespace()[0]

type MacroKind = enum
  ## What a call to the macro does to the assembler's cpuflags.
  inherits   ## no INIT of its own: emits with whatever section it is called in
  entersAvx512
  leavesAvx512

proc macroBodies(path: string): Table[string, seq[string]] =
  ## Body lines per macro name. A nested definition's lines belong to the inner
  ## macro only, since defining one emits nothing.
  var stack: seq[string]
  for line in lines(path):
    let text = line.strip()
    if isMacroStart(text):
      let name = text.splitWhitespace()[1]
      stack.add(name)
      if name notin result: result[name] = @[]
    elif text.startsWith("%endmacro"):
      if stack.len > 0: discard stack.pop()
    elif stack.len > 0:
      result[stack[^1]].add(text)

proc classify(path: string): Table[string, MacroKind] =
  ## x265 wraps whole functions in macros that set their own INIT, so the call
  ## site says nothing about what gets emitted: FILTER_VER_LUMA_PP is called
  ## right after an AVX-512 section yet emits SSE4, because its body starts with
  ## INIT_XMM sse4. Resolve each macro to the cpuflags it leaves behind,
  ## following calls to other macros in the same file.
  let bodies = macroBodies(path)
  var
    avxOf = initTable[string, bool]()   ## saw an AVX-512 INIT
    otherOf = initTable[string, bool]() ## saw any other INIT
    resolved = initHashSet[string]()

  proc resolve(name: string, active: var HashSet[string]) =
    if name in resolved or name in active: return
    active.incl(name)
    var avx, other = false
    for text in bodies.getOrDefault(name):
      if isInit(text):
        if isAvx512(text): avx = true else: other = true
      elif text.len > 0 and not text.startsWith(";") and
          not text.startsWith("%"):
        let callee = firstToken(text)
        if callee in bodies and callee != name:
          resolve(callee, active)
          if avxOf.getOrDefault(callee): avx = true
          if otherOf.getOrDefault(callee): other = true
    active.excl(name)
    avxOf[name] = avx
    otherOf[name] = other
    resolved.incl(name)

  for name in bodies.keys:
    var active = initHashSet[string]()
    resolve(name, active)

  for name in bodies.keys:
    let avx = avxOf.getOrDefault(name)
    let other = otherOf.getOrDefault(name)
    if avx and other:
      quit "strip_avx512_asm: " & path.extractFilename() & " macro " & name &
        " mixes AVX-512 and other INITs; stripping its calls would take out" &
        " more than AVX-512"
    result[name] =
      if avx: entersAvx512
      elif other: leavesAvx512
      else: inherits

proc stripFile(path: string): int =
  let macros = classify(path)
  var
    output: seq[string]
    macroDepth = 0
    avx512 = false
    guarded = false

  template closeGuard =
    if guarded:
      output.add(guardClose)
      guarded = false

  for line in lines(path):
    let
      text = line.strip()
      token = firstToken(text)

    # A macro body emits nothing until it is called, so leave definitions alone
    # and guard the calls instead.
    if macroDepth > 0:
      output.add(line)
      if isMacroStart(text): inc macroDepth
      elif text.startsWith("%endmacro"): dec macroDepth
      continue

    if isMacroStart(text):
      closeGuard()
      output.add(line)
      inc macroDepth
      continue

    # INIT_* picks the register size and cpuflags every following function is
    # built with, so it alone decides whether we are in an AVX-512 section.
    if isInit(text):
      closeGuard()
      avx512 = isAvx512(text)
      output.add(line)
      continue

    # Blanks and comments can sit inside the guard; preprocessor directives
    # cannot, or a %if/%endif pair would end up split across it.
    if text.len == 0 or text.startsWith(";"):
      output.add(line)
      continue

    # Naming a kernel is enough to pull it in from outside an AVX-512 section:
    # x264's cabac-a.asm declares them with cextern (which nasm lists in the
    # symbol table used or not) and builds a jump table of them with a macro.
    # Only those two forms count. An ordinary instruction that happens to name
    # an AVX-512 symbol is reading data, not calling a kernel, and x265 has AVX2
    # functions loading shuffle tables named *_avx512 that must keep working.
    let refsAvx512 = isAvx512(text) and
      (token == "cextern" or token in macros)

    if not refsAvx512 and (text.startsWith("%") or endsSection(token)):
      if endsSection(token):
        avx512 = false
      closeGuard()
      output.add(line)
      continue

    let kind = macros.getOrDefault(token, inherits)
    if kind == leavesAvx512:
      # Emits with its own non-AVX-512 INIT and leaves that behind, whatever
      # section it was called from.
      avx512 = false
      closeGuard()
      output.add(line)
      continue

    if not avx512 and not refsAvx512 and kind != entersAvx512:
      closeGuard()
      output.add(line)
      continue

    if not guarded:
      output.add(guardOpen)
      guarded = true
    output.add(line)
    inc result

    # The macro left the assembler in an AVX-512 section, so whatever follows
    # is AVX-512 too until the next INIT_*.
    if kind == entersAvx512:
      avx512 = true

  closeGuard()

  if result > 0:
    writeFile(path, output.join("\n") & "\n")

if paramCount() != 1 or not dirExists(paramStr(1)):
  quit "usage: strip_avx512_asm <x86 assembly directory>"

var
  total = 0
  done = 0
for path in walkFiles(paramStr(1) / "*.asm"):
  if readFile(path).contains(marker):
    inc done
    continue
  let stripped = stripFile(path)
  if stripped > 0:
    echo "stripped ", stripped, " AVX-512 lines from ", path.extractFilename()
    total += stripped

if total == 0 and done == 0:
  quit "strip_avx512_asm: found no AVX-512 assembly, has the source been" &
    " restructured?"
