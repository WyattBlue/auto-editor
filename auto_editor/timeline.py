from dataclasses import asdict, dataclass, fields
from typing import Any, Callable, Dict, List, NamedTuple, Optional, Tuple, Type, Union

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
from auto_editor.utils.func import chunkify, chunks_len, parse_dataclass
from auto_editor.utils.log import Log
from auto_editor.utils.progressbar import ProgressBar
from auto_editor.utils.types import (
    Align,
    Args,
    Chunks,
    align,
    anchor,
    color,
    number,
    pos,
)


class Clip(NamedTuple):
    start: int
    dur: int
    offset: int
    speed: float
    src: int


Visual = Type[Union[TextObj, ImageObj, RectangleObj, EllipseObj]]
VLayer = List[Union[VideoObj, Visual]]
VSpace = List[VLayer]

ALayer = List[AudioObj]
ASpace = List[ALayer]


def merge_chunks(all_chunks: List[Chunks]) -> Chunks:
    chunks = []
    start = 0
    for _chunks in all_chunks:
        for chunk in _chunks:
            chunks.append((chunk[0] + start, chunk[1] + start, chunk[2]))
        if _chunks:
            start += _chunks[-1][1]

    return chunks


def _values(
    name: str,
    val: Union[float, str],
    _type: Union[type, Callable[[Any], Any]],
    _vars: Dict[str, int],
    log: Log,
) -> Any:
    if name in ("x", "width"):
        return pos((val, _vars["width"]))
    elif name in ("y", "height"):
        return pos((val, _vars["height"]))
    elif name == "content":
        assert isinstance(val, str)
        return val.replace("\\n", "\n").replace("\\;", ",")
    elif _type is float:
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
        log.error(e)
    except Exception:
        log.error(f"{name}: variable '{val}' is not defined.")

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

    @property
    def end(self) -> int:
        end = 0
        for vclips in self.v:
            if len(vclips) > 0:
                v = vclips[-1]
                if isinstance(v, VideoObj):
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


def clipify(chunks: Chunks, src: int, start: float) -> List[Clip]:
    clips: List[Clip] = []
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

            if not (len(clips) > 0 and clips[-1].start == round(start)):
                clips.append(Clip(round(start), dur, offset, chunk[2], src))
            start += dur / chunk[2]
            i += 1

    return clips


def make_av(
    all_clips: List[List[Clip]], inputs: List[FileInfo]
) -> Tuple[VSpace, ASpace]:
    vclips: VSpace = [[]]

    max_a = 0
    for inp in inputs:
        max_a = max(max_a, len(inp.audios))

    aclips: ASpace = [[] for a in range(max_a)]

    for clips, inp in zip(all_clips, inputs):
        if len(inp.videos) > 0:
            for clip in clips:
                vclips[0].append(
                    VideoObj(clip.start, clip.dur, clip.offset, clip.speed, clip.src)
                )
        if len(inp.audios) > 0:
            for clip in clips:
                for a, _ in enumerate(inp.audios):
                    aclips[a].append(
                        AudioObj(
                            clip.start, clip.dur, clip.offset, clip.speed, clip.src, a
                        )
                    )

    return vclips, aclips


def make_timeline(
    inputs: List[FileInfo],
    args: Args,
    sr: int,
    progress: ProgressBar,
    temp: str,
    log: Log,
) -> Timeline:

    if inputs:
        fps = inputs[0].get_fps() if args.frame_rate is None else args.frame_rate
        res = inputs[0].get_res() if args.resolution is None else args.resolution
    else:
        fps, res = 30.0, (1920, 1080)

    def make_layers(inputs: List[FileInfo]) -> Tuple[Chunks, VSpace, ASpace]:
        start = 0.0
        all_clips: List[List[Clip]] = []
        all_chunks: List[Chunks] = []

        for i in range(len(inputs)):
            _chunks = chunkify(
                get_speed_list(i, inputs, fps, args, progress, temp, log)
            )
            all_chunks.append(_chunks)
            all_clips.append(clipify(_chunks, i, start))
            start += chunks_len(_chunks)

        vclips, aclips = make_av(all_clips, inputs)
        return merge_chunks(all_chunks), vclips, aclips

    chunks, vclips, aclips = make_layers(inputs)

    timeline = Timeline(inputs, fps, sr, res, args.background, vclips, aclips, chunks)

    w, h = res
    _vars: Dict[str, int] = {
        "width": w,
        "height": h,
        "start": 0,
        "end": timeline.end,
    }

    pool: List[Visual] = []
    for key, obj_str in args.pool:
        if key == "add_text":
            pool.append(parse_dataclass(obj_str, TextObj, log))
        if key == "add_rectangle":
            pool.append(parse_dataclass(obj_str, RectangleObj, log))
        if key == "add_ellipse":
            pool.append(parse_dataclass(obj_str, EllipseObj, log))
        if key == "add_image":
            pool.append(parse_dataclass(obj_str, ImageObj, log))

    for obj in pool:
        dic_value = asdict(obj)
        dic_type: Dict[str, Callable[[Any], Any]] = {}
        for field in fields(obj):
            dic_type[field.name] = field.type

        # Convert to the correct types
        for k, _type in dic_type.items():
            setattr(obj, k, _values(k, dic_value[k], _type, _vars, log))

        if obj.dur < 1:
            log.error(f"dur's value must be greater than 0. Was '{obj.dur}'.")

        # Higher layers are visually on top
        timeline.v.append([obj])

    return timeline
