"""
Palet is a light-weight scripting languge. It handles `--edit` and the `repl`.
The syntax is inspired by the Racket Programming language.
"""

from __future__ import annotations

from dataclasses import dataclass
from difflib import get_close_matches
from fractions import Fraction
from io import StringIO
from typing import TYPE_CHECKING, cast

import numpy as np

from auto_editor.analyze import LevelError, Levels, mut_remove_small
from auto_editor.lib.contracts import *
from auto_editor.lib.data_structs import *
from auto_editor.lib.err import MyError
from auto_editor.utils.func import boolop

if TYPE_CHECKING:
    from collections.abc import Callable
    from typing import Any, NoReturn, TypeGuard

    from numpy.typing import NDArray

    Node = tuple


class ClosingError(MyError):
    pass


###############################################################################
#                                                                             #
#  LEXER                                                                      #
#                                                                             #
###############################################################################

LPAREN, RPAREN, LBRAC, RBRAC, LCUR, RCUR, EOF = "(", ")", "[", "]", "{", "}", "EOF"
VAL, QUOTE, SEC, DB, DOT, VLIT, M = "VAL", "QUOTE", "SEC", "DB", "DOT", "VLIT", "M"
SEC_UNITS = ("s", "sec", "secs", "second", "seconds")
brac_pairs = {LPAREN: RPAREN, LBRAC: RBRAC, LCUR: RCUR}

str_escape = {
    "a": "\a",
    "b": "\b",
    "t": "\t",
    "n": "\n",
    "v": "\v",
    "f": "\f",
    "r": "\r",
    '"': '"',
    "\\": "\\",
}


@dataclass(slots=True)
class Token:
    type: str
    value: Any
    lineno: int
    column: int


class Lexer:
    __slots__ = (
        "filename",
        "text",
        "allow_lang_prag",
        "pos",
        "char",
        "lineno",
        "column",
    )

    def __init__(self, filename: str, text: str, langprag: bool = False):
        self.filename = filename
        self.text = text
        self.allow_lang_prag = langprag
        self.pos: int = 0
        self.lineno: int = 1
        self.column: int = 1
        self.char: str | None = self.text[self.pos] if text else None

    def error(self, msg: str) -> NoReturn:
        raise MyError(f"{msg}\n  at {self.filename}:{self.lineno}:{self.column}")

    def close_err(self, msg: str) -> NoReturn:
        raise ClosingError(f"{msg}\n  at {self.filename}:{self.lineno}:{self.column}")

    def char_is_norm(self) -> bool:
        return self.char is not None and self.char not in '()[]{}"; \t\n\r\x0b\x0c'

    def advance(self) -> None:
        if self.char == "\n":
            self.lineno += 1
            self.column = 0

        self.pos += 1

        if self.pos > len(self.text) - 1:
            self.char = None
        else:
            self.char = self.text[self.pos]
            self.column += 1

    def peek(self) -> str | None:
        peek_pos = self.pos + 1
        return None if peek_pos > len(self.text) - 1 else self.text[peek_pos]

    def is_whitespace(self) -> bool:
        return self.char is None or self.char in " \t\n\r\x0b\x0c"

    def string(self) -> str:
        result = StringIO()
        while self.char is not None and self.char != '"':
            if self.char == "\\":
                self.advance()
                if self.char is None:
                    break

                if self.char not in str_escape:
                    self.error(f"Unknown escape sequence `\\{self.char}` in string")

                result.write(str_escape[self.char])
            else:
                result.write(self.char)
            self.advance()

        if self.char is None:
            self.close_err('Expected a closing `"`')

        self.advance()
        return result.getvalue()

    def number(self) -> Token:
        buf = StringIO()
        token = VAL

        while self.char is not None and self.char in "+-0123456789./":
            buf.write(self.char)
            self.advance()

        result = buf.getvalue()
        del buf

        unit = ""
        if self.char_is_norm():
            while self.char_is_norm():
                assert self.char is not None
                unit += self.char
                self.advance()

            if unit in SEC_UNITS:
                token = SEC
            elif unit == "dB":
                token = DB
            elif unit != "i" and unit != "%":
                return Token(
                    VAL,
                    Sym(result + unit, self.lineno, self.column),
                    self.lineno,
                    self.column,
                )

        try:
            if unit == "i":
                return Token(VAL, complex(result + "j"), self.lineno, self.column)
            elif unit == "%":
                return Token(VAL, float(result) / 100, self.lineno, self.column)
            elif "/" in result:
                return Token(token, Fraction(result), self.lineno, self.column)
            elif "." in result:
                return Token(token, float(result), self.lineno, self.column)
            else:
                return Token(token, int(result), self.lineno, self.column)
        except ValueError:
            return Token(
                VAL,
                Sym(result + unit, self.lineno, self.column),
                self.lineno,
                self.column,
            )

    def hash_literal(self) -> Token:
        if self.char == "\\":
            self.advance()
            if self.char is None:
                self.close_err("Expected a character after #\\")

            char = self.char
            self.advance()
            return Token(VAL, Char(char), self.lineno, self.column)

        if self.char == ":":
            self.advance()
            buf = StringIO()
            while self.char_is_norm():
                assert self.char is not None
                buf.write(self.char)
                self.advance()

            return Token(VAL, Keyword(buf.getvalue()), self.lineno, self.column)

        if self.char is not None and self.char in "([{":
            brac_type = self.char
            self.advance()
            if self.char is None:
                self.close_err(f"Expected a character after #{brac_type}")
            return Token(VLIT, brac_pairs[brac_type], self.lineno, self.column)

        buf = StringIO()
        while self.char_is_norm():
            assert self.char is not None
            buf.write(self.char)
            self.advance()

        result = buf.getvalue()
        if result in {"t", "T", "true"}:
            return Token(VAL, True, self.lineno, self.column)

        if result in {"f", "F", "false"}:
            return Token(VAL, False, self.lineno, self.column)

        self.error(f"Unknown hash literal `#{result}`")

    def get_next_token(self) -> Token:
        while self.char is not None:
            while self.char is not None and self.is_whitespace():
                self.advance()
            if self.char is None:
                continue

            if self.char == ";":
                while self.char is not None and self.char != "\n":
                    self.advance()
                continue

            if self.char == '"':
                self.advance()
                my_str = self.string()
                if self.char == ".":  # handle `object.method` syntax
                    self.advance()
                    return Token(
                        DOT, (my_str, self.get_next_token()), self.lineno, self.column
                    )
                return Token(VAL, my_str, self.lineno, self.column)

            if self.char == "'":
                self.advance()
                return Token(QUOTE, "'", self.lineno, self.column)

            if self.char in "(){}[]":
                _par = self.char
                self.advance()
                return Token(_par, _par, self.lineno, self.column)

            if self.char in "+-":
                _peek = self.peek()
                if _peek is not None and _peek in "0123456789.":
                    return self.number()

            if self.char in "0123456789.":
                return self.number()

            if self.char == "#":
                self.advance()
                if self.char == "|":
                    success = False
                    while self.char is not None:
                        self.advance()

                        if self.char == "|" and self.peek() == "#":
                            self.advance()
                            self.advance()
                            success = True
                            break

                    if not success and self.char is None:
                        self.close_err("no closing `|#` for `#|` comment")
                    continue

                elif self.char == "!" and self.peek() == "/":
                    self.advance()
                    self.advance()
                    while self.char is not None and self.char != "\n":
                        self.advance()
                    if self.char is None or self.char == "\n":
                        continue

                elif self.char == "l" and self.peek() == "a":
                    buf = StringIO()
                    while self.char_is_norm():
                        assert self.char is not None
                        buf.write(self.char)
                        self.advance()

                    result = buf.getvalue()
                    if result != "lang":
                        self.error(f"Unknown hash literal `#{result}`")
                    if not self.allow_lang_prag:
                        self.error("#lang pragma is not allowed here")

                    self.advance()
                    buf = StringIO()
                    while not self.is_whitespace():
                        assert self.char is not None
                        buf.write(self.char)
                        self.advance()

                    result = buf.getvalue()
                    if result != "palet":
                        self.error(f"Invalid #lang: {result}")
                    self.allow_lang_prag = False
                    continue
                else:
                    return self.hash_literal()

            result = ""
            has_illegal = False

            def normal() -> bool:
                return (
                    self.char is not None
                    and self.char not in '.()[]{}"; \t\n\r\x0b\x0c'
                )

            def handle_strings() -> bool:
                nonlocal result
                if self.char == '"':
                    self.advance()
                    result = f'{result}"{self.string()}"'
                    return handle_strings()
                else:
                    return self.char_is_norm()

            is_method = False
            while normal():
                if self.char == ":":
                    name = result
                    result = ""
                    is_method = True
                    normal = handle_strings
                else:
                    result += self.char

                if self.char in "'`|\\":
                    has_illegal = True
                self.advance()

            if is_method:
                from auto_editor.utils.cmdkw import parse_method

                return Token(M, parse_method(name, result), self.lineno, self.column)

            if self.char == ".":  # handle `object.method` syntax
                self.advance()
                return Token(
                    DOT,
                    (Sym(result, self.lineno, self.column), self.get_next_token()),
                    self.lineno,
                    self.column,
                )

            if has_illegal:
                self.error(f"Symbol has illegal character(s): {result}")

            return Token(
                VAL, Sym(result, self.lineno, self.column), self.lineno, self.column
            )

        return Token(EOF, "EOF", self.lineno, self.column)


###############################################################################
#                                                                             #
#  PARSER                                                                     #
#                                                                             #
###############################################################################


class Parser:
    def __init__(self, lexer: Lexer):
        self.lexer = lexer
        self.current_token = self.lexer.get_next_token()

    def eat(self) -> None:
        self.current_token = self.lexer.get_next_token()

    def expr(self) -> Any:
        token = self.current_token
        lineno, column = token.lineno, token.column

        if token.type == VAL:
            self.eat()
            return token.value

        if token.type == VLIT:
            self.eat()
            literal_vec = []
            while self.current_token.type != token.value:
                literal_vec.append(self.expr())
                if self.current_token.type == EOF:
                    raise ClosingError("Unclosed vector literal")
            self.eat()
            return literal_vec

        # Handle unhygienic macros in next four cases
        if token.type == SEC:
            self.eat()
            return (Sym("round"), (Sym("*"), token.value, Sym("timebase")))

        if token.type == DB:
            self.eat()
            return (Sym("pow"), 10, (Sym("/"), token.value, 20))

        if token.type == M:
            self.eat()
            name, args, kwargs = token.value
            _result = [Sym(name, lineno, column)] + args
            for key, val in kwargs.items():
                _result.append(Keyword(key))
                _result.append(val)

            return tuple(_result)

        if token.type == DOT:
            self.eat()
            if type(token.value[1].value) is not Sym:
                raise MyError(". macro: attribute call needs to be an identifier")

            return (Sym("@r"), token.value[0], token.value[1].value)

        if token.type == QUOTE:
            self.eat()
            return (Sym("quote", lineno, column), self.expr())

        if token.type in brac_pairs:
            self.eat()
            closing = brac_pairs[token.type]
            childs = []
            while self.current_token.type != closing:
                if self.current_token.type == EOF:
                    raise ClosingError(f"Expected closing `{closing}` before end")
                childs.append(self.expr())

            self.eat()
            return tuple(childs)

        self.eat()
        childs = []
        while self.current_token.type not in {RPAREN, RBRAC, RCUR, EOF}:
            childs.append(self.expr())
        return tuple(childs)

    def __str__(self) -> str:
        result = str(self.expr())

        self.lexer.pos = 0
        self.lexer.char = self.lexer.text[0]
        self.current_token = self.lexer.get_next_token()

        return result


###############################################################################
#                                                                             #
#  ENVIRONMENT                                                                #
#                                                                             #
###############################################################################


class Syntax:
    __slots__ = "syn"

    def __init__(self, syn: Callable[[Env, Node], Any]):
        self.syn = syn

    def __call__(self, env: Env, node: Node) -> Any:
        return self.syn(env, node)

    def __str__(self) -> str:
        return "#<syntax>"

    __repr__ = __str__


def ref(seq: Any, ref: int) -> Any:
    try:
        if type(seq) is str:
            return Char(seq[ref])
        if isinstance(seq, np.ndarray) and seq.dtype == np.bool_:
            return int(seq[ref])
        return seq[ref]
    except (KeyError, IndexError, TypeError):
        raise MyError(f"ref: Invalid key: {print_str(ref)}")


def p_slice(
    seq: str | list | range | NDArray,
    start: int = 0,
    end: int | None = None,
    step: int = 1,
) -> Any:
    if end is None:
        end = len(seq)

    return seq[start:end:step]


def is_boolean_array(v: object) -> TypeGuard[np.ndarray]:
    return isinstance(v, np.ndarray) and v.dtype.kind == "b"


is_iterable = Contract(
    "iterable?",
    lambda v: type(v) in {str, range, list, tuple, dict, Quoted}
    or isinstance(v, np.ndarray),
)
is_boolarr = Contract("bool-array?", is_boolean_array)


def raise_(msg: str | Exception) -> NoReturn:
    raise MyError(msg)


def edit_none() -> np.ndarray:
    if "@levels" not in env:
        raise MyError("Can't use `none` if there's no input media")

    return env["@levels"].none()


def edit_all() -> np.ndarray:
    if "@levels" not in env:
        raise MyError("Can't use `all/e` if there's no input media")

    return env["@levels"].all()


def audio_levels(stream: int) -> np.ndarray:
    if "@levels" not in env:
        raise MyError("Can't use `audio` if there's no input media")

    try:
        return env["@levels"].audio(stream)
    except LevelError as e:
        raise MyError(e)


def motion_levels(stream: int, blur: int = 9, width: int = 400) -> np.ndarray:
    if "@levels" not in env:
        raise MyError("Can't use `motion` if there's no input media")

    try:
        return env["@levels"].motion(stream, blur, width)
    except LevelError as e:
        raise MyError(e)


def edit_audio(
    threshold: float = 0.04,
    stream: object = Sym("all"),
    mincut: int = 6,
    minclip: int = 3,
) -> np.ndarray:
    if "@levels" not in env:
        raise MyError("Can't use `audio` if there's no input media")

    levels = cast(Levels, env["@levels"])
    stream_data: NDArray[np.bool_] | None = None
    if stream == Sym("all"):
        stream_range = range(0, len(levels.container.streams.audio))
    else:
        assert isinstance(stream, int)
        stream_range = range(stream, stream + 1)

    try:
        for s in stream_range:
            audio_list = levels.audio(s) >= threshold
            if stream_data is None:
                stream_data = audio_list
            else:
                stream_data = boolop(stream_data, audio_list, np.logical_or)
    except LevelError:
        return np.array([], dtype=np.bool_)

    if stream_data is None:
        return np.array([], dtype=np.bool_)

    mut_remove_small(stream_data, minclip, replace=1, with_=0)
    mut_remove_small(stream_data, mincut, replace=0, with_=1)
    return stream_data


def edit_motion(
    threshold: float = 0.02,
    stream: int = 0,
    blur: int = 9,
    width: int = 400,
) -> np.ndarray:
    if "@levels" not in env:
        raise MyError("Can't use `motion` if there's no input media")

    levels = cast(Levels, env["@levels"])
    try:
        return levels.motion(stream, blur, width) >= threshold
    except LevelError:
        return np.array([], dtype=np.bool_)


def edit_subtitle(pattern, stream=0, **kwargs):
    if "@levels" not in env:
        raise MyError("Can't use `subtitle` if there's no input media")

    levels = cast(Levels, env["@levels"])
    if "ignore-case" not in kwargs:
        kwargs["ignore-case"] = False
    if "max-count" not in kwargs:
        kwargs["max-count"] = None
    ignore_case = kwargs["ignore-case"]
    max_count = kwargs["max-count"]
    try:
        return levels.subtitle(pattern, stream, ignore_case, max_count)
    except LevelError:
        return np.array([], dtype=np.bool_)


class StackTraceManager:
    __slots__ = ("stack",)

    def __init__(self) -> None:
        self.stack: list[Sym] = []

    def push(self, sym: Sym) -> None:
        self.stack.append(sym)

    def pop(self) -> None:
        if self.stack:
            self.stack.pop()


stack_trace_manager = StackTraceManager()


def my_eval(env: Env, node: object) -> Any:
    def make_trace(sym: object) -> str:
        return f"  at {sym.val} ({sym.lineno}:{sym.column})" if type(sym) is Sym else ""

    if type(node) is Sym:
        val = env.get(node.val)
        if type(val) is NotFound:
            stacktrace = make_trace(node)
            if mat := get_close_matches(node.val, env.data):
                raise MyError(
                    f"variable `{node.val}` not found. Did you mean: {mat[0]}\n{stacktrace}"
                )
            raise MyError(
                f"variable `{node.val}` not found. Did you mean a string literal.\n{stacktrace}"
            )
        return val

    if type(node) is list:
        return [my_eval(env, item) for item in node]

    if type(node) is tuple:
        if not node:
            raise MyError("Illegal () expression")

        oper = my_eval(env, node[0])
        if isinstance(node[0], Sym):
            stack_trace_manager.push(node[0])

        try:
            if not callable(oper):
                """
                ...No one wants to write (aref a x y) when they could write a[x,y].
                In this particular case there is a way to finesse our way out of the
                problem. If we treat data structures as if they were functions on indexes,
                we could write (a x y) instead, which is even shorter than the Perl form.
                """
                if is_iterable(oper):
                    length = len(node[1:])
                    if length > 3:
                        raise MyError(f"{print_str(node[0])}: slice expects 1 argument")
                    if length in {2, 3}:
                        return p_slice(oper, *(my_eval(env, c) for c in node[1:]))
                    if length == 1:
                        return ref(oper, my_eval(env, node[1]))

                raise MyError(
                    f"{print_str(oper)} is not a function. Tried to run with args: {print_str(node[1:])}"
                )

            if type(oper) is Syntax:
                return oper(env, node)

            i = 1
            args: list[Any] = []
            kwargs: dict[str, Any] = {}
            while i < len(node):
                result = my_eval(env, node[i])
                if type(result) is Keyword:
                    i += 1
                    if i >= len(node):
                        raise MyError("Keyword need argument")
                    kwargs[result.val] = my_eval(env, node[i])
                else:
                    args.append(result)
                i += 1

            return oper(*args, **kwargs)
        except MyError as e:
            error_msg = str(e)
            if not error_msg.endswith(make_trace(node[0])):
                error_msg += f"\n{make_trace(node[0])}"
            raise MyError(error_msg)
        finally:
            if isinstance(node[0], Sym):
                stack_trace_manager.pop()

    return node


# fmt: off
env = Env({})
env.update({
    "none": Proc("none", edit_none, (0, 0)),
    "all/e": Proc("all/e", edit_all, (0, 0)),
    "audio-levels": Proc("audio-levels", audio_levels, (1, 1), is_nat),
    "audio": Proc("audio", edit_audio, (0, 4),
        is_threshold, orc(is_nat, Sym("all")), is_nat,
        {"threshold": 0, "stream": 1, "minclip": 2, "mincut": 2}
    ),
    "motion-levels": Proc("motion-levels", motion_levels, (1, 3), is_nat, is_nat1, {"blur": 1, "width": 2}),
    "motion": Proc("motion", edit_motion, (0, 4),
        is_threshold, is_nat, is_nat1,
        {"threshold": 0, "stream": 1, "blur": 1, "width": 2}
    ),
    "subtitle": Proc("subtitle", edit_subtitle, (1, 4),
        is_str, is_nat, is_bool, orc(is_nat, is_void),
        {"pattern": 0, "stream": 1, "ignore-case": 2, "max-count": 3}
    ),
})
# fmt: on


def interpret(env: Env, parser: Parser) -> list[object]:
    result = []

    try:
        while parser.current_token.type != EOF:
            result.append(my_eval(env, parser.expr()))

            if type(result[-1]) is Keyword:
                raise MyError(f"Keyword misused in expression. `{result[-1]}`")
    except RecursionError:
        raise MyError("maximum recursion depth exceeded")
    return result
