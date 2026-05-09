#!/usr/bin/env -S nim e --hints:off
mode = ScriptMode.Silent

import std/strutils
import ../../src/[about, action]

func toMarkdown(v: string): string =
  v.replace("--", "\\--").replace("\n", "\n\n")

proc renderAction(a: ActionDef): string =
  if a.argSpec != "":
    result.add "### `" & a.name & ":<" & a.argSpec & ">`\n\n"
  else:
    result.add "### `" & a.name & "`\n\n"

  if a.range != "":
    result.add "**Range:** `" & a.range & "`\n\n"

  let help = a.help.strip()
  if help != "":
    result.add help.toMarkdown & "\n\n"

var output = ""
for a in actionDefs:
  output.add renderAction(a)

output.add "---\n"
output.add "Version " & $about.version & "<br>Generated: " & gorge("date +%Y-%m-%d") & "."
echo output
