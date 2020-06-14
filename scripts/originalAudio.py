'''scripts/originalAudio.py'''

import numpy as np
from audiotsm import phasevocoder
from audiotsm.io.wav import WavReader, WavWriter
from scipy.io import wavfile

import os
import subprocess

TEMP = '.TEMP'
CACHE = '.CACHE'
FADE_SIZE = 400

def splitAudio(filename, chunks, samplesPerFrame, NEW_SPEED, audioData, SAMPLE_RATE,
    maxAudioVolume):

    outputAudioData = []
    outputPointer = 0
    mask = [x / FADE_SIZE for x in range(FADE_SIZE)]
    num = 0
    chunk_len = str(len(chunks))
    for chunk in chunks:
        if(NEW_SPEED[int(chunk[2])] < 99999):
            start = int(chunk[0] * samplesPerFrame)
            end = int(chunk[1] * samplesPerFrame)
            audioChunk = audioData[start:end]

            sFile = ''.join([TEMP, '/tempStart.wav'])
            eFile = ''.join([TEMP, '/tempEnd.wav'])
            wavfile.write(sFile, SAMPLE_RATE, audioChunk)
            if(NEW_SPEED[int(chunk[2])] == 1):
                __, samefile = wavfile.read(sFile)
                leng = len(audioChunk)

                outputAudioData.extend((samefile / maxAudioVolume).tolist())
            else:
                with WavReader(sFile) as reader:
                    with WavWriter(eFile, reader.channels, reader.samplerate) as writer:
                        phasevocoder(reader.channels, speed=NEW_SPEED[int(chunk[2])]).run(reader, writer)
                __, alteredAudioData = wavfile.read(eFile)
                leng = alteredAudioData.shape[0]

                outputAudioData.extend((alteredAudioData / maxAudioVolume).tolist())

            endPointer = outputPointer + leng

            # smooth out transition's audio by quickly fading in/out
            if(leng < FADE_SIZE):
                for i in range(outputPointer, endPointer):
                    outputAudioData[i][0] = 0
                    outputAudioData[i][1] = 0
            else:
                for i in range(outputPointer, outputPointer+FADE_SIZE):
                    outputAudioData[i][0] *= mask[i-outputPointer]
                    outputAudioData[i][1] *= mask[i-outputPointer]
                for i in range(endPointer-FADE_SIZE, endPointer):
                    outputAudioData[i][0] *= (1-mask[i-endPointer+FADE_SIZE])
                    outputAudioData[i][1] *= (1-mask[i-endPointer+FADE_SIZE])

            outputPointer = endPointer

        num += 1
        if(num % 10 == 0):
            print(''.join([str(num), '/', chunk_len, ' audio chunks done.']))

    print(''.join([str(num), '/', chunk_len, ' audio chunks done.']))
    outputAudioData = np.asarray(outputAudioData)
    wavfile.write(filename, SAMPLE_RATE, outputAudioData)

    if(not os.path.isfile(filename)):
        raise IOError(f'Error: The file {filename} was not created.')
    else:
        print('Audio finished.')


def handleAudio(tracks, chunks, samplesPerFrame, NEW_SPEED, maxAudioVolume):
    print('Creating new audio.')
    for i in range(tracks):
        sampleRate, audioData = wavfile.read(f'{CACHE}/{i}.wav')
        splitAudio(f'{TEMP}/new{i}.wav', chunks, samplesPerFrame, NEW_SPEED,
            audioData, sampleRate, maxAudioVolume)

    if(tracks != 1):
        print('All audio tracks finished.')
