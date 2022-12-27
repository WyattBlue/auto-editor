from __future__ import annotations

from dataclasses import dataclass
from typing import Union


@dataclass
class ExDefault:
    pass


@dataclass
class ExPremiere:
    pass


@dataclass
class ExFinalCutPro:
    pass


@dataclass
class ExShotCut:
    pass


@dataclass
class ExJson:
    api: str


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
