from __future__ import annotations

from dataclasses import dataclass
from difflib import get_close_matches
from typing import TYPE_CHECKING

from auto_editor.lib.data_structs import Env

if TYPE_CHECKING:
    from collections.abc import Callable
    from typing import Any, Literal


class ParserError(Exception):
    pass


class Required:
    pass


@dataclass(slots=True)
class pAttr:
    n: str
    default: Any
    contract: Any
    coerce: Callable[[Any], Any] | Literal["source"] | None = None


class pAttrs:
    __slots__ = ("name", "attrs")

    def __init__(self, name: str, *attrs: pAttr):
        self.name = name
        self.attrs = attrs


def _norm_name(s: str) -> str:
    # Python does not allow - in variable names
    return s.replace("-", "_")


class PLexer:
    __slots__ = ("text", "pos", "char")

    def __init__(self, text: str):
        self.text = text
        self.pos: int = 0
        self.char: str | None = self.text[self.pos] if text else None

    def advance(self) -> None:
        self.pos += 1
        self.char = None if self.pos > len(self.text) - 1 else self.text[self.pos]

    def string(self) -> str:
        result = ""
        while self.char is not None and self.char != '"':
            if self.char == "\\":
                self.advance()
                if self.char is None:
                    raise ParserError(
                        "Expected character for escape sequence, got end of file."
                    )
                result += f"\\{self.char}"
                self.advance()
            else:
                result += self.char
            self.advance()

        self.advance()
        return f'"{result}"'

    def get_next_token(self) -> str | None:
        while self.char is not None:
            if self.char == '"':
                self.advance()
                return self.string()

            result = ""
            while self.char is not None and self.char not in ",":
                result += self.char
                self.advance()

            self.advance()
            return result
        return None


def parse_with_palet(
    text: str, build: pAttrs, _env: Env | dict[str, Any]
) -> dict[str, Any]:
    from auto_editor.lang.palet import Lexer, Parser, interpret
    from auto_editor.lib.data_structs import print_str
    from auto_editor.lib.err import MyError

    # Positional Arguments
    #    --option 0,end,10,20,20,30,#000, ...
    # Keyword Arguments
    #    --option start=0,dur=end,x1=10, ...

    KEYWORD_SEP = "="
    kwargs: dict[str, Any] = {}

    def go(text: str, c: Any) -> Any:
        try:
            env = _env if isinstance(_env, Env) else Env(_env)
            results = interpret(env, Parser(Lexer(build.name, text)))
        except MyError as e:
            raise ParserError(e)

        if not results:
            raise ParserError("Results must be of length > 0")

        if c(results[-1]) is not True:
            raise ParserError(
                f"{build.name}: Expected {c.name}, got {print_str(results[-1])}"
            )

        return results[-1]

    for attr in build.attrs:
        kwargs[_norm_name(attr.n)] = attr.default

    allow_positional_args = True

    lexer = PLexer(text)
    i = 0
    while (arg := lexer.get_next_token()) is not None:
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
                    more = (
                        f"\n    attributes available:\n        {', '.join(all_names)}"
                    )

                raise ParserError(
                    f"{build.name} got an unexpected attribute '{key}'\n{more}"
                )

        elif allow_positional_args:
            kwargs[_norm_name(build.attrs[i].n)] = go(arg, build.attrs[i].contract)
        else:
            raise ParserError(
                f"{build.name} positional argument follows keyword argument."
            )
        i += 1

    for k, v in kwargs.items():
        if v is Required:
            raise ParserError(f"'{k}' must be specified.")

    return kwargs


def parse_method(
    name: str, text: str, env: Env
) -> tuple[str, list[Any], dict[str, Any]]:
    from auto_editor.lang.palet import Lexer, Parser, interpret
    from auto_editor.lib.err import MyError

    # Positional Arguments
    #    audio:0.04,0,6,3
    # Keyword Arguments
    #    audio:threshold=0.04,stream=0,mincut=6,minclip=3

    args: list[Any] = []
    kwargs: dict[str, Any] = {}

    allow_positional_args = True
    lexer = PLexer(text)
    while (arg := lexer.get_next_token()) is not None:
        if not arg:
            continue

        if "=" in arg:
            key, val = arg.split("=", 1)

            results = interpret(env, Parser(Lexer(name, val)))
            if not results:
                raise MyError("Results must be of length > 0")

            kwargs[key] = results[-1]
            allow_positional_args = False

        elif allow_positional_args:
            results = interpret(env, Parser(Lexer(name, arg)))
            if not results:
                raise MyError("Results must be of length > 0")
            args.append(results[-1])
        else:
            raise ParserError(f"{name} positional argument follows keyword argument.")

    return name, args, kwargs
