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

# Internal libraries
import math
import os
import sys
import subprocess
import argparse
from shutil import rmtree, get_terminal_size
from time import time, localtime

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

    if(maxAudioVolume == 0):
        print('Warning! The entire video is silent')
        print(audioData)
        # WyattBlue is doing tests with silent mkv video files and he wants them to
        # be "edified" so that he can see if fastVideo.py is lossless.

        # That's why the entire length of the video is outputed.
        return [[0, audioFrameCount, 1]]

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

    channels = int(audioData.shape[1])

    y = np.zeros_like(audioData, dtype=np.int16)
    yPointer = 0
    samplesPerFrame = sampleRate / fps

    # premask = np.arange(FADE_SIZE) / FADE_SIZE
    # mask = np.repeat(premask[:, np.newaxis], 2, axis=1)

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

    totalFrames = chunks[len(chunks) - 1][1]
    numFrames = 0
    beginTime = time()

    while cap.isOpened():
        ret, frame = cap.read()
        if(not ret):
            break

        numFrames += 1

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
        outFile = f'{first}_ALTERED{extension}'

    cmd = ['ffmpeg', '-y', '-i', f'{TEMP}/spedup.mp4', '-i', f'{TEMP}/spedupAudio.wav',
        '-c:v', 'copy', '-c:a', 'aac', outFile]

    if(not VERBOSE):
        cmd.extend(['-nostats', '-loglevel', '0'])
    subprocess.call(cmd)

    return outFile
