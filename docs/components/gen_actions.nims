#!/usr/bin/env -S nim e --hints:off
mode = ScriptMode.Silent

import std/[strformat, strutils, options]
import ../../src/[about, action]

func toMarkdown(v: string): string =
  v.replace("--", "\\--").replace("\n", "\n\n")

func summary(help: string): string =
  ## Single-line first sentence, for the quick-reference table.
  let t = help.strip().replace("\n", " ")
  let idx = t.find(". ")
  let s = if idx >= 0: t[0 .. idx] else: t
  s.strip().replace("--", "\\--")

proc renderAction(a: ActionDef): string =
  if a.argSpec != "":
    result.add &"### **{a.name}**`:{a.argSpec}`\n\n"
  else:
    result.add &"### **{a.name}**\n\n"

  if a.range.isSome:
    result.add &"Range: `{a.range.get}`\n\n"

  let help = a.help.strip()
  if help != "":
    result.add help.toMarkdown & "\n\n"

proc renderTable(): string =
  result.add "<h2 id=\"quick-reference\" style=\"text-decoration:underline;\">Quick reference</h2>\n"
  result.add "<p>Type: A=audio, V=video, *=animatable.</p>\n\n"
  result.add "| Action | Arguments | Range | Type | Summary |\n"
  result.add "| --- | --- | --- | --- | --- |\n"
  for a in actionDefs:
    let args = if a.argSpec != "": "`" & a.argSpec & "`" else: "—"
    let rng = if a.range.isSome: $a.range.get else: "—"
    result.add &"| {a.name} | {args} | `{rng}` | `{a.flags}` | {a.help.summary} |\n"
  result.add "\n\n"

var output = ""
for a in actionDefs:
  output.add renderAction(a)

output.add renderTable()

output.add "---\n"
output.add &"Version {about.version}<br>Generated: " & gorge("date +%Y-%m-%d") & "."
echo output
