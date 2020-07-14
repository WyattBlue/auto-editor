'''scripts/originalMethod.py'''

import numpy as np

import os
import sys
import math
import subprocess
from shutil import move, rmtree

from scripts.fastAudio import fastAudio
from scripts.originalVid import splitVideo
from scripts.wavfile import read, write
from scripts.usefulFunctions import vidTracks, getMaxVolume, conwrite

TEMP = '.TEMP'
CACHE = '.CACHE'

def handleAudio(ffmpeg, tracks, CACHE, TEMP, silentT, frameMargin, SAMPLE_RATE, audioBit,
    verbose, SILENT_SPEED, VIDEO_SPEED, chunks, frameRate):
    for i in range(tracks):
        newCuts = fastAudio(ffmpeg, f'{CACHE}/{i}.wav', f'{TEMP}/new{i}.wav', silentT,
            frameMargin, SAMPLE_RATE, audioBit, verbose, SILENT_SPEED, VIDEO_SPEED,
            False, chunks=chunks, fps=frameRate)
    return newCuts


def getFrameRate(ffmpeg, path):
    """
    get the frame rate by asking ffmpeg to do it for us then using a regex command to
    retrieve it.
    """
    from re import search

    process = subprocess.Popen([ffmpeg, '-i', path],
        stdout=subprocess.PIPE, stderr=subprocess.STDOUT)
    stdout, __ = process.communicate()
    output = stdout.decode()
    matchDict = search(r'\s(?P<fps>[\d\.]+?)\stbr', output).groupdict()
    return float(matchDict['fps'])


def getZooms(chunks, audioFrameCount, hasLoudAudio, frameMargin):
    zooms = {}
    shouldIncludeFrame = np.zeros((audioFrameCount), dtype=np.uint8)
    hold = False
    endZoom = 0
    for i in range(audioFrameCount):
        if(i in zooms):
            continue
        start = int(max(0, i-frameMargin))
        end = int(min(audioFrameCount, i+1+frameMargin))
        shouldIncludeFrame[i] = np.max(hasLoudAudio[start:end])
        if(i >= 2 and shouldIncludeFrame[i] == 2 and not hold):
            # This part uses a sine function to have a smooth zoom transition.
            if(shouldIncludeFrame[i] != shouldIncludeFrame[i-1]):
                a = 1.2 - 1.0 # 1.0 -> 1.2
                p = int(frameRate / 3)
                for x in range(1, p + 1):
                    trans = a * math.sin((math.pi/(2*p)) * x + (2*math.pi))
                    zooms[i+x-3] = 1 + trans
                hold = True
                endZoom = i + x
                continue
        if(hold):
            zooms[i-1] = 1.2
            if(len(shouldIncludeFrame) - i > int(frameRate * 1.5) and
                shouldIncludeFrame[i] == 1 and i-endZoom > int(frameRate/2)):
                for chunk in chunks:
                    if chunk[0] == i and chunk[2] == 1:
                        hold = False
    return zooms


def originalMethod(ffmpeg, vidFile, outFile, frameMargin, silentT,
    LOUD_THRESHOLD, SAMPLE_RATE, audioBit, SILENT_SPEED, VIDEO_SPEED, KEEP_SEP,
    BACK_MUS, BACK_VOL, NEW_TRAC, BASE_TRAC, COMBINE_TRAC, verbose, HWACCEL):
    """
    This function takes in the path the the input file (and a bunch of other options)
    and outputs a new output file. This is both the safest and slowest of all methods.

    Safest in the fact that if feature isn't supported here, like handling certain
    commands or support obscure file type, it's not supported anywhere.
    """

    print('Running from originalMethod.py')

    speeds = [SILENT_SPEED, VIDEO_SPEED]

    dotIndex = vidFile.rfind('.')
    extension = vidFile[dotIndex:]
    if(outFile == ''):
        outFile = vidFile[:dotIndex] + '_ALTERED' + extension
    else:
        outFile = outFile

    if(not os.path.isfile(vidFile)):
        print('Could not find file:', vidFile)
        sys.exit(1)

    try:
        os.mkdir(TEMP)
    except OSError:
        rmtree(TEMP)
        os.mkdir(TEMP)

    fileSize = os.stat(vidFile).st_size

    try:
        frameRate = getFrameRate(ffmpeg, vidFile)
    except AttributeError:
        print('Warning! frame rate detection has failed, defaulting to 30.')
        frameRate = 30

    SKIP = False
    try:
        os.mkdir(CACHE)
    except OSError:
        # There must a cache already, check if that's usable.
        if(os.path.isfile(f'{CACHE}/cache.txt')):
            file = open(f'{CACHE}/cache.txt', 'r')
            x = file.read().splitlines()
            if(x[:3] == [vidFile, str(frameRate), str(fileSize)]
                and x[4] == str(COMBINE_TRAC)):
                print('Using cache.')
                SKIP = True
                tracks = int(x[3])
            file.close()
        if(not SKIP):
            rmtree(CACHE)
            os.mkdir(CACHE)

    if(not SKIP):
        # Videos can have more than one audio track os we need to extract them all.
        tracks = vidTracks(vidFile)

        if(BASE_TRAC >= tracks):
            print("Error! You choose a track that doesn't exist.")
            print(f'There are only {tracks-1} tracks. (starting from 0)')
            sys.exit(1)
        for trackNumber in range(tracks):
            cmd = [ffmpeg]
            if(HWACCEL is not None):
                cmd.extend(['-hwaccel', HWACCEL])
            cmd.extend(['-i', vidFile, '-map', f'0:a:{trackNumber}',
                f'{CACHE}/{trackNumber}.wav'])
            if(not verbose):
                cmd.extend(['-nostats', '-loglevel', '0'])
            subprocess.call(cmd)

            if(COMBINE_TRAC):
                from pydub import AudioSegment

                for i in range(tracks):
                    if(i == 0):
                        allAuds = AudioSegment.from_file(f'{CACHE}/{i}.wav')
                    else:
                        newTrack = AudioSegment.from_file(f'{CACHE}/{i}.wav')
                        allAuds = allAuds.overlay(newTrack)
                allAuds.export(f'{CACHE}/0.wav', format='wav')
                tracks = 1

            # Now deal with the video.
            conwrite('  Splitting video into jpgs. (This can take a while)')
            cmd = [ffmpeg]
            if(HWACCEL is not None):
                cmd.extend(['-hwaccel', HWACCEL])
            cmd.extend(['-i', vidFile, '-qscale:v', '1', f'{CACHE}/frame%06d.jpg'])
            if(verbose):
                cmd.extend(['-hide_banner'])
            else:
                cmd.extend(['-nostats', '-loglevel', '0'])
            subprocess.call(cmd)

    if(NEW_TRAC is None):
        sampleRate, audioData = read(f'{CACHE}/{BASE_TRAC}.wav')
    else:
        cmd = [ffmpeg, '-i', NEW_TRAC, '-ac', '2', '-ar', str(SAMPLE_RATE), '-vn',
            f'{TEMP}/NEW_TRAC.wav']
        if(verbose):
            cmd.extend(['-hide_banner'])
        else:
            cmd.extend(['-nostats', '-loglevel', '0'])
        subprocess.call(cmd)

        sampleRate, audioData = read(f'{TEMP}/NEW_TRAC.wav')
    audioSampleCount = audioData.shape[0]
    maxAudioVolume = getMaxVolume(audioData)

    samplesPerFrame = sampleRate / frameRate
    audioFrameCount = int(math.ceil(audioSampleCount / samplesPerFrame))
    hasLoudAudio = np.zeros((audioFrameCount), dtype=np.uint8)

    for i in range(audioFrameCount):
        start = int(i * samplesPerFrame)
        end = min(int((i+1) * samplesPerFrame), audioSampleCount)
        audiochunks = audioData[start:end]
        maxchunksVolume = getMaxVolume(audiochunks) / maxAudioVolume
        if(maxchunksVolume >= LOUD_THRESHOLD):
            hasLoudAudio[i] = 2
        elif(maxchunksVolume >= silentT):
            hasLoudAudio[i] = 1

    chunks = [[0, 0, 0]]
    shouldIncludeFrame = np.zeros((audioFrameCount), dtype=np.uint8)
    for i in range(audioFrameCount):
        start = int(max(0, i-frameMargin))
        end = int(min(audioFrameCount, i+1+frameMargin))
        shouldIncludeFrame[i] = min(1, np.max(hasLoudAudio[start:end]))

        if(i >= 1 and shouldIncludeFrame[i] != shouldIncludeFrame[i-1]):
            chunks.append([chunks[-1][1], i, shouldIncludeFrame[i-1]])

    chunks.append([chunks[-1][1], audioFrameCount, shouldIncludeFrame[i-1]])
    chunks = chunks[1:]

    zooms = getZooms(chunks, audioFrameCount, hasLoudAudio, frameMargin)

    conwrite('')

    handleAudio(ffmpeg, tracks, CACHE, TEMP, silentT, frameMargin,
        SAMPLE_RATE, audioBit, verbose, SILENT_SPEED, VIDEO_SPEED, chunks, frameRate)

    splitVideo(ffmpeg, chunks, speeds, frameRate, zooms, samplesPerFrame,
        SAMPLE_RATE, audioData, extension, verbose)

    if(BACK_MUS is not None):
        from pydub import AudioSegment

        cmd = [ffmpeg, '-i', f'{TEMP}/new{BASE_TRAC}.wav', '-vn', '-ar', '44100', '-ac',
            '2', '-ab', '192k', '-f', 'mp3', f'{TEMP}/output.mp3']
        subprocess.call(cmd)

        vidSound = AudioSegment.from_file(f'{TEMP}/output.mp3')

        back = AudioSegment.from_file(BACK_MUS)
        if(len(back) > len(vidSound)):
            back = back[:len(vidSound)]

        def match_target_amplitude(back, vidSound, target):
            diff = back.dBFS - vidSound.dBFS
            change_in_dBFS = target - diff
            return back.apply_gain(change_in_dBFS)

        # Fade the background music out by 1 second.
        back = match_target_amplitude(back, vidSound, BACK_VOL).fade_out(1000)
        # Write edited audio
        back.export(f'{TEMP}/new{tracks}.wav', format='wav')

        if(not os.path.isfile(f'{TEMP}/new{tracks}.wav')):
            raise IOError(f'The new music audio file was not created.')

        tracks += 1

    if(KEEP_SEP):
        # Mux the video and audio so that there are still multiple audio tracks.
        cmd = [ffmpeg, '-y']
        if(HWACCEL is not None):
            cmd.extend(['-hwaccel', HWACCEL])
        for i in range(tracks):
            cmd.extend(['-i', f'{TEMP}/new{i}.wav'])
        cmd.extend(['-i', f'{TEMP}/output{extension}'])
        for i in range(tracks):
            cmd.extend(['-map', f'{i}:a:0'])
        cmd.extend(['-map', f'{tracks}:v:0','-c:v', 'copy', '-movflags', '+faststart',
            outFile])
        if(not verbose):
            cmd.extend(['-nostats', '-loglevel', '0'])
    else:
        if(tracks > 1):
            cmd = [ffmpeg]
            for i in range(tracks):
                cmd.extend(['-i', f'{TEMP}/new{i}.wav'])
            cmd.extend(['-filter_complex', f'amerge=inputs={tracks}', '-ac', '2',
                f'{TEMP}/newAudioFile.wav'])
            if(not verbose):
                cmd.extend(['-nostats', '-loglevel', '0'])
            subprocess.call(cmd)
        else:
            os.rename(f'{TEMP}/new0.wav', f'{TEMP}/newAudioFile.wav')

        cmd = [ffmpeg, '-y']
        if(HWACCEL is not None):
            cmd.extend(['-hwaccel', HWACCEL])
        cmd.extend(['-i', f'{TEMP}/newAudioFile.wav', '-i',
            f'{TEMP}/output{extension}', '-c:v', 'copy', '-movflags', '+faststart',
            outFile])
        if(not verbose):
            cmd.extend(['-nostats', '-loglevel', '0'])
    subprocess.call(cmd)

    with open(f'{TEMP}/Renames.txt', 'r') as f:
        renames = f.read().splitlines()
        for i in range(0, len(renames), 2):
            os.rename(renames[i+1], renames[i])

    # Create cache.txt to see if the created cache is usable for next time.
    if(BACK_MUS is not None):
        tracks -= 1
    file = open(f'{CACHE}/cache.txt', 'w')
    file.write(f'{vidFile}\n{frameRate}\n{fileSize}\n{tracks}\n{COMBINE_TRAC}\n')

    return outFile
