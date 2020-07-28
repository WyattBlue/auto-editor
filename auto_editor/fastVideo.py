'''fastVideo.py'''

# External libraries
import numpy as np
from audiotsm2 import phasevocoder

# Included functions
from fastAudio import fastAudio
from usefulFunctions import getAudioChunks, progressBar, vidTracks, conwrite
from wavfile import read, write

# Internal libraries
import os
import sys
import time
import tempfile
import subprocess
from shutil import rmtree

def fastVideo(ffmpeg, videoFile, outFile, silentT, frameMargin, SAMPLE_RATE,
    AUD_BITRATE, verbose, videoSpeed, silentSpeed, cutByThisTrack, keepTracksSep):

    print('Running from fastVideo.py')

    import cv2

    conwrite('Reading audio.')

    if(not os.path.isfile(videoFile)):
        print('Could not find file:', videoFile)
        sys.exit(1)

    TEMP = tempfile.mkdtemp()
    speeds = [silentSpeed, videoSpeed]

    cap = cv2.VideoCapture(videoFile)
    width = int(cap.get(cv2.CAP_PROP_FRAME_WIDTH))
    height = int(cap.get(cv2.CAP_PROP_FRAME_HEIGHT))
    fourcc = cv2.VideoWriter_fourcc(*'mp4v')
    fps = cap.get(cv2.CAP_PROP_FPS)

    tracks = vidTracks(videoFile, ffmpeg)

    if(cutByThisTrack >= tracks):
        print("Error! You choose a track that doesn't exist.")
        print(f'There are only {tracks-1} tracks. (starting from 0)')
        sys.exit(1)

    for trackNumber in range(tracks):
        cmd = [ffmpeg, '-i', videoFile, '-ab', AUD_BITRATE, '-ac', '2', '-ar',
        str(SAMPLE_RATE),'-map', f'0:a:{trackNumber}', f'{TEMP}/{trackNumber}.wav']
        if(verbose):
            cmd.extend(['-hide_banner'])
        else:
            cmd.extend(['-nostats', '-loglevel', '0'])
        subprocess.call(cmd)


    sampleRate, audioData = read(f'{TEMP}/{cutByThisTrack}.wav')
    chunks = getAudioChunks(audioData, sampleRate, fps, silentT, 2, frameMargin)

    # Handle the Audio
    for trackNumber in range(tracks):
        fastAudio(ffmpeg, f'{TEMP}/{trackNumber}.wav', f'{TEMP}/new{trackNumber}.wav',
            silentT, frameMargin, SAMPLE_RATE, AUD_BITRATE, verbose, silentSpeed,
            videoSpeed, False, chunks=chunks, fps=fps)

        if(not os.path.isfile(f'{TEMP}/new{trackNumber}.wav')):
            print('Error! Audio file not created.')
            sys.exit(1)

    out = cv2.VideoWriter(f'{TEMP}/spedup.mp4', fourcc, fps, (width, height))
    totalFrames = chunks[len(chunks) - 1][1]
    beginTime = time.time()

    remander = 0
    framesWritten = 0

    while cap.isOpened():
        ret, frame = cap.read()
        if(not ret):
            break

        cframe = int(cap.get(cv2.CAP_PROP_POS_FRAMES)) # current frame
        state = None
        for chunk in chunks:
            if(cframe >= chunk[0] and cframe <= chunk[1]):
                state = chunk[2]
                break

        if(state is not None):
            mySpeed = speeds[state]

            if(mySpeed != 99999):
                doIt = (1 / mySpeed) + remander
                for __ in range(int(doIt)):
                    out.write(frame)
                    framesWritten += 1
                remander = doIt % 1

        progressBar(cframe, totalFrames, beginTime, title='Creating new video')

    conwrite('Writing the output file.')

    cap.release()
    out.release()
    cv2.destroyAllWindows()

    if(verbose):
        print('Frames written', framesWritten)

    # Now mix new audio(s) and the new video.
    if(keepTracksSep):
        cmd = [ffmpeg, '-y']
        for i in range(tracks):
            cmd.extend(['-i', f'{TEMP}/new{i}.wav'])
        cmd.extend(['-i', f'{TEMP}/spedup.mp4'])
        for i in range(tracks):
            cmd.extend(['-map', f'{i}:a:0'])
        cmd.extend(['-map', f'{tracks}:v:0','-c:v', 'copy', '-movflags', '+faststart',
            outFile])
        if(verbose):
            cmd.extend(['-hide_banner'])
        else:
            cmd.extend(['-nostats', '-loglevel', '0'])
    else:
        # Merge all the audio tracks into one.
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

        cmd = [ffmpeg, '-y', '-i', f'{TEMP}/newAudioFile.wav', '-i',
            f'{TEMP}/spedup.mp4', '-c:v', 'copy', '-movflags', '+faststart',
            outFile]
        if(verbose):
            cmd.extend(['-hide_banner'])
        else:
            cmd.extend(['-nostats', '-loglevel', '0'])
        subprocess.call(cmd)

    rmtree(TEMP)
    conwrite('')
