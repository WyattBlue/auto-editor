'''subcommands/grep.py'''

import sys
import os
import re
import tempfile

def grep_options(parser):
    parser.add_argument('--no_filename', action='store_true',
        help='Never print filenames with output lines.')
    parser.add_argument('--max_count', '-m', type=int, default=float('inf'),
        help='Stop reading a file after NUM matching lines.')
    parser.add_argument('--count', '-c', action='store_true',
        help='Suppress normal output; instead print count of matching lines for each file.')
    parser.add_argument('--ignore_case', '-i', action='store_true',
        help='Ignore case distinctions for the PATTERN.')
    parser.add_argument('--timecode', action='store_true',
        help="Print the match's timecode.")
    parser.add_argument('--time', action='store_true',
        help="Print when the match happens. (Ignore ending).")
    parser.add_argument('--ffmpeg_location', default=None,
        help='Point to your custom ffmpeg file.')
    parser.add_argument('--my_ffmpeg', action='store_true',
        help='Use the ffmpeg on your PATH instead of the one packaged.')
    parser.add_argument('--help', '-h', action='store_true',
        help='Print info about the program or an option and exit.')
    parser.add_argument('input', nargs='*',
        help='The path to a file you want inspected.')
    return parser

# stackoverflow.com/questions/9662346/python-code-to-remove-html-tags-from-a-string
def cleanhtml(raw_html):
    # type: (str) -> str
    cleanr = re.compile('<.*?>')
    cleantext = re.sub(cleanr, '', raw_html)
    return cleantext

def grep_core(media_file, add_prefix, ffmpeg, args, log, TEMP):

    """
    We're using the WEBVTT subtitle format. It's better than srt
    because it doesn't emit line numbers and the time code is in
    (hh:mm:ss.sss) instead of (dd:hh:mm:ss,sss)
    """

    out_file = os.path.join(TEMP, 'media.vtt')
    ffmpeg.run(['-i', media_file, out_file])

    count = 0

    flags = 0
    if(args.ignore_case):
        flags = re.IGNORECASE

    prefix = ''
    if(add_prefix):
        prefix = '{}:'.format(os.path.splitext(os.path.basename(media_file))[0])

    timecode = ''
    line_number = -1
    with open(out_file, 'r') as file:
        while True:
            line = file.readline()
            line_number += 1
            if(line_number == 0):
                continue

            if(not line or count >= args.max_count):
                break

            if(line.strip() == ''):
                continue

            if(re.match(r'\d*:\d\d.\d*\s-->\s\d*:\d\d.\d*', line)):
                if(args.time):
                    timecode = line.split('-->')[0].strip() + ' '
                else:
                    timecode = line.strip() + '; '
                continue

            line = cleanhtml(line)
            match = re.search(args.input[0], line, flags)
            line = line.strip()

            if(match):
                count += 1
                if(not args.count):
                    if(args.timecode or args.time):
                        print(prefix + timecode + line)
                    else:
                        print(prefix + line)

    if(args.count):
        print(prefix + str(count))


def main(sys_args=sys.argv[1:]):
    import auto_editor
    import auto_editor.vanparse as vanparse

    from auto_editor.utils.log import Log
    from auto_editor.ffwrapper import FFmpeg

    parser = vanparse.ArgumentParser('grep', auto_editor.version,
        description='Read and match subtitle tracks in media files.')
    parser = grep_options(parser)

    TEMP = tempfile.mkdtemp()
    log = Log(temp=TEMP)

    try:
        args = parser.parse_args(sys_args)
    except vanparse.ParserError as e:
        log.error(str(e))

    ffmpeg = FFmpeg(args.ffmpeg_location, args.my_ffmpeg, debug=False)

    media_files = args.input[1:]

    add_prefix = (len(media_files) > 1 or os.path.isdir(media_files[0])) and not args.no_filename

    for media_file in media_files:
        if(not os.path.exists(media_file)):
            log.error('{}: File does not exist.'.format(media_file))

        if(os.path.isdir(media_file)):
            for _, _, files in os.walk(media_file):
                for file in files:
                    if(file == '.DS_Store'):
                        continue
                    grep_core(os.path.join(media_file, file),
                        add_prefix, ffmpeg, args, log, TEMP)
        else:
            grep_core(media_file, add_prefix, ffmpeg, args, log, TEMP)

    log.cleanup()

if(__name__ == '__main__'):
    main()
