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

    # def getInfo(path):
    #     import os
    #     import re

    #     file = {}
    #     file['path'] = path
    #     file['basename'] = os.path.basename(path)
    #     file['name'], file['ext'] = os.path.splitext([path])


    #     info = pipeToConsole([self.path, '-hide_banner', '-i', path])

    #     print(info)


    #     return file

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

    def getPath(self) -> str:
        return self.path

    def run(self, cmd: list):
        cmd = [self.path, '-y'] + cmd
        if(self.FFdebug):
            cmd.extend(['-hide_banner'])
        else:
            cmd.extend(['-nostats', '-loglevel', 'error'])
        self.log.debug(cmd)
        subprocess.call(cmd)

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
