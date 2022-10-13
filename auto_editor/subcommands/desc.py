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


def main(sys_args: list[str]) -> None:
    args = desc_options(ArgumentParser("desc")).parse_args(DescArgs, sys_args)
    for path in args.input:
        src = FileInfo(path, FFmpeg(args.ffmpeg_location, debug=False), Log())
        if src.description is not None:
            sys.stdout.write(f"\n{src.description}\n\n")
        else:
            sys.stdout.write("\nNo description.\n\n")


if __name__ == "__main__":
    main(sys.argv[1:])
