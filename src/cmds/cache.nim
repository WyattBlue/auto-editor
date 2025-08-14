import std/os
import std/terminal
import std/strformat

import ../about

func formatBytes(size: var float): (string, string) =
  for unit in ["B", "KiB", "MiB", "GiB", "TiB"]:
    if size < 1024.0:
      return (fmt"{size:.2f}", unit)
    size = size / 1024.0
  return (fmt"{size:.2f}", "PiB")


proc main*(args: seq[string]) =
  let cacheDir = getTempDir() / fmt"ae-{version}"

  if args.len > 0 and args[0] in ["clean", "clear"]:
    try:
      removeDir cacheDir
    except:
      discard

    return

  var totalSize = 0.0
  try:
    for (kind, path) in walkDir(cacheDir):
      case kind
      of pcFile:
        var size = getFileSize(path).float
        totalSize += size
        let (sizeNum, sizeUnit) = formatBytes(size)

        let (_, key, _) = splitFile(path)
        let hashPart = key[0 ..< 16]
        let restPart = key[16 .. ^1]

        stdout.styledWrite(fgYellow, "entry: ")
        stdout.write "\e[90m", hashPart, "\e[0m"
        stdout.styledWriteLine(restPart, "  ", fgYellow, "size: ", fgGreen,
          sizeNum, " ", fgBlue, sizeUnit, resetStyle)

      else:
        discard
  except:
    discard

  if totalSize == 0.0:
    echo "Empty cache"
    return

  let (totalNum, totalUnit) = formatBytes(totalSize)

  stdout.styledWriteLine("\n", fgYellow, "total cache size: ", fgGreen,
      totalNum, " ", fgBlue, totalUnit, resetStyle)
