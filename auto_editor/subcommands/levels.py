'''subcommands/levels.py'''

import sys

def levels_options(parser):
    parser.add_argument('--kind', type=str, default='audio')
    parser.add_argument('--track', type=int, default=0,
        help='what audio/video track to get. If --kind is set to motion, track will look at video streams.')
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
    import os
    import tempfile

    import auto_editor
    import auto_editor.vanparse as vanparse

    from auto_editor.utils.log import Log
    from auto_editor.ffwrapper import FFmpeg

    parser = vanparse.ArgumentParser('levels', auto_editor.version,
        description='Get loudness of audio over time.')
    parser = levels_options(parser)

    temp = tempfile.mkdtemp()
    log = Log(temp=temp)

    try:
        args = parser.parse_args(sys_args)
    except vanparse.ParserError as e:
        log.error(str(e))

    ffmpeg = FFmpeg(args.ffmpeg_location, args.my_ffmpeg, False)

    inp = ffmpeg.file_info(args.input[0])
    fps = 30 if inp.fps is None else float(inp.fps)

    if(args.kind == 'audio'):
        from auto_editor.analyze.audio import display_audio_levels

        if(args.track >= len(inp.audio_streams)):
            log.error("Audio track '{}' does not exist.".format(args.track))

        read_track = os.path.join(temp, '{}.wav'.format(args.track))

        ffmpeg.run(['-i', inp.path, '-ac', '2', '-map', '0:a:{}'.format(args.track),
            read_track])

        if(not os.path.isfile(read_track)):
            log.error('Audio track file not found!')

        display_audio_levels(read_track, fps)

    if(args.kind == 'motion'):
        if(args.track >= len(inp.video_streams)):
            log.error("Video track '{}' does not exist.".format(args.track))

        from auto_editor.analyze.motion import display_motion_levels

        display_motion_levels(inp, width=400, dilates=2, blur=21)

    log.cleanup()

if(__name__ == '__main__'):
    main()
