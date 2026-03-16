#!/usr/bin/env -S nim e --hints:off
mode = ScriptMode.Silent

# For: docs/src/ref/options.md

import std/[strutils, sequtils]
import ../src/[about, cli]

func toMarkdown(v: string): string =
  v.replace("[Deprecated]", "\\[Deprecated\\]").replace("--", "\\--").replace("\n", "\n\n")

func primaryName(names: string): string =
  return names.split(", ")[^1].strip()

proc aliasNames(names: string): seq[string] =
  let primary = primaryName(names)
  for part in names.split(", "):
    let n = part.strip()
    if n != primary:
      result.add(n)

proc renderOpt(opt: OptDef): string =
  if opt.kind == Special: return ""
  if opt.c == cNone: return ""

  let pname = primaryName(opt.names)
  let alts = aliasNames(opt.names)
  let help = opt.help.strip()

  if opt.metavar != "":
    result.add "### `" & pname & " " & opt.metavar & "`\n"
  else:
    result.add "### `" & pname & "`\n"

  if alts.len > 0:
    result.add "#### Aliases:"
    for a in alts:
      result.add " `" & a & "`"
    result.add "\n\n"

  if help != "":
    result.add help.toMarkdown & "\n\n"

const catOrder = [cEdit, cTl, cUrl, cDis, cCon, cVid, cAud, cMis]

var output = "---\ntitle: Options\n---\n\n"

for cat in catOrder:
  var section = ""
  for opt in mainOptions:
    if opt.c == cat:
      section.add renderOpt(opt)
  if section != "":
    output.add "## " & categoryName(cat) & ":\n\n"
    output.add section

output.add "---\n"
output.add "Version " & $about.version & "<br>Generated: " & gorge("date +%Y-%m-%d") & "."
echo output
