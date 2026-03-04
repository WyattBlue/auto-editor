import std/[algorithm, options, os, streams, strformat, strutils, times]
import about
import ffmpeg
import log

# macOS's ld appears to remove more deadcode when this linker is placed here.
{.passL: "-lcrypto".}

const Sha1DigestSize = 20

type
  Sha1Digest = array[0 .. Sha1DigestSize - 1, uint8]
  SecureHash = distinct Sha1Digest

proc SHA1(d: ptr uint8, n: csize_t, md: ptr uint8): ptr uint8
  {.importc: "SHA1", header: "<openssl/sha.h>".}

proc secureHash(str: openArray[char]): SecureHash =
  var digest: Sha1Digest
  discard SHA1(cast[ptr uint8](unsafeAddr str[0]), csize_t(str.len), addr digest[0])
  SecureHash(digest)

proc `$`*(self: SecureHash): string =
  result = ""
  for v in Sha1Digest(self):
    result.add(toHex(int(v), 2))

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
  if cacheEntries.len > cacheFileLimit:
    cacheEntries.sort(proc(a, b: CacheEntry): int = cmp(a.mtime, b.mtime))

    # Remove oldest files until we're back to the limit
    for i in 0 ..< cacheEntries.len - cacheFileLimit:
      try:
        removeFile cacheEntries[i].path
      except OSError:
        discard
