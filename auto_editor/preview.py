'''preview.py'''

"""
This script is only meant to output info about how the video will be cut if the
selected options are used.
"""

# Included functions
from usefulFunctions import getAudioChunks, vidTracks, getNewLength, isAudioFile, checkCache, createCache
from wavfile import read, write

# Internal libraries
import os
import tempfile
import subprocess
from shutil import rmtree
from datetime import timedelta

def preview(ffmpeg, myInput, silentT, zoomT, frameMargin, sampleRate, videoSpeed,
        silentSpeed, cutByThisTrack, bitrate, cache):

    if(not os.path.isfile(myInput)):
        print('Could not find file:', myInput)
        sys.exit(1)

    audioFile = isAudioFile(myInput)
    if(audioFile):
        fps = 30
        tracks = 0
        TEMP = tempfile.mkdtemp()

        cmd = [ffmpeg, '-i', myInput, '-b:a', bitrate, '-ac', '2', '-ar',
            str(sampleRate), '-vn', f'{TEMP}/fastAud.wav', '-nostats', '-loglevel', '0']
        subprocess.call(cmd)

        sampleRate, audioData = read(f'{TEMP}/fastAud.wav')
        chunks = getAudioChunks(audioData, sampleRate, fps, silentT, 2, frameMargin)

        rmtree(TEMP)
    else:
        import cv2

        cap = cv2.VideoCapture(myInput)
        fps = cap.get(cv2.CAP_PROP_FPS)
        cap.release()
        cv2.destroyAllWindows()

        useCache, tracks = checkCache(cache, myInput, fps)

        if(not useCache):
            tracks = vidTracks(myInput, ffmpeg)

        if(cutByThisTrack >= tracks):
            print("Error! You choose a track that doesn't exist.")
            print(f'There are only {tracks-1} tracks. (starting from 0)')
            sys.exit(1)

        if(useCache and os.path.isfile(f'{cache}/{cutByThisTrack}.wav')):
            sampleRate, audioData = read(f'{cache}/{cutByThisTrack}.wav')
        else:
            for trackNum in range(tracks):
                cmd = [ffmpeg, '-i', myInput, '-ab', bitrate, '-ac', '2', '-ar',
                    str(sampleRate), '-map', f'0:a:{trackNum}',
                    f'{cache}/{trackNum}.wav', '-nostats', '-loglevel', '0']
                subprocess.call(cmd)
                sampleRate, audioData = read(f'{cache}/{cutByThisTrack}.wav')
        chunks = getAudioChunks(audioData, sampleRate, fps, silentT, 2, frameMargin)

    def printTimeFrame(title, frames, fps):
        inSec = round(frames / fps, 1)
        fps = round(fps)
        if(inSec < 1):
            minutes = f'{int(frames)}/{fps} frames'
        else:
            minutes = timedelta(seconds=round(inSec))
        print(f'{title}: {inSec} secs ({minutes})')


    oldTime = chunks[len(chunks)-1][1]
    print('')
    printTimeFrame('Old length', oldTime, fps)

    speeds = [silentSpeed, videoSpeed]
    newL = getNewLength(chunks, speeds, fps)
    printTimeFrame('New length', newL * fps, fps)
    print('')

    clips = 0
    cuts = 0
    cutL = []
    clipLengths = []
    for chunk in chunks:
        state = chunk[2]
        if(speeds[state] != 99999):
            clips += 1
            leng = (chunk[1] - chunk[0]) / speeds[state]
            clipLengths.append(leng)
        else:
            cuts += 1
            leng = chunk[1] - chunk[0]
            cutL.append(leng)

    print('Number of clips:', clips)
    printTimeFrame('Smallest clip length', min(clipLengths), fps)
    printTimeFrame('Largest clip length', max(clipLengths), fps)
    printTimeFrame('Average clip length', sum(clipLengths) / len(clipLengths), fps)
    print('')
    print('Number of cuts:', cuts)
    printTimeFrame('Smallest cut length', min(cutL), fps)
    printTimeFrame('Largest cut length', max(cutL), fps)
    printTimeFrame('Average cut length', sum(cutL) / len(cutL), fps)
    print('')
    if(not audioFile):
        print('Video framerate:', fps)

    if(not useCache):
        createCache(cache, myInput, fps, tracks)
