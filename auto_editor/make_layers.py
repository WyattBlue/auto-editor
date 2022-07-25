from __future__ import annotations

from fractions import Fraction
from typing import List, NamedTuple, Type, Union

from auto_editor.ffwrapper import FileInfo
from auto_editor.method import get_has_loud
from auto_editor.objects import (
    AudioObj,
    EllipseObj,
    ImageObj,
    RectangleObj,
    TextObj,
    VideoObj,
)
from auto_editor.utils.bar import Bar
from auto_editor.utils.chunks import Chunks, chunkify, chunks_len, merge_chunks
from auto_editor.utils.func import apply_margin, cook, set_range
from auto_editor.utils.log import Log
from auto_editor.utils.types import Margin

Visual = Type[Union[TextObj, ImageObj, RectangleObj, EllipseObj]]
VLayer = List[Union[VideoObj, Visual]]
VSpace = List[VLayer]

ALayer = List[AudioObj]
ASpace = List[ALayer]


class Clip(NamedTuple):
    start: int
    dur: int
    offset: int
    speed: float
    src: int


def clipify(chunks: Chunks, src: int, start: float) -> list[Clip]:
    clips: list[Clip] = []
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
    all_clips: list[list[Clip]], inputs: list[FileInfo]
) -> tuple[VSpace, ASpace]:
    vclips: VSpace = []

    max_a = 0
    for inp in inputs:
        max_a = max(max_a, len(inp.audios))

    aclips: ASpace = [[] for a in range(max_a)]

    for clips, inp in zip(all_clips, inputs):
        if len(inp.videos) > 0:
            for clip in clips:
                vclip_ = VideoObj(
                    clip.start, clip.dur, clip.offset, clip.speed, clip.src, 0
                )
                if len(vclips) == 0:
                    vclips = [[vclip_]]
                vclips[0].append(vclip_)
        if len(inp.audios) > 0:
            for clip in clips:
                for a, _ in enumerate(inp.audios):
                    aclips[a].append(
                        AudioObj(
                            clip.start, clip.dur, clip.offset, clip.speed, clip.src, a
                        )
                    )

    return vclips, aclips


def make_layers(
    inputs: list[FileInfo],
    tb: Fraction,
    method: str,
    margin: Margin,
    _min_cut: str | int,
    _min_clip: str | int,
    cut_out: list[list[str]],
    add_in: list[list[str]],
    mark_silent: list[list[str]],
    mark_loud: list[list[str]],
    set_speed_for_range: list[tuple[float, str, str]],
    silent_speed: float,
    loud_speed: float,
    bar: Bar,
    temp: str,
    log: Log,
) -> tuple[Chunks, VSpace, ASpace]:
    start = 0.0
    all_clips: list[list[Clip]] = []
    all_chunks: list[Chunks] = []

    def seconds_to_ticks(val: int | str, tb: Fraction) -> int:
        if isinstance(val, str):
            return int(float(val) * tb)
        return val

    start_margin, end_margin = margin
    start_margin = seconds_to_ticks(start_margin, tb)
    end_margin = seconds_to_ticks(end_margin, tb)
    min_clip = seconds_to_ticks(_min_clip, tb)
    min_cut = seconds_to_ticks(_min_cut, tb)

    for i in range(len(inputs)):
        has_loud = get_has_loud(method, i, inputs, tb, bar, temp, log)
        has_loud_length = len(has_loud)

        if len(mark_loud) > 0:
            has_loud = set_range(has_loud, mark_loud, tb, loud_speed, log)

        if len(mark_silent) > 0:
            has_loud = set_range(has_loud, mark_silent, tb, silent_speed, log)

        has_loud = cook(has_loud, min_clip, min_cut)
        has_loud = apply_margin(has_loud, has_loud_length, start_margin, end_margin)

        # Remove small clips/cuts created by applying other rules.
        has_loud = cook(has_loud, min_clip, min_cut)

        speed_list = has_loud.astype(float)
        del has_loud
        del has_loud_length

        # WARN: This breaks if speed is allowed to be 0
        speed_list[speed_list == 1] = loud_speed
        speed_list[speed_list == 0] = silent_speed

        if len(cut_out) > 0:
            speed_list = set_range(speed_list, cut_out, tb, 99999, log)

        if len(add_in) > 0:
            speed_list = set_range(speed_list, add_in, tb, loud_speed, log)

        for item in set_speed_for_range:
            speed_list = set_range(speed_list, [list(item[1:])], tb, item[0], log)

        _chunks = chunkify(speed_list)
        all_chunks.append(_chunks)
        all_clips.append(clipify(_chunks, i, start))
        start += round(chunks_len(_chunks))

    vclips, aclips = make_av(all_clips, inputs)
    return merge_chunks(all_chunks), vclips, aclips
