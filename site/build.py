#!/usr/bin/env python3

import argparse
import os
import re
import shutil
import subprocess

import auto_editor.vanparse as vanparse
import basswood
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

with open("src/options.html", "w") as file:
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
    subprocess.run(["rsync", "-rtvzP", "binaries/", SECRET2])
    subprocess.run(
        ["rsync", "-rtvzP", "auto-editor/", "root@auto-editor.com:/var/www/auto-editor"]
    )
else:
    site.serve(port=8080)

print("Removing temporary files.")
try:
    shutil.rmtree("./auto-editor")
except FileNotFoundError:
    pass
os.remove("./src/options.html")
os.remove(f"./src/{SECRET}/more.html")
