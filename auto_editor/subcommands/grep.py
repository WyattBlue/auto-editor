import sys
import os
import re
import tempfile

from auto_editor.utils.log import Log
from auto_editor.ffwrapper import FFmpeg
from auto_editor.vanparse import ArgumentParser


def grep_options(parser):
    parser.add_argument(
        "--no-filename", flag=True, help="Never print filenames with output lines."
    )
    parser.add_argument(
        "--max-count",
        "-m",
        type=int,
        help="Stop reading a file after NUM matching lines.",
    )
    parser.add_argument(
        "--count",
        "-c",
        flag=True,
        help="Suppress normal output; instead print count of matching lines for each file.",
    )
    parser.add_argument(
        "--ignore-case",
        "-i",
        flag=True,
        help="Ignore case distinctions for the PATTERN.",
    )
    parser.add_argument("--timecode", flag=True, help="Print the match's timecode.")
    parser.add_argument(
        "--time", flag=True, help="Print when the match happens. (Ignore ending)."
    )
    parser.add_argument("--ffmpeg-location", help="Point to your custom ffmpeg file.")
    parser.add_argument(
        "--my-ffmpeg",
        flag=True,
        help="Use the ffmpeg on your PATH instead of the one packaged.",
    )
    parser.add_required(
        "input", nargs="*", help="The path to a file you want inspected."
    )
    return parser


# stackoverflow.com/questions/9662346/python-code-to-remove-html-tags-from-a-string
def cleanhtml(raw_html: str) -> str:
    cleanr = re.compile("<.*?>")
    cleantext = re.sub(cleanr, "", raw_html)
    return cleantext


def grep_file(
    media_file: str, add_prefix: bool, ffmpeg: FFmpeg, args, log: Log, TEMP: str
) -> None:

    """
    We're using the WEBVTT subtitle format. It's better than srt
    because it doesn't emit line numbers and the time code is in
    (hh:mm:ss.sss) instead of (dd:hh:mm:ss,sss)
    """

    out_file = os.path.join(TEMP, "media.vtt")
    ffmpeg.run(["-i", media_file, out_file])

    count = 0

    flags = 0
    if args.ignore_case:
        flags = re.IGNORECASE

    prefix = ""
    if add_prefix:
        prefix = f"{os.path.splitext(os.path.basename(media_file))[0]}:"

    if args.max_count is None:
        args.max_count = float("inf")

    timecode = ""
    line_number = -1
    with open(out_file, "r") as file:
        while True:
            line = file.readline()
            line_number += 1
            if line_number == 0:
                continue

            if not line or count >= args.max_count:
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
            match = re.search(args.input[0], line, flags)
            line = line.strip()

            if match:
                count += 1
                if not args.count:
                    if args.timecode or args.time:
                        print(prefix + timecode + line)
                    else:
                        print(prefix + line)

    if args.count:
        print(prefix + str(count))


def main(sys_args=sys.argv[1:]):
    parser = grep_options(ArgumentParser("grep"))
    args = parser.parse_args(sys_args)

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
