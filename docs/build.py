#!/usr/bin/env python3

import os
import re
import shlex
import shutil
import subprocess
import sys
from pathlib import Path
from re import Match
from shutil import rmtree
from typing import Callable, NoReturn


def error(msg: str) -> NoReturn:
    print(f"Error! {msg}", file=sys.stderr)
    sys.exit(1)


def regex_match(regex: str, text: str) -> str | None:
    if match := re.search(regex, text):
        return match.groupdict()["match"]
    return None


def match_liquid(text: str, hook: Callable[[list[str]], str]) -> str:
    def search(text: str) -> Match[str] | None:
        return re.search(r"{{\s[^\}]+\s}}", text)

    liquid_syntax = search(text)
    while liquid_syntax:
        match = regex_match(r"{{\s(?P<match>[^\}]+)\s}}", text)
        if match is None:
            error(f"match is None. {text}")
        text = text.replace(liquid_syntax.group(), hook(shlex.split(match)))
        liquid_syntax = search(text)
    return text


def dollar_syntax(text: list[str]) -> list[int]:
    new_list = []
    for item in text:
        try:
            new_list.append(int(item[1:]))
        except (ValueError, TypeError):
            error(f'Can\'t convert "{text}" to dollar syntax.')
    return new_list


def add_components(lines: list[str], comp_map: dict[str, str]) -> list[str]:
    def comp_hook(args: list[str]) -> str:
        def arg_hook(dollars: list[str]) -> str:
            nonlocal args
            if len(dollars) > 1:
                error("Only one dollar allowed")

            indexes = dollar_syntax(dollars)
            return str(args[indexes[0]])

        comp_name = args[0]
        if comp_name not in comp_map:
            error(f"{lines}\n{comp_name} is not in components.")

        return match_liquid(comp_map[comp_name].rstrip(), arg_hook)

    return [match_liquid(line, comp_hook) for line in lines]



def make_site(source: str, output_dir: str) -> None:
    components = os.path.join(source, "components")

    if not os.path.isdir(components):
        error(f"components dir: '{components}' not found")

    join = os.path.join
    comp_map = {}
    for item in os.listdir(components):
        if item.startswith("."):
            continue
        comp_name = os.path.splitext(os.path.basename(item))[0]
        with open(os.path.join(components, item)) as file:
            comp_map[comp_name] = file.read()

    try:
        os.mkdir(output_dir)
    except OSError:
        rmtree(output_dir)
        os.mkdir(output_dir)

    def fix_files(path: str, out_dir: str) -> None:
        for item in os.listdir(path):
            the_file = join(path, item)
            new_file = join(out_dir, item)

            if os.path.isdir(the_file):
                if the_file != components:
                    os.mkdir(new_file)
                    fix_files(the_file, new_file)
                continue

            ext = os.path.splitext(the_file)[1]

            if ext == ".html":
                with open(the_file) as file:
                    contents = file.read().splitlines(True)

                contents = add_components(contents, comp_map)
                if not new_file.endswith("index.html"):
                    new_file = new_file[:-5]

                with open(new_file, "w") as file:
                    file.writelines(contents)

            elif ext != ".md" and item != ".DS_Store":
                shutil.copy(the_file, new_file)

    fix_files(source, output_dir)


sys.path.insert(0, "/Users/wyattblue/projects/auto-editor")

import auto_editor.vanparse as vanparse
from auto_editor.__main__ import main_options
from auto_editor.lang.palet import Lexer, Parser, env, interpret
from auto_editor.vanparse import OptionText

parser = vanparse.ArgumentParser("Auto-Editor")
parser = main_options(parser)

subprocess.run(["./mdGen"])


with open("src/ref/options.html", "w") as file:
    file.write(
        '{{ header-desc "Options" "These are the options and flags that auto-editor uses." }}\n'
        "<body>\n"
        "{{ nav }}\n"
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

with open("doc.pal", "r") as sourcefile:
    try:
        interpret(env, Parser(Lexer("doc.pal", sourcefile.read())))
    except Exception as e:
        print(e)
        quit(1)

make_site("src", "public")
