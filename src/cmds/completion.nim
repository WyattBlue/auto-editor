import std/strutils
import ../[cli, log]
import ./help


const completionArgumentOptions = {coShell}

assertArgumentOptions(completionOptions, completionArgumentOptions)

proc main*(args: seq[string]) =
  var shell = ""
  parseArgs(args, completionOptions, "[options]", "-"):
    case expecting
    of coShell: shell = key
    of coNone: discard
    else: discard
    expecting = coNone

  case shell
  of "zsh":
    zshcomplete()
  of "":
    error "The value of `--shell` is required"
  else:
    error "Supported shell values: zsh"
