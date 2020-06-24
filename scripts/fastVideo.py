'''scripts/fastVideo.py'''

"""
This method is used for mp4 files that only need frame margin and silent_threshold
specified.

It's about 4x faster than the safe method. 1 Minute of video may take about 12 seconds.
"""

# External libraries
import cv2
import numpy as np
from scipy.io import wavfile

# Included functions
from scripts.usefulFunctions import getAudioChunks, progressBar

# Internal libraries
import os
import sys
import subprocess
from shutil import rmtree
from time import time

def fastVideo(videoFile, outFile, silentThreshold, frameMargin, SAMPLE_RATE,
    AUD_BITRATE, VERBOSE):

    print('Running from fastVideo.py')

    if(not os.path.isfile(videoFile)):
        print('Could not find file:', videoFile)
        sys.exit()

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

    extractAudio = ['ffmpeg', '-i', videoFile, '-ab', AUD_BITRATE, '-ac', '2', '-ar',
        str(SAMPLE_RATE), '-vn', f'{TEMP}/output.wav']
    if(not VERBOSE):
        extractAudio.extend(['-nostats', '-loglevel', '0'])

    subprocess.call(extractAudio)

    out = cv2.VideoWriter(f'{TEMP}/spedup.mp4', fourcc, fps, (width, height))
    sampleRate, audioData = wavfile.read(f'{TEMP}/output.wav')

    chunks = getAudioChunks(audioData, sampleRate, fps, silentThreshold, frameMargin)

    y = np.zeros_like(audioData, dtype=np.int16)
    yPointer = 0

    totalFrames = chunks[len(chunks) - 1][1]
    beginTime = time()

    while cap.isOpened():
        ret, frame = cap.read()
        if(not ret):
            break

        cframe = int(cap.get(cv2.CAP_PROP_POS_FRAMES)) # current frame

        currentTime = cframe / fps

        # handle audio
        audioSampleStart = int(currentTime * sampleRate)
        audioSampleEnd = audioSampleStart + (sampleRate // fps)

        audioChunk = audioData[audioSampleStart:audioSampleEnd]

        state = None
        for chunk in chunks:
            if(cframe >= chunk[0] and cframe <= chunk[1]):
                state = chunk[2]
                break
        if(state == 1):
            out.write(frame)

            yPointerEnd = yPointer + audioChunk.shape[0]
            y[yPointer:yPointerEnd] = audioChunk
            yPointer = yPointerEnd

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

    cmd = ['ffmpeg', '-y', '-i', f'{TEMP}/spedup.mp4', '-i', f'{TEMP}/spedupAudio.wav',
        '-c:v', 'copy', '-c:a', 'aac', outFile]

    if(not VERBOSE):
        cmd.extend(['-nostats', '-loglevel', '0'])
    subprocess.call(cmd)

    return outFile
