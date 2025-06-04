from __future__ import annotations

from dataclasses import dataclass
from typing import TYPE_CHECKING

from auto_editor.ffwrapper import FileInfo, mux
from auto_editor.lib.contracts import *
from auto_editor.utils.cmdkw import Required, pAttr, pAttrs
from auto_editor.utils.types import CoerceError, natural, number, parse_color

if TYPE_CHECKING:
    from collections.abc import Iterator
    from fractions import Fraction
    from pathlib import Path

    from auto_editor.ffwrapper import FileInfo
    from auto_editor.utils.chunks import Chunks
    from auto_editor.utils.log import Log


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
class Clip:
    start: int
    dur: int
    src: FileInfo
    offset: int
    stream: int

    speed: float = 1.0
    volume: float = 1.0

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
class TlImage:
    start: int
    dur: int
    src: FileInfo
    x: int
    y: int
    width: int
    opacity: float

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
        }


@dataclass(slots=True)
class TlRect:
    start: int
    dur: int
    x: int
    y: int
    width: int
    height: int
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
            "fill": self.fill,
        }


def threshold(val: str | float) -> float:
    num = number(val)
    if num > 1 or num < 0:
        raise CoerceError(f"'{val}': Threshold must be between 0 and 1 (0%-100%)")
    return num


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
)
rect_builder = pAttrs(
    "rect",
    pAttr("start", Required, is_nat, natural),
    pAttr("dur", Required, is_nat, natural),
    pAttr("x", Required, is_int, int),
    pAttr("y", Required, is_int, int),
    pAttr("width", Required, is_int, int),
    pAttr("height", Required, is_int, int),
    pAttr("fill", "#c4c4c4", is_str, parse_color),
)
visual_objects = {
    "rect": (TlRect, rect_builder),
    "image": (TlImage, img_builder),
    "video": (Clip, video_builder),
}

VLayer = list[Clip | TlImage | TlRect]
VSpace = list[VLayer]
ASpace = list[list[Clip]]


@dataclass(slots=True)
class AudioTemplate:
    lang: str | None


@dataclass(slots=True)
class SubtitleTemplate:
    lang: str | None


@dataclass(slots=True)
class Template:
    sr: int
    layout: str
    res: tuple[int, int]
    audios: list[AudioTemplate]
    subtitles: list[SubtitleTemplate]

    @classmethod
    def init(
        self,
        src: FileInfo,
        sr: int | None = None,
        layout: str | None = None,
        res: tuple[int, int] | None = None,
    ) -> Template:
        alist = [AudioTemplate(x.lang) for x in src.audios]
        slist = [SubtitleTemplate(x.lang) for x in src.subtitles]

        if sr is None:
            sr = src.get_sr()

        if layout is None:
            layout = "stereo" if not src.audios else src.audios[0].layout

        if res is None:
            res = src.get_res()

        return Template(sr, layout, res, alist, slist)


@dataclass
class v3:
    tb: Fraction
    background: str
    template: Template
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
                if isinstance(obj, Clip):
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
                if isinstance(v, Clip):
                    yield v.src
        for aclips in self.a:
            for a in aclips:
                yield a.src

    def unique_sources(self) -> Iterator[FileInfo]:
        seen = set()
        for source in self.sources:
            if source.path not in seen:
                seen.add(source.path)
                yield source

    def __len__(self) -> int:
        result = 0
        for clips in self.v + self.a:
            if len(clips) > 0:
                lastClip = clips[-1]
                result = max(result, lastClip.start + lastClip.dur)

        return result

    def as_dict(self) -> dict:
        def aclip_to_dict(self: Clip) -> dict:
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

        v = []
        a = []
        for vlayer in self.v:
            vb = [vobj.as_dict() for vobj in vlayer]
            if vb:
                v.append(vb)
        for layer in self.a:
            ab = [aclip_to_dict(clip) for clip in layer]
            if ab:
                a.append(ab)

        return {
            "version": "3",
            "timebase": f"{self.tb.numerator}/{self.tb.denominator}",
            "background": self.background,
            "resolution": self.T.res,
            "samplerate": self.T.sr,
            "layout": self.T.layout,
            "v": v,
            "a": a,
        }

    @property
    def T(self) -> Template:
        return self.template

    @property
    def res(self) -> tuple[int, int]:
        return self.T.res

    @property
    def sr(self) -> int:
        return self.T.sr


def make_tracks_dir(tracks_dir: Path) -> None:
    from os import mkdir
    from shutil import rmtree

    try:
        mkdir(tracks_dir)
    except OSError:
        rmtree(tracks_dir)
        mkdir(tracks_dir)


def set_stream_to_0(tl: v3, log: Log) -> None:
    dir_exists = False
    cache: dict[Path, FileInfo] = {}

    def make_track(i: int, path: Path) -> FileInfo:
        nonlocal dir_exists

        fold = path.parent / f"{path.stem}_tracks"
        if not dir_exists:
            make_tracks_dir(fold)
            dir_exists = True

        newtrack = fold / f"{path.stem}_{i}.wav"
        if newtrack not in cache:
            mux(path, output=newtrack, stream=i)
            cache[newtrack] = FileInfo.init(f"{newtrack}", log)
        return cache[newtrack]

    for alayer in tl.a:
        for aobj in alayer:
            if aobj.stream > 0:
                aobj.src = make_track(aobj.stream, aobj.src.path)
                aobj.stream = 0
