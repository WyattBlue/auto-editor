#!/usr/bin/env python3

import os
import sys
import tempfile

import auto_editor
import auto_editor.utils.func as usefulfunctions
from auto_editor.edit import edit_media
from auto_editor.ffwrapper import FFmpeg
from auto_editor.utils.log import Log, Timer
from auto_editor.utils.types import (
    MainArgs,
    color,
    frame_rate,
    margin,
    number,
    resolution,
    sample_rate,
    speed_range,
    time,
    time_range,
)
from auto_editor.validate_input import valid_input
from auto_editor.vanparse import ArgumentParser


def main_options(parser: ArgumentParser) -> ArgumentParser:
    parser.add_required("input", nargs="*", metavar="[file | url ...] [options]")
    parser.add_text("Editing Options:")
    parser.add_argument(
        "--frame-margin",
        "--margin",
        "-m",
        type=margin,
        metavar="LENGTH",
        help='Set sections near "loud" as "loud" too if section is less than LENGTH away.',
    )
    parser.add_argument(
        "--min-clip-length",
        "-minclip",
        "-mclip",
        type=time,
        metavar="LENGTH",
        help="Set the minimum length a clip can be. If a clip is too short, cut it",
    )
    parser.add_argument(
        "--min-cut-length",
        "-mincut",
        "-mcut",
        type=time,
        metavar="LENGTH",
        help="Set the minimum length a cut can be. If a cut is too short, don't cut",
    )
    parser.add_argument(
        "--edit-based-on",
        "--edit",
        metavar="[METHOD:[ATTRS?] OPERAND? ...]",
        help="Decide which method to use when making edits",
    )
    parser.add_argument(
        "--silent-speed",
        "-s",
        type=number,
        metavar="NUM",
        help='Set speed of sections marked "silent" to NUM',
    )
    parser.add_argument(
        "--video-speed",
        "--sounded-speed",
        "-v",
        type=number,
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
        "--mark-as-loud",
        type=time_range,
        nargs="*",
        metavar="[START,STOP ...]",
        help='The range that will be marked as "loud"',
    )
    parser.add_argument(
        "--mark-as-silent",
        type=time_range,
        nargs="*",
        metavar="[START,STOP ...]",
        help='The range that will be marked as "silent"',
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
        "--api",
        metavar="VERSION",
        help="Set what version of the timeline to use",
    )
    parser.add_argument(
        "--add",
        nargs="*",
        metavar="OBJ:START,DUR,ATTRS?",
        help="Insert an timeline object to the timeline",
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
        choices=(
            "default",
            "premiere",
            "final-cut-pro",
            "shotcut",
            "json",
            "audio",
            "clip-sequence",
        ),
        metavar="EXPORT",
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
        "--show-ffmpeg-debug", flag=True, help="Show ffmpeg progress and output"
    )
    parser.add_argument("--quiet", "-q", flag=True, help="Display less output")
    parser.add_argument(
        "--preview",
        "--stats",
        flag=True,
        help="Show stats on how the input will be cut and halt",
    )
    parser.add_argument(
        "--timeline", flag=True, help="Show auto-editor JSON timeline file and halt"
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
        help="Set the number of bits per second for audio",
    )
    parser.add_argument(
        "--keep-tracks-separate",
        flag=True,
        help="Don't mix all audio tracks into one when exporting",
    )
    parser.add_text("Miscellaneous:")
    parser.add_argument(
        "--extras",
        metavar="CMD",
        help="Add extra options for ffmpeg. Must be in quotes",
    )
    parser.add_argument("--version", "-V", flag=True, help="Display version and halt")
    return parser


def main() -> None:
    subcommands = ("test", "info", "levels", "grep", "subdump", "desc")

    if len(sys.argv) > 1 and sys.argv[1] in subcommands:
        obj = __import__(
            f"auto_editor.subcommands.{sys.argv[1]}", fromlist=["subcommands"]
        )
        obj.main(sys.argv[2:])
        sys.exit()
    else:
        args = main_options(ArgumentParser("Auto-Editor")).parse_args(
            MainArgs,
            sys.argv[1:],
            macros=[
                ({"--export-to-premiere", "-exp"}, ["--export", "premiere"]),
                ({"--export-to-final-cut-pro", "-exf"}, ["--export", "final-cut-pro"]),
                ({"--export-to-shotcut", "-exs"}, ["--export", "shotcut"]),
                ({"--export-as-json"}, ["--export", "json"]),
                ({"--export-as-clip-sequence", "-excs"}, ["--export", "clip-sequence"]),
                ({"--keep-tracks-seperate"}, ["--keep-tracks-separate"]),
            ],
        )

    log = Log(args.debug, args.quiet)
    timer = Timer(args.quiet)

    exporting_to_editor = args.export in ("premiere", "final-cut-pro", "shotcut")

    ffmpeg = FFmpeg(args.ffmpeg_location, args.my_ffmpeg, args.show_ffmpeg_debug)

    if args.debug and args.input == []:
        import platform as plat

        is64bit = "64-bit" if sys.maxsize > 2**32 else "32-bit"
        print(f"Python Version: {plat.python_version()} {is64bit}")
        print(f"Platform: {plat.system()} {plat.release()} {plat.machine().lower()}")
        print(f"FFmpeg Version: {ffmpeg.version}\nFFmpeg Path: {ffmpeg.path}")
        print(f"Auto-Editor Version: {auto_editor.version}")
        sys.exit()

    if args.version:
        print(f"{auto_editor.version} ({auto_editor.__version__})")
        sys.exit()

    if args.timeline:
        args.quiet = True

    if args.input == []:
        log.error("You need to give auto-editor an input file.")

    if args.temp_dir is None:
        temp = tempfile.mkdtemp()
    else:
        temp = args.temp_dir
        if os.path.isfile(temp):
            log.error("Temp directory cannot be an already existing file.")
        if os.path.isdir(temp):
            if len(os.listdir(temp)) != 0:
                log.error("Temp directory should be empty!")
        else:
            os.mkdir(temp)

    log = Log(args.debug, args.quiet, temp=temp)
    log.debug(f"Temp Directory: {temp}")

    log.conwrite("Starting")

    if args.preview or args.export not in ("audio", "default"):
        args.no_open = True

    if args.silent_speed <= 0 or args.silent_speed > 99999:
        args.silent_speed = 99999

    if args.video_speed <= 0 or args.video_speed > 99999:
        args.video_speed = 99999

    paths = valid_input(args.input, ffmpeg, args, log)

    if exporting_to_editor and len(paths) > 1:
        cmd = []
        for path in paths:
            cmd.extend(["-i", path])
        cmd.extend(
            [
                "-filter_complex",
                f"[0:v]concat=n={len(paths)}:v=1:a=1",
                "-codec:v",
                "h264",
                "-pix_fmt",
                "yuv420p",
                "-strict",
                "-2",
                "combined.mp4",
            ]
        )
        ffmpeg.run(cmd)
        paths = ["combined.mp4"]
    try:
        output = edit_media(paths, ffmpeg, args, temp, log)

        if not args.preview and not args.timeline:
            timer.stop()

        if not args.no_open and output is not None:
            if args.player is None:
                usefulfunctions.open_with_system_default(output, log)
            else:
                import subprocess
                from shlex import split

                subprocess.run(split(args.player) + [output])
    except KeyboardInterrupt:
        log.error("Keyboard Interrupt")
    log.cleanup()


if __name__ == "__main__":
    main()
