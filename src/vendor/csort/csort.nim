# Batcher's odd-even mergesort with SIMD, handles arbitrary lengths.

# Instruction set tags. The sorting network takes one as a parameter, so a
# single build can hold a version per instruction set.
type
  NoSimd = object
  Neon = object
  Sse42 = object
  Avx2 = object
  Wasm128 = object

template lanes32(_: typedesc[NoSimd]): int = 0
template lanes64(_: typedesc[NoSimd]): int = 0

when defined(arm64) or defined(aarch64):
  type DefaultIsa = Neon

  # -- int32: 4-wide NEON --
  template lanes32(_: typedesc[Neon]): int = 4
  type Vec32 {.importc: "int32x4_t", header: "<arm_neon.h>".} = object
  proc neonLoad32(p: ptr int32): Vec32 {.importc: "vld1q_s32", header: "<arm_neon.h>".}
  proc store32(p: ptr int32, v: Vec32) {.importc: "vst1q_s32", header: "<arm_neon.h>".}
  proc min32(a, b: Vec32): Vec32 {.importc: "vminq_s32", header: "<arm_neon.h>".}
  proc max32(a, b: Vec32): Vec32 {.importc: "vmaxq_s32", header: "<arm_neon.h>".}

  # -- int64: 2-wide NEON (compare + bitselect) --
  template lanes64(_: typedesc[Neon]): int = 2
  type Vec64 {.importc: "int64x2_t", header: "<arm_neon.h>".} = object
  type VecU64 {.importc: "uint64x2_t", header: "<arm_neon.h>".} = object
  proc neonLoad64(p: ptr int64): Vec64 {.importc: "vld1q_s64", header: "<arm_neon.h>".}
  proc store64(p: ptr int64, v: Vec64) {.importc: "vst1q_s64", header: "<arm_neon.h>".}
  proc neonCgtS64(a, b: Vec64): VecU64 {.importc: "vcgtq_s64", header: "<arm_neon.h>".}
  proc neonBslS64(mask: VecU64, a, b: Vec64): Vec64 {.importc: "vbslq_s64", header: "<arm_neon.h>".}

  template load32(_: typedesc[Neon], p: ptr int32): Vec32 = neonLoad32(p)
  template load64(_: typedesc[Neon], p: ptr int64): Vec64 = neonLoad64(p)

  proc min64(a, b: Vec64): Vec64 {.inline.} =
    let mask = neonCgtS64(a, b) # true where a > b
    neonBslS64(mask, b, a)      # pick b where a>b, else a

  proc max64(a, b: Vec64): Vec64 {.inline.} =
    let mask = neonCgtS64(a, b)
    neonBslS64(mask, a, b)      # pick a where a>b, else b

elif defined(amd64):
  # No -msse4.2/-mavx2 here: passC reaches every C file in the build, and the
  # program would die on CPUs without them (e.g. Phenom II has neither). The
  # network is instead compiled once per instruction set with a target
  # attribute and chosen at runtime. The wrappers are templates so the
  # intrinsics expand inside those functions; a plain proc would need the
  # target attribute itself.

  # -- SSE4.2: 4 x int32, 2 x int64 --
  type Vec128 {.importc: "__m128i", header: "<smmintrin.h>".} = object
  proc sseLoad(p: ptr Vec128): Vec128 {.importc: "_mm_loadu_si128", header: "<smmintrin.h>".}
  proc sseStore(p: ptr Vec128, v: Vec128) {.importc: "_mm_storeu_si128", header: "<smmintrin.h>".}
  proc sseMin32(a, b: Vec128): Vec128 {.importc: "_mm_min_epi32", header: "<smmintrin.h>".}
  proc sseMax32(a, b: Vec128): Vec128 {.importc: "_mm_max_epi32", header: "<smmintrin.h>".}
  proc sseCmpGt64(a, b: Vec128): Vec128 {.importc: "_mm_cmpgt_epi64", header: "<nmmintrin.h>".}
  proc sseBlendv(a, b, mask: Vec128): Vec128 {.importc: "_mm_blendv_epi8", header: "<smmintrin.h>".}

  template lanes32(_: typedesc[Sse42]): int = 4
  template lanes64(_: typedesc[Sse42]): int = 2
  template load32(_: typedesc[Sse42], p: ptr int32): Vec128 = sseLoad(cast[ptr Vec128](p))
  template load64(_: typedesc[Sse42], p: ptr int64): Vec128 = sseLoad(cast[ptr Vec128](p))
  template store32(p: ptr int32, v: Vec128) = sseStore(cast[ptr Vec128](p), v)
  template store64(p: ptr int64, v: Vec128) = sseStore(cast[ptr Vec128](p), v)
  template min32(a, b: Vec128): Vec128 = sseMin32(a, b)
  template max32(a, b: Vec128): Vec128 = sseMax32(a, b)
  # pick b where a>b, else a
  template min64(a, b: Vec128): Vec128 = sseBlendv(a, b, sseCmpGt64(a, b))
  # pick a where a>b, else b
  template max64(a, b: Vec128): Vec128 = sseBlendv(b, a, sseCmpGt64(a, b))

  # -- AVX2: 8 x int32, 4 x int64 --
  type Vec256 {.importc: "__m256i", header: "<immintrin.h>".} = object
  proc avx2Load(p: ptr Vec256): Vec256 {.importc: "_mm256_loadu_si256", header: "<immintrin.h>".}
  proc avx2Store(p: ptr Vec256, v: Vec256) {.importc: "_mm256_storeu_si256", header: "<immintrin.h>".}
  proc avx2Min32(a, b: Vec256): Vec256 {.importc: "_mm256_min_epi32", header: "<immintrin.h>".}
  proc avx2Max32(a, b: Vec256): Vec256 {.importc: "_mm256_max_epi32", header: "<immintrin.h>".}
  proc avx2CmpGt64(a, b: Vec256): Vec256 {.importc: "_mm256_cmpgt_epi64", header: "<immintrin.h>".}
  proc avx2Blendv(a, b, mask: Vec256): Vec256 {.importc: "_mm256_blendv_epi8", header: "<immintrin.h>".}

  template lanes32(_: typedesc[Avx2]): int = 8
  template lanes64(_: typedesc[Avx2]): int = 4
  template load32(_: typedesc[Avx2], p: ptr int32): Vec256 = avx2Load(cast[ptr Vec256](p))
  template load64(_: typedesc[Avx2], p: ptr int64): Vec256 = avx2Load(cast[ptr Vec256](p))
  template store32(p: ptr int32, v: Vec256) = avx2Store(cast[ptr Vec256](p), v)
  template store64(p: ptr int64, v: Vec256) = avx2Store(cast[ptr Vec256](p), v)
  template min32(a, b: Vec256): Vec256 = avx2Min32(a, b)
  template max32(a, b: Vec256): Vec256 = avx2Max32(a, b)
  # pick b where a>b, else a
  template min64(a, b: Vec256): Vec256 = avx2Blendv(a, b, avx2CmpGt64(a, b))
  # pick a where a>b, else b
  template max64(a, b: Vec256): Vec256 = avx2Blendv(b, a, avx2CmpGt64(a, b))

  proc cpuHasSse42(): bool {.inline.} =
    {.emit: [result, " = __builtin_cpu_supports(\"sse4.2\");"].}

  proc cpuHasAvx2(): bool {.inline.} =
    {.emit: [result, " = __builtin_cpu_supports(\"avx2\");"].}

elif defined(wasm):
  type DefaultIsa = Wasm128

  # WebAssembly simd128 uses one 128-bit type for every lane width.
  type Vec128 {.importc: "v128_t", header: "<wasm_simd128.h>".} = object
  proc wasmLoad(p: pointer): Vec128 {.importc: "wasm_v128_load", header: "<wasm_simd128.h>".}
  proc wasmStore(p: pointer, v: Vec128) {.importc: "wasm_v128_store", header: "<wasm_simd128.h>".}
  proc wasmBitselect(a, b, mask: Vec128): Vec128 {.importc: "wasm_v128_bitselect", header: "<wasm_simd128.h>".}

  # -- int32: 4-wide simd128 --
  template lanes32(_: typedesc[Wasm128]): int = 4
  proc min32(a, b: Vec128): Vec128 {.importc: "wasm_i32x4_min", header: "<wasm_simd128.h>".}
  proc max32(a, b: Vec128): Vec128 {.importc: "wasm_i32x4_max", header: "<wasm_simd128.h>".}

  template load32(_: typedesc[Wasm128], p: ptr int32): Vec128 = wasmLoad(p)
  proc store32(p: ptr int32, v: Vec128) {.inline.} = wasmStore(p, v)

  # -- int64: 2-wide simd128 (compare + bitselect; there is no i64x2 min/max) --
  template lanes64(_: typedesc[Wasm128]): int = 2
  proc wasmCgtS64(a, b: Vec128): Vec128 {.importc: "wasm_i64x2_gt", header: "<wasm_simd128.h>".}

  template load64(_: typedesc[Wasm128], p: ptr int64): Vec128 = wasmLoad(p)
  proc store64(p: ptr int64, v: Vec128) {.inline.} = wasmStore(p, v)

  proc min64(a, b: Vec128): Vec128 {.inline.} =
    let mask = wasmCgtS64(a, b) # true where a > b
    wasmBitselect(b, a, mask)   # pick b where a>b, else a

  proc max64(a, b: Vec128): Vec128 {.inline.} =
    let mask = wasmCgtS64(a, b)
    wasmBitselect(a, b, mask)   # pick a where a>b, else b

else:
  type DefaultIsa = NoSimd

# Constant-time scalar minmax using XOR-masked swap.
# Widens to a larger signed type to compute (b - a), extracts the sign bit
# to build an all-ones or all-zeros mask, then XOR-swaps conditionally.
# An asm barrier prevents the compiler from converting this to branches.

proc asmBarrier32(x: var uint32) {.inline.} =
  {.emit: ["__asm__ volatile(\"\" : \"+r\"(", x, "));"].}

proc asmBarrier64(x: var uint64) {.inline.} =
  {.emit: ["__asm__ volatile(\"\" : \"+r\"(", x, "));"].}

proc minmax(a, b: var int32) {.inline.} =
  # `a > b` compiles to cmp + setcc (constant-time)
  let swap = uint32(ord(a > b))  # 0 or 1, branchless
  var mask = not (swap - 1'u32)  # all 1s if a > b, all 0s otherwise
  asmBarrier32(mask)
  let d = cast[uint32](a) xor cast[uint32](b)
  let masked = d and mask
  a = a xor cast[int32](masked)
  b = b xor cast[int32](masked)

proc minmax(a, b: var int64) {.inline.} =
  # On aarch64/x86_64, `a > b` compiles to cmp + cset/setcc (constant-time).
  # The asm barrier prevents the compiler from converting the XOR swap back
  # into a conditional branch.
  let swap = uint64(ord(a > b))     # 0 or 1, branchless on aarch64/x86_64
  var mask = not (swap - 1'u64)     # all 1s if a > b, all 0s otherwise
  asmBarrier64(mask)
  let d = cast[uint64](a) xor cast[uint64](b)
  let masked = d and mask
  a = a xor cast[int64](masked)
  b = b xor cast[int64](masked)

# Maps IEEE 754 float bit-patterns to an integer sort key that preserves
# the natural float ordering under signed integer comparison:
#   - positive floats (sign=0): key = bits unchanged (already ordered)
#   - negative floats (sign=1): key = bits ^ 0x7FFFFFFF (flip lower bits,
#     inverting the order so more-negative floats get smaller keys)
# The function is its own inverse, so applying it again restores the original.

proc floatSortKey(s: int32): int32 {.inline.} =
  let sign = cast[uint32](s) shr 31    # 1 if negative, 0 if positive
  let mask = cast[int32](0'u32 - sign) # all 1s if negative, 0 if positive
  s xor (mask and high(int32))

proc floatSortKey(s: int64): int64 {.inline.} =
  let sign = cast[uint64](s) shr 63
  let mask = cast[int64](0'u64 - sign)
  s xor (mask and high(int64))

{.push overflowChecks: off.}

proc cascade[T: int32 | int64](data: ptr UncheckedArray[T], j, p, q: int) {.inline.} =
  var a = data[j + p]
  var r = q
  while r > p:
    minmax(a, data[j + r])
    r = r shr 1
  data[j + p] = a

# Core sorting network, templated over element type and SIMD use.
# Operates directly on a raw pointer + length so float sorts can reuse it
# after transforming their data in place via floatSortKey.
template sortNetwork(T, Isa: typedesc, data: ptr UncheckedArray[T], n: int) =
  const vecLen = when T is int32: lanes32(Isa) else: lanes64(Isa)

  var top = 1
  while top < n - top:
    top += top

  var p = top
  while p >= 1:
    # Loop 1: main minmax pairs
    var i = 0
    while i + 2 * p <= n:
      var k = 0
      when vecLen > 0:
        while k + vecLen <= p:
          when T is int32:
            let aVec = load32(Isa, addr data[i + k])
            let bVec = load32(Isa, addr data[i + k + p])
            store32(addr data[i + k], min32(aVec, bVec))
            store32(addr data[i + k + p], max32(aVec, bVec))
          else:
            let aVec = load64(Isa, addr data[i + k])
            let bVec = load64(Isa, addr data[i + k + p])
            store64(addr data[i + k], min64(aVec, bVec))
            store64(addr data[i + k + p], max64(aVec, bVec))
          k += vecLen
      while k < p:
        minmax(data[i + k], data[i + k + p])
        k += 1
      i += 2 * p

    # Loop 2: residual minmax
    var j = i
    when vecLen > 0:
      while j + vecLen + p <= n:
        when T is int32:
          let aVec = load32(Isa, addr data[j])
          let bVec = load32(Isa, addr data[j + p])
          store32(addr data[j], min32(aVec, bVec))
          store32(addr data[j + p], max32(aVec, bVec))
        else:
          let aVec = load64(Isa, addr data[j])
          let bVec = load64(Isa, addr data[j + p])
          store64(addr data[j], min64(aVec, bVec))
          store64(addr data[j + p], max64(aVec, bVec))
        j += vecLen
    while j + p < n:
      minmax(data[j], data[j + p])
      j += 1

    # Cascade loops
    i = 0
    j = 0
    var q = top
    while q > p:
      block qBody:
        if j != i:
          while true:
            if j + q == n:
              break qBody
            cascade(data, j, p, q)
            j += 1
            if j == i + p:
              i += 2 * p
              break

        # Loop 3: cascade groups with SIMD
        while i + p + q <= n:
          var k = 0
          when vecLen > 0:
            while k + vecLen <= p:
              when T is int32:
                var aVec = load32(Isa, addr data[i + k + p])
                var r = q
                while r > p:
                  let cVec = load32(Isa, addr data[i + k + r])
                  let hi = max32(aVec, cVec)
                  aVec = min32(aVec, cVec)
                  store32(addr data[i + k + r], hi)
                  r = r shr 1
                store32(addr data[i + k + p], aVec)
              else:
                var aVec = load64(Isa, addr data[i + k + p])
                var r = q
                while r > p:
                  let cVec = load64(Isa, addr data[i + k + r])
                  let hi = max64(aVec, cVec)
                  aVec = min64(aVec, cVec)
                  store64(addr data[i + k + r], hi)
                  r = r shr 1
                store64(addr data[i + k + p], aVec)
              k += vecLen
          while k < p:
            cascade(data, i + k, p, q)
            k += 1
          i += 2 * p

        # Loop 4: residual cascades
        j = i
        when vecLen > 0:
          if p >= vecLen:
            while j + vecLen + q <= n:
              when T is int32:
                var aVec = load32(Isa, addr data[j + p])
                var r = q
                while r > p:
                  let cVec = load32(Isa, addr data[j + r])
                  let hi = max32(aVec, cVec)
                  aVec = min32(aVec, cVec)
                  store32(addr data[j + r], hi)
                  r = r shr 1
                store32(addr data[j + p], aVec)
              else:
                var aVec = load64(Isa, addr data[j + p])
                var r = q
                while r > p:
                  let cVec = load64(Isa, addr data[j + r])
                  let hi = max64(aVec, cVec)
                  aVec = min64(aVec, cVec)
                  store64(addr data[j + r], hi)
                  r = r shr 1
                store64(addr data[j + p], aVec)
              j += vecLen
        while j + q < n:
          cascade(data, j, p, q)
          j += 1

      q = q shr 1

    p = p shr 1

when defined(amd64):
  proc cSortScalar[T: int32 | int64](data: ptr UncheckedArray[T], n: int) =
    sortNetwork(T, NoSimd, data, n)

  proc cSortSse42[T: int32 | int64](data: ptr UncheckedArray[T], n: int)
      {.codegenDecl: "__attribute__((target(\"sse4.2\"))) $# $#$#".} =
    sortNetwork(T, Sse42, data, n)

  proc cSortAvx2[T: int32 | int64](data: ptr UncheckedArray[T], n: int)
      {.codegenDecl: "__attribute__((target(\"avx2\"))) $# $#$#".} =
    sortNetwork(T, Avx2, data, n)

  proc cSortCore[T: int32 | int64](data: ptr UncheckedArray[T], n: int) =
    if n < 2: return
    if cpuHasAvx2(): cSortAvx2(data, n)
    elif cpuHasSse42(): cSortSse42(data, n)
    else: cSortScalar(data, n)
else:
  proc cSortCore[T: int32 | int64](data: ptr UncheckedArray[T], n: int) =
    if n < 2: return
    sortNetwork(T, DefaultIsa, data, n)

{.pop.}

proc sort*[T: int32 | int64](items: var openArray[T]) =
  if items.len < 2: return
  cSortCore(cast[ptr UncheckedArray[T]](addr items[0]), items.len)

proc sort*(items: var openArray[int]) =
  if items.len < 2: return
  when sizeof(int) == 4:
    cSortCore(cast[ptr UncheckedArray[int32]](addr items[0]), items.len)
  else:
    cSortCore(cast[ptr UncheckedArray[int64]](addr items[0]), items.len)

# Unsigned sort: XOR each element with the high bit to map [0..UINT_MAX] ->
# [INT_MIN..INT_MAX] preserving order, sort as signed integers, then un-map.

proc sort*[T: uint32 | uint64](items: var openArray[T]) =
  type iT = (when T is uint32: int32 else: int64)
  let n = items.len
  if n < 2: return
  let idata = cast[ptr UncheckedArray[iT]](addr items[0])
  for i in 0 ..< n: idata[i] = idata[i] xor low(iT)
  cSortCore(idata, n)
  for i in 0 ..< n: idata[i] = idata[i] xor low(iT)

proc sort*(items: var openArray[uint]) =
  if items.len < 2: return
  let n = items.len
  when sizeof(uint) == 4:
    let idata = cast[ptr UncheckedArray[int32]](addr items[0])
    for i in 0 ..< n: idata[i] = idata[i] xor low(int32)
    cSortCore(idata, n)
    for i in 0 ..< n: idata[i] = idata[i] xor low(int32)
  else:
    let idata = cast[ptr UncheckedArray[int64]](addr items[0])
    for i in 0 ..< n: idata[i] = idata[i] xor low(int64)
    cSortCore(idata, n)
    for i in 0 ..< n: idata[i] = idata[i] xor low(int64)

# Float sort: transform bit-patterns to sort keys, sort as integers, untransform.
# Resulting order: -NaN < -INF < ... < -0.0 < +0.0 < ... < +INF < +NaN

proc sort*[T: float32 | float64](items: var openArray[T]) =
  type iT = (when T is float32: int32 else: int64)
  let n = items.len
  if n < 2: return
  let idata = cast[ptr UncheckedArray[iT]](addr items[0])
  for i in 0 ..< n: idata[i] = floatSortKey(idata[i])
  cSortCore(idata, n)
  for i in 0 ..< n: idata[i] = floatSortKey(idata[i])
