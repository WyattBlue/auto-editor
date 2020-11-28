'''fastVideo.py'''

# External libraries
import cv2
import numpy as np

# Included functions
from fastAudio import fastAudio
from usefulFunctions import progressBar, conwrite

# Internal libraries
import os
import time
import subprocess
from shutil import move

def fastVideo(ffmpeg: str, vidFile: str, outFile: str, chunks: list, includeFrame:
    np.ndarray, speeds: list, tracks: int, abitrate: str, samplerate, temp: str,
    keepTracksSep: bool, vcodec, fps: float, exportAsAudio: bool, vbitrate, preset,
    tune, log):

    if(not os.path.isfile(vidFile)):
        log.error('fastVideo.py could not find file: ' + vidFile)

    cap = cv2.VideoCapture(vidFile)
    width = int(cap.get(cv2.CAP_PROP_FRAME_WIDTH))
    height = int(cap.get(cv2.CAP_PROP_FRAME_HEIGHT))
    fourcc = cv2.VideoWriter_fourcc(*'mp4v')

    for trackNum in range(tracks):
        fastAudio(ffmpeg, f'{temp}/{trackNum}.wav', f'{temp}/new{trackNum}.wav', chunks,
            speeds, abitrate, samplerate, False, temp, log, fps=fps)

        if(not os.path.isfile(f'{temp}/new{trackNum}.wav')):
            log.error('Audio file not created.')

    if(exportAsAudio):
        if(keepTracksSep):
            log.warning("Audio files can't have multiple tracks.")

        if(tracks == 1):
            move(f'{temp}/0.wav', outFile)
            return None # Exit out early.

        cmd = ['ffmpeg', '-y']
        for trackNum in range(tracks):
            cmd.extend(['-i', f'{temp}/{trackNum}.wav'])
        cmd.extend(['-filter_complex', f'amix=inputs={tracks}:duration=longest', outFile])
        log.debug(cmd)
        subprocess.call(cmd)
        return None

    out = cv2.VideoWriter(f'{temp}/spedup.mp4', fourcc, fps, (width, height))
    if(speeds[0] == 99999 and speeds[1] != 99999):
        totalFrames = int(np.where(includeFrame == True)[0][-1])
        cframe = int(np.where(includeFrame == True)[0][0])
    elif(speeds[0] != 99999 and speeds[1] == 99999):
        totalFrames = int(np.where(includeFrame == False)[0][-1])
        cframe = int(np.where(includeFrame == False)[0][0])
    else:
        totalFrames = chunks[len(chunks) - 1][1]
        cframe = 0

    beginTime = time.time()
    starting = cframe
    cap.set(cv2.CAP_PROP_POS_FRAMES, cframe)
    remander = 0
    framesWritten = 0

    while cap.isOpened():
        ret, frame = cap.read()
        if(not ret or cframe > totalFrames):
            break

        cframe = int(cap.get(cv2.CAP_PROP_POS_FRAMES)) # current frame
        try:
            state = includeFrame[cframe]
        except IndexError:
            state = False

        mySpeed = speeds[state]

        if(mySpeed != 99999):
            doIt = (1 / mySpeed) + remander
            for __ in range(int(doIt)):
                out.write(frame)
                framesWritten += 1
            remander = doIt % 1

        progressBar(cframe - starting, totalFrames - starting, beginTime,
            title='Creating new video')

    log.debug(f'\n   - Frames Written: {framesWritten}')
    log.debug(f'   - Starting: {starting}')
    log.debug(f'   - Total Frames: {totalFrames}')

    if(log.is_debug):
        log.debug('Writing the output file.')
    else:
        conwrite('Writing the output file.')

    cap.release()
    out.release()
    cv2.destroyAllWindows()

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
        cmd.extend(['-preset', preset, '-movflags', '+faststart', '-strict', '-2', outFile])
        if(log.is_ffmpeg):
            cmd.extend(['-hide_banner'])
        else:
            cmd.extend(['-nostats', '-loglevel', '8'])
    else:
        # Merge all the audio tracks into one.
        if(tracks > 1):
            cmd = [ffmpeg]
            for i in range(tracks):
                cmd.extend(['-i', f'{temp}/new{i}.wav'])
            cmd.extend(['-filter_complex', f'amerge=inputs={tracks}', '-ac', '2',
                f'{temp}/newAudioFile.wav'])
            if(log.is_ffmpeg):
                cmd.extend(['-hide_banner'])
            else:
                cmd.extend(['-nostats', '-loglevel', '8'])
            subprocess.call(cmd)
        else:
            move(f'{temp}/new0.wav', f'{temp}/newAudioFile.wav')

        cmd = [ffmpeg, '-y', '-i', f'{temp}/newAudioFile.wav', '-i',
            f'{temp}/spedup.mp4', '-c:v', vcodec]
        if(vbitrate is None):
            cmd.extend(['-crf', '15'])
        else:
            cmd.extend(['-b:v', vbitrate])
        if(tune != 'none'):
            cmd.extend(['-tune', tune])
        cmd.extend(['-preset', preset, '-movflags', '+faststart', '-strict', '-2', outFile])
        if(log.is_ffmpeg):
            cmd.extend(['-hide_banner'])
        else:
            cmd.extend(['-nostats', '-loglevel', '8'])

    def pipeToConsole(myCommands):
        process = subprocess.Popen(myCommands, stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT)
        stdout, __ = process.communicate()
        return stdout.decode()

    message = pipeToConsole(cmd)
    log.debug(message)

    if('Conversion failed!' in message):
        log.warning('The muxing/compression failed. '\
            'This may be a problem with your ffmpeg, your codec, or your bitrate.'\
            '\nTrying, again but not compressing.')
        cmd = [ffmpeg, '-y', '-i', f'{temp}/newAudioFile.wav', '-i',
            f'{temp}/spedup.mp4', '-c:v', 'copy', '-movflags', '+faststart',
            outFile]
        if(log.is_ffmpeg):
            cmd.extend(['-hide_banner'])
        else:
            cmd.extend(['-nostats', '-loglevel', '8'])
        subprocess.call(cmd)
    conwrite('')
