from __future__ import annotations

from dataclasses import dataclass

from auto_editor.utils.types import Stream, db_threshold, natural, stream, threshold

from .util import Attr


@dataclass
class Audio:
    threshold: float
    stream: Stream


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
class Random:
    threshold: float
    seed: int


audio_builder = [
    Attr(("threshold",), db_threshold, 0.04),
    Attr(("stream", "track"), stream, 0),
]
motion_builder = [
    Attr(("threshold",), threshold, 0.02),
    Attr(("stream", "track"), natural, 0),
    Attr(("blur",), natural, 9),
    Attr(("width",), natural, 400),
]
pixeldiff_builder = [
    Attr(("threshold",), natural, 1),
    Attr(("stream", "track"), natural, 0),
]
random_builder = [Attr(("threshold",), threshold, 0.5), Attr(("seed",), int, -1)]
