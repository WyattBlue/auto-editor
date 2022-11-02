from __future__ import annotations

import cmath
import math
import sys
from dataclasses import dataclass
from fractions import Fraction
from functools import reduce
from typing import TYPE_CHECKING

import numpy as np

from auto_editor.analyze import edit_method
from auto_editor.utils.func import apply_margin, boolop, cook, remove_small

if TYPE_CHECKING:
    from fractions import Fraction
    from typing import Any, Callable, Union

    from numpy.typing import NDArray

    from auto_editor.ffwrapper import FileInfo
    from auto_editor.output import Ensure
    from auto_editor.utils.bar import Bar
    from auto_editor.utils.log import Log

    Node = Union[Compound, ManyOp, Var, Num, Str, Bool, BoolArr]
    Number = Union[int, float, complex, Fraction]
    Real = Union[int, float, Fraction]
    BoolList = NDArray[np.bool_]


class MyError(Exception):
    pass


class CharType:
    __slots__ = "val"

    def __init__(self, val: str):
        assert len(val) == 1
        self.val = val

    __str__: Callable[[CharType], str] = lambda self: self.val

    def __repr__(self) -> str:
        names = {" ": "space", "\n": "newline", "\t": "tab"}
        return f"#\\{self.val}" if self.val not in names else f"#\\{names[self.val]}"

    def __radd__(self, obj2: str) -> str:
        return obj2 + self.val


def print_arr(arr: BoolList) -> str:
    rs = "(boolarr"
    for item in arr:
        rs += " 1" if item else " 0"
    rs += ")\n"
    return rs


def is_boolarr(arr: object) -> bool:
    """boolarr?"""
    if isinstance(arr, np.ndarray):
        return arr.dtype.kind == "b"
    return False


def is_bool(val: object) -> bool:
    """boolean?"""
    return isinstance(val, bool)


def is_num(val: object) -> bool:
    """number?"""
    return not isinstance(val, bool) and isinstance(
        val, (int, float, Fraction, complex)
    )


def is_real(val: object) -> bool:
    """real?"""
    return not isinstance(val, bool) and isinstance(val, (int, float, Fraction))


def exact_int(val: object) -> bool:
    """exact-integer?"""
    return not isinstance(val, bool) and isinstance(val, int)


def is_exact(val: object) -> bool:
    """exact?"""
    return isinstance(val, (int, Fraction))


def is_str(val: object) -> bool:
    """string?"""
    return isinstance(val, str)


def is_char(val: object) -> bool:
    """char?"""
    return isinstance(val, CharType)


###############################################################################
#                                                                             #
#  LEXER                                                                      #
#                                                                             #
###############################################################################

METHODS = ("audio", "motion", "pixeldiff", "random", "none", "all")
SEC_UNITS = ("s", "sec", "secs", "second", "seconds")
ID, NUM, BOOL, STR, ARR, SEC, CHAR = "ID", "NUM", "BOOL", "STR", "ARR", "SEC", "CHAR"
LPAREN, RPAREN, LBRAC, RBRAC, LCUR, RCUR, EOF = "(", ")", "[", "]", "{", "}", "EOF"


class Token:
    __slots__ = ("type", "value")

    def __init__(self, type: str, value: Any):
        self.type = type
        self.value = value

    __str__: Callable[[Token], str] = lambda self: f"(Token {self.type} {self.value})"


class Lexer:
    __slots__ = ("log", "text", "pos", "char")

    def __init__(self, text: str):
        self.text = text
        self.pos: int = 0
        if len(text) == 0:
            self.char: str | None = None
        else:
            self.char = self.text[self.pos]

    def char_is_norm(self) -> bool:
        return self.char is not None and self.char not in '()[]{}"; \t\n\r\x0b\x0c'

    def advance(self) -> None:
        self.pos += 1
        if self.pos > len(self.text) - 1:
            self.char = None
        else:
            self.char = self.text[self.pos]

    def peek(self) -> str | None:
        peek_pos = self.pos + 1
        if peek_pos > len(self.text) - 1:
            return None
        else:
            return self.text[peek_pos]

    def skip_whitespace(self) -> None:
        while self.char is not None and self.char in " \t\n\r\x0b\x0c":
            self.advance()

    def string(self) -> str:
        result = ""
        while self.char is not None and self.char != '"':
            if self.char == "\\":
                self.advance()
                if self.char in 'nt"\\':
                    if self.char == "n":
                        result += "\n"
                    if self.char == "t":
                        result += "\t"
                    if self.char == '"':
                        result += '"'
                    if self.char == "\\":
                        result += "\\"
                    self.advance()
                    continue

                if self.char is None:
                    raise MyError("Unexpected EOF while parsing")
                raise MyError(
                    f"Unexpected character {self.char} during escape sequence"
                )
            else:
                result += self.char
            self.advance()

        self.advance()
        return result

    def number(self) -> Token:
        result = ""
        token = NUM

        while self.char is not None and self.char in "+-0123456789./":
            result += self.char
            self.advance()

        unit = ""
        if self.char_is_norm():
            while self.char_is_norm():
                assert self.char is not None
                unit += self.char
                self.advance()

            if unit in SEC_UNITS:
                token = SEC
            elif unit != "i":
                return Token(ID, result + unit)

        if unit == "i":
            try:
                return Token(NUM, complex(result + "j"))
            except ValueError:
                return Token(ID, result + unit)

        if "/" in result:
            try:
                val = Fraction(result)
                if val.denominator == 1:
                    return Token(token, val.numerator)
                return Token(token, val)
            except ValueError:
                return Token(ID, result + unit)

        if "." in result:
            try:
                return Token(token, float(result))
            except ValueError:
                return Token(ID, result + unit)

        try:
            return Token(token, int(result))
        except ValueError:
            return Token(ID, result + unit)

    def hash_literal(self) -> Token:
        if self.char == "\\":
            self.advance()
            if self.char is None:
                raise MyError("Expected a character after #\\")

            char = self.char
            self.advance()
            return Token(CHAR, CharType(char))

        result = ""
        while self.char_is_norm():
            assert self.char is not None
            result += self.char
            self.advance()

        if result in ("t", "true"):
            return Token(BOOL, True)

        if result in ("f", "false"):
            return Token(BOOL, False)

        raise MyError(f"Unknown hash literal: {result}")

    def get_next_token(self) -> Token:
        while self.char is not None:
            self.skip_whitespace()
            if self.char is None:
                continue

            if self.char == ";":
                while self.char is not None and self.char != "\n":
                    self.advance()
                continue

            if self.char == '"':
                self.advance()
                return Token(STR, self.string())

            if self.char in "(){}[]":
                _par = self.char
                self.advance()
                return Token(_par, _par)

            if self.char in "+-":
                _peek = self.peek()
                if _peek is not None and _peek in "0123456789.":
                    return self.number()

            if self.char in "0123456789.":
                return self.number()

            if self.char == "#":
                self.advance()
                return self.hash_literal()

            result = ""
            has_illegal = False
            while self.char_is_norm():
                result += self.char
                if self.char in "'`|\\":
                    has_illegal = True
                self.advance()

            if has_illegal:
                raise MyError(f"Token has illegal character(s): {result}")

            for method in METHODS:
                if result == method or result.startswith(method + ":"):
                    return Token(ARR, result)

            return Token(ID, result)

        return Token(EOF, "EOF")


###############################################################################
#                                                                             #
#  PARSER                                                                     #
#                                                                             #
###############################################################################


class Compound:
    __slots__ = "children"

    def __init__(self, children: list[Node]):
        self.children = children

    def __str__(self) -> str:
        s = "{Compound"
        for child in self.children:
            s += f" {child}"
        s += "}"
        return s


class ManyOp:
    __slots__ = ("op", "children")

    def __init__(self, op: Node, children: list[Node]):
        self.op = op
        self.children = children

    def __str__(self) -> str:
        s = f"(ManyOp {self.op}"
        for child in self.children:
            s += f" {child}"
        s += ")"
        return s

    __repr__ = __str__


class Atom:
    pass


class Var(Atom):
    def __init__(self, token: Token):
        assert token.type == ID
        self.token = token
        self.value = token.value

    __str__: Callable[[Var], str] = lambda self: f"(Var {self.value})"


class Num(Atom):
    __slots__ = "val"

    def __init__(self, val: int | float | Fraction | complex):
        self.val = val

    __str__: Callable[[Num], str] = lambda self: f"(num {self.val})"


class Bool(Atom):
    __slots__ = "val"

    def __init__(self, val: bool):
        self.val = val

    __str__: Callable[[Bool], str] = lambda self: f"(bool {'#t' if self.val else '#f'})"


class Str(Atom):
    __slots__ = "val"

    def __init__(self, val: str):
        self.val = val

    __str__: Callable[[Str], str] = lambda self: f"(str {self.val})"


class Char(Atom):
    __slots__ = "val"

    def __init__(self, val: str):
        self.val = val

    __str__: Callable[[Char], str] = lambda self: f"(char {self.val})"


class BoolArr(Atom):
    __slots__ = "val"

    def __init__(self, val: str):
        self.val = val

    __str__: Callable[[BoolArr], str] = lambda self: f"(boolarr {self.val})"


class Parser:
    def __init__(self, lexer: Lexer):
        self.lexer = lexer
        self.current_token = self.lexer.get_next_token()

    def eat(self, token_type: str) -> None:
        if self.current_token.type != token_type:
            raise MyError(f"Expected {token_type}, got {self.current_token.type}")

        self.current_token = self.lexer.get_next_token()

    def comp(self) -> Compound:
        comp_kids = []
        while self.current_token.type not in (EOF, RPAREN, RBRAC, RCUR):
            comp_kids.append(self.expr())
        return Compound(comp_kids)

    def expr(self) -> Node:
        token = self.current_token

        if token.type == ID:
            self.eat(ID)
            return Var(token)

        matches = {ARR: BoolArr, BOOL: Bool, NUM: Num, STR: Str, CHAR: Char}
        if token.type in matches:
            self.eat(token.type)
            return matches[token.type](token.value)

        if token.type == SEC:
            self.eat(SEC)
            return ManyOp(
                Var(Token(ID, "exact-round")),
                [
                    ManyOp(
                        Var(Token(ID, "*")),
                        [Num(token.value), Var(Token(ID, "timebase"))],
                    )
                ],
            )

        if token.type == LPAREN:
            self.eat(token.type)
            childs = []
            while self.current_token.type != RPAREN:
                if self.current_token.type == EOF:
                    raise MyError("Unexpected EOF")
                childs.append(self.expr())

            self.eat(RPAREN)
            return ManyOp(childs[0], children=childs[1:])

        if token.type == LBRAC:
            self.eat(token.type)
            childs = []
            while self.current_token.type != RBRAC:
                if self.current_token.type == EOF:
                    raise MyError("Unexpected EOF")
                childs.append(self.expr())

            self.eat(RBRAC)
            return ManyOp(childs[0], children=childs[1:])

        if token.type == LCUR:
            self.eat(token.type)
            childs = []
            while self.current_token.type != RCUR:
                if self.current_token.type == EOF:
                    raise MyError("Unexpected EOF")
                childs.append(self.expr())

            self.eat(RCUR)
            return ManyOp(childs[0], children=childs[1:])

        self.eat(token.type)
        childs = []
        while self.current_token.type not in (RPAREN, RBRAC, RCUR, EOF):
            childs.append(self.expr())

        return ManyOp(childs[0], children=childs[1:])

    def __str__(self) -> str:
        result = str(self.comp())

        self.lexer.pos = 0
        self.lexer.char = self.lexer.text[0]
        self.current_token = self.lexer.get_next_token()

        return result


###############################################################################
#                                                                             #
#  STANDARD LIBRARY                                                           #
#                                                                             #
###############################################################################


def check_args(
    op: Token, values: list[Any], arity: tuple[int, int | None], types: list[Any] | None
) -> None:
    lower, upper = arity
    amount = len(values)
    o = op.value
    if upper is not None and lower > upper:
        raise ValueError("lower must be less than upper")
    if lower == upper:
        if len(values) != lower:
            raise MyError(f"{o}: Arity mismatch. Expected {lower}, got {amount}")

    if upper is None and amount < lower:
        raise MyError(f"{o}: Arity mismatch. Expected at least {lower}, got {amount}")
    if upper is not None and (amount > upper or amount < lower):
        raise MyError(
            f"{o}: Arity mismatch. Expected between {lower} and {upper}, got {amount}"
        )

    if types is None:
        return

    for i, val in enumerate(values):
        check = types[-1] if i >= len(types) else types[i]
        if not check(val):
            raise MyError(f"{o} expects: {' '.join([_t.__doc__ for _t in types])}")


def display(op: Token, values: list[Any]) -> None:
    check_args(op, values, (1, 1), None)
    if (val := values[0]) is None:
        return
    if is_boolarr(val):
        val = print_arr(val)
    sys.stdout.write(str(val))


def equalq(op: Token, values: list[Any]) -> bool:
    check_args(op, values, (2, 2), None)
    if isinstance(values[0], np.ndarray) or isinstance(values[1], np.ndarray):
        return np.array_equal(values[0], values[1])
    if isinstance(values[0], float) and not isinstance(values[1], float):
        return False
    if isinstance(values[1], float) and not isinstance(values[0], float):
        return False
    return values[0] == values[1]


def stringq(op: Token, values: list[Any]) -> bool:
    check_args(op, values, (1, 1), None)
    return is_str(values[0])


def exactq(op: Token, values: list[Any]) -> bool:
    check_args(op, values, (1, 1), [is_num])
    return is_exact(values[0])


def inexactq(op: Token, values: list[Any]) -> bool:
    check_args(op, values, (1, 1), [is_num])
    return not is_exact(values[0])


def numq(op: Token, values: list[Any]) -> bool:
    check_args(op, values, (1, 1), None)
    return is_num(values[0])


def realq(op: Token, values: list[Any]) -> bool:
    check_args(op, values, (1, 1), None)
    return is_real(values[0])


def intq(op: Token, values: list[Any]) -> bool:
    check_args(op, values, (1, 1), None)
    if isinstance(values[0], float):
        return values[0].is_integer()
    if isinstance(values[0], Fraction):
        return int(values[0]) == values[0]
    return isinstance(values[0], int)


def _exact_int(op: Token, values: list[Any]) -> bool:
    check_args(op, values, (1, 1), None)
    return exact_int(values[0])


def boolq(op: Token, values: list[Any]) -> bool:
    check_args(op, values, (1, 1), None)
    return is_bool(values[0])


def charq(op: Token, values: list[Any]) -> bool:
    check_args(op, values, (1, 1), None)
    return is_char(values[0])


def boolarrq(op: Token, values: list[Any]) -> bool:
    check_args(op, values, (1, 1), None)
    return is_boolarr(values[0])


def greater(op: Token, values: list[Any]) -> bool:
    check_args(op, values, (2, 2), [is_real, is_real])
    return values[0] > values[1]


def greater_equal(op: Token, values: list[Any]) -> bool:
    check_args(op, values, (2, 2), [is_real, is_real])
    return values[0] >= values[1]


def lesser(op: Token, values: list[Any]) -> bool:
    check_args(op, values, (2, 2), [is_real, is_real])
    return values[0] < values[1]


def lesser_equal(op: Token, values: list[Any]) -> bool:
    check_args(op, values, (2, 2), [is_real, is_real])
    return values[0] <= values[1]


def equal_num(op: Token, values: list[Any]) -> bool:
    check_args(op, values, (1, None), [is_num])
    return all(values[0] == val for val in values[1:])


def zero(op: Token, values: list[Any]) -> bool:
    check_args(op, values, (1, 1), [is_real])
    return values[0] == 0


def pos(op: Token, values: list[Any]) -> bool:
    check_args(op, values, (1, 1), [is_real])
    return values[0] > 0


def neg(op: Token, values: list[Any]) -> bool:
    check_args(op, values, (1, 1), [is_real])
    return values[0] < 0


def add1(op: Token, values: list[Any]) -> Number:
    check_args(op, values, (1, 1), [is_num])
    return values[0] + 1


def sub1(op: Token, values: list[Any]) -> Number:
    check_args(op, values, (1, 1), [is_num])
    return values[0] - 1


def plus(op: Token, values: list[Any]) -> Number:
    check_args(op, values, (0, None), [is_num])
    return sum(values)


def mul(op: Token, values: list[Any]) -> Number:
    check_args(op, values, (0, None), [is_num])
    return reduce(lambda a, b: a * b, values, 1)


def minus(op: Token, values: list[Any]) -> Number:
    check_args(op, values, (1, None), [is_num])
    if len(values) == 1:
        return -values[0]
    return reduce(lambda a, b: a - b, values)


def div(op: Token, values: list[Any]) -> Number:
    check_args(op, values, (1, None), [is_num])
    if len(values) == 1:
        values.insert(0, 1)
    try:
        if not {float, complex}.intersection({type(val) for val in values}):
            result = reduce(lambda a, b: Fraction(a, b), values)
            if result.denominator == 1:
                return result.numerator
            return result
        return reduce(lambda a, b: a / b, values)
    except ZeroDivisionError:
        raise MyError("division by zero")


def expt(op: Token, values: list[Any]) -> Real:
    check_args(op, values, (2, 2), [is_real])
    return pow(values[0], values[1])


def _sqrt(op: Token, values: list[Any]) -> Number:
    check_args(op, values, (1, 1), [is_num])
    result = cmath.sqrt(values[0])
    if result.imag == 0:
        _real = result.real
        if int(_real) == _real:
            return int(_real)
        return _real
    return result


def real_part(op: Token, values: list[Any]) -> Number:
    check_args(op, values, (1, 1), [is_num])
    return values[0].real


def imag_part(op: Token, values: list[Any]) -> Number:
    check_args(op, values, (1, 1), [is_num])
    return values[0].imag


def absolute(op: Token, values: list[Any]) -> Real:
    check_args(op, values, (1, 1), [is_real])
    return abs(values[0])


def ceiling(op: Token, values: list[Any]) -> Real:
    check_args(op, values, (1, 1), [is_real])
    if isinstance(values[0], float):
        return float(math.ceil(values[0]))
    return math.ceil(values[0])


def exact_ceiling(op: Token, values: list[Any]) -> int:
    check_args(op, values, (1, 1), [is_real])
    return math.ceil(values[0])


def floor(op: Token, values: list[Any]) -> Real:
    check_args(op, values, (1, 1), [is_real])
    if isinstance(values[0], float):
        return float(math.floor(values[0]))
    return math.floor(values[0])


def exact_floor(op: Token, values: list[Any]) -> int:
    check_args(op, values, (1, 1), [is_real])
    return math.floor(values[0])


def _round(op: Token, values: list[Any]) -> Real:
    check_args(op, values, (1, 1), [is_real])
    if isinstance(values[0], float):
        return float(round(values[0]))
    return round(values[0])


def exact_round(op: Token, values: list[Any]) -> int:
    check_args(op, values, (1, 1), [is_real])
    return round(values[0])


def modulo(op: Token, values: list[Any]) -> int:
    check_args(op, values, (2, 2), [exact_int, exact_int])
    return values[0] % values[1]


def _max(op: Token, values: list[Any]) -> Real:
    check_args(op, values, (1, None), [is_real])
    return max(values)


def _min(op: Token, values: list[Any]) -> Real:
    check_args(op, values, (1, None), [is_real])
    return min(values)


def _not(op: Token, values: list[Any]) -> bool | BoolList:
    check_args(op, values, (1, 1), None)
    if is_boolarr(val := values[0]):
        return np.logical_not(val)
    if is_bool(val):
        return not val
    raise MyError(f"{op.value} expects: boolean? or boolarr?")


def _and(op: Token, values: list[Any]) -> bool | BoolList:
    check_args(op, values, (1, None), None)
    if is_boolarr(values[0]):
        check_args(op, values, (2, None), [is_boolarr])
        return reduce(lambda a, b: boolop(a, b, np.logical_and), values)
    return reduce(lambda a, b: a and b, values)


def _or(op: Token, values: list[Any]) -> bool | BoolList:
    check_args(op, values, (1, None), None)
    if is_boolarr(values[0]):
        check_args(op, values, (2, None), [is_boolarr])
        return reduce(lambda a, b: boolop(a, b, np.logical_or), values)
    return reduce(lambda a, b: a or b, values)


def _xor(op: Token, values: list[Any]) -> bool | BoolList:
    check_args(op, values, (2, None), None)
    if is_boolarr(values[0]):
        check_args(op, values, (2, None), [is_boolarr])
        return reduce(lambda a, b: boolop(a, b, np.logical_xor), values)
    return reduce(lambda a, b: a ^ b, values)


def string_proc(op: Token, values: list[Any]) -> str:
    check_args(op, values, (0, None), [is_char])
    return reduce(lambda a, b: a + b, values, "")


def string_append(op: Token, values: list[Any]) -> str:
    check_args(op, values, (0, None), [is_str])
    return reduce(lambda a, b: a + b, values, "")


def string_upcase(op: Token, values: list[Any]) -> str:
    check_args(op, values, (1, 1), [is_str])
    return values[0].upper()


def string_downcase(op: Token, values: list[Any]) -> str:
    check_args(op, values, (1, 1), [is_str])
    return values[0].lower()


def string_titlecase(op: Token, values: list[Any]) -> str:
    check_args(op, values, (1, 1), [is_str])
    return values[0].title()


def string_length(op: Token, values: list[Any]) -> int:
    check_args(op, values, (1, 1), [is_str])
    return len(values[0])


def string_ref(op: Token, values: list[Any]) -> CharType:
    check_args(op, values, (2, 2), [is_str, is_real])
    try:
        return CharType(values[0][values[1]])
    except IndexError:
        raise MyError(f"string index {values[1]} is out of range")


def number_to_string(op: Token, values: list[Any]) -> str:
    check_args(op, values, (1, 1), [is_num])
    if isinstance(val := values[0], complex):
        join = "" if val.imag < 0 else "+"
        return f"{val.real}{join}{val.imag}i"
    return str(values[0])


def array_length(op: Token, values: list[Any]) -> int:
    check_args(op, values, (1, 1), [is_boolarr])
    return len(values[0])


def count_nonzero(op: Token, values: list[Any]) -> int:
    check_args(op, values, (1, 1), [is_boolarr])
    return np.count_nonzero(values[0])


def minclip(op: Token, values: list[Any]) -> BoolList:
    check_args(op, values, (2, 2), [exact_int, is_boolarr])
    return remove_small(np.copy(values[1]), values[0], replace=1, with_=0)


def mincut(op: Token, values: list[Any]) -> BoolList:
    check_args(op, values, (2, 2), [exact_int, is_boolarr])
    return remove_small(np.copy(values[1]), values[0], replace=0, with_=1)


def margin(op: Token, values: list[Any]) -> BoolList:
    if len(values) == 2:
        check_args(op, values, (2, 2), [exact_int, is_boolarr])
        arr = np.copy(values[1])
        return apply_margin(arr, len(arr), values[0], values[0])
    check_args(op, values, (3, 3), [exact_int, exact_int, is_boolarr])
    arr = np.copy(values[2])
    return apply_margin(arr, len(arr), values[0], values[1])


def _cook(op: Token, values: list[Any]) -> BoolList:
    check_args(op, values, (3, 3), [exact_int, exact_int, is_boolarr])
    return cook(np.copy(values[2]), values[1], values[0])


def boolarr_proc(op: Token, values: list[Any]) -> BoolList:
    check_args(op, values, (1, None), [exact_int])
    return np.array(values, dtype=np.bool_)


###############################################################################
#                                                                             #
#  INTERPRETER                                                                #
#                                                                             #
###############################################################################


@dataclass
class FileSetup:
    src: FileInfo
    ensure: Ensure
    strict: bool
    tb: Fraction
    bar: Bar
    temp: str
    log: Log


class Interpreter:

    GLOBAL_SCOPE: dict[str, Any] = {
        # constants
        "true": True,
        "false": False,
        "pi": math.pi,
        # actions
        "display": display,
        # booleans
        ">": greater,
        ">=": greater_equal,
        "<": lesser,
        "<=": lesser_equal,
        "=": equal_num,
        "not": _not,
        "and": _and,
        "or": _or,
        "xor": _xor,
        # questions
        "equal?": equalq,
        "number?": numq,
        "exact?": exactq,
        "inexact?": inexactq,
        "real?": realq,
        "integer?": intq,
        "exact-integer?": _exact_int,
        "positive?": pos,
        "negative?": neg,
        "zero?": zero,
        "boolean?": boolq,
        "string?": stringq,
        "char?": charq,
        # strings
        "string": string_proc,
        "string-append": string_append,
        "string-upcase": string_upcase,
        "string-downcase": string_downcase,
        "string-titlecase": string_titlecase,
        "string-length": string_length,
        "string-ref": string_ref,
        "number->string": number_to_string,
        # numbers
        "+": plus,
        "-": minus,
        "*": mul,
        "/": div,
        "add1": add1,
        "sub1": sub1,
        "expt": expt,
        "sqrt": _sqrt,
        "mod": modulo,
        "real-part": real_part,
        "imag-part": imag_part,
        # reals
        "abs": absolute,
        "ceiling": ceiling,
        "exact-ceiling": exact_ceiling,
        "floor": floor,
        "exact-floor": exact_floor,
        "round": _round,
        "exact-round": exact_round,
        "max": _max,
        "min": _min,
        # ae extensions
        "margin": margin,
        "mcut": mincut,
        "mincut": mincut,
        "mclip": minclip,
        "minclip": minclip,
        "cook": _cook,
        "boolarr": boolarr_proc,
        "array-length": array_length,
        "count-nonzero": count_nonzero,
        "boolarr?": boolarrq,
    }

    def __init__(self, parser: Parser, filesetup: FileSetup | None):
        self.parser = parser
        self.filesetup = filesetup

        if filesetup is not None:
            self.GLOBAL_SCOPE["timebase"] = filesetup.tb

    def visit(self, node: Node) -> Any:
        if isinstance(node, Atom):
            if isinstance(node, (Num, Str, Bool, Char)):
                return node.val

            if isinstance(node, Var):
                val = self.GLOBAL_SCOPE.get(node.value)
                if val is None:
                    raise MyError(f"{node.value} is undefined")
                return val

            if isinstance(node, BoolArr):
                if self.filesetup is None:
                    raise MyError("Can't use edit methods if there's no input files")
                return edit_method(node.val, self.filesetup)

            raise ValueError("Unreachable")

        if isinstance(node, ManyOp):
            if isinstance(node.op, Var):
                name: str | None = node.op.value
            else:
                name = None

            if name == "if":
                check_args(node.op, node.children, (3, 3), None)
                test_expr = self.visit(node.children[0])
                if not isinstance(test_expr, bool):
                    raise MyError(f"if: test-expr arg must be: boolean?")
                if test_expr:
                    return self.visit(node.children[1])
                return self.visit(node.children[2])

            if name == "when":
                check_args(node.op, node.children, (2, 2), None)
                test_expr = self.visit(node.children[0])
                if not isinstance(test_expr, bool):
                    raise MyError(f"when: test-expr arg must be: boolean?")
                if test_expr:
                    return self.visit(node.children[1])
                return None

            if name in ("define", "set!"):
                check_args(node.op, node.children, (2, 2), None)

                if not isinstance(node.children[0], Var):
                    raise MyError(
                        f"Variable must be set with a symbol, got {node.children[0]}"
                    )

                var_name = node.children[0].value
                if name == "set!" and var_name not in self.GLOBAL_SCOPE:
                    raise MyError(f"Cannot set variable {var_name} before definition")

                self.GLOBAL_SCOPE[var_name] = self.visit(node.children[1])
                return None

            if not callable(oper := self.visit(node.op)):
                raise MyError(f"{oper}, expected procedure")

            values = [self.visit(child) for child in node.children]
            return oper(Token(ID, str(oper)), values)

        if isinstance(node, Compound):
            results = []
            for child in node.children:
                results.append(self.visit(child))
            return results

        raise ValueError(f"Unknown node type: {node}")

    def interpret(self) -> Any:
        return self.visit(self.parser.comp())
