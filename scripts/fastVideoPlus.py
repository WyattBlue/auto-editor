'''fastVideoPlus.py'''

"""
This script is like fastVideo but it supports sounded and silent speeds. It might be a
bit RAM intensive though.
"""

# External libraries
import cv2
import numpy as np
from scipy.io import wavfile
from audiotsm import phasevocoder

# Included functions
from scripts.readAudio import ArrReader, ArrWriter
from scripts.usefulFunctions import getAudioChunks, progressBar

# Internal libraries
import sys
import os
import math
import subprocess
from shutil import rmtree
from time import time

nFrames = 0

def preview(chunks, NEW_SPEED, fps):
    timeInSeconds = 0
    for chunk in chunks:
        leng = chunk[1] - chunk[0]
        if(NEW_SPEED[chunk[2]] < 99999):
            timeInSeconds += leng * (1 / NEW_SPEED[chunk[2]])
    return timeInSeconds / fps


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
    chunks = getAudioChunks(audioData, sampleRate, fps, silentThreshold, frameMargin)
    channels = int(audioData.shape[1])

    switchStart = 0
    needChange = False
    preve = None
    endMargin = 0

    hmm = preview(chunks, NEW_SPEED, fps)
    estLeng = int((hmm * SAMPLE_RATE) * 1.15)

    # y needs to be as big or bigger than the new audio data or this program will fail
    y = np.zeros((estLeng, 2), dtype=np.int16)
    yPointer = 0
    frameBuffer = []

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


    totalFrames = chunks[len(chunks) - 1][1]
    outFrame = 0
    beginTime = time()

    while cap.isOpened():
        ret, frame = cap.read()
        if(not ret):
            break

        cframe = int(cap.get(cv2.CAP_PROP_POS_FRAMES)) # current frame

        currentTime = cap.get(cv2.CAP_PROP_POS_MSEC) / 1000
        audioSampleStart = int(currentTime * sampleRate)

        audioSampleEnd = min(
            audioSampleStart + sampleRate // fps * frameMargin, len(audioData)
        )
        switchEnd = audioSampleStart + sampleRate // fps

        audioChunk = audioData[audioSampleStart:audioSampleEnd]

        state = None
        for chunk in chunks:
            if(cframe >= chunk[0] and cframe <= chunk[1]):
                state = chunk[2]
                break

        if(state == 0):
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
                y[yPointer: yPointerEnd] = spedupAudio
                yPointer = yPointerEnd
            else:
                yPointerEnd = yPointer

            writeFrames(frameBuffer, yPointerEnd, NEW_SPEED[isSilent], sampleRate, out)
            frameBuffer = []
            switchStart = switchEnd
            needChange = False

        progressBar(cframe, totalFrames, beginTime)

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
        outFile = f'{first}_ALTERED{extension}'

    cmd = ['ffmpeg', '-y', '-i', f'{TEMP}/spedup.mp4', '-i',
        f'{TEMP}/spedupAudio.wav', '-c:v', 'copy', '-c:a', 'aac', outFile]

    if(not VERBOSE):
        cmd.extend(['-nostats', '-loglevel', '0'])
    subprocess.call(cmd)

    return outFile
