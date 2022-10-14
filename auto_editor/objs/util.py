from __future__ import annotations

from fractions import Fraction
from typing import Any, NamedTuple, TypedDict, TypeVar

from auto_editor.utils.func import seconds_to_ticks
from auto_editor.utils.log import Log
from auto_editor.utils.types import pos, time

T = TypeVar("T")


class _Vars(TypedDict, total=False):
    width: int
    height: int
    end: int
    tb: Fraction


class Attr(NamedTuple):
    names: tuple[str, ...]
    coerce: Any
    default: Any


def parse_dataclass(
    attrs_str: str,
    definition: tuple[type[T], list[Attr]],
    log: Log,
    _vars: _Vars = {},
    coerce_default: bool = False,
) -> T:

    dataclass, builder = definition

    ARG_SEP = ","
    KEYWORD_SEP = "="

    # Positional Arguments
    #    --rectangle 0,end,10,20,20,30,#000, ...
    # Keyword Arguments
    #    --rectangle start=0,dur=end,x1=10, ...

    def _values(name: str, val: Any, _type: Any, _vars: _Vars, log: Log) -> Any:
        if val is None:
            return None

        if name in ("start", "dur", "offset"):
            assert "tb" in _vars and "end" in _vars
            if isinstance(val, int):
                return val

            assert isinstance(val, str)

            if val == "start":
                return 0
            if val == "end":
                return _vars["end"]

            return seconds_to_ticks(time(val), _vars["tb"])

        if name in ("x", "width"):
            assert "width" in _vars
            return pos((val, _vars["width"]))

        if name in ("y", "height"):
            assert "height" in _vars
            return pos((val, _vars["height"]))

        try:
            _type(val)
        except TypeError as e:
            log.error(e)
        except Exception:
            log.error(f"{name}: variable '{val}' is not defined.")

        return _type(val)

    kwargs: dict[str, Any] = {}
    for attr in builder:
        key = attr.names[0]
        if coerce_default:
            kwargs[key] = _values(key, attr.default, attr.coerce, _vars, log)
        else:
            kwargs[key] = attr.default

    if attrs_str == "":
        for k, v in kwargs.items():
            if v is None:
                log.error(f"'{k}' must be specified.")
        return dataclass(**kwargs)

    d_name = dataclass.__name__
    allow_positional_args = True

    for i, arg in enumerate(attrs_str.split(ARG_SEP)):
        if i + 1 > len(builder):
            log.error(f"{d_name} has too many arguments, starting with '{arg}'.")

        if KEYWORD_SEP in arg:
            allow_positional_args = False

            parameters = arg.split(KEYWORD_SEP)
            if len(parameters) > 2:
                log.error(f"{d_name} invalid syntax: '{arg}'.")

            key, val = parameters
            found = False
            for attr in builder:
                if key in attr.names:
                    kwargs[attr.names[0]] = _values(
                        attr.names[0], val, attr.coerce, _vars, log
                    )
                    found = True
                    break

            if not found:
                from difflib import get_close_matches

                keys = set()
                for attr in builder:
                    for name in attr.names:
                        keys.add(name)

                more = ""
                if matches := get_close_matches(key, keys):
                    more = f"\n    Did you mean:\n        {', '.join(matches)}"

                log.error(f"{d_name} got an unexpected keyword '{key}'\n{more}")

        elif allow_positional_args:
            key = builder[i].names[0]
            kwargs[key] = _values(key, arg, builder[i].coerce, _vars, log)
        else:
            log.error(f"{d_name} positional argument follows keyword argument.")

    for k, v in kwargs.items():
        if v is None:
            log.error(f"'{k}' must be specified.")
    return dataclass(**kwargs)
