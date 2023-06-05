from __future__ import annotations

from fractions import Fraction
from typing import Any, Callable

from .data_structs import Sym, print_str
from .err import MyError


class Proc:
    __slots__ = ("name", "proc", "arity", "contracts")

    def __init__(
        self,
        name: str,
        proc: Callable,
        arity: tuple[int, int | None] = (1, None),
        contracts: list[Any] | None = None,
    ):
        self.name = name
        self.proc = proc
        self.arity = arity
        self.contracts = contracts

    def __str__(self) -> str:
        return f"#<procedure:{self.name}>"

    __repr__ = __str__

    def __call__(self, *args: Any) -> Any:
        return self.proc(*args)


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


def check_contract(c: object, val: object) -> bool:
    if isinstance(c, Contract):
        return c(val)
    if (
        isinstance(c, Proc)
        and c.arity[0] < 2
        and (c.arity[1] is None or c.arity[1] > 0)
    ):
        return c(val)
    if c is True:
        return val is True
    if c is False:
        return val is False

    if type(c) is int:
        return val == c
    if type(c) in (int, float, Fraction, complex, str, Sym):
        return val == c
    raise MyError(f"Invalid contract, got: {print_str(c)}")


def is_contract(c: object) -> bool:
    if isinstance(c, Contract):
        return True
    if (
        isinstance(c, Proc)
        and c.arity[0] < 2
        and (c.arity[1] is None or c.arity[1] > 0)
    ):
        return True
    if c is True or c is False:
        return True
    return type(c) in (int, float, Fraction, complex, str, Sym)


is_bool = Contract("bool?", lambda v: type(v) is bool)
is_int = Contract("int?", lambda v: type(v) is int)
is_uint = Contract("uint?", lambda v: type(v) is int and v > -1)
is_nat = Contract("nat?", lambda v: type(v) is int and v > 0)
int_not_zero = Contract("(or/c (not/c 0) int?)", lambda v: v != 0 and is_int(v))
is_num = Contract("number?", lambda v: type(v) in (int, float, Fraction, complex))
is_real = Contract("real?", lambda v: type(v) in (int, float, Fraction))
is_float = Contract("float?", lambda v: type(v) is float)
is_frac = Contract("frac?", lambda v: type(v) is Fraction)
is_str = Contract("string?", lambda v: type(v) is str)
any_p = Contract("any", lambda v: True)
is_void = Contract("void?", lambda v: v is None)
is_int_or_float = Contract("(or/c int? float?)", lambda v: type(v) in (int, float))
is_threshold = Contract(
    "threshold?", lambda v: type(v) in (int, float) and v >= 0 and v <= 1  # type: ignore
)
is_proc = Contract("procedure?", lambda v: isinstance(v, (Proc, Contract)))


def andc(*cs: object) -> Proc:
    return Proc(
        "flat-and/c", lambda v: all([check_contract(c, v) for c in cs]), (1, 1), [any_p]
    )


def orc(*cs: object) -> Proc:
    return Proc(
        "flat-or/c", lambda v: any([check_contract(c, v) for c in cs]), (1, 1), [any_p]
    )


def notc(c: object) -> Proc:
    return Proc("flat-not/c", lambda v: not check_contract(c, v), (1, 1), [any_p])


def gte_c(n: int | float | Fraction) -> Proc:
    return Proc(f"(>=/c {n})", lambda i: i >= n, (1, 1), [is_real])


def gt_c(n: int | float | Fraction) -> Proc:
    return Proc(f"(>/c {n})", lambda i: i > n, (1, 1), [is_real])


def lte_c(n: int | float | Fraction) -> Proc:
    return Proc(f"(<=/c {n})", lambda i: i <= n, (1, 1), [is_real])


def lt_c(n: int | float | Fraction) -> Proc:
    return Proc(f"(</c {n})", lambda i: i < n, (1, 1), [is_real])


def between_c(n: int | float | Fraction, m: int | float | Fraction) -> Proc:
    if m > n:
        return Proc(f"(between/c {n} {m})", lambda i: is_real(i) and i <= m and i >= n)
    return Proc(f"(between/c {n} {m})", lambda i: is_real(i) and i <= n and i >= m)
