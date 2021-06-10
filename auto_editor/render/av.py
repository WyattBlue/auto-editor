'''render/av.py'''

# Internal Libraries
import os.path
import subprocess

# Included Libaries
from auto_editor.utils.progressbar import ProgressBar
from .utils import properties, scale_to_sped

def render_av(ffmpeg, inp, args, chunks, speeds, fps, has_vfr, temp, log):
    import av

    totalFrames = chunks[len(chunks) - 1][1]
    videoProgress = ProgressBar(totalFrames, 'Creating new video',
        args.machine_readable_progress, args.no_progress)

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
            str(fps), '-vsync', '1', '-f', 'matroska', '-vcodec', 'rawvideo', 'pipe:1']

        wrapper = Wrapper(ffmpeg.Popen(cmd).stdout)
        input_ = av.open(wrapper, 'r')
    else:
        input_ = av.open(inp.path)

    inputVideoStream = input_.streams.video[0]
    inputVideoStream.thread_type = 'AUTO'

    width = inputVideoStream.width
    height = inputVideoStream.height
    pix_fmt = inputVideoStream.pix_fmt

    log.debug('pix_fmt: {}'.format(pix_fmt))

    cmd = [ffmpeg.getPath(), '-hide_banner', '-y', '-f', 'rawvideo', '-vcodec', 'rawvideo',
        '-pix_fmt', pix_fmt, '-s', '{}*{}'.format(width, height), '-framerate', str(fps),
        '-i', '-', '-pix_fmt', pix_fmt]

    if(args.scale != 1):
        cmd.extend(['-vf', 'scale=iw*{}:ih*{}'.format(args.scale, args.scale),
            os.path.join(temp, 'scale.mp4')])
    else:
        cmd = properties(cmd, args, inp)
        cmd.append(os.path.join(temp, 'spedup.mp4'))

    if(args.show_ffmpeg_debug):
        process2 = subprocess.Popen(cmd, stdin=subprocess.PIPE)
    else:
        process2 = subprocess.Popen(cmd, stdin=subprocess.PIPE, stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL)

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
        process2 = subprocess.Popen(cmd, stdin=subprocess.PIPE)
        log.error('Broken Pipe Error!')

    if(args.scale != 1):
        scale_to_sped(ffmpeg, inp, args, temp)

