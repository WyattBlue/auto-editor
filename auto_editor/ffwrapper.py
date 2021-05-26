'''ffwrapper.py'''

# Internal Libraries
import subprocess
from os import path
from platform import system

# Included Libraries
from auto_editor.usefulFunctions import pipeToConsole, cleanList

def setPath(dirpath, my_ffmpeg, name):
    if(my_ffmpeg):
        return name
    if(system() == 'Windows'):
        return path.join(dirpath, 'win-ffmpeg', 'bin', '{}.exe'.format(name))
    if(system() == 'Darwin'):
        return path.join(dirpath, 'mac-ffmpeg', 'bin', name)
    return name

def testPath(dirpath, my_ffmpeg, name, log):
    path = setPath(dirpath, my_ffmpeg, name)
    try:
        pipeToConsole([path, '-h'])
    except FileNotFoundError:
        if(system() == 'Darwin'):
            log.error('No {} found, download via homebrew or restore the '\
                'included binary.'.format(name))
        if(system() == 'Windows'):
            log.error(f'No {name} found, download {name} with your favorite package '\
                'manager (ex chocolatey), or restore the included binary.')

        log.error(f'{name} must be on PATH. Download {name} by running:\n'\
        '  sudo apt-get install libavformat-dev libavfilter-dev libavdevice-dev ffmpeg'\
        '\nOr something similar depending on your distro.')
    return path

class FFprobe():
    def __init__(self, dirpath, myFFmpeg: bool, FFdebug, log):

        self.log = log
        self.path = testPath(dirpath, myFFmpeg, 'ffprobe', log)
        self.FFdebug = FFdebug

    def getPath(self) -> str:
        return self.path

    def run(self, cmd: list):
        cmd.insert(0, self.path)
        self.log.debug(cmd)
        subprocess.call(cmd)

    def pipe(self, cmd: list) -> str:
        full_cmd = [self.path, '-v', 'error'] + cmd

        self.log.debug(full_cmd)
        output = pipeToConsole(full_cmd)
        self.log.debug(output)

        return output

    def _get(self, file, stream, the_type, track, of='compact=p=0:nk=1') -> str:
        return self.pipe(['-select_streams', f'{the_type}:{track}', '-show_entries',
            f'stream={stream}', '-of', of, file]).strip()

    def getResolution(self, file):
        return self._get(file, 'height,width', 'v', 0, of='csv=s=x:p=0')

    def getDuration(self, file):
        return self._get(file, 'duration', 'v', 0)

    def getAudioDuration(self, file):
        return self._get(file, 'duration', 'a', 0)

    def getTimeBase(self, file):
        return self.pipe(['-select_streams', 'v', '-show_entries',
            'stream=avg_frame_rate', '-of', 'compact=p=0:nk=1', file]).strip()

    def getFrameRate(self, file) -> float:
        nums = cleanList(self.getTimeBase(file).split('/'), '\r\t\n')
        try:
            return int(nums[0]) / int(nums[1])
        except (ZeroDivisionError, IndexError, ValueError):
            self.log.error('getFrameRate had an error')

    def getAudioTracks(self, file):
        output = self.pipe(['-select_streams', 'a', '-show_entries', 'stream=index',
            '-of', 'compact=p=0:nk=1', file]).strip()

        numbers = cleanList(output.split('\n'), '\r\t')
        self.log.debug(f'Track data: {numbers}')
        if(numbers[0].isnumeric()):
            return len(numbers)
        else:
            self.log.warning('ffprobe had an invalid output.')
            return 1 # Assume there's one audio track.

    def getSubtitleTracks(self, file):
        output = self.pipe(['-select_streams', 's', '-show_entries', 'stream=index',
            '-of', 'compact=p=0:nk=1', file]).strip()

        numbers = cleanList(output.split('\n'), '\r\t')
        self.log.debug(f'Track data: {numbers}')
        if(numbers[0].isnumeric()):
            return len(numbers)
        else:
            self.log.warning('Invalid output when detecting number of subtitle tracks.')
            return 0

    def getLang(self, file, track=0):
        return self.pipe(['-select_streams', f's:{track}', '-show_entries',
            'stream_tags=language', '-of', 'csv=p=0', file])

    def getAudioCodec(self, file, track=0):
        return self._get(file, 'codec_name', 'a', track)

    def getVideoCodec(self, file, track=0):
        return self._get(file, 'codec_name', 'v', track)

    def getSampleRate(self, file, track=0):
        return self._get(file, 'sample_rate', 'a', track)

    def getBitrate(self, file, the_type='v', track=0):
        return self._get(file, 'bit_rate', the_type, track)

    def getPrettySampleRate(self, file, track=0) -> str:
        output = self.getSampleRate(file, track)
        if(output.isnumeric()):
            return '{} kHz'.format(int(output) / 1000)
        return 'N/A'

    def getPrettyBitrate(self, file, the_type='v', track=0) -> str:
        # This result gets used by ffmpeg so be careful.
        output = self.getBitrate(file, the_type, track)
        if(output.isnumeric()):
            return '{}k'.format(round(int(output) / 1000))
        return 'N/A'

class FFmpeg():
    def __init__(self, dirpath, myFFmpeg: bool, FFdebug, log):

        self.log = log
        self.path = testPath(dirpath, myFFmpeg, 'ffmpeg', log)
        self.FFdebug = FFdebug

    def getPath(self):
        return self.path

    def run(self, cmd: list):
        cmd = [self.path, '-y'] + cmd
        if(self.FFdebug):
            cmd.extend(['-hide_banner'])
        else:
            cmd.extend(['-nostats', '-loglevel', 'error'])
        self.log.debug(cmd)
        subprocess.call(cmd)

    def file_info(self, path):
        import os
        import re

        class File:
            def __repr__(self):
                return str(self.__dict__)

        file = File()

        setattr(file, 'path', path)
        setattr(file, 'abspath', os.path.abspath(path))
        setattr(file, 'basename', os.path.basename(path))
        setattr(file, 'dirname', os.path.dirname(path))

        f_name, f_ext = os.path.splitext(path)

        setattr(file, 'name', f_name)
        setattr(file, 'ext', f_ext)

        def regex_match(regex, text):
            match = re.search(regex, text)
            if(match):
                return match.groupdict()['match']
            return None

        info = pipeToConsole([self.path, '-hide_banner', '-i', path])

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
                    s_data['codec'] = regex_match(r'Video:\s(?P<match>\w+)\s', line)
                    s_data['bitrate'] = regex_match(r'\s(?P<match>\d+\skb\/s)', line)
                    fps = regex_match(r'\s(?P<match>[\d\.]+)\stbr', line)
                    video_streams.append(s_data)

                elif(re.search(r'Audio:', line)):
                    s_data['codec'] = regex_match(r'Audio:\s(?P<match>\w+)\s', line)
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

    def Popen(self, cmd: list):
        cmd = [self.path] + cmd
        if(self.FFdebug):
            return subprocess.Popen(cmd, stdout=subprocess.PIPE)
        return subprocess.Popen(cmd, stdout=subprocess.PIPE, stderr=subprocess.DEVNULL)

    def pipe(self, cmd: list) -> str:
        cmd = [self.path, '-y'] + cmd

        self.log.debug(cmd)
        output = pipeToConsole(cmd)
        self.log.debug(output)

        return output

    def getVersion(self):
        _version = self.pipe(['-version']).split('\n')[0]
        _version = _version.replace('ffmpeg version', '').strip()
        return _version.split(' ')[0]
