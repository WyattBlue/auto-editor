import std/[strformat, strutils]
import ../[cli, log]
import ./help


proc main*(args: seq[string]) =
  var expecting: string = ""
  var shell = ""
  for key in args:
    if genCliMacro(key, args, completionOptions):
      continue
    if key in ["-h", "--help"]:
      printHelp("[options]", completionOptions)
    if key.startsWith("-"):
      error &"Unknown option: {key}"

    case expecting
    of "shell": shell = key
    expecting = ""

  case shell
  of "zsh":
    zshcomplete()
  of "":
    error "The value of `--shell` is required"
  else:
    error "Supported shell values: zsh"
