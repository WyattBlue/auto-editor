'''subcommands/info.py'''

import sys
import os.path

def info_options(parser):
    parser.add_argument('--include_vfr', '--has_vfr', action='store_true',
        help='skip information that is very slow to get.')
    parser.add_argument('--ffmpeg_location', default=None,
        help='point to your custom ffmpeg file.')
    parser.add_argument('--my_ffmpeg', action='store_true',
        help='use the ffmpeg on your PATH instead of the one packaged.')
    parser.add_argument('--help', '-h', action='store_true',
        help='print info about the program or an option and exit.')
    parser.add_argument('(input)', nargs='*',
        help='the path to a file you want inspected.')
    return parser

def main(sys_args=sys.argv[1:]):

    import auto_editor
    import auto_editor.vanparse as vanparse

    from auto_editor.utils.func import aspect_ratio
    from auto_editor.utils.log import Log

    from auto_editor.ffwrapper import FFmpeg

    parser = vanparse.ArgumentParser('info', auto_editor.version,
        description='Get basic information about media files.')
    parser = info_options(parser)

    log = Log()
    args = parser.parse_args(sys_args, log, 'info')

    ffmpeg = FFmpeg(args.ffmpeg_location, args.my_ffmpeg, False)

    def aspect_str(w, h):
        w, h = aspect_ratio(int(w), int(h))
        if(w is None):
            return ''
        return ' ({}:{})'.format(w, h)

    for file in args.input:
        text = ''
        if(os.path.exists(file)):
            text += 'file: {}\n'.format(file)
        else:
            log.error('Could not find file: {}'.format(file))

        inp = ffmpeg.file_info(file)

        if(len(inp.video_streams) > 0):
            text += f' - video tracks: {len(inp.video_streams)}\n'

        for track, stream in enumerate(inp.video_streams):
            text += '   - Track #{}\n'.format(track)

            text += '     - codec: {}\n'.format(stream['codec'])
            if(stream['fps'] is not None):
                text += '     - fps: {}\n'.format(stream['fps'])

            w = stream['width']
            h = stream['height']

            if(w is not None and h is not None):
                text += '     - resolution: {}x{}{}\n'.format(w, h, aspect_str(w, h))

            if(stream['bitrate'] is not None):
                text += '     - bitrate: {}\n'.format(stream['bitrate'])
            if(stream['lang'] is not None):
                text += '     - lang: {}\n'.format(stream['lang'])


        if(len(inp.audio_streams) > 0):
            text += f' - audio tracks: {len(inp.audio_streams)}\n'

        for track, stream in enumerate(inp.audio_streams):
            text += '   - Track #{}\n'.format(track)
            text += '     - codec: {}\n'.format(stream['codec'])
            text += '     - samplerate: {}\n'.format(stream['samplerate'])

            if(stream['bitrate'] is not None):
                text += '     - bitrate: {}\n'.format(stream['bitrate'])

            if(stream['lang'] is not None):
                text += '     - lang: {}\n'.format(stream['lang'])

        if(len(inp.subtitle_streams) > 0):
            text += f' - subtitle tracks: {len(inp.subtitle_streams)}\n'

        for track, stream in enumerate(inp.subtitle_streams):
            text += '   - Track #{}\n'.format(track)
            text += '     - codec: {}\n'.format(stream['codec'])
            if(stream['lang'] is not None):
                text += '     - lang: {}\n'.format(stream['lang'])


        if(len(inp.video_streams) == 0 and len(inp.audio_streams) == 0 and
            len(inp.subtitle_streams) == 0):
            text += 'Invalid media.\n'
        else:
            text += ' - container:\n'
            if(inp.duration is not None):
                text += '   - duration: {}\n'.format(inp.duration)
            if(inp.bitrate is not None):
                text += '   - bitrate: {}\n'.format(inp.bitrate)

            if(args.include_vfr):
                print(text, end='')
                text = ''
                fps_mode = ffmpeg.pipe(['-i', file, '-hide_banner', '-vf', 'vfrdet',
                    '-an', '-f', 'null', '-'])
                fps_mode = fps_mode.strip()

                if('VFR:' in fps_mode):
                    fps_mode = (fps_mode[fps_mode.index('VFR:'):]).strip()

                text += '  - {}\n'.format(fps_mode)

        print(text)

if(__name__ == '__main__'):
    main()
