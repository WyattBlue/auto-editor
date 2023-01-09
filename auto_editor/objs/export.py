from __future__ import annotations

from dataclasses import dataclass
from typing import Union


@dataclass
class ExDefault:
    pass


@dataclass
class ExPremiere:
    name: str | None = None


@dataclass
class ExFinalCutPro:
    name: str | None = None


@dataclass
class ExShotCut:
    pass


@dataclass
class ExJson:
    api: str = "3"


@dataclass
class ExTimeline:
    api: str


@dataclass
class ExAudio:
    pass


@dataclass
class ExClipSequence:
    pass


Exports = Union[
    ExDefault,
    ExPremiere,
    ExFinalCutPro,
    ExShotCut,
    ExJson,
    ExTimeline,
    ExAudio,
    ExClipSequence,
]
