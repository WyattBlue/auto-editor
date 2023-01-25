from __future__ import annotations

import sys
from dataclasses import dataclass, field
from typing import TYPE_CHECKING

import numpy as np

from auto_editor.analyze import (
    audio_levels,
    motion_levels,
    pixeldiff_levels,
    subtitle_levels,
)
from auto_editor.ffwrapper import FFmpeg, FileInfo
from auto_editor.objs.edit import (
    audio_builder,
    motion_builder,
    pixeldiff_builder,
    subtitle_builder,
)
from auto_editor.objs.util import ParserError, parse_dataclass
from auto_editor.output import Ensure
from auto_editor.utils.bar import Bar
from auto_editor.utils.func import setup_tempdir
from auto_editor.utils.log import Log
from auto_editor.utils.types import frame_rate, pos
from auto_editor.vanparse import ArgumentParser

if TYPE_CHECKING:
    from fractions import Fraction
    from typing import Any

    from numpy.typing import NDArray


@dataclass
class Audio:
    stream: int
    mincut: int
    minclip: int


@dataclass
class Motion:
    stream: int
    blur: int
    width: int


@dataclass
class Pixeldiff:
    stream: int


@dataclass
class Subtitle:
    pattern: str
    stream: int
    ignore_case: bool = False
    max_count: int | None = None


@dataclass
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


def print_floats(arr: NDArray[np.float_]) -> None:
    for a in arr:
        sys.stdout.write(f"{a:.20f}\n")


def print_ints(arr: NDArray[np.uint64] | NDArray[np.bool_]) -> None:
    for a in arr:
        sys.stdout.write(f"{a}\n")


def main(sys_args: list[str] = sys.argv[1:]) -> None:
    parser = levels_options(ArgumentParser("levels"))
    args = parser.parse_args(LevelArgs, sys_args)

    ffmpeg = FFmpeg(args.ffmpeg_location, args.my_ffmpeg)

    bar = Bar("none")
    temp = setup_tempdir(None, Log())
    log = Log(quiet=True, temp=temp)

    sources = {}
    for i, path in enumerate(args.input):
        sources[str(i)] = FileInfo(path, ffmpeg, log, str(i))

    assert "0" in sources
    src = sources["0"]

    tb = src.get_fps() if args.timebase is None else args.timebase
    ensure = Ensure(ffmpeg, src.get_samplerate(), temp, log)

    strict = True

    if ":" in args.edit:
        method, attrs = args.edit.split(":", 1)
    else:
        method, attrs = args.edit, ""

    def my_var_f(name: str, val: str, coerce: Any) -> Any:
        if src.videos:
            if name in ("x", "width"):
                return pos((val, src.videos[0].width))
            if name in ("y", "height"):
                return pos((val, src.videos[0].height))
        return coerce(val)

    for src in sources.values():
        if method == "audio":
            try:
                aobj = parse_dataclass(attrs, (Audio, audio_builder[1:]))
            except ParserError as e:
                log.error(e)

            print_floats(
                audio_levels(ensure, src, aobj.stream, tb, bar, strict, temp, log)
            )

        elif method == "motion":
            try:
                mobj = parse_dataclass(attrs, (Motion, motion_builder[1:]), my_var_f)
            except ParserError as e:
                log.error(e)

            print_floats(motion_levels(ensure, src, mobj, tb, bar, strict, temp, log))

        elif method == "pixeldiff":
            try:
                pobj = parse_dataclass(
                    attrs, (Pixeldiff, pixeldiff_builder[1:]), my_var_f
                )
            except ParserError as e:
                log.error(e)

            print_ints(pixeldiff_levels(ensure, src, pobj, tb, bar, strict, temp, log))
        elif method == "subtitle":
            try:
                sobj = parse_dataclass(attrs, (Subtitle, subtitle_builder))
            except ParserError as e:
                log.error(e)

            print_ints(subtitle_levels(ensure, src, sobj, tb, bar, strict, temp, log))
        else:
            log.error(f"Method: {method} not supported")

    log.cleanup()


if __name__ == "__main__":
    main()
