'''scripts/preview.py'''

"""
This script is only meant to output info about how the video will be cut if the
selected options are used.
"""

# External libraries
import cv2

# Included functions
from scripts.usefulFunctions import getAudioChunks, vidTracks, getNewLength
from scripts.wavfile import read, write

# Internal libraries
import os
import tempfile
import subprocess
from shutil import rmtree
from datetime import timedelta


def preview(myInput, silentT, zoomT, frameMargin, sampleRate, videoSpeed, silentSpeed,
        cutByThisTrack, bitrate):
    TEMP = tempfile.mkdtemp()

    cap = cv2.VideoCapture(myInput)
    fps = cap.get(cv2.CAP_PROP_FPS)

    tracks = vidTracks(myInput)

    if(cutByThisTrack >= tracks):
        print("Error: You choose a track that doesn't exist.")
        print(f'There are only {tracks-1} tracks. (starting from 0)')
        sys.exit(1)

    for trackNumber in range(tracks):
        cmd = ['ffmpeg', '-i', myInput, '-ab', bitrate, '-ac', '2', '-ar',
            str(sampleRate),'-map', f'0:a:{trackNumber}',  f'{TEMP}/{trackNumber}.wav',
            '-nostats', '-loglevel', '0']
        subprocess.call(cmd)

    sampleRate, audioData = read(f'{TEMP}/{cutByThisTrack}.wav')
    chunks = getAudioChunks(audioData, sampleRate, fps, silentT, 2, frameMargin)

    rmtree(TEMP)

    def printTimeFrame(title, frames, fps):
        inSec = round(frames / fps, 1)
        if(inSec < 1):
            minutes = f'{int(frames)}/{fps} frames'
        else:
            minutes = timedelta(seconds=round(inSec))
        print(f'{title}: {inSec} secs ({minutes})')


    oldTime = chunks[len(chunks)-1][1]
    printTimeFrame('Old length', oldTime, fps)

    speeds = [silentSpeed, videoSpeed]
    printTimeFrame('New length', getNewLength(chunks, speeds, fps), fps)

    clips = 0
    clipLengths = []
    for chunk in chunks:
        state = chunk[2]
        if(NEW_SPEED[state] != 99999):
            clips += 1
            leng = (chunk[1] - chunk[0]) / NEW_SPEED[state]
            clipLengths.append(leng)

    print('Number of clips:', clips)
    printTimeFrame('Smallest clip length', min(clipLengths), fps)
    printTimeFrame('Largest clip length', max(clipLengths), fps)
    printTimeFrame('Average clip length', sum(clipLengths) / len(clipLengths), fps)
