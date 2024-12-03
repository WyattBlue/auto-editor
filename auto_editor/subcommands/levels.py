from __future__ import annotations

import sys
from dataclasses import dataclass, field
from fractions import Fraction
from typing import TYPE_CHECKING

import av
import numpy as np

from auto_editor.analyze import *
from auto_editor.ffwrapper import initFileInfo
from auto_editor.lang.palet import env
from auto_editor.lib.contracts import is_bool, is_nat, is_nat1, is_str, is_void, orc
from auto_editor.utils.bar import initBar
from auto_editor.utils.cmdkw import (
    ParserError,
    Required,
    parse_with_palet,
    pAttr,
    pAttrs,
)
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


def print_arr_gen(arr: Iterator[float | np.float32]) -> None:
    print("")
    print("@start")
    for a in arr:
        print(f"{a:.20f}")
    print("")


def main(sys_args: list[str] = sys.argv[1:]) -> None:
    parser = levels_options(ArgumentParser("levels"))
    args = parser.parse_args(LevelArgs, sys_args)

    bar = initBar("none")
    log = Log(quiet=True)

    sources = [initFileInfo(path, log) for path in args.input]
    if len(sources) < 1:
        log.error("levels needs at least one input file")

    src = sources[0]

    tb = src.get_fps() if args.timebase is None else args.timebase

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

        levels = Levels(src, tb, bar, False, log, strict=True)
        try:
            if method == "audio":
                container = av.open(src.path, "r")
                audio_stream = container.streams.audio[obj["stream"]]
                log.experimental(audio_stream.codec)
                print_arr_gen(iter_audio(audio_stream, tb))
                container.close()

            elif method == "motion":
                container = av.open(src.path, "r")
                video_stream = container.streams.video[obj["stream"]]
                log.experimental(video_stream.codec)
                print_arr_gen(iter_motion(video_stream, tb, obj["blur"], obj["width"]))
                container.close()

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
