from __future__ import annotations

from collections.abc import Callable
from dataclasses import dataclass
from fractions import Fraction
from typing import Any

from .data_structs import Sym, print_str
from .err import MyError


@dataclass(slots=True)
class Contract:
    # Convenient flat contract class
    name: str
    c: Callable[[object], bool]

    def __call__(self, *v: object) -> bool:
        if len(v) != 1:
            o = self.name
            raise MyError(f"`{o}` has an arity mismatch. Expected 1, got {len(v)}")
        return self.c(v[0])

    def __str__(self) -> str:
        return self.name

    def __repr__(self) -> str:
        return f"#<proc:{self.name} (1 1)>"


def check_contract(c: object, val: object) -> bool:
    if type(c) is Contract:
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
    if type(c) in (int, float, Fraction, complex, str, Sym):
        return val == c
    raise MyError(f"Invalid contract, got: {print_str(c)}")


def check_args(
    o: str,
    values: list | tuple,
    arity: tuple[int, int | None],
    cont: tuple[Any, ...],
) -> None:
    lower, upper = arity
    amount = len(values)

    assert not (upper is not None and lower > upper)
    base = f"`{o}` has an arity mismatch. Expected "

    if lower == upper and len(values) != lower:
        raise MyError(f"{base}{lower}, got {amount}")
    if upper is None and amount < lower:
        raise MyError(f"{base}at least {lower}, got {amount}")
    if upper is not None and (amount > upper or amount < lower):
        raise MyError(f"{base}between {lower} and {upper}, got {amount}")

    if not cont:
        return

    for i, val in enumerate(values):
        check = cont[-1] if i >= len(cont) else cont[i]
        if not check_contract(check, val):
            exp = f"{check}" if callable(check) else print_str(check)
            raise MyError(f"`{o}` expected a {exp}, got {print_str(val)}")


class Proc:
    __slots__ = ("name", "proc", "arity", "contracts")

    def __init__(
        self, n: str, p: Callable, a: tuple[int, int | None] = (1, None), *c: Any
    ):
        self.name = n
        self.proc = p
        self.arity = a
        self.contracts: tuple[Any, ...] = c

    def __call__(self, *args: Any) -> Any:
        check_args(self.name, args, self.arity, self.contracts)
        return self.proc(*args)

    def __str__(self) -> str:
        return self.name

    def __repr__(self) -> str:
        n = "inf" if self.arity[1] is None else f"{self.arity[1]}"

        if self.contracts is None:
            c = ""
        else:
            c = " (" + " ".join([f"{c}" for c in self.contracts]) + ")"
        return f"#<proc:{self.name} ({self.arity[0]} {n}){c}>"


def is_contract(c: object) -> bool:
    if type(c) is Contract:
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
is_nat = Contract("nat?", lambda v: type(v) is int and v > -1)
is_nat1 = Contract("nat1?", lambda v: type(v) is int and v > 0)
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
    "threshold?",
    lambda v: type(v) in (int, float) and v >= 0 and v <= 1,  # type: ignore
)
is_proc = Contract("procedure?", lambda v: isinstance(v, Proc | Contract))


def andc(*cs: object) -> Proc:
    name = "(and/c " + " ".join(f"{c}" for c in cs) + ")"
    return Proc(name, lambda v: all(check_contract(c, v) for c in cs), (1, 1), any_p)


def orc(*cs: object) -> Proc:
    name = "(or/c " + " ".join(f"{c}" for c in cs) + ")"
    return Proc(name, lambda v: any(check_contract(c, v) for c in cs), (1, 1), any_p)


def notc(c: object) -> Proc:
    return Proc("flat-not/c", lambda v: not check_contract(c, v), (1, 1), any_p)


def gte_c(n: int | float | Fraction) -> Proc:
    return Proc(f"(>=/c {n})", lambda i: i >= n, (1, 1), is_real)


def gt_c(n: int | float | Fraction) -> Proc:
    return Proc(f"(>/c {n})", lambda i: i > n, (1, 1), is_real)


def lte_c(n: int | float | Fraction) -> Proc:
    return Proc(f"(<=/c {n})", lambda i: i <= n, (1, 1), is_real)


def lt_c(n: int | float | Fraction) -> Proc:
    return Proc(f"(</c {n})", lambda i: i < n, (1, 1), is_real)


def between_c(n: Any, m: Any) -> Proc:
    if m > n:
        return Proc(
            f"(between/c {n} {m})", lambda i: is_real(i) and i <= m and i >= n, (1, 1)
        )
    return Proc(
        f"(between/c {n} {m})", lambda i: is_real(i) and i <= n and i >= m, (1, 1)
    )
