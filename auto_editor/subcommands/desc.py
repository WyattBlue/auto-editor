from __future__ import annotations

import sys
from dataclasses import dataclass, field

from auto_editor.ffwrapper import FFmpeg, FileInfo
from auto_editor.utils.log import Log
from auto_editor.vanparse import ArgumentParser


@dataclass
class DescArgs:
    ffmpeg_location: str | None = None
    help: bool = False
    input: list[str] = field(default_factory=list)


def desc_options(parser: ArgumentParser) -> ArgumentParser:
    parser.add_required("input", nargs="*")
    parser.add_argument("--ffmpeg-location", help="Point to your custom ffmpeg file")
    return parser


def main(sys_args=sys.argv[1:]) -> None:
    args = desc_options(ArgumentParser("desc")).parse_args(DescArgs, sys_args)
    for i, istr in enumerate(args.input):
        inp = FileInfo(i, istr, FFmpeg(args.ffmpeg_location, debug=False), Log())
        if inp.description is not None:
            sys.stdout.write(f"\n{inp.description}\n\n")
        else:
            sys.stdout.write("\nNo description.\n\n")


if __name__ == "__main__":
    main()
