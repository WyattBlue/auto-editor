#!/usr/bin/env python3

# Internal Libraries
import os
import sys
import tempfile

# Typing
from typing import List

# Included Libraries
import auto_editor
import auto_editor.vanparse as vanparse
import auto_editor.utils.func as usefulfunctions

from auto_editor.utils.progressbar import ProgressBar
from auto_editor.utils.log import Log, Timer
from auto_editor.ffwrapper import FFmpeg, FileInfo
from auto_editor.edit import edit_media


def main_options(parser):
    from auto_editor.utils.types import (
        float_type,
        sample_rate_type,
        frame_type,
        range_type,
        speed_range_type,
        margin_type,
        color_type,
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
    parser.add_argument(
        "--yt-dlp-location", default="yt-dlp", help="Set a custom path to yt-dlp."
    )
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
        default="auto",
        help="Set the video codec for the output media file.",
    )
    parser.add_argument(
        "--audio-codec",
        "-acodec",
        "-c:a",
        default="auto",
        help="Set the audio codec for the output media file.",
    )
    parser.add_argument(
        "--video-bitrate",
        "-b:v",
        default="10m",
        help="Set the number of bits per second for video.",
    )
    parser.add_argument(
        "--audio-bitrate",
        "-b:a",
        default="unset",
        help="Set the number of bits per second for audio.",
    )
    parser.add_argument(
        "--sample-rate",
        "-ar",
        type=sample_rate_type,
        help="Set the sample rate of the input and output videos.",
    )
    parser.add_argument(
        "--video-quality-scale",
        "-qscale:v",
        "-q:v",
        default="unset",
        help="Set a value to the ffmpeg option -qscale:v",
    )
    parser.add_argument(
        "--scale",
        type=float_type,
        default=1,
        help="Scale the output video by a certain factor.",
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
    parser.add_text("Miscellaneous Options")
    parser.add_argument(
        "--background",
        type=color_type,
        default="#000",
        help="Set the color of the background that is visible when the video is moved.",
    )
    parser.add_argument(
        "--combine-files",
        flag=True,
        help="Combine all input files into one before editing.",
    )
    parser.add_argument(
        "--progress",
        default="modern",
        choices=["modern", "classic", "ascii", "machine", "none"],
        help="Set what type of progress bar to use.",
    )
    parser.add_text("Manual Editing Options")
    parser.add_argument(
        "--cut-out",
        type=range_type,
        nargs="*",
        help="The range of media that will be removed completely, regardless of the "
        "value of silent speed.",
    )
    parser.add_argument(
        "--add-in",
        type=range_type,
        nargs="*",
        help="The range of media that will be added in, opposite of --cut-out",
    )
    parser.add_blank()
    parser.add_argument(
        "--mark-as-loud",
        type=range_type,
        nargs="*",
        help='The range that will be marked as "loud".',
    )
    parser.add_argument(
        "--mark-as-silent",
        type=range_type,
        nargs="*",
        help='The range that will be marked as "silent".',
    )
    parser.add_argument(
        "--set-speed-for-range",
        type=speed_range_type,
        nargs="*",
        help="Set an arbitrary speed for a given range.",
    )
    parser.add_text("Select Editing Source Options")
    parser.add_argument(
        "--edit-based-on",
        "--edit",
        default="audio",
        help="Decide which method to use when making edits.",
    )
    parser.add_argument(
        "--keep-tracks-seperate",
        flag=True,
        help="Don't combine audio tracks when exporting.",
    )
    parser.add_argument(
        "--export",
        default="default",
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
    parser.add_argument(
        "--api",
        default="0.2.0",
        help="Set what version of the JSON timeline to output.",
    )
    parser.add_text("Editing Options")
    parser.add_argument(
        "--silent-threshold",
        "-t",
        type=float_type,
        default=0.04,
        help="Set the volume that frames audio needs to surpass to be marked loud.",
    )
    parser.add_argument(
        "--frame-margin",
        "--margin",
        "-m",
        type=margin_type,
        default="6",
        help='Set how many "silent" frames on either side of the "loud" sections to include.',
    )
    parser.add_argument(
        "--silent-speed",
        "-s",
        type=float_type,
        default=99999,
        help='Set the speed that "silent" sections should be played at.',
    )
    parser.add_argument(
        "--video-speed",
        "--sounded-speed",
        "-v",
        type=float_type,
        default=1,
        help='Set the speed that "loud" sections should be played at.',
    )
    parser.add_argument(
        "--min-clip-length",
        "-mclip",
        type=frame_type,
        default=3,
        help="Set the minimum length a clip can be. If a clip is too short, cut it.",
    )
    parser.add_argument(
        "--min-cut-length",
        "-mcut",
        type=frame_type,
        default=6,
        help="Set the minimum length a cut can be. If a cut is too short, don't cut.",
    )
    parser.add_blank()
    parser.add_argument(
        "--output-file",
        "--output",
        "-o",
        nargs="*",
        help="Set the name(s) of the new output.",
    )
    parser.add_required(
        "input", nargs="*", help="File(s) or URL(s) that will be edited."
    )

    return parser


def main():
    parser = vanparse.ArgumentParser("Auto-Editor")

    subcommands = ["test", "info", "levels", "grep", "subdump", "desc"]

    if len(sys.argv) > 1 and sys.argv[1] in subcommands:
        obj = __import__(
            f"auto_editor.subcommands.{sys.argv[1]}", fromlist=["subcommands"]
        )
        obj.main(sys.argv[2:])
        sys.exit()
    else:
        parser = main_options(parser)

        # Preserve backwards compatibility

        sys_a = sys.argv[1:]

        def c(sys_a, options, new):
            for option in options:
                if option in sys_a:
                    pos = sys_a.index(option)
                    sys_a[pos : pos + 1] = new
            return sys_a

        sys_a = c(
            sys_a,
            ["--export_to_premiere", "--export-to-premiere", "-exp"],
            ["--export", "premiere"],
        )
        sys_a = c(
            sys_a,
            ["--export_to_final_cut_pro", "--export-to-final-cut-pro", "-exf"],
            ["--export", "final-cut-pro"],
        )
        sys_a = c(
            sys_a,
            ["--export_to_shotcut", "--export-to-shotcut", "-exs"],
            ["--export", "shotcut"],
        )
        sys_a = c(sys_a, ["--export_as_json", "--export-as-json"], ["--export", "json"])
        sys_a = c(
            sys_a,
            ["--export_as_clip_sequence", "--export-as-clip-sequence", "-excs"],
            ["--export", "clip-sequence"],
        )

        args = parser.parse_args(sys_a)

    timer = Timer(args.quiet)

    exporting_to_editor = args.export in ("premiere", "final-cut-pro", "shotcut")
    making_data_file = exporting_to_editor or args.export == "json"

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
        Log().error(
            "You need to give auto-editor an input file so it can do the work for you."
        )

    if args.temp_dir is None:
        TEMP = tempfile.mkdtemp()
    else:
        TEMP = args.temp_dir
        if os.path.isfile(TEMP):
            Log().error("Temp directory cannot be an already existing file.")
        if os.path.isdir(TEMP):
            if len(os.listdir(TEMP)) != 0:
                Log().error("Temp directory should be empty!")
        else:
            os.mkdir(TEMP)

    log = Log(args.debug, args.quiet, temp=TEMP)
    log.debug(f"Temp Directory: {TEMP}")

    log.conwrite("Starting")

    if args.preview or args.export not in ("audio", "default"):
        args.no_open = True

    if args.silent_speed <= 0 or args.silent_speed > 99999:
        args.silent_speed = 99999

    if args.video_speed <= 0 or args.video_speed > 99999:
        args.video_speed = 99999

    if args.output_file is None:
        args.output_file = []

    from auto_editor.validate_input import valid_input

    input_list = valid_input(args.input, ffmpeg, args, log)

    if args.combine_files:
        temp_file = (
            "combined.mp4"
            if exporting_to_editor
            else os.path.join(TEMP, "combined.mp4")
        )

        cmd = []
        for fileref in input_list:
            cmd.extend(["-i", fileref])
        cmd.extend(
            [
                "-filter_complex",
                f"[0:v]concat=n={len(input_list)}:v=1:a=1",
                "-codec:v",
                "h264",
                "-pix_fmt",
                "yuv420p",
                "-strict",
                "-2",
                temp_file,
            ]
        )

        ffmpeg.run(cmd)
        del cmd
        input_list = [temp_file]

    def main_loop(input_list: List[str], ffmpeg: FFmpeg, args, log: Log) -> None:
        num_cuts = 0

        progress = ProgressBar(args.progress)

        for i, input_path in enumerate(input_list):
            inp = FileInfo(input_path, ffmpeg, log)

            if len(input_list) > 1:
                log.conwrite(f"Working on {inp.basename}")

            cuts, output_path = edit_media(i, inp, ffmpeg, args, progress, TEMP, log)
            num_cuts += cuts

        if not args.preview and not args.timeline and not making_data_file:
            timer.stop()

        if not args.preview and not args.timeline and making_data_file:
            # Assume making each cut takes about 30 seconds.
            time_save = usefulfunctions.human_readable_time(num_cuts * 30)
            s = "s" if num_cuts != 1 else ""

            log.print(
                f"Auto-Editor made {num_cuts} cut{s}, which would have taken "
                f"about {time_save} if edited manually."
            )

        if not args.no_open and output_path is not None:
            usefulfunctions.open_with_system_default(output_path, log)

    try:
        main_loop(input_list, ffmpeg, args, log)
    except KeyboardInterrupt:
        log.error("Keyboard Interrupt")
    log.cleanup()


if __name__ == "__main__":
    main()
