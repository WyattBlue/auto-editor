import std/[strformat, strutils]
import ../[cli, log]


proc main*(args: seq[string]) =
  var expecting: string = ""
  var shell = ""
  for key in args:
    case key:
    of "--help":
      echo """usage: [options]

Options:
  -s, --shell       Shell type: {zsh}
"""
      quit(0)
    of "-s", "--shell":
      expecting = "shell"
    else:
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
