from __future__ import annotations

import os
import sys
import tempfile
from dataclasses import dataclass, field

import numpy as np
from numpy.typing import NDArray

from auto_editor.analyze.audio import audio_detection
from auto_editor.analyze.motion import motion_detection
from auto_editor.analyze.pixeldiff import pixel_difference
from auto_editor.analyze.random import random_levels
from auto_editor.ffwrapper import FFmpeg, FileInfo
from auto_editor.method import (
    audio_builder,
    motion_builder,
    pixeldiff_builder,
    random_builder,
)
from auto_editor.objects import parse_dataclass
from auto_editor.utils.bar import Bar
from auto_editor.utils.log import Log
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
    parser.add_argument("--ffmpeg-location", help="Point to your custom ffmpeg file")
    parser.add_argument(
        "--my-ffmpeg",
        flag=True,
        help="Use the ffmpeg on your PATH instead of the one packaged",
    )
    return parser


def print_float_list(arr: NDArray[np.float_]) -> None:
    for a in arr:
        sys.stdout.write(f"{a:.20f}\n")


def print_int_list(arr: NDArray[np.uint64]) -> None:
    for a in arr:
        sys.stdout.write(f"{a}\n")


def main(sys_args=sys.argv[1:]) -> None:
    parser = levels_options(ArgumentParser("levels"))
    args = parser.parse_args(LevelArgs, sys_args)

    ffmpeg = FFmpeg(args.ffmpeg_location, args.my_ffmpeg, False)

    bar = Bar("none")
    temp = tempfile.mkdtemp()
    log = Log(temp=temp)

    inputs = [FileInfo(inp, ffmpeg, log) for inp in args.input]
    timebase = inputs[0].get_fps()

    strict = True

    METHOD_ATTRS_SEP = ":"
    METHODS = ("audio", "motion", "pixeldiff", "random")

    if METHOD_ATTRS_SEP in args.edit:
        method, attrs = args.edit.split(METHOD_ATTRS_SEP)
    else:
        method, attrs = args.edit, ""

    if method not in METHODS:
        log.error(f"Method: {method} not supported")

    for i, inp in enumerate(inputs):

        if method == "random":
            robj = parse_dataclass(attrs, Random, random_builder[1:], log)

            # TODO: Find better way to get media length
            if len(inp.audios) > 0:
                read_track = os.path.join(temp, f"{i}-0.wav")
                ffmpeg.run(["-i", inp.path, "-ac", "2", "-map", f"0:a:0", read_track])
            print_float_list(random_levels(inp.path, i, robj, timebase, temp, log))

        if method == "audio":
            aobj = parse_dataclass(attrs, Audio, audio_builder[1:], log)

            if aobj.stream >= len(inp.audios):
                log.error(f"Audio track '{aobj.stream}' does not exist.")

            read_track = os.path.join(temp, f"{i}-{aobj.stream}.wav")
            ffmpeg.run(
                ["-i", inp.path, "-ac", "2", "-map", f"0:a:{aobj.stream}", read_track]
            )

            if not os.path.isfile(read_track):
                log.error("Audio track file not found!")

            print_float_list(
                audio_detection(inp, i, aobj.stream, timebase, bar, strict, temp, log)
            )

        if method == "motion":
            mobj = parse_dataclass(attrs, Motion, motion_builder[1:], log)
            print_float_list(motion_detection(inp, i, mobj, timebase, bar, strict, temp, log))

        if method == "pixeldiff":
            pobj = parse_dataclass(attrs, Pixeldiff, pixeldiff_builder[1:], log)
            print_int_list(pixel_difference(inp, i, pobj, timebase, bar, strict, temp, log))

    log.cleanup()


if __name__ == "__main__":
    main()
