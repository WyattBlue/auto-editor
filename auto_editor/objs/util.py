from __future__ import annotations

from difflib import get_close_matches
from typing import TYPE_CHECKING, NamedTuple

if TYPE_CHECKING:
    from typing import Any, Callable


class ParserError(Exception):
    pass


class Required:
    pass


class smallAttr:
    __slots__ = ("n", "default", "contract")

    def __init__(self, n: str, default: Any, contract: Any):
        self.n = n
        self.default = default
        self.contract = contract


class smallAttrs:
    __slots__ = ("name", "attrs")

    def __init__(self, name: str, *attrs: smallAttr):
        self.name = name
        self.attrs = attrs


class Attr(NamedTuple):
    n: str
    coerce: Any
    default: Any


class Attrs:
    __slots__ = ("name", "attrs")

    def __init__(self, name: str, *attrs: Attr):
        self.name = name
        self.attrs = attrs


def _default_var_f(name: str, val: str, coerce: Any) -> Any:
    return coerce(val)


def _norm_name(s: str) -> str:
    # Python does not allow - in variable names
    return s.replace("-", "_")


def parse_with_palet(
    text: str,  # the string to be parsed
    build: smallAttrs,
    env: dict,
) -> dict[str, Any]:
    from auto_editor.interpreter import Lexer, MyError, Parser, display_str, interpret

    def go(text: str, c: Any) -> Any:
        try:
            results = interpret(env, Parser(Lexer(text)))
        except MyError as e:
            raise ParserError(e)

        if len(results) == 0:
            raise ParserError("Results must be of length > 0")

        if c(results[-1]) is not True:
            raise ParserError(f"Value: {display_str(results[-1])} needs to be {c.name}")

        return results[-1]

    # Positional Arguments
    #    --rectangle 0,end,10,20,20,30,#000, ...
    # Keyword Arguments
    #    --rectangle start=0,dur=end,x1=10, ...

    KEYWORD_SEP = "="
    kwargs: dict[str, Any] = {}

    for attr in build.attrs:
        kwargs[_norm_name(attr.n)] = attr.default

    allow_positional_args = True

    for i, arg in enumerate(text.split(",")):
        if not arg:
            continue

        if i + 1 > len(build.attrs):
            raise ParserError(
                f"{build.name} has too many arguments, starting with '{arg}'."
            )

        if KEYWORD_SEP in arg:
            key, val = arg.split(KEYWORD_SEP, 1)

            allow_positional_args = False
            found = False

            for attr in build.attrs:
                if key == attr.n:
                    kwargs[_norm_name(attr.n)] = go(val, attr.contract)
                    found = True
                    break

            if not found:
                all_names = {attr.n for attr in build.attrs}
                if matches := get_close_matches(key, all_names):
                    more = f"\n    Did you mean:\n        {', '.join(matches)}"
                else:
                    more = f"\n    keywords available:\n        {', '.join(all_names)}"

                raise ParserError(
                    f"{build.name} got an unexpected keyword '{key}'\n{more}"
                )

        elif allow_positional_args:
            kwargs[_norm_name(build.attrs[i].n)] = go(arg, build.attrs[i].contract)
        else:
            raise ParserError(
                f"{build.name} positional argument follows keyword argument."
            )

    for k, v in kwargs.items():
        if v is Required:
            raise ParserError(f"'{k}' must be specified.")

    return kwargs


def parse_dataclass(
    text: str,  # the string to be parsed
    build: Attrs,
    var_f: Callable[[str, str, Any], Any] = _default_var_f,
    coerce_default: bool = False,
) -> dict[str, Any]:
    # Positional Arguments
    #    --rectangle 0,end,10,20,20,30,#000, ...
    # Keyword Arguments
    #    --rectangle start=0,dur=end,x1=10, ...

    KEYWORD_SEP = "="
    kwargs: dict[str, Any] = {}

    for attr in build.attrs:
        if coerce_default and attr.default is not Required:
            kwargs[_norm_name(attr.n)] = var_f(attr.n, attr.default, attr.coerce)
        else:
            kwargs[_norm_name(attr.n)] = attr.default

    allow_positional_args = True

    for i, arg in enumerate(text.split(",")):
        if not arg:
            continue

        if i + 1 > len(build.attrs):
            raise ParserError(
                f"{build.name} has too many arguments, starting with '{arg}'."
            )

        if KEYWORD_SEP in arg:
            key, val = arg.split(KEYWORD_SEP, 1)

            allow_positional_args = False
            found = False

            for attr in build.attrs:
                if key == attr.n:
                    kwargs[_norm_name(attr.n)] = var_f(attr.n, val, attr.coerce)
                    found = True
                    break

            if not found:
                all_names = {attr.n for attr in build.attrs}
                if matches := get_close_matches(key, all_names):
                    more = f"\n    Did you mean:\n        {', '.join(matches)}"
                else:
                    more = f"\n    keywords available:\n        {', '.join(all_names)}"

                raise ParserError(
                    f"{build.name} got an unexpected keyword '{key}'\n{more}"
                )

        elif allow_positional_args:
            name = build.attrs[i].n
            kwargs[_norm_name(name)] = var_f(name, arg, build.attrs[i].coerce)
        else:
            raise ParserError(
                f"{build.name} positional argument follows keyword argument."
            )

    for k, v in kwargs.items():
        if v is Required:
            raise ParserError(f"'{k}' must be specified.")

    return kwargs
