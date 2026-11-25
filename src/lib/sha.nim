## SHA-1 and SHA-512, ported from nimcrypto 0.7.3's portable code: the cache
## names its files with SHA-1, and ed25519 hashes with SHA-512.
##
## NimCrypto (c) Copyright 2016-2025 Eugene Kabanov, MIT License:
##
## Permission is hereby granted, free of charge, to any person obtaining a copy
## of this software and associated documentation files (the "Software"), to deal
## in the Software without restriction, including without limitation the rights
## to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
## copies of the Software, and to permit persons to whom the Software is
## furnished to do so, subject to the following conditions:
##
## The above copyright notice and this permission notice shall be included in
## all copies or substantial portions of the Software.
##
## THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
## IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
## FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
## AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
## LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
## OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
## THE SOFTWARE.

type
  Sha1* = object
    size: uint64
    h: array[5, uint32]
    buf: array[64, byte]
  Sha512* = object
    size: uint64
    h: array[8, uint64]
    buf: array[128, byte]
  Block = ptr UncheckedArray[byte]

const k512 = [
  0x428a2f98d728ae22'u64, 0x7137449123ef65cd'u64, 0xb5c0fbcfec4d3b2f'u64,
  0xe9b5dba58189dbbc'u64, 0x3956c25bf348b538'u64, 0x59f111f1b605d019'u64,
  0x923f82a4af194f9b'u64, 0xab1c5ed5da6d8118'u64, 0xd807aa98a3030242'u64,
  0x12835b0145706fbe'u64, 0x243185be4ee4b28c'u64, 0x550c7dc3d5ffb4e2'u64,
  0x72be5d74f27b896f'u64, 0x80deb1fe3b1696b1'u64, 0x9bdc06a725c71235'u64,
  0xc19bf174cf692694'u64, 0xe49b69c19ef14ad2'u64, 0xefbe4786384f25e3'u64,
  0x0fc19dc68b8cd5b5'u64, 0x240ca1cc77ac9c65'u64, 0x2de92c6f592b0275'u64,
  0x4a7484aa6ea6e483'u64, 0x5cb0a9dcbd41fbd4'u64, 0x76f988da831153b5'u64,
  0x983e5152ee66dfab'u64, 0xa831c66d2db43210'u64, 0xb00327c898fb213f'u64,
  0xbf597fc7beef0ee4'u64, 0xc6e00bf33da88fc2'u64, 0xd5a79147930aa725'u64,
  0x06ca6351e003826f'u64, 0x142929670a0e6e70'u64, 0x27b70a8546d22ffc'u64,
  0x2e1b21385c26c926'u64, 0x4d2c6dfc5ac42aed'u64, 0x53380d139d95b3df'u64,
  0x650a73548baf63de'u64, 0x766a0abb3c77b2a8'u64, 0x81c2c92e47edaee6'u64,
  0x92722c851482353b'u64, 0xa2bfe8a14cf10364'u64, 0xa81a664bbc423001'u64,
  0xc24b8b70d0f89791'u64, 0xc76c51a30654be30'u64, 0xd192e819d6ef5218'u64,
  0xd69906245565a910'u64, 0xf40e35855771202a'u64, 0x106aa07032bbd1b8'u64,
  0x19a4c116b8d2d0c8'u64, 0x1e376c085141ab53'u64, 0x2748774cdf8eeb99'u64,
  0x34b0bcb5e19b48a8'u64, 0x391c0cb3c5c95a63'u64, 0x4ed8aa4ae3418acb'u64,
  0x5b9cca4f7763e373'u64, 0x682e6ff3d6b2b8a3'u64, 0x748f82ee5defb2fc'u64,
  0x78a5636f43172f60'u64, 0x84c87814a1f0ab72'u64, 0x8cc702081a6439ec'u64,
  0x90befffa23631e28'u64, 0xa4506cebde82bde9'u64, 0xbef9a3f7b2c67915'u64,
  0xc67178f2e372532b'u64, 0xca273eceea26619c'u64, 0xd186b8c721c0c207'u64,
  0xeada7dd6cde0eb1e'u64, 0xf57d4f7fee6ed178'u64, 0x06f067aa72176fba'u64,
  0x0a637dc5a2c898a6'u64, 0x113f9804bef90dae'u64, 0x1b710b35131c471b'u64,
  0x28db77f523047d84'u64, 0x32caab7b40c72493'u64, 0x3c9ebe0a15c9bebc'u64,
  0x431d67c49c100d4c'u64, 0x4cc5d4becb3e42b6'u64, 0x597f299cfc657e2a'u64,
  0x5fcb6fab3ad6faec'u64, 0x6c44198c4a475817'u64]
const k1 = [0x5A827999'u32, 0x6ED9EBA1'u32, 0x8F1BBCDC'u32, 0xCA62C1D6'u32]

func rol(x: uint32, n: int): uint32 {.inline.} = (x shl n) or (x shr (32 - n))
func ror(x: uint64, n: int): uint64 {.inline.} = (x shr n) or (x shl (64 - n))

func be32(b: Block, i: int): uint32 {.inline.} =
  (uint32(b[i]) shl 24) or (uint32(b[i + 1]) shl 16) or (uint32(b[i + 2]) shl 8) or
    uint32(b[i + 3])

func be64(b: Block, i: int): uint64 {.inline.} =
  (uint64(be32(b, i)) shl 32) or uint64(be32(b, i + 4))

func compress(ctx: var Sha1, b: Block) =
  var w {.noinit.}: array[80, uint32]
  for t in 0 ..< 16: w[t] = be32(b, 4 * t)
  for t in 16 ..< 80: w[t] = rol(w[t - 3] xor w[t - 8] xor w[t - 14] xor w[t - 16], 1)
  var (a, b, c, d, e) = (ctx.h[0], ctx.h[1], ctx.h[2], ctx.h[3], ctx.h[4])
  for t in 0 ..< 80:
    let f =
      if t < 20: ((c xor d) and b) xor d
      elif t < 40 or t >= 60: b xor c xor d
      else: (b and c) + (d and (b xor c))
    let tmp = rol(a, 5) + f + e + k1[t div 20] + w[t]
    (e, d, c, b, a) = (d, c, rol(b, 30), a, tmp)
  ctx.h[0] += a
  ctx.h[1] += b
  ctx.h[2] += c
  ctx.h[3] += d
  ctx.h[4] += e

func compress(ctx: var Sha512, b: Block) =
  var w {.noinit.}: array[80, uint64]
  for t in 0 ..< 16: w[t] = be64(b, 8 * t)
  for t in 16 ..< 80:
    let s0 = ror(w[t - 15], 1) xor ror(w[t - 15], 8) xor (w[t - 15] shr 7)
    let s1 = ror(w[t - 2], 19) xor ror(w[t - 2], 61) xor (w[t - 2] shr 6)
    w[t] = s1 + w[t - 7] + s0 + w[t - 16]
  var (a, b, c, d, e, f, g, h) =
    (ctx.h[0], ctx.h[1], ctx.h[2], ctx.h[3], ctx.h[4], ctx.h[5], ctx.h[6], ctx.h[7])
  for t in 0 ..< 80:
    let t0 = h + (ror(e, 14) xor ror(e, 18) xor ror(e, 41)) +
      ((e and f) xor (not e and g)) + k512[t] + w[t]
    let t1 = (ror(a, 28) xor ror(a, 34) xor ror(a, 39)) +
      ((a and b) xor (a and c) xor (b and c))
    (h, g, f, e, d, c, b, a) = (g, f, e, d + t0, c, b, a, t0 + t1)
  ctx.h[0] += a
  ctx.h[1] += b
  ctx.h[2] += c
  ctx.h[3] += d
  ctx.h[4] += e
  ctx.h[5] += f
  ctx.h[6] += g
  ctx.h[7] += h

func initSha1*(): Sha1 =
  Sha1(h: [0x67452301'u32, 0xEFCDAB89'u32, 0x98BADCFE'u32, 0x10325476'u32,
    0xC3D2E1F0'u32])

func initSha512*(): Sha512 =
  Sha512(h: [0x6A09E667F3BCC908'u64, 0xBB67AE8584CAA73B'u64,
    0x3C6EF372FE94F82B'u64, 0xA54FF53A5F1D36F1'u64, 0x510E527FADE682D1'u64,
    0x9B05688C2B3E6C1F'u64, 0x1F83D9ABFB41BD6B'u64, 0x5BE0CD19137E2179'u64])

func update*[T: byte | char](ctx: var (Sha1 | Sha512), data: openArray[T]) =
  if data.len == 0: return
  const n = sizeof(ctx.buf)
  let p = cast[Block](addr data[0])
  let fill = int(ctx.size mod uint64(n))
  var i = 0
  ctx.size += uint64(data.len)
  if fill > 0:
    let take = min(n - fill, data.len)
    copyMem(addr ctx.buf[fill], addr p[0], take)
    i = take
    if fill + take < n: return
    ctx.compress(cast[Block](addr ctx.buf[0]))
  while data.len - i >= n:
    ctx.compress(cast[Block](addr p[i]))
    i += n
  if i < data.len:
    copyMem(addr ctx.buf[0], addr p[i], data.len - i)

func pad(ctx: var (Sha1 | Sha512)) =
  ## The 0x80 byte, zeros, then the bit length big-endian: 8 bytes for SHA-1,
  ## 16 for SHA-512, whose high half is zero at any size a uint64 counts.
  const n = sizeof(ctx.buf)
  const lenBytes = n div 8
  let bits = ctx.size shl 3
  ctx.update([0x80'u8])
  let zeros = default(array[n, byte])
  let fill = int(ctx.size mod uint64(n))
  let gap = (if fill <= n - lenBytes: n - lenBytes - fill else: 2 * n - lenBytes - fill)
  ctx.update(zeros.toOpenArray(0, gap - 1))
  var field: array[lenBytes, byte]
  for i in 0 ..< 8: field[lenBytes - 8 + i] = byte(bits shr (56 - 8 * i))
  ctx.update(field)

func finish*(ctx: var Sha1): array[20, byte] =
  ctx.pad()
  for i in 0 ..< 20: result[i] = byte(ctx.h[i div 4] shr (24 - 8 * (i mod 4)))

func finish*(ctx: var Sha512): array[64, byte] =
  ctx.pad()
  for i in 0 ..< 64: result[i] = byte(ctx.h[i div 8] shr (56 - 8 * (i mod 8)))
