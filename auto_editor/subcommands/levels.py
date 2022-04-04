import sys


def levels_options(parser):
    parser.add_argument(
        "--kind",
        type=str,
        default="audio",
        choices=["audio", "motion", "pixeldiff"],
    )
    parser.add_argument(
        "--track",
        type=int,
        default=0,
        help="Select the track to get. If `--kind` is set to motion, track will look "
        "at video tracks instead of audio.",
    )
    parser.add_argument(
        "--ffmpeg-location", default=None, help="Point to your custom ffmpeg file."
    )
    parser.add_argument(
        "--my-ffmpeg",
        action="store_true",
        help="Use the ffmpeg on your PATH instead of the one packaged.",
    )
    parser.add_argument(
        "--help",
        "-h",
        action="store_true",
        help="Print info about the program or an option and exit.",
    )
    parser.add_required(
        "input", nargs="*", help="Path to the file to have its levels dumped."
    )
    return parser



def print_float_list(a):
    for item in a:
        sys.stdout.write(f'{item:.20f}\n')


def print_int_list(a):
    for item in a:
        sys.stdout.write(f'{item}\n')


def main(sys_args=sys.argv[1:]):
    import os
    import tempfile

    import auto_editor
    import auto_editor.vanparse as vanparse

    from auto_editor.utils.log import Log
    from auto_editor.utils.progressbar import ProgressBar
    from auto_editor.ffwrapper import FFmpeg, FileInfo

    parser = vanparse.ArgumentParser(
        "levels", auto_editor.version, description="Get loudness of audio over time."
    )
    parser = levels_options(parser)

    temp = tempfile.mkdtemp()
    log = Log(temp=temp)

    try:
        args = parser.parse_args(sys_args)
    except vanparse.ParserError as e:
        log.error(str(e))

    ffmpeg = FFmpeg(args.ffmpeg_location, args.my_ffmpeg, False)

    progress = ProgressBar("none")

    inp = FileInfo(args.input[0], ffmpeg)
    fps = 30 if inp.fps is None else float(inp.fps)

    if args.kind == "audio":
        from auto_editor.analyze.audio import audio_detection

        if args.track >= len(inp.audio_streams):
            log.error(f"Audio track '{args.track}' does not exist.")

        read_track = os.path.join(temp, f"{args.track}.wav")

        ffmpeg.run(
            ["-i", inp.path, "-ac", "2", "-map", f"0:a:{args.track}", read_track]
        )

        if not os.path.isfile(read_track):
            log.error("Audio track file not found!")

        from auto_editor.scipy.wavfile import read
        sample_rate, audio_samples = read(read_track)

        print_float_list(audio_detection(audio_samples, sample_rate, fps, progress))

    if args.kind == "motion":
        if args.track >= len(inp.video_streams):
            log.error(f"Video track '{args.track}' does not exist.")

        from auto_editor.analyze.motion import motion_detection

        print_float_list(motion_detection(inp.path, fps, progress, width=400, blur=9))

    if args.kind == "pixeldiff":
        if args.track >= len(inp.video_streams):
            log.error(f"Video track '{args.track}' does not exist.")

        from auto_editor.analyze.pixeldiff import pixel_difference

        print_int_list(pixel_difference(inp.path, fps, progress))

    log.cleanup()


if __name__ == "__main__":
    main()
