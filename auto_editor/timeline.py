from dataclasses import asdict, dataclass, fields
from typing import Any, Callable, Dict, List, NamedTuple, Optional, Tuple, Union

import numpy as np
from numpy.typing import NDArray

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
from auto_editor.utils.func import chunkify, parse_dataclass
from auto_editor.utils.log import Log
from auto_editor.utils.progressbar import ProgressBar
from auto_editor.utils.types import Align, Chunks, align, anchor, color, number

Clip = NamedTuple(
    "Clip",
    [("start", int), ("dur", int), ("offset", int), ("speed", float), ("src", int)],
)

Visual = Union[TextObj, ImageObj, RectangleObj, EllipseObj]
VLayer = List[Union[VideoObj, Visual]]
VSpace = List[VLayer]

ALayer = List[AudioObj]
ASpace = List[ALayer]


def unclipify(layer: List[Clip]) -> NDArray[np.float_]:
    l: List[int] = []
    for clip in layer:
        if clip.src != 0:
            raise ValueError("Clip has src that is not 0")

        if clip.start > len(l):
            raise ValueError(
                f"Clip layer has null frames, cannot convert speed list: {l}"
            )

        for item in range(clip.offset, clip.offset + clip.dur):
            l.append(item)

    if len(set(l)) != len(l) or sorted(l) != l:
        raise ValueError(f"Clip layer to complex, cannot convert to speed list: {l}")

    arr = np.empty(layer[-1].offset + layer[-1].dur, dtype=float)
    arr.fill(99999)

    for clip in layer:
        arr[clip.offset : clip.offset + clip.dur] = clip.speed

    return arr


def _values(
    name: str,
    val: Union[float, str],
    _type: Union[type, Callable[[Any], Any]],
    _vars: Dict[str, int],
    log: Log,
):
    if _type is Any:
        return None
    if _type is float and name != "rotate":
        _type = number
    elif _type == Align:
        _type = align
    elif name == "anchor":
        _type = anchor
    elif name in ("fill", "strokecolor"):
        _type = color

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


@dataclass
class Timeline:
    inputs: List[FileInfo]
    fps: float
    samplerate: int
    res: Tuple[int, int]
    background: str
    v: VSpace
    a: ASpace
    chunks: Optional[Chunks] = None

    @property
    def inp(self) -> FileInfo:
        return self.inputs[0]

    def out_len(self) -> float:
        out_len: float = 0
        for vclips in self.v:
            dur: float = 0
            for v_obj in vclips:
                if isinstance(v_obj, VideoObj):
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


def clipify(chunks: Chunks, src: int) -> List[Clip]:
    clips = []
    start = 0
    # Add "+1" to match how chunks are rendered in 22w18a
    i = 0
    for chunk in chunks:
        if chunk[2] != 99999:
            if i == 0:
                dur = chunk[1] - chunk[0] + 1
                offset = chunk[0]
            else:
                dur = chunk[1] - chunk[0]
                offset = chunk[0] + 1

            clips.append(Clip(start, dur, offset, chunk[2], src))
            start += dur
            i += 1

    # If Chunks equals: [
    #    (0, 26, 1.0),
    #    (26, 34, 99999.0),
    #    (34, 396, 1.0),
    #    (396, 410, 99999.0),
    #    (410, 522, 1.0), (522, 1192, 99999.0),
    #    (1192, 1220, 1.0),
    #    (1220, 1273, 99999.0)
    # ]
    # try:
    #     assert clips == [
    #         Clip(start=0, dur=27, offset=0, speed=1.0, src=0),
    #         Clip(start=27, dur=362, offset=35, speed=1.0, src=0),
    #         Clip(start=27 + 362, dur=112, offset=411, speed=1.0, src=0),
    #         Clip(start=27 + 362 + 112, dur=28, offset=1193, speed=1.0, src=0),
    #     ]
    # except AssertionError:
    #     for clip in clips:
    #         print(clip)
    #     quit(1)

    return clips


def make_av(clips: List[Clip], inp: FileInfo) -> Tuple[VSpace, ASpace]:

    vclips: VSpace = [[]]
    aclips: ASpace = [[] for a in inp.audios]

    for clip in clips:
        vclips[0].append(
            VideoObj(clip.start, clip.dur, clip.offset, clip.speed, clip.src)
        )

    for a, _ in enumerate(inp.audios):
        for clip in clips:
            aclips[a].append(
                AudioObj(clip.start, clip.dur, clip.offset, clip.speed, clip.src, a)
            )

    return vclips, aclips


def make_layers(
    inputs: List[FileInfo], speedlists: List[NDArray[np.float_]]
) -> Tuple[int, Optional[Chunks], VSpace, ASpace]:

    clips = []
    for i, _chunks in enumerate([chunkify(s) for s in speedlists]):
        clips += clipify(_chunks, i)

    if len(clips) == 0:
        end = 0
    else:
        e = clips[-1]
        end = round(e.start + (e.dur * e.speed))

    chunks: Optional[Chunks] = None
    try:
        chunks = chunkify(unclipify(clips))
    except ValueError:
        pass

    vclips, aclips = make_av(clips, inputs[0])
    return end, chunks, vclips, aclips


def make_timeline(
    inputs: List[FileInfo], args, sr: int, progress: ProgressBar, temp: str, log: Log
) -> Timeline:
    assert len(inputs) > 0

    inp = inputs[0]

    if args.frame_rate is None:
        fps = inp.get_fps()
    else:
        fps = args.frame_rate

    res = inp.get_res()

    speedlists = []
    for i, inp in enumerate(inputs):
        speedlists.append(get_speed_list(i, inp, fps, args, progress, temp, log))

    end, chunks, vclips, aclips = make_layers(inputs, speedlists)

    timeline = Timeline(inputs, fps, sr, res, args.background, vclips, aclips, chunks)

    w, h = res
    _vars: Dict[str, int] = {
        "width": w,
        "height": h,
        "centerX": w // 2,
        "centerY": h // 2,
        "start": 0,
        "end": end,
    }

    pool = []

    for o in args.add_text:
        pool.append(parse_dataclass(o, TextObj, log))
    for o in args.add_rectangle:
        pool.append(parse_dataclass(o, RectangleObj, log))
    for o in args.add_ellipse:
        pool.append(parse_dataclass(o, EllipseObj, log))
    for o in args.add_image:
        pool.append(parse_dataclass(o, ImageObj, log))

    for obj in pool:
        dic_value = asdict(obj)
        dic_type = {}
        for field in fields(obj):
            dic_type[field.name] = field.type

        # Convert to the correct types
        for k, _type in dic_type.items():
            obj.__setattr__(k, _values(k, dic_value[k], _type, _vars, log))

        if obj.dur < 1:
            log.error(f"dur's value must be greater than 0. Was '{obj.dur}'.")

    # Higher layers are visually on top
    for obj in pool:
        timeline.v.append([obj])

    return timeline
