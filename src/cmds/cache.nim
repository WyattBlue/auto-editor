import std/[os, strformat, strutils, terminal]

import ../[about, cli, log]
import ../util/fun
import ./help

func formatBytes(intSize: BiggestInt): (string, string) =
  if intSize < 1024:
    return ($intSize, "B")
  var size = intSize.float / 1024.0
  for unit in ["KiB", "MiB", "GiB", "TiB"]:
    if size < 1024.0:
      return (&"{size:.2f}", unit)
    size = size / 1024.0
  return (&"{size:.2f}", "PiB")


proc main*(args: seq[string]) =
  var positionals: seq[string] = @[]
  for key in args:
    if genCliMacro(key, args, cacheOptions):
      continue
    if key in ["-h", "--help"]:
      printHelp("[clean | clear]", cacheOptions)
    if key.startsWith("-"):
      error "Unknown option: " & key
    positionals.add key

  let cacheDir = getTempDir() / &"ae-{version}"

  if positionals.len > 0 and positionals[0] in ["clean", "clear"]:
    try: removeDir cacheDir
    except: discard
    return

  var totalSize: BiggestInt = 0
  try:
    for (kind, path) in walkDir(cacheDir):
      if kind == pcFile:
        let (_, key, ext) = agSplitFile(path)
        # Only .bin files with the 16-char hash prefix are cache entries.
        if ext != ".bin" or key.len < 16:
          continue
        let size = getFileSize(path)
        totalSize += size
        let (sizeNum, sizeUnit) = formatBytes(size)

        let hashPart = key[0 ..< 16]
        let restPart = key[16 .. ^1]

        stdout.styledWrite(fgYellow, "entry: ")
        stdout.write "\e[90m", hashPart, "\e[0m"
        stdout.styledWriteLine(restPart, "  ", fgYellow, "size: ", fgGreen, sizeNum,
            fgBlue, sizeUnit, resetStyle)
  except:
    discard

  if totalSize == 0:
    echo "Empty cache"
    return

  let (totalNum, totalUnit) = formatBytes(totalSize)

  stdout.styledWriteLine("\n", fgYellow, "total cache size: ", fgGreen, totalNum,
      fgBlue, totalUnit, resetStyle)
