'''subcommands/grep.py'''

from __future__ import print_function

def grep_options(parser):
    parser.add_argument('--max_count', '-m', type=int, default=float('inf'),
        help='Stop reading a file after NUM matching lines')
    parser.add_argument('--count', '-c', action='store_true',
        help='Suppress normal output; instead print count of matching lines for each file.')
    parser.add_argument('--ignore_case', '-i', action='store_true',
        help='Ignore case distinctions for the PATTERN.')
    parser.add_argument('--my_ffmpeg', action='store_true',
        help='use your ffmpeg and other binaries instead of the ones packaged.')
    parser.add_argument('--help', '-h', action='store_true',
        help='print info about the program or an option and exit.')
    parser.add_argument('input', nargs='*',
        help='the path to a file you want inspected.')
    return parser


def grep(sys_args=None):
    import os
    import re
    import sys
    import tempfile

    import auto_editor
    import auto_editor.vanparse as vanparse

    from auto_editor.utils.log import Log
    from auto_editor.ffwrapper import FFmpeg

    parser = vanparse.ArgumentParser('grep', auto_editor.version,
        description='Read and match subtitle tracks in media files.')
    parser = grep_options(parser)

    if(sys_args is None):
        sys_args = sys.args[1:]

    TEMP = tempfile.mkdtemp()
    log = Log(temp=TEMP)
    args = parser.parse_args(sys_args, log, 'grep')

    dir_path = os.path.dirname(os.path.dirname(os.path.realpath(__file__)))
    ffmpeg = FFmpeg(dir_path, args.my_ffmpeg, False, log)

    regex = args.input[0]
    media_files = args.input[1:]

    flags = 0
    if(args.ignore_case):
        flags = re.IGNORECASE

    """
    we're using the WEBVTT subtitle format. It's better than srt
    because it doesn't emit line numbers and the time code is in
    (hh:mm:ss.sss) instead of (dd:hh:mm:ss,sss)
    """

    for media_file in media_files:

        if(not os.path.exists(media_file)):
            log.error('{}: File does not exist.'.format(media_file))

        out_file = os.path.join(TEMP, 'media.vtt')
        ffmpeg.run(['-i', media_file, out_file])

        count = 0

        prefix = ''
        if(len(media_files) > 1):
            prefix = '{}:'.format(media_file)

        with open(out_file, 'r') as file:
            while True:
                line = file.readline()

                if(not line or count >= args.max_count):
                    break

                match = re.search(regex, line, flags)

                if(match):
                    count += 1
                    if(not args.count):
                        print(prefix + line.strip())

        if(args.count):
            print(prefix + str(count))

    log.cleanup()

if(__name__ == '__main__'):
    grep()
