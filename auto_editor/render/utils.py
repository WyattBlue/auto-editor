'''render/utils.py'''

import os.path

from auto_editor.utils.func import fnone

def fset(cmd, option, value):
    if(fnone(value)):
        return cmd
    return cmd + [option] + [value]

def properties(cmd, args, inp):
    if(args.video_codec == 'uncompressed'):
        cmd.extend(['-vcodec', 'mpeg4', '-qscale:v', '1'])
    elif(args.video_codec == 'copy'):
        new_codec = inp.video_streams[0]['codec']
        if(new_codec != 'dvvideo'): # This codec seems strange.
            cmd.extend(['-vcodec', new_codec])
    else:
        cmd = fset(cmd, '-vcodec', args.video_codec)

    cmd = fset(cmd, '-crf', args.constant_rate_factor)
    cmd = fset(cmd, '-b:v', args.video_bitrate)
    cmd = fset(cmd, '-tune', args.tune)
    cmd = fset(cmd, '-preset', args.preset)

    cmd.extend(['-movflags', '+faststart', '-strict', '-2'])
    return cmd

def scale_to_sped(ffmpeg, inp, args, temp):
    SCALE = os.path.join(temp, 'scale.mp4')
    SPED = os.path.join(temp, 'spedup.mp4')

    cmd = ['-i', SCALE]
    cmd = properties(cmd, args, inp)
    cmd.append(SPED)
    check_errors = ffmpeg.pipe(cmd)

    if('Error' in check_errors or 'failed' in check_errors):
        cmd = ['-i', SCALE]
        if('-allow_sw 1' in check_errors):
            cmd.extend(['-allow_sw', '1'])

        cmd = properties(cmd, args, inp)
        cmd.append(SPED)
        ffmpeg.run(cmd)
