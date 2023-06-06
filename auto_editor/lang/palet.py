"""
Palet is a light-weight scripting languge. It handles `--edit` and the `repl`.
The syntax is inspired by the Racket Programming language.
"""


from __future__ import annotations

import cmath
import math
import random
from difflib import get_close_matches
from fractions import Fraction
from functools import reduce
from io import StringIO
from typing import TYPE_CHECKING

import numpy as np

from auto_editor.analyze import edit_method, mut_remove_large, mut_remove_small
from auto_editor.lib.contracts import *
from auto_editor.lib.data_structs import *
from auto_editor.lib.err import MyError
from auto_editor.utils.func import boolop, mut_margin

if TYPE_CHECKING:
    from typing import Any, Callable, NoReturn, Union

    from numpy.typing import NDArray

    Number = Union[int, float, complex, Fraction]
    Real = Union[int, float, Fraction]
    BoolList = NDArray[np.bool_]
    Env = dict[str, Any]


class ClosingError(MyError):
    pass


###############################################################################
#                                                                             #
#  LEXER                                                                      #
#                                                                             #
###############################################################################

SEC_UNITS = ("s", "sec", "secs", "second", "seconds")
VAL, QUOTE, SEC, DB, PER, DOT = "VAL", "QUOTE", "SEC", "DB", "PER", "DOT"
LPAREN, RPAREN, LBRAC, RBRAC, LCUR, RCUR, EOF = "(", ")", "[", "]", "{", "}", "EOF"
VLIT, HASH_LIT = "VLIT", "HLIT"
METHODS = ("audio:", "motion:", "pixeldiff:", "subtitle:", "none:", "all/e:")
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


class Token:
    __slots__ = ("type", "value")

    def __init__(self, type: str, value: Any):
        self.type = type
        self.value = value

    def __str__(self) -> str:
        return f"(Token {print_str(self.type)} {print_str(self.value)})"

    __repr__ = __str__


class Lexer:
    __slots__ = ("filename", "text", "pos", "char", "lineno", "column")

    def __init__(self, filename: str, text: str):
        self.filename = filename
        self.text = text
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
            elif unit == "%":
                token = PER
            elif unit != "i":
                return Token(VAL, Sym(result + unit))

        try:
            if unit == "i":
                return Token(VAL, complex(result + "j"))
            elif "/" in result:
                val = Fraction(result)
                if val.denominator == 1:
                    return Token(token, val.numerator)
                return Token(token, val)
            elif "." in result:
                return Token(token, float(result))
            else:
                return Token(token, int(result))
        except ValueError:
            return Token(VAL, Sym(result + unit))

    def hash_literal(self) -> Token:
        if self.char == "\\":
            self.advance()
            if self.char is None:
                self.close_err("Expected a character after #\\")

            char = self.char
            self.advance()
            return Token(VAL, Char(char))

        if self.char is not None and self.char in "([{":
            brac_type = self.char
            self.advance()
            if self.char is None:
                self.close_err(f"Expected a character after #{brac_type}")
            return Token(VLIT, brac_pairs[brac_type])

        buf = StringIO()
        while self.char_is_norm():
            assert self.char is not None
            buf.write(self.char)
            self.advance()

        result = buf.getvalue()
        if result in ("t", "T", "true"):
            return Token(VAL, True)

        if result in ("f", "F", "false"):
            return Token(VAL, False)

        if result == "hash":
            self.advance()
            if self.char is None or self.char not in "([{":
                self.error("Expected an opening bracket after #hash")

            brac_type = self.char
            self.advance()
            if self.char is None:
                self.close_err(f"Expected a character after #{brac_type}")

            return Token(HASH_LIT, brac_type)

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
                    return Token(DOT, (my_str, self.get_next_token()))
                return Token(VAL, my_str)

            if self.char == "'":
                self.advance()
                return Token(QUOTE, "'")

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
                else:
                    return self.hash_literal()

            result = ""
            has_illegal = False
            is_method = False

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

            while normal():
                result += self.char
                if (result + ":") in METHODS:
                    is_method = True
                    normal = handle_strings

                if self.char in "'`|\\":
                    has_illegal = True
                self.advance()

            if is_method:
                return Token(VAL, Method(result))

            for method in METHODS:
                if result == method[:-1]:
                    return Token(VAL, Method(result))

            if self.char == ".":  # handle `object.method` syntax
                self.advance()
                return Token(DOT, (Sym(result), self.get_next_token()))

            if has_illegal:
                self.error(f"Symbol has illegal character(s): {result}")

            return Token(VAL, Sym(result))

        return Token(EOF, "EOF")


###############################################################################
#                                                                             #
#  PARSER                                                                     #
#                                                                             #
###############################################################################


class Method:
    __slots__ = "val"

    def __init__(self, val: str):
        self.val = val

    def __str__(self) -> str:
        return f'(Method "{self.val}")'

    __repr__ = __str__


class Parser:
    def __init__(self, lexer: Lexer):
        self.lexer = lexer
        self.current_token = self.lexer.get_next_token()

    def eat(self) -> None:
        self.current_token = self.lexer.get_next_token()

    def expr(self) -> Any:
        token = self.current_token

        if token.type == VAL:
            self.eat()
            return token.value

        if token.type == VLIT:
            lit_arr = []
            self.eat()
            while self.current_token.type != token.value:
                lit_arr.append(self.expr())
                if self.current_token.type == EOF:
                    raise ClosingError("Unclosed vector literal")
            self.eat()
            return [list, lit_arr]

        if token.type == SEC:
            self.eat()
            return [Sym("round"), [Sym("*"), token.value, Sym("timebase")]]

        if token.type == DB:
            self.eat()
            return [Sym("pow"), 10, [Sym("/"), token.value, 20]]

        if token.type == PER:
            self.eat()
            return [Sym("/"), token.value, 100.0]

        if token.type == DOT:
            self.eat()
            if type(token.value[1].value) is not Sym:
                raise MyError(". macro: attribute call needs to be an identifier")

            return [Sym("@r"), token.value[0], token.value[1].value]

        if token.type == QUOTE:
            self.eat()
            return [Sym("quote"), self.expr()]

        if token.type in brac_pairs:
            self.eat()
            closing = brac_pairs[token.type]
            childs = []
            while self.current_token.type != closing:
                if self.current_token.type == EOF:
                    raise ClosingError(f"Expected closing `{closing}` before end")
                childs.append(self.expr())

            self.eat()
            return childs

        self.eat()
        childs = []
        while self.current_token.type not in (RPAREN, RBRAC, RCUR, EOF):
            childs.append(self.expr())
        return childs

    def __str__(self) -> str:
        result = str(self.expr())

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
    o: str,
    values: list | tuple,
    arity: tuple[int, int | None],
    cont: list[Contract] | None,
) -> None:
    lower, upper = arity
    amount = len(values)
    if upper is not None and lower > upper:
        raise ValueError("lower must be less than upper")
    if lower == upper and len(values) != lower:
        raise MyError(f"{o}: Arity mismatch. Expected {lower}, got {amount}")

    if upper is None and amount < lower:
        raise MyError(f"{o}: Arity mismatch. Expected at least {lower}, got {amount}")
    if upper is not None and (amount > upper or amount < lower):
        raise MyError(
            f"{o}: Arity mismatch. Expected between {lower} and {upper}, got {amount}"
        )

    if cont is None:
        return

    for i, val in enumerate(values):
        check = cont[-1] if i >= len(cont) else cont[i]
        if not check_contract(check, val):
            raise MyError(f"{o} expected a {check.name}, got {print_str(val)}")


is_cont = Contract("contract?", is_contract)
is_iterable = Contract(
    "iterable?",
    lambda v: type(v) in (str, range) or isinstance(v, (list, dict, np.ndarray)),
)
is_sequence = Contract(
    "sequence?",
    lambda v: type(v) in (str, range) or isinstance(v, (list, np.ndarray)),
)
is_boolarr = Contract(
    "bool-array?",
    lambda v: isinstance(v, np.ndarray) and v.dtype.kind == "b",
)
bool_or_barr = Contract(
    "(or/c bool? bool-array?)",
    lambda v: type(v) is bool or is_boolarr(v),
)


def is_equal(a: object, b: object) -> bool:
    if isinstance(a, np.ndarray) and isinstance(b, np.ndarray):
        return np.array_equal(a, b)
    return type(a) == type(b) and a == b


def equal_num(*values: object) -> bool:
    return all(values[0] == val for val in values[1:])


def mul(*vals: Any) -> Number:
    return reduce(lambda a, b: a * b, vals, 1)


def minus(*vals: Number) -> Number:
    if len(vals) == 1:
        return -vals[0]
    return reduce(lambda a, b: a - b, vals)


def num_div(z: Number, *w: Number) -> Number:
    if len(w) == 0:
        w = (z,)
        z = 1

    for num in w:
        if num == 0:
            raise MyError("/: division by zero")

        if type(num) is int:
            num = Fraction(num)

        z /= num

    if type(z) is Fraction and z.denominator == 1:
        return z.numerator
    return z


def int_div(n: int, *m: int) -> int:
    if 0 in m:
        raise MyError("div: division by zero")

    return reduce(lambda a, b: a // b, m, n)


def _sqrt(v: Number) -> Number:
    r = cmath.sqrt(v)
    if r.imag == 0:
        if int(r.real) == r.real:
            return int(r.real)
        return r.real
    return r


def _xor(*vals: Any) -> bool | BoolList:
    if is_boolarr(vals[0]):
        check_args("xor", vals, (2, None), [is_boolarr])
        return reduce(lambda a, b: boolop(a, b, np.logical_xor), vals)
    check_args("xor", vals, (2, None), [is_bool])
    return reduce(lambda a, b: a ^ b, vals)


def string_append(*vals: str | Char) -> str:
    return reduce(lambda a, b: a + b, vals, "")


def vector_append(*vals: list) -> list:
    return reduce(lambda a, b: a + b, vals, [])


def string_ref(s: str, ref: int) -> Char:
    try:
        return Char(s[ref])
    except IndexError:
        raise MyError(f"string index {ref} is out of range")


def number_to_string(val: Number) -> str:
    if isinstance(val, complex):
        join = "" if val.imag < 0 else "+"
        return f"{val.real}{join}{val.imag}i"
    return f"{val}"


dtype_map = {
    Sym("bool"): np.bool_,
    Sym("int8"): np.int8,
    Sym("int16"): np.int16,
    Sym("int32"): np.int32,
    Sym("int64"): np.int64,
    Sym("uint8"): np.uint8,
    Sym("uint16"): np.uint16,
    Sym("uint32"): np.uint32,
    Sym("uint64"): np.uint64,
    Sym("float32"): np.float32,
    Sym("float64"): np.float64,
}


def _dtype_to_np(dtype: Sym) -> type[np.generic]:
    np_dtype = dtype_map.get(dtype)
    if np_dtype is None:
        raise MyError(f"Invalid array dtype: {dtype}")
    return np_dtype


def array_proc(dtype: Sym, *vals: Any) -> np.ndarray:
    try:
        return np.array(vals, dtype=_dtype_to_np(dtype))
    except OverflowError:
        raise MyError(f"number too large to be converted to {dtype}")


def make_array(dtype: Sym, size: int, v: int = 0) -> np.ndarray:
    try:
        return np.array([v] * size, dtype=_dtype_to_np(dtype))
    except OverflowError:
        raise MyError(f"number too large to be converted to {dtype}")


def minclip(oarr: BoolList, _min: int) -> BoolList:
    arr = np.copy(oarr)
    mut_remove_small(arr, _min, replace=1, with_=0)
    return arr


def mincut(oarr: BoolList, _min: int) -> BoolList:
    arr = np.copy(oarr)
    mut_remove_small(arr, _min, replace=0, with_=1)
    return arr


def maxclip(oarr: BoolList, _min: int) -> BoolList:
    arr = np.copy(oarr)
    mut_remove_large(arr, _min, replace=1, with_=0)
    return arr


def maxcut(oarr: BoolList, _min: int) -> BoolList:
    arr = np.copy(oarr)
    mut_remove_large(arr, _min, replace=0, with_=1)
    return arr


def margin(a: int, b: Any, c: Any = None) -> BoolList:
    if c is None:
        check_args("margin", [a, b], (2, 2), [is_int, is_boolarr])
        oarr = b
        start, end = a, a
    else:
        check_args("margin", [a, b, c], (3, 3), [is_int, is_int, is_boolarr])
        oarr = c
        start, end = a, b

    arr = np.copy(oarr)
    mut_margin(arr, start, end)
    return arr


def vector_set(vec: list, pos: int, v: Any) -> None:
    try:
        vec[pos] = v
    except IndexError:
        raise MyError(f"vector-set: Invalid index {pos}")


def vector_extend(vec: list, *more_vecs: list) -> None:
    for more in more_vecs:
        vec.extend(more)


def randrange(*args: int) -> int:
    try:
        return random.randrange(*args)
    except ValueError:
        raise MyError("randrange: got empty range")


def palet_map(proc: Proc, seq: str | list | range | NDArray) -> Any:
    if type(seq) is str:
        return str(map(proc.proc, seq))
    if isinstance(seq, (list, range)):
        return list(map(proc.proc, seq))

    if isinstance(seq, np.ndarray):
        if proc.arity[0] != 0:
            raise MyError("map: procedure must take at least one arg")
        check_args(proc.name, [0], (1, 1), None)
        return proc.proc(seq)


def apply(proc: Proc, seq: str | list | range) -> Any:
    return reduce(proc.proc, seq)


def ref(seq: Any, ref: int) -> Any:
    try:
        if type(seq) is str:
            return Char(seq[ref])
        if isinstance(seq, np.ndarray) and seq.dtype == np.bool_:
            return int(seq[ref])
        return seq[ref]
    except KeyError:
        raise MyError(f"ref: Invalid key: {print_str(ref)}")
    except IndexError:
        raise MyError(f"ref: Invalid index: {print_str(ref)}")


def p_slice(
    seq: str | list | range | NDArray,
    start: int = 0,
    end: int | None = None,
    step: int = 1,
) -> Any:
    if end is None:
        end = len(seq)

    return seq[start:end:step]


def splice(
    arr: NDArray, v: int, start: int | None = None, end: int | None = None
) -> None:
    arr[start:end] = v


def palet_hash(*args: Any) -> dict:
    result = {}
    if len(args) % 2 == 1:
        raise MyError("hash: number of args must be even")
    for key, item in zip(args[0::2], args[1::2]):
        result[key] = item
    return result


def palet_assert(expr: object, msg: str | bool = False) -> None:
    if expr is not True:
        raise MyError("AssertError" if msg is False else f"AssertError: {msg}")


###############################################################################
#                                                                             #
#  ENVIRONMENT                                                                #
#                                                                             #
###############################################################################


class UserProc(Proc):
    """A user-defined procedure."""

    __slots__ = ("parms", "body", "name", "arity", "contracts")

    def __init__(
        self,
        name: str,
        parms: list,
        body: list,
        contracts: list[Any] | None = None,
        eat_last: bool = False,
    ):
        self.parms = [f"{p}" for p in parms]
        self.body = body
        self.name = name

        if eat_last:
            self.arity: tuple[int, int | None] = len(parms) - 1, None
        else:
            self.arity = len(parms), len(parms)

        self.contracts = contracts

    def __call__(self, *args: Any) -> Any:
        saved_env: Env = {}
        for item in self.parms:
            if item in env:
                saved_env[item] = env[item]

        if self.arity[1] is None:
            largs = list(args)
            args = tuple([largs[len(self.parms) - 1 :]])

        env.update(zip(self.parms, args))
        for item in self.body[0:-1]:
            my_eval(env, item)
        result = my_eval(env, self.body[-1])

        for item in self.parms:
            del env[item]
        env.update(saved_env)
        return result


class Syntax:
    __slots__ = "syn"

    def __init__(self, syn: Callable[[Env, list], Any]):
        self.syn = syn

    def __call__(self, env: Env, node: list) -> Any:
        return self.syn(env, node)

    def __str__(self) -> str:
        return "#<syntax>"

    __repr__ = __str__


def check_for_syntax(env: Env, node: list) -> tuple[Sym, Any]:
    name = node[0]
    if len(node) < 2:
        raise MyError(f"{name}: bad syntax")

    if len(node) == 2:
        raise MyError(f"{name}: missing body")

    assert isinstance(node[1], list)
    assert isinstance(node[1][0], list)

    var = node[1][0][0]
    if type(var) is not Sym:
        raise MyError(f"{name}: binding must be an identifier")
    my_iter = my_eval(env, node[1][0][1])

    if not is_iterable(my_iter):
        if type(my_iter) is int:
            return var, range(my_iter)
        raise MyError(f"{name}: got non-iterable in iter slot")

    return var, my_iter


def syn_lambda(env: Env, node: list) -> UserProc:
    if not isinstance(node[1], list):
        raise MyError(f"{node[0]}: bad syntax")

    return UserProc("", node[1], node[2:])  # parms, body


def syn_define(env: Env, node: list) -> None:
    if len(node) < 3:
        raise MyError(f"{node[0]}: too few args")

    if isinstance(node[1], list):
        if not node[1] or type(node[1][0]) is not Sym:
            raise MyError(f"{node[0]}: proc-binding must be an identifier")

        n = node[1][0].val

        eat_last = False
        if node[1][1:] and node[1][-1] == Sym("..."):
            eat_last = True
            parameters = node[1][1:-1]
        else:
            parameters = node[1][1:]

        body = node[2:]
        env[n] = UserProc(n, parameters, body, eat_last=eat_last)
        return None
    elif type(node[1]) is not Sym:
        raise MyError(f"{node[0]}: must be an identifier")

    n = node[1].val

    if len(node) > 3:
        raise MyError(f"{node[0]}: bad syntax (multiple expressions after identifier)")

    if (
        isinstance(node[2], list)
        and node[2]
        and type(node[2][0]) is Sym
        and node[2][0].val in ("lambda", "λ")
    ):
        parameters = node[2][1]
        body = node[2][2:]
        env[n] = UserProc(n, parameters, body)
    else:
        for item in node[2:-1]:
            my_eval(env, item)
        env[n] = my_eval(env, node[-1])

    return None


def syn_definec(env: Env, node: list) -> None:
    if len(node) < 3:
        raise MyError(f"{node[0]}: bad syntax")

    if not isinstance(node[1], list):
        raise MyError(f"{node[0]} only allows procedure declarations")

    if not node[1] or type(node[1][0]) is not Sym:
        raise MyError(f"{node[0]}: bad proc-binding syntax")

    n = node[1][0].val

    contracts: list[Proc | Contract] = []
    parameters: list[Sym] = []
    for item in node[1][1:]:
        if len(item) != 2:
            raise MyError(f"{node[0]}: bad var-binding syntax")
        if type(item[0]) is not Sym:
            raise MyError(f"{node[0]}: binding must be identifier")

        parameters.append(item[0])
        con = my_eval(env, item[1])
        if not is_cont(con):
            raise MyError(f"{node[0]}: {print_str(con)} is not a valid contract")

        contracts.append(con)

    env[n] = UserProc(n, parameters, node[2:], contracts)
    return None


def syn_set(env: Env, node: list) -> None:
    if len(node) != 3:
        raise MyError(f"{node[0]}: bad syntax")
    if type(node[1]) is not Sym:
        raise MyError(f"{node[0]} expected identifier, got {print_str(node[1])}")

    name = node[1].val
    if name not in env:
        raise MyError(f"{node[0]}: cannot set variable {name} before definition")
    env[name] = my_eval(env, node[2])
    return None


def syn_for(env: Env, node: list) -> None:
    var, my_iter = check_for_syntax(env, node)

    if isinstance(my_iter, np.ndarray) and my_iter.dtype == np.bool_:
        for item in my_iter:
            env[var.val] = int(item)
            for c in node[2:]:
                my_eval(env, c)
    else:
        for item in my_iter:
            env[var.val] = item
            for c in node[2:]:
                my_eval(env, c)

    return None


def syn_quote(env: Env, node: list) -> list:
    if len(node) != 2:
        raise MyError("quote: bad syntax")
    return node[1]


def syn_if(env: Env, node: list) -> Any:
    if len(node) != 4:
        raise MyError(f"{node[0]}: bad syntax")
    test_expr = my_eval(env, node[1])

    if type(test_expr) is not bool:
        raise MyError(
            f"{node[0]} test-expr: expected bool?, got {print_str(test_expr)}"
        )

    return my_eval(env, node[2] if test_expr else node[3])


def syn_when(env: Env, node: list) -> Any:
    if len(node) < 3:
        raise MyError(f"{node[0]}: bad syntax")
    test_expr = my_eval(env, node[1])

    if type(test_expr) is not bool:
        raise MyError(
            f"{node[0]} test-expr: expected bool?, got {print_str(test_expr)}"
        )

    if test_expr:
        for item in node[2:-1]:
            my_eval(env, item)
        return my_eval(env, node[-1])
    return None


def syn_and(env: Env, node: list) -> Any:
    if len(node) == 1:
        raise MyError(f"{node[0]}: Arity mismatch: Expected 1. got 0")

    first = my_eval(env, node[1])
    if first is False:
        return False
    if first is True:
        for n in node[2:]:
            val = my_eval(env, n)
            if val is False:
                return False
            if val is not True:
                raise MyError(f"{node[0]} args must be bool?")
        return True

    if is_boolarr(first):
        vals = [first] + [my_eval(env, n) for n in node[2:]]
        check_args(node[0], vals, (2, None), [is_boolarr])
        return reduce(lambda a, b: boolop(a, b, np.logical_and), vals)

    raise MyError(f"{node[0]} expects (or/c bool? bool-array?)")


def syn_or(env: Env, node: list) -> Any:
    if len(node) == 1:
        raise MyError(f"{node[0]}: Arity mismatch: Expected 1. got 0")

    first = my_eval(env, node[1])
    if first is True:
        return True
    if first is False:
        for n in node[2:]:
            val = my_eval(env, n)
            if val is True:
                return True
            if val is not False:
                raise MyError(f"{node[0]} args must be bool?")
        return False

    if is_boolarr(first):
        vals = [first] + [my_eval(env, n) for n in node[2:]]
        check_args(node[0], vals, (2, None), [is_boolarr])
        return reduce(lambda a, b: boolop(a, b, np.logical_or), vals)

    raise MyError(f"{node[0]} expects (or/c bool? bool-array?)")


class PaletObject:
    __slots__ = "attributes"

    def __init__(self, attrs: dict[str, Any]):
        self.attributes = attrs


is_obj = Contract(
    "object?",
    lambda v: type(v) is str or isinstance(v, (list, Proc, PaletObject)),
)


def get_attrs(obj: Any) -> dict[str, Any]:
    if type(obj) is str:
        return {
            "@name": "string",
            "@len": Proc("@len", obj.__len__, (0, 0)),
            "split": Proc("split", obj.split, (0, 1), [is_str]),
            "strip": Proc("strip", obj.strip, (0, 0)),
            "repeat": Proc("repeat", lambda a: obj * a, (1, 1), [is_int]),
            "startswith": Proc("startswith", obj.startswith, (1, 1), [is_str]),
            "endswith": Proc("endswith", obj.endswith, (1, 1), [is_str]),
            "replace": Proc("replace", obj.replace, (2, 3), [is_str, is_str, is_int]),
            "title": Proc("title", obj.title, (0, 0)),
            "lower": Proc("lower", obj.lower, (0, 0)),
            "upper": Proc("upper", obj.upper, (0, 0)),
        }
    if isinstance(obj, list):
        return {
            "@name": "vector",
            "@len": Proc("@len", obj.__len__, (0, 0)),
            "repeat": Proc("repeat", lambda a: obj * a, (1, 1), [is_int]),
            "pop": Proc("pop", obj.pop, (0, 0)),
            "sort": Proc("sort", lambda: sorted(obj), (0, 0)),
            "sort!": Proc("sort!", obj.sort, (0, 0)),
        }
    if isinstance(obj, PaletObject):
        return obj.attributes
    raise MyError("")


def attr(env: Env, node: list) -> Any:
    if len(node) != 3:
        raise MyError("@r: not enough args")

    if not isinstance(node[2], Sym):
        raise MyError("@r: attribute must be an identifier")
    my_attr = node[2].val
    my_obj = my_eval(env, node[1])

    try:
        attrs = get_attrs(my_obj)
    except MyError:
        raise MyError(f"@r: expected an object, got {print_str(my_obj)}")
    if my_attr not in attrs:
        if mat := get_close_matches(my_attr, attrs):
            raise MyError(f"@r: No such attribute: '{my_attr}'. Did you mean: {mat[0]}")
        raise MyError(f"@r: No such attribute: '{my_attr}'")
    return attrs[my_attr]


def my_eval(env: Env, node: object) -> Any:
    if type(node) is Sym:
        val = env.get(node.val)
        if val is None:
            if mat := get_close_matches(node.val, env):
                raise MyError(f"'{node.val}' not found. Did you mean: {mat[0]}")
            raise MyError(f"'{node.val}' not found.")
        return val

    if isinstance(node, Method):
        if "@filesetup" not in env:
            raise MyError("Can't use edit methods if there's no input files")
        return edit_method(node.val, env["@filesetup"], env)

    if isinstance(node, list):
        if not node:
            raise MyError("Illegal () expression")

        if node[0] is list:  # Handle vector literal
            return [my_eval(env, item) for item in node[1]]

        oper = my_eval(env, node[0])
        if not callable(oper):
            """
            ...No one wants to write (aref a x y) when they could write a[x,y].
            In this particular case there is a way to finesse our way out of the
            problem. If we treat data structures as if they were functions on indexes,
            we could write (a x y) instead, which is even shorter than the Perl form.
            """
            if is_iterable(oper):
                values = [my_eval(env, c) for c in node[1:]]
                if len(values) > 3:
                    raise MyError(f"{print_str(node[0])}: slice expects 1 argument")
                if len(values) in (2, 3):
                    return p_slice(oper, *values)
                if len(values) == 1:
                    return ref(oper, *values)

            raise MyError(f"{print_str(oper)}, expected procedure")

        if type(oper) is Syntax:
            return oper(env, node)

        values = [my_eval(env, c) for c in node[1:]]
        if type(oper) is Contract:
            check_args(oper.name, values, (1, 1), None)
        else:
            check_args(oper.name, values, oper.arity, oper.contracts)
        return oper(*values)

    return node


env: Env = {
    # constants
    "true": True,
    "false": False,
    "all": Sym("all"),
    # syntax
    "lambda": Syntax(syn_lambda),
    "λ": Syntax(syn_lambda),
    "define": Syntax(syn_define),
    "define/c": Syntax(syn_definec),
    "set!": Syntax(syn_set),
    "quote": Syntax(syn_quote),
    "if": Syntax(syn_if),
    "when": Syntax(syn_when),
    # loops
    "for": Syntax(syn_for),
    # contracts
    "number?": is_num,
    "real?": is_real,
    "int?": is_int,
    "uint?": is_uint,
    "nat?": is_nat,
    "float?": is_float,
    "frac?": is_frac,
    "threshold?": is_threshold,
    "any": any_p,
    "bool?": is_bool,
    "void?": is_void,
    "symbol?": (is_symbol := Contract("symbol?", lambda v: type(v) is Sym)),
    "string?": is_str,
    "char?": (is_char := Contract("char?", lambda v: type(v) is Char)),
    "vector?": (is_vector := Contract("vector?", lambda v: isinstance(v, list))),
    "array?": (is_array := Contract("array?", lambda v: isinstance(v, np.ndarray))),
    "bool-array?": is_boolarr,
    "range?": (is_range := Contract("range?", lambda v: type(v) is range)),
    "iterable?": is_iterable,
    "sequence?": is_sequence,
    "procedure?": is_proc,
    "contract?": is_cont,
    "hash?": (is_hash := Contract("hash?", lambda v: isinstance(v, dict))),
    "begin": Proc("begin", lambda *x: x[-1] if x else None, (0, None)),
    "void": Proc("void", lambda *v: None, (0, 0)),
    # control / b-arrays
    "not": Proc(
        "not",
        lambda v: not v if type(v) is bool else np.logical_not(v),
        (1, 1),
        [bool_or_barr],
    ),
    "and": Syntax(syn_and),
    "or": Syntax(syn_or),
    "xor": Proc("xor", _xor, (2, None), [bool_or_barr]),
    # booleans
    ">": Proc(">", lambda a, b: a > b, (2, 2), [is_real, is_real]),
    ">=": Proc(">=", lambda a, b: a >= b, (2, 2), [is_real, is_real]),
    "<": Proc("<", lambda a, b: a < b, (2, 2), [is_real, is_real]),
    "<=": Proc("<=", lambda a, b: a <= b, (2, 2), [is_real, is_real]),
    "=": Proc("=", equal_num, (1, None), [is_num]),
    "eq?": Proc("eq?", lambda a, b: a is b, (2, 2)),
    "equal?": Proc("equal?", is_equal, (2, 2)),
    "zero?": UserProc("zero?", ["z"], [[Sym("="), Sym("z"), 0]], [is_num]),
    "positive?": UserProc("positive?", ["x"], [[Sym(">"), Sym("x"), 0]], [is_real]),
    "negative?": UserProc("negative?", ["x"], [[Sym("<"), Sym("x"), 0]], [is_real]),
    "even?": UserProc(
        "even?", ["n"], [[Sym("zero?"), [Sym("mod"), Sym("n"), 2]]], [is_int]
    ),
    "odd?": UserProc("odd?", ["n"], [[Sym("not"), [Sym("even?"), Sym("n")]]], [is_int]),
    ">=/c": Proc(">=/c", gte_c, (1, 1), [is_real]),
    ">/c": Proc(">/c", gt_c, (1, 1), [is_real]),
    "<=/c": Proc("<=/c", lte_c, (1, 1), [is_real]),
    "</c": Proc("</c", lt_c, (1, 1), [is_real]),
    "between/c": Proc("between/c", between_c, (2, 2), [is_real, is_real]),
    # numbers
    "+": Proc("+", lambda *v: sum(v), (0, None), [is_num]),
    "-": Proc("-", minus, (1, None), [is_num]),
    "*": Proc("*", mul, (0, None), [is_num]),
    "/": Proc("/", num_div, (1, None), [is_num]),
    "div": Proc("div", int_div, (2, None), [is_int]),
    "add1": Proc("add1", lambda z: z + 1, (1, 1), [is_num]),
    "sub1": Proc("sub1", lambda z: z - 1, (1, 1), [is_num]),
    "sqrt": Proc("sqrt", _sqrt, (1, 1), [is_num]),
    "real-part": Proc("real-part", lambda v: v.real, (1, 1), [is_num]),
    "imag-part": Proc("imag-part", lambda v: v.imag, (1, 1), [is_num]),
    # reals
    "pow": Proc("pow", pow, (2, 2), [is_real]),
    "exp": Proc("exp", math.exp, (1, 1), [is_real]),
    "abs": Proc("abs", abs, (1, 1), [is_real]),
    "ceil": Proc("ceil", math.ceil, (1, 1), [is_real]),
    "floor": Proc("floor", math.floor, (1, 1), [is_real]),
    "round": Proc("round", round, (1, 1), [is_real]),
    "max": Proc("max", lambda *v: max(v), (1, None), [is_real]),
    "min": Proc("min", lambda *v: min(v), (1, None), [is_real]),
    "sin": Proc("sin", math.sin, (1, 1), [is_real]),
    "cos": Proc("cos", math.cos, (1, 1), [is_real]),
    "log": Proc("log", math.log, (1, 2), [is_real, is_real]),
    "tan": Proc("tan", math.tan, (1, 1), [is_real]),
    "mod": Proc("mod", lambda a, b: a % b, (2, 2), [is_int]),
    "modulo": Proc("modulo", lambda a, b: a % b, (2, 2), [is_int]),
    # symbols
    "symbol->string": Proc("symbol->string", str, (1, 1), [is_symbol]),
    "string->symbol": Proc("string->symbol", Sym, (1, 1), [is_str]),
    # strings
    "string": Proc("string", string_append, (0, None), [is_char]),
    "string-append": Proc("string-append", string_append, (0, None), [is_str]),
    "char->int": Proc("char->int", lambda c: ord(c.val), (1, 1), [is_char]),
    "int->char": Proc("int->char", Char, (1, 1), [is_int]),
    "~a": Proc("~a", lambda *v: "".join([display_str(a) for a in v]), (0, None)),
    "~s": Proc("~s", lambda *v: " ".join([display_str(a) for a in v]), (0, None)),
    "~v": Proc("~v", lambda *v: " ".join([print_str(a) for a in v]), (0, None)),
    # vectors
    "vector": Proc("vector", lambda *a: list(a), (0, None)),
    "make-vector": Proc(
        "make-vector", lambda size, a=0: [a] * size, (1, 2), [is_uint, any_p]
    ),
    "vector-append": Proc("vector-append", vector_append, (0, None), [is_vector]),
    "vector-pop!": Proc("vector-pop!", list.pop, (1, 1), [is_vector]),
    "vector-add!": Proc("vector-add!", list.append, (2, 2), [is_vector, any_p]),
    "vector-set!": Proc("vector-set!", vector_set, (3, 3), [is_vector, is_int, any_p]),
    "vector-extend!": Proc("vector-extend!", vector_extend, (2, None), [is_vector]),
    # arrays
    "array": Proc("array", array_proc, (2, None), [is_symbol, is_real]),
    "make-array": Proc("make-array", make_array, (2, 3), [is_symbol, is_uint, is_real]),
    "array-splice!": Proc(
        "array-splice!", splice, (2, 4), [is_array, is_real, is_int, is_int]
    ),
    "array-copy": Proc("array-copy", np.copy, (1, 1), [is_array]),
    "count-nonzero": Proc("count-nonzero", np.count_nonzero, (1, 1), [is_array]),
    # bool arrays
    "bool-array": Proc(
        "bool-array", lambda *a: np.array(a, dtype=np.bool_), (1, None), [is_uint]
    ),
    "margin": Proc("margin", margin, (2, 3), None),
    "mincut": Proc("mincut", mincut, (2, 2), [is_boolarr, is_uint]),
    "minclip": Proc("minclip", minclip, (2, 2), [is_boolarr, is_uint]),
    "maxcut": Proc("maxcut", maxcut, (2, 2), [is_boolarr, is_uint]),
    "maxclip": Proc("maxclip", maxclip, (2, 2), [is_boolarr, is_uint]),
    # ranges
    "range": Proc("range", range, (1, 3), [is_int, is_int, int_not_zero]),
    # generic iterables
    "len": Proc("len", len, (1, 1), [is_iterable]),
    "reverse": Proc("reverse", lambda v: v[::-1], (1, 1), [is_sequence]),
    "ref": Proc("ref", ref, (2, 2), [is_iterable, is_int]),
    "slice": Proc("slice", p_slice, (2, 4), [is_sequence, is_int]),
    # procedures
    "map": Proc("map", palet_map, (2, 2), [is_proc, is_sequence]),
    "apply": Proc("apply", apply, (2, 2), [is_proc, is_sequence]),
    "and/c": Proc("and/c", andc, (1, None), [is_cont]),
    "or/c": Proc("or/c", orc, (1, None), [is_cont]),
    "not/c": Proc("not/c", notc, (1, 1), [is_cont]),
    # hashs
    "hash": Proc("hash", palet_hash),
    "has-key?": Proc("has-key?", lambda h, k: k in h, (2, 2), [is_hash, any_p]),
    # actions
    "assert": Proc("assert", palet_assert, (1, 2), [any_p, orc(is_str, False)]),
    "display": Proc("display", lambda v: print(display_str(v), end=""), (1, 1)),
    "displayln": Proc("displayln", lambda v: print(display_str(v)), (1, 1)),
    "print": Proc("print", lambda v: print(print_str(v), end=""), (1, 1)),
    "println": Proc("println", lambda v: print(print_str(v)), (1, 1)),
    # conversions
    "number->string": Proc("number->string", number_to_string, (1, 1), [is_num]),
    "string->vector": Proc(
        "string->vector", lambda s: [Char(c) for c in s], (1, 1), [is_str]
    ),
    "range->vector": Proc("range->vector", list, (1, 1), [is_range]),
    # objects
    "object?": is_obj,
    "attrs": Proc("attrs", lambda v: list(get_attrs(v).keys()), (1, 1), [is_obj]),
    "@r": Syntax(attr),
}


def interpret(env: Env, parser: Parser) -> list:
    result = []
    while parser.current_token.type != EOF:
        result.append(my_eval(env, parser.expr()))
    return result
