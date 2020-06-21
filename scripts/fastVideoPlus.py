'''fastVideoPlus.py'''

"""
This script is like fastVideo but it supports sounded and silent speeds.

It might be a bit RAM intensive though. This is currently not being used.
"""

# External libraries
import cv2
import numpy as np
from scipy.io import wavfile
from audiotsm import phasevocoder
from readAudio import ArrReader, ArrWriter

# Internal libraries
import math
import sys
import time
import os
import subprocess
import argparse
from shutil import rmtree
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

    while cap.isOpened():
        ret, frame = cap.read()
        if(not ret):
            break
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

        if(skipped % 200 == 0):
            print(f"{skipped} frames inspected")
            skipped += 1

    y = y[:yPointer]
    wavfile.write(f'{TEMP}/spedupAudio.wav', sampleRate, y)

    if not os.path.isfile(f'{TEMP}/spedupAudio.wav'):
        raise IOError('The new audio file was not created.')

    cap.release()
    out.release()
    cv2.destroyAllWindows()

    first = videoFile[:videoFile.rfind('.')]
    extension = videoFile[videoFile.rfind('.'):]

    outFile = f'{first}_faster{extension}'

    cmd = ['ffmpeg', '-y', '-i', f'{TEMP}/spedup.mp4', '-i',
        f'{TEMP}/spedupAudio.wav', '-c:v', 'copy', '-c:a', 'aac', outFile]

    if(not VERBOSE):
        cmd.extend(['-nostats', '-loglevel', '0'])
    subprocess.call(cmd)

    return outFile
