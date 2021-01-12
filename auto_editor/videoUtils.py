'''videoUtils.py'''

from usefulFunctions import ffAddDebug, pipeToConsole

import subprocess
from shutil import move

def handleAudioTracks(ffmpeg, outFile, args, tracks, chunks, speeds, fps, temp, log) -> bool:
    import os
    from fastAudio import fastAudio

    log.checkType(tracks, 'tracks', int)
    log.checkType(outFile, 'outFile', str)

    for trackNum in range(tracks):
        fastAudio(f'{temp}/{trackNum}.wav', f'{temp}/new{trackNum}.wav', chunks,
            speeds, log, fps, args.machine_readable_progress, args.no_progress)

        if(not os.path.isfile(f'{temp}/new{trackNum}.wav')):
            log.bug('Audio file not created.')

    if(args.export_as_audio):
        if(args.keep_tracks_seperate):
            log.warning("Audio files can't have multiple tracks.")

        if(tracks == 1):
            move(f'{temp}/0.wav', outFile)
            return False

        cmd = [ffmpeg, '-y']
        for trackNum in range(tracks):
            cmd.extend(['-i', f'{temp}/{trackNum}.wav'])
        cmd.extend(['-filter_complex', f'amix=inputs={tracks}:duration=longest', outFile])
        log.debug(cmd)
        subprocess.call(cmd)
        return False
    return True

def muxVideo(ffmpeg, outFile, args, tracks, temp, log):
    if(args.keep_tracks_seperate):
        cmd = [ffmpeg, '-y']
        for i in range(tracks):
            cmd.extend(['-i', f'{temp}/new{i}.wav'])
        cmd.extend(['-i', f'{temp}/spedup.mp4'])
        for i in range(tracks):
            cmd.extend(['-map', f'{i}:a:0'])

        cmd.extend(['-map', f'{tracks}:v:0'])
    else:
        # Merge all the audio tracks into one.
        if(tracks > 1):
            cmd = [ffmpeg]
            for i in range(tracks):
                cmd.extend(['-i', f'{temp}/new{i}.wav'])
            cmd.extend(['-filter_complex', f'amerge=inputs={tracks}', '-ac', '2',
                f'{temp}/newAudioFile.wav'])
            cmd = ffAddDebug(cmd, log.is_ffmpeg)
            log.debug(cmd)
            subprocess.call(cmd)
        else:
            move(f'{temp}/new0.wav', f'{temp}/newAudioFile.wav')

        cmd = [ffmpeg, '-y', '-i', f'{temp}/newAudioFile.wav', '-i', f'{temp}/spedup.mp4']

    cmd.extend(['-c:v', 'copy'])
    if(args.audio_codec is not None):
        cmd.extend(['-c:a', args.audio_codec])
    cmd = ffAddDebug(cmd, log.is_ffmpeg)
    cmd.append(outFile)

    log.debug(cmd)
    message = pipeToConsole(cmd)
    log.debug(message)
    log.conwrite('')
