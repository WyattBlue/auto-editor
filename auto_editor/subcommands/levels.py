import sys

def levels_options(parser):
    parser.add_argument('--kind', type=str, default='audio')
    parser.add_argument('--track', type=int, default=0,
        help='Select the track to get. If `--kind` is set to motion, track will look '
            'at video tracks instead of audio.')
    parser.add_argument('--ffmpeg-location', default=None,
        help='Point to your custom ffmpeg file.')
    parser.add_argument('--my-ffmpeg', action='store_true',
        help='Use the ffmpeg on your PATH instead of the one packaged.')
    parser.add_argument('--help', '-h', action='store_true',
        help='Print info about the program or an option and exit.')
    parser.add_required('input', nargs='*',
        help='Path to the file to have its levels dumped.')
    return parser

def main(sys_args=sys.argv[1:]):
    import os
    import tempfile

    import auto_editor
    import auto_editor.vanparse as vanparse

    from auto_editor.utils.log import Log
    from auto_editor.ffwrapper import FFmpeg, FileInfo

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

    inp = FileInfo(args.input[0], ffmpeg)
    fps = 30 if inp.fps is None else float(inp.fps)

    if args.kind == 'audio':
        from auto_editor.analyze.audio import display_audio_levels

        if args.track >= len(inp.audio_streams):
            log.error(f"Audio track '{args.track}' does not exist.")

        read_track = os.path.join(temp, '{}.wav'.format(args.track))

        ffmpeg.run(['-i', inp.path, '-ac', '2', '-map', f'0:a:{args.track}', read_track])

        if not os.path.isfile(read_track):
            log.error('Audio track file not found!')

        display_audio_levels(read_track, fps)

    if args.kind == 'motion':
        if args.track >= len(inp.video_streams):
            log.error(f"Video track '{args.track}' does not exist.")

        from auto_editor.analyze.motion import display_motion_levels

        display_motion_levels(inp.path, width=400, blur=9)

    log.cleanup()

if __name__ == '__main__':
    main()
