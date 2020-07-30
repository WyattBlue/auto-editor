'''fastVideo.py'''

# External libraries
import cv2
import numpy as np
from audiotsm2 import phasevocoder

# Included functions
from fastAudio import fastAudio
from usefulFunctions import getAudioChunks, progressBar, vidTracks, conwrite

# Internal libraries
import os
import sys
import time
import tempfile
import subprocess
from shutil import rmtree

def fastVideo(ffmpeg, videoFile, outFile, chunks, speeds, tracks, bitrate, sampleRate,
    verbose, temp, cache, keepTracksSep):

    print('Running from fastVideo.py')

    cap = cv2.VideoCapture(videoFile)
    width = int(cap.get(cv2.CAP_PROP_FRAME_WIDTH))
    height = int(cap.get(cv2.CAP_PROP_FRAME_HEIGHT))
    fourcc = cv2.VideoWriter_fourcc(*'mp4v')
    fps = cap.get(cv2.CAP_PROP_FPS)

    for trackNum in range(tracks):
        fastAudio(ffmpeg, f'{cache}/{trackNum}.wav', f'{temp}/new{trackNum}.wav', chunks,
            speeds, bitrate, sampleRate, verbose, False, fps=fps)

        if(not os.path.isfile(f'{temp}/new{trackNum}.wav')):
            print('Error! Audio file not created.')
            sys.exit(1)

    out = cv2.VideoWriter(f'{temp}/spedup.mp4', fourcc, fps, (width, height))
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
            cmd.extend(['-i', f'{temp}/new{i}.wav'])
        cmd.extend(['-i', f'{temp}/spedup.mp4'])
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
                cmd.extend(['-i', f'{temp}/new{i}.wav'])
            cmd.extend(['-filter_complex', f'amerge=inputs={tracks}', '-ac', '2',
                f'{temp}/newAudioFile.wav'])
            if(verbose):
                cmd.extend(['-hide_banner'])
            else:
                cmd.extend(['-nostats', '-loglevel', '0'])
            subprocess.call(cmd)
        else:
            os.rename(f'{temp}/new0.wav', f'{temp}/newAudioFile.wav')

        cmd = [ffmpeg, '-y', '-i', f'{temp}/newAudioFile.wav', '-i',
            f'{temp}/spedup.mp4', '-c:v', 'copy', '-movflags', '+faststart',
            outFile]
        if(verbose):
            cmd.extend(['-hide_banner'])
        else:
            cmd.extend(['-nostats', '-loglevel', '0'])
        subprocess.call(cmd)

    conwrite('')
