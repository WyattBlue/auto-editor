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

proc procTag(path: string, tb: AVRational, kind, args: string): string =
  let modTime = getLastModificationTime(path).toUnix().int
  let (_, name, ext) = agSplitFile(path)
  let key = &"{name}{ext}:{modTime:x}:{tb}:{args}"
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
  let fs = newFileStream(filename, fmRead)
  if fs == nil:
    raise newException(IOError, "")
  defer: fs.close()

  if fs.readUint8() != uint8(codecOf(T)):
    raise newException(IOError, "cache codec mismatch")
  let length = fs.readInt32().int
  result = newSeq[T](length)
  if length > 0:
    let want = length * sizeof(T)
    if fs.readData(addr result[0], want) != want:
      raise newException(IOError, "cache truncated")

# Non-generic so `version` (referenced via the `&` macro) binds; it won't
# inside a generic proc body.
proc cacheDir(): string = getTempDir() / &"ae-{version}"
proc cacheFilePath(path: string, tb: AVRational, kind, args: string): string =
  cacheDir() / &"{procTag(path, tb, kind, args)}.bin"

proc readCache*[T](path: string, tb: AVRational, kind, args: string): Option[seq[T]] =
  try:
    return some(loadCache[T](cacheFilePath(path, tb, kind, args)))
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
    saveCache(cacheFilePath(path, tb, kind, args), data)
  except Exception as e:
    error &"Cache write failed: {e.msg}"

  pruneCache(workdir)
