'''subcommands/subdump.py'''

import sys

def subdump_options(parser):
    parser.add_argument('--ffmpeg_location', default=None,
        help='Point to your custom ffmpeg file.')
    parser.add_argument('--my_ffmpeg', action='store_true',
        help='Use the ffmpeg on your PATH instead of the one packaged.')
    parser.add_argument('--help', '-h', action='store_true',
        help='Print info about the program or an option and exit.')
    parser.add_argument('input', nargs='*',
        help='The path to a file you want inspected.')
    return parser

def main(sys_args=sys.argv[1:]):
    import os
    import tempfile

    import auto_editor
    import auto_editor.vanparse as vanparse

    from auto_editor.utils.log import Log
    from auto_editor.ffwrapper import FFmpeg

    parser = vanparse.ArgumentParser('subdump', auto_editor.version,
        description='Dump subtitle streams to stdout in text readable form.')
    parser = subdump_options(parser)

    temp = tempfile.mkdtemp()
    log = Log(temp=temp)

    try:
        args = parser.parse_args(sys_args)
    except vanparse.ParserError as e:
        log.error(str(e))

    ffmpeg = FFmpeg(args.ffmpeg_location, args.my_ffmpeg, debug=False)

    for i, input_file in enumerate(args.input):
        inp = ffmpeg.file_info(input_file)

        cmd = ['-i', input_file]
        for s, sub in enumerate(inp.subtitle_streams):
            cmd.extend(['-map', '0:s:{}'.format(s),
                os.path.join(temp, '{}s{}.{}'.format(i, s, sub['ext']))])
        ffmpeg.run(cmd)

        for s, sub in enumerate(inp.subtitle_streams):
            print('file: {} ({}:{}:{})'.format(input_file, s, sub['lang'], sub['ext']))
            with open(os.path.join(temp, '{}s{}.{}'.format(i, s, sub['ext']))) as file:
                print(file.read())
            print('------')

    log.cleanup()

if(__name__ == '__main__'):
    main()
