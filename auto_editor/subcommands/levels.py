from __future__ import annotations

import sys
import tempfile
from dataclasses import dataclass, field
from fractions import Fraction

import numpy as np
from numpy.typing import NDArray

from auto_editor.analyze import (
    audio_levels,
    motion_levels,
    pixeldiff_levels,
    random_levels,
)
from auto_editor.ffwrapper import FFmpeg, FileInfo
from auto_editor.method import (
    audio_builder,
    motion_builder,
    pixeldiff_builder,
    random_builder,
)
from auto_editor.objects import parse_dataclass
from auto_editor.output import Ensure
from auto_editor.utils.bar import Bar
from auto_editor.utils.log import Log
from auto_editor.utils.types import frame_rate
from auto_editor.vanparse import ArgumentParser


@dataclass
class Audio:
    stream: int


@dataclass
class Motion:
    stream: int
    blur: int
    width: int


@dataclass
class Pixeldiff:
    stream: int


@dataclass
class Random:
    seed: int


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


def print_ints(arr: NDArray[np.uint64]) -> None:
    for a in arr:
        sys.stdout.write(f"{a}\n")


def main(sys_args=sys.argv[1:]) -> None:
    parser = levels_options(ArgumentParser("levels"))
    args = parser.parse_args(LevelArgs, sys_args)

    ffmpeg = FFmpeg(args.ffmpeg_location, args.my_ffmpeg, False)

    bar = Bar("none")
    temp = tempfile.mkdtemp()
    log = Log(temp=temp)

    inputs = [FileInfo(i, istr, ffmpeg, log) for i, istr in enumerate(args.input)]

    tb = inputs[0].get_fps() if args.timebase is None else args.timebase
    ensure = Ensure(ffmpeg, inputs[0].get_samplerate(), temp, log)

    strict = True

    METHOD_ATTRS_SEP = ":"
    METHODS = ("audio", "motion", "pixeldiff", "random")

    if METHOD_ATTRS_SEP in args.edit:
        method, attrs = args.edit.split(METHOD_ATTRS_SEP)
    else:
        method, attrs = args.edit, ""

    if method not in METHODS:
        log.error(f"Method: {method} not supported")

    for inp in inputs:
        if method == "random":
            robj = parse_dataclass(attrs, Random, random_builder[1:], log)
            print_floats(random_levels(ensure, inp, robj, tb, temp, log))

        if method == "audio":
            aobj = parse_dataclass(attrs, Audio, audio_builder[1:], log)
            print_floats(
                audio_levels(ensure, inp, aobj.stream, tb, bar, strict, temp, log)
            )

        if method == "motion":
            if inp.videos:
                _vars = {"width": inp.videos[0].width}
            else:
                _vars = {"width": 1}
            mobj = parse_dataclass(attrs, Motion, motion_builder[1:], log, _vars)
            print_floats(motion_levels(ensure, inp, mobj, tb, bar, strict, temp, log))

        if method == "pixeldiff":
            pobj = parse_dataclass(attrs, Pixeldiff, pixeldiff_builder[1:], log)
            print_ints(pixeldiff_levels(ensure, inp, pobj, tb, bar, strict, temp, log))

    log.cleanup()


if __name__ == "__main__":
    main()
