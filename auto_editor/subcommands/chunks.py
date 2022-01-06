'''subcommands/chunks.py'''

import sys
from auto_editor.utils.types import margin_type, frame_type, float_type

def chunks_options(parser):
    parser.add_argument('-fps', type=float_type, default=30)
    parser.add_argument('-mclip', type=frame_type, default=3)
    parser.add_argument('-mcut', type=frame_type, default=6)
    parser.add_argument('--margin', type=margin_type, default='6')
    parser.add_argument('--video_speed', type=float_type, default=1)
    parser.add_argument('--silent_speed', type=float_type, default=99999)

    parser.add_argument('-t', type=float_type, default=0.04)
    parser.add_argument('--help', '-h', action='store_true',
        help="Take level's data from stdin and output chunk data in stdout.")
    return parser

def main(sys_args=sys.argv[1:]):
    import os
    import json

    import auto_editor
    import auto_editor.vanparse as vanparse
    from auto_editor.utils.log import Log

    import numpy as np

    parser = vanparse.ArgumentParser('chunks', auto_editor.version)
    parser = chunks_options(parser)

    try:
        args = parser.parse_args(sys_args)
    except vanparse.ParserError as e:
        log.error(str(e))

    levels = []
    for line in sys.stdin:
        if(line.strip() != ''):
            levels.append(float(line) > args.t)
    has_loud = np.asarray(levels, dtype=np.bool_)

    from auto_editor.cutting import (chunkify, apply_margin, to_speed_list,
        seconds_to_frames, cook)

    start_margin, end_margin = args.margin

    start_margin = seconds_to_frames(start_margin, args.fps)
    end_margin = seconds_to_frames(end_margin, args.fps)
    min_clip = seconds_to_frames(args.mclip, args.fps)
    min_cut = seconds_to_frames(args.mcut, args.fps)

    has_loud_length = len(has_loud)
    has_loud = cook(has_loud, min_clip, min_cut)
    has_loud = apply_margin(has_loud, has_loud_length, start_margin, end_margin)
    has_loud = cook(has_loud, min_clip, min_cut)

    speed_list = to_speed_list(has_loud, args.video_speed, args.silent_speed)

    chunks = chunkify(speed_list, has_loud_length)

    json.dump({'chunks': chunks}, sys.stdout)

if(__name__ == '__main__'):
    main()
