'''levels.py'''

import numpy as np

import os
import math

from usefulFunctions import sep
from wavfile import read

def levels_options():
    from vanparse import add_argument
    ops = []
    ops += add_argument('--output_file', '--output', '-o', type=str,
        default='data.txt')
    ops += add_argument('--track', type=int, default=0,
        help='which audio track to target.')
    ops += add_argument('--my_ffmpeg', action='store_true',
        help='use your ffmpeg and other binaries instead of the ones packaged.')
    ops += add_argument('--help', '-h', action='store_true',
        help='print info about the program or an option and exit.')
    ops += add_argument('(input)', nargs='*',
        help='the template')
    return ops

def levels(inputs: list, track, outfile, ffmpeg, ffprobe, temp, log):

    file = inputs[0]

    tracks = ffprobe.getAudioTracks(file)
    fps = ffprobe.getFrameRate(file)

    # Split audio tracks into: 0.wav, 1.wav, etc.
    for trackNum in range(tracks):
        ffmpeg.run(['-i', file, '-ac', '2', '-map', f'0:a:{trackNum}',
            f'{temp}{sep()}{trackNum}.wav'])

    track = 0

    # Read only one audio file.
    if(os.path.isfile(f'{temp}{sep()}{track}.wav')):
        sampleRate, audioData = read(f'{temp}{sep()}{track}.wav')
    else:
        log.error('Audio track not found!')

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
            out.write(f'{getMaxVolume(audiochunks) / maxAudioVolume}\n')

    log.debug('Deleting temp dir')

    from shutil import rmtree
    try:
        rmtree(temp)
    except PermissionError:
        from time import sleep
        sleep(1)
        try:
            rmtree(temp)
        except PermissionError:
            log.debug('Failed to delete temp dir.')
