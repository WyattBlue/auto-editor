'''fastAudio.py'''

"""
This script is for handling audio files ONLY.
"""

# External libraries
import numpy as np
from audiotsm2 import phasevocoder
from audiotsm2.io.array import ArrReader, ArrWriter

# Included functions
from usefulFunctions import getAudioChunks, progressBar, getNewLength
from wavfile import read, write

# Internal libraries
import os
import sys
import time
import tempfile
import subprocess

def fastAudio(ffmpeg, theFile, outFile, chunks, speeds, audioBit, samplerate, debug,
    needConvert, fps=30):

    if(not os.path.isfile(theFile)):
        print('fastAudio.py: Could not find file', theFile)
        sys.exit(1)

    if(needConvert):
        # Only print this here so other scripts can use this function.
        print('Running from fastAudio.py')

        import tempfile
        from shutil import rmtree

        TEMP = tempfile.mkdtemp()

        cmd = [ffmpeg, '-i', theFile, '-b:a', audioBit, '-ac', '2', '-ar',
            str(samplerate), '-vn', f'{TEMP}/fastAud.wav']
        if(not debug):
            cmd.extend(['-nostats', '-loglevel', '0'])
        subprocess.call(cmd)

        theFile = f'{TEMP}/fastAud.wav'

    samplerate, audioData = read(theFile)

    newL = getNewLength(chunks, speeds, fps)
    # Get the new length in samples with some extra leeway.
    estLeng = int(newL * samplerate * 1.5) + int(samplerate * 2)

    # Create an empty array for the new audio.
    newAudio = np.zeros((estLeng, 2), dtype=np.int16)

    channels = 2
    yPointer = 0
    totalChunks = len(chunks)
    beginTime = time.time()

    for chunkNum, chunk in enumerate(chunks):
        audioSampleStart = int(chunk[0] / fps * samplerate)
        audioSampleEnd = int(audioSampleStart + (samplerate / fps) * (chunk[1] - chunk[0]))

        theSpeed = speeds[chunk[2]]
        if(theSpeed != 99999):
            spedChunk = audioData[audioSampleStart:audioSampleEnd]

            if(theSpeed == 1):
                yPointerEnd = yPointer + spedChunk.shape[0]
                newAudio[yPointer:yPointerEnd] = spedChunk
            else:
                spedupAudio = np.zeros((0, 2), dtype=np.int16)
                with ArrReader(spedChunk, channels, samplerate, 2) as reader:
                    with ArrWriter(spedupAudio, channels, samplerate, 2) as writer:
                        phasevocoder(reader.channels, speed=theSpeed).run(
                            reader, writer
                        )
                        spedupAudio = writer.output

                yPointerEnd = yPointer + spedupAudio.shape[0]
                newAudio[yPointer:yPointerEnd] = spedupAudio

            myL = chunk[1] - chunk[0]
            mySamples = (myL / fps) * samplerate
            newSamples = int(mySamples / theSpeed)

            yPointer = yPointer + newSamples
        else:
            # Speed is too high so skip this section.
            yPointerEnd = yPointer

        progressBar(chunkNum, totalChunks, beginTime, title='Creating new audio')

    if(debug):
        print('yPointer', yPointer)
        print('samples per frame', samplerate / fps)
        print('Expected video length', yPointer / (samplerate / fps))
    newAudio = newAudio[:yPointer]
    write(outFile, samplerate, newAudio)

    if('TEMP' in locals()):
        rmtree(TEMP)
