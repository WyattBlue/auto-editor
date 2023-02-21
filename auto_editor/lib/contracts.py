from __future__ import annotations

from fractions import Fraction
from typing import Callable


class Contract:
    # Convenient flat contract class
    __slots__ = ("name", "c")

    def __init__(self, name: str, c: Callable[[object], bool]):
        self.name = name
        self.c = c

    def __str__(self) -> str:
        return f"<procedure:{self.name}>"

    __repr__ = __str__

    def __call__(self, v: object) -> bool:
        return self.c(v)


is_bool = Contract("bool?", lambda v: type(v) is bool)
is_int = Contract("int?", lambda v: type(v) is int)
is_uint = Contract("uint?", lambda v: type(v) is int and v > -1)
int_not_zero = Contract("(or/c (not/c 0) int?)", lambda v: v != 0 and is_int(v))
is_num = Contract("number?", lambda v: type(v) in (int, float, Fraction, complex))
is_real = Contract("real?", lambda v: type(v) in (int, float, Fraction))
is_float = Contract("float?", lambda v: type(v) is float)
is_frac = Contract("frac?", lambda v: type(v) is Fraction)
is_str = Contract("string?", lambda v: type(v) is str)
any_p = Contract("any", lambda v: True)
is_void = Contract("void?", lambda v: v is None)
is_threshold = Contract(
    "threshold?", lambda v: type(v) in (int, float) and v >= 0 and v <= 1  # type: ignore
)
