import std/[algorithm, options, os, streams, strformat, strutils, times]

import ./[about, ffmpeg, log]
import ./util/[fun, rational, dnorm16]

import nimcrypto/sha

type CacheCodec = enum
  ccFloat32 = 0'u8  # raw float32
  ccUnorm16 = 1'u8  # [0.0, 1.0]
  ccSnorm16 = 2'u8  # [-1.0, 1.0]

func codecOf(T: typedesc): CacheCodec =
  when T is Unorm16: ccUnorm16
  elif T is Snorm16: ccSnorm16
  elif T is float32: ccFloat32
  else: {.error: "cache: unsupported element type".}

proc procTag(path: AbsPath, tb: AVRational, kind, args: string): string =
  let info = getFileInfo($path)
  let mtime = info.lastWriteTime
  let key = &"{$path}:{mtime.toUnix():x}.{mtime.nanosecond:x}:" &
    &"{info.size:x}:{tb}:{args}"
  var ctx: sha1
  ctx.init()
  ctx.update(key)
  return ($ctx.finish())[0..<16].toLowerAscii() & kind

# Levels are cached in their in-memory form (Unorm16 / Snorm16 / float32) and
# blasted to/from disk in bulk. A leading codec byte makes each file self-
# describing, so a type mismatch or stale format fails to decode and the data
# is simply recomputed rather than misread.
proc saveCache[T](filename: string, data: seq[T]) =
  let fs = newFileStream(filename, fmWrite)
  defer: fs.close()

  fs.write(uint8(codecOf(T)))
  fs.write(data.len.int32)
  if data.len > 0:
    fs.writeData(unsafeAddr data[0], data.len * sizeof(T))

proc loadCache[T](filename: string): seq[T] =
  var f: File
  if not open(f, filename):
    raise newException(IOError, "")
  defer: f.close()

  var header {.noinit.}: array[5, byte] # codec byte + int32 length
  if f.readBuffer(addr header[0], 5) != 5:
    raise newException(IOError, "cache truncated")
  if header[0] != uint8(codecOf(T)):
    raise newException(IOError, "cache codec mismatch")
  var length32: int32
  copyMem(addr length32, addr header[1], 4)
  let length = length32.int
  # Untrusted length: newSeq on a corrupt value is an uncatchable RangeDefect
  # or a giant allocation.
  if length < 0 or length.int64 * sizeof(T) != f.getFileSize() - 5:
    raise newException(IOError, "cache length corrupt")
  result = newSeq[T](length)
  if length > 0:
    let want = length * sizeof(T)
    if f.readBuffer(addr result[0], want) != want:
      raise newException(IOError, "cache truncated")

# Non-generic so `version` (referenced via the `&` macro) binds; it won't
# inside a generic proc body.
proc cacheDir(): string = getTempDir() / &"ae-{version}"
proc cacheFilePath(path: AbsPath, tb: AVRational, kind, args: string): string =
  cacheDir() / &"{procTag(path, tb, kind, args)}.bin"

proc readCache*[T](path: string, tb: AVRational, kind, args: string): Option[seq[T]] =
  try:
    return some(loadCache[T](cacheFilePath(path.absPath, tb, kind, args)))
  except Exception:
    return none(seq[T])

type CacheEntry = tuple[path: string, mtime: Time]

const cacheFileLimit = 255

# Evict the oldest cache files once the directory exceeds the limit. Kept
# non-generic so its `cmp`/`sort`/`walkDir` calls bind at definition.
proc pruneCache(workdir: string) =
  var cacheEntries: seq[CacheEntry] = @[]

  try:
    for entry in walkDir(workdir):
      if entry.kind == pcFile and entry.path.endsWith(".bin"):
        let info = getFileInfo(entry.path)
        cacheEntries.add((entry.path, info.lastWriteTime))
  except OSError:
    discard

  # Sort by modification time (oldest first) and remove excess files
  if cacheEntries.len > cacheFileLimit:
    cacheEntries.sort(proc(a, b: CacheEntry): int = cmp(a.mtime, b.mtime))

    # Remove oldest files until we're back to the limit
    for i in 0 ..< cacheEntries.len - cacheFileLimit:
      try:
        removeFile cacheEntries[i].path
      except OSError:
        discard

proc writeCache*[T](data: seq[T], tb: AVRational, path, kind, args: string) =
  if data.len <= 10:
    return

  let workdir = cacheDir()
  try:
    createDir(workdir)
  except OSError:
    discard

  try:
    saveCache(cacheFilePath(path.absPath, tb, kind, args), data)
  except Exception as e:
    error &"Cache write failed: {e.msg}"

  pruneCache(workdir)
