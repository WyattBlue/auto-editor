'''subcommands/levels.py'''

import numpy as np

import os
import math

from auto_editor.wavfile import read

def levels_options(parser):
    parser.add_argument('--output_file', '--output', '-o', type=str,
        default='data.txt')
    parser.add_argument('--track', type=int, default=0,
        help='which audio track to target.')
    parser.add_argument('--my_ffmpeg', action='store_true',
        help='use your ffmpeg and other binaries instead of the ones packaged.')
    parser.add_argument('(input)', nargs='*',
        help='the template')
    return parser

def levels(inputs: list, track, outfile, ffmpeg, ffprobe, temp, log):

    file = inputs[0]

    tracks = ffprobe.getAudioTracks(file)
    fps = ffprobe.getFrameRate(file)

    # Split audio tracks into: 0.wav, 1.wav, etc.
    for t in range(tracks):
        ffmpeg.run(['-i', file, '-ac', '2', '-map', '0:a:{}'.format(t),
            os.path.join(temp, '{}.wav'.format(t))])

    sampleRate, audioData = read(os.path.join(temp, '0.wav'))
    audioSampleCount = audioData.shape[0]

    def getMaxVolume(s: np.ndarray) -> float:
        maxv = float(np.max(s))
        minv = float(np.min(s))
        return max(maxv, -minv)

    maxAudioVolume = getMaxVolume(audioData)

    samplesPerFrame = sampleRate / fps
    audioFrameCount = int(math.ceil(audioSampleCount / samplesPerFrame))

    with open(outfile, 'w') as out:
        for i in range(audioFrameCount):
            start = int(i * samplesPerFrame)
            end = min(int((i+1) * samplesPerFrame), audioSampleCount)
            audiochunks = audioData[start:end]
            out.write('{}\n'.format(getMaxVolume(audiochunks) / maxAudioVolume))

    log.cleanup()
