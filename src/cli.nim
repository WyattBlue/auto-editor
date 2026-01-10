import std/strutils

const commands*: seq[tuple[name: string, help: string]] = @[
  ("cache", ""),
  ("desc", "Display a media file's description metadata"),
  ("info", "Retrieve information and properties about media files"),
  ("levels", "Display loudness over time"),
  ("subdump", "Dump text-based subtitles to stdout with formatting stripped out"),
  ("whisper", "Transcribe audio with ggml models"),
]

proc zshcomplete*() =
  echo "#compdef auto-editor"
  echo ""
  echo "_auto-editor() {"
  echo "  local -a subcommands"
  echo "  subcommands=("
  for (command, help) in commands:
    if help != "":
      echo "    '" & command & ":" & help.replace("'", "'\\''") & "'"
    else:
      echo "    '" & command & "'"
  echo "  )"
  echo """
  if (( CURRENT == 2 )); then
    _describe 'command' subcommands
    _files
  else
    case "$words[2]" in
      cache)
        # No file completion for cache command
        ;;
      *)
        _files
        ;;
    esac
  fi
}

_auto-editor "$@"
"""
