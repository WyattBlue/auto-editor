'''ffwrapper.py'''

# Internal Libraries
import re
import os.path
import subprocess
from platform import system

# Included Libraries
from auto_editor.utils.func import get_stdout
from auto_editor.utils.log import Log

def _set_ff_path(ff_location, my_ffmpeg):
    # type: (str | None, bool) -> str
    if(ff_location is not None):
        return ff_location
    if(my_ffmpeg or system() not in ['Windows', 'Darwin']):
        return 'ffmpeg'
    program = 'ffmpeg' if system() == 'Darwin' else 'ffmpeg.exe'
    dirpath = os.path.dirname(os.path.realpath(__file__))
    return os.path.join(dirpath, 'ffmpeg', system(), program)

def _test_path(path):
    try:
        get_stdout([path, '-h'])
    except FileNotFoundError:
        if(system() == 'Darwin'):
            Log().error('No ffmpeg found, download via homebrew or restore the '
                'included binary.')
        if(system() == 'Windows'):
            Log().error('No ffmpeg found, download ffmpeg with your favorite package '
                'manager (ex chocolatey), or restore the included binary.')

        Log().error('ffmpeg must be installed and on PATH.')
    return path

def regex_match(regex, text):
    match = re.search(regex, text)
    if(match):
        return match.groupdict()['match']
    return None


class File:
    def __repr__(self):
        return str(self.__dict__)

    def __init__(self, ffmpeg, path):
        self.path = path
        self.abspath = os.path.abspath(path)
        self.basename = os.path.basename(path)
        self.dirname = os.path.dirname(os.path.abspath(path))

        f_name, f_ext = os.path.splitext(path)
        self.name = f_name
        self.ext = f_ext

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

                if(key is None):
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
                    if(fps is None):
                        fps = regex_match(r'\s(?P<match>[\d\.]+)\stbr', line)
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


class FFmpeg():
    def __init__(self, ff_location=None, my_ffmpeg=False, debug=False):
        _path = _set_ff_path(ff_location, my_ffmpeg)
        self.path = _test_path(_path)
        self.FFdebug = debug

    def getPath(self):
        return self.path

    def run(self, cmd):
        cmd = [self.path, '-y'] + cmd
        if(self.FFdebug):
            cmd.extend(['-hide_banner'])
            print(cmd)
        else:
            cmd.extend(['-nostats', '-loglevel', 'error'])
        subprocess.call(cmd)

    def file_info(self, path):
        return File(self, path)

    def Popen(self, cmd, stdin=None, stdout=subprocess.PIPE, stderr=None):
        cmd = [self.path] + cmd
        return subprocess.Popen(cmd, stdin=stdin, stdout=stdout, stderr=stderr)

    def pipe(self, cmd):
        # type: (list[str]) -> str
        cmd = [self.path, '-y'] + cmd

        if(self.FFdebug):
            print(cmd)
        output = get_stdout(cmd)
        if(self.FFdebug):
            print(output)

        return output

    def version(self):
        # type: () -> str
        _version = self.pipe(['-version']).split('\n')[0]
        _version = _version.replace('ffmpeg version', '').strip()
        return _version.split(' ')[0]
