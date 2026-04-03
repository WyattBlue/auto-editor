import std/terminal

when defined(wasmBuild):
  proc terminalWidth*(): int = 80
else:
  let terminalWidth* = terminalWidth

export ForegroundColor, BackgroundColor, TerminalCmd, styledWriteLine, isatty
