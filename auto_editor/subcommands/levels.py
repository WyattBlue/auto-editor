from __future__ import annotations

import math
import sys
from dataclasses import dataclass, field
from fractions import Fraction
from typing import TYPE_CHECKING

import av
import numpy as np
from av.audio.fifo import AudioFifo

from auto_editor.analyze import LevelError, Levels
from auto_editor.ffwrapper import FFmpeg, initFileInfo
from auto_editor.lang.palet import env
from auto_editor.lib.contracts import is_bool, is_nat, is_nat1, is_str, is_void, orc
from auto_editor.output import Ensure
from auto_editor.utils.bar import Bar
from auto_editor.utils.cmdkw import (
    ParserError,
    Required,
    parse_with_palet,
    pAttr,
    pAttrs,
)
from auto_editor.utils.func import setup_tempdir
from auto_editor.utils.log import Log
from auto_editor.utils.types import frame_rate
from auto_editor.vanparse import ArgumentParser

if TYPE_CHECKING:
    from collections.abc import Iterator
    from fractions import Fraction

    from numpy.typing import NDArray


@dataclass(slots=True)
class LevelArgs:
    input: list[str] = field(default_factory=list)
    edit: str = "audio"
    timebase: Fraction | None = None
    ffmpeg_location: str | None = None
    my_ffmpeg: bool = False
    help: bool = False


def levels_options(parser: ArgumentParser) -> ArgumentParser:
    parser.add_required("input", nargs="*")
    parser.add_argument(
        "--edit",
        metavar="METHOD:[ATTRS?]",
        help="Select the kind of detection to analyze with attributes",
    )
    parser.add_argument(
        "--timebase",
        "-tb",
        metavar="NUM",
        type=frame_rate,
        help="Set custom timebase",
    )
    parser.add_argument("--ffmpeg-location", help="Point to your custom ffmpeg file")
    parser.add_argument(
        "--my-ffmpeg",
        flag=True,
        help="Use the ffmpeg on your PATH instead of the one packaged",
    )
    return parser


def print_arr(arr: NDArray) -> None:
    print("")
    print("@start")
    if arr.dtype == np.float64:
        for a in arr:
            sys.stdout.write(f"{a:.20f}\n")
    elif arr.dtype == np.bool_:
        for a in arr:
            sys.stdout.write(f"{1 if a else 0}\n")
    else:
        for a in arr:
            sys.stdout.write(f"{a}\n")
    sys.stdout.flush()
    print("")


def print_arr_gen(arr: Iterator[int | float]) -> None:
    print("")
    print("@start")
    for a in arr:
        if isinstance(a, float):
            print(f"{a:.20f}")
        else:
            print(a)
    print("")


def iter_audio(src, tb: Fraction, stream: int = 0) -> Iterator[float]:
    fifo = AudioFifo()
    try:
        container = av.open(src.path, "r")
        audio_stream = container.streams.audio[stream]
        sample_rate = audio_stream.rate

        exact_size = (1 / tb) * sample_rate
        accumulated_error = 0

        # Resample so that audio data is between [-1, 1]
        resampler = av.AudioResampler(
            av.AudioFormat("flt"), audio_stream.layout, sample_rate
        )

        for frame in container.decode(audio=stream):
            frame.pts = None  # Skip time checks

            for reframe in resampler.resample(frame):
                fifo.write(reframe)

            while fifo.samples >= math.ceil(exact_size):
                size_with_error = exact_size + accumulated_error
                current_size = round(size_with_error)
                accumulated_error = size_with_error - current_size

                audio_chunk = fifo.read(current_size)
                assert audio_chunk is not None
                arr = audio_chunk.to_ndarray().flatten()
                yield float(np.max(np.abs(arr)))

    finally:
        container.close()


def iter_motion(src, tb, stream: int, blur: int, width: int) -> Iterator[float]:
    container = av.open(src.path, "r")

    video = container.streams.video[stream]
    video.thread_type = "AUTO"

    prev_frame = None
    current_frame = None
    total_pixels = src.videos[0].width * src.videos[0].height
    index = 0
    prev_index = 0

    graph = av.filter.Graph()
    graph.link_nodes(
        graph.add_buffer(template=video),
        graph.add("scale", f"{width}:-1"),
        graph.add("format", "gray"),
        graph.add("gblur", f"sigma={blur}"),
        graph.add("buffersink"),
    ).configure()

    for unframe in container.decode(video):
        if unframe.pts is None:
            continue

        graph.push(unframe)
        frame = graph.pull()
        assert frame.time is not None
        index = round(frame.time * tb)

        current_frame = frame.to_ndarray()
        if prev_frame is None:
            value = 0.0
        else:
            # Use `int16` to avoid underflow with `uint8` datatype
            diff = np.abs(prev_frame.astype(np.int16) - current_frame.astype(np.int16))
            value = np.count_nonzero(diff) / total_pixels

        for _ in range(index - prev_index):
            yield value

        prev_frame = current_frame
        prev_index = index

    container.close()


def main(sys_args: list[str] = sys.argv[1:]) -> None:
    parser = levels_options(ArgumentParser("levels"))
    args = parser.parse_args(LevelArgs, sys_args)

    ffmpeg = FFmpeg(args.ffmpeg_location, args.my_ffmpeg)

    bar = Bar("none")
    temp = setup_tempdir(None, Log())
    log = Log(quiet=True, temp=temp)

    sources = [initFileInfo(path, log) for path in args.input]
    if len(sources) < 1:
        log.error("levels needs at least one input file")

    src = sources[0]

    tb = src.get_fps() if args.timebase is None else args.timebase
    ensure = Ensure(ffmpeg, bar, src.get_sr(), temp, log)

    if ":" in args.edit:
        method, attrs = args.edit.split(":", 1)
    else:
        method, attrs = args.edit, ""

    audio_builder = pAttrs("audio", pAttr("stream", 0, is_nat))
    motion_builder = pAttrs(
        "motion",
        pAttr("stream", 0, is_nat),
        pAttr("blur", 9, is_nat),
        pAttr("width", 400, is_nat1),
    )
    subtitle_builder = pAttrs(
        "subtitle",
        pAttr("pattern", Required, is_str),
        pAttr("stream", 0, is_nat),
        pAttr("ignore-case", False, is_bool),
        pAttr("max-count", None, orc(is_nat, is_void)),
    )

    builder_map = {
        "audio": audio_builder,
        "motion": motion_builder,
        "subtitle": subtitle_builder,
    }

    for src in sources:
        if method in builder_map:
            try:
                obj = parse_with_palet(attrs, builder_map[method], env)
            except ParserError as e:
                log.error(e)

        levels = Levels(ensure, src, tb, bar, temp, log)
        try:
            if method == "audio":
                # print_arr(levels.audio(**obj))
                print_arr_gen(iter_audio(src, tb, **obj))
            elif method == "motion":
                print_arr_gen(iter_motion(src, tb, **obj))
            elif method == "subtitle":
                print_arr(levels.subtitle(**obj))
            elif method == "none":
                print_arr(levels.none())
            elif method == "all/e":
                print_arr(levels.all())
            else:
                log.error(f"Method: {method} not supported")
        except LevelError as e:
            log.error(e)

    log.cleanup()


if __name__ == "__main__":
    main()
