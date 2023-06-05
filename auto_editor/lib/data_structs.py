from __future__ import annotations

from fractions import Fraction
from io import StringIO

import numpy as np


class Sym:
    __slots__ = ("val", "hash")

    def __init__(self, val: str):
        self.val = val
        self.hash = hash(val)

    def __str__(self) -> str:
        return self.val

    __repr__ = __str__

    def __hash__(self) -> int:
        return self.hash

    def __eq__(self, obj: object) -> bool:
        return type(obj) is Sym and self.hash == obj.hash


class Char:
    __slots__ = "val"

    def __init__(self, val: str | int):
        if type(val) is int:
            self.val: str = chr(val)
        else:
            assert type(val) is str and len(val) == 1
            self.val = val

    def __str__(self) -> str:
        return self.val

    def __repr__(self) -> str:
        names = {" ": "space", "\n": "newline", "\t": "tab"}
        return f"#\\{self.val}" if self.val not in names else f"#\\{names[self.val]}"

    def __eq__(self, obj: object) -> bool:
        return type(obj) is Char and self.val == obj.val

    def __radd__(self, obj2: str) -> str:
        return obj2 + self.val


def display_dtype(dtype: np.dtype) -> str:
    if dtype.kind == "b":
        return "bool"

    if dtype.kind == "i":
        return f"int{dtype.itemsize * 8}"

    if dtype.kind == "u":
        return f"uint{dtype.itemsize * 8}"

    return f"float{dtype.itemsize * 8}"


def display_str(val: object) -> str:
    if val is None:
        return "#<void>"
    if val is True:
        return "#t"
    if val is False:
        return "#f"
    if type(val) is Sym:
        return val.val
    if type(val) is str:
        return val
    if type(val) is Char:
        return f"{val}"
    if type(val) is range:
        return "#<range>"
    if type(val) is complex:
        join = "" if val.imag < 0 else "+"
        return f"{val.real}{join}{val.imag}i"
    if type(val) is np.bool_:
        return "1" if val else "0"

    if isinstance(val, Fraction):
        return f"{val.numerator}/{val.denominator}"
    if isinstance(val, list):
        if not val:
            return "#()"
        result = StringIO()
        result.write(f"#({print_str(val[0])}")
        for item in val[1:]:
            result.write(f" {print_str(item)}")
        result.write(")")
        return result.getvalue()
    if isinstance(val, dict):
        result = StringIO()
        result.write("#hash(")
        is_first = True
        for k, v in val.items():
            if is_first:
                result.write(f"[{print_str(k)} {print_str(v)}]")
                is_first = False
            else:
                result.write(f" [{print_str(k)} {print_str(v)}]")
        result.write(")")
        return result.getvalue()
    if isinstance(val, np.ndarray):
        result = StringIO()
        result.write(f"(array '{display_dtype(val.dtype)}")
        if val.dtype.kind == "b":
            for item in val:
                result.write(" 1" if item else " 0")
        else:
            for item in val:
                result.write(f" {item}")
        result.write(")")
        return result.getvalue()

    return f"{val!r}"


str_escape = {
    "\\": "\\\\",
    '"': '\\"',
    "\r": "\\r",
    "\f": "\\f",
    "\v": "\\v",
    "\n": "\\n",
    "\t": "\\t",
    "\b": "\\b",
    "\a": "\\a",
}


def print_str(val: object) -> str:
    if type(val) is str:
        for k, v in str_escape.items():
            val = val.replace(k, v)
        return f'"{val}"'
    if type(val) is Char:
        return f"{val!r}"
    if type(val) is Sym:
        return f"'{display_str(val)}"

    return display_str(val)
