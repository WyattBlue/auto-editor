# type: ignore

from __future__ import annotations

import readline  # noqa
import sys
from dataclasses import dataclass, field
from fractions import Fraction

import numpy as np

import auto_editor
from auto_editor.ffwrapper import FFmpeg, FileInfo
from auto_editor.interpreter import Interpreter, Lexer, MyError, Parser, print_arr
from auto_editor.output import Ensure
from auto_editor.utils.bar import Bar
from auto_editor.utils.func import setup_tempdir
from auto_editor.utils.log import Log
from auto_editor.utils.types import frame_rate
from auto_editor.vanparse import ArgumentParser


@dataclass
class REPL_Args:
    input: list[str] = field(default_factory=list)
    timebase: Fraction | None = None
    ffmpeg_location: str | None = None
    my_ffmpeg: bool = False
    temp_dir: str | None = None
    help: bool = False


def repl_options(parser: ArgumentParser) -> ArgumentParser:
    parser.add_required("input", nargs="*")
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
    parser.add_argument(
        "--temp-dir",
        metavar="PATH",
        help="Set where the temporary directory is located",
    )
    return parser


def display_val(val: Any) -> str:
    if val is None:
        return ""
    if val is True:
        return "#t\n"
    if val is False:
        return "#f\n"
    if isinstance(val, complex):
        join = "" if val.imag < 0 else "+"
        return f"{val.real}{join}{val.imag}i\n"
    if isinstance(val, np.ndarray):
        return print_arr(val)
    if isinstance(val, str):
        return f'"{val}"\n'
    if isinstance(val, Fraction):
        return f"{val.numerator}/{val.denominator}\n"

    return f"{val!r}\n"


def main(sys_args: list[str]) -> None:
    parser = repl_options(ArgumentParser("levels"))
    args = parser.parse_args(REPL_Args, sys_args)

    ffmpeg = FFmpeg(args.ffmpeg_location, args.my_ffmpeg, False)
    temp = setup_tempdir(args.temp_dir, Log())
    log = Log(quiet=True, temp=temp)
    strict = len(args.input) < 2

    sources = {}
    for i, path in enumerate(args.input):
        sources[str(i)] = FileInfo(path, ffmpeg, log, str(i))

    src = sources["0"]
    tb = src.get_fps() if args.timebase is None else args.timebase
    ensure = Ensure(ffmpeg, src.get_samplerate(), temp, log)
    bar = Bar("none")

    print(f"Auto-Editor {auto_editor.version} ({auto_editor.__version__})")

    try:
        while True:
            text = input("> ")

            try:
                lexer = Lexer(text)
                parser = Parser(lexer)
            except MyError as e:
                print(f"error: {e}")
                continue

            try:
                interpreter = Interpreter(
                    parser, src, ensure, strict, tb, bar, temp, log
                )
                result = interpreter.interpret()
                if isinstance(result, list):
                    for item in result:
                        sys.stdout.write(display_val(item))
                else:
                    sys.stdout.write(display_val(result))
            except MyError as e:
                print(f"error: {e}")

    except (KeyboardInterrupt, EOFError):
        print("")


if __name__ == "__main__":
    main(sys.argv[1:])
