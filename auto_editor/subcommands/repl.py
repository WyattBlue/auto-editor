from __future__ import annotations

import sys
from dataclasses import dataclass, field
from fractions import Fraction

import auto_editor
from auto_editor.analyze import FileSetup, Levels
from auto_editor.ffwrapper import FFmpeg, initFileInfo
from auto_editor.lang.palet import ClosingError, Lexer, Parser, env, interpret
from auto_editor.lib.data_structs import print_str
from auto_editor.lib.err import MyError
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


@dataclass(slots=True)
class REPL_Args:
    input: list[str] = field(default_factory=list)
    debug_parser: bool = False
    timebase: Fraction | None = None
    ffmpeg_location: str | None = None
    my_ffmpeg: bool = False
    temp_dir: str | None = None
    help: bool = False


def repl_options(parser: ArgumentParser) -> ArgumentParser:
    parser.add_required("input", nargs="*")
    parser.add_argument(
        "--debug-parser",
        flag=True,
        help="Print parser value",
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
        sources = [initFileInfo(path, log) for path in args.input]
        src = sources[0]
        tb = src.get_fps() if args.timebase is None else args.timebase
        bar = Bar("none")
        ensure = Ensure(ffmpeg, bar, src.get_sr(), temp, log)
        env["timebase"] = tb
        env["@levels"] = Levels(ensure, src, tb, bar, temp, log)
        env["@filesetup"] = FileSetup(src, ensure, strict, tb, bar, temp, log)

    print(f"Auto-Editor {auto_editor.version} ({auto_editor.__version__})")
    text = None

    try:
        while True:
            try:
                if text is None:
                    text = input("> ")
                else:
                    text += "\n" + input("   ")
            except KeyboardInterrupt as e:
                if text is None:
                    raise e
                text = None
                print("")
                continue

            try:
                lexer = Lexer("repl", text)
                parser = Parser(lexer)
                if args.debug_parser:
                    print(f"parser: {parser}")

                for result in interpret(env, parser):
                    if result is not None:
                        sys.stdout.write(f"{print_str(result)}\n")
                        env["_"] = result

            except ClosingError:
                continue  # Allow user to continue adding text
            except (MyError, ZeroDivisionError) as e:
                print(f"error: {e}")

            text = None

    except (KeyboardInterrupt, EOFError):
        print("")


if __name__ == "__main__":
    main()
