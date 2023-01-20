from __future__ import annotations

from difflib import get_close_matches
from typing import TYPE_CHECKING, NamedTuple

if TYPE_CHECKING:
    from typing import Any, Callable, TypeVar

    T = TypeVar("T")


class ParserError(Exception):
    pass


class Required:
    pass


class Attr(NamedTuple):
    n: str
    coerce: Any
    default: Any


def _default_var_f(name: str, val: str, coerce: Any) -> Any:
    return coerce(val)


def _norm_name(s: str) -> str:
    # Python does not allow - in variable names
    return s.replace("-", "_")


def parse_dataclass(
    text: str,
    definition: tuple[type[T], list[Attr]],
    var_f: Callable[[str, str, Any], Any] = _default_var_f,
    coerce_default: bool = False,
) -> T:

    # Positional Arguments
    #    --rectangle 0,end,10,20,20,30,#000, ...
    # Keyword Arguments
    #    --rectangle start=0,dur=end,x1=10, ...

    KEYWORD_SEP = "="
    dataclass, builder = definition
    d_name = dataclass.__name__

    kwargs: dict[str, Any] = {}
    for attr in builder:
        if coerce_default and attr.default is not Required:
            kwargs[_norm_name(attr.n)] = var_f(attr.n, attr.default, attr.coerce)
        else:
            kwargs[_norm_name(attr.n)] = attr.default

    allow_positional_args = True

    for i, arg in enumerate(text.split(",")):
        if not arg:
            continue

        if i + 1 > len(builder):
            raise ParserError(
                f"{d_name} has too many arguments, starting with '{arg}'."
            )

        if KEYWORD_SEP in arg:
            key, val = arg.split(KEYWORD_SEP, 1)

            allow_positional_args = False
            found = False

            for attr in builder:
                if key == attr.n:
                    kwargs[_norm_name(attr.n)] = var_f(attr.n, val, attr.coerce)
                    found = True
                    break

            if not found:
                all_names = {attr.n for attr in builder}
                if matches := get_close_matches(key, all_names):
                    more = f"\n    Did you mean:\n        {', '.join(matches)}"
                else:
                    more = f"\n    keywords available:\n        {', '.join(all_names)}"

                raise ParserError(f"{d_name} got an unexpected keyword '{key}'\n{more}")

        elif allow_positional_args:
            name = builder[i].n
            kwargs[_norm_name(name)] = var_f(name, arg, builder[i].coerce)
        else:
            raise ParserError(f"{d_name} positional argument follows keyword argument.")

    for k, v in kwargs.items():
        if v is Required:
            raise ParserError(f"'{k}' must be specified.")

    return dataclass(**kwargs)
