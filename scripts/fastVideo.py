'''scripts/fastVideo.py'''

"""
This method is used for mp4 files that only need frame margin and silent_threshold
specified.

It's about 4x faster than the safe method. 1 Minute of video takes about 12 seconds.
"""

# External libraries
import cv2
import numpy as np
from scipy.io import wavfile

# Internal libraries
import math
import os
import subprocess
import argparse
from shutil import rmtree

def getAudioChunks(audioData, sampleRate, frameRate, SILENT_THRESHOLD, FRAME_SPREADAGE):

    def getMaxVolume(s):
        maxv = float(np.max(s))
        minv = float(np.min(s))
        return max(maxv, -minv)

    audioSampleCount = audioData.shape[0]
    maxAudioVolume = getMaxVolume(audioData)

    samplesPerFrame = sampleRate / frameRate
    audioFrameCount = int(math.ceil(audioSampleCount / samplesPerFrame))
    hasLoudAudio = np.zeros((audioFrameCount))

    for i in range(audioFrameCount):
        start = int(i * samplesPerFrame)
        end = min(int((i+1) * samplesPerFrame), audioSampleCount)
        audiochunks = audioData[start:end]
        maxchunksVolume = getMaxVolume(audiochunks) / maxAudioVolume
        if(maxchunksVolume >= SILENT_THRESHOLD):
            hasLoudAudio[i] = 1

    chunks = [[0, 0, 0]]
    shouldIncludeFrame = np.zeros((audioFrameCount))
    for i in range(audioFrameCount):
        start = int(max(0, i-FRAME_SPREADAGE))
        end = int(min(audioFrameCount, i+1+FRAME_SPREADAGE))
        shouldIncludeFrame[i] = min(1, np.max(hasLoudAudio[start:end]))

        if (i >= 1 and shouldIncludeFrame[i] != shouldIncludeFrame[i-1]):
            chunks.append([chunks[-1][1], i, shouldIncludeFrame[i-1]])

    chunks.append([chunks[-1][1], audioFrameCount, shouldIncludeFrame[i-1]])
    chunks = chunks[1:]

    return chunks

def fastVideo(videoFile, outFile, silentThreshold, frameMargin):

    TEMP = '.TEMP'

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

    extractAudio = ["ffmpeg", "-i", videoFile, "-ab", "160k", "-ac", "2", "-ar"]
    extractAudio.extend(["44100", "-vn", f"{TEMP}/output.wav", "-nostats", "-loglevel"])
    extractAudio.extend(["0"])

    subprocess.call(extractAudio)

    out = cv2.VideoWriter(f'{TEMP}/spedup.mp4', fourcc, fps, (width, height))
    sampleRate, audioData = wavfile.read(f'{TEMP}/output.wav')

    chunks = getAudioChunks(audioData, sampleRate, fps, silentThreshold, frameMargin)

    channels = int(audioData.shape[1])

    y = np.zeros_like(audioData, dtype=np.int16)
    yPointer = 0
    samplesPerFrame = sampleRate / fps

    # premask = np.arange(FADE_SIZE) / FADE_SIZE
    # mask = np.repeat(premask[:, np.newaxis], 2, axis=1)

    while cap.isOpened():
        ret, frame = cap.read()
        if(not ret):
            break

        cframe = int(cap.get(cv2.CAP_PROP_POS_FRAMES)) # current frame

        currentTime = cframe / fps

        # handle audio
        audioSampleStart = int(currentTime * sampleRate)
        audioSampleEnd = audioSampleStart + (sampleRate // fps)
        switchEnd = audioSampleEnd

        audioChunk = audioData[audioSampleStart:audioSampleEnd]

        state = None
        normal = True
        for chunk in chunks:
            if(cframe >= chunk[0] and cframe <= chunk[1]):
                state = chunk[2]
                if(cframe == chunk[1]):
                    normal = False
                break
        if(state == 1):
            out.write(frame)

            switchStart = switchEnd

            yPointerEnd = yPointer + audioChunk.shape[0]
            y[yPointer:yPointerEnd] = audioChunk
            yPointer = yPointerEnd

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

    cmd = ['ffmpeg', '-y', '-i', f'{TEMP}/spedup.mp4', '-i']
    cmd.extend([f"{TEMP}/spedupAudio.wav", "-c:v", "copy", "-c:a", "aac", outFile])
    cmd.extend(["-nostats", "-loglevel", "0"])
    subprocess.call(cmd)

    return outFile
