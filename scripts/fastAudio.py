'''scripts/fastAudio.py'''

"""
This script is for handling audio files ONLY.
"""

# External libraries
import numpy as np
from audiotsm import phasevocoder

# Included functions
from scripts.readAudio import ArrReader, ArrWriter
from scripts.usefulFunctions import getAudioChunks, progressBar
from scripts.wavfile import read, write

# Internal libraries
import os
import sys
import subprocess

def preview(chunks, NEW_SPEED, fps):
    timeInFrames = 0
    for chunk in chunks:
        leng = chunk[1] - chunk[0]
        if(NEW_SPEED[chunk[2]] < 99999):
            timeInFrames += leng * (1 / NEW_SPEED[chunk[2]])
    return timeInFrames / fps


def fastAudio(theFile, outFile, silentT, frameMargin, SAMPLE_RATE, audioBit, verbose,
    silentSpeed, soundedSpeed, needConvert):

    if(not os.path.isfile(theFile)):
        print('Could not find file:', theFile)
        sys.exit()

    if(outFile == ''):
        fileName = theFile[:theFile.rfind('.')]
        outFile = f'{fileName}_ALTERED.wav'

    if(needConvert):
        # Only print this here so other programs can use this function.
        print('Running from fastAudio.py')

        import tempfile
        from shutil import rmtree

        TEMP = tempfile.mkdtemp()

        cmd = ['ffmpeg', '-i', theFile, '-b:a', audioBit, '-ac', '2', '-ar',
            str(SAMPLE_RATE), '-vn', f'{TEMP}/fastAud.wav']
        if(not verbose):
            cmd.extend(['-nostats', '-loglevel', '0'])
        subprocess.call(cmd)

        theFile = f'{TEMP}/fastAud.wav'

    NEW_SPEED = [silentSpeed, soundedSpeed]

    sampleRate, audioData = read(theFile)
    chunks = getAudioChunks(audioData, sampleRate, 30, silentT, 2, frameMargin)

    # Get the estimated length of the new audio in frames.
    hmm = preview(chunks, NEW_SPEED, 30)

    # Get the new length in samples with some extra leeway.
    estLeng = int((hmm * sampleRate) * 1.5) + int(sampleRate * 2)

    # Create an empty array for the new audio.
    newAudio = np.zeros((estLeng, 2), dtype=np.int16)

    channels = 2
    yPointer = 0

    # samples per frame
    spf = int(sampleRate / 30)

    for chunk in chunks:
        audioSampleStart = int(chunk[0] / 30 * sampleRate)
        audioSampleEnd = audioSampleStart + spf * (chunk[1] - chunk[0])

        theSpeed = NEW_SPEED[chunk[2]]

        print(yPointer)

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
        else:
            # Speed is too high so skip this section.
            yPointerEnd = yPointer

    newAudio = newAudio[:yPointer]
    write(outFile, sampleRate, newAudio)

    if('TEMP' in locals()):
        rmtree(TEMP)
    return outFile

