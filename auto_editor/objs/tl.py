from __future__ import annotations

from dataclasses import dataclass
from typing import Union

from auto_editor.utils.types import (
    Align,
    align,
    anchor,
    color,
    db_number,
    natural,
    number,
    src,
    threshold,
)

from .util import Attr


@dataclass
class TlVideo:
    start: int
    dur: int
    src: str
    offset: int
    speed: float
    stream: int


@dataclass
class TlAudio:
    start: int
    dur: int
    src: str
    offset: int
    speed: float
    volume: float
    stream: int


@dataclass
class _Visual:
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
class TlText(_Visual):
    content: str
    font: str
    size: int
    align: Align
    fill: str


@dataclass
class TlImage(_Visual):
    src: str


@dataclass
class TlRect(_Visual):
    width: int
    height: int
    fill: str


@dataclass
class TlEllipse(_Visual):
    width: int
    height: int
    fill: str


video_builder = [
    Attr(("start",), natural, None),
    Attr(("dur",), natural, None),
    Attr(("src",), src, None),
    Attr(("offset",), natural, 0),
    Attr(("speed",), number, 1),
    Attr(("stream", "track"), natural, 0),
]
audio_builder = [
    Attr(("start",), natural, None),
    Attr(("dur",), natural, None),
    Attr(("src",), src, None),
    Attr(("offset",), natural, 0),
    Attr(("speed",), number, 1),
    Attr(("volume",), db_number, 1),
    Attr(("stream", "track"), natural, 0),
]


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
    Attr(("src",), src, None),
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

timeline_builder = [Attr(("api",), str, "1.0.0")]

Visual = Union[TlText, TlImage, TlRect, TlEllipse]
VLayer = list[Union[TlVideo, Visual]]
VSpace = list[VLayer]

ALayer = list[TlAudio]
ASpace = list[ALayer]
