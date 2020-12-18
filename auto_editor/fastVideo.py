'''fastVideo.py'''

import numpy as np

# Included functions
from fastAudio import fastAudio
from usefulFunctions import ProgressBar, pipeToConsole, ffAddDebug

# Internal libraries
import subprocess
from shutil import move

def handleAudioTracks(ffmpeg, outFile, exportAsAudio, tracks, keepTracksSep,
    chunks, speeds, fps, temp, machineReadable, hideBar, log):
    import os

    log.checkType(tracks, 'tracks', int)
    log.checkType(outFile, 'outFile', str)

    for trackNum in range(tracks):
        fastAudio(f'{temp}/{trackNum}.wav', f'{temp}/new{trackNum}.wav', chunks,
            speeds, log, fps, machineReadable, hideBar)

        if(not os.path.isfile(f'{temp}/new{trackNum}.wav')):
            log.bug('Audio file not created.')

    if(exportAsAudio):
        if(keepTracksSep):
            log.warning("Audio files can't have multiple tracks.")

        if(tracks == 1):
            move(f'{temp}/0.wav', outFile)
            return None # Exit out early.

        cmd = [ffmpeg, '-y']
        for trackNum in range(tracks):
            cmd.extend(['-i', f'{temp}/{trackNum}.wav'])
        cmd.extend(['-filter_complex', f'amix=inputs={tracks}:duration=longest', outFile])
        log.debug(cmd)
        subprocess.call(cmd)
        return False
    return True

def muxVideo(ffmpeg, outFile, keepTracksSep, tracks, vbitrate, tune, preset, vcodec,
    crf, temp, log):

    def extender(cmd, vbitrate, tune, preset, outFile, isFFmpeg):
        if(vbitrate is None):
            cmd.extend(['-crf', crf])
        else:
            cmd.extend(['-b:v', vbitrate])
        if(tune != 'none'):
            cmd.extend(['-tune', tune])
        cmd.extend(['-preset', preset, '-movflags', '+faststart', '-strict', '-2',
            outFile])
        cmd = ffAddDebug(cmd, isFFmpeg)
        return cmd

    # Now mix new audio(s) and the new video.
    if(keepTracksSep):
        cmd = [ffmpeg, '-y']
        for i in range(tracks):
            cmd.extend(['-i', f'{temp}/new{i}.wav'])
        cmd.extend(['-i', f'{temp}/spedup.mp4'])
        for i in range(tracks):
            cmd.extend(['-map', f'{i}:a:0'])

        cmd.extend(['-map', f'{tracks}:v:0', '-c:v', vcodec])
        cmd = extender(cmd, vbitrate, tune, preset, outFile, log.is_ffmpeg)
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
        cmd = extender(cmd, vbitrate, tune, preset, outFile, log.is_ffmpeg)

    message = pipeToConsole(cmd)
    log.debug(message)

    if('Conversion failed!' in message):
        log.warning('The muxing/compression failed. '\
            'This may be a problem with your ffmpeg, your codec, or your bitrate.'\
            '\nTrying, again but not compressing.')
        cmd = [ffmpeg, '-y', '-i', f'{temp}/newAudioFile.wav', '-i',
            f'{temp}/spedup.mp4', '-c:v', 'copy', '-movflags', '+faststart',
            outFile]
        cmd = ffAddDebug(cmd, log.is_ffmpeg)
        subprocess.call(cmd)
    log.conwrite('')


def fastVideo(vidFile: str, chunks: list, includeFrame: np.ndarray, speeds: list,
    fps, machineReadable, hideBar, temp, log):

    import cv2

    cap = cv2.VideoCapture(vidFile)
    width = int(cap.get(cv2.CAP_PROP_FRAME_WIDTH))
    height = int(cap.get(cv2.CAP_PROP_FRAME_HEIGHT))
    fourcc = cv2.VideoWriter_fourcc(*'mp4v')

    out = cv2.VideoWriter(f'{temp}/spedup.mp4', fourcc, fps, (width, height))

    log.checkType(vidFile, 'vidFile', str)
    log.checkType(includeFrame, 'includeFrame', np.ndarray)

    if(speeds[0] == 99999 and speeds[1] != 99999):
        totalFrames = int(np.where(includeFrame == True)[0][-1])
        cframe = int(np.where(includeFrame == True)[0][0])
    elif(speeds[0] != 99999 and speeds[1] == 99999):
        totalFrames = int(np.where(includeFrame == False)[0][-1])
        cframe = int(np.where(includeFrame == False)[0][0])
    else:
        totalFrames = chunks[len(chunks) - 1][1]
        cframe = 0

    starting = cframe
    cap.set(cv2.CAP_PROP_POS_FRAMES, cframe)
    remander = 0
    framesWritten = 0

    videoProgress = ProgressBar(totalFrames - starting, 'Creating new video',
        machineReadable, hideBar)

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

        videoProgress.tick(cframe - starting)
    log.debug(f'\n   - Frames Written: {framesWritten}')
    log.debug(f'   - Starting: {starting}')
    log.debug(f'   - Total Frames: {totalFrames}')

    if(log.is_debug):
        log.debug('Writing the output file.')
    else:
        log.conwrite('Writing the output file.')

    cap.release()
    out.release()
    cv2.destroyAllWindows()
