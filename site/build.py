#!/usr/bin/env python3

import argparse
import os
import pathlib
from pathlib import Path
import re
import sys
import shutil
import subprocess

import basswood
import paletdoc
from paletdoc import proc, text, value, syntax, code

sys.path.insert(0, '/Users/wyattblue/projects/auto-editor')

import auto_editor
import auto_editor.vanparse as vanparse
from auto_editor.__main__ import main_options
from auto_editor.vanparse import OptionText

parser = argparse.ArgumentParser()
parser.add_argument("--production", "-p", action="store_true")
args = parser.parse_args()

SECRET = "secret" if os.getenv("AE_SECRET") is None else os.getenv("AE_SECRET")


def get_link_name(item: str) -> str:
    root, ext = os.path.splitext(item)

    _os = "Windows"
    if ext == ".dmg":
        _os = "MacOS"
    if ext == ".7z":
        _os = "Arch-Based"
    if ext == ".deb":
        _os = "Debian"

    version = re.search(r"[0-9]\.[0-9]\.[0-9]", root).group()

    return f"{version} {_os} Download"


parser = vanparse.ArgumentParser("Auto-Editor")
parser = main_options(parser)

ref = Path(f"src/ref/{auto_editor.version}")
ref.mkdir(parents=True, exist_ok=True)

with open(ref / "options.html", "w") as file:
    file.write(
        '{{ comp.header "Options" }}\n'
        "<body>\n"
        "{{ comp.nav }}\n"
        '<section class="section">\n'
        '<div class="container">\n'
    )
    for op in parser.args:
        if isinstance(op, OptionText):
            file.write(f"<h2>{op.text}</h2>\n")
        else:
            file.write(f"<h3><code>{op.names[0]}</code></h3>\n")
            if len(op.names) > 1:
                file.write(
                    "<h4><code>"
                    + "</code> <code>".join(op.names[1:])
                    + "</code></h4>\n"
                )

            file.write(f"<p>{op.help}</p>\n")

    file.write("</div>\n</section>\n</body>\n</html>\n\n")


with open(ref / "palet.html", 'w') as file:
    file.write(
        '{{ comp.header "Palet Scripting Reference" }}\n'
        "<body>\n"
        "{{ comp.nav }}\n"
        '<section class="section">\n'
        '<div class="container">\n'
        '<h1>Palet Scripting Reference</h1>\n'
        '<p>This manual describes the complete overview of the palet scripting language.'
        "<p>Palet is an anagram-acronym of the words: "
        "(A)uto-(E)ditor's (T)iny (P)rocedural (L)anguage</p>"
    )

    def text_to_str(t: text) -> str:
        s = ""
        for c in t.children:
            s += f"<code>{c.child}</code>" if isinstance(c, code) else c
        return s



    for category, somethings in paletdoc.doc.items():
        file.write(f'<h2 class="left">{category}</h2>\n')
        for some in somethings:
            if isinstance(some, syntax):
                file.write(
                    f'<div class="palet-block"><p id="{some.name}" class="mono">\n'
                    f'(<b>{some.name}</b>&nbsp;{some.body})</p>\n</div>\n'
                    f"<p>{text_to_str(some.summary)}</p>\n"
                )
            if isinstance(some, proc):
                rname = some.sig[1]
                file.write(
                    f'<div class="palet-block">\n'
                    f'<p id="{some.name}" class="mono">(<b>{some.name}</b>&nbsp;{"&nbsp;".join(some.sig[0])})'
                    f'&nbsp;→&nbsp;<a href="#{rname}">{rname}</a></p>\n'

                )
                for argsig in some.argsig:
                    if len(argsig) == 2:
                        var, sig = argsig
                        file.write(
                            f'<p class="mono">&nbsp;{var}&nbsp;:&nbsp;<a href="#{sig}">{sig}</a></p>\n'
                        )
                    else:
                        var, sig, default = argsig
                        file.write(
                            f'<p class="mono">&nbsp;{var}&nbsp;:&nbsp;<a href="#{sig}">{sig}</a>&nbsp;=&nbsp;{default}</p>\n'
                        )

                file.write(
                    '</div>\n'
                    f"<p>{text_to_str(some.summary)}</p>\n"
                )
            if isinstance(some, value):
                file.write(
                    f'<div class="palet-block">\n<p class="mono">{some.name}'
                    f'&nbsp;:&nbsp;<a href="#{some.sig}">{some.sig}</a></p>\n</div>\n'
                    f"<p>{text_to_str(some.summary)}</p>\n"
                )



if os.path.exists("binaries"):
    with open(f"./src/{SECRET}/more.html", "w") as file:
        file.write(
            '{{ comp.header "More Downloads" }}\n'
            "<body>\n"
            "{{ comp.app_nav }}\n"
            '<section class="section">\n'
            '<div class="container">\n'
            '<h1 class="bigger">More Downloads</h1>\n'
        )
        for item in sorted(os.listdir("binaries")):
            if os.path.splitext(item)[1] in (".dmg", ".zip", ".7z", ".deb"):
                file.write(f'<p><a href="./{item}">{get_link_name(item)}</a></p>\n')

        file.write("</div>\n</section>\n</body>\n</html>\n\n")

site = basswood.Site(source="src", output_dir="auto-editor")
site.production = args.production
site.make()

if args.production:
    SECRET2 = os.getenv("AE_SECRET2")
    assert SECRET2 is not None
    subprocess.run(["rsync", "-rtvzP", "binaries/", SECRET2])
    subprocess.run(
        ["rsync", "-rtvzP", "auto-editor/", "root@auto-editor.com:/var/www/auto-editor"]
    )
else:
    site.serve(port=8080)

print("Removing auto-generated files.")
try:
    shutil.rmtree("./auto-editor")
except FileNotFoundError:
    pass

os.remove(f"./src/{SECRET}/more.html")
