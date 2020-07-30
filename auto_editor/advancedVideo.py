'''advancedVideo.py'''

import numpy as np

import os
import sys
import math
import subprocess

from fastAudio import fastAudio
from splitVid import splitVideo
from usefulFunctions import getMaxVolume, conwrite


def getFrameRate(ffmpeg, path):
    from re import search

    process = subprocess.Popen([ffmpeg, '-i', path],
        stdout=subprocess.PIPE, stderr=subprocess.STDOUT)
    stdout, __ = process.communicate()
    output = stdout.decode()
    matchDict = search(r'\s(?P<fps>[\d\.]+?)\stbr', output).groupdict()
    return float(matchDict['fps'])


def getZooms(chunks, audioFrameCount, hasLoudAudio, frameMargin, fps):
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
                p = int(fps / 3)
                for x in range(1, p + 1):
                    trans = a * math.sin((math.pi/(2*p)) * x + (2*math.pi))
                    zooms[i+x-3] = 1 + trans
                hold = True
                endZoom = i + x
                continue
        if(hold):
            zooms[i-1] = 1.2
            if(len(shouldIncludeFrame) - i > int(fps * 1.5) and
                shouldIncludeFrame[i] == 1 and i-endZoom > int(fps/2)):
                for chunk in chunks:
                    if chunk[0] == i and chunk[2] == 1:
                        hold = False
    return zooms


def advancedVideo(ffmpeg, vidFile, outFile, chunks, speeds, tracks, silentT, zoomT, frameMargin,
    samplerate, audioBit, keepSep, backMusic, backVolume, debug, hwaccel, temp, cache,
    audioData, fps):
    """
    This method splits the video into jpegs which allows for more advanced effects.
    As of 20w31a, zooming is the only unique effect.
    """
    if(not os.path.isfile(vidFile)):
        print('advancedVideo.py: Could not find file', vidFile)
        sys.exit(1)

    print('Running from advancedVideo.py')

    conwrite('Splitting video into jpgs. (This can take a while)')
    cmd = [ffmpeg]
    if(hwaccel is not None):
        cmd.extend(['-hwaccel', hwaccel])
    cmd.extend(['-i', vidFile, '-qscale:v', '1', f'{cache}/frame%06d.jpg'])
    if(debug):
        cmd.extend(['-hide_banner'])
    else:
        cmd.extend(['-nostats', '-loglevel', '0'])
    subprocess.call(cmd)

    maxAudioVolume = getMaxVolume(audioData)

    samplesPerFrame = samplerate / fps
    audioSampleCount = audioData.shape[0]
    audioFrameCount = int(math.ceil(audioSampleCount / samplesPerFrame))
    hasLoudAudio = np.zeros((audioFrameCount), dtype=np.uint8)
    for i in range(audioFrameCount):
        start = int(i * samplesPerFrame)
        end = min(int((i+1) * samplesPerFrame), audioSampleCount)
        threshold = getMaxVolume(audioData[start:end]) / maxAudioVolume
        if(threshold >= zoomT):
            hasLoudAudio[i] = 2
        elif(threshold >= silentT):
            hasLoudAudio[i] = 1

    zooms = getZooms(chunks, audioFrameCount, hasLoudAudio, frameMargin, fps)

    # Handle audio.
    for i in range(tracks):
        fastAudio(ffmpeg, f'{cache}/{i}.wav', f'{temp}/new{i}.wav', chunks,
            speeds, audioBit, samplerate, debug, False, fps=fps)

    ext = vidFile[vidFile.rfind('.'):]
    splitVideo(ffmpeg, chunks, speeds, fps, zooms, samplesPerFrame,
        samplerate, audioData, ext, debug, temp, cache)

    if(backMusic is not None):
        from pydub import AudioSegment

        cmd = [ffmpeg, '-i', f'{temp}/new0.wav', '-vn', '-ar', '44100', '-ac',
            '2', '-ab', '192k', '-f', 'mp3', f'{temp}/output.mp3']
        subprocess.call(cmd)

        vidSound = AudioSegment.from_file(f'{temp}/output.mp3')

        back = AudioSegment.from_file(backMusic)
        if(len(back) > len(vidSound)):
            back = back[:len(vidSound)]

        def match_target_amplitude(back, vidSound, target):
            diff = back.dBFS - vidSound.dBFS
            change_in_dBFS = target - diff
            return back.apply_gain(change_in_dBFS)

        # Fade the background music out by 1 second.
        back = match_target_amplitude(back, vidSound, backVolume).fade_out(1000)
        back.export(f'{temp}/new{tracks}.wav', format='wav')

        if(not os.path.isfile(f'{temp}/new{tracks}.wav')):
            print('Error! The new music audio file was not created.')
            sys.exit(1)
        tracks += 1

    if(keepSep):
        # Mux the video and audio so that there are still multiple audio tracks.
        cmd = [ffmpeg, '-y']
        if(hwaccel is not None):
            cmd.extend(['-hwaccel', hwaccel])
        for i in range(tracks):
            cmd.extend(['-i', f'{temp}/new{i}.wav'])
        cmd.extend(['-i', f'{temp}/output{ext}'])
        for i in range(tracks):
            cmd.extend(['-map', f'{i}:a:0'])
        cmd.extend(['-map', f'{tracks}:v:0','-c:v', 'copy', '-movflags', '+faststart',
            outFile])
        if(debug):
            cmd.extend(['-hide_banner'])
        else:
            cmd.extend(['-nostats', '-loglevel', '0'])
        subprocess.call(cmd)
    else:
        if(tracks > 1):
            cmd = [ffmpeg]
            for i in range(tracks):
                cmd.extend(['-i', f'{temp}/new{i}.wav'])
            cmd.extend(['-filter_complex', f'amerge=inputs={tracks}', '-ac', '2',
                f'{temp}/newAudioFile.wav'])
            if(debug):
                cmd.extend(['-hide_banner'])
            else:
                cmd.extend(['-nostats', '-loglevel', '0'])
            subprocess.call(cmd)
        else:
            os.rename(f'{temp}/new0.wav', f'{temp}/newAudioFile.wav')

        cmd = [ffmpeg, '-y']
        if(hwaccel is not None):
            cmd.extend(['-hwaccel', hwaccel])
        cmd.extend(['-i', f'{temp}/newAudioFile.wav', '-i',
            f'{temp}/output{ext}', '-c:v', 'copy', '-movflags', '+faststart',
            outFile])
        if(debug):
            cmd.extend(['-hide_banner'])
        else:
            cmd.extend(['-nostats', '-loglevel', '0'])
        subprocess.call(cmd)

    with open(f'{temp}/Renames.txt', 'r') as f:
        renames = f.read().splitlines()
        for i in range(0, len(renames), 2):
            os.rename(renames[i+1], renames[i])

    conwrite('')
