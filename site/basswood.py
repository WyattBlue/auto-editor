import os
import re
import shlex
import shutil
import sys
from re import Match
from typing import Any, Callable, NoReturn, Optional


def error(msg: str) -> NoReturn:
    print(f"Error! {msg}", file=sys.stderr)
    sys.exit(1)


def regex_match(regex: str, text: str) -> Optional[str]:
    match = re.search(regex, text)
    if match:
        return match.groupdict()["match"]
    return None


def match_liquid(text: str, hook: Callable[[list[str]], str]) -> str:
    def search(text: str) -> Optional[Match[str]]:
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

    new_lines = []
    for line in lines:
        new_lines.append(match_liquid(line, comp_hook))
    return new_lines


def safe_rm_dir(path: str) -> None:
    try:
        os.mkdir(path)
    except OSError:
        shutil.rmtree(path)
        os.mkdir(path)


class Site:
    def __init__(self, source: str, output_dir: str) -> None:
        self.source = source
        self.output_dir = output_dir
        self.components = os.path.join(source, "components")
        self.production = False

        if not os.path.isdir(self.components):
            error(f"components dir: '{self.components}' not found")

    @staticmethod
    def _get_filename(path: str) -> str:
        return os.path.splitext(os.path.basename(path))[0]

    def _get_components(self) -> dict[str, str]:
        components = {}
        if os.path.exists(self.components):
            for item in os.listdir(self.components):
                if item.startswith("."):
                    continue
                comp_name = self._get_filename(item)
                with open(os.path.join(self.components, item), "r") as file:
                    components[comp_name] = file.read()
        return components

    def make(self) -> None:
        join = os.path.join
        components = self._get_components()

        def fix_files(path: str, OUT: str, root: str) -> None:
            safe_rm_dir(OUT)
            for item in os.listdir(path):
                the_file = join(path, item)
                new_file = join(OUT, item)

                if os.path.isdir(the_file):
                    if the_file != self.components:
                        shutil.copytree(the_file, new_file)
                        fix_files(the_file, new_file, root)
                    continue

                ext = os.path.splitext(the_file)[1]

                if ext not in (".html", ".css", ".txt", ".js"):
                    if item != ".DS_Store":
                        shutil.copy(the_file, new_file)
                    continue

                with open(the_file, "r") as file:
                    contents = file.read().splitlines(True)

                contents = add_components(contents, components)

                def remove_html_links(n):
                    return n.replace(".html", "")

                if ext == ".html":
                    if self.production:
                        if "index" not in item:
                            new_file = os.path.splitext(new_file)[0]

                            # remove bad html files with liquid syntax.
                            if os.path.exists(new_file + ".html"):
                                os.remove(new_file + ".html")

                        # remove .html links
                        contents = list(map(remove_html_links, contents))

                with open(new_file, "w") as file:
                    file.writelines(contents)

        root = os.path.abspath(self.source)
        fix_files(self.source, self.output_dir, root)

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
                print("\nClosing server.")
                httpd.server_close()

        try:
            run_server(port, DIRECTORY)
        except OSError:
            run_server(port + 1, DIRECTORY)
