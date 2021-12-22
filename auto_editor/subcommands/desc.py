'''subcommands/desc.py'''

import sys

def desc_options(parser):
    parser.add_argument('--ffmpeg_location', default=None,
        help='Point to your custom ffmpeg file.')
    parser.add_argument('--help', '-h', action='store_true',
        help='Print info about the program or an option and exit.')
    parser.add_argument('input', nargs='*',
        help='The path to file(s)')
    return parser

def main(sys_args=sys.argv[1:]):
    import auto_editor
    import auto_editor.vanparse as vanparse

    from auto_editor.utils.log import Log
    from auto_editor.ffwrapper import FFmpeg

    parser = vanparse.ArgumentParser('desc', auto_editor.version,
        description="Print the video's metadata description.")
    parser = desc_options(parser)

    log = Log()

    try:
        args = parser.parse_args(sys_args)
    except vanparse.ParserError as e:
        log.error(str(e))

    ffmpeg = FFmpeg(args.ffmpeg_location, debug=False)

    print('')
    for input_file in args.input:
        inp = ffmpeg.file_info(input_file)
        if('description' in inp.metadata):
            print(inp.metadata['description'], end='\n\n')
        else:
            print('No description.', end='\n\n')

    log.cleanup()


if(__name__ == '__main__'):
    main()
