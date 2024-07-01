#!/usr/bin/env python3

import sys
from os import environ

import auto_editor
from auto_editor.edit import edit_media
from auto_editor.ffwrapper import FFmpeg
from auto_editor.utils.func import setup_tempdir
from auto_editor.utils.log import Log
from auto_editor.utils.types import (
    Args,
    bitrate,
    color,
    frame_rate,
    margin,
    number,
    resolution,
    sample_rate,
    speed,
    speed_range,
    time_range,
)
from auto_editor.validate_input import valid_input
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
        type=color,
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
        "--export",
        "-ex",
        metavar="EXPORT:ATTRS?",
        help="Choose the export mode",
    )
    parser.add_argument(
        "--output-file",
        "--output",
        "-o",
        metavar="FILE",
        help="Set the name/path of the new output file.",
    )
    parser.add_argument(
        "--player",
        "-p",
        metavar="CMD",
        help="Set player to open output media files",
    )
    parser.add_argument(
        "--no-open",
        flag=True,
        help="Do not open the output file after editing is done",
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
    parser.add_argument(
        "--my-ffmpeg",
        flag=True,
        help="Use the ffmpeg on your PATH instead of the one packaged",
    )
    parser.add_text("Display Options:")
    parser.add_argument(
        "--progress",
        metavar="PROGRESS",
        choices=("modern", "classic", "ascii", "machine", "none"),
        help="Set what type of progress bar to use",
    )
    parser.add_argument("--debug", flag=True, help="Show debugging messages and values")
    parser.add_argument(
        "--show-ffmpeg-commands", flag=True, help="Show ffmpeg commands"
    )
    parser.add_argument(
        "--show-ffmpeg-output", flag=True, help="Show ffmpeg stdout and stderr"
    )
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
        type=bitrate,
        help="Set the number of bits per second for video",
    )
    parser.add_argument(
        "--video-quality-scale",
        "-qscale:v",
        "-q:v",
        metavar="SCALE",
        help="Set a value to the ffmpeg option -qscale:v",
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
        type=bitrate,
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
        help="Apply audio rendering to all audio tracks. Applied right before rendering the output file.",
    )
    parser.add_text("Miscellaneous:")
    parser.add_argument(
        "-sn",
        flag=True,
        help="Disable the inclusion of subtitle streams in the output file",
    )
    parser.add_argument(
        "--extras",
        metavar="CMD",
        help="Add extra options for ffmpeg. Must be in quotes",
    )
    parser.add_argument("--version", "-V", flag=True, help="Display version and halt")
    return parser


def main() -> None:
    subcommands = ("test", "info", "levels", "subdump", "desc", "repl", "palet")

    if len(sys.argv) > 1 and sys.argv[1] in subcommands:
        obj = __import__(
            f"auto_editor.subcommands.{sys.argv[1]}", fromlist=["subcommands"]
        )
        obj.main(sys.argv[2:])
        return

    ff_color = "AV_LOG_FORCE_NOCOLOR"
    no_color = bool(environ.get("NO_COLOR")) or bool(environ.get(ff_color))
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
        print(f"{auto_editor.version} ({auto_editor.__version__})")
        return

    if args.debug and not args.input:
        import platform as plat

        import av

        print(f"OS: {plat.system()} {plat.release()} {plat.machine().lower()}")
        print(f"Python: {plat.python_version()}")
        print(f"PyAV: {av.__version__}")
        print(f"Auto-Editor: {auto_editor.version}")
        return

    if not args.input:
        log.error("You need to give auto-editor an input file.")

    temp = setup_tempdir(args.temp_dir, log)
    log = Log(args.debug, args.quiet, temp, args.progress == "machine", no_color)
    log.debug(f"Temp Directory: {temp}")

    ffmpeg = FFmpeg(
        args.ffmpeg_location,
        args.my_ffmpeg,
        args.show_ffmpeg_commands,
        args.show_ffmpeg_output,
    )
    paths = valid_input(args.input, ffmpeg, args, log)

    try:
        edit_media(paths, ffmpeg, args, temp, log)
    except KeyboardInterrupt:
        log.error("Keyboard Interrupt")
    log.cleanup()


if __name__ == "__main__":
    main()
