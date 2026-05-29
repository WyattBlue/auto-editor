import std/[algorithm, options, os, streams, strformat, strutils, times]

import ./[about, ffmpeg, log]
import ./util/[fun, rational, dnorm16]

import nimcrypto/sha

type CacheCodec = enum
  ccFloat32 = 0'u8  # raw float32
  ccUnorm16 = 1'u8  # [0.0, 1.0]
  ccSnorm16 = 2'u8  # [-1.0, 1.0]

func codecFor(kind: string): CacheCodec =
  case kind
  of "audio", "motion": ccUnorm16
  of "waveform": ccSnorm16
  else: ccFloat32

proc procTag(path: string, tb: AVRational, kind, args: string): string =
  let modTime = getLastModificationTime(path).toUnix().int
  let (_, name, ext) = agSplitFile(path)
  let key = &"{name}{ext}:{modTime:x}:{tb}:{args}"
  var ctx: sha1
  ctx.init()
  ctx.update(key)
  return ($ctx.finish())[0..<16].toLowerAscii() & kind

proc saveFloats(filename: string, data: seq[float32], codec: CacheCodec) =
  let fs = newFileStream(filename, fmWrite)
  defer: fs.close()

  fs.write(uint8(codec))
  fs.write(data.len.int32)
  case codec
  of ccFloat32:
    for v in data: fs.write(v)
  of ccUnorm16:
    for v in data: fs.write(uint16(toUnorm16(v)))
  of ccSnorm16:
    for v in data: fs.write(int16(toSnorm16(v)))

proc loadFloats(filename: string): seq[float32] =
  let fs = newFileStream(filename, fmRead)
  if fs == nil:
    raise newException(IOError, "")
  defer: fs.close()

  let codec = fs.readUint8()
  let length = fs.readInt32()
  result = newSeq[float32](length)
  case codec
  of uint8(ccFloat32):
    for i in 0..<length: result[i] = fs.readFloat32()
  of uint8(ccUnorm16):
    for i in 0..<length: result[i] = toFloat32(Unorm16(fs.readUint16()))
  of uint8(ccSnorm16):
    for i in 0..<length: result[i] = toFloat32(Snorm16(fs.readInt16()))
  else:
    raise newException(IOError, "unknown cache codec")

proc readCache*(path: string, tb: AVRational, kind, args: string): Option[seq[float32]] =
  let temp: string = getTempDir()
  let cacheFile = temp / &"ae-{version}" / &"{procTag(path, tb, kind, args)}.bin"
  try:
    return some(loadFloats(cacheFile))
  except Exception:
    return none(seq[float32])

type CacheEntry = tuple[path: string, mtime: Time]

const cacheFileLimit = 255

proc writeCache*(data: seq[float32], tb: AVRational, path, kind, args: string) =
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
    saveFloats(cacheFile, data, codecFor(kind))
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
  if cacheEntries.len > cacheFileLimit:
    cacheEntries.sort(proc(a, b: CacheEntry): int = cmp(a.mtime, b.mtime))

    # Remove oldest files until we're back to the limit
    for i in 0 ..< cacheEntries.len - cacheFileLimit:
      try:
        removeFile cacheEntries[i].path
      except OSError:
        discard
