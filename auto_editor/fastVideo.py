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

def muxVideo(ffmpeg, outFile, keepTracksSep, tracks, vbitrate, tune, preset,
    acodec, crf, temp, log):

    def extender(cmd, vbitrate, tune, preset, acodec, outFile, isFFmpeg):
        if(acodec is not None):
            cmd.extend(['-c:a', acodec])
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

        cmd.extend(['-map', f'{tracks}:v:0', '-c:v', 'copy'])
        cmd = extender(cmd, vbitrate, tune, preset, acodec, outFile, log.is_ffmpeg)
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
            f'{temp}/spedup.mp4', '-c:v', 'copy']
        cmd = extender(cmd, vbitrate, tune, preset, acodec, outFile, log.is_ffmpeg)

    log.debug(cmd)
    message = pipeToConsole(cmd)
    log.debug(message)
    log.conwrite('')


def fastVideo(vidFile: str, chunks: list, speeds: list, codec, machineReadable,
    hideBar, temp, log):

    import av

    input_ = av.open(vidFile)
    inputVideoStream = input_.streams.video[0]
    inputVideoStream.thread_type = 'AUTO'

    width = inputVideoStream.width
    height = inputVideoStream.height
    pix_fmt = inputVideoStream.pix_fmt
    averageFramerate = float(inputVideoStream.average_rate)

    totalFrames = chunks[len(chunks) - 1][1]
    videoProgress = ProgressBar(totalFrames, 'Creating new video',
        machineReadable, hideBar)

    process2 = subprocess.Popen(['ffmpeg', '-y', '-f', 'rawvideo', '-vcodec',
        'rawvideo', '-pix_fmt', pix_fmt, '-s', f'{width}*{height}',
        '-framerate', f'{averageFramerate}', '-i', '-', '-pix_fmt', pix_fmt,
        '-vcodec', codec, '-qscale:v', '3', f'{temp}/spedup.mp4'],
        stdin=subprocess.PIPE, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)

    inputEquavalentNumber = 0
    outputEquavalentNumber = 0

    index = 0
    chunk = chunks.pop(0)
    for packet in input_.demux(inputVideoStream):
        for frame in packet.decode():
            index += 1
            if(len(chunks) > 0 and index >= chunk[1] + 1):
                chunk = chunks.pop(0)

            if(speeds[chunk[2]] != 99999):
                inputEquavalentNumber += (1 / speeds[chunk[2]])

            while inputEquavalentNumber > outputEquavalentNumber:
                in_bytes = frame.to_ndarray().astype(np.uint8).tobytes()
                process2.stdin.write(in_bytes)
                outputEquavalentNumber += 1

            videoProgress.tick(index - 1)
    process2.stdin.close()
    process2.wait()

    if(log.is_debug):
        log.debug('Writing the output file.')
    else:
        log.conwrite('Writing the output file.')



