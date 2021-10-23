'''utils/video.py'''

# Internal Libraries
import os.path
from shutil import move

# Included Libraries
from .func import fnone
from auto_editor.render.audio import make_new_audio

def handle_audio_tracks(ffmpeg, write_file, args, a_tracks, chunks, speeds, fps, progress,
    temp, log):
    for t in range(a_tracks):
        temp_file = os.path.join(temp, '{}.wav'.format(t))
        new_file = os.path.join(temp, 'new{}.wav'.format(t))
        make_new_audio(temp_file, new_file, chunks, speeds, log, fps, progress)

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

def mux_rename_video(ffmpeg, spedup, write_file, args, inp, temp, log):

    s_tracks = len(inp.subtitle_streams)
    a_tracks = len(inp.audio_streams)

    if(a_tracks == 0 and s_tracks == 0):
        move(spedup, write_file)
        log.conwrite('')
        return

    cmd = ['-i', spedup]
    if(a_tracks > 0):
        if(args.keep_tracks_seperate):
            for t in range(a_tracks):
                cmd.extend(['-i', os.path.join(temp, 'new{}.wav'.format(t))])
        else:
            # Merge all the audio a_tracks into one.
            new_a_file = os.path.join(temp, 'new_audio.wav')
            if(a_tracks > 1):
                new_cmd = []
                for t in range(a_tracks):
                    new_cmd.extend(['-i', os.path.join(temp, 'new{}.wav'.format(t))])
                new_cmd.extend(['-filter_complex', 'amerge=inputs={}'.format(a_tracks),
                    '-ac', '2', new_a_file])
                ffmpeg.run(new_cmd)
            else:
                new_a_file = os.path.join(temp, 'new0.wav')
            cmd.extend(['-i', new_a_file])

    if(s_tracks > 0):
        for s, sub in enumerate(inp.subtitle_streams):
            new_path = os.path.join(temp, 'new{}s.{}'.format(s, sub['ext']))
            cmd.extend(['-i', new_path])

    total_streams = 1 + s_tracks + (a_tracks if args.keep_tracks_seperate else 1)
    for i in range(total_streams):
        cmd.extend(['-map', '{}:0'.format(i)])

    cmd.extend(['-c:v', 'copy'])
    if(s_tracks > 0):
        codec = inp.subtitle_streams[0]['codec']
        cmd.extend(['-c:s', codec])

    if(not fnone(args.audio_codec)):
        cmd.extend(['-c:a', args.audio_codec])

    cmd.append(write_file)
    ffmpeg.run(cmd)
    log.conwrite('')
