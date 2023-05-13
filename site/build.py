#!/usr/bin/env python3.11

import subprocess
import sys
from argparse import ArgumentParser
from os import getenv
from pathlib import Path
from shutil import rmtree
from copy import deepcopy

import basswood

sys.path.insert(0, "/Users/wyattblue/projects/auto-editor")

from auto_editor import version
import auto_editor.vanparse as vanparse
from auto_editor.__main__ import main_options
from auto_editor.vanparse import OptionText
from auto_editor.lang.palet import env, interpret, Parser, Lexer, Sym

argp = ArgumentParser()
argp.add_argument("--production", "-p", action="store_true")
args = argp.parse_args()

parser = vanparse.ArgumentParser("Auto-Editor")
parser = main_options(parser)

secret = Path("src") / getenv("AE_SECRET", "secret")
ref = Path("src") / "ref" / version
ref.mkdir(parents=True, exist_ok=True)


# Build blog posts
subprocess.run(["./blog_gen"])


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

    if _os == "MacOS":
        ver, arch = item.stem.replace("Auto-Editor-", "").split("-")
        return f"{ver} {_os} {arch} Download"

    ver, _, _ = item.stem.replace("Auto-Editor-", "").split("-")
    return f"{ver} {_os} Download"


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


palet_style = """
.palet-block {
 padding-left: 7px;
 padding-bottom: 7px;
 padding-top: 7px;
 margin-top: 30px;
 margin-bottom: 6px;
}
.palet-block > p {margin-top: 0; margin-bottom: 0}
.palet-var {font-style: italic}
.palet-val {color: #0B65B8; font-family: monospace;}

.palet-block { background-color: #F9F5F5; border-top: 3px solid #EAEAEA}
@media (prefers-color-scheme: dark) {
  .palet-block {background-color: #323232; border-top: 3px solid #4A4A4A}
  .palet-val {color: #A3DEFF}
}
"""

def san(s: str) -> str:
    return s.replace("&", "&amp;").replace("<", "&lt;").replace(">", "&gt;")


with open(ref / "palet.html", "w") as file:
    file.write(
        '{{ comp.header "Palet Scripting Reference" }}\n'
        f"<style>{palet_style}</style>\n"
        "<body>\n"
        "{{ comp.nav }}\n"
        '<section class="section">\n'
        '<div class="container">\n'
        "<h1>Palet Scripting Reference</h1>\n"
        "<p>This manual describes the complete overview of the palet scripting language.</p>"
        "<p>Palet is an anagram-acronym of the words: "
        "(A)uto-(E)ditor's (T)iny (P)rocedural (L)anguage</p>"
    )

    def text_to_str(t: dict) -> str:
        s = ""

        for c in t["children"]:
            if c is True:
                s += '<span class="palet-val">#t</span>'
            elif c is False:
                s += '<span class="palet-val">#f</span>'
            elif c is None:
                s += '<span class="palet-val">#&lt;void&gt;</span>'
            elif type(c) is Sym:
                s += f'<span class="palet-var">{san(c.val)}</span>'
            elif isinstance(c, str):
                s += san(c)
            elif c["tag"] == "link":
                p = san(c["val"])
                s += f'<a href="#{p}">{p}</a>'
            elif c["tag"] == "code":
                s += f"<code>{san(c['val'])}</code>"
            else:
                raise ValueError(c)

        return s


    def build_sig(vec: list[str | tuple]) -> str:
        results = []
        for v in vec:
            if v == "...":
                results.append(v)
                continue
            if len(v) == 3:
                results.append(f'<span class="palet-var">[{san(v[0])}]</span>')
            else:
                results.append(f'<span class="palet-var">{san(v[0])}</span>')
        return "&nbsp;".join(results)


    def build_var(v: str) -> str:
        result = ""
        for p in v.replace("(", " ( ").replace(")", " ) ").strip().split(" "):
            if p in env:
                result += f'<a href="#{p}">{san(p)}</a> '
            elif p == "(":
                result += "("
            elif p == ")":
                result = result[:-1] + ")"
            else:
                result += f"{san(p)} "
        return result.strip()

    def build_var_sig(sigs: list[str | tuple]) -> str:
        result = ""
        for s in sigs:
            if isinstance(s, str):
                if s == "...":
                    return result
                raise ValueError(f"bad signature: {sigs}")

            name, sig, *_ = s
            result += f'<p class="mono">&nbsp;<span class="palet-var">{san(name)}</span>'
            result += f'&nbsp;:&nbsp;{build_var(sig)}'

            result += f"&nbsp;=&nbsp;{build_var(s[2])}</p>\n" if len(s) > 2 else "</p>\n"
        return result

    pt_vars = []

    with open("paletdoc.pt", "r") as sourcefile:
        source = sourcefile.read()[:]

    canonical_env = deepcopy(env)
    result = interpret(env, Parser(Lexer("paletdoc.pt", source)))
    doc = env["doc"].copy()

    for category, somethings in doc.items():
        file.write(f'<h2 class="left">{category}</h2>\n')
        for some in somethings:
            if some["tag"] == "text":
                file.write(f"<p>{text_to_str(some)}</p>\n")
                continue

            pt_vars.append(some["name"])
            if some["tag"] == "value":
                file.write(
                    '<div class="palet-block">\n'
                    f'<p class="mono">{san(some["name"])}\n'
                    f'&nbsp;:&nbsp;<a href="#{some["sig"]}">{some["sig"]}</a>'
                    '&nbsp;&nbsp;Value</p>\n</div>\n'
                    f"<p>{text_to_str(some['summary'])}</p>\n"
                )
            if some["tag"] == "syntax":
                file.write(
                    f'<div id="{san(some["name"])}" class="palet-block">\n'
                    f'<p class="mono">(<b>{some["name"]}</b>&nbsp;{some["body"]})'
                    '&nbsp;&nbsp;Syntax</p>\n</div>\n'
                    f"<p>{text_to_str(some['summary'])}</p>\n"
                )
            if some["tag"] == "pred":
                file.write(
                    f'<div id="{some["name"]}" class="palet-block">\n'
                    f'<p class="mono">(<b>{san(some["name"])}</b>&nbsp;{build_sig(["v"])})'
                    '&nbsp;→&nbsp;<a href="#bool?">bool?</a>&nbsp;&nbsp;Procedure</p>\n'
                    f'<p class="mono">&nbsp;<span class="palet-var">v</span>'
                    '&nbsp;:&nbsp;<a href="#any?">any?</a></p></div>\n'
                    f"<p>{text_to_str(some['summary'])}</p>\n"
                )
            if some["tag"] == "proc":
                rname = some["sig"][-1]
                varsigs = some["sig"][:-1]
                assert isinstance(rname, str), rname
                file.write(
                    f'<div id="{some["name"]}" class="palet-block">\n'
                    f'<p class="mono">(<b>{san(some["name"])}</b>&nbsp;{build_sig(varsigs)})'
                    + ("" if rname == "none" else f'&nbsp;→&nbsp;{build_var(rname)}')
                    + '&nbsp;&nbsp;Procedure</p>\n'
                )
                file.write(build_var_sig(varsigs))
                file.write(f"</div>\n<p>{text_to_str(some['summary'])}</p>\n")


    for _var in pt_vars:
        if _var not in canonical_env:
            raise ValueError(f"{_var} not in env")

    for key in canonical_env:
        if key not in pt_vars:
            raise ValueError(f"missing docs for {key}")

    print(f"built {len(canonical_env)} variables")


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
            '<p>See also: <a href="../docs">docs</a></p>\n'
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
