from __future__ import annotations

import os
import re
import shlex
import shutil
import sys
from re import Match
from typing import Any, Callable, NoReturn


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


def add_components(lines: list[str], components: dict[str, str]) -> list[str]:
    def comp_hook(args: list[str]) -> str:
        def arg_hook(dollars: list[str]) -> str:
            nonlocal args
            if len(dollars) > 1:
                error("Only one dollar allowed")

            indexes = dollar_syntax(dollars)
            return str(args[indexes[0]])

        var = args[0]
        if var.startswith("comp."):
            comp_name = var[var.index(".") + 1 :]
            if comp_name not in components:
                print(lines)
                error(f"{comp_name} is not in components.")

            comp_text = components[comp_name].rstrip()
            comp_text = match_liquid(comp_text, arg_hook)
            return comp_text
        error(f"Cannot use variable: {var}")
        return " ".join(args)

    return [match_liquid(l, comp_hook) for l in lines]


def safe_rm_dir(path: str) -> None:
    try:
        os.mkdir(path)
    except OSError:
        shutil.rmtree(path)
        os.mkdir(path)


class Site:
    def __init__(self, prod: bool, source: str, output_dir: str):
        self.source = source
        self.output_dir = output_dir
        self.components = os.path.join(source, "components")
        self.production = prod

        if not os.path.isdir(self.components):
            error(f"components dir: '{self.components}' not found")


    def make(self) -> None:
        join = os.path.join
        components = {}
        for item in os.listdir(self.components):
            if item.startswith("."):
                continue
            comp_name = os.path.splitext(os.path.basename(item))[0]
            with open(os.path.join(self.components, item)) as file:
                components[comp_name] = file.read()

        def fix_files(path: str, OUT: str) -> None:
            safe_rm_dir(OUT)
            for item in os.listdir(path):
                the_file = join(path, item)
                new_file = join(OUT, item)

                if os.path.isdir(the_file):
                    if the_file != self.components:
                        shutil.copytree(the_file, new_file)
                        fix_files(the_file, new_file)
                    continue

                ext = os.path.splitext(the_file)[1]

                if ext not in (".html", ".css", ".txt", ".js"):
                    if item != ".DS_Store":
                        shutil.copy(the_file, new_file)
                    continue

                with open(the_file) as file:
                    contents = file.read().splitlines(True)

                contents = add_components(contents, components)

                if ext == ".html" and self.production:
                    if "index" not in item:
                        # remove .html files
                        new_file = f"{os.path.splitext(new_file)[0]}.html"
                        if os.path.exists(new_file):
                            os.remove(new_file)

                    # remove .html links
                    contents = list(map(lambda n: n.replace(".html", ""), contents))

                with open(new_file, "w") as file:
                    file.writelines(contents)

        fix_files(self.source, self.output_dir)

    def serve(self, port: int) -> None:
        import http.server
        import socketserver

        DIRECTORY = os.path.abspath(self.output_dir)

        def run_server(port: int, DIRECTORY: str) -> None:
            class Handler(http.server.SimpleHTTPRequestHandler):
                def __init__(self, *args: Any, **kwargs: Any) -> None:
                    super().__init__(*args, directory=DIRECTORY, **kwargs)

            with socketserver.TCPServer(("", port), Handler) as httpd:
                print(f"serving at http://localhost:{port}")
                try:
                    httpd.serve_forever()
                except KeyboardInterrupt:
                    pass
                print("\nclosing server")
                httpd.server_close()

        try:
            run_server(port, DIRECTORY)
        except OSError:
            run_server(port + 1, DIRECTORY)
