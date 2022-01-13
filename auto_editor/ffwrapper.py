'''ffwrapper.py'''

# Internal Libraries
import re
import sys
import os.path
import subprocess
from platform import system

# Included Libraries
from auto_editor.utils.func import get_stdout
from auto_editor.utils.log import Log

def regex_match(regex, text):
    match = re.search(regex, text)
    if(match):
        return match.groupdict()['match']
    return None


class FFmpeg():

    @staticmethod
    def _set_ff_path(ff_location, my_ffmpeg):
        # type: (str | None, bool) -> str
        if(ff_location is not None):
            return ff_location
        if(my_ffmpeg or system() not in ['Windows', 'Darwin']):
            return 'ffmpeg'
        program = 'ffmpeg' if system() == 'Darwin' else 'ffmpeg.exe'
        dirpath = os.path.dirname(os.path.realpath(__file__))
        return os.path.join(dirpath, 'ffmpeg', system(), program)

    def __init__(self, ff_location=None, my_ffmpeg=False, debug=False):
        self.debug = debug
        self.path = self._set_ff_path(ff_location, my_ffmpeg)
        try:
            _version = get_stdout([self.path, '-version']).split('\n')[0]
            _version = _version.replace('ffmpeg version', '').strip()
            self.version = _version.split(' ')[0]
        except FileNotFoundError:
            if(system() == 'Darwin'):
                Log().error('No ffmpeg found, download via homebrew or restore the '
                    'included binary.')
            if(system() == 'Windows'):
                Log().error('No ffmpeg found, download ffmpeg with your favorite package '
                    'manager (ex chocolatey), or restore the included binary.')

            Log().error('ffmpeg must be installed and on PATH.')

    def print(self, message: str):
        if(self.debug):
            print('FFmpeg: {}'.format(message), file=sys.stderr)

    def print_cmd(self, cmd):
        # type: (list[str]) -> None
        if(self.debug):
            print('FFmpeg run: {}\n'.format(' '.join(cmd)), file=sys.stderr)

    def run(self, cmd):
        # type: (list[str]) -> None
        cmd = [self.path, '-y', '-hide_banner'] + cmd
        if(not self.debug):
            cmd.extend(['-nostats', '-loglevel', 'error'])
        self.print_cmd(cmd)
        subprocess.call(cmd)

    def run_check_errors(self, cmd, log, show_out=False):

        def _run(cmd):
            process = self.Popen(cmd, stdin=subprocess.PIPE,
                stdout=subprocess.PIPE, stderr=subprocess.PIPE)

            _, stderr = process.communicate()
            process.stdin.close()
            return stderr.decode()

        output = _run(cmd)

        if('Try -allow_sw 1' in output):
            cmd.insert(-1, '-allow_sw')
            cmd.insert(-1, '1')
            output = _run(cmd)

        error_list = [
            r"Unknown encoder '.*'",
            r"-q:v qscale not available for encoder\. Use -b:v bitrate instead\.",
            r'Specified sample rate .* is not supported',
            r'Unable to parse option value ".*"',
            r'Error setting option .* to value .*\.',
            r"Undefined constant or missing '.*' in '.*'",
        ]

        if(self.debug):
            print(f'stderr: {output}')

        for item in error_list:
            check = re.search(item, output)
            if(check):
                log.error(check.group())

        if(show_out and not self.debug):
            print(f'stderr: {output}')

    def file_info(self, path):
        return File(self, path)

    def Popen(self, cmd, stdin=None, stdout=subprocess.PIPE, stderr=None):
        cmd = [self.path] + cmd
        self.print_cmd(cmd)
        return subprocess.Popen(cmd, stdin=stdin, stdout=stdout, stderr=stderr)

    def pipe(self, cmd):
        # type: (list[str]) -> str
        cmd = [self.path, '-y'] + cmd

        self.print_cmd(cmd)
        output = get_stdout(cmd)
        self.print(output)
        return output


class File:
    __slots__ = ('path', 'abspath', 'basename', 'dirname', 'name', 'ext', 'duration',
        'bitrate', 'metadata', 'fps', 'video_streams', 'audio_streams', 'subtitle_streams')

    def __init__(self, ffmpeg: FFmpeg, path: str):
        self.path = path
        self.abspath = os.path.abspath(path)
        self.basename = os.path.basename(path)
        self.dirname = os.path.dirname(os.path.abspath(path))
        self.name, self.ext = os.path.splitext(path)

        info = get_stdout([ffmpeg.path, '-hide_banner', '-i', path])

        self.duration = regex_match(r'Duration:\s(?P<match>[\d:.]+),', info)
        self.bitrate = regex_match(r'bitrate:\s(?P<match>\d+\skb\/s)', info)

        self.metadata = {}
        active = False
        active_key = None

        for line in info.split('\n'):
            if(active):
                if(re.search(r'^\s*[A-Z][a-z_]*', line)):
                    break

                key = regex_match(r'^\s*(?P<match>[a-z_]+)', line)
                body = regex_match(r'^\s*[a-z_]*\s*:\s(?P<match>[\w\W]*)', line)

                if(body is not None):
                    if(key is None):
                        if(active_key is not None):
                            self.metadata[active_key] += '\n' + body
                    else:
                        self.metadata[key] = body
                        active_key = key

            if(re.search(r'^\s\sMetadata:', line)):
                active = True

        video_streams = []
        audio_streams = []
        subtitle_streams = []
        fps = None

        sub_exts = {'mov_text': 'srt', 'ass': 'ass', 'webvtt': 'vtt'}

        for line in info.split('\n'):
            if(re.search(r'Stream #', line)):
                s_data = {}
                if(re.search(r'Video:', line)):
                    s_data['width'] = regex_match(r'(?P<match>\d+)x\d+[\s,]', line)
                    s_data['height'] = regex_match(r'\d+x(?P<match>\d+)[\s,]', line)
                    s_data['codec'] = regex_match(r'Video:\s(?P<match>\w+)', line)
                    s_data['bitrate'] = regex_match(r'\s(?P<match>\d+\skb\/s)', line)
                    s_data['fps'] = regex_match(r'\s(?P<match>[\d\.]+)\stbr', line)
                    s_data['lang'] = regex_match(r'Stream #\d+:\d+\((?P<match>\w+)\)', line)

                    if(fps is None):
                        fps = s_data['fps']
                    video_streams.append(s_data)

                elif(re.search(r'Audio:', line)):
                    s_data['codec'] = regex_match(r'Audio:\s(?P<match>\w+)', line)
                    s_data['samplerate'] = regex_match(r'(?P<match>\d+)\sHz', line)
                    s_data['bitrate'] = regex_match(r'\s(?P<match>\d+\skb\/s)', line)
                    s_data['lang'] = regex_match(r'Stream #\d+:\d+\((?P<match>\w+)\)', line)
                    audio_streams.append(s_data)

                elif(re.search(r'Subtitle:', line)):
                    s_data['lang'] = regex_match(r'Stream #\d+:\d+\((?P<match>\w+)\)', line)
                    s_data['codec'] = regex_match(r'Subtitle:\s(?P<match>\w+)', line)
                    s_data['ext'] = sub_exts.get(s_data['codec'], 'vtt')
                    subtitle_streams.append(s_data)

        self.fps = fps
        self.video_streams = video_streams
        self.audio_streams = audio_streams
        self.subtitle_streams = subtitle_streams
