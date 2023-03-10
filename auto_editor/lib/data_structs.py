from __future__ import annotations

from fractions import Fraction
from typing import Any, Callable

import numpy as np

from .err import MyError


class Sym:
    __slots__ = ("val", "hash")

    def __init__(self, val: str):
        self.val = val
        self.hash = hash(val)

    __str__: Callable[[Sym], str] = lambda self: self.val
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

    __str__: Callable[[Char], str] = lambda self: self.val

    def __repr__(self) -> str:
        names = {" ": "space", "\n": "newline", "\t": "tab"}
        return f"#\\{self.val}" if self.val not in names else f"#\\{names[self.val]}"

    def __eq__(self, obj: object) -> bool:
        return type(obj) is Char and self.val == obj.val

    def __radd__(self, obj2: str) -> str:
        return obj2 + self.val


class NullType:
    __slots__ = ()

    def __new__(cls: type[NullType]) -> NullType:
        return Null

    def __eq__(self, obj: object) -> bool:
        return obj is Null

    def __len__(self) -> int:
        return 0

    def __next__(self) -> StopIteration:
        raise StopIteration

    def __getitem__(self, ref: int | slice) -> None:
        raise IndexError

    def __str__(self) -> str:
        return "'()"

    def __copy__(self) -> NullType:
        return Null

    def __deepcopy__(self, memo: Any) -> NullType:
        return Null

    __repr__ = __str__


Null = object.__new__(NullType)


class Cons:
    __slots__ = ("a", "d")

    def __init__(self, a: Any, d: Any):
        self.a = a
        self.d = d

    def __repr__(self) -> str:
        if type(self.d) not in (Cons, NullType):
            return f"(cons {self.a} {self.d})"

        result = f"({display_str(self.a)}"
        tail = self.d
        while type(tail) is Cons:
            if type(tail.d) not in (Cons, NullType):
                return f"{result} (cons {tail.a} {tail.d}))"
            result += f" {display_str(tail.a)}"
            tail = tail.d

        return f"{result})"

    def __eq__(self, obj: object) -> bool:
        return type(obj) is Cons and self.a == obj.a and self.d == obj.d

    def __len__(self: Cons | NullType) -> int:
        count = 0
        while type(self) is Cons:
            self = self.d
            count += 1
        if self is not Null:
            raise MyError("length expects: list?")
        return count

    def __next__(self) -> Any:
        if type(self.d) is Cons:
            return self.d
        raise StopIteration

    def __iter__(self) -> Any:
        while type(self) is Cons:
            yield self.a
            self = self.d

    def __getitem__(self, ref: object) -> Any:
        if type(ref) is not int and type(ref) is not slice:
            raise MyError(f"ref: not a valid index: {print_str(ref)}")

        if type(ref) is int:
            if ref < 0:
                raise MyError(f"ref: negative index not allowed: {ref}")
            pos = ref
            while pos > 0:
                pos -= 1
                self = self.d
                if type(self) is not Cons:
                    raise MyError(f"ref: index out of range: {ref}")

            return self.a

        assert type(ref) is slice

        lst: Cons | NullType = Null
        steps: int = -1
        i: int = 0

        do_reverse = True
        start, stop, step = ref.start, ref.stop, ref.step
        if start is None:
            start = 0
        if step < 0:
            do_reverse = False
            step = -step

            if stop is None:
                stop = float("inf")
            else:
                start, stop = stop + 1, start

        while type(self) is Cons:
            if i > stop - 1:
                break
            if i >= start:
                steps = (steps + 1) % step
                if steps == 0:
                    lst = Cons(self.a, lst)

            self = self.d
            i += 1

        if not do_reverse:
            return lst

        result: Cons | NullType = Null
        while type(lst) is Cons:
            result = Cons(lst.a, result)
            lst = lst.d
        return result


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
        result = f"#({display_str(val[0])}"
        for item in val[1:]:
            result += f" {display_str(item)}"
        return result + ")"
    if isinstance(val, np.ndarray):
        kind = val.dtype.kind
        result = f"(array '{display_dtype(val.dtype)}"
        if kind == "b":
            for item in val:
                result += " 1" if item else " 0"
        else:
            for item in val:
                result += f" {item}"
        return result + ")"

    return f"{val!r}"


def print_str(val: object) -> str:
    if type(val) is str:

        def str_escape(val: str) -> str:
            return (
                val.replace("\\", "\\\\")
                .replace('"', '\\"')
                .replace("\n", "\\n")
                .replace("\t", "\\t")
            )

        return f'"{str_escape(val)}"'
    if type(val) is Char:
        return f"{val!r}"
    if type(val) is Sym or type(val) is Cons or isinstance(val, list):
        return f"'{display_str(val)}"

    return display_str(val)
