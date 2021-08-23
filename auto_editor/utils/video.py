'''utils/video.py'''

# Internal Libraries
import os
from shutil import move

# Included Libraries
from .func import fnone
from auto_editor.render.audio import make_new_audio

def handle_audio_tracks(ffmpeg, write_file, args, a_tracks, chunks, speeds, fps, temp,
    log):
    for t in range(a_tracks):
        temp_file = os.path.join(temp, '{}.wav'.format(t))
        new_file = os.path.join(temp, 'new{}.wav'.format(t))
        make_new_audio(temp_file, new_file, chunks, speeds, log, fps,
            args.machine_readable_progress, args.no_progress)

        if(not os.path.isfile(new_file)):
            log.bug('Audio file not created.')

    if(args.export_as_audio):
        if(args.keep_tracks_seperate):
            log.warning("Audio files don't have multiple a_tracks.")

        if(a_tracks == 1):
            move(os.path.join(temp, '0.wav'), write_file)
            return False

        cmd = []
        for t in range(a_tracks):
            cmd.extend(['-i', os.path.join(temp, '{}.wav'.format(t))])
        cmd.extend(['-filter_complex', 'amix=inputs={}:duration=longest'.format(a_tracks),
            write_file])
        ffmpeg.run(cmd)

        return False
    return True

def mux_rename_video(ffmpeg, write_file, args, inp, temp, log):

    if(len(inp.subtitle_streams) > 0):
        cmd = []
        for s, sub in enumerate(inp.subtitle_streams):
            new_path = os.path.join(temp, '{}s.{}'.format(s, sub['codec']))
            cmd.extend(['-i', new_path])
        cmd.extend(['-i', os.path.join(temp, 'spedup.mp4')])

        for s, sub in enumerate(inp.subtitle_streams):
            cmd.extend(['-map', '{}:s:0'.format(s)])
        cmd.extend(['-map', '0:v:0'])
        ffmpeg.run(cmd)

    a_tracks = len(inp.audio_streams)

    if(a_tracks == 0):
        move(os.path.join(temp, 'spedup.mp4'), write_file)
        log.conwrite('')
        return

    cmd = []
    if(args.keep_tracks_seperate):
        for t in range(a_tracks):
            cmd.extend(['-i', os.path.join(temp, 'new{}.wav'.format(t))])
        cmd.extend(['-i', os.path.join(temp, 'spedup.mp4')])
        for t in range(a_tracks):
            cmd.extend(['-map', '{}:a:0'.format(t)])
        cmd.extend(['-map', '{}:v:0'.format(a_tracks)])
    else:
        # Merge all the audio a_tracks into one.
        new_a_file = os.path.join(temp, 'new_audio.wav')
        if(a_tracks > 1):
            for t in range(a_tracks):
                cmd.extend(['-i', os.path.join(temp, 'new{}.wav'.format(t))])
            cmd.extend(['-filter_complex', 'amerge=inputs={}'.format(a_tracks), '-ac', '2',
                new_a_file])
            ffmpeg.run(cmd)
        else:
            new_a_file = os.path.join(temp, 'new0.wav')
        cmd = ['-i', new_a_file, '-i', os.path.join(temp, 'spedup.mp4')]

    cmd.extend(['-c:v', 'copy'])
    if(not fnone(args.audio_codec)):
        cmd.extend(['-c:a', args.audio_codec])
    cmd.append(write_file)
    ffmpeg.run(cmd)
    log.conwrite('')
