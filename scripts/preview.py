'''scripts/preview.py'''

"""
This script is only meant to output info about how the video will be cut if the
selected options are used.
"""

# External libraries
import cv2
from scipy.io import wavfile

# Included functions
from scripts.usefulFunctions import getAudioChunks

# Internal libraries
import os
import subprocess
from shutil import rmtree
from datetime import timedelta


def preview(myInput, silentT, zoomT, frameMargin, sampleRate, videoSpeed, silentSpeed):

    TEMP = '.TEMP'

    cap = cv2.VideoCapture(myInput)
    fps = round(cap.get(cv2.CAP_PROP_FPS))

    try:
        os.mkdir(TEMP)
    except OSError:
        rmtree(TEMP)
        os.mkdir(TEMP)

    cmd = ['ffmpeg', '-i', myInput, '-ab', '160k', '-ac', '2', '-ar',
        str(sampleRate), '-vn', f'{TEMP}/output.wav', '-nostats', '-loglevel', '0']

    subprocess.call(cmd)

    sampleRate, audioData = wavfile.read(f'{TEMP}/output.wav')

    chunks = getAudioChunks(audioData, sampleRate, fps, silentT, zoomT, frameMargin)


    def printTimeFrame(title, frames, fps):
        inSec = round(frames / fps, 1)
        if(inSec < 1):
            minutes = f'{int(frames)}/{fps} frames'
        else:
            minutes = timedelta(seconds=round(inSec))
        print(f'{title}: {inSec} secs ({minutes})')


    oldTime = chunks[len(chunks)-1][1]
    printTimeFrame('Old length', oldTime, fps)

    NEW_SPEED = [silentSpeed, videoSpeed]
    frameLen = 0
    for chunk in chunks:
        leng = chunk[1] - chunk[0]
        if(NEW_SPEED[chunk[2]] < 99999):
            frameLen += leng * (1 / NEW_SPEED[chunk[2]])


    printTimeFrame('New length', frameLen, fps)

    cuts = 0
    cutLengths = []
    for chunk in chunks:
        state = chunk[2]
        if(NEW_SPEED[state] != 99999):
            cuts += 1
            leng = (chunk[1] - chunk[0]) / NEW_SPEED[state]
            cutLengths.append(leng)

    print('Number of cuts:', cuts)
    printTimeFrame('Smallest clip length', min(cutLengths), fps)
    printTimeFrame('Largest clip length', max(cutLengths), fps)
    printTimeFrame('Average clip length', sum(cutLengths) / len(cutLengths), fps)
    print(chunks)

