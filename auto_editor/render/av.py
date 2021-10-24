'''render/av.py'''

# External Libraries
import av

# Internal Libraries
import os.path
import subprocess

# Included Libraries
from auto_editor.utils.func import fnone

def pix_fmt_allowed(pix_fmt):
    # type: (str) -> bool

    # From: github.com/PyAV-Org/PyAV/blob/main/av/video/frame.pyx
    allowed_formats = ['yuv420p', 'yuvj420p', 'rgb24', 'bgr24', 'argb', 'rgba',
        'abgr', 'bgra', 'gray', 'gray8', 'rgb8', 'bgr8', 'pal8']

    return pix_fmt in allowed_formats

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

def render_av(ffmpeg, inp, args, chunks, speeds, fps, has_vfr, progress, effects, temp, log):
    total_frames = chunks[len(chunks) - 1][1]
    progress.start(total_frames, 'Creating new video')

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

    log.debug('pix_fmt: {}'.format(pix_fmt))

    inputVideoStream = input_.streams.video[0]
    inputVideoStream.thread_type = 'AUTO'

    width = inputVideoStream.width
    height = inputVideoStream.height

    effects.add_var('fps', fps)
    effects.add_var('width', width)
    effects.add_var('height', height)
    effects.add_var('start', 0)
    effects.add_var('end', total_frames - 1)
    effects.add_var('centerX', width // 2)
    effects.add_var('centerY', height // 2)

    effects.resolve(args)

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

    process2 = ffmpeg.Popen(cmd, stdin=subprocess.PIPE, stdout=subprocess.DEVNULL,
        stderr=None if args.show_ffmpeg_debug else subprocess.DEVNULL)

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

                    if(index-1 in effects.sheet):
                        frame = effects.apply(index-1, frame, pix_fmt)

                    in_bytes = frame.to_ndarray().tobytes()
                    process2.stdin.write(in_bytes)
                    outputEquavalent += 1

                progress.tick(index - 1)
        progress.end()
        process2.stdin.close()
        process2.wait()
    except BrokenPipeError:
        log.print(cmd)
        process2 = ffmpeg.Popen(cmd, stdin=subprocess.PIPE)
        log.error('Broken Pipe Error!')

    if(args.scale != 1):
        scale_to_sped(ffmpeg, spedup, scale, inp, args, temp)

    return spedup

