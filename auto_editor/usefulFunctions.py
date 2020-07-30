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


def isAudioFile(filePath):
    extension = filePath[filePath.rfind('.'):]
    return extension in ['.wav', '.mp3', '.m4a']


def createCache(cache, myFile, fps, tracks):
    baseFile = os.path.basename(myFile)
    fileSize = str(os.stat(myFile).st_size)
    with open(f'{cache}/cache.txt', 'w') as ct:
        ct.write('\n'.join([baseFile, str(fps), fileSize, str(tracks)]) + '\n')


def checkCache(cache, myFile, fps):
    from shutil import rmtree

    useCache = False
    tracks = 0
    try:
        os.mkdir(cache)
    except OSError:
        # There must a cache already, check if that's usable.
        if(os.path.isfile(f'{cache}/cache.txt')):
            file = open(f'{cache}/cache.txt', 'r')
            x = file.read().splitlines()
            file.close()

            baseFile = os.path.basename(myFile)
            fileSize = str(os.stat(myFile).st_size)
            if(x[:3] == [baseFile, str(fps), fileSize]):
                useCache = True
                tracks = int(x[3])

        if(not useCache):
            rmtree(cache)
            os.mkdir(cache)

    return useCache, tracks


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
        if(getMaxVolume(audiochunks) / maxAudioVolume >= silentT):
            hasLoudAudio[i] = 1

    # Remove small loudness spikes
    startP = 0
    active = False
    for j, item in enumerate(hasLoudAudio):
        if(item == 1):
            if(not active):
                startP = j
                active = True
            if(j == len(hasLoudAudio) - 1):
                if(j - startP < minClip):
                    hasLoudAudio[startP:j+1] = 0
        else:
            if(active):
                if(j - startP < minClip):
                    hasLoudAudio[startP:j] = 0
                active = False

    # Remove small silences
    startP = 0
    active = False
    for j, item in enumerate(hasLoudAudio):
        if(item == 0):
            if(not active):
                startP = j
                active = True
            if(j == len(hasLoudAudio) - 1):
                if(j - startP < minCut):
                    hasLoudAudio[startP:j+1] = 1
        else:
            if(active):
                if(j - startP < minCut):
                    hasLoudAudio[startP:j] = 1
                active = False

    includeFrame = np.zeros((audioFrameCount), dtype=np.uint8)
    for i in range(audioFrameCount):
        start = int(max(0, i - frameMargin))
        end = int(min(audioFrameCount, i+1+frameMargin))
        includeFrame[i] = min(1, np.max(hasLoudAudio[start:end]))

    # Remove unneeded clips.
    startP = 0
    active = False
    for j, item in enumerate(includeFrame):
        if(item == 1):
            if(not active):
                startP = j
                active = True
            if(j == len(includeFrame) - 1):
                if(j - startP < minClip):
                    includeFrame[startP:j+1] = 0
        else:
            if(active):
                if(j - startP < minClip):
                    includeFrame[startP:j] = 0
                active = False

    # Remove unneeded cuts.
    startP = 0
    active = False
    for j, item in enumerate(includeFrame):
        if(item == 0):
            if(not active):
                startP = j
                active = True
            if(j == len(includeFrame) - 1):
                if(j - startP < minCut):
                    includeFrame[startP:j+1] = 1
        else:
            if(active):
                if(j - startP < minCut):
                    includeFrame[startP:j] = 1
                active = False
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
        print('Warning! ffprobe had an invalid output.')
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