#!/usr/bin/env python3

import os
import sys
import tempfile

import auto_editor
import auto_editor.utils.func as usefulfunctions
from auto_editor.edit import edit_media
from auto_editor.ffwrapper import FFmpeg
from auto_editor.utils.log import Log, Timer
from auto_editor.utils.types import MainArgs
from auto_editor.validate_input import valid_input
from auto_editor.vanparse import ArgumentParser


def main_options(parser: ArgumentParser) -> ArgumentParser:
    from auto_editor.utils.types import (
        color,
        margin,
        number,
        sample_rate,
        speed_range,
        time,
        time_range,
    )

    parser.add_text("Object Options")
    parser.add_argument(
        "--add-text",
        nargs="*",
        help="Add a text object to the timeline.",
    )
    parser.add_argument(
        "--add-rectangle",
        nargs="*",
        help="Add a rectangle object to the timeline.",
    )
    parser.add_argument(
        "--add-ellipse",
        nargs="*",
        help="Add an ellipse object to the timeline.",
    )
    parser.add_argument(
        "--add-image",
        nargs="*",
        help="Add an image object onto the timeline.",
    )
    parser.add_text("URL Download Options")
    parser.add_argument("--yt-dlp-location", help="Set a custom path to yt-dlp.")
    parser.add_argument(
        "--download-format", help="Set the yt-dlp download format. (--format, -f)"
    )
    parser.add_argument(
        "--output-format", help="Set the yt-dlp output file template. (--output, -o)"
    )
    parser.add_argument(
        "--yt-dlp-extras", help="Add extra options for yt-dlp. Must be in quotes"
    )
    parser.add_text("Exporting as Media Options")
    parser.add_argument(
        "--video-codec",
        "-vcodec",
        "-c:v",
        help="Set the video codec for the output media file.",
    )
    parser.add_argument(
        "--audio-codec",
        "-acodec",
        "-c:a",
        help="Set the audio codec for the output media file.",
    )
    parser.add_argument(
        "--video-bitrate",
        "-b:v",
        help="Set the number of bits per second for video.",
    )
    parser.add_argument(
        "--audio-bitrate",
        "-b:a",
        help="Set the number of bits per second for audio.",
    )
    parser.add_argument(
        "--video-quality-scale",
        "-qscale:v",
        "-q:v",
        help="Set a value to the ffmpeg option -qscale:v",
    )
    parser.add_argument(
        "--scale",
        type=number,
        help="Scale the input video's resolution by the given factor.",
    )
    parser.add_argument(
        "--extras",
        help="Add extra options for ffmpeg for video rendering. Must be in quotes.",
    )
    parser.add_argument(
        "--no-seek",
        flag=True,
        help="Disable file seeking when rendering video. Helpful for debugging desync issues.",
    )
    parser.add_text("Manual Editing Options")
    parser.add_argument(
        "--cut-out",
        type=time_range,
        nargs="*",
        help="The range of media that will be removed completely, regardless of the "
        "value of silent speed.",
    )
    parser.add_argument(
        "--add-in",
        type=time_range,
        nargs="*",
        help="The range of media that will be added in, opposite of --cut-out",
    )
    parser.add_blank()
    parser.add_argument(
        "--mark-as-loud",
        type=time_range,
        nargs="*",
        help='The range that will be marked as "loud".',
    )
    parser.add_argument(
        "--mark-as-silent",
        type=time_range,
        nargs="*",
        help='The range that will be marked as "silent".',
    )
    parser.add_argument(
        "--set-speed-for-range",
        "--set-speed",
        type=speed_range,
        nargs="*",
        help="SPEED,START,STOP - Set an arbitrary speed for a given range.",
    )
    parser.add_text("Timeline Options")
    parser.add_argument(
        "--frame-rate",
        "-fps",
        "-r",
        type=float,
        help="Set the frame rate for the timeline and output media.",
    )
    parser.add_argument(
        "--sample-rate",
        "-ar",
        type=sample_rate,
        help="Set the sample rate for the timeline and output media.",
    )
    parser.add_argument(
        "--background",
        type=color,
        help="Set the color of the background that is visible when the video is moved.",
    )
    parser.add_text("Select Editing Source Options")
    parser.add_argument(
        "--edit-based-on",
        "--edit",
        help="Decide which method to use when making edits.",
    )
    parser.add_argument(
        "--keep-tracks-separate",
        flag=True,
        help="Don't combine audio tracks when exporting.",
    )
    parser.add_argument(
        "--export",
        "-ex",
        choices=[
            "default",
            "premiere",
            "final-cut-pro",
            "shotcut",
            "json",
            "audio",
            "clip-sequence",
        ],
        help="Choose the export mode.",
    )
    parser.add_text("Utility Options")
    parser.add_argument(
        "--no-open", flag=True, help="Do not open the file after editing is done."
    )
    parser.add_argument(
        "--temp-dir",
        help="Set where the temporary directory is located.",
    )
    parser.add_argument(
        "--ffmpeg-location",
        help="Set a custom path to the ffmpeg location.",
    )
    parser.add_argument(
        "--my-ffmpeg",
        flag=True,
        help="Use the ffmpeg on your PATH instead of the one packaged.",
    )
    parser.add_text("Display Options")
    parser.add_argument(
        "--progress",
        choices=["modern", "classic", "ascii", "machine", "none"],
        help="Set what type of progress bar to use.",
    )
    parser.add_argument(
        "--version", flag=True, help="Display the program's version and halt."
    )
    parser.add_argument(
        "--debug", flag=True, help="Show debugging messages and values."
    )
    parser.add_argument(
        "--show-ffmpeg-debug", flag=True, help="Show ffmpeg progress and output."
    )
    parser.add_argument("--quiet", "-q", flag=True, help="Display less output.")
    parser.add_argument(
        "--preview", flag=True, help="Show stats on how the input will be cut and halt."
    )
    parser.add_argument(
        "--timeline", flag=True, help="Show auto-editor JSON timeline file and halt."
    )
    parser.add_argument("--api", help="Set what version of the timeline to use.")
    parser.add_text("Global Editing Options")
    parser.add_argument(
        "--silent-threshold",
        "-t",
        type=number,
        help="Set the volume that frames audio needs to surpass to be marked loud.",
    )
    parser.add_argument(
        "--frame-margin",
        "--margin",
        "-m",
        type=margin,
        help='Set how many "silent" frames on either side of the "loud" sections to include.',
    )
    parser.add_argument(
        "--silent-speed",
        "-s",
        type=number,
        help='Set the speed that "silent" sections should be played at.',
    )
    parser.add_argument(
        "--video-speed",
        "--sounded-speed",
        "-v",
        type=number,
        help='Set the speed that "loud" sections should be played at.',
    )
    parser.add_argument(
        "--min-clip-length",
        "-minclip",
        "-mclip",
        type=time,
        help="Set the minimum length a clip can be. If a clip is too short, cut it.",
    )
    parser.add_argument(
        "--min-cut-length",
        "-mincut",
        "-mcut",
        type=time,
        help="Set the minimum length a cut can be. If a cut is too short, don't cut.",
    )
    parser.add_blank()
    parser.add_argument(
        "--output-file",
        "--output",
        "-o",
        help="Set the name/path of the new output file.",
    )
    parser.add_required(
        "input", nargs="*", help="File(s) or URL(s) that will be edited."
    )

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
                ({"--combine-files"}, []),
                ({"--keep-tracks-seperate"}, ["--keep-tracks-separate"]),
            ],
        )

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
        Log().error("You need to give auto-editor an input file.")

    if args.temp_dir is None:
        temp = tempfile.mkdtemp()
    else:
        temp = args.temp_dir
        if os.path.isfile(temp):
            Log().error("Temp directory cannot be an already existing file.")
        if os.path.isdir(temp):
            if len(os.listdir(temp)) != 0:
                Log().error("Temp directory should be empty!")
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

    inputs = valid_input(args.input, ffmpeg, args, log)

    if exporting_to_editor and len(inputs) > 1:
        cmd = []
        for inp in inputs:
            cmd.extend(["-i", inp])
        cmd.extend(
            [
                "-filter_complex",
                f"[0:v]concat=n={len(inputs)}:v=1:a=1",
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
        inputs = ["combined.mp4"]
    try:
        output = edit_media(inputs, ffmpeg, args, temp, log)

        if not args.preview and not args.timeline:
            timer.stop()

        if not args.no_open and output is not None:
            usefulfunctions.open_with_system_default(output, log)
    except KeyboardInterrupt:
        log.error("Keyboard Interrupt")
    log.cleanup()


if __name__ == "__main__":
    main()
