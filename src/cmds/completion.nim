import std/[strformat, strutils]
import ../[cli, log]
import ./help


proc main*(args: seq[string]) =
  var expecting = coNone
  var shell = ""
  for key in args:
    if genCliMacro(key, args, completionOptions):
      continue
    if key in ["-h", "--help"]:
      printHelp("[options]", completionOptions)
    if key.startsWith("-"):
      error &"Unknown option: {key}{optionDidYouMean(key, completionOptions)}"

    case expecting
    of coShell: shell = key
    of coNone: discard
    else: error &"Internal error: unexpected CLI option {expecting}"
    expecting = coNone

  case shell
  of "zsh":
    zshcomplete()
  of "":
    error "The value of `--shell` is required"
  else:
    error "Supported shell values: zsh"
