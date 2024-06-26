from __future__ import annotations

from fractions import Fraction
from math import ceil
from typing import TYPE_CHECKING, NamedTuple

import numpy as np

from auto_editor.analyze import FileSetup, Levels
from auto_editor.ffwrapper import FileInfo
from auto_editor.lang.palet import Lexer, Parser, env, interpret, is_boolarr
from auto_editor.lib.data_structs import print_str
from auto_editor.lib.err import MyError
from auto_editor.timeline import ASpace, TlAudio, TlVideo, VSpace, v1, v3
from auto_editor.utils.func import mut_margin
from auto_editor.utils.types import Args, CoerceError, time

if TYPE_CHECKING:
    from numpy.typing import NDArray

    from auto_editor.output import Ensure
    from auto_editor.utils.bar import Bar
    from auto_editor.utils.chunks import Chunks
    from auto_editor.utils.log import Log

    BoolList = NDArray[np.bool_]


class Clip(NamedTuple):
    start: int
    dur: int
    offset: int
    speed: float
    src: FileInfo


def clipify(chunks: Chunks, src: FileInfo, start: int = 0) -> list[Clip]:
    clips: list[Clip] = []
    i = 0
    for chunk in chunks:
        if chunk[2] > 0 and chunk[2] < 99999.0:
            dur = round((chunk[1] - chunk[0]) / chunk[2])
            if dur == 0:
                continue

            offset = int(chunk[0] / chunk[2])

            if not (clips and clips[-1].start == round(start)):
                clips.append(Clip(start, dur, offset, chunk[2], src))
            start += dur
            i += 1

    return clips


def make_av(src: FileInfo, all_clips: list[list[Clip]]) -> tuple[VSpace, ASpace]:
    assert type(src) is FileInfo
    vtl: VSpace = []
    atl: ASpace = [[] for _ in range(len(src.audios))]

    for clips in all_clips:
        for c in clips:
            if src.videos:
                if len(vtl) == 0:
                    vtl.append([])
                vtl[0].append(TlVideo(c.start, c.dur, c.src, c.offset, c.speed, 0))

        for c in clips:
            for a in range(len(src.audios)):
                atl[a].append(TlAudio(c.start, c.dur, c.src, c.offset, c.speed, 1, a))

    return vtl, atl


def run_interpreter_for_edit_option(
    text: str, filesetup: FileSetup
) -> NDArray[np.bool_]:
    ensure = filesetup.ensure
    src = filesetup.src
    tb = filesetup.tb
    bar = filesetup.bar
    temp = filesetup.temp
    log = filesetup.log

    try:
        parser = Parser(Lexer("`--edit`", text))
        if log.is_debug:
            log.debug(f"edit: {parser}")

        env["timebase"] = filesetup.tb
        env["@levels"] = Levels(ensure, src, tb, bar, temp, log)
        env["@filesetup"] = filesetup

        results = interpret(env, parser)

        if len(results) == 0:
            raise MyError("Expression in --edit must return a bool-array, got nothing")

        result = results[-1]
        if callable(result):
            result = result()

        if not is_boolarr(result):
            raise MyError(
                f"Expression in --edit must return a bool-array, got {print_str(result)}"
            )
    except MyError as e:
        log.error(e)

    assert isinstance(result, np.ndarray)
    return result


def make_sane_timebase(fps: Fraction) -> Fraction:
    tb = round(fps, 2)

    ntsc_60 = Fraction(60_000, 1001)
    ntsc = Fraction(30_000, 1001)
    film_ntsc = Fraction(24_000, 1001)

    if tb == round(ntsc_60, 2):
        return ntsc_60
    if tb == round(ntsc, 2):
        return ntsc
    if tb == round(film_ntsc, 2):
        return film_ntsc
    return tb


def parse_time(val: str, arr: NDArray, tb: Fraction) -> int:  # raises: `CoerceError`
    if val == "start":
        return 0
    if val == "end":
        return len(arr)

    num = time(val, tb)
    return num if num >= 0 else num + len(arr)


def make_timeline(
    sources: list[FileInfo],
    ensure: Ensure,
    args: Args,
    sr: int,
    bar: Bar,
    temp: str,
    log: Log,
) -> v3:
    inp = None if not sources else sources[0]

    if inp is None:
        tb, res = Fraction(30), (1920, 1080)
    else:
        tb = make_sane_timebase(
            inp.get_fps() if args.frame_rate is None else args.frame_rate
        )
        res = inp.get_res() if args.resolution is None else args.resolution

    try:
        start_margin = time(args.margin[0], tb)
        end_margin = time(args.margin[1], tb)
    except CoerceError as e:
        log.error(e)

    method = args.edit_based_on

    has_loud = np.array([], dtype=np.bool_)
    src_index = np.array([], dtype=np.int32)
    concat = np.concatenate

    for i, src in enumerate(sources):
        filesetup = FileSetup(src, ensure, len(sources) < 2, tb, bar, temp, log)

        edit_result = run_interpreter_for_edit_option(method, filesetup)
        mut_margin(edit_result, start_margin, end_margin)

        has_loud = concat((has_loud, edit_result))
        src_index = concat((src_index, np.full(len(edit_result), i, dtype=np.int32)))

    # Setup for handling custom speeds
    speed_index = has_loud.astype(np.uint)
    speed_map = [args.silent_speed, args.video_speed]
    speed_hash = {
        0: args.silent_speed,
        1: args.video_speed,
    }

    def get_speed_index(speed: float) -> int:
        if speed in speed_map:
            return speed_map.index(speed)
        speed_map.append(speed)
        speed_hash[len(speed_map) - 1] = speed
        return len(speed_map) - 1

    try:
        for _range in args.cut_out:
            # always cut out even if 'silent_speed' is not 99,999
            pair = [parse_time(val, speed_index, tb) for val in _range]
            speed_index[pair[0] : pair[1]] = get_speed_index(99_999)

        for _range in args.add_in:
            # set to 'video_speed' index
            pair = [parse_time(val, speed_index, tb) for val in _range]
            speed_index[pair[0] : pair[1]] = 1

        for speed_range in args.set_speed_for_range:
            start_in = parse_time(speed_range[1], speed_index, tb)
            end_in = parse_time(speed_range[2], speed_index, tb)
            speed_index[start_in:end_in] = get_speed_index(speed_range[0])
    except CoerceError as e:
        log.error(e)

    def echunk(
        arr: NDArray, src_index: NDArray[np.int32]
    ) -> list[tuple[FileInfo, int, int, float]]:
        arr_length = len(has_loud)

        chunks = []
        start = 0
        doi = 0
        for j in range(1, arr_length):
            if (arr[j] != arr[j - 1]) or (src_index[j] != src_index[j - 1]):
                src = sources[src_index[j - 1]]
                chunks.append((src, start, j - doi, speed_map[arr[j - 1]]))
                start = j - doi

                if src_index[j] != src_index[j - 1]:
                    start = 0
                    doi = j

        src = sources[src_index[j]]
        chunks.append((src, start, arr_length, speed_map[arr[j]]))
        return chunks

    # Assert timeline is monotonic because non-monotonic timelines are incorrect
    # here and causes back-seeking (performance issue) in video rendering.

    # We don't properly check monotonicity for multiple sources, so skip those.

    check_monotonic = len(sources) == 1
    last_i = 0

    clips: list[Clip] = []
    start = 0

    for chunk in echunk(speed_index, src_index):
        if chunk[3] != 99999:
            dur = int((chunk[2] - chunk[1]) / chunk[3])
            if dur == 0:
                continue

            offset = ceil(chunk[1] / chunk[3])

            if check_monotonic:
                max_end = start + dur - 1
                this_i = round((offset + max_end - start) * chunk[3])
                if this_i < last_i:
                    raise ValueError("not monotonic", sources, this_i, last_i)
                last_i = this_i

            clips.append(Clip(start, dur, offset, chunk[3], chunk[0]))

            start += dur

    vtl: VSpace = []
    atl: ASpace = []
    for c in clips:
        if c.src.videos:
            if len(vtl) == 0:
                vtl.append([])
            vtl[0].append(TlVideo(c.start, c.dur, c.src, c.offset, c.speed, 0))

    for c in clips:
        for a in range(len(c.src.audios)):
            if a >= len(atl):
                atl.append([])
            atl[a].append(TlAudio(c.start, c.dur, c.src, c.offset, c.speed, 1, a))

    # Turn long silent/loud array to formatted chunk list.
    # Example: [1, 1, 1, 2, 2], {1: 1.0, 2: 1.5} => [(0, 3, 1.0), (3, 5, 1.5)]
    def chunkify(arr: NDArray, smap: dict[int, float]) -> Chunks:
        arr_length = len(arr)

        chunks = []
        start = 0
        for j in range(1, arr_length):
            if arr[j] != arr[j - 1]:
                chunks.append((start, j, smap[arr[j - 1]]))
                start = j
        chunks.append((start, arr_length, smap[arr[j]]))
        return chunks

    if len(sources) == 1 and inp is not None:
        chunks = chunkify(speed_index, speed_hash)
        v1_compatiable = v1(inp, chunks)
    else:
        v1_compatiable = None

    tl = v3(inp, tb, sr, res, args.background, vtl, atl, v1_compatiable)

    # Additional monotonic check, o(n^2) time complexity so disable by default.

    # if len(sources) != 1:
    #     return tl

    # last_i = 0
    # for index in range(tl.end):
    #     for layer in tl.v:
    #         for lobj in layer:
    #             if index >= lobj.start and index < (lobj.start + lobj.dur):
    #                 _i = round((lobj.offset + index - lobj.start) * lobj.speed)
    #                 if (_i < last_i):
    #                     print(_i, last_i)
    #                     raise ValueError("not monotonic")
    #                 last_i = _i

    return tl
