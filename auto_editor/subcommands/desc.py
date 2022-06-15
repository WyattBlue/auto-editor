import sys
from dataclasses import dataclass, field
from typing import List, Optional

from auto_editor.ffwrapper import FFmpeg, FileInfo
from auto_editor.utils.log import Log
from auto_editor.vanparse import ArgumentParser


@dataclass
class DescArgs:
    ffmpeg_location: Optional[str] = None
    help: bool = False
    input: List[str] = field(default_factory=list)


def desc_options(parser: ArgumentParser) -> ArgumentParser:
    parser.add_argument("--ffmpeg-location", help="Point to your custom ffmpeg file.")
    parser.add_required("input", nargs="*", help="Path to file(s)")
    return parser


def main(sys_args=sys.argv[1:]) -> None:
    args = desc_options(ArgumentParser("desc")).parse_args(DescArgs, sys_args)
    for input_file in args.input:
        inp = FileInfo(input_file, FFmpeg(args.ffmpeg_location, debug=False), Log())
        if inp.description is not None:
            sys.stdout.write(f"\n{inp.description}\n\n")
        else:
            sys.stdout.write("\nNo description.\n\n")


if __name__ == "__main__":
    main()
