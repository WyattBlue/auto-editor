'''fastVideo.py'''

# External libraries
import cv2
import numpy as np
from audiotsm2 import phasevocoder

# Included functions
from fastAudio import fastAudio
from usefulFunctions import getAudioChunks, progressBar, conwrite

# Internal libraries
import os
import sys
import time
import tempfile
import subprocess
from shutil import rmtree, move

def fastVideo(ffmpeg, vidFile, outFile, chunks, includeFrame, speeds, tracks, abitrate,
    samplerate, debug, temp, keepTracksSep, vcodec, fps, exportAsAudio, vbitrate,
    preset, tune, log):

    if(not os.path.isfile(vidFile)):
        log.error('Could not find file ' + vidFile)

    cap = cv2.VideoCapture(vidFile)
    width = int(cap.get(cv2.CAP_PROP_FRAME_WIDTH))
    height = int(cap.get(cv2.CAP_PROP_FRAME_HEIGHT))
    fourcc = cv2.VideoWriter_fourcc(*'mp4v')

    for trackNum in range(tracks):
        fastAudio(ffmpeg, f'{temp}/{trackNum}.wav', f'{temp}/new{trackNum}.wav', chunks,
            speeds, abitrate, samplerate, debug, False, log, fps=fps)

        if(not os.path.isfile(f'{temp}/new{trackNum}.wav')):
            log.error('Audio file not created.')

    if(exportAsAudio):
        if(keepTracksSep):
            log.warning("Audio files can't have multiple tracks.")
        else:
            pass
            # TODO: combine all the audio tracks
        move(f'{temp}/0.wav', outFile)
        return None

    out = cv2.VideoWriter(f'{temp}/spedup.mp4', fourcc, fps, (width, height))

    totalFrames = np.where(includeFrame == 1)[0][-1]

    beginTime = time.time()

    remander = 0
    framesWritten = 0
    cframe = 0

    while cap.isOpened():
        #cap.set()
        ret, frame = cap.read()
        if(not ret or cframe > totalFrames):
            break

        cframe = int(cap.get(cv2.CAP_PROP_POS_FRAMES)) # current frame
        state = includeFrame[cframe]
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

    log.debug('Frames written ' + str(framesWritten))

    # Now mix new audio(s) and the new video.
    if(keepTracksSep):
        cmd = [ffmpeg, '-y']
        for i in range(tracks):
            cmd.extend(['-i', f'{temp}/new{i}.wav'])
        cmd.extend(['-i', f'{temp}/spedup.mp4'])
        for i in range(tracks):
            cmd.extend(['-map', f'{i}:a:0'])

        cmd.extend(['-map', f'{tracks}:v:0', '-c:v', vcodec])
        if(vbitrate is None):
            cmd.extend(['-crf', '15'])
        else:
            cmd.extend(['-b:v', vbitrate])
        if(tune != 'none'):
            cmd.extend(['-tune', tune])
        cmd.extend(['-preset', preset, '-movflags', '+faststart', outFile])
        if(debug):
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
            if(debug):
                cmd.extend(['-hide_banner'])
            else:
                cmd.extend(['-nostats', '-loglevel', '0'])
            subprocess.call(cmd)
        else:
            move(f'{temp}/new0.wav', f'{temp}/newAudioFile.wav')


        def pipeToConsole(myCommands):
            process = subprocess.Popen(myCommands, stdout=subprocess.PIPE,
                stderr=subprocess.STDOUT)
            stdout, __ = process.communicate()
            return stdout.decode()

        cmd = [ffmpeg, '-y', '-i', f'{temp}/newAudioFile.wav', '-i',
            f'{temp}/spedup.mp4', '-c:v', vcodec]
        if(vbitrate is None):
            cmd.extend(['-crf', '15'])
        else:
            cmd.extend(['-b:v', vbitrate])
        if(tune != 'none'):
            cmd.extend(['-tune', tune])
        cmd.extend(['-preset', preset, '-movflags', '+faststart', outFile, '-hide_banner'])

        log.debug(cmd)
        message = pipeToConsole(cmd)
        log.debug('')
        log.debug(message)

        if('Conversion failed!' in message):
            log.warning('The muxing/compression failed. '\
                'This may be a problem with your ffmpeg, your codec, or your bitrate.'\
                '\nTrying, again but using the "copy" video codec.')
            cmd = [ffmpeg, '-y', '-i', f'{temp}/newAudioFile.wav', '-i',
                f'{temp}/spedup.mp4', '-c:v', 'copy', '-movflags', '+faststart',
                outFile, '-nostats', '-loglevel', '0']
            subprocess.call(cmd)
        log.debug(cmd)

    conwrite('')
