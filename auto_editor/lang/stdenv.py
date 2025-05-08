from __future__ import annotations

from dataclasses import dataclass
from typing import TYPE_CHECKING

import bv

from auto_editor.analyze import mut_remove_large, mut_remove_small
from auto_editor.lib.contracts import *
from auto_editor.lib.data_structs import *
from auto_editor.lib.err import MyError

from .palet import Syntax, env, is_boolarr, is_iterable, my_eval, p_slice, raise_, ref

if TYPE_CHECKING:
    from fractions import Fraction
    from typing import Any, Literal

    import numpy as np
    from numpy.typing import NDArray

    Number = int | float | complex | Fraction
    BoolList = NDArray[np.bool_]
    Node = tuple


def make_standard_env() -> dict[str, Any]:
    import os.path
    from cmath import sqrt as complex_sqrt
    from functools import reduce
    from operator import add, ge, gt, is_, le, lt, mod, mul
    from subprocess import run
    from time import sleep

    from numpy import logical_and, logical_not, logical_or, logical_xor

    from auto_editor.utils.func import boolop, mut_margin

    # fmt: off

    class UserProc(Proc):
        """A user-defined procedure."""

        __slots__ = ("env", "name", "parms", "body", "contracts", "arity")

        def __init__(
            self,
            env: Env,
            name: str,
            parms: list[str],
            contracts: tuple[Any, ...],
            body: Node,
        ):
            self.env = env
            self.name = name
            self.parms = parms
            self.body = body
            self.contracts = contracts

            if parms and parms[-1] == "...":
                parms.pop()
                self.arity: tuple[int, int | None] = len(parms) - 1, None
            else:
                self.arity = len(parms), len(parms)

        def __call__(self, *args: Any) -> Any:
            check_args(self.name, args, self.arity, self.contracts)

            if self.arity[1] is None:
                args = tuple(
                    list(args[: len(self.parms) - 1]) + [list(args[len(self.parms) - 1 :])]
                )

            inner_env = Env(dict(zip(self.parms, args)), self.env)

            for item in self.body[0:-1]:
                my_eval(inner_env, item)

            return my_eval(inner_env, self.body[-1])

    @dataclass(slots=True)
    class KeywordUserProc:
        env: Env
        name: str
        parms: list[str]
        kw_parms: list[str]
        body: Node
        arity: tuple[int, None]
        contracts: list[Any] | None = None

        def __call__(self, *args: Any, **kwargs: Any) -> Any:
            env = {}
            all_parms = self.parms + self.kw_parms
            for i, arg in enumerate(args):
                if i >= len(all_parms):
                    raise MyError("Too many arguments")
                env[all_parms[i]] = arg

            for key, val in kwargs.items():
                if key in env:
                    raise MyError(
                        f"Keyword: {key} already fulfilled by positional argument."
                    )
                else:
                    env[key] = val

            inner_env = Env(env, self.env)

            for item in self.body[0:-1]:
                my_eval(inner_env, item)

            return my_eval(inner_env, self.body[-1])

        def __str__(self) -> str:
            return self.name

        def __repr__(self) -> str:
            return f"#<kw-proc:{self.name}>"

    is_cont = Contract("contract?", is_contract)
    is_sequence = Contract(
        "sequence?",
        lambda v: type(v) in (str, range, Quoted) or isinstance(v, list | np.ndarray),
    )
    bool_or_barr = Contract(
        "(or/c bool? bool-array?)",
        lambda v: type(v) is bool or is_boolarr(v),
    )
    is_keyw = Contract("keyword?", lambda v: type(v) is QuotedKeyword)
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

    @dataclass(slots=True)
    class InputPort:
        name: str
        port: Any
        closed: bool

        def close(self) -> None:
            if not self.closed:
                self.closed = True
                self.port.close()

        def __str__(self) -> str:
            return f"#<input-port:{self.name}>"

        __repr__ = __str__

    @dataclass(slots=True)
    class OutputPort:
        name: str
        port: Any
        write: Any
        closed: bool

        def close(self) -> None:
            if not self.closed:
                self.closed = True
                self.port.close()

        def __str__(self) -> str:
            return f"#<output-port:{self.name}>"

        __repr__ = __str__

    def initInPort(name: str) -> InputPort | Literal[False]:
        try:
            port = open(name, encoding="utf-8")
        except Exception:
            return False
        return InputPort(name, port, False)

    def initOutPort(name: str) -> OutputPort | Literal[False]:
        try:
            port = open(name, "w", encoding="utf-8")
        except Exception:
            return False
        return OutputPort(name, port, port.write, False)

    def is_equal(a: object, b: object) -> bool:
        if isinstance(a, np.ndarray) and isinstance(b, np.ndarray):
            return np.array_equal(a, b)
        return type(a) == type(b) and a == b

    # Syntax definitions
    def check_for_syntax(env: Env, node: Node) -> tuple[Sym, Any]:
        name = node[0]
        if len(node) < 2:
            raise MyError(f"{name}: bad syntax")

        if len(node) == 2:
            raise MyError(f"{name}: missing body")

        assert isinstance(node[1], tuple)
        assert isinstance(node[1][0], tuple)

        var = node[1][0][0]
        if type(var) is not Sym:
            raise MyError(f"{name}: binding must be an identifier")
        my_iter = my_eval(env, node[1][0][1])

        if not is_iterable(my_iter):
            if type(my_iter) is int:
                return var, range(my_iter)
            raise MyError(f"{name}: got non-iterable in iter slot")

        return var, my_iter

    def syn_lambda(env: Env, node: Node) -> UserProc:
        if len(node) < 3:
            raise MyError(f"{node[0]}: too few terms")

        if type(node[1]) is not tuple:
            raise MyError(f"{node[0]}: bad syntax")

        parms: list[str] = []
        for item in node[1]:
            if type(item) is not Sym:
                raise MyError(f"{node[0]}: must be an identifier, got: {item} {type(item)}")

            parms.append(f"{item}")

        return UserProc(env, "", parms, (), node[2:])

    def syn_define(env: Env, node: Node) -> None:
        if len(node) < 2:
            raise MyError(f"{node[0]}: too few terms")
        if len(node) < 3:
            if type(node[1]) is Sym:
                raise MyError(f"{node[0]}: what should `{node[1]}` be defined as?")
            elif type(node[1]) is tuple and len(node[1]) > 0:
                raise MyError(f"{node[0]}: function `{node[1][0]}` needs a body.")
            raise MyError(f"{node[0]}: too few terms")

        if type(node[1]) is tuple:
            term = node[1]
            body = node[2:]

            if not term or type(term[0]) is not Sym:
                raise MyError(f"{node[0]}: proc-binding must be an identifier")

            n = term[0].val
            parms: list[str] = []
            kparms: list[str] = []
            kw_only = False

            for item in term[1:]:
                if kw_only:
                    if type(item) is Sym:
                        raise MyError(f"{node[0]}: {item} must be a keyword")
                    if type(item) is not Keyword:
                        raise MyError(f"{node[0]}: must be a keyword")
                    kparms.append(item.val)
                else:
                    if type(item) is Keyword:
                        kw_only = True
                        kparms.append(item.val)
                    elif type(item) is Sym:
                        parms.append(item.val)
                    else:
                        raise MyError(f"{node[0]}: must be an identifier")

            if kw_only:
                env[n] = KeywordUserProc(env, n, parms, kparms, body, (len(parms), None))
            else:
                env[n] = UserProc(env, n, parms, (), body)
            return None

        elif type(node[1]) is not Sym:
            raise MyError(f"{node[0]}: must be an identifier")

        if len(node) > 3:
            raise MyError(f"{node[0]}: multiple expressions after identifier")

        n = node[1].val

        if (
            type(node[2]) is tuple
            and node[2]
            and type(node[2][0]) is Sym
            and node[2][0].val in {"lambda", "λ"}
        ):
            terms = node[2][1]
            body = node[2][2:]

            parms = []
            for item in terms:
                if type(item) is not Sym:
                    raise MyError(f"{node[0]}: must be an identifier")

                parms.append(f"{item}")

            env[n] = UserProc(env, n, parms, (), body)

        else:
            for item in node[2:-1]:
                my_eval(env, item)
            env[n] = my_eval(env, node[-1])

    def syn_definec(env: Env, node: Node) -> None:
        if len(node) < 3:
            raise MyError(f"{node[0]}: too few terms")

        if type(node[1]) is not tuple:
            raise MyError(f"{node[0]} only allows procedure declarations")

        if not node[1] or type(node[1][0]) is not Sym:
            raise MyError(f"{node[0]}: bad proc-binding syntax")

        n = node[1][0].val

        contracts: list[Any] = []
        parms: list[str] = []
        for item in node[1][1:]:
            if item == Sym("->"):
                break
            if type(item) is not tuple or len(item) != 2:
                raise MyError(f"{node[0]}: bad var-binding syntax")
            if type(item[0]) is not Sym:
                raise MyError(f"{node[0]}: binding must be identifier")

            con = my_eval(env, item[1])
            if not is_cont(con):
                raise MyError(f"{node[0]}: {print_str(con)} is not a valid contract")

            parms.append(f"{item[0]}")
            contracts.append(con)

        env[n] = UserProc(env, n, parms, tuple(contracts), node[2:])
        return None

    def guard_term(node: Node, n: int, u: int) -> None:
        if n == u:
            if len(node) != n:
                raise MyError(
                    f"{node[0]}: Expects exactly {n-1} term{'s' if n > 2 else ''}"
                )
            return None
        if len(node) < n:
            raise MyError(f"{node[0]}: Expects at least {n-1} term{'s' if n > 2 else ''}")
        if len(node) > u:
            raise MyError(f"{node[0]}: Expects at most {u-1} term{'s' if u > 2 else ''}")

    def syn_set(env: Env, node: Node) -> None:
        guard_term(node, 3, 3)

        if type(node[1]) is Sym:
            name = node[1].val
            if name not in env:
                raise MyError(f"{node[0]}: Can't set variable `{name}` before definition")
            env[name] = my_eval(env, node[2])
            return None

        if type(node[1]) is tuple and len(node[1]) == 3 and node[1][0] == Sym("@r"):
            base = my_eval(env, node[1][1])
            name = node[1][2].val
            for i, item in enumerate(base.attrs[0::2]):
                if name == item:
                    result = my_eval(env, node[2])
                    check_args(item, (result,), (1, 1), (base.attrs[i * 2 + 1],))
                    base.values[i] = result
                    return None

            raise MyError(f"{node[0]}: {base.name} has no attribute `{name}`")

        raise MyError(f"{node[0]}: Expected identifier, got {print_str(node[1])}")

    def syn_incf(env: Env, node: Node) -> None:
        guard_term(node, 2, 3)

        incre_by = 1
        if len(node) == 3:
            incre_by = my_eval(env, node[2])
            if not is_num(incre_by):
                raise MyError(f"{node[0]}: Expected number? got: {print_str(incre_by)}")

        if type(node[1]) is Sym:
            name = node[1].val

            if type(env[name]) is NotFound:
                raise MyError(f"{node[0]}: `{name}` is not defined")
            if not is_num(env[name]):
                raise MyError(f"{node[0]}: `{name}` is not a number?")
            env[name] += incre_by
            return None

        if type(node[1]) is tuple and len(node[1]) == 3 and node[1][0] == Sym("@r"):
            base = my_eval(env, node[1][1])
            if type(base) is not PaletClass:
                raise MyError(f"{node[0]}: must be a class instance")
            if type(node[1][2]) is not Sym:
                raise MyError(f"{node[0]}: class attribute must be an identifier")
            name = node[1][2].val
            for i, item in enumerate(base.attrs[0::2]):
                if name == item:
                    if not is_num(base.values[i]):
                        raise MyError(f"{node[0]}: `{name}` is not a number?")

                    check_args(
                        name, (base.values[i] + incre_by,), (1, 1), (base.attrs[i * 2 + 1],)
                    )
                    base.values[i] += incre_by
                    return None
            raise MyError(f"{node[0]}: {base.name} has no attribute `{name}`")

        raise MyError(f"{node[0]}: Expected identifier, got {print_str(node[1])}")

    def syn_decf(env: Env, node: Node) -> None:
        guard_term(node, 2, 3)

        incre_by = 1
        if len(node) == 3:
            incre_by = my_eval(env, node[2])
            if not is_num(incre_by):
                raise MyError(f"{node[0]}: Expected number? got: {print_str(incre_by)}")

        if type(node[1]) is Sym:
            name = node[1].val

            if type(env[name]) is NotFound:
                raise MyError(f"{node[0]}: `{name}` is not defined")
            if not is_num(env[name]):
                raise MyError(f"{node[0]}: `{name}` is not a number?")
            env[name] -= incre_by
            return None

        if type(node[1]) is tuple and len(node[1]) == 3 and node[1][0] == Sym("@r"):
            base = my_eval(env, node[1][1])
            if type(base) is not PaletClass:
                raise MyError(f"{node[0]}: must be a class instance")
            if type(node[1][2]) is not Sym:
                raise MyError(f"{node[0]}: class attribute must be an identifier")
            name = node[1][2].val
            for i, item in enumerate(base.attrs[0::2]):
                if name == item:
                    if not is_num(base.values[i]):
                        raise MyError(f"{node[0]}: `{name}` is not a number?")

                    check_args(
                        name, (base.values[i] - incre_by,), (1, 1), (base.attrs[i * 2 + 1],)
                    )
                    base.values[i] -= incre_by
                    return None
            raise MyError(f"{node[0]}: {base.name} has no attribute `{name}`")

        raise MyError(f"{node[0]}: Expected identifier, got {print_str(node[1])}")

    def syn_strappend(env: Env, node: Node) -> None:
        guard_term(node, 3, 3)

        if type(node[1]) is not Sym:
            raise MyError(f"{node[0]}: Expected identifier, got {print_str(node[1])}")
        name = node[1].val

        if type(env[name]) is NotFound:
            raise MyError(f"{node[0]}: `{name}` is not defined")
        if not is_str(env[name]):
            raise MyError(f"{node[0]}: `{name}` is not a string?")

        if not is_str(num := my_eval(env, node[2])):
            raise MyError(f"{node[0]}: Expected string? got: {print_str(num)}")
        env[name] += num

    def syn_while(env: Env, node: Node) -> None:
        while my_eval(env, node[1]) == True:
            for c in node[2:]:
                my_eval(env, c)

    def syn_for(env: Env, node: Node) -> None:
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

    def syn_for_items(env: Env, node: Node) -> None:
        if len(node) < 2:
            raise MyError(f"{node[0]}: bad syntax")

        if type(node[1]) is not tuple or len(node[1]) != 3:
            raise MyError(f"{node[0]}: Invalid id body")

        key, val, dic = node[1]
        if type(key) is not Sym or type(val) is not Sym:
            raise MyError(f"{node[0]}: key and val must be identifiers")

        dic = my_eval(env, dic)
        if type(dic) is not dict:
            raise MyError(f"{node[0]}: dict must be a hash?")

        for k, v in dic.items():
            env[key.val] = k
            env[val.val] = v
            for c in node[2:]:
                my_eval(env, c)

    def syn_quote(env: Env, node: Node) -> Any:
        guard_term(node, 2, 2)
        if type(node[1]) is Keyword:
            return QuotedKeyword(node[1])
        if type(node[1]) is tuple:
            return Quoted(node[1])
        return node[1]

    def syn_if(env: Env, node: Node) -> Any:
        guard_term(node, 4, 4)
        test_expr = my_eval(env, node[1])

        if type(test_expr) is not bool:
            raise MyError(
                f"{node[0]} test-expr: expected bool?, got {print_str(test_expr)}"
            )

        return my_eval(env, node[2] if test_expr else node[3])

    def syn_when(env: Env, node: Node) -> Any:
        if len(node) < 3:
            raise MyError(f"{node[0]}: Expected at least 2 terms")
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

    def syn_and(env: Env, node: Node) -> Any:
        if len(node) == 1:
            raise MyError(f"{node[0]}: Expected at least 1 term")

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
            check_args(node[0], vals, (2, None), (is_boolarr,))
            return reduce(lambda a, b: boolop(a, b, logical_and), vals)

        raise MyError(f"{node[0]} expects (or/c bool? bool-array?)")

    def syn_or(env: Env, node: Node) -> Any:
        if len(node) == 1:
            raise MyError(f"{node[0]}: Expected at least 1 term")

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
            check_args(node[0], vals, (2, None), (is_boolarr,))
            return reduce(lambda a, b: boolop(a, b, logical_or), vals)

        raise MyError(f"{node[0]} expects (or/c bool? bool-array?)")

    def syn_delete(env: Env, node: Node) -> None:
        guard_term(node, 2, 2)
        if type(node[1]) is not Sym:
            raise MyError(f"{node[0]}: Expected identifier for first term")

        del env[node[1].val]

    def syn_rename(env: Env, node: Node) -> None:
        guard_term(node, 3, 3)

        first = node[1]
        if type(first) is not Sym:
            raise MyError(f"{node[0]}: Expected identifier for first term")

        sec = node[2]
        if type(sec) is not Sym:
            raise MyError(f"{node[0]}: Expected identifier for second term")

        if first.val not in env:
            raise MyError(f"{node[0]}: Original identifier does not exist")

        env[sec.val] = env[first.val]
        del env[first.val]

    def syn_cond(env: Env, node: Node) -> Any:
        for test_expr in node[1:]:
            if type(test_expr) is not tuple or not test_expr:
                raise MyError(f"{node[0]}: bad syntax, clause is not a test-value pair")

            if test_expr[0] == Sym("else"):
                if len(test_expr) == 1:
                    raise MyError(f"{node[0]}: missing expression in else clause")
                test_clause = True
            else:
                test_clause = my_eval(env, test_expr[0])
                if type(test_clause) is not bool:
                    raise MyError(
                        f"{node[0]} test-expr: expected bool?, got {print_str(test_clause)}"
                    )

            if test_clause:
                if len(test_expr) == 1:
                    return True

                for rest_clause in test_expr[1:-1]:
                    my_eval(env, rest_clause)
                return my_eval(env, test_expr[-1])

        return None

    def syn_case(env: Env, node: Node) -> Any:
        val_expr = my_eval(env, node[1])
        for case_clause in node[2:]:
            if type(case_clause) is not tuple or len(case_clause) != 2:
                raise MyError("case: bad syntax")
            if type(case_clause[0]) is tuple:
                for case in case_clause[0]:
                    if is_equal(case, val_expr):
                        return my_eval(env, case_clause[1])
            elif type(case_clause[0]) is Sym and case_clause[0].val == "else":
                return my_eval(env, case_clause[1])
            else:
                raise MyError("case: bad syntax")
        return None

    def syn_let(env: Env, node: Node) -> Any:
        if len(node) < 2:
            raise MyError(f"{node[0]}: Expected at least 1 term")

        if type(node[1]) is Sym:
            raise MyError(f"{node[0]}: Named-let form is not supported")

        for var_ids in node[1]:
            if type(var_ids) is not tuple or len(var_ids) != 2:
                raise MyError(f"{node[0]}: Expected two terms: `id` and `val-expr`")

        new_maps: dict[str, Any] = {}
        for var, val in node[1]:
            if type(var) is not Sym:
                raise MyError(f"{node[0]}: Expected symbol for `id` term")
            new_maps[var.val] = my_eval(env, val)

        inner_env = Env(new_maps, env)
        for item in node[2:-1]:
            my_eval(inner_env, item)
        return my_eval(inner_env, node[-1])

    def syn_let_star(env: Env, node: Node) -> Any:
        if len(node) < 2:
            raise MyError(f"{node[0]}: Expected at least 1 term")

        for var_ids in node[1]:
            if len(var_ids) != 2:
                raise MyError(f"{node[0]}: Expected two terms: `id` and `val-expr`")

        inner_env = Env({}, env)

        for var, val in node[1]:
            if type(var) is not Sym:
                raise MyError(f"{node[0]}: Expected symbol for `id` term")
            inner_env[var.val] = my_eval(inner_env, val)

        for item in node[2:-1]:
            my_eval(inner_env, item)
        return my_eval(inner_env, node[-1])

    def syn_import(env: Env, node: Node) -> None:
        guard_term(node, 2, 2)

        if type(node[1]) is not Sym:
            raise MyError("class name must be an identifier")

        module = node[1].val
        try:
            obj = __import__(f"auto_editor.lang.lib{module}", fromlist=["lang"])
        except ImportError:
            raise MyError(f"No module named `{module}`")

        env.update(obj.all())

    def syn_class(env: Env, node: Node) -> None:
        if len(node) < 2:
            raise MyError(f"{node[0]}: Expects at least 1 term")

        if type(node[1]) is not Sym:
            raise MyError("class name must be an identifier")

        attr_len = len(node) - 2
        attrs: Any = [None] * (attr_len * 2)
        contracts = [None] * attr_len

        for i, item in enumerate(node[2:]):
            if type(item) is not tuple or len(item) != 2:
                raise MyError(f"{node[0]}: Invalid syntax")

            contracts[i] = my_eval(env, item[1])
            attrs[i * 2] = item[0].val
            attrs[i * 2 + 1] = contracts[i]

        name = node[1].val
        pred = name + "?"
        attrs = tuple(attrs)

        env[name] = Proc(
            name,
            lambda *args: PaletClass(name, attrs, list(args)),
            (attr_len, attr_len),
            *contracts,
        )
        env[pred] = Proc(
            pred,
            lambda v: type(v) is PaletClass and v.name == name and v.attrs == attrs,
            (1, 1),
        )

    def attr(env: Env, node: Node) -> Any:
        guard_term(node, 3, 3)

        if type(node[2]) is not Sym:
            raise MyError("@r: attribute must be an identifier")

        base = my_eval(env, node[1])

        if hasattr(base, "__pyx_vtable__"):
            try:
                return getattr(base, node[2].val)
            except AttributeError as e:
                raise MyError(e)

        if type(base) is PaletClass:
            if type(name := node[2]) is not Sym:
                raise MyError("@r: class attribute must be an identifier")

            for i, item in enumerate(base.attrs[0::2]):
                if name.val == item:
                    return base.values[i]

        return my_eval(env, (node[2], node[1]))

    # Procedure definitions
    def minclip(oarr: BoolList, _min: int, /) -> BoolList:
        arr = np.copy(oarr)
        mut_remove_small(arr, _min, replace=1, with_=0)
        return arr

    def mincut(oarr: BoolList, _min: int, /) -> BoolList:
        arr = np.copy(oarr)
        mut_remove_small(arr, _min, replace=0, with_=1)
        return arr

    def maxclip(oarr: BoolList, _min: int, /) -> BoolList:
        arr = np.copy(oarr)
        mut_remove_large(arr, _min, replace=1, with_=0)
        return arr

    def maxcut(oarr: BoolList, _min: int, /) -> BoolList:
        arr = np.copy(oarr)
        mut_remove_large(arr, _min, replace=0, with_=1)
        return arr

    def margin(oarr: BoolList, start: int, end: int | None = None, /) -> BoolList:
        arr = np.copy(oarr)
        if end is None:
            mut_margin(arr, start, start)
        else:
            mut_margin(arr, start, end)
        return arr

    def equal_num(*values: object) -> bool:
        return all(values[0] == val for val in values[1:])

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

            z /= num

        return z

    def int_div(n: int, *m: int) -> int:
        if 0 in m:
            raise MyError("div: division by zero")

        return reduce(lambda a, b: a // b, m, n)

    def _sqrt(v: Number) -> Number:
        r = complex_sqrt(v)
        if r.imag == 0:
            if int(r.real) == r.real:
                return int(r.real)
            return r.real
        return r

    def _xor(*vals: Any) -> bool | BoolList:
        if is_boolarr(vals[0]):
            check_args("xor", vals, (2, None), (is_boolarr,))
            return reduce(lambda a, b: boolop(a, b, logical_xor), vals)
        check_args("xor", vals, (2, None), (is_bool,))
        return reduce(lambda a, b: a ^ b, vals)

    def number_to_string(val: Number) -> str:
        if isinstance(val, complex):
            join = "" if val.imag < 0 else "+"
            return f"{val.real}{join}{val.imag}i"
        return f"{val}"

    def string_to_number(val) -> float:
        try:
            return float(val)
        except Exception:
            raise MyError(f"failed to convert {val} to number")

    def palet_join(v: Any, s: str) -> str:
        try:
            return s.join(v)
        except Exception:
            raise MyError("join: expected string?")

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

    def vector_set(vec: list, pos: int, v: Any) -> None:
        try:
            vec[pos] = v
        except IndexError:
            raise MyError(f"vector-set: Invalid index {pos}")

    def vector_extend(vec: list, *more_vecs: list) -> None:
        for more in more_vecs:
            vec.extend(more)

    def list_append(*v: Quoted) -> Quoted:
        result = Quoted(tuple())
        for item in v:
            result.val = result.val + item.val
        return result

    def palet_map(proc: Proc, seq: Any) -> Any:
        if type(seq) is str:
            return str(map(proc, seq))
        if type(seq) is Quoted:
            return Quoted(tuple(map(proc, seq.val)))
        if isinstance(seq, list | range):
            return list(map(proc, seq))
        elif isinstance(seq, np.ndarray):
            vectorized_proc = np.vectorize(proc)
            return vectorized_proc(seq)
        return proc(seq)

    def palet_member(v: object, seq: Any) -> bool:
        if type(v) is Char and type(seq) is str:
            return v.val in seq
        return v in seq

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

    def hash_ref(h: dict, k: object) -> object:
        try:
            return h[k]
        except Exception:
            raise MyError("hash-ref: invalid key")

    def hash_set(h: dict[object, object], k: object, v: object) -> None:
        h[k] = v

    def hash_remove(h: dict, v: object) -> None:
        try:
            del h[v]
        except Exception:
            pass

    def palet_assert(expr: object, msg: str | bool = False) -> None:
        if expr is not True:
            raise MyError("assert-error" if msg is False else f"assert-error: {msg}")

    def palet_system(cmd: str) -> bool:
        try:
            return run(cmd, shell=True).returncode == 0
        except Exception:
            return False

    def palet_system_star(*cmd: str) -> bool:
        try:
            return run(cmd).returncode == 0
        except Exception:
            return False

    def change_file_ext(a: str, ext: str) -> str:
        import os.path

        base_name = os.path.splitext(a)[0]
        return f"{base_name}.{ext}" if ext else base_name


    return {
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
        "incf": Syntax(syn_incf),
        "decf": Syntax(syn_decf),
        "&=": Syntax(syn_strappend),
        "quote": Syntax(syn_quote),
        "if": Syntax(syn_if),
        "when": Syntax(syn_when),
        "cond": Syntax(syn_cond),
        "case": Syntax(syn_case),
        "let": Syntax(syn_let),
        "let*": Syntax(syn_let_star),
        "import": Syntax(syn_import),
        "class": Syntax(syn_class),
        "@r": Syntax(attr),
        # loops
        "for": Syntax(syn_for),
        "for-items": Syntax(syn_for_items),
        "while": Syntax(syn_while),
        # contracts
        "number?": is_num,
        "real?": is_real,
        "int?": is_int,
        "float?": is_float,
        "frac?": is_frac,
        "complex?": Contract("complex?", lambda v: type(v) is complex),
        "nat?": is_nat,
        "nat1?": is_nat1,
        "threshold?": is_threshold,
        "any": any_p,
        "bool?": is_bool,
        "void?": is_void,
        "symbol?": (is_symbol := Contract("symbol?", lambda v: type(v) is Sym)),
        "string?": is_str,
        "char?": (is_char := Contract("char?", lambda v: type(v) is Char)),
        "list?": (is_list := Contract("list?", lambda v: type(v) is Quoted or type(v) is tuple)),
        "vector?": (is_vector := Contract("vector?", lambda v: type(v) is list)),
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
        "not": Proc("not", lambda v: not v if type(v) is bool else logical_not(v), (1, 1), bool_or_barr),
        "and": Syntax(syn_and),
        "or": Syntax(syn_or),
        "xor": Proc("xor", _xor, (2, None), bool_or_barr),
        # booleans
        ">": Proc(">", gt, (2, 2), is_real),
        ">=": Proc(">=", ge, (2, 2), is_real),
        "<": Proc("<", lt, (2, 2), is_real),
        "<=": Proc("<=", le, (2, 2), is_real),
        "=": Proc("=", equal_num, (1, None), is_num),
        "eq?": Proc("eq?", is_, (2, 2)),
        "equal?": Proc("equal?", is_equal, (2, 2)),
        "zero?": UserProc(env, "zero?", ["z"], (is_num,), ((Sym("="), Sym("z"), 0),)),
        "positive?": UserProc(env, "positive?", ["x"], (is_real,), ((Sym(">"), Sym("x"), 0),)),
        "negative?": UserProc(env, "negative?", ["x"], (is_real,), ((Sym("<"), Sym("x"), 0),)),
        "even?": UserProc(
            env, "even?", ["n"], (is_int,), ((Sym("zero?"), (Sym("mod"), Sym("n"), 2)),)),
        "odd?": UserProc(
            env, "odd?", ["n"], (is_int,), ((Sym("not"), (Sym("even?"), Sym("n"))),)),
        ">=/c": Proc(">=/c", gte_c, (1, 1), is_real),
        ">/c": Proc(">/c", gt_c, (1, 1), is_real),
        "<=/c": Proc("<=/c", lte_c, (1, 1), is_real),
        "</c": Proc("</c", lt_c, (1, 1), is_real),
        "between/c": Proc("between/c", between_c, (2, 2), is_real),
        # numbers
        "+": Proc("+", lambda *v: sum(v), (0, None), is_num),
        "-": Proc("-", minus, (1, None), is_num),
        "*": Proc("*", lambda *v: reduce(mul, v, 1), (0, None), is_num),
        "/": Proc("/", num_div, (1, None), is_num),
        "div": Proc("div", int_div, (2, None), is_int),
        "add1": Proc("add1", lambda z: z + 1, (1, 1), is_num),
        "sub1": Proc("sub1", lambda z: z - 1, (1, 1), is_num),
        "sqrt": Proc("sqrt", _sqrt, (1, 1), is_num),
        "real-part": Proc("real-part", lambda v: v.real, (1, 1), is_num),
        "imag-part": Proc("imag-part", lambda v: v.imag, (1, 1), is_num),
        # reals
        "pow": Proc("pow", pow, (2, 2), is_real),
        "abs": Proc("abs", abs, (1, 1), is_real),
        "round": Proc("round", round, (1, 2), is_real, is_int),
        "max": Proc("max", lambda *v: max(v), (1, None), is_real),
        "min": Proc("min", lambda *v: min(v), (1, None), is_real),
        "max-seq": Proc("max-seq", max, (1, 1), is_sequence),
        "min-seq": Proc("min-seq", min, (1, 1), is_sequence),
        "mod": Proc("mod", mod, (2, 2), is_int),
        "modulo": Proc("modulo", mod, (2, 2), is_int),
        # symbols
        "symbol->string": Proc("symbol->string", str, (1, 1), is_symbol),
        "string->symbol": Proc("string->symbol", Sym, (1, 1), is_str),
        # strings
        "string": Proc("string", lambda *v: reduce(add, v, ""), (0, None), is_char),
        "&": Proc("&", lambda *v: reduce(add, v, ""), (0, None), is_str),
        "split": Proc("split", str.split, (1, 2), is_str, is_str),
        "strip": Proc("strip", str.strip, (1, 1), is_str),
        "str-repeat": Proc("str-repeat", mul, (2, 2), is_str, is_int),
        "startswith": Proc("startswith", str.startswith, (2, 2), is_str),
        "endswith": Proc("endswith", str.endswith, (2, 2), is_str),
        "replace": Proc("replace", str.replace, (3, 4), is_str, is_str, is_str, is_int),
        "title": Proc("title", str.title, (1, 1), is_str),
        "lower": Proc("lower", str.lower, (1, 1), is_str),
        "upper": Proc("upper", str.upper, (1, 1), is_str),
        "join": Proc("join", palet_join, (2, 2), is_vector, is_str),
        "change-file-ext": Proc("change-file-ext", change_file_ext, (2, 2), is_str),
        # format
        "char->int": Proc("char->int", lambda c: ord(c.val), (1, 1), is_char),
        "int->char": Proc("int->char", Char, (1, 1), is_int),
        "~a": Proc("~a", lambda *v: "".join([display_str(a) for a in v]), (0, None)),
        "~s": Proc("~s", lambda *v: " ".join([display_str(a) for a in v]), (0, None)),
        "~v": Proc("~v", lambda *v: " ".join([print_str(a) for a in v]), (0, None)),
        # keyword
        "keyword?": is_keyw,
        "keyword->string": Proc("keyword->string", lambda v: v.val.val, (1, 1), is_keyw),
        "string->keyword": Proc("string->keyword", QuotedKeyword, (1, 1), is_str),
        # lists
        "list": Proc("list", lambda *a: Quoted(a), (0, None)),
        "append": Proc("append", list_append, (0, None), is_list),
        # vectors
        "vector": Proc("vector", lambda *a: list(a), (0, None)),
        "make-vector": Proc(
            "make-vector", lambda size, a=0: [a] * size, (1, 2), is_nat, any_p
        ),
        "add!": Proc("add!", list.append, (2, 2), is_vector, any_p),
        "pop!": Proc("pop!", list.pop, (1, 1), is_vector),
        "vec-set!": Proc("vec-set!", vector_set, (3, 3), is_vector, is_int, any_p),
        "vec-append": Proc("vec-append", lambda *v: reduce(add, v, []), (0, None), is_vector),
        "vec-extend!": Proc("vec-extend!", vector_extend, (2, None), is_vector),
        "sort": Proc("sort", sorted, (1, 1), is_vector),
        "sort!": Proc("sort!", list.sort, (1, 1), is_vector),
        # arrays
        "array": Proc("array", array_proc, (2, None), is_symbol, is_real),
        "make-array": Proc("make-array", make_array, (2, 3), is_symbol, is_nat, is_real),
        "array-splice!": Proc(
            "array-splice!", splice, (2, 4), is_array, is_real, is_int, is_int
        ),
        "array-copy": Proc("array-copy", np.copy, (1, 1), is_array),
        "count-nonzero": Proc("count-nonzero", np.count_nonzero, (1, 1), is_array),
        # bool arrays
        "bool-array": Proc(
            "bool-array", lambda *a: np.array(a, dtype=np.bool_), (1, None), is_nat
        ),
        "margin": Proc("margin", margin, (2, 3), is_boolarr, is_int),
        "mincut": Proc("mincut", mincut, (2, 2), is_boolarr, is_nat),
        "minclip": Proc("minclip", minclip, (2, 2), is_boolarr, is_nat),
        "maxcut": Proc("maxcut", maxcut, (2, 2), is_boolarr, is_nat),
        "maxclip": Proc("maxclip", maxclip, (2, 2), is_boolarr, is_nat),
        # ranges
        "range": Proc("range", range, (1, 3), is_int, is_int, int_not_zero),
        # generic iterables
        "len": Proc("len", len, (1, 1), is_iterable),
        "member": Proc("member", palet_member, (2, 2), any_p, is_sequence),
        "reverse": Proc("reverse", lambda v: v[::-1], (1, 1), is_sequence),
        "ref": Proc("ref", ref, (2, 2), is_sequence, is_int),
        "slice": Proc("slice", p_slice, (2, 4), is_sequence, is_int),
        # procedures
        "map": Proc("map", palet_map, (2, 2), is_proc, is_sequence),
        "apply": Proc("apply", lambda p, s: p(*s), (2, 2), is_proc, is_sequence),
        "and/c": Proc("and/c", andc, (1, None), is_cont),
        "or/c": Proc("or/c", orc, (1, None), is_cont),
        "not/c": Proc("not/c", notc, (1, 1), is_cont),
        # hashs
        "hash": Proc("hash", palet_hash, (0, None)),
        "hash-ref": Proc("hash", hash_ref, (2, 2), is_hash, any_p),
        "hash-set!": Proc("hash-set!", hash_set, (3, 3), is_hash, any_p, any_p),
        "has-key?": Proc("has-key?", lambda h, k: k in h, (2, 2), is_hash, any_p),
        "hash-remove!": Proc("hash-remove!", hash_remove, (2, 2), is_hash, any_p),
        "hash-update!": UserProc(env, "hash-update!", ["h", "v", "up"], (is_hash, any_p),
            (
                (Sym("hash-set!"), Sym("h"), Sym("v"), (Sym("up"), (Sym("h"), Sym("v"))),),
            ),
        ),
        # i/o
        "file-exists?": Proc("file-exists", os.path.isfile, (1, 1), is_str),
        "open-input-file": Proc("open-input-file", initInPort, (1, 1), is_str),
        "input-port?": (ip := Contract("input-port?", lambda v: type(v) is InputPort)),
        "read-line": Proc("read-line",
            lambda f: (r := f.port.readline(), None if r == "" else r.rstrip())[-1],
            (1, 1), ip),
        "open-output-file": Proc("open-output-file", initOutPort, (1, 1), is_str),
        "output-port?": (op := Contract("output-port?", lambda v: type(v) is OutputPort)),
        "port?": (port := Contract("port?", orc(ip, op))),
        "close-port": Proc("close-port", lambda p: p.close, (1, 1), port),
        "closed?": Proc("closed?", lambda o: o.closed, (1, 1), port),
        # subprocess
        "system": Proc("system", palet_system, (1, 1), is_str),
        "system*": Proc("system*", palet_system_star, (1, None), is_str),
        # printing
        "display": Proc("display",
            lambda v, f=None: print(display_str(v), end="", file=f), (1, 2), any_p, op),
        "displayln": Proc("displayln",
            lambda v, f=None: print(display_str(v), file=f), (1, 2), any_p, op),
        "print": Proc("print",
            lambda v, f=None: print(print_str(v), end="", file=f), (1, 2), any_p, op),
        "println": Proc("println",
            lambda v, f=None: print(print_str(v), file=f), (1, 2), any_p, op),
        # actions
        "assert": Proc("assert", palet_assert, (1, 2), any_p, orc(is_str, False)),
        "error": Proc("error", raise_, (1, 1), is_str),
        "sleep": Proc("sleep", sleep, (1, 1), is_int_or_float),
        # conversions
        "number->string": Proc("number->string", number_to_string, (1, 1), is_num),
        "string->number": Proc("string->number", string_to_number, (1, 1), is_str),
        "string->vector": Proc(
            "string->vector", lambda s: [Char(c) for c in s], (1, 1), is_str
        ),
        "range->vector": Proc("range->vector", list, (1, 1), is_range),
        # av
        "encoder": Proc("encoder", lambda x: bv.Codec(x, "w"), (1, 1), is_str),
        "decoder": Proc("decoder", lambda x: bv.Codec(x), (1, 1), is_str),
        # reflexion
        "var-exists?": Proc("var-exists?", lambda sym: sym.val in env, (1, 1), is_symbol),
        "rename": Syntax(syn_rename),
        "delete": Syntax(syn_delete),
        "eval": Proc("eval",
            lambda tl: my_eval(env, tl.val) if type(tl) is Quoted
                else (my_eval(env, tl) if type(tl) is Sym else tl),
            (1, 1)
        ),
    }
