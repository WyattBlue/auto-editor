from __future__ import annotations

import math

from auto_editor.lib.contracts import Proc, andc, between_c, gt_c, is_real


def all() -> dict[str, object]:
    return {
        "exp": Proc("exp", math.exp, (1, 1), is_real),
        "ceil": Proc("ceil", math.ceil, (1, 1), is_real),
        "floor": Proc("floor", math.floor, (1, 1), is_real),
        "sin": Proc("sin", math.sin, (1, 1), is_real),
        "cos": Proc("cos", math.cos, (1, 1), is_real),
        "tan": Proc("tan", math.tan, (1, 1), is_real),
        "asin": Proc("asin", math.asin, (1, 1), between_c(-1, 1)),
        "acos": Proc("acos", math.acos, (1, 1), between_c(-1, 1)),
        "atan": Proc("atan", math.atan, (1, 1), is_real),
        "log": Proc("log", math.log, (1, 2), andc(is_real, gt_c(0))),
        "pi": math.pi,
        "e": math.e,
        "tau": math.tau,
    }
