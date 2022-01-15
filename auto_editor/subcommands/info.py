'''subcommands/info.py'''

import sys
import json
import os.path

def info_options(parser):
    parser.add_argument('--json', action='store_true',
        help='Export the information in JSON format.')
    parser.add_argument('--include_vfr', '--has_vfr', action='store_true',
        help='Skip information that is very slow to get.')
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

    import auto_editor
    import auto_editor.vanparse as vanparse

    from auto_editor.utils.func import aspect_ratio
    from auto_editor.utils.log import Log

    from auto_editor.ffwrapper import FFmpeg

    parser = vanparse.ArgumentParser('info', auto_editor.version,
        description='Get basic information about media files.')
    parser = info_options(parser)

    log = Log()

    try:
        args = parser.parse_args(sys_args)
    except vanparse.ParserError as e:
        log.error(str(e))

    ffmpeg = FFmpeg(args.ffmpeg_location, args.my_ffmpeg, False)

    def aspect_str(w, h):
        w, h = aspect_ratio(int(w), int(h))
        if(w is None):
            return ''
        return ' ({}:{})'.format(w, h)

    file_info = {}

    for file in args.input:
        text = ''
        if(os.path.exists(file)):
            text += 'file: {}\n'.format(file)
        else:
            log.error('Could not find file: {}'.format(file))

        inp = ffmpeg.file_info(file)

        file_info[file] = {
            'video': [],
            'audio': [],
            'subtitle': [],
            'container': {},
        }

        if(len(inp.video_streams) > 0):
            text += f' - video tracks: {len(inp.video_streams)}\n'

        for track, stream in enumerate(inp.video_streams):
            text += '   - Track #{}\n'.format(track)

            text += '     - codec: {}\n'.format(stream['codec'])

            vid = {}
            vid['codec'] = stream['codec']

            import av
            container = av.open(file, 'r')
            pix_fmt = container.streams.video[track].pix_fmt
            time_base = container.streams.video[track].time_base

            text += f'     - pix_fmt: {pix_fmt}\n'
            text += f'     - time_base: {time_base}\n'

            vid['pix_fmt'] = pix_fmt
            vid['time_base'] = time_base


            if(stream['fps'] is not None):
                text += '     - fps: {}\n'.format(stream['fps'])
                vid['fps'] = float(stream['fps'])

            w = stream['width']
            h = stream['height']

            if(w is not None and h is not None):
                text += '     - resolution: {}x{}{}\n'.format(w, h, aspect_str(w, h))

                vid['width'] = int(w)
                vid['height'] = int(h)
                vid['aspect_ratio'] = aspect_ratio(int(w), int(h))

            if(stream['bitrate'] is not None):
                text += '     - bitrate: {}\n'.format(stream['bitrate'])
                vid['bitrate'] = stream['bitrate']
            if(stream['lang'] is not None):
                text += '     - lang: {}\n'.format(stream['lang'])
                vid['lang'] = stream['lang']

            file_info[file]['video'].append(vid)


        if(len(inp.audio_streams) > 0):
            text += f' - audio tracks: {len(inp.audio_streams)}\n'

        for track, stream in enumerate(inp.audio_streams):
            aud = {}

            text += '   - Track #{}\n'.format(track)
            text += '     - codec: {}\n'.format(stream['codec'])
            text += '     - samplerate: {}\n'.format(stream['samplerate'])

            aud['codec'] = stream['codec']
            aud['samplerate'] = int(stream['samplerate'])

            if(stream['bitrate'] is not None):
                text += '     - bitrate: {}\n'.format(stream['bitrate'])
                aud['bitrate'] = stream['bitrate']

            if(stream['lang'] is not None):
                text += '     - lang: {}\n'.format(stream['lang'])
                aud['lang'] = stream['lang']

            file_info[file]['audio'].append(aud)

        if(len(inp.subtitle_streams) > 0):
            text += f' - subtitle tracks: {len(inp.subtitle_streams)}\n'

        for track, stream in enumerate(inp.subtitle_streams):
            sub = {}

            text += '   - Track #{}\n'.format(track)
            text += '     - codec: {}\n'.format(stream['codec'])
            sub['codec'] = stream['codec']
            if(stream['lang'] is not None):
                text += '     - lang: {}\n'.format(stream['lang'])
                sub['lang'] = stream['lang']

            file_info[file]['subtitle'].append(sub)

        if(len(inp.video_streams) == 0 and len(inp.audio_streams) == 0 and
            len(inp.subtitle_streams) == 0):
            text += 'Invalid media.\n'
            file_info[file] = {'media': 'invalid'}
        else:
            text += ' - container:\n'

            cont = file_info[file]['container']

            if(inp.duration is not None):
                text += '   - duration: {}\n'.format(inp.duration)
                cont['duration'] = inp.duration
            if(inp.bitrate is not None):
                text += '   - bitrate: {}\n'.format(inp.bitrate)
                cont['bitrate'] = inp.bitrate

            if(args.include_vfr):
                if(not args.json):
                    print(text, end='')
                text = ''
                fps_mode = ffmpeg.pipe(['-i', file, '-hide_banner', '-vf', 'vfrdet',
                    '-an', '-f', 'null', '-'])
                fps_mode = fps_mode.strip()

                if('VFR:' in fps_mode):
                    fps_mode = (fps_mode[fps_mode.index('VFR:'):]).strip()

                text += '   - {}\n'.format(fps_mode)
                cont['fps_mode'] = fps_mode

        if(not args.json):
            print(text)

    if(args.json):
        json_object = json.dumps(file_info, indent=4)
        print(json_object)

if(__name__ == '__main__'):
    main()
