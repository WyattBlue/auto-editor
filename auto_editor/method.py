from __future__ import annotations

from dataclasses import dataclass
from typing import TYPE_CHECKING

import numpy as np

from auto_editor.analyze import (
    audio_levels,
    get_all,
    get_none,
    motion_levels,
    pixeldiff_levels,
    random_levels,
    to_threshold,
)
from auto_editor.objects import Attr, _Vars, parse_dataclass
from auto_editor.utils.types import Stream, db_threshold, natural, stream, threshold

if TYPE_CHECKING:
    from fractions import Fraction
    from typing import Any, Callable

    from numpy.typing import NDArray

    from auto_editor.ffwrapper import FileInfo
    from auto_editor.output import Ensure
    from auto_editor.utils.bar import Bar
    from auto_editor.utils.log import Log

    BoolList = NDArray[np.bool_]
    BoolOperand = Callable[[BoolList, BoolList], BoolList]


@dataclass
class Audio:
    threshold: float
    stream: Stream


@dataclass
class Motion:
    threshold: float
    stream: int
    blur: int
    width: int


@dataclass
class Pixeldiff:
    threshold: int
    stream: int


@dataclass
class Random:
    threshold: float
    seed: int


audio_builder = [
    Attr(("threshold",), db_threshold, 0.04),
    Attr(("stream", "track"), stream, 0),
]
motion_builder = [
    Attr(("threshold",), threshold, 0.02),
    Attr(("stream", "track"), natural, 0),
    Attr(("blur",), natural, 9),
    Attr(("width",), natural, 400),
]
pixeldiff_builder = [
    Attr(("threshold",), natural, 1),
    Attr(("stream", "track"), natural, 0),
]
random_builder = [Attr(("threshold",), threshold, 0.5), Attr(("seed",), int, -1)]


def operand_combine(a: BoolList, b: BoolList, call: BoolOperand) -> BoolList:
    if len(a) > len(b):
        b = np.resize(b, len(a))
    if len(b) > len(a):
        a = np.resize(a, len(b))

    return call(a, b)


###############################################################################
#                                                                             #
#  LEXER                                                                      #
#                                                                             #
###############################################################################

NOT, OR, AND, XOR = "NOT", "OR", "AND", "XOR"
ARR, LPAREN, RPAREN, EOF = "ARR", "(", ")", "EOF"
METHODS = ("audio", "motion", "pixeldiff", "random", "none", "all")
METHOD_ATTRS_SEP = ":"
whitespace = " _\t\n\r\x0b\x0c"
abc = "0123456789abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ!\"#$%&'*+,-./:;<=>?@\\^`|~"


class Token:
    __slots__ = ("type", "value")

    def __init__(self, type: str, value: Any):
        self.type = type
        self.value = value

    def __str__(self) -> str:
        return self.value

    def __repr__(self):
        return self.__str__()


class Lexer:
    __slots__ = ("log", "text", "pos", "current_char")

    def __init__(self, text: str, log: Log):
        self.log = log
        self.text = text
        self.pos: int = 0
        self.current_char: str | None = self.text[self.pos]

    def advance(self) -> None:
        self.pos += 1
        if self.pos > len(self.text) - 1:
            self.current_char = None
        else:
            self.current_char = self.text[self.pos]

    def skip_whitespace(self) -> None:
        while self.current_char is not None and self.current_char in whitespace:
            self.advance()

    def word(self) -> tuple[str, str]:
        result = ""
        while self.current_char is not None and self.current_char in abc:
            result += self.current_char
            self.advance()

        if result == "not":
            return NOT, "!"
        if result == "or":
            return OR, "||"
        if result == "and":
            return AND, "&&"
        if result == "xor":
            return XOR, "^"

        for method in METHODS:
            if result.startswith(method):
                return ARR, result

        self.log.error(f"Unknown method/operator: '{result}'")

    def get_next_token(self) -> Token:
        while self.current_char is not None:
            if self.current_char in whitespace:
                self.skip_whitespace()
                continue

            if self.current_char in abc:
                return Token(*self.word())

            if self.current_char == "(":
                self.advance()
                return Token(LPAREN, "(")

            if self.current_char == ")":
                self.advance()
                return Token(RPAREN, ")")

            raise ValueError(self.current_char)

        return Token(EOF, "EOF")


###############################################################################
#                                                                             #
#  PARSER                                                                     #
#                                                                             #
###############################################################################


class Node:
    pass


class UnOp(Node):
    __slots__ = ("value", "op")

    def __init__(self, value: Any, op: Any):
        self.value = value
        self.op = op

    def __str__(self) -> str:
        return f"({self.op} {self.value})"


class BinOp(Node):
    __slots__ = ("left", "op", "right")

    def __init__(self, left: Any, op: Any, right: Any):
        self.left = left
        self.op = op
        self.right = right

    def __str__(self) -> str:
        return f"({self.left} {self.op} {self.right})"


class ArrObj(Node):
    __slots__ = "val"

    def __init__(self, val: str):
        self.val = val

    def __str__(self) -> str:
        return self.val


class Parser:
    __slots__ = ("lexer", "log", "current_token")

    def __init__(self, lexer: Lexer, log: Log):
        self.lexer = lexer
        self.log = log
        self.current_token = self.lexer.get_next_token()

    def eat(self, token_type: str) -> None:
        if self.current_token.type != token_type:
            raise ValueError(f"{self.current_token.type}, {token_type}")

        nt = self.lexer.get_next_token()

        if self.current_token.type == ARR and nt.type in (ARR, LPAREN):
            self.log.error("Operator must be between two editing methods")
        self.current_token = nt

    def factor(self) -> Node | None:
        token = self.current_token
        if token.type == ARR:
            self.eat(ARR)
            return ArrObj(token.value)

        if token.type == LPAREN:
            self.eat(LPAREN)
            node = self.expr()
            self.eat(RPAREN)
            return node

        return None

    def term(self) -> Node | None:
        # High predicent operations
        node = self.factor()

        while self.current_token.type == NOT:
            token = self.current_token
            self.eat(NOT)
            node = UnOp(value=self.term(), op=token)

        return node

    def expr(self) -> Node | None:
        # Low precident operations
        node = self.term()

        while self.current_token.type in (OR, AND, XOR):
            token = self.current_token
            if token.type == OR:
                self.eat(OR)
            elif token.type == AND:
                self.eat(AND)
            elif token.type == XOR:
                self.eat(XOR)

            node = BinOp(left=node, op=token, right=self.term())

        return node

    def __str__(self) -> str:
        result = str(self.expr())

        self.lexer.pos = 0
        self.lexer.current_char = self.lexer.text[0]
        self.current_token = self.lexer.get_next_token()

        return result


###############################################################################
#                                                                             #
#  INTERPRETER                                                                #
#                                                                             #
###############################################################################


class Interpreter:
    def __init__(
        self,
        parser: Parser,
        src: FileInfo,
        ensure: Ensure,
        strict: bool,
        tb: Fraction,
        bar: Bar,
        temp: str,
        log: Log,
    ):

        self.parser = parser
        self.src = src
        self.ensure = ensure
        self.strict = strict
        self.tb = tb
        self.bar = bar
        self.temp = temp
        self.log = log

    def visit(self, node: UnOp | BinOp | ArrObj | None) -> BoolList | None:
        log = self.log

        if isinstance(node, UnOp):
            if (val := self.visit(node.value)) is None:
                log.error(
                    f"'{node.op.type.lower()}' operator needs right hand expression"
                )
            return np.logical_not(val)

        if isinstance(node, BinOp):
            left = self.visit(node.left)
            right = self.visit(node.right)

            if left is None or right is None:
                operator = node.op.type.lower()

                if left is None and right is None:
                    log.error(
                        f"'{operator}' operator needs left and right hand expression"
                    )
                if left is None:
                    log.error(f"'{operator}' operator needs left hand expression")
                log.error(f"'{operator}' operator needs right hand expression")

            if node.op.type == OR:
                return operand_combine(left, right, np.logical_or)
            if node.op.type == AND:
                return operand_combine(left, right, np.logical_and)
            if node.op.type == XOR:
                return operand_combine(left, right, np.logical_xor)

        if isinstance(node, ArrObj):
            src, ensure, strict, tb = self.src, self.ensure, self.strict, self.tb
            bar, temp = self.bar, self.temp

            if METHOD_ATTRS_SEP in node.val:
                method, attrs = node.val.split(METHOD_ATTRS_SEP)
                if method not in METHODS:
                    log.error(f"'{method}' not allowed to have attributes")
            else:
                method, attrs = node.val, ""

            if method == "none":
                return get_none(ensure, src, tb, temp, log)

            if method == "all":
                return get_all(ensure, src, tb, temp, log)

            if method == "random":
                robj = parse_dataclass(attrs, (Random, random_builder), log)
                return to_threshold(
                    random_levels(ensure, src, robj, tb, temp, log), robj.threshold
                )

            if method == "audio":
                aobj = parse_dataclass(attrs, (Audio, audio_builder), log)
                s = aobj.stream
                if s == "all":
                    total_list: NDArray[np.bool_] | None = None
                    for s in range(len(src.audios)):
                        audio_list = to_threshold(
                            audio_levels(ensure, src, s, tb, bar, strict, temp, log),
                            aobj.threshold,
                        )
                        if total_list is None:
                            total_list = audio_list
                        else:
                            total_list = operand_combine(
                                total_list, audio_list, np.logical_or
                            )
                    if total_list is None:
                        if strict:
                            log.error("Input has no audio streams.")
                        stream_data = get_all(ensure, src, tb, temp, log)
                    else:
                        stream_data = total_list
                else:
                    stream_data = to_threshold(
                        audio_levels(ensure, src, s, tb, bar, strict, temp, log),
                        aobj.threshold,
                    )

                return stream_data

            if method == "motion":
                if src.videos:
                    _vars: _Vars = {"width": src.videos[0].width}
                else:
                    _vars = {"width": 1}

                mobj = parse_dataclass(attrs, (Motion, motion_builder), log, _vars)
                return to_threshold(
                    motion_levels(ensure, src, mobj, tb, bar, strict, temp, log),
                    mobj.threshold,
                )

            if method == "pixeldiff":
                pobj = parse_dataclass(attrs, (Pixeldiff, pixeldiff_builder), log)
                return to_threshold(
                    pixeldiff_levels(ensure, src, pobj, tb, bar, strict, temp, log),
                    pobj.threshold,
                )

            raise ValueError("Unreachable")

        return None

    def interpret(self):
        tree = self.parser.expr()
        result = self.visit(tree)

        assert result is not None
        return result


def get_has_loud(
    text: str,
    src: FileInfo,
    ensure: Ensure,
    strict: bool,
    tb: Fraction,
    bar: Bar,
    temp: str,
    log: Log,
) -> BoolList:

    lexer = Lexer(text, log)
    parser = Parser(lexer, log)

    if log.debug:
        log.debug(f"edit: {parser}")

    interpreter = Interpreter(parser, src, ensure, strict, tb, bar, temp, log)
    return interpreter.interpret()
