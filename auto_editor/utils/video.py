'''utils/video.py'''

# Internal Libraries
import os
from shutil import move, copy

# Included Libraries
from .func import fnone
from auto_editor.render.audio import fastAudio

def handleAudioTracks(ffmpeg, write_file, args, tracks, chunks, speeds, fps, temp, log):
    for t in range(tracks):
        temp_file = os.path.join(temp, '{}.wav'.format(t))
        new_file = os.path.join(temp, 'new{}.wav'.format(t))
        fastAudio(temp_file, new_file, chunks, speeds, log, fps,
            args.machine_readable_progress, args.no_progress)

        if(not os.path.isfile(new_file)):
            log.bug('Audio file not created.')

    if(args.export_as_audio):
        if(args.keep_tracks_seperate):
            log.warning("Audio files don't have multiple tracks.")

        if(tracks == 1):
            move(os.path.join(temp, '0.wav'), write_file)
            return False

        cmd = []
        for t in range(tracks):
            cmd.extend(['-i', os.path.join(temp, '{}.wav'.format(t))])
        cmd.extend(['-filter_complex', 'amix=inputs={}:duration=longest'.format(tracks),
            write_file])
        ffmpeg.run(cmd)

        return False
    return True

def muxVideo(ffmpeg, write_file, args, tracks, temp, log):
    cmd = []
    if(args.keep_tracks_seperate):
        for t in range(tracks):
            cmd.extend(['-i', os.path.join(temp, 'new{}.wav'.format(t))])
        cmd.extend(['-i', os.path.join(temp, 'spedup.mp4')])
        for t in range(tracks):
            cmd.extend(['-map', '{}:a:0'.format(t)])
        cmd.extend(['-map', '{}:v:0'.format(tracks)])
    else:
        # Merge all the audio tracks into one.
        new_a_file = os.path.join(temp, 'newAudioFile.wav')
        if(tracks > 1):
            for t in range(tracks):
                cmd.extend(['-i', os.path.join(temp, 'new{}.wav'.format(t))])
            cmd.extend(['-filter_complex', 'amerge=inputs={}'.format(tracks), '-ac', '2',
                new_a_file])
            ffmpeg.run(cmd)
        else:
            copy(os.path.join(temp, 'new0.wav'), new_a_file)
        cmd = ['-i', new_a_file, '-i', os.path.join(temp, 'spedup.mp4')]

    cmd.extend(['-c:v', 'copy'])
    if(not fnone(args.audio_codec)):
        cmd.extend(['-c:a', args.audio_codec])
    cmd.append(write_file)
    ffmpeg.run(cmd)
    log.conwrite('')
