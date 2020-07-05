'''fastVideoPlus.py'''

"""
This script is like fastVideo but it supports sounded and silent speeds. It might be a
bit RAM intensive though.
"""

# External libraries
import cv2  # pip3 install opencv-python
import numpy as np
from audiotsm import phasevocoder

# Included functions
from scripts.readAudio import ArrReader, ArrWriter
from scripts.usefulFunctions import getAudioChunks, progressBar, vidTracks
from scripts.wavfile import read, write

# Internal libraries
import sys
import os
import math
import tempfile
import subprocess
from shutil import rmtree
from time import time

def preview(chunks, NEW_SPEED, fps):
    timeInSeconds = 0
    for chunk in chunks:
        leng = chunk[1] - chunk[0]
        if(NEW_SPEED[chunk[2]] < 99999):
            timeInSeconds += leng * (1 / NEW_SPEED[chunk[2]])
    return timeInSeconds / fps


def fastVideoPlus(videoFile, outFile, silentThreshold, frameMargin, SAMPLE_RATE,
    AUD_BITRATE, VERBOSE, videoSpeed, silentSpeed, cutByThisTrack, keepTracksSep):

    print('Running from fastVideoPlus.py')

    if(not os.path.isfile(videoFile)):
        print('Could not find file:', videoFile)
        sys.exit()

    TEMP = tempfile.mkdtemp()
    FADE_SIZE = 400
    NEW_SPEED = [silentSpeed, videoSpeed]

    cap = cv2.VideoCapture(videoFile)
    width = int(cap.get(cv2.CAP_PROP_FRAME_WIDTH))
    height = int(cap.get(cv2.CAP_PROP_FRAME_HEIGHT))
    fourcc = cv2.VideoWriter_fourcc(*'mp4v')
    fps = round(cap.get(cv2.CAP_PROP_FPS))

    tracks = vidTracks(videoFile)

    if(cutByThisTrack >= tracks):
        print("Error: You choose a track that doesn't exist.")
        print(f'There are only {tracks-1} tracks. (starting from 0)')
        sys.exit()
    for trackNumber in range(tracks):
        cmd = ['ffmpeg', '-i', videoFile, '-ab', AUD_BITRATE, '-ac', '2', '-ar',
        str(SAMPLE_RATE),'-map', f'0:a:{trackNumber}', f'{TEMP}/{trackNumber}.wav']
        if(not VERBOSE):
            cmd.extend(['-nostats', '-loglevel', '0'])
        else:
            cmd.extend(['-hide_banner'])
        subprocess.call(cmd)

    sampleRate, audioData = read(f'{TEMP}/{cutByThisTrack}.wav')
    chunks = getAudioChunks(audioData, sampleRate, fps, silentThreshold, 2, frameMargin)

    hmm = preview(chunks, NEW_SPEED, fps)
    estLeng = int((hmm * SAMPLE_RATE) * 1.5) + int(SAMPLE_RATE * 2)

    oldAudios = []
    newAudios = []
    for i in range(tracks):
        __, audioData = read(f'{TEMP}/{i}.wav')
        oldAudios.append(audioData)
        newAudios.append(np.zeros((estLeng, 2), dtype=np.int16))

    yPointer = 0

    out = cv2.VideoWriter(f'{TEMP}/spedup.mp4', fourcc, fps, (width, height))

    channels = 2

    switchStart = 0
    needChange = False
    preve = None
    endMargin = 0

    yPointer = 0

    totalFrames = chunks[len(chunks) - 1][1]
    lastChunk = chunks[len(chunks) - 1][0]
    outFrame = 0
    beginTime = time()

    remander = 0

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

        # handle when to add a frame
        mySpeed = NEW_SPEED[state]
        if(mySpeed != 99999):
            doIt = 1 / mySpeed + remander
            for __ in range(int(doIt)):
                out.write(frame)
            remander = doIt % 1

        # handle audio
        if(needChange):
            theSpeed = NEW_SPEED[isSilent]
            if(theSpeed != 99999):
                # handle audio tracks
                for i, oneAudioData in enumerate(oldAudios):
                    spedChunk = oneAudioData[switchStart:switchEnd]
                    spedupAudio = np.zeros((0, 2), dtype=np.int16)
                    with ArrReader(spedChunk, channels, sampleRate, 2) as reader:
                        with ArrWriter(spedupAudio, channels, sampleRate, 2) as writer:
                            phasevocoder(reader.channels, speed=theSpeed).run(
                                reader, writer
                            )
                            spedupAudio = writer.output

                    yPointerEnd = yPointer + spedupAudio.shape[0]

                    newAudios[i][yPointer:yPointerEnd] = spedupAudio
                yPointer = yPointerEnd

            else:
                yPointerEnd = yPointer

            switchStart = switchEnd
            needChange = False

        progressBar(cframe, totalFrames, beginTime)

    # finish audio
    for i, newData in enumerate(newAudios):
        newData = newData[:yPointer]
        write(f'{TEMP}/new{i}.wav', sampleRate, newData)

        if(not os.path.isfile(f'{TEMP}/new{i}.wav')):
            raise IOError('audio file not created.')

    cap.release()
    out.release()
    cv2.destroyAllWindows()

    first = videoFile[:videoFile.rfind('.')]
    extension = videoFile[videoFile.rfind('.'):]

    if(outFile == ''):
        outFile = f'{first}_ALTERED{extension}'

    # Now mix new audio(s) and the new video.
    if(keepTracksSep):
        cmd = ['ffmpeg', '-y']
        for i in range(tracks):
            cmd.extend(['-i', f'{TEMP}/new{i}.wav'])
        cmd.extend(['-i', f'{TEMP}/spedup.mp4']) # add input video
        for i in range(tracks):
            cmd.extend(['-map', f'{i}:a:0'])
        cmd.extend(['-map', f'{tracks}:v:0','-c:v', 'copy', '-movflags', '+faststart',
            outFile])
        if(not VERBOSE):
            cmd.extend(['-nostats', '-loglevel', '0'])
    else:
        if(tracks > 1):
            cmd = ['ffmpeg']
            for i in range(tracks):
                cmd.extend(['-i', f'{TEMP}/new{i}.wav'])
            cmd.extend(['-filter_complex', f'amerge=inputs={tracks}', '-ac', '2',
                f'{TEMP}/newAudioFile.wav'])
            if(not VERBOSE):
                cmd.extend(['-nostats', '-loglevel', '0'])
            subprocess.call(cmd)
        else:
            os.rename(f'{TEMP}/new0.wav', f'{TEMP}/newAudioFile.wav')

        cmd = ['ffmpeg', '-y', '-i', f'{TEMP}/newAudioFile.wav', '-i',
            f'{TEMP}/spedup.mp4', '-c:v', 'copy', '-movflags', '+faststart',
            outFile]
        if(not VERBOSE):
            cmd.extend(['-nostats', '-loglevel', '0'])
        subprocess.call(cmd)

    rmtree(TEMP)

    return outFile
