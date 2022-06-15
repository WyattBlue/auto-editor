import difflib
import re
import sys
import textwrap
from dataclasses import dataclass
from shutil import get_terminal_size
from typing import (
    Any,
    Callable,
    Dict,
    List,
    Literal,
    Optional,
    Sequence,
    Set,
    Tuple,
    TypeVar,
    Union,
)

import auto_editor
from auto_editor.utils.log import Log

T = TypeVar("T", bound=Callable)
Nargs = Union[int, Literal["*"]]


@dataclass
class Required:
    names: Sequence[str]
    nargs: Nargs = "*"
    type: type = str
    choices: Optional[Sequence[str]] = None
    help: str = ""
    _type: str = "required"


@dataclass
class Options:
    names: Sequence[str]
    nargs: Nargs = 1
    type: type = str
    flag: bool = False
    choices: Optional[Sequence[str]] = None
    help: str = ""
    _type: str = "option"


@dataclass
class OptionText:
    text: str
    _type: str


def indent(text: str, prefix: str) -> str:
    def predicate(line: str) -> str:
        return line.strip()

    def prefixed_lines():
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


def print_program_help(
    reqs: List[Required], args: List[Union[Options, OptionText]]
) -> None:
    text = ""
    for arg in args:
        if isinstance(arg, OptionText):
            text += f"\n  {arg.text}\n" if arg._type == "text" else "\n"
        else:
            text += "  " + ", ".join(arg.names) + f": {arg.help}\n"
    text += "\n"
    for req in reqs:
        text += "  " + ", ".join(req.names) + f": {req.help}\n"
    out(text)


def get_help_data() -> Dict[str, Dict[str, str]]:
    import json
    import os.path

    dirpath = os.path.dirname(os.path.realpath(__file__))

    with open(os.path.join(dirpath, "help.json"), "r") as fileobj:
        data = json.load(fileobj)

    assert isinstance(data, dict)
    return data


def to_underscore(name: str) -> str:
    """Convert new style options to old style.  e.g. --hello-world -> --hello_world"""
    return name[:2] + name[2:].replace("-", "_")


def to_key(op: Union[Options, Required]) -> str:
    """Convert option name to arg key.  e.g. --hello-world -> hello_world"""
    return op.names[0][:2].replace("-", "") + op.names[0][2:].replace("-", "_")


def print_option_help(program_name: str, ns_obj: T, option: Options) -> None:
    text = "  " + ", ".join(option.names) + f"\n    {option.help}\n\n"

    data = get_help_data()

    if option.names[0] in data[program_name]:
        text += indent(data[program_name][option.names[0]], "    ") + "\n\n"

    if option.flag:
        text += "    type: flag\n"
    else:
        text += f"    type: {option.type.__name__}\n"

        if option.nargs != 1:
            text += f"    nargs: {option.nargs}\n"

        default = getattr(ns_obj, to_key(option))

        if default is not None:
            text += f"    default: {default}\n"

        if option.choices is not None:
            text += "    choices: " + ", ".join(option.choices) + "\n"

    out(text)


def get_option(name: str, options: List[Options]) -> Optional[Options]:
    for option in options:
        if name in option.names or name in map(to_underscore, option.names):
            return option
    return None


def parse_value(option: Union[Options, Required], val: Optional[str]) -> Any:
    if val is None and option.nargs == 1:
        Log().error(f"{option.names[0]} needs argument.")

    try:
        value = option.type(val)
    except TypeError as e:
        Log().error(str(e))

    if option.choices is not None and value not in option.choices:
        my_choices = ", ".join(option.choices)

        Log().error(
            f"{value} is not a choice for {option.names[0]}\nchoices are:\n  {my_choices}"
        )

    return value


class ArgumentParser:
    def __init__(self, program_name: str) -> None:
        self.program_name = program_name
        self.requireds: List[Required] = []
        self.options: List[Options] = []
        self.args: List[Union[Options, OptionText]] = []

    def add_argument(self, *args: str, **kwargs) -> None:
        x = Options(args, **kwargs)
        self.options.append(x)
        self.args.append(x)

    def add_required(self, *args: str, **kwargs) -> None:
        self.requireds.append(Required(args, **kwargs))

    def add_text(self, text: str) -> None:
        self.args.append(OptionText(text, "text"))

    def add_blank(self) -> None:
        self.args.append(OptionText("", "blank"))

    def parse_args(
        self,
        ns_obj: T,
        sys_args: List[str],
        macros: Optional[List[Tuple[Set[str], List[str]]]] = None,
    ) -> T:
        if len(sys_args) == 0:
            out(get_help_data()[self.program_name]["_"])
            sys.exit()

        if len(sys_args) == 1 and sys_args[0] in ("-v", "-V"):
            sys.stdout.write(f"{auto_editor.version} ({auto_editor.__version__})\n")
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
        option_names: List[str] = []

        program_name = self.program_name
        requireds = self.requireds
        options = self.options
        args = self.args

        builtin_help = Options(
            ("--help", "-h"),
            flag=True,
            help="Show info about this program or option then exit.",
        )
        options.append(builtin_help)
        args.append(builtin_help)

        # Figure out command line options changed by user.
        used_options: List[Options] = []

        req_list: List[str] = []
        req_list_name = requireds[0].names[0]
        setting_req_list = requireds[0].nargs != 1

        option_list: List[str] = []
        oplist_name: Optional[str] = None
        oplist_coerce = str

        i = 0
        while i < len(sys_args):
            arg = sys_args[i]
            option = get_option(arg, options)

            if option is None:
                if oplist_name is not None:
                    option_list.append(oplist_coerce(arg))

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
                if oplist_name is not None:
                    ns.__setattr__(oplist_name, option_list)

                if option in used_options:
                    Log().error(f"Cannot repeat option {option.names[0]} twice.")

                used_options.append(option)

                option_list = []
                oplist_name = None
                oplist_coerce = option.type

                key = to_key(option)

                next_arg = None if i == len(sys_args) - 1 else sys_args[i + 1]
                if next_arg in ("-h", "--help"):
                    print_option_help(program_name, ns_obj, option)
                    sys.exit()

                if option.nargs != 1:
                    oplist_name = key
                    ns.__setattr__(key, parse_value(option, next_arg))
                elif option.flag:
                    ns.__setattr__(key, True)
                else:
                    ns.__setattr__(key, parse_value(option, next_arg))
                    i += 1
            i += 1

        if oplist_name is not None:
            ns.__setattr__(oplist_name, option_list)

        if setting_req_list:
            ns.__setattr__(req_list_name, req_list)

        if ns.help:
            print_program_help(requireds, args)
            sys.exit()

        return ns
