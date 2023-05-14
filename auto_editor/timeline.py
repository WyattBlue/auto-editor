from __future__ import annotations

from dataclasses import dataclass
from fractions import Fraction
from typing import Any, Union

from auto_editor.ffwrapper import FileInfo
from auto_editor.lib.contracts import *
from auto_editor.utils.chunks import Chunks
from auto_editor.utils.cmdkw import Required, pAttr, pAttrs
from auto_editor.utils.types import Align


@dataclass
class v1:
    """
    v1 timeline constructor
    timebase is always the source's average fps

    """

    source: FileInfo
    chunks: Chunks

    def as_dict(self) -> dict:
        return {
            "version": "1",
            "source": f"{self.source.path.resolve()}",
            "chunks": self.chunks,
        }


class Tl:
    pass


@dataclass
class TlVideo(Tl):
    start: int
    dur: int
    src: str
    offset: int
    speed: float
    stream: int
    name: str = "video"


@dataclass
class TlAudio(Tl):
    start: int
    dur: int
    src: str
    offset: int
    speed: float
    volume: float
    stream: int
    name: str = "audio"


@dataclass
class _Visual(Tl):
    start: int
    dur: int
    x: int | float
    y: int | float
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
    name: str = "text"


@dataclass
class TlImage(_Visual):
    src: str
    name: str = "image"


@dataclass
class TlRect(_Visual):
    width: int
    height: int
    fill: str
    name: str = "rectangle"


@dataclass
class TlEllipse(_Visual):
    width: int
    height: int
    fill: str
    name: str = "ellipse"


video_builder = pAttrs(
    "video",
    pAttr("start", Required, is_uint),
    pAttr("dur", Required, is_uint),
    pAttr("src", Required, any_p),
    pAttr("offset", 0, is_int),
    pAttr("speed", 1, is_real),
    pAttr("stream", 0, is_uint),
)
audio_builder = pAttrs(
    "audio",
    pAttr("start", Required, is_uint),
    pAttr("dur", Required, is_uint),
    pAttr("src", Required, any_p),
    pAttr("offset", 0, is_int),
    pAttr("speed", 1, is_real),
    pAttr("volume", 1, is_real),
    pAttr("stream", 0, is_uint),
)
text_builder = pAttrs(
    "text",
    pAttr("start", Required, is_uint),
    pAttr("dur", Required, is_uint),
    pAttr("content", Required, is_str),
    pAttr("x", 0.5, is_real),
    pAttr("y", 0.5, is_real),
    pAttr("font", "Arial", is_str),
    pAttr("size", 55, is_uint),
    pAttr("align", "left", is_str),
    pAttr("opacity", 1, is_threshold),
    pAttr("anchor", "ce", is_str),
    pAttr("rotate", 0, is_real),
    pAttr("fill", "#FFF", is_str),
    pAttr("stroke", 0, is_uint),
    pAttr("strokecolor", "#000", is_str),
)

img_builder = pAttrs(
    "image",
    pAttr("start", Required, is_uint),
    pAttr("dur", Required, is_uint),
    pAttr("src", Required, any_p),
    pAttr("x", 0.5, is_real),
    pAttr("y", 0.5, is_real),
    pAttr("opacity", 1, is_threshold),
    pAttr("anchor", "ce", is_str),
    pAttr("rotate", 0, is_real),
    pAttr("stroke", 0, is_uint),
    pAttr("strokecolor", "#000", is_str),
)

rect_builder = pAttrs(
    "rect",
    pAttr("start", Required, is_uint),
    pAttr("dur", Required, is_uint),
    pAttr("x", Required, is_real),
    pAttr("y", Required, is_real),
    pAttr("width", Required, is_real),
    pAttr("height", Required, is_real),
    pAttr("opacity", 1, is_threshold),
    pAttr("anchor", "ce", is_str),
    pAttr("rotate", 0, is_real),
    pAttr("fill", "#c4c4c4", is_str),
    pAttr("stroke", 0, is_uint),
    pAttr("strokecolor", "#000", is_str),
)
ellipse_builder = rect_builder
visual_objects = {
    "rectangle": (TlRect, rect_builder),
    "ellipse": (TlEllipse, ellipse_builder),
    "text": (TlText, text_builder),
    "image": (TlImage, img_builder),
    "video": (TlVideo, video_builder),
}

audio_objects = {
    "audio": (TlAudio, audio_builder),
}

Visual = Union[TlText, TlImage, TlRect, TlEllipse]
VLayer = list[Union[TlVideo, Visual]]
VSpace = list[VLayer]

ALayer = list[TlAudio]
ASpace = list[ALayer]


@dataclass
class v3:
    sources: dict[str, FileInfo]
    tb: Fraction
    sr: int
    res: tuple[int, int]
    background: str
    v: VSpace
    a: ASpace
    v1: v1 | None  # v1 compatible?

    def __str__(self) -> str:
        result = "sources\n"
        for k, v in self.sources.items():
            result += f" [{k} -> {v.path}]\n"
        result += f"""
global
 timebase {self.tb}
 samplerate {self.sr}
 res {self.res[0]}x{self.res[1]}
"""
        result += "\nvideo\n"
        for i, layer in enumerate(self.v):
            result += f" v{i} "
            for obj in layer:
                if isinstance(obj, TlVideo):
                    result += (
                        f"[#:start {obj.start} #:dur {obj.dur} #:off {obj.offset}] "
                    )
                else:
                    result += f"[#:start {obj.start} #:dur {obj.dur}] "
            result += "\n"

        result += "\naudio\n"
        for i, alayer in enumerate(self.a):
            result += f" a{i} "
            for abj in alayer:
                result += f"[#:start {abj.start} #:dur {abj.dur} #:off {abj.offset}] "
            result += "\n"
        return result

    @property
    def end(self) -> int:
        end = 0
        for vclips in self.v:
            if vclips:
                v = vclips[-1]
                end = max(end, v.start + v.dur)

        for aclips in self.a:
            if aclips:
                a = aclips[-1]
                end = max(end, a.start + a.dur)

        return end

    def _duration(self, layer: Any) -> int:
        total_dur = 0
        for clips in layer:
            dur = 0
            for clip in clips:
                dur += clip.dur
            total_dur = max(total_dur, dur)
        return total_dur

    def out_len(self) -> int:
        # Calculates the duration of the timeline
        return max(self._duration(self.v), self._duration(self.a))

    def as_dict(self) -> dict:
        sources = {key: f"{src.path.resolve()}" for key, src in self.sources.items()}

        v = []
        for i, vlayer in enumerate(self.v):
            vb = [vobj.__dict__ for vobj in vlayer]
            if vb:
                v.append(vb)

        a = []
        for i, alayer in enumerate(self.a):
            ab = [aobj.__dict__ for aobj in alayer]
            if ab:
                a.append(ab)

        return {
            "version": "3",
            "resolution": self.res,
            "timebase": f"{self.tb.numerator}/{self.tb.denominator}",
            "samplerate": self.sr,
            "sources": sources,
            "background": self.background,
            "v": v,
            "a": a,
        }
