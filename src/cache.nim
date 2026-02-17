import std/[algorithm, options, os, streams, strformat, strutils, times]
from std/endians import bigEndian32, bigEndian64
import about
import ffmpeg
import log

# SHA-1 functions are vendored from `nim-lang/checksums` with modifications.
# Not used for security purposes, see: https://en.wikipedia.org/wiki/SHA-1

const Sha1DigestSize = 20

type
  Sha1Digest = array[0 .. Sha1DigestSize - 1, uint8]
  SecureHash = distinct Sha1Digest
  Sha1State = object
    count: int
    state: array[5, uint32]
    buf:   array[64, byte]

proc newSha1State(): Sha1State =
  result.count = 0
  result.state[0] = 0x67452301'u32
  result.state[1] = 0xEFCDAB89'u32
  result.state[2] = 0x98BADCFE'u32
  result.state[3] = 0x10325476'u32
  result.state[4] = 0xC3D2E1F0'u32

template ror27(val: uint32): uint32 = (val shr 27) or (val shl  5)
template ror2(val: uint32):  uint32 = (val shr  2) or (val shl 30)
template ror31(val: uint32): uint32 = (val shr 31) or (val shl  1)

proc transform(ctx: var Sha1State) =
  var w: array[80, uint32]
  var a, b, c, d, e: uint32
  var t = 0

  a = ctx.state[0]
  b = ctx.state[1]
  c = ctx.state[2]
  d = ctx.state[3]
  e = ctx.state[4]

  template shaF1(a, b, c, d, e, t: untyped) =
    bigEndian32(addr w[t], addr ctx.buf[t * 4])
    e += ror27(a) + w[t] + (d xor (b and (c xor d))) + 0x5A827999'u32
    b = ror2(b)

  while t < 15:
    shaF1(a, b, c, d, e, t + 0)
    shaF1(e, a, b, c, d, t + 1)
    shaF1(d, e, a, b, c, t + 2)
    shaF1(c, d, e, a, b, t + 3)
    shaF1(b, c, d, e, a, t + 4)
    t += 5
  shaF1(a, b, c, d, e, t + 0) # 16th one, t == 15

  template shaF11(a, b, c, d, e, t: untyped) =
    w[t] = ror31(w[t-3] xor w[t-8] xor w[t-14] xor w[t-16])
    e += ror27(a) + w[t] + (d xor (b and (c xor d))) + 0x5A827999'u32
    b = ror2(b)

  shaF11(e, a, b, c, d, t + 1)
  shaF11(d, e, a, b, c, t + 2)
  shaF11(c, d, e, a, b, t + 3)
  shaF11(b, c, d, e, a, t + 4)

  template shaF2(a, b, c, d, e, t: untyped) =
    w[t] = ror31(w[t-3] xor w[t-8] xor w[t-14] xor w[t-16])
    e += ror27(a) + w[t] + (b xor c xor d) + 0x6ED9EBA1'u32
    b = ror2(b)

  t = 20
  while t < 40:
    shaF2(a, b, c, d, e, t + 0)
    shaF2(e, a, b, c, d, t + 1)
    shaF2(d, e, a, b, c, t + 2)
    shaF2(c, d, e, a, b, t + 3)
    shaF2(b, c, d, e, a, t + 4)
    t += 5

  template shaF3(a, b, c, d, e, t: untyped) =
    w[t] = ror31(w[t-3] xor w[t-8] xor w[t-14] xor w[t-16])
    e += ror27(a) + w[t] + ((b and c) or (d and (b or c))) + 0x8F1BBCDC'u32
    b = ror2(b)

  while t < 60:
    shaF3(a, b, c, d, e, t + 0)
    shaF3(e, a, b, c, d, t + 1)
    shaF3(d, e, a, b, c, t + 2)
    shaF3(c, d, e, a, b, t + 3)
    shaF3(b, c, d, e, a, t + 4)
    t += 5

  template shaF4(a, b, c, d, e, t: untyped) =
    w[t] = ror31(w[t-3] xor w[t-8] xor w[t-14] xor w[t-16])
    e += ror27(a) + w[t] + (b xor c xor d) + 0xCA62C1D6'u32
    b = ror2(b)

  while t < 80:
    shaF4(a, b, c, d, e, t + 0)
    shaF4(e, a, b, c, d, t + 1)
    shaF4(d, e, a, b, c, t + 2)
    shaF4(c, d, e, a, b, t + 3)
    shaF4(b, c, d, e, a, t + 4)
    t += 5

  ctx.state[0] += a
  ctx.state[1] += b
  ctx.state[2] += c
  ctx.state[3] += d
  ctx.state[4] += e

proc update(ctx: var Sha1State, data: openArray[char]) =
  ## Updates the `Sha1State` with `data`.
  var i = ctx.count mod 64
  var j = 0
  var len = data.len
  # Gather 64-bytes worth of data in order to perform a round with the leftover
  # data we had stored (but not processed yet)
  if len > 64 - i:
    copyMem(addr ctx.buf[i], unsafeAddr data[j], 64 - i)
    len -= 64 - i
    j += 64 - i
    transform(ctx)
    # Update the index since it's used in the while loop below _and_ we want to
    # keep its value if this code path isn't executed
    i = 0
  # Process the bulk of the payload
  while len >= 64:
    copyMem(addr ctx.buf[0], unsafeAddr data[j], 64)
    len -= 64
    j += 64
    transform(ctx)
  # Process the tail of the payload (len is < 64)
  while len > 0:
    dec len
    ctx.buf[i] = byte(data[j])
    inc i
    inc j
    if i == 64:
      transform(ctx)
      i = 0
  ctx.count += data.len

proc finalize(ctx: var Sha1State): Sha1Digest =
  var cnt = uint64(ctx.count * 8)
  update(ctx, "\x80")
  while (ctx.count mod 64) != (64 - 8):
    update(ctx, "\x00")
  var tmp: array[8, char]
  bigEndian64(addr tmp[0], addr cnt)
  update(ctx, tmp)
  for i in 0 ..< 5:
    bigEndian32(addr ctx.state[i], addr ctx.state[i])
  copyMem(addr result[0], addr ctx.state[0], Sha1DigestSize)

proc secureHash(str: openArray[char]): SecureHash =
  var state = newSha1State()
  state.update(str)
  SecureHash(state.finalize())

proc `$`*(self: SecureHash): string =
  result = ""
  for v in Sha1Digest(self):
    result.add(toHex(int(v), 2))

## End SHA-1 functions

proc procTag(path: string, tb: AVRational, kind, args: string): string =
  let modTime = getLastModificationTime(path).toUnix().int
  let (_, name, ext) = splitFile(path)
  let key = &"{name}{ext}:{modTime:x}:{tb}:{args}"
  return ($secureHash(key))[0..<16].toLowerAscii() & kind

proc saveFloats(filename: string, data: seq[float32]) =
  let fs = newFileStream(filename, fmWrite)
  defer: fs.close()

  fs.write(data.len.int32)
  for value in data:
    fs.write(value)

proc loadFloats(filename: string): seq[float32] =
  let fs = newFileStream(filename, fmRead)
  if fs == nil:
    raise newException(IOError, "")
  defer: fs.close()

  let length = fs.readInt32()
  result = newSeq[float32](length)
  for i in 0..<length:
    result[i] = fs.readFloat32()

proc readCache*(path: string, tb: AVRational, kind, args: string): Option[seq[float32]] =
  let temp: string = getTempDir()
  let cacheFile = temp / &"ae-{version}" / &"{procTag(path, tb, kind, args)}.bin"
  try:
    return some(loadFloats(cacheFile))
  except Exception:
    return none(seq[float32])

type CacheEntry = tuple[path: string, mtime: Time]

proc writeCache*(data: seq[float32], path: string, tb: AVRational, kind,
    args: string) =
  if data.len <= 10:
    return

  let workdir = getTempDir() / &"ae-{version}"
  try:
    createDir(workdir)
  except OSError:
    discard

  let cacheTag = procTag(path, tb, kind, args)
  let cacheFile = workdir / &"{cacheTag}.bin"

  try:
    saveFloats(cacheFile, data)
  except Exception as e:
    error &"Cache write failed: {e.msg}"

  var cacheEntries: seq[CacheEntry] = @[]

  try:
    for entry in walkDir(workdir):
      if entry.kind == pcFile and entry.path.endsWith(".bin"):
        let info = getFileInfo(entry.path)
        cacheEntries.add((entry.path, info.lastWriteTime))
  except OSError:
    discard

  # Sort by modification time (oldest first) and remove excess files
  if cacheEntries.len > 10:
    cacheEntries.sort(proc(a, b: CacheEntry): int = cmp(a.mtime, b.mtime))

    # Remove oldest files until we're back to 10
    for i in 0 ..< (cacheEntries.len - 10):
      try:
        removeFile(cacheEntries[i].path)
      except OSError:
        discard
