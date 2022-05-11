from typing import Any, Callable, Dict, List, NamedTuple, Tuple, Union, Optional
from dataclasses import dataclass, asdict, fields

import numpy as np

from auto_editor.cutting import chunkify
from auto_editor.ffwrapper import FileInfo
from auto_editor.method import get_speed_list
from auto_editor.objects import (
    AudioObj,
    EllipseObj,
    ImageObj,
    RectangleObj,
    TextObj,
    VideoObj,
)
from auto_editor.utils.func import parse_dataclass
from auto_editor.utils.log import Log
from auto_editor.utils.progressbar import ProgressBar
from auto_editor.utils.types import (
    AlignType,
    align_type,
    anchor_type,
    color_type,
    float_type,
)

Clip = NamedTuple(
    "Clip", [("start", int), ("dur", int), ("offset", int), ("speed", float)]
)


def clipify(chunks: List[Tuple[int, int, float]]) -> List[Clip]:
    clips = []
    start = 0
    for chunk in chunks:
        if chunk[2] != 99999:
            dur = chunk[1] - chunk[0]
            clips.append(Clip(start, dur, chunk[0], chunk[2]))
            start += dur

    return clips


def unclipify(layer: List[Clip]) -> np.ndarray:
    l: List[Optional[int]] = []
    for clip in layer:
        b = list(range(clip.offset, clip.offset + clip.dur))

        while clip.start > len(l):
            l.append(None)

        for item in b:
            l.append(item)

    if None in l or len(set(l)) != len(l) or sorted(l) != l:
        raise ValueError(f"Clip layer to complex, cannot convert to speed list: {l}")

    arr = np.empty(layer[-1].offset + layer[-1].dur, dtype=float)
    arr.fill(99999)

    for clip in layer:
        arr[clip.offset : clip.offset + clip.dur] = clip.speed

    return arr


def _values(
    name: str,
    val: Union[int, str, float],
    _type: Union[type, Callable[[Any], Any]],
    _vars: Dict[str, int],
    log: Log,
):
    if _type is Any:
        return None
    if _type is float and name != "rotate":
        _type = float_type
    elif _type == AlignType:
        _type = align_type
    elif name == "anchor":
        _type = anchor_type
    elif name in ("fill", "strokecolor"):
        _type = color_type

    if _type is int:
        for key, item in _vars.items():
            if val == key:
                return item

    try:
        _type(val)
    except TypeError as e:
        log.error(str(e))
    except Exception:
        log.error(f"variable '{val}' is not defined.")

    return _type(val)


class Timeline:
    def __init__(
        self,
        fps: float,
        samplerate: int,
        res: Tuple[int, int],
        background: str,
        chunks: List[Tuple[int, int, float]],
        inp: FileInfo,
        log: Log,
    ):

        vclips: List[List[VideoObj]] = [[] for v in inp.videos]
        aclips: List[List[AudioObj]] = [[] for a in inp.audios]

        self.fps = fps
        self.samplerate = samplerate
        self.res = res

        self.chunks = chunks
        clips = clipify(self.chunks)

        for v, _ in enumerate(inp.videos):
            for clip in clips:
                vclips[v].append(
                    VideoObj(clip.start, clip.dur, clip.offset, clip.speed, inp.path)
                )

        for a, _ in enumerate(inp.audios):
            for clip in clips:
                aclips[a].append(
                    AudioObj(clip.start, clip.dur, clip.offset, clip.speed, inp.path, a)
                )

        self.aclips = aclips
        self.vclips = vclips
        self.background = background
        self.inp = inp


def make_timeline(
    inputs: List[FileInfo], args, progress: ProgressBar, temp: str, log: Log
) -> Timeline:
    assert len(inputs) == 1

    inp = inputs[0]

    if args.frame_rate is None:
        fps = inp.get_fps()
    else:
        fps = args.frame_rate

    if args.sample_rate is None:
        samplerate = inp.get_samplerate()
    else:
        samplerate = args.sample_rate

    res = inp.get_res()

    speedlist = get_speed_list(0, inp, fps, args, progress, temp, log)
    chunks = chunkify(speedlist)

    # TODO: Calculate timeline duration

    w, h = res
    _vars: Dict[str, int] = {
        "width": w,
        "height": h,
        "centerX": w // 2,
        "centerY": h // 2,
        "start": 0,
        "end": 0,  # TODO: deal with this
    }

    # self.all = []
    # self.sheet: Dict[int, List[int]] = {}

    # pool = []

    # for o in args.add_text:
    #     pool.append(parse_dataclass(o, TextObj, log))
    # for o in args.add_rectangle:
    #     pool.append(parse_dataclass(o, RectangleObj, log))
    # for o in args.add_ellipse:
    #     pool.append(parse_dataclass(o, EllipseObj, log))
    # for o in args.add_image:
    #     pool.append(parse_dataclass(o, ImageObj, log))

    # for index, obj in enumerate(pool):

    #     dic_value = asdict(obj)
    #     dic_type = {}
    #     for field in fields(obj):
    #         dic_type[field.name] = field.type

    #     # Convert to the correct types
    #     for k, _type in dic_type.items():
    #         obj.__setattr__(k, _values(k, dic_value[k], _type, _vars, log))

    #     if obj.dur < 1:
    #         log.error(f"dur's value must be greater than 0. Was '{obj.dur}'.")

    #     for frame in range(obj.start, obj.start + obj.dur, 1):
    #         if frame in self.sheet:
    #             self.sheet[frame].append(index)
    #         else:
    #             self.sheet[frame] = [index]

    #     self.all.append(obj)

    return Timeline(fps, samplerate, res, args.background, chunks, inp, log)
