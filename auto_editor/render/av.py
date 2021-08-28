'''render/av.py'''

from __future__ import print_function, absolute_import

# External Libraries
import av

# Internal Libraries
import os.path
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
    videoProgress = ProgressBar(totalFrames, 'Creating new video',
        args.machine_readable_progress, args.no_progress)

    input_ = av.open(inp.path)
    pix_fmt = input_.streams.video[0].pix_fmt

    def throw_pix_fmt(inp, pix_fmt, log):
        log.error('''pix_fmt {} is not supported.\n
Convert your video to a supported pix_fmt. The following command might work for you:
  ffmpeg -i "{}" -pix_fmt yuv420p converted{}
'''.format(pix_fmt, inp.path, '' if inp.ext is None else inp.ext))

    if(has_vfr):
        class Wrapper:
            """
            Wrapper which only exposes the `read` method to avoid PyAV
            trying to use `seek`.
            From: github.com/PyAV-Org/PyAV/issues/578#issuecomment-621362337
            """

            name = "<wrapped>"

            def __init__(self, fh):
                self._fh = fh

            def read(self, buf_size):
                return self._fh.read(buf_size)

        # Create a cfr stream on stdout.
        cmd = ['-i', inp.path, '-map', '0:v:0', '-vf', 'fps=fps={}'.format(fps), '-r',
            str(fps), '-vsync', '1', '-f', 'matroska']
        if(not pix_fmt_allowed(pix_fmt)):
            pix_fmt = 'yuv420p'
            cmd.extend(['-pix_fmt', pix_fmt])

        cmd.extend(['-vcodec', 'rawvideo', 'pipe:1'])

        wrapper = Wrapper(ffmpeg.Popen(cmd).stdout)
        input_ = av.open(wrapper, 'r')
    elif(not pix_fmt_allowed(pix_fmt)):
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

