'''usefulFunctions.py'''

"""
To prevent duplicate code being pasted between scripts, common functions should be
put here. No code here should modify or create video/audio files.
"""

# External libraries
import numpy as np

# Internal libraries
import os
import subprocess
from shutil import get_terminal_size
from time import time, localtime


class Log():
    """
    Log(0), print nothing
    Log(1), print errors
    Log(2), print errors and warnings.
    Log(3), print errors, warnings, and debug.

    Log(-1), don't crash when errors happen
    """
    def __init__(self, level=3):
        self.level = level

    def error(self, message):
        if(self.level > 0):
            print('Error!', message)
        if(self.level != -1):
            import sys
            sys.exit(1)

    def warning(self, message):
        if(self.level > 1):
            print('Warning!', message)

    def debug(self, message):
        if(self.level > 2):
            print(message)

log = Log(level=3)

def isAudioFile(filePath):
    fileFormat = filePath[filePath.rfind('.'):]
    return fileFormat in ['.wav', '.mp3', '.m4a']


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


def getAudioChunks(audioData, sampleRate, fps, silentT, frameMargin, minClip, minCut):
    import math

    log.warning('testing', 10)

    audioSampleCount = audioData.shape[0]
    maxAudioVolume = getMaxVolume(audioData)

    samplesPerFrame = sampleRate / fps
    audioFrameCount = int(math.ceil(audioSampleCount / samplesPerFrame))
    hasLoudAudio = np.zeros((audioFrameCount), dtype=np.uint8)

    if(maxAudioVolume == 0):
        log.warning('The entire audio is silent')
        return [[0, audioFrameCount, 1]]

    # Calculate when the audio is lould or silent.
    for i in range(audioFrameCount):
        start = int(i * samplesPerFrame)
        end = min(int((i+1) * samplesPerFrame), audioSampleCount)
        audiochunks = audioData[start:end]
        if(getMaxVolume(audiochunks) / maxAudioVolume >= silentT):
            hasLoudAudio[i] = 1

    def removeSmall(hasLoudAudio, limit, replace, with_):
        startP = 0
        active = False
        for j, item in enumerate(hasLoudAudio):
            if(item == replace):
                if(not active):
                    startP = j
                    active = True
                if(j == len(hasLoudAudio) - 1):
                    if(j - startP < limit):
                        hasLoudAudio[startP:j+1] = with_
            else:
                if(active):
                    if(j - startP < limit):
                        hasLoudAudio[startP:j] = with_
                    active = False
        return hasLoudAudio

    # Remove small loudness spikes
    hasLoudAudio = removeSmall(hasLoudAudio, minClip, replace=1, with_=0)
    # Remove small silences
    hasLoudAudio = removeSmall(hasLoudAudio, minCut, replace=0, with_=1)

    # Apply frame margin rules.
    includeFrame = np.zeros((audioFrameCount), dtype=np.uint8)
    for i in range(audioFrameCount):
        start = int(max(0, i - frameMargin))
        end = int(min(audioFrameCount, i+1+frameMargin))
        includeFrame[i] = min(1, np.max(hasLoudAudio[start:end]))

    # Remove small clips created. (not necessary unless frame margin is negative)
    hasLoudAudio = removeSmall(hasLoudAudio, minClip, replace=1, with_=0)
    # Remove small cuts created by appling frame margin rules.
    hasLoudAudio = removeSmall(hasLoudAudio, minCut, replace=0, with_=1)

    # Convert long numpy array into properly formatted chunks list.
    chunks = []
    startP = 0
    for j in range(1, audioFrameCount):
        if(includeFrame[j] != includeFrame[j - 1]):
            chunks.append([startP, j, includeFrame[j-1]])
            startP = j
    chunks.append([startP, audioFrameCount, includeFrame[j]])
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
    import platform

    dirPath = os.path.dirname(os.path.realpath(__file__))

    if(ffmpeg == 'ffmpeg'):
        ffprobe = 'ffprobe'
    else:
        if(platform.system() == 'Windows'):
            ffprobe = os.path.join(dirPath, 'win-ffmpeg/bin/ffprobe.exe')
        elif(platform.system() == 'Darwin'):
            ffprobe = os.path.join(dirPath, 'mac-ffmpeg/bin/ffprobe')
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
        log.warning('ffprobe had an invalid output.')
        # Most of the time, there's only one track anyway,
        # so just assume that's the case.
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
