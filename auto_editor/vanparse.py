from __future__ import annotations

import difflib
import re
import sys
import textwrap
from dataclasses import dataclass
from shutil import get_terminal_size
from typing import Any, Callable, Iterator, Literal, TypeVar, Union

from auto_editor.utils.log import Log

T = TypeVar("T", bound=type)
Nargs = Union[int, Literal["*"]]


@dataclass
class Required:
    names: tuple[str, ...]
    nargs: Nargs = "*"
    type: type = str
    choices: tuple[str, ...] | None = None
    metavar: str = "[file ...] [options]"


@dataclass
class Options:
    names: tuple[str, ...]
    nargs: Nargs = 1
    type: type = str
    flag: bool = False
    choices: tuple[str, ...] | None = None
    metavar: str | None = None
    help: str = ""


@dataclass
class OptionText:
    text: str


def indent(text: str, prefix: str) -> str:
    def predicate(line: str) -> str:
        return line.strip()

    def prefixed_lines() -> Iterator[str]:
        for line in text.splitlines(True):
            yield (prefix + line if predicate(line) else line)

    return "".join(prefixed_lines())


def out(text: str) -> None:
    width = get_terminal_size().columns - 3

    indent_regex = re.compile(r"^(\s+)")
    wrapped_lines = []

    for line in text.split("\n"):
        exist_indent = re.search(indent_regex, line)
        pre_indent = exist_indent.groups()[0] if exist_indent else ""

        wrapped_lines.append(
            textwrap.fill(line, width=width, subsequent_indent=pre_indent)
        )

    print("\n".join(wrapped_lines))


def print_program_help(reqs: list[Required], args: list[Options | OptionText]) -> None:
    text = f"Usage: {' '.join([req.metavar for req in reqs])}\n\nOptions:"

    width = get_terminal_size().columns - 3
    split = int(width * 0.44) + 3
    indent = "  "

    for i, arg in enumerate(args):
        if isinstance(arg, OptionText):
            if i == 0:
                text += f"\n  {arg.text}"
                indent = "    "
            else:
                text += f"\n\n  {arg.text}"
        else:
            text += "\n"
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
                ).replace("&", "")
            else:
                line += "\n"
                line += textwrap.fill(
                    arg.help,
                    width=width,
                    initial_indent=split * " ",
                    subsequent_indent=split * " ",
                )

            text += line
    text += "\n\n"
    sys.stdout.write(text)


def get_help_data() -> dict[str, dict[str, str]]:
    import json
    import os.path

    dirpath = os.path.dirname(os.path.realpath(__file__))

    with open(os.path.join(dirpath, "help.json")) as fileobj:
        data = json.load(fileobj)

    assert isinstance(data, dict)
    return data


def to_underscore(name: str) -> str:
    """Convert new style options to old style.  e.g. --hello-world -> --hello_world"""
    return name[:2] + name[2:].replace("-", "_")


def to_key(op: Options | Required) -> str:
    """Convert option name to arg key.  e.g. --hello-world -> hello_world"""
    return op.names[0][:2].replace("-", "") + op.names[0][2:].replace("-", "_")


def print_option_help(program_name: str, ns_obj: T, option: Options) -> None:
    text = f"  {', '.join(option.names)} {'' if option.metavar is None else option.metavar}\n\n"

    bar_len = 11
    if option.flag:
        text += "    type: flag\n"
        bar_len = 15
    else:
        if option.nargs != 1:
            _add = f"    nargs: {option.nargs}\n"
            bar_len = len(_add)
            text += _add

        default: str | None = None
        try:
            default = getattr(ns_obj, to_key(option))
        except AttributeError:
            pass

        if default is not None:
            if isinstance(default, tuple):
                _add = f"    default: {','.join(map(str, default))}\n"
            else:
                _add = f"    default: {default}\n"
            bar_len = len(_add)
            text += _add

        if option.choices is not None:
            text += "    choices: " + ", ".join(option.choices) + "\n"

    text += f"    {'-' * (bar_len - 5)}\n\n    {option.help}\n\n"
    data = get_help_data()

    if option.names[0] in data[program_name]:
        text += indent(data[program_name][option.names[0]], "    ") + "\n"

    out(text)


def get_option(name: str, options: list[Options]) -> Options | None:
    for option in options:
        if name in option.names or name in map(to_underscore, option.names):
            return option
    return None


def parse_value(option: Options | Required, val: str | None) -> Any:
    if val is None and option.nargs == 1:
        Log().error(f"{option.names[0]} needs argument.")

    try:
        value = option.type(val)
    except TypeError as e:
        Log().error(e)

    if option.choices is not None and value not in option.choices:
        my_choices = ", ".join(option.choices)

        Log().error(
            f"{value} is not a choice for {option.names[0]}\nchoices are:\n  {my_choices}"
        )

    return value


class ArgumentParser:
    def __init__(self, program_name: str) -> None:
        self.program_name = program_name
        self.requireds: list[Required] = []
        self.options: list[Options] = []
        self.args: list[Options | OptionText] = []

    def add_argument(self, *args: str, **kwargs) -> None:
        x = Options(args, **kwargs)
        self.options.append(x)
        self.args.append(x)

    def add_required(self, *args: str, **kwargs) -> None:
        self.requireds.append(Required(args, **kwargs))

    def add_text(self, text: str) -> None:
        self.args.append(OptionText(text))

    def parse_args(
        self,
        ns_obj: T,
        sys_args: list[str],
        macros: list[tuple[set[str], list[str]]] | None = None,
    ) -> T:
        if len(sys_args) == 0:
            out(get_help_data()[self.program_name]["_"])
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

        ns = ns_obj()
        option_names: list[str] = []

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
                    except (TypeError, ValueError) as e:
                        Log().error(e)
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
                        Log().error(f"Option '{arg}' has an unnecessary comma.")

                    close_matches = difflib.get_close_matches(arg, option_names)
                    if close_matches:
                        Log().error(
                            f"Unknown {label}: {arg}\n\n    Did you mean:\n        "
                            + ", ".join(close_matches)
                        )
                    Log().error(f"Unknown {label}: {arg}")
            else:
                if option.nargs != "*":
                    if option in used_options:
                        Log().error(f"Cannot repeat option {option.names[0]} twice.")
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

        if ns.help:
            print_program_help(requireds, args)
            sys.exit()

        return ns
