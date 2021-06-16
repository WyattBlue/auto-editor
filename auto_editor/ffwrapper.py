'''ffwrapper.py'''

from __future__ import print_function

# Internal Libraries
import subprocess
import os.path
from platform import system

# Included Libraries
from auto_editor.utils.func import get_stdout

def _set_path(dirpath, my_ffmpeg):
    if(my_ffmpeg or system() not in ['Windows', 'Darwin']):
        return 'ffmpeg'
    program = 'ffmpeg' if system() == 'Darwin' else 'ffmpeg.exe'
    return os.path.join(dirpath, 'ffmpeg', system(), program)

def _test_path(dirpath, my_ffmpeg, log):
    path = _set_path(dirpath, my_ffmpeg)
    try:
        get_stdout([path, '-h'])
    except FileNotFoundError:
        if(system() == 'Darwin'):
            log.error('No ffmpeg found, download via homebrew or restore the '\
                'included binary.')
        if(system() == 'Windows'):
            log.error('No ffmpeg found, download ffmpeg with your favorite package '\
                'manager (ex chocolatey), or restore the included binary.')

        log.error('ffmpeg must be on PATH. Download ffmpeg by running:\n'\
        '  sudo apt-get install libavformat-dev libavfilter-dev libavdevice-dev ffmpeg'\
        '\nOr something similar depending on your distro.')
    return path

class FFmpeg():
    def __init__(self, dirpath, myFFmpeg, FFdebug, log):
        self.log = log
        self.path = _test_path(dirpath, myFFmpeg, log)
        self.FFdebug = FFdebug

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
        import re

        class File:
            def __repr__(self):
                return str(self.__dict__)

        file = File()

        setattr(file, 'path', path)
        setattr(file, 'abspath', os.path.abspath(path))
        setattr(file, 'basename', os.path.basename(path))
        setattr(file, 'dirname', os.path.dirname(os.path.abspath(path)))

        f_name, f_ext = os.path.splitext(path)

        setattr(file, 'name', f_name)
        setattr(file, 'ext', f_ext)

        def regex_match(regex, text):
            match = re.search(regex, text)
            if(match):
                return match.groupdict()['match']
            return None

        info = get_stdout([self.path, '-hide_banner', '-i', path])

        setattr(file, 'duration', regex_match(r'Duration:\s(?P<match>[\d:.]+),', info))
        setattr(file, 'bitrate', regex_match(r'bitrate:\s(?P<match>\d+\skb\/s)', info))

        video_streams = []
        audio_streams = []
        subtitle_streams = []
        fps = None

        for line in info.split('\n'):
            if(re.search(r'Stream #', line)):
                s_data = {}
                if(re.search(r'Video:', line)):
                    s_data['width'] = regex_match(r'(?P<match>\d+)x\d+\s', line)
                    s_data['height'] = regex_match(r'\d+x(?P<match>\d+)\s', line)
                    s_data['codec'] = regex_match(r'Video:\s(?P<match>\w+)', line)
                    s_data['bitrate'] = regex_match(r'\s(?P<match>\d+\skb\/s)', line)
                    fps = regex_match(r'\s(?P<match>[\d\.]+)\stbr', line)
                    video_streams.append(s_data)

                elif(re.search(r'Audio:', line)):
                    s_data['codec'] = regex_match(r'Audio:\s(?P<match>\w+)', line)
                    s_data['samplerate'] = regex_match(r'(?P<match>\d+)\sHz', line)
                    s_data['bitrate'] = regex_match(r'\s(?P<match>\d+\skb\/s)', line)
                    audio_streams.append(s_data)

                elif(re.search(r'Subtitle:', line)):
                    s_data['lang'] = regex_match(r'Stream #\d:\d\((?P<match>\w+)\)', line)
                    subtitle_streams.append(s_data)

        setattr(file, 'fps', fps)
        setattr(file, 'video_streams', video_streams)
        setattr(file, 'audio_streams', audio_streams)
        setattr(file, 'subtitle_streams', subtitle_streams)

        return file

    def Popen(self, cmd):
        cmd = [self.path] + cmd
        if(self.FFdebug):
            return subprocess.Popen(cmd, stdout=subprocess.PIPE)
        return subprocess.Popen(cmd, stdout=subprocess.PIPE, stderr=subprocess.DEVNULL)

    def pipe(self, cmd):
        cmd = [self.path, '-y'] + cmd

        if(self.FFdebug):
            print(cmd)
        output = get_stdout(cmd)
        if(self.FFdebug):
            print(output)

        return output

    def getVersion(self):
        _version = self.pipe(['-version']).split('\n')[0]
        _version = _version.replace('ffmpeg version', '').strip()
        return _version.split(' ')[0]
