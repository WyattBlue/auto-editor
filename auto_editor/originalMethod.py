'''originalMethod.py'''

import numpy as np

import os
import sys
import math
import subprocess
import tempfile
from shutil import move, rmtree

from fastAudio import fastAudio
from originalVid import splitVideo
from wavfile import read, write
from usefulFunctions import vidTracks, getMaxVolume, conwrite, createCache

def handleAudio(ffmpeg, tracks, cache, TEMP, silentT, frameMargin, SAMPLE_RATE, audioBit,
    verbose, silentSpeed, videoSpeed, chunks, frameRate):
    for i in range(tracks):
        newCuts = fastAudio(ffmpeg, f'{cache}/{i}.wav', f'{TEMP}/new{i}.wav', silentT,
            frameMargin, SAMPLE_RATE, audioBit, verbose, silentSpeed, videoSpeed,
            False, chunks=chunks, fps=frameRate)
    return newCuts


def getFrameRate(ffmpeg, path):
    from re import search

    process = subprocess.Popen([ffmpeg, '-i', path],
        stdout=subprocess.PIPE, stderr=subprocess.STDOUT)
    stdout, __ = process.communicate()
    output = stdout.decode()
    matchDict = search(r'\s(?P<fps>[\d\.]+?)\stbr', output).groupdict()
    return float(matchDict['fps'])


def getZooms(chunks, audioFrameCount, hasLoudAudio, frameMargin, frameRate):
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


def originalMethod(ffmpeg, vidFile, outFile, frameMargin, silentT, zoomT, SAMPLE_RATE,
    audioBit, silentSpeed, videoSpeed, keepSep, backMusic, backVolume, newTrack,
    baseTrack, combineTrack, verbose, hwaccel, cache):
    """
    This method splits the video into jpegs which allows for more advanced effects.
    As of 20w31a, zooming is the only unique effect.
    """

    print('Running from originalMethod.py')

    speeds = [silentSpeed, videoSpeed]
    TEMP = tempfile.mkdtemp()

    if(not os.path.isfile(vidFile)):
        print('Could not find file:', vidFile)
        sys.exit(1)

    fileSize = os.stat(vidFile).st_size

    try:
        frameRate = getFrameRate(ffmpeg, vidFile)
    except AttributeError:
        print('Warning! frame rate detection has failed, defaulting to 30.')
        frameRate = 30

    SKIP, tracks = checkCache(cache, vidFile, frameRate)

    if(not SKIP):
        # Videos can have more than one audio track os we need to extract them all.
        tracks = vidTracks(vidFile, ffmpeg)

        if(baseTrack >= tracks):
            print("Error! You choose a track that doesn't exist.")
            print(f'There are only {tracks-1} tracks. (starting from 0)')
            sys.exit(1)
        for trackNum in range(tracks):
            cmd = [ffmpeg]
            if(hwaccel is not None):
                cmd.extend(['-hwaccel', hwaccel])
            cmd.extend(['-i', vidFile, '-map', f'0:a:{trackNum}',
                f'{cache}/{trackNum}.wav'])
            if(not verbose):
                cmd.extend(['-nostats', '-loglevel', '0'])
            subprocess.call(cmd)

            if(combineTrack):
                from pydub import AudioSegment

                for i in range(tracks):
                    if(not os.path.isfile(f'{cache}/{i}.wav')):
                        print('Error! Audio file(s) could not be found.')
                        sys.exit(1)
                    if(i == 0):
                        allAuds = AudioSegment.from_file(f'{cache}/{i}.wav')
                    else:
                        newTrack = AudioSegment.from_file(f'{cache}/{i}.wav')
                        allAuds = allAuds.overlay(newTrack)
                allAuds.export(f'{cache}/0.wav', format='wav')
                tracks = 1

            # Now deal with the video.
            conwrite('Splitting video into jpgs. (This can take a while)')
            cmd = [ffmpeg]
            if(hwaccel is not None):
                cmd.extend(['-hwaccel', hwaccel])
            cmd.extend(['-i', vidFile, '-qscale:v', '1', f'{cache}/frame%06d.jpg'])
            if(verbose):
                cmd.extend(['-hide_banner'])
            else:
                cmd.extend(['-nostats', '-loglevel', '0'])
            subprocess.call(cmd)

    if(newTrack is None):
        sampleRate, audioData = read(f'{cache}/{baseTrack}.wav')
    else:
        cmd = [ffmpeg, '-i', newTrack, '-ac', '2', '-ar', str(SAMPLE_RATE), '-vn',
            f'{TEMP}/newTrack.wav']
        if(verbose):
            cmd.extend(['-hide_banner'])
        else:
            cmd.extend(['-nostats', '-loglevel', '0'])
        subprocess.call(cmd)

        sampleRate, audioData = read(f'{TEMP}/newTrack.wav')
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
        if(maxchunksVolume >= zoomT):
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

    zooms = getZooms(chunks, audioFrameCount, hasLoudAudio, frameMargin, frameRate)

    handleAudio(ffmpeg, tracks, cache, TEMP, silentT, frameMargin,
        SAMPLE_RATE, audioBit, verbose, silentSpeed, videoSpeed, chunks, frameRate)

    splitVideo(ffmpeg, chunks, speeds, frameRate, zooms, samplesPerFrame,
        SAMPLE_RATE, audioData, extension, verbose, TEMP, cache)

    if(backMusic is not None):
        from pydub import AudioSegment

        cmd = [ffmpeg, '-i', f'{TEMP}/new{baseTrack}.wav', '-vn', '-ar', '44100', '-ac',
            '2', '-ab', '192k', '-f', 'mp3', f'{TEMP}/output.mp3']
        subprocess.call(cmd)

        vidSound = AudioSegment.from_file(f'{TEMP}/output.mp3')

        back = AudioSegment.from_file(backMusic)
        if(len(back) > len(vidSound)):
            back = back[:len(vidSound)]

        def match_target_amplitude(back, vidSound, target):
            diff = back.dBFS - vidSound.dBFS
            change_in_dBFS = target - diff
            return back.apply_gain(change_in_dBFS)

        # Fade the background music out by 1 second.
        back = match_target_amplitude(back, vidSound, backVolume).fade_out(1000)
        back.export(f'{TEMP}/new{tracks}.wav', format='wav')

        if(not os.path.isfile(f'{TEMP}/new{tracks}.wav')):
            print('Error! The new music audio file was not created.')
            sys.exit(1)
        tracks += 1

    if(keepSep):
        # Mux the video and audio so that there are still multiple audio tracks.
        cmd = [ffmpeg, '-y']
        if(hwaccel is not None):
            cmd.extend(['-hwaccel', hwaccel])
        for i in range(tracks):
            cmd.extend(['-i', f'{TEMP}/new{i}.wav'])
        cmd.extend(['-i', f'{TEMP}/output{extension}'])
        for i in range(tracks):
            cmd.extend(['-map', f'{i}:a:0'])
        cmd.extend(['-map', f'{tracks}:v:0','-c:v', 'copy', '-movflags', '+faststart',
            outFile])
        if(verbose):
            cmd.extend(['-hide_banner'])
        else:
            cmd.extend(['-nostats', '-loglevel', '0'])
        subprocess.call(cmd)
    else:
        if(tracks > 1):
            cmd = [ffmpeg]
            for i in range(tracks):
                cmd.extend(['-i', f'{TEMP}/new{i}.wav'])
            cmd.extend(['-filter_complex', f'amerge=inputs={tracks}', '-ac', '2',
                f'{TEMP}/newAudioFile.wav'])
            if(verbose):
                cmd.extend(['-hide_banner'])
            else:
                cmd.extend(['-nostats', '-loglevel', '0'])
            subprocess.call(cmd)
        else:
            os.rename(f'{TEMP}/new0.wav', f'{TEMP}/newAudioFile.wav')

        cmd = [ffmpeg, '-y']
        if(hwaccel is not None):
            cmd.extend(['-hwaccel', hwaccel])
        cmd.extend(['-i', f'{TEMP}/newAudioFile.wav', '-i',
            f'{TEMP}/output{extension}', '-c:v', 'copy', '-movflags', '+faststart',
            outFile])
        if(verbose):
            cmd.extend(['-hide_banner'])
        else:
            cmd.extend(['-nostats', '-loglevel', '0'])
        subprocess.call(cmd)

    with open(f'{TEMP}/Renames.txt', 'r') as f:
        renames = f.read().splitlines()
        for i in range(0, len(renames), 2):
            os.rename(renames[i+1], renames[i])

    rmtree(TEMP)

    # Create cache.txt to see if the created cache is usable for next time.
    if(backMusic is not None):
        tracks -= 1

    createCache(cache, vidFile, frameRate, tracks)
    conwrite('')
