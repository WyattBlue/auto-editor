#!/usr/bin/env python3

import re
import subprocess
import sys
from argparse import ArgumentParser
from os import getenv
from pathlib import Path
from shutil import rmtree

import basswood
import paletdoc
from paletdoc import code, proc, syntax, text, value, var, pred

sys.path.insert(0, "/Users/wyattblue/projects/auto-editor")

from auto_editor import version
import auto_editor.vanparse as vanparse
from auto_editor.__main__ import main_options
from auto_editor.vanparse import OptionText
from auto_editor.interpreter import env

argp = ArgumentParser()
argp.add_argument("--production", "-p", action="store_true")
args = argp.parse_args()

parser = vanparse.ArgumentParser("Auto-Editor")
parser = main_options(parser)

secret = Path("src") / getenv("AE_SECRET", "secret")
ref = Path("src") / "ref" / version
ref.mkdir(parents=True, exist_ok=True)


def get_link_name(item: Path) -> str:
    extname = {
        ".dmg": "MacOS",
        ".7z": "Arch-Based",
        ".deb": "Debian",
        ".exe": "Windows",
        ".zip": "Windows",
    }
    _os = extname.get(item.suffix)
    if _os is None:
        raise ValueError(f"Unknown suffix: {item.suffix}")

    version = re.search(r"[0-9]\.[0-9]\.[0-9]", item.stem).group()

    return f"{version} {_os} Download"


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


with open(ref / "palet.html", "w") as file:
    file.write(
        '{{ comp.header "Palet Scripting Reference" }}\n'
        "<body>\n"
        "{{ comp.nav }}\n"
        '<section class="section">\n'
        '<div class="container">\n'
        "<h1>Palet Scripting Reference</h1>\n"
        "<p>This manual describes the complete overview of the palet scripting language.</p>"
        "<p>Palet is an anagram-acronym of the words: "
        "(A)uto-(E)ditor's (T)iny (P)rocedural (L)anguage</p>"
    )

    def text_to_str(t: text) -> str:
        s = ""
        for c in t.children:
            if isinstance(c, code):
                s += f"<code>{c.val}</code>"
            elif isinstance(c, var):
                s += f'<span class="palet-var">{c.val}</span>'
            else:
                s += c
        return s

    def build_sig(vec: list[str]) -> str:
        results = [
            v if v == "..." else f'<span class="palet-var">{v}</span>' for v in vec
        ]
        return "&nbsp;".join(results)

    pt_vars = []
    for category, somethings in paletdoc.doc.items():
        file.write(f'<h2 class="left">{category}</h2>\n')
        for some in somethings:
            if isinstance(some, text):
                file.write(f"<p>{text_to_str(some)}</p>\n")
                continue

            pt_vars.append(some.name)
            if isinstance(some, value):
                file.write(
                    '<div class="palet-block">\n'
                    f'<p class="mono">{some.name}\n'
                    f'&nbsp;:&nbsp;<a href="#{some.sig}">{some.sig}</a>'
                    '&nbsp;&nbsp;Value</p>\n</div>\n'
                    f"<p>{text_to_str(some.summary)}</p>\n"
                )
            if isinstance(some, syntax):
                _body = build_sig(some.body.split(" "))
                file.write(
                    f'<div id="{some.name}" class="palet-block">\n'
                    f'<p class="mono">(<b>{some.name}</b>&nbsp;{_body})'
                    '&nbsp;&nbsp;Syntax</p>\n</div>\n'
                    f"<p>{text_to_str(some.summary)}</p>\n"
                )
            if isinstance(some, pred):
                file.write(
                    f'<div id="{some.name}" class="palet-block">\n'
                    f'<p class="mono">(<b>{some.name}</b>&nbsp;{build_sig(["v"])})'
                    '&nbsp;→&nbsp;<a href="#bool?">bool?</a>&nbsp;&nbsp;Procedure</p>\n'
                    f'<p class="mono">&nbsp;<span class="palet-var">v</span>'
                    '&nbsp;:&nbsp;<a href="#any?">any?</a></p></div>\n'
                    f"<p>{text_to_str(some.summary)}</p>\n"
                )
            if isinstance(some, proc):
                rname = some.sig[1]
                file.write(
                    f'<div id="{some.name}" class="palet-block">\n'
                    f'<p class="mono">(<b>{some.name}</b>&nbsp;{build_sig(some.sig[0])})'
                    + (
                        ""
                        if rname == "none"
                        else f'&nbsp;→&nbsp;<a href="#{rname}">{rname}</a>'
                    )
                    + '&nbsp;&nbsp;Procedure</p>\n'
                )
                for argsig in some.argsig:
                    name = argsig[0]
                    sig = argsig[1]
                    default = argsig[2] if len(argsig) > 2 else None
                    file.write(
                        f'<p class="mono">&nbsp;<span class="palet-var">{name}</span>&nbsp;:&nbsp;<a href="#{sig}">{sig}</a>'
                        + (
                            "</p>\n"
                            if default is None
                            else f"&nbsp;=&nbsp;{default}</p>\n"
                        )
                    )

                file.write("</div>\n" f"<p>{text_to_str(some.summary)}</p>\n")


    for _var in pt_vars:
        if _var not in env:
            raise ValueError(f"{_var} not in env")

    for key in env:
        if key not in pt_vars:
            print(f"missing docs for {key}")


binaries = Path("binaries")
if binaries.exists():
    with open(secret / "more.html", "w") as file:
        file.write(
            '{{ comp.header "More Downloads" }}\n'
            "<body>\n"
            "{{ comp.app_nav }}\n"
            '<section class="section">\n'
            '<div class="container">\n'
            '<h1 class="bigger">More Downloads</h1>\n'
        )
        for item in sorted([x for x in binaries.iterdir() if x.is_file()]):
            if item.suffix in (".dmg", ".zip", ".7z", ".deb"):
                file.write(
                    f'<p><a href="./{item.parts[-1]}">{get_link_name(item)}</a></p>\n'
                )

        file.write("</div>\n</section>\n</body>\n</html>\n\n")

ref = Path("src/ref")
if ref.exists():
    with open(ref / "index.html", "w") as file:
        file.write(
            '{{ comp.header "Reference" }}\n'
            "<body>\n"
            "{{ comp.nav }}\n"
            '<section class="section">\n'
            '<div class="container">\n'
            '<h2 class="left">Reference</h2>\n'
            '<hr>\n'
        )
        for child in sorted(ref.iterdir(), reverse=True):
            if child.is_dir():
                file.write(f'<h3><a href="./{child.stem}">{child.stem}</a></h3>\n')
                file.write(
                    "<ul>\n"
                    f'<li><a href="./{child.stem}/options.html">options</a></li>\n'
                    f'<li><a href="./{child.stem}/palet.html">palet</a></li>\n'
                    "</ul>\n"
                )
                with open(child / "index.html", "w") as innerfile:
                    innerfile.write(
                        '{{ comp.header "' + child.stem + ' - Reference" }}\n'
                        "<body>\n"
                        "{{ comp.nav }}\n"
                        '<section class="section">\n'
                        '<div class="container">\n'
                        f'<h2 class="left">{child.stem} Reference</h2>\n'
                    )
                    if not child.stem.endswith("dev"):
                        innerfile.write(
                            '<p><a href="https://github.com/WyattBlue/auto-editor/'
                            f'releases/tag/{child.stem}">GitHub Release</a></p>\n'
                        )
                    innerfile.write(
                        '<hr>\n'
                        '<h3><a href="./options.html">options</a></h3>\n'
                        '<h3><a href="./palet.html">palet</a></h3>\n'
                        "</div>\n</section>\n</body>\n</html>\n\n"
                    )

        file.write('<br><p>See also: <a href="../docs">docs</a></p>\n')
        file.write("</div>\n</section>\n</body>\n</html>\n\n")


site = basswood.Site(args.production, source="src", output_dir="auto-editor")
site.make()

if args.production:
    SECRET2 = getenv("AE_SECRET2")
    assert SECRET2 is not None
    subprocess.run(["rsync", "-rtvzP", "binaries/", SECRET2])
    subprocess.run(
        ["rsync", "-rtvzP", "auto-editor/", "root@auto-editor.com:/var/www/auto-editor"]
    )
else:
    site.serve(port=8080)

print("removing auto-generated files")
try:
    rmtree("./auto-editor")
except FileNotFoundError:
    pass

(secret / "more.html").unlink(missing_ok=True)
print("done")
