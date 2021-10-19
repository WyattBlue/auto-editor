'''render/av.py'''

# External Libraries
import av

# Internal Libraries
import os.path
import subprocess

# Included Libraries
from auto_editor.utils.progressbar import ProgressBar
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


class Effect():
    def _values(self, val, _type):
        if(_type is str):
            return str(val)

        for key, item in self._vars.items():
            if(val == key):
                return item

        if(not isinstance(val, int)
            and not (val.replace('.', '', 1)).replace('-', '', 1).isdigit()):
            self.log.error("variable '{}' is not defined.".format(val))
        return _type(val)

    def set_all(self, effect, my_types):
        for key, _type in my_types.items():
            effect[key] = self._values(effect[key], _type)

        self.all.append(effect)

    def set_start_end(self, start, end, num_effects):
        start = self._values(start, int)
        end = self._values(end, int)

        for i in range(start, end, 1):
            if(i in self.sheet):
                self.sheet[i].append(num_effects)
            else:
                self.sheet[i] = [num_effects]

    def __init__(self, args, log, pix_fmt, _vars):
        self.pix_fmt = pix_fmt

        self.all = []
        self.sheet = {}
        self._vars = _vars
        self.log = log

        num_effects = 0

        rect_types = {
            'x1': int,
            'y1': int,
            'x2': int,
            'y2': int,
            'color': str,
        }
        for rect in args.rectangle:
            effect = rect.copy()
            effect['type'] = 'rectangle'

            start = effect.pop('start', None)
            end = effect.pop('end', None)

            self.set_start_end(start, end, num_effects)
            self.set_all(effect, rect_types)

            num_effects += 1

        zoom_types = {
            'zoom': float,
            'end_zoom': float,
            'x': int,
            'y': int,
            'interpolate': str,
        }

        for zoom in args.zoom:
            if(zoom['end_zoom'] == '{zoom}'):
                zoom['end_zoom'] = zoom['zoom']

            effect = zoom.copy()
            effect['type'] = 'zoom'

            start = effect.pop('start', None)
            end = effect.pop('end', None)

            self.set_start_end(start, end, num_effects)
            self.set_all(effect, zoom_types)

            num_effects += 1

    def apply(self, index, frame, pix_fmt):
        from PIL import Image, ImageDraw, ImageFont

        img = frame.to_image()

        for item in self.sheet[index]:
            pars = self.all[item]

            if(pars['type'] == 'rectangle'):
                draw = ImageDraw.Draw(img)
                draw.rectangle([(pars['x1'], pars['y1'],), (pars['x2'], pars['y2'])],
                    fill=pars['color'])

            if(pars['type'] == 'zoom'):
                w, h = img.size

                # img = img.crop((pars['x'] - w / pars['zoom'], pars['y'] - h / pars['zoom'],
                #     pars['x'] + w / pars['zoom'], pars['y'] + h / pars['zoom']))
                # img = img.resize((w, h), Image.LANCZOS)

        frame = frame.from_image(img).reformat(format=self.pix_fmt)
        return frame

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

    log.debug('pix_fmt: {}'.format(pix_fmt))

    inputVideoStream = input_.streams.video[0]
    inputVideoStream.thread_type = 'AUTO'

    width = inputVideoStream.width
    height = inputVideoStream.height

    _vars = {
        'width': width,
        'height': height,
        'start': 0,
        'end': totalFrames - 1,
        'centerX': width // 2,
        'centerY': height // 2,
    }
    effects = Effect(args, log, pix_fmt=pix_fmt, _vars=_vars)

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

