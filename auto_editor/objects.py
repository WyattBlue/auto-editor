from __future__ import annotations

from dataclasses import dataclass
from typing import Any, NamedTuple, TypeVar

from auto_editor.utils.log import Log
from auto_editor.utils.types import (
    Align,
    align,
    anchor,
    color,
    natural,
    number,
    pos,
    threshold,
)

# start - When the clip starts in the timeline
# dur - The duration of the clip in the timeline before speed is applied
# offset - When from the source to start playing the media at

T = TypeVar("T", bound=type)


class Attr(NamedTuple):
    names: tuple[str, ...]
    coerce: Any
    default: Any


def parse_dataclass(
    attrs_str: str,
    dataclass: T,
    builder: list[Attr],
    log: Log,
    _vars: dict[str, int] = {},
    coerce_default: bool = False,
) -> T:
    ARG_SEP = ","
    KEYWORD_SEP = "="

    # Positional Arguments
    #    --rectangle 0,end,10,20,20,30,#000, ...
    # Keyword Arguments
    #    --rectangle start=0,end=end,x1=10, ...

    def _values(name: str, val, _type, _vars: dict[str, int], log: Log):
        if val is None:
            return None
        if name in ("x", "width"):
            return pos((val, _vars["width"]))
        elif name in ("y", "height"):
            return pos((val, _vars["height"]))

        if _type is int:
            for key, item in _vars.items():
                if val == key:
                    return item

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


@dataclass
class VideoObj:
    start: int
    dur: int
    offset: int
    speed: float
    src: int
    stream: int


@dataclass
class AudioObj:
    start: int
    dur: int
    offset: int
    speed: float
    src: int
    stream: int


@dataclass
class Visual:
    start: int
    dur: int
    x: int
    y: int
    anchor: str
    opacity: float
    rotate: float
    stroke: int
    strokecolor: str


@dataclass
class TextObj(Visual):
    content: str
    font: str
    size: int
    align: Align
    fill: str


@dataclass
class ImageObj(Visual):
    src: str


@dataclass
class RectangleObj(Visual):
    width: int
    height: int
    fill: str


@dataclass
class EllipseObj(Visual):
    width: int
    height: int
    fill: str


video_builder = [
    Attr(("start",), natural, None),
    Attr(("dur",), natural, None),
    Attr(("offset",), natural, None),
    Attr(("speed",), number, None),
    Attr(("stream", "track"), natural, 0),
]
audio_builder = video_builder


def content(val: str) -> str:
    return val.replace("\\n", "\n").replace("\\;", ",")


text_builder = [
    Attr(("start",), natural, None),
    Attr(("dur",), natural, None),
    Attr(("content",), content, None),
    Attr(("x",), int, "50%"),
    Attr(("y",), int, "50%"),
    Attr(("font",), str, "Arial"),
    Attr(("size",), natural, 55),
    Attr(("align",), align, "left"),
    Attr(("opacity",), threshold, 1),
    Attr(("anchor",), anchor, "ce"),
    Attr(("rotate",), number, 0),
    Attr(("fill", "color"), str, "#FFF"),
    Attr(("stroke",), natural, 0),
    Attr(("strokecolor",), color, "#000"),
]

img_builder = [
    Attr(("start",), natural, None),
    Attr(("dur",), natural, None),
    Attr(("src",), str, None),
    Attr(("x",), int, "50%"),
    Attr(("y",), int, "50%"),
    Attr(("opacity",), threshold, 1),
    Attr(("anchor",), anchor, "ce"),
    Attr(("rotate",), number, 0),
    Attr(("stroke",), natural, 0),
    Attr(("strokecolor",), color, "#000"),
]

rect_builder = [
    Attr(("start",), natural, None),
    Attr(("dur",), natural, None),
    Attr(("x",), int, None),
    Attr(("y",), int, None),
    Attr(("width",), int, None),
    Attr(("height",), int, None),
    Attr(("opacity",), threshold, 1),
    Attr(("anchor",), anchor, "ce"),
    Attr(("rotate",), number, 0),
    Attr(("fill", "color"), color, "#c4c4c4"),
    Attr(("stroke",), natural, 0),
    Attr(("strokecolor",), color, "#000"),
]
ellipse_builder = rect_builder
