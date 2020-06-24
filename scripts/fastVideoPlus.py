'''fastVideoPlus.py'''

"""
This script is like fastVideo but it supports sounded and silent speeds. It might be a
bit RAM intensive though.

This script is not currently being used.
"""

# External libraries
import cv2
import numpy as np
from scipy.io import wavfile
from audiotsm import phasevocoder
from scripts.readAudio import ArrReader, ArrWriter

# Internal libraries
import math
import sys
import time
import os
import subprocess
import argparse
from shutil import rmtree, get_terminal_size
from time import time, localtime
from datetime import timedelta

nFrames = 0


def fastVideoPlus(videoFile, outFile, silentThreshold, frameMargin, SAMPLE_RATE,
    AUD_BITRATE, VERBOSE, videoSpeed, silentSpeed):

    print('Running from fastVideoPlus.py')

    if(not os.path.isfile(videoFile)):
        print('Could not find file:', videoFile)
        sys.exit()

    TEMP = '.TEMP'
    FADE_SIZE = 400
    NEW_SPEED = [silentSpeed, videoSpeed]

    cap = cv2.VideoCapture(videoFile)
    width = int(cap.get(cv2.CAP_PROP_FRAME_WIDTH))
    height = int(cap.get(cv2.CAP_PROP_FRAME_HEIGHT))
    fourcc = cv2.VideoWriter_fourcc(*'mp4v')
    fps = round(cap.get(cv2.CAP_PROP_FPS))

    try:
        os.mkdir(TEMP)
    except OSError:
        rmtree(TEMP)
        os.mkdir(TEMP)

    extractAudio = ['ffmpeg', '-i', videoFile, '-ab', AUD_BITRATE, '-ac', '2', '-ar',
        str(SAMPLE_RATE), '-vn', f'{TEMP}/output.wav']
    if(not VERBOSE):
        extractAudio.extend(['-nostats', '-loglevel', '0'])

    subprocess.call(extractAudio)

    out = cv2.VideoWriter(f'{TEMP}/spedup.mp4', fourcc, fps, (width, height))
    sampleRate, audioData = wavfile.read(f'{TEMP}/output.wav')

    skipped = 0
    channels = int(audioData.shape[1])

    def getMaxVolume(s):
        maxv = np.max(s)
        minv = np.min(s)
        return max(maxv, -minv)

    switchStart = 0
    maxVolume = getMaxVolume(audioData)

    needChange = False
    preve = None
    endMargin = 0

    y = np.zeros_like(audioData, dtype=np.int16)
    yPointer = 0
    frameBuffer = []

    premask = np.arange(FADE_SIZE) / FADE_SIZE
    mask = np.repeat(premask[:, np.newaxis], 2, axis=1)

    def prettyTime(newTime):
        newTime = localtime(newTime)
        hours = newTime.tm_hour

        if(hours == 0):
            hours = 12
        if(hours > 12):
            hours -= 12

        if(newTime.tm_hour >= 12):
            ampm = 'PM'
        else:
            ampm = 'AM'

        minutes = newTime.tm_min
        return f'{hours:02}:{minutes:02} {ampm}'

    def print_percent_done(index, total, bar_len=34, title='Please wait'):

        termsize = get_terminal_size().columns

        bar_len = max(1, termsize - (len(title) + 50))
        percent_done = (index+1) / total * 100
        percent_done = round(percent_done, 1)

        done = round(percent_done / (100/bar_len))
        togo = bar_len - done

        done_str = '█'*int(done)
        togo_str = '░'*int(togo)

        curTime = time() - beginTime

        if(percent_done == 0):
            percentPerSec = 0
        else:
            percentPerSec = curTime / percent_done

        newTime = prettyTime(beginTime + (percentPerSec * 100))

        bar = f'  ⏳{title}: [{done_str}{togo_str}] {percent_done}% done ETA {newTime}  '

        # clear the screen to prevent
        print(' ' * (termsize - 2), end='\r', flush=True)
        # then print everything
        if(index != total - 1):
            print(bar, end='\r', flush=True)
        else:
            print('Finished.' + (' ' * (termsize - 11)), end='\r', flush=True)


    def writeFrames(frames, nAudio, speed, samplePerSecond, writer):
        numAudioChunks = round(nAudio / samplePerSecond * fps)
        global nFrames
        numWrites = numAudioChunks - nFrames
        nFrames += numWrites  # if sync issue exists, change this back
        limit = len(frames) - 1
        for i in range(numWrites):
            frameIndex = round(i * speed)
            if(frameIndex > limit):
                writer.write(frames[-1])
            else:
                writer.write(frames[frameIndex])

    totalFrames = 4000 # change this later
    numFrames = 0
    beginTime = time()

    while cap.isOpened():
        ret, frame = cap.read()
        if(not ret):
            break

        numFrames += 1

        currentTime = cap.get(cv2.CAP_PROP_POS_MSEC) / 1000
        audioSampleStart = math.floor(currentTime * sampleRate)

        audioSampleEnd = min(
            audioSampleStart + sampleRate // fps * frameMargin, len(audioData)
        )
        switchEnd = audioSampleStart + sampleRate // fps

        audioChunk = audioData[audioSampleStart:audioSampleEnd]

        if(getMaxVolume(audioChunk) / maxVolume < silentThreshold):
            if(endMargin < 1):
                isSilent = 1
            else:
                isSilent = 0
                endMargin -= 1
        else:
            isSilent = 0
            endMargin = frameMargin
        if(preve is not None and preve != isSilent):
            needChange = True

        preve = isSilent

        if(not needChange):
            skipped += 1
            frameBuffer.append(frame)
        else:
            theSpeed = NEW_SPEED[isSilent]
            if(theSpeed < 99999):
                spedChunk = audioData[switchStart:switchEnd]
                spedupAudio = np.zeros((0, 2), dtype=np.int16)
                with ArrReader(spedChunk, channels, sampleRate, 2) as reader:
                    with ArrWriter(spedupAudio, channels, sampleRate, 2) as writer:
                        phasevocoder(reader.channels, speed=theSpeed).run(
                            reader, writer
                        )
                        spedupAudio = writer.output

                yPointerEnd = yPointer + spedupAudio.shape[0]
                y[yPointer:yPointerEnd] = spedupAudio

                if(spedupAudio.shape[0] < FADE_SIZE):
                    y[yPointer:yPointerEnd] = 0
                else:
                    y[yPointer : yPointer + FADE_SIZE] = (
                        y[yPointer : yPointer + FADE_SIZE] * mask
                    )
                    y[yPointerEnd - FADE_SIZE : yPointerEnd] = (
                        y[yPointerEnd - FADE_SIZE : yPointerEnd] * 1 - mask
                    )
                yPointer = yPointerEnd
            else:
                yPointerEnd = yPointer

            writeFrames(frameBuffer, yPointerEnd, NEW_SPEED[isSilent], sampleRate, out)
            frameBuffer = []
            switchStart = switchEnd
            needChange = False

        print_percent_done(numFrames, totalFrames)

    # finish audio
    y = y[:yPointer]
    wavfile.write(f'{TEMP}/spedupAudio.wav', sampleRate, y)

    if(not os.path.isfile(f'{TEMP}/spedupAudio.wav')):
        raise IOError('audio file not created.')

    cap.release()
    out.release()
    cv2.destroyAllWindows()

    first = videoFile[:videoFile.rfind('.')]
    extension = videoFile[videoFile.rfind('.'):]

    if(outFile == ''):
        outFile = f'{first}_faster{extension}'

    cmd = ['ffmpeg', '-y', '-i', f'{TEMP}/spedup.mp4', '-i',
        f'{TEMP}/spedupAudio.wav', '-c:v', 'copy', '-c:a', 'aac', outFile]

    if(not VERBOSE):
        cmd.extend(['-nostats', '-loglevel', '0'])
    subprocess.call(cmd)

    return outFile
