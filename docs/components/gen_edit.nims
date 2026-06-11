#!/usr/bin/env -S nim e --hints:off
mode = ScriptMode.Silent

import std/[strformat, strutils]
import ../../src/editmethods

const ret = "BoolArray"

func htmlHelp(s: string): string =
  ## Render `name` (backtick-wrapped param refs) as edit-var spans.
  var inCode = false
  for c in s:
    if c == '`':
      result.add(if inCode: "</span>" else: "<span class=\"edit-var\">")
      inCode = not inCode
    else:
      result.add c

func sigArg(prm: EditParam): string =
  let label = if prm.default == "": prm.name else: "[" & prm.name & "]"
  &"<span class=\"edit-var\">{label}</span>"

func defaultVal(d: string): string =
  if d.startsWith("#") or d == "nil": &"<span class=\"edit-val\">{d}</span>"
  else: d

proc renderMethod(d: EditMethodDef): string =
  var sig = ""
  for name in d.names:
    sig.add &"(<b>{name}</b>"
    for prm in d.params:
      sig.add "&nbsp;" & sigArg(prm)
    sig.add &")&nbsp;→&nbsp;{ret}<br>"

  result.add &"<div id=\"{d.names[0]}\" class=\"edit-block\">\n"
  result.add &"<p class=\"mono\">{sig}</p>\n"
  for prm in d.params:
    var line = &"&nbsp;<span class=\"edit-var\">{prm.name}</span>:&nbsp;{prm.typ}"
    if prm.default != "":
      line.add &"&nbsp;=&nbsp;{defaultVal(prm.default)}"
    result.add &"<p class=\"mono\">{line}</p>\n"
  result.add "</div>\n"
  result.add &"<p>{htmlHelp(d.help)}</p>\n\n"

proc renderOperator(o: EditOperatorDef): string =
  var sig = &"(<b>{o.name}</b>&nbsp;<span class=\"edit-var\">operand</span>"
  if o.variadic:
    sig.add "&nbsp;<span class=\"edit-var\">...</span>"
  sig.add &")&nbsp;→&nbsp;{ret}"

  result.add &"<div id=\"{o.name}\" class=\"edit-block\">\n"
  result.add &"<p class=\"mono\">{sig}</p>\n"
  result.add &"<p class=\"mono\">&nbsp;<span class=\"edit-var\">operand</span>:&nbsp;{ret}</p>\n"
  result.add "</div>\n"
  result.add &"<p>{htmlHelp(o.help)}</p>\n\n"

var output = "<h2>Edit Methods</h2>\n"
for d in editMethodDefs:
  output.add renderMethod(d)

output.add "<h2>Operators</h2>\n"
for o in editOperatorDefs:
  output.add renderOperator(o)

echo output
