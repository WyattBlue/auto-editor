from __future__ import annotations

from dataclasses import dataclass
from fractions import Fraction
from typing import Union

from auto_editor.ffwrapper import FileInfo
from auto_editor.lib.contracts import *
from auto_editor.objs.util import Attr, Attrs, Required, smallAttr, smallAttrs
from auto_editor.utils.chunks import Chunks, v2Chunks
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
            "version": "1.0",
            "source": self.source.path.resolve(),
            "chunks": self.chunks,
        }


@dataclass
class v2:
    """
    v2 timeline constructor

    Like v1 but allows for (nameless) multiple inputs and a custom timebase
    """

    sources: list[FileInfo]
    tb: Fraction
    sr: int
    res: tuple[int, int]
    chunks: v2Chunks

    def as_dict(self) -> dict:
        return {
            "version": "2.0",
            "timebase": f"{self.tb.numerator}/{self.tb.denominator}",
            "samplerate": self.sr,
            "sources": [s.path.resolve() for s in self.sources],
            "chunks": self.chunks,
        }


"""
timeline v3 classes
"""


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


video_builder = smallAttrs(
    "video",
    smallAttr("start", Required, is_uint),
    smallAttr("dur", Required, is_uint),
    smallAttr("src", Required, any_p),
    smallAttr("offset", 0, is_int),
    smallAttr("speed", 1, is_real),
    smallAttr("stream", 0, is_uint),
)
audio_builder = smallAttrs(
    "audio",
    smallAttr("start", Required, is_uint),
    smallAttr("dur", Required, is_uint),
    smallAttr("src", Required, any_p),
    smallAttr("offset", 0, is_int),
    smallAttr("speed", 1, is_real),
    smallAttr("volume", 1, is_real),
    smallAttr("stream", 0, is_uint),
)
text_builder = smallAttrs(
    "text",
    smallAttr("start", Required, is_uint),
    smallAttr("dur", Required, is_uint),
    smallAttr("content", Required, is_str),
    smallAttr("x", 0.5, is_real),
    smallAttr("y", 0.5, is_real),
    smallAttr("font", "Arial", is_str),
    smallAttr("size", 55, is_uint),
    smallAttr("align", "left", is_str),
    smallAttr("opacity", 1, is_threshold),
    smallAttr("anchor", "ce", is_str),
    smallAttr("rotate", 0, is_real),
    smallAttr("fill", "#FFF", is_str),
    smallAttr("stroke", 0, is_uint),
    smallAttr("strokecolor", "#000", is_str),
)

img_builder = smallAttrs(
    "image",
    smallAttr("start", Required, is_uint),
    smallAttr("dur", Required, is_uint),
    smallAttr("src", Required, any_p),
    smallAttr("x", 0.5, is_real),
    smallAttr("y", 0.5, is_real),
    smallAttr("opacity", 1, is_threshold),
    smallAttr("anchor", "ce", is_str),
    smallAttr("rotate", 0, is_real),
    smallAttr("stroke", 0, is_uint),
    smallAttr("strokecolor", "#000", is_str),
)

rect_builder = smallAttrs(
    "rect",
    smallAttr("start", Required, is_uint),
    smallAttr("dur", Required, is_uint),
    smallAttr("x", Required, is_real),
    smallAttr("y", Required, is_real),
    smallAttr("width", Required, is_real),
    smallAttr("height", Required, is_real),
    smallAttr("opacity", 1, is_threshold),
    smallAttr("anchor", "ce", is_str),
    smallAttr("rotate", 0, is_real),
    smallAttr("fill", "#c4c4c4", is_str),
    smallAttr("stroke", 0, is_uint),
    smallAttr("strokecolor", "#000", is_str),
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

timeline_builder = Attrs("timeline", Attr("api", str, "3.0.0"))

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

    @property
    def end(self) -> int:
        end = 0
        for vclips in self.v:
            if len(vclips) > 0:
                v = vclips[-1]
                if isinstance(v, TlVideo):
                    end = max(end, max(1, round(v.start + (v.dur / v.speed))))
                else:
                    end = max(end, v.start + v.dur)
        for aclips in self.a:
            if len(aclips) > 0:
                a = aclips[-1]
                end = max(end, max(1, round(a.start + (a.dur / a.speed))))

        return end

    def out_len(self) -> float:
        out_len: float = 0
        for vclips in self.v:
            dur: float = 0
            for v_obj in vclips:
                if isinstance(v_obj, TlVideo):
                    dur += v_obj.dur / v_obj.speed
                else:
                    dur += v_obj.dur
            out_len = max(out_len, dur)
        for aclips in self.a:
            dur = 0
            for aclip in aclips:
                dur += aclip.dur / aclip.speed
            out_len = max(out_len, dur)
        return out_len

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
            "version": "unstable:3.0",
            "timeline": {
                "resolution": self.res,
                "timebase": f"{self.tb.numerator}/{self.tb.denominator}",
                "samplerate": self.sr,
                "sources": sources,
                "background": self.background,
                "v": v,
                "a": a,
            },
        }
