'''render/av.py'''

from __future__ import print_function, absolute_import

# External Libraries
import av

# Internal Libraries
import os
import subprocess

# Included Libaries
from auto_editor.utils.progressbar import ProgressBar
from .utils import properties, scale_to_sped

def pix_fmt_allowed(pix_fmt):
    # type: (str) -> bool

    # From: github.com/PyAV-Org/PyAV/blob/main/av/video/frame.pyx
    allowed_formats = ['yuv420p', 'yuvj420p', 'rgb24', 'bgr24', 'argb', 'rgba',
        'abgr', 'bgra', 'gray', 'gray8', 'rgb8', 'bgr8', 'pal8']

    return pix_fmt in allowed_formats


def render_av(ffmpeg, inp, args, chunks, speeds, fps, has_vfr, temp, log):
    totalFrames = chunks[len(chunks) - 1][1]

    SPLIT_DURATION = 5

    total_seconds = int(totalFrames / fps)

    vid_space = os.path.join(temp, 'video')
    os.mkdir(vid_space)
    n = 0
    for i in range(0, total_seconds, SPLIT_DURATION):
        print(i)
        ffmpeg.run(['-i', inp.path, '-vcodec', 'copy', '-ss', str(i), '-to',
            str(i + SPLIT_DURATION),
            os.path.join(vid_space, '{}{}'.format(n, inp.ext))
        ])
        n += 1

    print(vid_space)
    quit()

    videoProgress = ProgressBar(totalFrames, 'Creating new video',
        args.machine_readable_progress, args.no_progress)

    input_ = av.open(inp.path)
    pix_fmt = input_.streams.video[0].pix_fmt

    if(not pix_fmt_allowed(pix_fmt)):
        throw_pix_fmt(inp, pix_fmt, log)

    inputVideoStream = input_.streams.video[0]
    inputVideoStream.thread_type = 'AUTO'

    width = inputVideoStream.width
    height = inputVideoStream.height

    log.debug('pix_fmt: {}'.format(pix_fmt))

    cmd = ['-hide_banner', '-y', '-f', 'rawvideo', '-vcodec', 'rawvideo',
        '-pix_fmt', pix_fmt, '-s', '{}*{}'.format(width, height), '-framerate', str(fps),
        '-i', '-', '-pix_fmt', pix_fmt]

    correct_ext = '.mp4' if inp.ext == '.gif' else inp.ext

    spedup = os.path.join(temp, 'spedup{}'.format(correct_ext))
    scale = os.path.join(temp, 'scale{}'.format(correct_ext))

    if(args.scale != 1):
        cmd.extend(['-vf', 'scale=iw*{}:ih*{}'.format(args.scale, args.scale), scale])
    else:
        cmd = properties(cmd, args, inp)
        cmd.append(spedup)

    process2 = ffmpeg.Popen(cmd, stdin=subprocess.PIPE)

    inputEquavalent = 0.0
    outputEquavalent = 0
    index = 0
    chunk = chunks.pop(0)

    try:
        for packet in input_.demux(inputVideoStream):
            for frame in packet.decode():
                index += 1
                if(len(chunks) > 0 and index >= chunk[1]):
                    chunk = chunks.pop(0)

                if(speeds[chunk[2]] != 99999):
                    inputEquavalent += (1 / speeds[chunk[2]])

                while inputEquavalent > outputEquavalent:
                    in_bytes = frame.to_ndarray().tobytes()
                    process2.stdin.write(in_bytes)
                    outputEquavalent += 1

                videoProgress.tick(index - 1)
        process2.stdin.close()
        process2.wait()
    except BrokenPipeError:
        log.print(cmd)
        process2 = ffmpeg.Popen(cmd, stdin=subprocess.PIPE)
        log.error('Broken Pipe Error!')

    if(args.scale != 1):
        scale_to_sped(ffmpeg, spedup, scale, inp, args, temp)

    return spedup

