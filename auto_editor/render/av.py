'''render/av.py'''

# Internal Libraries
import os.path
import subprocess

# From: github.com/PyAV-Org/PyAV/blob/main/av/video/frame.pyx
allowed_pix_fmt = {'yuv420p', 'yuvj420p', 'rgb24', 'bgr24', 'argb', 'rgba',
    'abgr', 'bgra', 'gray', 'gray8', 'rgb8', 'bgr8', 'pal8'}

def pix_fmt_allowed(pix_fmt):
    # type: (str) -> bool
    return pix_fmt in allowed_pix_fmt

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


def render_av(ffmpeg, inp, args, chunks, speeds, fps, has_vfr, progress, effects, rules,
    temp, log):
    try:
        import av
    except ImportError:
        log.error("av python module not installed. Run 'pip install av'")

    total_frames = chunks[len(chunks) - 1][1]
    progress.start(total_frames, 'Creating new video')

    input_ = av.open(inp.path)
    pix_fmt = input_.streams.video[0].pix_fmt

    apply_video = True

    if(has_vfr):
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
        pix_fmt = 'yuv420p'
        cmd = ['-i', inp.path, '-map', '0:v:0', '-f', 'matroska', '-pix_fmt', pix_fmt,
            '-vcodec', 'rawvideo', 'pipe:1']
        wrapper = Wrapper(ffmpeg.Popen(cmd).stdout)
        input_ = av.open(wrapper, 'r')
    else:
        apply_video = inp.ext != '.mp4'

    log.debug('pix_fmt: {}'.format(pix_fmt))
    log.debug('apply video quality settings now: {}'.format(not apply_video))

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

    spedup = os.path.join(temp, 'spedup.mp4')

    cmd = ['-hide_banner', '-y', '-f', 'rawvideo', '-c:v', 'rawvideo',
        '-pix_fmt', pix_fmt, '-s', '{}*{}'.format(width, height), '-framerate', str(fps),
        '-i', '-', '-pix_fmt', pix_fmt]

    if(args.scale != 1):
        apply_video = False

    from auto_editor.utils.encoder import encoders
    from auto_editor.utils.video import get_vcodec, video_quality

    my_codec = get_vcodec(args, inp, rules)

    if(my_codec in encoders):
        if(encoders[my_codec]['pix_fmt'].isdisjoint(allowed_pix_fmt)):
            apply_video = True

    if(apply_video):
        cmd.extend(['-c:v', 'mpeg4', '-qscale:v', '1'])
    else:
        cmd = video_quality(cmd, args, inp, rules)

    cmd.append(spedup)

    process2 = ffmpeg.Popen(cmd, stdin=subprocess.PIPE, stdout=subprocess.DEVNULL,
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
        progress.end()
        ffmpeg.run_check_errors(cmd, log, True)
        log.error('FFmpeg Error!')

    # Unfortunately, scaling has to be a concrete step.
    if(args.scale != 1):
        sped_input = os.path.join(temp, 'spedup.mp4')
        spedup = os.path.join(temp, 'scale.mp4')
        cmd = ['-i', sped_input, '-vf', 'scale=iw*{s}:ih*{s}'.format(s=args.scale),
            spedup]

        check_errors = ffmpeg.pipe(cmd)
        if('Error' in check_errors or 'failed' in check_errors):
            if('-allow_sw 1' in check_errors):
                # Add "-allow_sw 1" to command.
                cmd.insert(-1, '1')
                cmd.insert(-1, '-allow_sw')
            # Run again to show errors even if it might not work.
            ffmpeg.run(cmd)

    return spedup, apply_video

