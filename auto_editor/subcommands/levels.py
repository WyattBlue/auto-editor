'''subcommands/levels.py'''

from __future__ import print_function

def levels_options(parser):
    parser.add_argument('--output_file', '--output', '-o', type=str,
        default='data.txt')
    parser.add_argument('--my_ffmpeg', action='store_true',
        help='use your ffmpeg and other binaries instead of the ones packaged.')
    parser.add_argument('--help', '-h', action='store_true',
        help='print info about the program or an option and exit.')
    parser.add_argument('(input)', nargs='*',
        help='the template')
    return parser

def levels(sys_args=None):
    import os
    import sys
    import math
    import tempfile

    import numpy as np

    import auto_editor
    import auto_editor.vanparse as vanparse

    from auto_editor.utils.log import Log
    from auto_editor.ffwrapper import FFmpeg
    from auto_editor.scipy.wavfile import read

    dir_path = os.path.dirname(os.path.dirname(os.path.realpath(__file__)))

    parser = vanparse.ArgumentParser('levels', auto_editor.version,
        description='Get loudness of audio over time.')
    parser = levels_options(parser)

    if(sys_args is None):
        sys_args = sys.args[1:]

    temp = tempfile.mkdtemp()
    log = Log(temp=temp)

    args = parser.parse_args(sys_args, log, 'levels')

    ffmpeg = FFmpeg(dir_path, args.my_ffmpeg, False, log)
    inp = ffmpeg.file_info(args.input[0])

    fps = 30 if inp.fps is None else float(inp.fps)

    # Split audio tracks into: 0.wav, 1.wav, etc.
    for t in range(len(inp.audio_streams)):
        ffmpeg.run(['-i', inp.path, '-ac', '2', '-map', '0:a:{}'.format(t),
            os.path.join(temp, '{}.wav'.format(t))])

    sample_rate, audio_data = read(os.path.join(temp, '0.wav'))
    audio_sample_count = audio_data.shape[0]

    def get_max_volume(s):
        return max(float(np.max(s)), -float(np.min(s)))

    max_volume = get_max_volume(audio_data)

    samples_per_frame = sample_rate / fps
    audio_frame_count = math.ceil(audio_sample_count / samples_per_frame)

    with open(args.output_file, 'w') as out:
        for i in range(audio_frame_count):
            start = int(i * samples_per_frame)
            end = min(int((i+1) * samples_per_frame), audio_sample_count)
            audiochunks = audio_data[start:end]
            out.write('{}\n'.format(get_max_volume(audiochunks) / max_volume))

    log.cleanup()

if(__name__ == '__main__'):
    levels()
