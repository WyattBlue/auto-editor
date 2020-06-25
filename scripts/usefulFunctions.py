'''scripts/usefulFunctions.py'''

"""
To prevent duplicate code being pasted between methods, common functions should be
put here.
"""

# External libraries
import numpy as np

# Internal libraries
import math
from shutil import get_terminal_size
from time import time, localtime

def getMaxVolume(s):
    maxv = float(np.max(s))
    minv = float(np.min(s))
    return max(maxv, -minv)

def getAudioChunks(audioData, sampleRate, frameRate, SILENT_THRESHOLD, FRAME_SPREADAGE):
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

def progressBar(index, total, beginTime, title='Please wait'):
    termsize = get_terminal_size().columns
    bar_len = max(1, termsize - (len(title) + 50))
    percent_done = (index+1) / total * 100
    percent_done = round(percent_done, 1)

    done = round(percent_done / (100/bar_len))
    togo = bar_len - done
    done_str = '█' * int(done)
    togo_str = '░' * int(togo)

    curTime = time() - beginTime

    if(percent_done == 0):
        percentPerSec = 0
    else:
        percentPerSec = curTime / percent_done

    newTime = prettyTime(beginTime + (percentPerSec * 100))
    bar = f'  ⏳{title}: [{done_str}{togo_str}] {percent_done}% done ETA {newTime}  '
    print(' ' * (termsize - 2), end='\r', flush=True)
    if(percent_done < 99.9):
        print(bar, end='\r', flush=True)
    else:
        print('Finished.' + (' ' * (termsize - 11)), end='\r', flush=True)

