from __future__ import annotations

from collections.abc import Iterator
from dataclasses import dataclass
from fractions import Fraction
from typing import Any

from auto_editor.ffwrapper import FileInfo
from auto_editor.lib.contracts import *
from auto_editor.utils.chunks import Chunks
from auto_editor.utils.cmdkw import Required, pAttr, pAttrs
from auto_editor.utils.types import (
    anchor,
    color,
    natural,
    number,
    threshold,
)


@dataclass(slots=True)
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


@dataclass(slots=True)
class TlVideo:
    start: int
    dur: int
    src: FileInfo
    offset: int
    speed: float
    stream: int

    def as_dict(self) -> dict:
        return {
            "name": "video",
            "src": self.src,
            "start": self.start,
            "dur": self.dur,
            "offset": self.offset,
            "speed": self.speed,
            "stream": self.stream,
        }


@dataclass(slots=True)
class TlAudio:
    start: int
    dur: int
    src: FileInfo
    offset: int
    speed: float
    volume: float
    stream: int

    def as_dict(self) -> dict:
        return {
            "name": "audio",
            "src": self.src,
            "start": self.start,
            "dur": self.dur,
            "offset": self.offset,
            "speed": self.speed,
            "volume": self.volume,
            "stream": self.stream,
        }


@dataclass(slots=True)
class TlImage:
    start: int
    dur: int
    src: FileInfo
    x: int
    y: int
    width: int
    opacity: float
    anchor: str

    def as_dict(self) -> dict:
        return {
            "name": "image",
            "src": self.src,
            "start": self.start,
            "dur": self.dur,
            "x": self.x,
            "y": self.y,
            "width": self.width,
            "opacity": self.opacity,
            "anchor": self.anchor,
        }


@dataclass(slots=True)
class TlRect:
    start: int
    dur: int
    x: int
    y: int
    width: int
    height: int
    anchor: str
    fill: str

    def as_dict(self) -> dict:
        return {
            "name": "rect",
            "start": self.start,
            "dur": self.dur,
            "x": self.x,
            "y": self.y,
            "width": self.width,
            "height": self.height,
            "anchor": self.anchor,
            "fill": self.fill,
        }


video_builder = pAttrs(
    "video",
    pAttr("start", Required, is_nat, natural),
    pAttr("dur", Required, is_nat, natural),
    pAttr("src", Required, is_str, "source"),
    pAttr("offset", 0, is_int, natural),
    pAttr("speed", 1, is_real, number),
    pAttr("stream", 0, is_nat, natural),
)
audio_builder = pAttrs(
    "audio",
    pAttr("start", Required, is_nat, natural),
    pAttr("dur", Required, is_nat, natural),
    pAttr("src", Required, is_str, "source"),
    pAttr("offset", 0, is_int, natural),
    pAttr("speed", 1, is_real, number),
    pAttr("volume", 1, is_threshold, threshold),
    pAttr("stream", 0, is_nat, natural),
)
img_builder = pAttrs(
    "image",
    pAttr("start", Required, is_nat, natural),
    pAttr("dur", Required, is_nat, natural),
    pAttr("src", Required, is_str, "source"),
    pAttr("x", Required, is_int, int),
    pAttr("y", Required, is_int, int),
    pAttr("width", 0, is_nat, natural),
    pAttr("opacity", 1, is_threshold, threshold),
    pAttr("anchor", "ce", is_str, anchor),
)
rect_builder = pAttrs(
    "rect",
    pAttr("start", Required, is_nat, natural),
    pAttr("dur", Required, is_nat, natural),
    pAttr("x", Required, is_int, int),
    pAttr("y", Required, is_int, int),
    pAttr("width", Required, is_int, int),
    pAttr("height", Required, is_int, int),
    pAttr("anchor", "ce", is_str, anchor),
    pAttr("fill", "#c4c4c4", is_str, color),
)
visual_objects = {
    "rect": (TlRect, rect_builder),
    "image": (TlImage, img_builder),
    "video": (TlVideo, video_builder),
}

VLayer = list[TlVideo | TlImage | TlRect]
VSpace = list[VLayer]

ALayer = list[TlAudio]
ASpace = list[ALayer]


@dataclass
class v3:
    src: FileInfo | None  # Used as a template for timeline settings
    tb: Fraction
    sr: int
    res: tuple[int, int]
    background: str
    v: VSpace
    a: ASpace
    v1: v1 | None  # Is it v1 compatible (linear and only one source)?

    def __str__(self) -> str:
        result = f"""
global
 timebase {self.tb}
 samplerate {self.sr}
 res {self.res[0]}x{self.res[1]}

video\n"""

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

    @property
    def sources(self) -> Iterator[FileInfo]:
        for vclips in self.v:
            for v in vclips:
                if isinstance(v, TlVideo):
                    yield v.src
        for aclips in self.a:
            for a in aclips:
                yield a.src

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
        v = []
        for i, vlayer in enumerate(self.v):
            vb = [vobj.as_dict() for vobj in vlayer]
            if vb:
                v.append(vb)

        a = []
        for i, alayer in enumerate(self.a):
            ab = [aobj.as_dict() for aobj in alayer]
            if ab:
                a.append(ab)

        return {
            "version": "3",
            "resolution": self.res,
            "timebase": f"{self.tb.numerator}/{self.tb.denominator}",
            "samplerate": self.sr,
            "background": self.background,
            "v": v,
            "a": a,
        }
