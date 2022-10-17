from __future__ import annotations

from fractions import Fraction
from typing import TYPE_CHECKING, NamedTuple

import numpy as np

from auto_editor.interpreter import run_interpreter
from auto_editor.objs.tl import ASpace, TlAudio, TlVideo, VSpace
from auto_editor.utils.chunks import Chunks, chunkify, chunks_len, merge_chunks
from auto_editor.utils.func import apply_margin, cook, seconds_to_ticks, set_range

if TYPE_CHECKING:
    from auto_editor.ffwrapper import FileInfo
    from auto_editor.output import Ensure
    from auto_editor.utils.bar import Bar
    from auto_editor.utils.log import Log
    from auto_editor.utils.types import Margin


class Clip(NamedTuple):
    start: int
    dur: int
    offset: int
    speed: float
    src: str


def clipify(chunks: Chunks, src: str, start: Fraction = Fraction(0)) -> list[Clip]:
    clips: list[Clip] = []
    i = 0
    for chunk in chunks:
        if chunk[2] != 99999:
            if i == 0:
                dur = chunk[1] - chunk[0]
                offset = chunk[0]
            else:
                dur = chunk[1] - chunk[0]
                offset = chunk[0] + 1

            if not (len(clips) > 0 and clips[-1].start == round(start)):
                clips.append(Clip(round(start), dur, offset, chunk[2], src))
            start += Fraction(dur, Fraction(chunk[2]))
            i += 1

    return clips


def make_av(
    all_clips: list[list[Clip]], sources: dict[str, FileInfo], inputs: list[int]
) -> tuple[VSpace, ASpace]:
    vclips: VSpace = []

    max_a = 0
    for inp in inputs:
        max_a = max(max_a, len(sources[str(inp)].audios))

    aclips: ASpace = [[] for a in range(max_a)]

    for clips, inp in zip(all_clips, inputs):
        src = sources[str(inp)]
        if len(src.videos) > 0:
            for clip in clips:
                vclip_ = TlVideo(
                    clip.start, clip.dur, clip.src, clip.offset, clip.speed, 0
                )
                if len(vclips) == 0:
                    vclips = [[vclip_]]
                else:
                    vclips[0].append(vclip_)
        if len(src.audios) > 0:
            for clip in clips:
                for a, _ in enumerate(src.audios):
                    aclips[a].append(
                        TlAudio(
                            clip.start,
                            clip.dur,
                            clip.src,
                            clip.offset,
                            clip.speed,
                            1,
                            a,
                        )
                    )

    return vclips, aclips


def make_layers(
    sources: dict[str, FileInfo],
    inputs: list[int],
    ensure: Ensure,
    tb: Fraction,
    method: str,
    margin: Margin,
    _min_cut: str | int,
    _min_clip: str | int,
    cut_out: list[list[str]],
    add_in: list[list[str]],
    mark_silent: list[list[str]],
    mark_loud: list[list[str]],
    speed_range: list[tuple[float, str, str]],
    silent_speed: float,
    loud_speed: float,
    bar: Bar,
    temp: str,
    log: Log,
) -> tuple[Chunks, VSpace, ASpace]:
    start = Fraction(0)
    all_clips: list[list[Clip]] = []
    all_chunks: list[Chunks] = []

    start_margin, end_margin = margin
    start_margin = seconds_to_ticks(start_margin, tb)
    end_margin = seconds_to_ticks(end_margin, tb)
    min_clip = seconds_to_ticks(_min_clip, tb)
    min_cut = seconds_to_ticks(_min_cut, tb)

    strict = len(inputs) < 2

    for i in inputs:
        src = sources[str(i)]
        has_loud = run_interpreter(method, src, ensure, strict, tb, bar, temp, log)
        has_loud_length = len(has_loud)

        if len(mark_loud) > 0:
            has_loud = set_range(has_loud, mark_loud, tb, loud_speed, log)

        if len(mark_silent) > 0:
            has_loud = set_range(has_loud, mark_silent, tb, silent_speed, log)

        has_loud = cook(has_loud, min_clip, min_cut)
        has_loud = apply_margin(has_loud, has_loud_length, start_margin, end_margin)

        # Remove small clips/cuts created by applying other rules.
        has_loud = cook(has_loud, min_clip, min_cut)

        # Setup for handling custom speeds
        has_loud = has_loud.astype(np.uint)
        del has_loud_length

        speed_map = [silent_speed, loud_speed]
        speed_hash = {
            0: silent_speed,
            1: loud_speed,
        }

        def get_speed(speed: float) -> int:
            if speed in speed_map:
                return speed_map.index(speed)
            speed_map.append(speed)
            speed_hash[len(speed_map) - 1] = speed
            return len(speed_map) - 1

        if len(cut_out) > 0:
            index = get_speed(99999)
            has_loud = set_range(has_loud, cut_out, tb, index, log)

        if len(add_in) > 0:
            # Set speed index to 'loud_speed'
            has_loud = set_range(has_loud, add_in, tb, 1, log)

        for item in speed_range:
            index = get_speed(item[0])
            has_loud = set_range(has_loud, [list(item[1:])], tb, index, log)

        chunks = chunkify(has_loud, speed_hash)

        all_chunks.append(chunks)
        all_clips.append(clipify(chunks, str(i), start))
        start += round(chunks_len(chunks))

    vclips, aclips = make_av(all_clips, sources, inputs)

    return merge_chunks(all_chunks), vclips, aclips
