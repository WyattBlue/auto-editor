from __future__ import annotations

import difflib
import re
import sys
import textwrap
from collections.abc import Iterator
from dataclasses import dataclass
from io import StringIO
from shutil import get_terminal_size
from typing import TYPE_CHECKING

from auto_editor.utils.log import Log
from auto_editor.utils.types import CoerceError

if TYPE_CHECKING:
    from collections.abc import Callable
    from typing import Any, Literal, TypeVar

    T = TypeVar("T")
    Nargs = int | Literal["*"]


@dataclass(slots=True)
class Required:
    names: tuple[str, ...]
    nargs: Nargs = "*"
    type: type = str
    choices: tuple[str, ...] | None = None
    metavar: str = "[file ...] [options]"


@dataclass(slots=True)
class Options:
    names: tuple[str, ...]
    nargs: Nargs = 1
    type: type = str
    flag: bool = False
    choices: tuple[str, ...] | None = None
    metavar: str | None = None
    help: str = ""


@dataclass(slots=True)
class OptionText:
    text: str


def indent(text: str, prefix: str) -> str:
    def prefixed_lines() -> Iterator[str]:
        for line in text.splitlines(True):
            yield (prefix + line if line.strip() else line)

    return "".join(prefixed_lines())


def out(text: str) -> None:
    width = get_terminal_size().columns - 3

    indent_regex = re.compile(r"^(\s+)")

    for line in text.split("\n"):
        exist_indent = re.search(indent_regex, line)
        pre_indent = exist_indent.groups()[0] if exist_indent else ""

        sys.stdout.write(textwrap.fill(line, width=width, subsequent_indent=pre_indent))
        sys.stdout.write("\n")


def print_program_help(reqs: list[Required], args: list[Options | OptionText]) -> None:
    sys.stdout.write(f"Usage: {' '.join([req.metavar for req in reqs])}\n\nOptions:")

    width = get_terminal_size().columns - 3
    split = int(width * 0.44) + 3
    indent = "  "

    for i, arg in enumerate(args):
        if isinstance(arg, OptionText):
            if i == 0:
                sys.stdout.write(f"\n  {arg.text}")
                indent = "    "
            else:
                sys.stdout.write(f"\n\n  {arg.text}")
        else:
            sys.stdout.write("\n")
            line = f"{indent}{', '.join(reversed(arg.names))}"
            if arg.metavar is not None:
                line += f" {arg.metavar}"

            if arg.help == "":
                pass
            elif len(line) < split:
                line = textwrap.fill(
                    arg.help,
                    width=width,
                    initial_indent=f"{line}{' ' * (split - len(line))}",
                    subsequent_indent=split * " ",
                )
            else:
                line += "\n"
                line += textwrap.fill(
                    arg.help,
                    width=width,
                    initial_indent=split * " ",
                    subsequent_indent=split * " ",
                )

            sys.stdout.write(line)
    sys.stdout.write("\n\n")


def to_underscore(name: str) -> str:
    """Convert new style options to old style.  e.g. --hello-world -> --hello_world"""
    return name[:2] + name[2:].replace("-", "_")


def to_key(op: Options | Required) -> str:
    """Convert option name to arg key.  e.g. --hello-world -> hello_world"""
    return op.names[0][:2].replace("-", "") + op.names[0][2:].replace("-", "_")


def print_option_help(name: str | None, ns_obj: object, option: Options) -> None:
    text = StringIO()
    text.write(
        f"  {', '.join(option.names)} {'' if option.metavar is None else option.metavar}\n\n"
    )

    if option.flag:
        text.write("    type: flag\n")
    else:
        if option.nargs != 1:
            text.write(f"    nargs: {option.nargs}\n")

        default: str | float | int | tuple | None = None
        try:
            default = getattr(ns_obj, to_key(option))
        except AttributeError:
            pass

        if default is not None and isinstance(default, int | float | str):
            text.write(f"    default: {default}\n")

        if option.choices is not None:
            text.write(f"    choices: {', '.join(option.choices)}\n")

    from auto_editor.help import data

    if name is not None and option.names[0] in data[name]:
        text.write(indent(data[name][option.names[0]], "    ") + "\n")
    else:
        text.write(f"    {option.help}\n\n")

    out(text.getvalue())


def get_option(name: str, options: list[Options]) -> Options | None:
    for option in options:
        if name in option.names or name in map(to_underscore, option.names):
            return option
    return None


class ArgumentParser:
    def __init__(self, program_name: str | None):
        self.program_name = program_name
        self.requireds: list[Required] = []
        self.options: list[Options] = []
        self.args: list[Options | OptionText] = []

    def add_argument(self, *args: str, **kwargs: Any) -> None:
        x = Options(args, **kwargs)
        self.options.append(x)
        self.args.append(x)

    def add_required(self, *args: str, **kwargs: Any) -> None:
        self.requireds.append(Required(args, **kwargs))

    def add_text(self, text: str) -> None:
        self.args.append(OptionText(text))

    def parse_args(
        self,
        ns_obj: type[T],
        sys_args: list[str],
        log_: Log | None = None,
        macros: list[tuple[set[str], list[str]]] | None = None,
    ) -> T:
        if not sys_args and self.program_name is not None:
            from auto_editor.help import data

            out(data[self.program_name]["_"])
            sys.exit()

        if macros is not None:
            _macros = [(x[0].union(map(to_underscore, x[0])), x[1]) for x in macros]
            for old_options, new in _macros:
                for old_option in old_options:
                    if old_option in sys_args:
                        pos = sys_args.index(old_option)
                        sys_args[pos : pos + 1] = new
            del _macros
        del macros

        log = Log() if log_ is None else log_
        ns = ns_obj()
        option_names: list[str] = []

        def parse_value(option: Options | Required, val: str | None) -> Any:
            if val is None and option.nargs == 1:
                log.error(f"{option.names[0]} needs argument.")

            try:
                value = option.type(val)
            except CoerceError as e:
                log.error(e)

            if option.choices is not None and value not in option.choices:
                log.error(
                    f"{value} is not a choice for {option.names[0]}\n"
                    f"choices are:\n  {', '.join(option.choices)}"
                )
            return value

        program_name = self.program_name
        requireds = self.requireds
        options = self.options
        args = self.args

        builtin_help = Options(
            ("--help", "-h"),
            flag=True,
            help="Show info about this program or option then exit",
        )
        options.append(builtin_help)
        args.append(builtin_help)

        # Figure out command line options changed by user.
        used_options: list[Options] = []

        req_list: list[str] = []
        req_list_name = requireds[0].names[0]
        setting_req_list = requireds[0].nargs != 1

        oplist_name: str | None = None
        oplist_coerce: Callable[[str], str] = str

        i = 0
        while i < len(sys_args):
            arg = sys_args[i]
            option = get_option(arg, options)

            if option is None:
                if oplist_name is not None:
                    try:
                        val = oplist_coerce(arg)
                        ns.__setattr__(oplist_name, getattr(ns, oplist_name) + [val])
                    except (CoerceError, ValueError) as e:
                        log.error(e)
                elif requireds and not arg.startswith("--"):
                    if requireds[0].nargs == 1:
                        ns.__setattr__(req_list_name, parse_value(requireds[0], arg))
                        requireds.pop()
                    else:
                        req_list.append(arg)
                else:
                    label = "option" if arg.startswith("--") else "short"

                    # 'Did you mean' message might appear that options need a comma.
                    if arg.replace(",", "") in option_names:
                        log.error(f"Option '{arg}' has an unnecessary comma.")

                    close_matches = difflib.get_close_matches(arg, option_names)
                    if close_matches:
                        log.error(
                            f"Unknown {label}: {arg}\n\n    Did you mean:\n        "
                            + ", ".join(close_matches)
                        )
                    log.error(f"Unknown {label}: {arg}")
            else:
                if option.nargs != "*":
                    if option in used_options:
                        log.error(
                            f"Option {option.names[0]} may not be used more than once."
                        )
                    used_options.append(option)

                oplist_name = None
                oplist_coerce = option.type

                key = to_key(option)

                next_arg = None if i == len(sys_args) - 1 else sys_args[i + 1]
                if next_arg in ("-h", "--help"):
                    print_option_help(program_name, ns_obj, option)
                    sys.exit()

                if option.flag:
                    ns.__setattr__(key, True)
                elif option.nargs == 1:
                    ns.__setattr__(key, parse_value(option, next_arg))
                    i += 1
                else:
                    oplist_name = key

            i += 1

        if setting_req_list:
            ns.__setattr__(req_list_name, req_list)

        if getattr(ns, "help"):
            print_program_help(requireds, args)
            sys.exit()

        return ns
