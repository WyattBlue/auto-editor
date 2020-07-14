'''scripts/fastAudio.py'''

"""
This script is for handling audio files ONLY.
"""

# External libraries
import numpy as np
from audiotsm import phasevocoder

# Included functions
from scripts.readAudio import ArrReader, ArrWriter
from scripts.usefulFunctions import getAudioChunks, progressBar, getNewLength
from scripts.wavfile import read, write

# Internal libraries
import os
import sys
import time
import subprocess

def fastAudio(ffmpeg, theFile, outFile, silentT, frameMargin, SAMPLE_RATE, audioBit,
        verbose, silentSpeed, soundedSpeed, needConvert, chunks=[], fps=30):

    if(not os.path.isfile(theFile)):
        print('Could not find file:', theFile)
        sys.exit(1)

    if(outFile == ''):
        fileName = theFile[:theFile.rfind('.')]
        outFile = f'{fileName}_ALTERED.wav'

    if(needConvert):
        # Only print this here so other scripts can use this function.
        print('Running from fastAudio.py')

        import tempfile
        from shutil import rmtree

        TEMP = tempfile.mkdtemp()

        cmd = [ffmpeg, '-i', theFile, '-b:a', audioBit, '-ac', '2', '-ar',
            str(SAMPLE_RATE), '-vn', f'{TEMP}/fastAud.wav']
        if(not verbose):
            cmd.extend(['-nostats', '-loglevel', '0'])
        subprocess.call(cmd)

        theFile = f'{TEMP}/fastAud.wav'

    speeds = [silentSpeed, soundedSpeed]

    sampleRate, audioData = read(theFile)
    if(chunks == []):
        print('Creating chunks')
        chunks = getAudioChunks(audioData, sampleRate, fps, silentT, 2, frameMargin)

    # Get the estimated length of the new audio in frames.
    newL = getNewLength(chunks, speeds, fps)

    # Get the new length in samples with some extra leeway.
    estLeng = int((newL * sampleRate) * 1.5) + int(sampleRate * 2)

    # Create an empty array for the new audio.
    newAudio = np.zeros((estLeng, 2), dtype=np.int16)

    channels = 2
    yPointer = 0

    totalChunks = len(chunks)
    beginTime = time.time()

    newCuts = []

    for chunkNum, chunk in enumerate(chunks):
        audioSampleStart = int(chunk[0] / fps * sampleRate)
        audioSampleEnd = int(audioSampleStart + (sampleRate / fps) * (chunk[1] - chunk[0]))

        theSpeed = speeds[chunk[2]]

        if(theSpeed != 99999):
            spedChunk = audioData[audioSampleStart:audioSampleEnd]
            spedupAudio = np.zeros((0, 2), dtype=np.int16)
            with ArrReader(spedChunk, channels, sampleRate, 2) as reader:
                with ArrWriter(spedupAudio, channels, sampleRate, 2) as writer:
                    phasevocoder(reader.channels, speed=theSpeed).run(
                        reader, writer
                    )
                    spedupAudio = writer.output

            yPointerEnd = yPointer + spedupAudio.shape[0]
            newAudio[yPointer:yPointerEnd] = spedupAudio

            yPointer = yPointerEnd

            newEnd = chunk[0] + (spedupAudio.shape[0] /
                (sampleRate / fps))

            newCuts.append([chunk[0], int(newEnd), chunk[2]])
        else:
            # Speed is too high so skip this section.
            yPointerEnd = yPointer

        progressBar(chunkNum, totalChunks, beginTime, title='Creating new audio')

    if(verbose):
        print('yPointer', yPointer)
        print('samples per frame', sampleRate / fps)
        print('Expected video length', yPointer / (sampleRate / fps))
    newAudio = newAudio[:yPointer]
    write(outFile, sampleRate, newAudio)

    if('TEMP' in locals()):
        rmtree(TEMP)

    if(needConvert):
        return outFile
    else:
        return newCuts
