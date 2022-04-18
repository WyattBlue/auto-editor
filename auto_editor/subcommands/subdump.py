import sys


def subdump_options(parser):
    parser.add_argument("--ffmpeg-location", help="Point to your custom ffmpeg file.")
    parser.add_argument(
        "--my-ffmpeg",
        flag=True,
        help="Use the ffmpeg on your PATH instead of the one packaged.",
    )
    parser.add_required(
        "input", nargs="*", help="Path to the file to have its subtitles dumped."
    )
    return parser


def main(sys_args=sys.argv[1:]):
    import os
    import tempfile

    from auto_editor.utils.log import Log
    from auto_editor.vanparse import ArgumentParser
    from auto_editor.ffwrapper import FFmpeg, FileInfo

    parser = subdump_options(ArgumentParser("subdump"))
    args = parser.parse_args(sys_args)

    ffmpeg = FFmpeg(args.ffmpeg_location, args.my_ffmpeg, debug=False)

    temp = tempfile.mkdtemp()
    log = Log(temp=temp)

    for i, input_file in enumerate(args.input):
        inp = FileInfo(input_file, ffmpeg, log)

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
