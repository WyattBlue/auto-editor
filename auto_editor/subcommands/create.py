'''subcommands/create.py'''

import os
import sys
import time

def create_options(parser):
    parser.add_argument('--frame_rate', '-fps', '-r', type=float, default=30.0,
        help='set the framerate for the output video.')
    parser.add_argument('--duration', '-d', type=int, default=10,
        help='set the length of the video (in seconds).')
    parser.add_argument('--width', type=int, default=1280,
        help='set the pixel width of the video.')
    parser.add_argument('--height', type=int, default=720,
        help='set the pixel height of the video.')
    parser.add_argument('--output_file', '--output', '-o', type=str,
        default='testsrc.mp4')
    parser.add_argument('--ffmpeg_location', default=None,
        help='point to your custom ffmpeg file.')
    parser.add_argument('--my_ffmpeg', action='store_true',
        help='use the ffmpeg on your PATH instead of the one packaged.')
    parser.add_argument('--help', '-h', action='store_true',
        help='print info about the program or an option and exit.')
    parser.add_argument('input', nargs='*',
        help='the template')
    return parser

def main(sys_args=sys.argv[1:]):
    import auto_editor
    import auto_editor.vanparse as vanparse

    from auto_editor.utils.log import Log
    from auto_editor.ffwrapper import FFmpeg

    parser = vanparse.ArgumentParser('create', auto_editor.version,
        description='Generate simple media.')
    parser = create_options(parser)

    log = Log()
    try:
        args = parser.parse_args(sys_args)
    except vanparse.ParserError as e:
        log.error(str(e))

    ffmpeg = FFmpeg(args.ffmpeg_location, args.my_ffmpeg, debug=False)

    theme = args.input
    output = args.output_file
    fps = args.frame_rate

    if(len(theme) == 0):
        log.error('You must put a theme!')
    if(len(theme) > 1):
        log.error('Only one theme at a time.')
    theme = theme[0]

    try:
        os.remove(output)
    except FileNotFoundError:
        pass

    if(theme == 'test'):
        # Create sine wav.
        ffmpeg.run(['-f', 'lavfi', '-i', 'sine=frequency=1000:duration=0.2', 'short.wav'])
        ffmpeg.run(['-i', 'short.wav', '-af', 'apad', '-t', '1', 'beep.wav']) # Pad audio.

        # Generate video with no audio.
        ffmpeg.run(['-f', 'lavfi', '-i', 'testsrc=duration={}:size={}x{}:rate={}'.format(
            args.duration, args.width, args.height, fps), '-pix_fmt', 'yuv420p', output])

        # Add empty audio channel to video.
        ffmpeg.run(['-f', 'lavfi', '-i', 'anullsrc=channel_layout=stereo:sample_rate=44100',
            '-i', output, '-c:v', 'copy', '-c:a', 'aac', '-shortest', 'pre' + output])

        # Mux Video with repeating audio.
        ffmpeg.run(['-i', 'pre' + output, '-filter_complex',
            'amovie=beep.wav:loop=0,asetpts=N/SR/TB[aud];[0:a][aud]amix[a]',
            '-map', '0:v', '-map', '[a]', '-c:v', 'copy', '-c:a', 'aac', '-b:a', '256k',
            '-shortest', output])

        time.sleep(1)
        os.remove('short.wav')
        os.remove('beep.wav')
        os.remove('pre' + output)

    if(theme in ['white', 'black']):
        ffmpeg.run(['-f', 'lavfi', '-i', 'color=size={}x{}:rate={}:color={}'.format(
            args.width, args.height, fps, theme), '-t', str(args.duration), output])

if(__name__ == '__main__'):
    main()
