'''render/video.py'''

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


def render_av(ffmpeg, track, inp, args, chunks, fps, progress, effects, rules, temp, log):
    try:
        import av
    except ImportError:
        log.error("av python module not installed. Run 'pip install av'")

    total_frames = chunks[-1][1]
    progress.start(total_frames, 'Creating new video')

    container = av.open(inp.path, 'r')
    pix_fmt = container.streams.video[track].pix_fmt

    if(not pix_fmt_allowed(pix_fmt)):
        pix_fmt = 'yuv420p'
        cmd = ['-i', inp.path, '-map', f'0:v:{track}', '-f', 'matroska', '-pix_fmt', pix_fmt,
            '-vcodec', 'rawvideo', 'pipe:1']
        wrapper = Wrapper(ffmpeg.Popen(cmd).stdout)
        container = av.open(wrapper, 'r')

    from auto_editor.utils.encoder import encoders
    from auto_editor.utils.video import get_vcodec, video_quality

    my_codec = get_vcodec(args, inp, rules)

    apply_video_later = True

    if(my_codec in encoders):
        apply_video_later = encoders[my_codec]['pix_fmt'].isdisjoint(allowed_pix_fmt)

    if(args.scale != 1):
        apply_video_later = False

    log.debug(f'apply video quality settings now: {not apply_video_later}')

    video_stream = container.streams.video[track]
    video_stream.thread_type = 'AUTO'

    width = video_stream.width
    height = video_stream.height

    effects.add_var('fps', fps)
    effects.add_var('width', width)
    effects.add_var('height', height)
    effects.add_var('start', 0)
    effects.add_var('end', total_frames - 1)
    effects.add_var('centerX', width // 2)
    effects.add_var('centerY', height // 2)

    effects.resolve(args)

    spedup = os.path.join(temp, f'spedup{track}.mp4')

    cmd = ['-hide_banner', '-y', '-f', 'rawvideo', '-c:v', 'rawvideo',
        '-pix_fmt', pix_fmt, '-s', f'{width}*{height}', '-framerate', str(fps),
        '-i', '-', '-pix_fmt', pix_fmt]

    if(apply_video_later):
        cmd.extend(['-c:v', 'mpeg4', '-qscale:v', '1'])
    else:
        cmd = video_quality(cmd, args, inp, rules)

    cmd.append(spedup)

    process2 = ffmpeg.Popen(cmd, stdin=subprocess.PIPE, stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL)

    input_equavalent = 0.0
    output_equavalent = 0
    chunk = chunks.pop(0)

    try:
        for frame in container.decode(video_stream):
            index = int(frame.time * fps)

            if index > chunk[1]:
                if chunks:
                    chunk = chunks.pop(0)
                else:
                    break

            if chunk[2] != 99999:
                input_equavalent += (1 / chunk[2])

            while input_equavalent > output_equavalent:
                if index in effects.sheet:
                    frame = effects.apply(index, frame, pix_fmt)

                in_bytes = frame.to_ndarray().tobytes()
                process2.stdin.write(in_bytes)
                output_equavalent += 1

            progress.tick(index)

        progress.end()
        process2.stdin.close()
        process2.wait()
    except (OSError, BrokenPipeError):
        progress.end()
        ffmpeg.run_check_errors(cmd, log, True)
        log.error('FFmpeg Error!')

    # Unfortunately, scaling has to be a concrete step.
    if(args.scale != 1):
        sped_input = os.path.join(temp, f'spedup{track}.mp4')
        spedup = os.path.join(temp, f'scale{track}.mp4')
        cmd = ['-i', sped_input, '-vf', 'scale=iw*{s}:ih*{s}'.format(s=args.scale),
            spedup]

        check_errors = ffmpeg.pipe(cmd)
        if('Error' in check_errors or 'failed' in check_errors):
            if('-allow_sw 1' in check_errors):
                cmd.insert(-1, '-allow_sw')
                cmd.insert(-1, '1')
            # Run again to show errors even if it might not work.
            ffmpeg.run(cmd)

    return 'video', spedup, apply_video_later

