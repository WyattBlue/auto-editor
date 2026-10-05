# Batcher's odd-even mergesort with SIMD, handles arbitrary lengths.

when defined(arm64) or defined(aarch64):
  const HasSimd = true

  # -- int32: 4-wide NEON --
  const VecLen32 = 4
  type Vec32 {.importc: "int32x4_t", header: "<arm_neon.h>".} = object
  proc neonLoad32(p: ptr int32): Vec32 {.importc: "vld1q_s32", header: "<arm_neon.h>".}
  proc neonStore32(p: ptr int32, v: Vec32) {.importc: "vst1q_s32", header: "<arm_neon.h>".}
  proc neonMin32(a, b: Vec32): Vec32 {.importc: "vminq_s32", header: "<arm_neon.h>".}
  proc neonMax32(a, b: Vec32): Vec32 {.importc: "vmaxq_s32", header: "<arm_neon.h>".}

  # -- int64: 2-wide NEON (compare + bitselect) --
  const VecLen64 = 2
  type Vec64 {.importc: "int64x2_t", header: "<arm_neon.h>".} = object
  type VecU64 {.importc: "uint64x2_t", header: "<arm_neon.h>".} = object
  proc neonLoad64(p: ptr int64): Vec64 {.importc: "vld1q_s64", header: "<arm_neon.h>".}
  proc neonStore64(p: ptr int64, v: Vec64) {.importc: "vst1q_s64", header: "<arm_neon.h>".}
  proc neonCgtS64(a, b: Vec64): VecU64 {.importc: "vcgtq_s64", header: "<arm_neon.h>".}
  proc neonBslS64(mask: VecU64, a, b: Vec64): Vec64 {.importc: "vbslq_s64", header: "<arm_neon.h>".}

  proc neonMin64(a, b: Vec64): Vec64 {.inline.} =
    let mask = neonCgtS64(a, b) # true where a > b
    neonBslS64(mask, b, a)      # pick b where a>b, else a

  proc neonMax64(a, b: Vec64): Vec64 {.inline.} =
    let mask = neonCgtS64(a, b)
    neonBslS64(mask, a, b)      # pick a where a>b, else b

elif defined(amd64) and defined(avx2):
  const HasSimd = true
  {.passC: "-mavx2".}

  # -- int32: 8-wide AVX2 --
  const VecLen32 = 8
  type Vec32 {.importc: "__m256i", header: "<immintrin.h>".} = object
  proc avx2Load(p: ptr Vec32): Vec32 {.importc: "_mm256_loadu_si256", header: "<immintrin.h>".}
  proc avx2Store(p: ptr Vec32, v: Vec32) {.importc: "_mm256_storeu_si256", header: "<immintrin.h>".}
  proc avx2Min32(a, b: Vec32): Vec32 {.importc: "_mm256_min_epi32", header: "<immintrin.h>".}
  proc avx2Max32(a, b: Vec32): Vec32 {.importc: "_mm256_max_epi32", header: "<immintrin.h>".}

  proc neonLoad32(p: ptr int32): Vec32 {.inline.} = avx2Load(cast[ptr Vec32](p))
  proc neonStore32(p: ptr int32, v: Vec32) {.inline.} = avx2Store(cast[ptr Vec32](p), v)
  proc neonMin32(a, b: Vec32): Vec32 {.inline.} = avx2Min32(a, b)
  proc neonMax32(a, b: Vec32): Vec32 {.inline.} = avx2Max32(a, b)

  # -- int64: 4-wide AVX2 --
  const VecLen64 = 4
  type Vec64 = Vec32 # same __m256i type
  proc avx2CmpGt64(a, b: Vec64): Vec64 {.importc: "_mm256_cmpgt_epi64", header: "<immintrin.h>".}
  proc avx2Blendv(a, b, mask: Vec64): Vec64 {.importc: "_mm256_blendv_epi8", header: "<immintrin.h>".}

  proc neonLoad64(p: ptr int64): Vec64 {.inline.} = avx2Load(cast[ptr Vec32](p))
  proc neonStore64(p: ptr int64, v: Vec64) {.inline.} = avx2Store(cast[ptr Vec32](p), v)

  proc neonMin64(a, b: Vec64): Vec64 {.inline.} =
    let mask = avx2CmpGt64(a, b)
    avx2Blendv(a, b, mask) # pick b where a>b, else a

  proc neonMax64(a, b: Vec64): Vec64 {.inline.} =
    let mask = avx2CmpGt64(a, b)
    avx2Blendv(b, a, mask) # pick a where a>b, else b

elif defined(amd64):
  # No -msse4.2 here: passC reaches every C file in the build, and the program
  # would die on CPUs without SSE4.2 (e.g. Phenom II). Instead only the SIMD
  # sorting network is compiled with target("sse4.2"), and it is chosen at
  # runtime. The wrappers are templates so the intrinsics expand inside that
  # function; a plain proc would need the target attribute itself.
  const HasSimd = true
  const RuntimeSse42 = true

  # -- int32: 4-wide SSE4.1 --
  const VecLen32 = 4
  type Vec32 {.importc: "__m128i", header: "<smmintrin.h>".} = object
  proc sseLoad(p: ptr Vec32): Vec32 {.importc: "_mm_loadu_si128", header: "<smmintrin.h>".}
  proc sseStore(p: ptr Vec32, v: Vec32) {.importc: "_mm_storeu_si128", header: "<smmintrin.h>".}
  proc sseMin32(a, b: Vec32): Vec32 {.importc: "_mm_min_epi32", header: "<smmintrin.h>".}
  proc sseMax32(a, b: Vec32): Vec32 {.importc: "_mm_max_epi32", header: "<smmintrin.h>".}

  template neonLoad32(p: ptr int32): Vec32 = sseLoad(cast[ptr Vec32](p))
  template neonStore32(p: ptr int32, v: Vec32) = sseStore(cast[ptr Vec32](p), v)
  template neonMin32(a, b: Vec32): Vec32 = sseMin32(a, b)
  template neonMax32(a, b: Vec32): Vec32 = sseMax32(a, b)

  # -- int64: 2-wide SSE4.2 --
  const VecLen64 = 2
  type Vec64 = Vec32 # same __m128i type
  proc sseCmpGt64(a, b: Vec64): Vec64 {.importc: "_mm_cmpgt_epi64", header: "<nmmintrin.h>".}
  proc sseBlendv(a, b, mask: Vec64): Vec64 {.importc: "_mm_blendv_epi8", header: "<smmintrin.h>".}

  template neonLoad64(p: ptr int64): Vec64 = sseLoad(cast[ptr Vec32](p))
  template neonStore64(p: ptr int64, v: Vec64) = sseStore(cast[ptr Vec32](p), v)
  # pick b where a>b, else a
  template neonMin64(a, b: Vec64): Vec64 = sseBlendv(a, b, sseCmpGt64(a, b))
  # pick a where a>b, else b
  template neonMax64(a, b: Vec64): Vec64 = sseBlendv(b, a, sseCmpGt64(a, b))

  proc cpuHasSse42(): bool {.inline.} =
    {.emit: [result, " = __builtin_cpu_supports(\"sse4.2\");"].}

elif defined(wasm):
  const HasSimd = true

  # WebAssembly simd128 uses one 128-bit type for every lane width.
  type Vec128 {.importc: "v128_t", header: "<wasm_simd128.h>".} = object
  proc wasmLoad(p: pointer): Vec128 {.importc: "wasm_v128_load", header: "<wasm_simd128.h>".}
  proc wasmStore(p: pointer, v: Vec128) {.importc: "wasm_v128_store", header: "<wasm_simd128.h>".}
  proc wasmBitselect(a, b, mask: Vec128): Vec128 {.importc: "wasm_v128_bitselect", header: "<wasm_simd128.h>".}

  # -- int32: 4-wide simd128 --
  const VecLen32 = 4
  type Vec32 = Vec128
  proc wasmMin32(a, b: Vec32): Vec32 {.importc: "wasm_i32x4_min", header: "<wasm_simd128.h>".}
  proc wasmMax32(a, b: Vec32): Vec32 {.importc: "wasm_i32x4_max", header: "<wasm_simd128.h>".}

  proc neonLoad32(p: ptr int32): Vec32 {.inline.} = wasmLoad(p)
  proc neonStore32(p: ptr int32, v: Vec32) {.inline.} = wasmStore(p, v)
  proc neonMin32(a, b: Vec32): Vec32 {.inline.} = wasmMin32(a, b)
  proc neonMax32(a, b: Vec32): Vec32 {.inline.} = wasmMax32(a, b)

  # -- int64: 2-wide simd128 (compare + bitselect; there is no i64x2 min/max) --
  const VecLen64 = 2
  type Vec64 = Vec128
  proc wasmCgtS64(a, b: Vec64): Vec64 {.importc: "wasm_i64x2_gt", header: "<wasm_simd128.h>".}

  proc neonLoad64(p: ptr int64): Vec64 {.inline.} = wasmLoad(p)
  proc neonStore64(p: ptr int64, v: Vec64) {.inline.} = wasmStore(p, v)

  proc neonMin64(a, b: Vec64): Vec64 {.inline.} =
    let mask = wasmCgtS64(a, b) # true where a > b
    wasmBitselect(b, a, mask)   # pick b where a>b, else a

  proc neonMax64(a, b: Vec64): Vec64 {.inline.} =
    let mask = wasmCgtS64(a, b)
    wasmBitselect(a, b, mask)   # pick a where a>b, else b

else:
  const HasSimd = false
  const VecLen32 = 0
  const VecLen64 = 0

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
template sortNetwork(T: typedesc, data: ptr UncheckedArray[T], n: int, useSimd: static bool) =
  const vecLen = when not useSimd: 0 elif T is int32: VecLen32 else: VecLen64

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
            let aVec = neonLoad32(addr data[i + k])
            let bVec = neonLoad32(addr data[i + k + p])
            neonStore32(addr data[i + k], neonMin32(aVec, bVec))
            neonStore32(addr data[i + k + p], neonMax32(aVec, bVec))
          else:
            let aVec = neonLoad64(addr data[i + k])
            let bVec = neonLoad64(addr data[i + k + p])
            neonStore64(addr data[i + k], neonMin64(aVec, bVec))
            neonStore64(addr data[i + k + p], neonMax64(aVec, bVec))
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
          let aVec = neonLoad32(addr data[j])
          let bVec = neonLoad32(addr data[j + p])
          neonStore32(addr data[j], neonMin32(aVec, bVec))
          neonStore32(addr data[j + p], neonMax32(aVec, bVec))
        else:
          let aVec = neonLoad64(addr data[j])
          let bVec = neonLoad64(addr data[j + p])
          neonStore64(addr data[j], neonMin64(aVec, bVec))
          neonStore64(addr data[j + p], neonMax64(aVec, bVec))
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
                var aVec = neonLoad32(addr data[i + k + p])
                var r = q
                while r > p:
                  let cVec = neonLoad32(addr data[i + k + r])
                  let hi = neonMax32(aVec, cVec)
                  aVec = neonMin32(aVec, cVec)
                  neonStore32(addr data[i + k + r], hi)
                  r = r shr 1
                neonStore32(addr data[i + k + p], aVec)
              else:
                var aVec = neonLoad64(addr data[i + k + p])
                var r = q
                while r > p:
                  let cVec = neonLoad64(addr data[i + k + r])
                  let hi = neonMax64(aVec, cVec)
                  aVec = neonMin64(aVec, cVec)
                  neonStore64(addr data[i + k + r], hi)
                  r = r shr 1
                neonStore64(addr data[i + k + p], aVec)
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
                var aVec = neonLoad32(addr data[j + p])
                var r = q
                while r > p:
                  let cVec = neonLoad32(addr data[j + r])
                  let hi = neonMax32(aVec, cVec)
                  aVec = neonMin32(aVec, cVec)
                  neonStore32(addr data[j + r], hi)
                  r = r shr 1
                neonStore32(addr data[j + p], aVec)
              else:
                var aVec = neonLoad64(addr data[j + p])
                var r = q
                while r > p:
                  let cVec = neonLoad64(addr data[j + r])
                  let hi = neonMax64(aVec, cVec)
                  aVec = neonMin64(aVec, cVec)
                  neonStore64(addr data[j + r], hi)
                  r = r shr 1
                neonStore64(addr data[j + p], aVec)
              j += vecLen
        while j + q < n:
          cascade(data, j, p, q)
          j += 1

      q = q shr 1

    p = p shr 1

when declared(RuntimeSse42):
  proc cSortScalar[T: int32 | int64](data: ptr UncheckedArray[T], n: int) =
    sortNetwork(T, data, n, false)

  proc cSortSse42[T: int32 | int64](data: ptr UncheckedArray[T], n: int)
      {.codegenDecl: "__attribute__((target(\"sse4.2\"))) $# $#$#".} =
    sortNetwork(T, data, n, true)

  proc cSortCore[T: int32 | int64](data: ptr UncheckedArray[T], n: int) =
    if n < 2: return
    if cpuHasSse42(): cSortSse42(data, n)
    else: cSortScalar(data, n)
else:
  proc cSortCore[T: int32 | int64](data: ptr UncheckedArray[T], n: int) =
    if n < 2: return
    sortNetwork(T, data, n, HasSimd)

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
