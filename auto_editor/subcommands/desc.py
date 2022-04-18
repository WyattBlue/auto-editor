import sys


def desc_options(parser):
    parser.add_argument("--ffmpeg-location", help="Point to your custom ffmpeg file.")
    parser.add_required("input", nargs="*", help="Path to file(s)")
    return parser


def main(sys_args=sys.argv[1:]):
    from auto_editor.vanparse import ArgumentParser
    from auto_editor.ffwrapper import FFmpeg, FileInfo
    from auto_editor.utils.log import Log

    parser = desc_options(ArgumentParser("desc"))
    args = parser.parse_args(sys_args)

    ffmpeg = FFmpeg(args.ffmpeg_location, debug=False)

    print("")
    for input_file in args.input:
        inp = FileInfo(input_file, ffmpeg, Log())
        if "description" in inp.metadata:
            print(inp.metadata["description"], end="\n\n")
        else:
            print("No description.", end="\n\n")


if __name__ == "__main__":
    main()
