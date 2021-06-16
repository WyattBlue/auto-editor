'''subcommands/info.py'''

from __future__ import print_function

def info_options(parser):
    parser.add_argument('--include_vfr', action='store_true',
        help='skip information that is very slow to get.')
    parser.add_argument('--my_ffmpeg', action='store_true',
        help='use your ffmpeg and other binaries instead of the ones packaged.')
    parser.add_argument('--help', '-h', action='store_true',
        help='print info about the program or an option and exit.')
    parser.add_argument('(input)', nargs='*',
        help='the path to a file you want inspected.')
    return parser

def info(sys_args=None):
    import os
    import sys

    import auto_editor
    import auto_editor.vanparse as vanparse

    from auto_editor.utils.func import clean_list, aspect_ratio
    from auto_editor.utils.log import Log

    from auto_editor.ffwrapper import FFmpeg

    dir_path = os.path.dirname(os.path.dirname(os.path.realpath(__file__)))

    parser = vanparse.ArgumentParser('info', auto_editor.version,
        description='Get basic information about media files.')
    parser = info_options(parser)

    if(sys_args is None):
        sys_args = sys.args[1:]

    log = Log()
    args = parser.parse_args(sys_args, log, 'info')

    ffmpeg = FFmpeg(dir_path, args.my_ffmpeg, False, log)

    def aspect_str(w, h):
        w, h = aspect_ratio(int(w), int(h))
        if(w is None):
            return ''
        return '{}:{}'.format(w, h)

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

            text += ' - resolution: {}x{} ({})\n'.format(w, h, aspect_str(w, h))
            text += ' - video codec: {}\n'.format(inp.video_streams[0]['codec'])
            text += ' - video bitrate: {}\n'.format(inp.video_streams[0]['bitrate'])

            tracks = len(inp.audio_streams)
            text += ' - audio tracks: {}\n'.format(tracks)

            for track in range(tracks):
                text += '   - Track #{}\n'.format(track)
                text += '     - codec: {}\n'.format(inp.audio_streams[track]['codec'])
                text += '     - samplerate: {}\n'.format(
                    inp.audio_streams[track]['samplerate'])
                text += '     - bitrate: {}\n'.format(inp.audio_streams[track]['bitrate'])

            sub_tracks = len(inp.subtitle_streams)
            if(sub_tracks > 0):
                text += ' - subtitle tracks: {}\n'.format(sub_tracks)
                for track in range(tracks):
                    text += '   - Track #{}\n'.format(track)
                    text += '     - lang: {}\n'.format(inp.subtitle_streams[track]['lang'])

            if(args.include_vfr):
                print(text, end='')
                text = ''
                fps_mode = ffmpeg.pipe(['-i', file, '-hide_banner', '-vf', 'vfrdet',
                    '-an', '-f', 'null', '-'])
                fps_mode = clean_list(fps_mode.split('\n'), '\r\t')
                fps_mode = fps_mode.pop()

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
    info()
