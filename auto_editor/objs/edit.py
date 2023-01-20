from __future__ import annotations

from dataclasses import dataclass

from auto_editor.utils.types import (
    Stream,
    bool_coerce,
    db_threshold,
    natural,
    natural_or_none,
    stream,
    threshold,
    time,
)

from .util import Attr, Required


@dataclass
class Audio:
    threshold: float
    stream: Stream
    mincut: int | str
    minclip: int | str


@dataclass
class Motion:
    threshold: float
    stream: int
    blur: int
    width: int


@dataclass
class Pixeldiff:
    threshold: int
    stream: int


@dataclass
class Subtitle:
    pattern: str
    stream: int
    ignore_case: bool = False
    max_count: int | None = None


audio_builder = [
    Attr("threshold", db_threshold, 0.04),
    Attr("stream", stream, 0),
    Attr("mincut", time, 6),
    Attr("minclip", time, 3),
]
motion_builder = [
    Attr("threshold", threshold, 0.02),
    Attr("stream", natural, 0),
    Attr("blur", natural, 9),
    Attr("width", natural, 400),
]
pixeldiff_builder = [
    Attr("threshold", natural, 1),
    Attr("stream", natural, 0),
]
subtitle_builder = [
    Attr("pattern", str, Required),
    Attr("stream", stream, 0),
    Attr("ignore-case", bool_coerce, False),
    Attr("max-count", natural_or_none, None),
]
