from __future__ import annotations

import os
import sys
import tempfile
from dataclasses import dataclass, field

from auto_editor.ffwrapper import FFmpeg, FileInfo
from auto_editor.utils.log import Log
from auto_editor.vanparse import ArgumentParser


@dataclass
class SubArgs:
    ffmpeg_location: str | None = None
    my_ffmpeg: bool = False
    help: bool = False
    input: list[str] = field(default_factory=list)


def subdump_options(parser: ArgumentParser) -> ArgumentParser:
    parser.add_required("input", nargs="*")
    parser.add_argument("--ffmpeg-location", help="Point to your custom ffmpeg file")
    parser.add_argument(
        "--my-ffmpeg",
        flag=True,
        help="Use the ffmpeg on your PATH instead of the one packaged",
    )
    return parser


def main(sys_args=sys.argv[1:]) -> None:
    args = subdump_options(ArgumentParser("subdump")).parse_args(SubArgs, sys_args)

    ffmpeg = FFmpeg(args.ffmpeg_location, args.my_ffmpeg, debug=False)

    temp = tempfile.mkdtemp()
    log = Log(temp=temp)

    for i, input_file in enumerate(args.input):
        inp = FileInfo(i, input_file, ffmpeg, log)

        cmd = ["-i", input_file]
        for s, sub in enumerate(inp.subtitles):
            cmd.extend(["-map", f"0:s:{s}", os.path.join(temp, f"{i}s{s}.{sub.ext}")])
        ffmpeg.run(cmd)

        for s, sub in enumerate(inp.subtitles):
            print(f"file: {input_file} ({s}:{sub.lang}:{sub.ext})")
            with open(os.path.join(temp, f"{i}s{s}.{sub.ext}")) as file:
                print(file.read())
            print("------")

    log.cleanup()


if __name__ == "__main__":
    main()
