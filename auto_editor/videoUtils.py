'''videoUtils.py'''

# Internal Libraries
import os
from shutil import move, copy

# Included Libraries
from auto_editor.usefulFunctions import fNone
from auto_editor.fastAudio import fastAudio

def handleAudioTracks(ffmpeg, outFile, args, tracks, chunks, speeds, fps, temp, log):
    for t in range(tracks):
        temp_file = os.path.join(temp, f'{t}.wav')
        new_file = os.path.join(temp, f'new{t}.wav')
        fastAudio(temp_file, new_file, chunks, speeds, log, fps,
            args.machine_readable_progress, args.no_progress)

        if(not os.path.isfile(new_file)):
            log.bug('Audio file not created.')

    if(args.export_as_audio):
        if(args.keep_tracks_seperate):
            log.warning("Audio files don't have multiple tracks.")

        if(tracks == 1):
            move(os.path.join(temp, '0.wav'), outFile)
            return False

        cmd = []
        for t in range(tracks):
            cmd.extend(['-i', os.path.join(temp, f'{t}.wav')])
        cmd.extend(['-filter_complex', f'amix=inputs={tracks}:duration=longest', outFile])
        ffmpeg.run(cmd)

        return False
    return True

def muxVideo(ffmpeg, outFile, args, tracks, temp, log):
    cmd = []
    if(args.keep_tracks_seperate):
        for t in range(tracks):
            cmd.extend(['-i', os.path.join(temp, f'new{t}.wav')])
        cmd.extend(['-i', os.path.join(temp, 'spedup.mp4')])
        for t in range(tracks):
            cmd.extend(['-map', f'{t}:a:0'])
        cmd.extend(['-map', f'{tracks}:v:0'])
    else:
        # Merge all the audio tracks into one.
        new_a_file = os.path.join(temp, 'newAudioFile.wav')
        if(tracks > 1):
            for t in range(tracks):
                cmd.extend(['-i', os.path.join(temp, f'new{t}.wav')])
            cmd.extend(['-filter_complex', f'amerge=inputs={tracks}', '-ac', '2',
                new_a_file])
            ffmpeg.run(cmd)
        else:
            copy(os.path.join(temp, 'new0.wav'), new_a_file)
        cmd = ['-i', new_a_file, '-i', os.path.join(temp, 'spedup.mp4')]

    cmd.extend(['-c:v', 'copy'])
    if(not fNone(args.audio_codec)):
        cmd.extend(['-c:a', args.audio_codec])
    cmd.append(outFile)
    ffmpeg.run(cmd)
    log.conwrite('')
