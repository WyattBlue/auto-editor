from __future__ import annotations

import sys
from dataclasses import dataclass, field
from typing import TYPE_CHECKING

import numpy as np

from auto_editor.analyze import LevelError, Levels, builder_map
from auto_editor.ffwrapper import FFmpeg, initFileInfo
from auto_editor.lang.palet import env
from auto_editor.output import Ensure
from auto_editor.utils.bar import Bar
from auto_editor.utils.cmdkw import ParserError, parse_with_palet
from auto_editor.utils.func import setup_tempdir
from auto_editor.utils.log import Log
from auto_editor.utils.types import frame_rate
from auto_editor.vanparse import ArgumentParser

if TYPE_CHECKING:
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
    if arr.dtype == np.float64:
        for a in arr:
            sys.stdout.write(f"{a:.20f}\n")
    elif arr.dtype == np.bool_:
        for a in arr:
            sys.stdout.write(f"{1 if a else 0}\n")
    else:
        for a in arr:
            sys.stdout.write(f"{a}\n")


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

    for src in sources:
        print("")
        print("@start")

        levels = Levels(ensure, src, tb, bar, temp, log)

        if method in builder_map:
            builder = builder_map[method]

            try:
                obj = parse_with_palet(attrs, builder, env)
            except ParserError as e:
                log.error(e)

            if "threshold" in obj:
                del obj["threshold"]

        try:
            if method == "audio":
                print_arr(levels.audio(obj["stream"]))
            elif method == "motion":
                print_arr(levels.motion(obj["stream"], obj["blur"], obj["width"]))
            elif method == "subtitle":
                print_arr(
                    levels.subtitle(
                        obj["pattern"],
                        obj["stream"],
                        obj["ignore_case"],
                        obj["max_count"],
                    )
                )
            elif method == "none":
                print_arr(levels.none())
            elif method == "all/e":
                print_arr(levels.all())
            else:
                log.error(f"Method: {method} not supported")
        except LevelError as e:
            log.error(e)

    sys.stdout.flush()
    print("")
    log.cleanup()


if __name__ == "__main__":
    main()
