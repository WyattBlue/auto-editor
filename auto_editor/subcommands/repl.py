from __future__ import annotations

import sys
from dataclasses import dataclass, field
from fractions import Fraction

import auto_editor
from auto_editor.analyze import FileSetup
from auto_editor.ffwrapper import FFmpeg, FileInfo
from auto_editor.interpreter import (
    ClosingError,
    Lexer,
    MyError,
    Parser,
    env,
    interpret,
    print_str,
)
from auto_editor.output import Ensure
from auto_editor.utils.bar import Bar
from auto_editor.utils.func import setup_tempdir
from auto_editor.utils.log import Log
from auto_editor.utils.types import frame_rate
from auto_editor.vanparse import ArgumentParser

try:
    import readline  # noqa
except ImportError:
    pass


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


def main(sys_args: list[str] = sys.argv[1:]) -> None:
    args = repl_options(ArgumentParser(None)).parse_args(REPL_Args, sys_args)

    if args.input:
        temp = setup_tempdir(args.temp_dir, Log())
        log = Log(quiet=True, temp=temp)
        ffmpeg = FFmpeg(args.ffmpeg_location, args.my_ffmpeg, False)
        strict = len(args.input) < 2
        sources = {}
        for i, path in enumerate(args.input):
            sources[str(i)] = FileInfo(path, ffmpeg, log, str(i))

        src = sources["0"]
        tb = src.get_fps() if args.timebase is None else args.timebase
        ensure = Ensure(ffmpeg, src.get_samplerate(), temp, log)
        filesetup = FileSetup(src, ensure, strict, tb, Bar("none"), temp, log)
        env["timebase"] = tb
        env["@filesetup"] = filesetup

    print(f"Auto-Editor {auto_editor.version} ({auto_editor.__version__})")
    text = None

    try:
        while True:
            try:
                if text is None:
                    text = input("> ")
                else:
                    text += " " + input("   ")
            except KeyboardInterrupt as e:
                if text is None:
                    raise e
                text = None
                print("")
                continue

            try:
                lexer = Lexer(text)
                parser = Parser(lexer)
            except MyError as e:
                text = None
                print(f"error: {e}")
                continue
            try:
                for result in interpret(env, parser):
                    if result is not None:
                        sys.stdout.write(f"{print_str(result)}\n")
            except ClosingError:
                continue  # Allow user to continue adding text
            except (MyError, ZeroDivisionError) as e:
                print(f"error: {e}")

            text = None

    except (KeyboardInterrupt, EOFError):
        print("")


if __name__ == "__main__":
    main()
