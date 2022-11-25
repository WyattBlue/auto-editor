from __future__ import annotations

from fractions import Fraction
from typing import TYPE_CHECKING, Any, NamedTuple

import numpy as np

from auto_editor.interpreter import (
    FileSetup,
    Interpreter,
    Lexer,
    MyError,
    Parser,
    cook,
    is_boolarr,
)
from auto_editor.objs.tl import ASpace, TlAudio, TlVideo, VSpace
from auto_editor.utils.chunks import Chunks, chunkify, chunks_len, merge_chunks
from auto_editor.utils.func import mut_margin
from auto_editor.utils.types import time

if TYPE_CHECKING:
    from numpy.typing import NDArray

    from auto_editor.ffwrapper import FileInfo
    from auto_editor.output import Ensure
    from auto_editor.utils.bar import Bar
    from auto_editor.utils.log import Log
    from auto_editor.utils.types import Margin

    BoolList = NDArray[np.bool_]


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

            if not (clips and clips[-1].start == round(start)):
                clips.append(Clip(round(start), dur, offset, chunk[2], src))
            start += Fraction(dur, Fraction(chunk[2]))
            i += 1

    return clips


def make_av(
    all_clips: list[list[Clip]], sources: dict[str, FileInfo], _inputs: list[int]
) -> tuple[VSpace, ASpace]:

    if len(_inputs) > 1000:
        raise ValueError("Number of file inputs can't be greater than 1000")

    inputs = [str(i) for i in _inputs]
    vtl: VSpace = []
    atl: ASpace = [[] for _ in range(max(len(sources[i].audios) for i in inputs))]

    for clips, inp in zip(all_clips, inputs):
        src = sources[inp]
        if src.videos:
            vtl.append(
                [TlVideo(c.start, c.dur, c.src, c.offset, c.speed, 0) for c in clips]
            )

        for c in clips:
            for a in range(len(src.audios)):
                atl[a].append(TlAudio(c.start, c.dur, c.src, c.offset, c.speed, 1, a))

    return vtl, atl


def run_interpreter(
    text: str,
    filesetup: FileSetup,
    log: Log,
) -> NDArray[np.bool_]:

    try:
        lexer = Lexer(text)
        parser = Parser(lexer)
        if log.is_debug:
            log.debug(f"edit: {parser}")

        interpreter = Interpreter(parser, filesetup)
        results = interpreter.interpret()
    except (MyError, ZeroDivisionError) as e:
        log.error(e)

    if len(results) == 0:
        log.error("Expression in --edit must return a bool-array")

    result = results[-1]
    if not is_boolarr(result):
        log.error("Expression in --edit must return a bool-array")

    assert isinstance(result, np.ndarray)
    return result


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
    speed_ranges: list[tuple[float, str, str]],
    silent_speed: float,
    loud_speed: float,
    bar: Bar,
    temp: str,
    log: Log,
) -> tuple[Chunks, VSpace, ASpace]:
    start = Fraction(0)
    all_clips: list[list[Clip]] = []
    all_chunks: list[Chunks] = []

    def seconds_to_ticks(val: int | str) -> int:
        if isinstance(val, str):
            return round(float(val) * tb)
        return val

    start_margin = seconds_to_ticks(margin[0])
    end_margin = seconds_to_ticks(margin[1])
    min_clip = seconds_to_ticks(_min_clip)
    min_cut = seconds_to_ticks(_min_cut)

    speed_map = [silent_speed, loud_speed]
    speed_hash = {
        0: silent_speed,
        1: loud_speed,
    }

    def get_speed_index(speed: float) -> int:
        if speed in speed_map:
            return speed_map.index(speed)
        speed_map.append(speed)
        speed_hash[len(speed_map) - 1] = speed
        return len(speed_map) - 1

    def parse_time(val: str, arr: NDArray) -> int:
        if val == "start":
            return 0
        if val == "end":
            return len(arr)
        try:
            num = seconds_to_ticks(time(val))
            return num if num >= 0 else num + len(arr)
        except TypeError as e:
            log.error(e)

    def mut_set_range(arr: NDArray, _ranges: list[list[str]], index: Any) -> None:
        for _range in _ranges:
            assert len(_range) == 2
            pair = [parse_time(val, arr) for val in _range]
            arr[pair[0] : pair[1]] = index

    for i in map(str, inputs):
        filesetup = FileSetup(sources[i], ensure, len(inputs) < 2, tb, bar, temp, log)
        has_loud = run_interpreter(method, filesetup, log)

        if len(mark_loud) > 0:
            mut_set_range(has_loud, mark_loud, loud_speed)

        if len(mark_silent) > 0:
            mut_set_range(has_loud, mark_silent, silent_speed)

        has_loud = cook(min_clip, min_cut, has_loud)
        mut_margin(has_loud, start_margin, end_margin)

        # Remove small clips/cuts created by applying other rules.
        has_loud = cook(min_clip, min_cut, has_loud)

        # Setup for handling custom speeds
        has_loud = has_loud.astype(np.uint)

        if len(cut_out) > 0:
            # always cut out even if 'silent_speed' is not 99,999
            mut_set_range(has_loud, cut_out, get_speed_index(99_999))

        if len(add_in) > 0:
            # set to 'video_speed' index
            mut_set_range(has_loud, add_in, 1)

        for speed_range in speed_ranges:
            speed = speed_range[0]
            _range = list(speed_range[1:])
            mut_set_range(has_loud, [_range], get_speed_index(speed))

        chunks = chunkify(has_loud, speed_hash)

        all_chunks.append(chunks)
        all_clips.append(clipify(chunks, i, start))
        start += round(chunks_len(chunks))

    vclips, aclips = make_av(all_clips, sources, inputs)

    return merge_chunks(all_chunks), vclips, aclips
