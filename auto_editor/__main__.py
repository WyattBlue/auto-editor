#!/usr/bin/env python3

import re
import sys
from os import environ
from os.path import exists, isdir, isfile, lexists, splitext
from subprocess import run

import auto_editor
from auto_editor.edit import edit_media
from auto_editor.ffwrapper import FFmpeg
from auto_editor.utils.func import get_stdout
from auto_editor.utils.log import Log
from auto_editor.utils.types import (
    Args,
    frame_rate,
    margin,
    number,
    parse_color,
    resolution,
    sample_rate,
    speed,
    speed_range,
    time_range,
)
from auto_editor.vanparse import ArgumentParser


def main_options(parser: ArgumentParser) -> ArgumentParser:
    parser.add_required("input", nargs="*", metavar="[file | url ...] [options]")
    parser.add_text("Editing Options:")
    parser.add_argument(
        "--margin",
        "-m",
        type=margin,
        metavar="LENGTH",
        help='Set sections near "loud" as "loud" too if section is less than LENGTH away.',
    )
    parser.add_argument(
        "--edit-based-on",
        "--edit",
        metavar="METHOD",
        help="Decide which method to use when making edits",
    )
    parser.add_argument(
        "--silent-speed",
        "-s",
        type=speed,
        metavar="NUM",
        help='Set speed of sections marked "silent" to NUM',
    )
    parser.add_argument(
        "--video-speed",
        "--sounded-speed",
        "-v",
        type=speed,
        metavar="NUM",
        help='Set speed of sections marked "loud" to NUM',
    )
    parser.add_argument(
        "--cut-out",
        type=time_range,
        nargs="*",
        metavar="[START,STOP ...]",
        help="The range of media that will be removed completely, regardless of the "
        "value of silent speed",
    )
    parser.add_argument(
        "--add-in",
        type=time_range,
        nargs="*",
        metavar="[START,STOP ...]",
        help="The range of media that will be added in, opposite of --cut-out",
    )
    parser.add_argument(
        "--set-speed-for-range",
        "--set-speed",
        type=speed_range,
        nargs="*",
        metavar="[SPEED,START,STOP ...]",
        help="Set an arbitrary speed for a given range",
    )
    parser.add_text("Timeline Options:")
    parser.add_argument(
        "--frame-rate",
        "-fps",
        "-r",
        "--time-base",
        "-tb",
        type=frame_rate,
        metavar="NUM",
        help="Set timeline frame rate",
    )
    parser.add_argument(
        "--sample-rate",
        "-ar",
        type=sample_rate,
        metavar="NAT",
        help="Set timeline sample rate",
    )
    parser.add_argument(
        "--resolution",
        "-res",
        type=resolution,
        metavar="WIDTH,HEIGHT",
        help="Set timeline width and height",
    )
    parser.add_argument(
        "--background",
        "-b",
        type=parse_color,
        metavar="COLOR",
        help="Set the background as a solid RGB color",
    )
    parser.add_argument(
        "--add",
        nargs="*",
        metavar="OBJ:START,DUR,ATTRS?",
        help="Insert an audio/video object to the timeline",
    )
    parser.add_text("URL Download Options:")
    parser.add_argument(
        "--yt-dlp-location",
        metavar="PATH",
        help="Set a custom path to yt-dlp",
    )
    parser.add_argument(
        "--download-format",
        metavar="FORMAT",
        help="Set the yt-dlp download format (--format, -f)",
    )
    parser.add_argument(
        "--output-format",
        metavar="TEMPLATE",
        help="Set the yt-dlp output file template (--output, -o)",
    )
    parser.add_argument(
        "--yt-dlp-extras",
        metavar="CMD",
        help="Add extra options for yt-dlp. Must be in quotes",
    )
    parser.add_text("Utility Options:")
    parser.add_argument(
        "--export", "-ex", metavar="EXPORT:ATTRS?", help="Choose the export mode"
    )
    parser.add_argument(
        "--output-file",
        "--output",
        "-o",
        metavar="FILE",
        help="Set the name/path of the new output file.",
    )
    parser.add_argument(
        "--player", "-p", metavar="CMD", help="Set player to open output media files"
    )
    parser.add_argument(
        "--no-open", flag=True, help="Do not open the output file after editing is done"
    )
    parser.add_argument(
        "--temp-dir",
        metavar="PATH",
        help="Set where the temporary directory is located",
    )
    parser.add_argument(
        "--ffmpeg-location",
        metavar="PATH",
        help="Set a custom path to the ffmpeg location",
    )
    parser.add_text("Display Options:")
    parser.add_argument(
        "--progress",
        metavar="PROGRESS",
        choices=("modern", "classic", "ascii", "machine", "none"),
        help="Set what type of progress bar to use",
    )
    parser.add_argument("--debug", flag=True, help="Show debugging messages and values")
    parser.add_argument("--quiet", "-q", flag=True, help="Display less output")
    parser.add_argument(
        "--preview",
        "--stats",
        flag=True,
        help="Show stats on how the input will be cut and halt",
    )
    parser.add_text("Video Rendering:")
    parser.add_argument(
        "--video-codec",
        "-vcodec",
        "-c:v",
        metavar="ENCODER",
        help="Set video codec for output media",
    )
    parser.add_argument(
        "--video-bitrate",
        "-b:v",
        metavar="BITRATE",
        help="Set the number of bits per second for video",
    )
    parser.add_argument(
        "--scale",
        type=number,
        metavar="NUM",
        help="Scale the output video's resolution by NUM factor",
    )
    parser.add_argument(
        "--no-seek",
        flag=True,
        help="Disable file seeking when rendering video. Helpful for debugging desync issues",
    )
    parser.add_text("Audio Rendering:")
    parser.add_argument(
        "--audio-codec",
        "-acodec",
        "-c:a",
        metavar="ENCODER",
        help="Set audio codec for output media",
    )
    parser.add_argument(
        "--audio-bitrate",
        "-b:a",
        metavar="BITRATE",
        help="Set the number of bits per second for audio",
    )
    parser.add_argument(
        "--keep-tracks-separate",
        flag=True,
        help="Don't mix all audio tracks into one when exporting",
    )
    parser.add_argument(
        "--audio-normalize",
        metavar="NORM-TYPE",
        help="Apply audio rendering to all audio tracks. Applied right before rendering the output file",
    )
    parser.add_text("Miscellaneous:")
    parser.add_argument(
        "-sn",
        flag=True,
        help="Disable the inclusion of subtitle streams in the output file",
    )
    parser.add_argument(
        "-dn",
        flag=True,
        help="Disable the inclusion of data streams in the output file",
    )
    parser.add_argument(
        "--extras",
        metavar="CMD",
        help="Add extra options for ffmpeg. Must be in quotes",
    )
    parser.add_argument(
        "--config", flag=True, help="When set, look for `config.pal` and run it"
    )
    parser.add_argument(
        "--no-cache", flag=True, help="Don't look for or write a cache file"
    )
    parser.add_argument("--version", "-V", flag=True, help="Display version and halt")
    return parser


def download_video(my_input: str, args: Args, ffmpeg: FFmpeg, log: Log) -> str:
    log.conwrite("Downloading video...")

    def get_domain(url: str) -> str:
        t = __import__("urllib.parse", fromlist=["parse"]).urlparse(url).netloc
        return ".".join(t.split(".")[-2:])

    download_format = args.download_format
    if download_format is None and get_domain(my_input) == "youtube.com":
        download_format = "bestvideo[ext=mp4]+bestaudio[ext=m4a]"

    if args.output_format is None:
        output_format = re.sub(r"\W+", "-", splitext(my_input)[0]) + ".%(ext)s"
    else:
        output_format = args.output_format

    yt_dlp_path = args.yt_dlp_location

    cmd = ["--ffmpeg-location", ffmpeg.get_path("yt-dlp", log)]

    if download_format is not None:
        cmd.extend(["-f", download_format])

    cmd.extend(["-o", output_format, my_input])

    if args.yt_dlp_extras is not None:
        cmd.extend(args.yt_dlp_extras.split(" "))

    try:
        location = get_stdout(
            [yt_dlp_path, "--get-filename", "--no-warnings"] + cmd
        ).strip()
    except FileNotFoundError:
        log.error("Program `yt-dlp` must be installed and on PATH.")

    if not isfile(location):
        run([yt_dlp_path] + cmd)

    if not isfile(location):
        log.error(f"Download file wasn't created: {location}")

    return location


def main() -> None:
    subcommands = ("test", "info", "levels", "subdump", "desc", "repl", "palet")

    if len(sys.argv) > 1 and sys.argv[1] in subcommands:
        obj = __import__(
            f"auto_editor.subcommands.{sys.argv[1]}", fromlist=["subcommands"]
        )
        obj.main(sys.argv[2:])
        return

    no_color = bool(environ.get("NO_COLOR") or environ.get("AV_LOG_FORCE_NOCOLOR"))
    log = Log(no_color=no_color)

    args = main_options(ArgumentParser("Auto-Editor")).parse_args(
        Args,
        sys.argv[1:],
        log,
        macros=[
            ({"--frame-margin"}, ["--margin"]),
            ({"--export-to-premiere", "-exp"}, ["--export", "premiere"]),
            ({"--export-to-resolve", "-exr"}, ["--export", "resolve"]),
            ({"--export-to-final-cut-pro", "-exf"}, ["--export", "final-cut-pro"]),
            ({"--export-to-shotcut", "-exs"}, ["--export", "shotcut"]),
            ({"--export-as-json"}, ["--export", "json"]),
            ({"--export-as-clip-sequence", "-excs"}, ["--export", "clip-sequence"]),
            ({"--keep-tracks-seperate"}, ["--keep-tracks-separate"]),
        ],
    )

    if args.version:
        print(auto_editor.__version__)
        return

    if args.debug and not args.input:
        import platform as plat

        import av

        license = av._core.library_meta["libavcodec"]["license"]

        print(f"OS: {plat.system()} {plat.release()} {plat.machine().lower()}")
        print(f"Python: {plat.python_version()}")
        print(f"PyAV: {av.__version__} ({license})")
        print(f"Auto-Editor: {auto_editor.__version__}")
        return

    if not args.input:
        log.error("You need to give auto-editor an input file.")

    is_machine = args.progress == "machine"
    log = Log(args.debug, args.quiet, args.temp_dir, is_machine, no_color)

    ffmpeg = FFmpeg(args.ffmpeg_location)
    paths = []
    for my_input in args.input:
        if my_input.startswith("http://") or my_input.startswith("https://"):
            paths.append(download_video(my_input, args, ffmpeg, log))
        else:
            if not splitext(my_input)[1]:
                if isdir(my_input):
                    log.error("Input must be a file or a URL, not a directory.")
                if exists(my_input):
                    log.error(f"Input file must have an extension: {my_input}")
                if lexists(my_input):
                    log.error(f"Input file is a broken symbolic link: {my_input}")
                if my_input.startswith("-"):
                    log.error(f"Option/Input file doesn't exist: {my_input}")
            paths.append(my_input)

    try:
        edit_media(paths, ffmpeg, args, log)
    except KeyboardInterrupt:
        log.error("Keyboard Interrupt")
    log.cleanup()


if __name__ == "__main__":
    main()
