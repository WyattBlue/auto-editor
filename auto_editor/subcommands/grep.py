from __future__ import annotations

import os
import re
import sys
import tempfile
from dataclasses import dataclass, field

from auto_editor.ffwrapper import FFmpeg
from auto_editor.utils.log import Log
from auto_editor.vanparse import ArgumentParser


@dataclass
class GrepArgs:
    no_filename: bool = False
    max_count: int | None = None
    count: bool = False
    ignore_case: bool = False
    timecode: bool = False
    time: bool = False
    ffmpeg_location: str | None = None
    my_ffmpeg: bool = False
    help: bool = False
    input: list[str] = field(default_factory=list)


def grep_options(parser: ArgumentParser) -> ArgumentParser:
    parser.add_required("input", nargs="*", metavar="pattern [file ...]")
    parser.add_argument(
        "--no-filename", flag=True, help="Never print filenames with output lines"
    )
    parser.add_argument(
        "--max-count",
        "-m",
        type=int,
        help="Stop reading a file after NUM matching lines",
    )
    parser.add_argument(
        "--count",
        "-c",
        flag=True,
        help="Suppress normal output; instead print count of matching lines for each file",
    )
    parser.add_argument(
        "--ignore-case",
        "-i",
        flag=True,
        help="Ignore case distinctions for the PATTERN",
    )
    parser.add_argument("--timecode", flag=True, help="Print the match's timecode")
    parser.add_argument(
        "--time", flag=True, help="Print when the match happens. (Ignore ending)"
    )
    parser.add_argument("--ffmpeg-location", help="Point to your custom ffmpeg file")
    parser.add_argument(
        "--my-ffmpeg",
        flag=True,
        help="Use the ffmpeg on your PATH instead of the one packaged",
    )
    return parser


# stackoverflow.com/questions/9662346/python-code-to-remove-html-tags-from-a-string
def cleanhtml(raw_html: str) -> str:
    cleanr = re.compile("<.*?>")
    cleantext = re.sub(cleanr, "", raw_html)
    return cleantext


def grep_file(
    media_file: str,
    add_prefix: bool,
    ffmpeg: FFmpeg,
    args: type[GrepArgs],
    log: Log,
    TEMP: str,
) -> None:

    """
    We're using the WEBVTT subtitle format. It's better than srt
    because it doesn't emit line numbers and the time code is in
    (hh:mm:ss.sss) instead of (dd:hh:mm:ss,sss)
    """

    try:
        flags = re.IGNORECASE if args.ignore_case else 0
        pattern = re.compile(args.input[0], flags)
    except re.error as e:
        log.error(e)

    out_file = os.path.join(TEMP, "media.vtt")
    ffmpeg.run(["-i", media_file, out_file])

    count = 0

    prefix = ""
    if add_prefix:
        prefix = f"{os.path.splitext(os.path.basename(media_file))[0]}:"

    timecode = ""
    line_number = -1

    with open(out_file) as file:
        while True:
            line = file.readline()
            line_number += 1
            if line_number == 0:
                continue

            if not line or (args.max_count is not None and count >= args.max_count):
                break

            if line.strip() == "":
                continue

            if re.match(r"\d*:\d\d.\d*\s-->\s\d*:\d\d.\d*", line):
                if args.time:
                    timecode = line.split("-->")[0].strip() + " "
                else:
                    timecode = line.strip() + "; "
                continue

            line = cleanhtml(line)

            if re.search(pattern, line):
                count += 1
                if not args.count:
                    if args.timecode or args.time:
                        print(prefix + timecode + line.strip())
                    else:
                        print(prefix + line.strip())

    if args.count:
        print(prefix + str(count))


def main(sys_args=sys.argv[1:]) -> None:
    args = grep_options(ArgumentParser("grep")).parse_args(GrepArgs, sys_args)
    ffmpeg = FFmpeg(args.ffmpeg_location, args.my_ffmpeg, debug=False)

    TEMP = tempfile.mkdtemp()
    log = Log(temp=TEMP)

    media_files = args.input[1:]
    add_prefix = (
        len(media_files) > 1 or os.path.isdir(media_files[0])
    ) and not args.no_filename

    for path in media_files:
        if os.path.isdir(path):
            for filename in [f for f in os.listdir(path) if not f.startswith(".")]:
                grep_file(
                    os.path.join(path, filename),
                    add_prefix,
                    ffmpeg,
                    args,
                    log,
                    TEMP,
                )
        elif os.path.isfile(path):
            grep_file(path, add_prefix, ffmpeg, args, log, TEMP)
        else:
            log.error(f"{path}: File does not exist.")

    log.cleanup()


if __name__ == "__main__":
    main()
