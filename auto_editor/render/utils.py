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
    elif(inp.ext == '.gif'):
        cmd.extend(['-vcodec', 'gif'])
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

def scale_to_sped(ffmpeg, spedup, scale, inp, args, temp):
    cmd = ['-i', scale]
    cmd = properties(cmd, args, inp)
    cmd.append(spedup)
    check_errors = ffmpeg.pipe(cmd)

    if('Error' in check_errors or 'failed' in check_errors):
        cmd = ['-i', scale]
        if('-allow_sw 1' in check_errors):
            cmd.extend(['-allow_sw', '1'])

        cmd = properties(cmd, args, inp)
        cmd.append(sped)
        ffmpeg.run(cmd)
