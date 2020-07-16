'''scripts/usefulFunctions.py'''

"""
To prevent duplicate code being pasted between methods, common functions should be
put here. No code here should make or delete files.
"""

# External libraries
import numpy as np

# Internal libraries
import subprocess
from shutil import get_terminal_size
from time import time, localtime

def getNewLength(chunks, speeds, fps):
    timeInFrames = 0
    for chunk in chunks:
        leng = chunk[1] - chunk[0]
        if(speeds[chunk[2]] < 99999):
            timeInFrames += leng * (1 / speeds[chunk[2]])
    return timeInFrames / fps


def getMaxVolume(s):
    maxv = float(np.max(s))
    minv = float(np.min(s))
    return max(maxv, -minv)


def getAudioChunks(audioData, sampleRate, fps, silentT, zoomT, frameMargin):
    import math

    audioSampleCount = audioData.shape[0]
    maxAudioVolume = getMaxVolume(audioData)

    samplesPerFrame = sampleRate / fps
    audioFrameCount = int(math.ceil(audioSampleCount / samplesPerFrame))
    hasLoudAudio = np.zeros((audioFrameCount), dtype=np.uint8)

    if(maxAudioVolume == 0):
        print('Warning! The entire audio is silent')
        return [[0, audioFrameCount, 1]]

    for i in range(audioFrameCount):
        start = int(i * samplesPerFrame)
        end = min(int((i+1) * samplesPerFrame), audioSampleCount)
        audiochunks = audioData[start:end]
        maxchunksVolume = getMaxVolume(audiochunks) / maxAudioVolume
        if(maxchunksVolume >= zoomT):
            hasLoudAudio[i] = 2
        elif(maxchunksVolume >= silentT):
            hasLoudAudio[i] = 1

    chunks = [[0, 0, 0]]
    shouldIncludeFrame = np.zeros((audioFrameCount), dtype=np.uint8)
    for i in range(audioFrameCount):
        start = int(max(0, i - frameMargin))
        end = int(min(audioFrameCount, i+1+frameMargin))
        shouldIncludeFrame[i] = min(1, np.max(hasLoudAudio[start:end]))

        if(i >= 1 and shouldIncludeFrame[i] != shouldIncludeFrame[i-1]):
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


def vidTracks(videoFile, ffmpeg):
    """
    Return the number of audio tracks in a video file.
    """
    import os
    import platform

    dirPath = os.path.dirname(os.path.realpath(__file__))

    if(ffmpeg == 'ffmpeg'):
        ffprobe = 'ffprobe'
    else:
        if(platform.system() == 'Windows'):
            ffporbe = os.path.join(dirPath, 'win-ffmpeg/bin/ffprobe.exe')
        elif(platform.system() == 'Darwin'):
            ffprobe = os.path.join(dirPath, 'unix-ffprobe')
        else:
            ffprobe = 'ffprobe'

    cmd = [ffprobe, videoFile, '-hide_banner', '-loglevel', 'panic',
        '-show_entries', 'stream=index', '-select_streams', 'a', '-of',
        'compact=p=0:nk=1']

    # Read what ffprobe piped in.
    process = subprocess.Popen(cmd, stdout=subprocess.PIPE, stderr=subprocess.STDOUT)
    stdout, __ = process.communicate()
    output = stdout.decode()
    numbers = output.split('\n')
    try:
        test = int(numbers[0])
        return len(numbers) - 1
    except ValueError:
        print('Warning: ffprobe had an invalid output.')
        return 1


def conwrite(message):
    numSpaces = get_terminal_size().columns - len(message) - 3
    print('  ' + message + ' ' * numSpaces, end='\r', flush=True)


def progressBar(index, total, beginTime, title='Please wait'):
    termsize = get_terminal_size().columns
    barLen = max(1, termsize - (len(title) + 50))

    percentDone = round((index+1) / total * 100, 1)
    done = round(percentDone / (100 / barLen))
    doneStr = '█' * done
    togoStr = '░' * int(barLen - done)

    if(percentDone == 0):
        percentPerSec = 0
    else:
        percentPerSec = (time() - beginTime) / percentDone

    newTime = prettyTime(beginTime + (percentPerSec * 100))

    bar = f'  ⏳{title}: [{doneStr}{togoStr}] {percentDone}% done ETA {newTime}'
    if(len(bar) > termsize - 2):
        bar = bar[:termsize - 2]
    else:
        bar += ' ' * (termsize - len(bar) - 4)
    try:
        print(bar, end='\r', flush=True)
    except UnicodeEncodeError:
        print(f'   {percentDone}% done ETA {newTime}')
