import std/terminal

when defined(emscripten):
  {.emit: "#include <emscripten.h>".}
  proc terminalWidth*(): int = 80
  proc wasmProgressWrite*(text: cstring) =
    {.emit: """EM_ASM({ out(UTF8ToString($0) + '\r'); }, `text`);""".}
else:
  let terminalWidth* = terminalWidth

export ForegroundColor, BackgroundColor, TerminalCmd, styledWriteLine, isatty
