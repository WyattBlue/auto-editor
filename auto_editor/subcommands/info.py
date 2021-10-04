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
            text += ' - fps: {}\n'.format(inp.fps)
            text += ' - duration: {}\n'.format(inp.duration)

            w = inp.video_streams[0]['width']
            h = inp.video_streams[0]['height']

            if(w is not None and h is not None):
                text += ' - resolution: {}x{}{}\n'.format(w, h, aspect_str(w, h))

            text += ' - video codec: {}\n'.format(inp.video_streams[0]['codec'])
            text += ' - video bitrate: {}\n'.format(inp.video_streams[0]['bitrate'])

            audio_tracks = len(inp.audio_streams)
            text += ' - audio tracks: {}\n'.format(audio_tracks)

            for track in range(audio_tracks):
                text += '   - Track #{}\n'.format(track)
                text += '     - codec: {}\n'.format(inp.audio_streams[track]['codec'])
                text += '     - samplerate: {}\n'.format(
                    inp.audio_streams[track]['samplerate'])
                text += '     - bitrate: {}\n'.format(inp.audio_streams[track]['bitrate'])
                text += '     - lang: {}\n'.format(inp.audio_streams[track]['lang'])

            sub_tracks = len(inp.subtitle_streams)
            if(sub_tracks > 0):
                text += ' - subtitle tracks: {}\n'.format(sub_tracks)
                for track in range(sub_tracks):
                    text += '   - Track #{}\n'.format(track)
                    text += '     - codec: {}\n'.format(inp.subtitle_streams[track]['codec'])
                    text += '     - lang: {}\n'.format(inp.subtitle_streams[track]['lang'])

            if(args.include_vfr):
                print(text, end='')
                text = ''
                fps_mode = ffmpeg.pipe(['-i', file, '-hide_banner', '-vf', 'vfrdet',
                    '-an', '-f', 'null', '-'])
                fps_mode = fps_mode.strip()

                if('VFR:' in fps_mode):
                    fps_mode = (fps_mode[fps_mode.index('VFR:'):]).strip()

                text += ' - {}\n'.format(fps_mode)

        elif(len(inp.audio_streams) > 0):
            text += ' - duration: {}\n'.format(inp.duration)
            text += ' - codec: {}\n'.format(inp.audio_streams[0]['codec'])
            text += ' - samplerate: {}\n'.format(inp.audio_streams[0]['samplerate'])
            text += ' - bitrate: {}\n'.format(inp.audio_streams[0]['bitrate'])
        else:
            text += 'Invalid media.\n'
        print(text)

if(__name__ == '__main__'):
    main()
