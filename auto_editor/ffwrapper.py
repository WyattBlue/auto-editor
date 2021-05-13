'''ffwrapper.py'''

# Internal Libraries
import subprocess
from os import path
from platform import system

# Included Libraries
from usefulFunctions import pipeToConsole, cleanList, sep

class FFprobe():
    def __init__(self, dirPath, myFFmpeg: bool, FFdebug, log):

        self.mylog = log
        self.FFdebug = FFdebug

        newF = None
        if(system() == 'Windows' and not myFFmpeg):
            newF = path.join(dirPath, f'win-ffmpeg{sep()}bin{sep()}ffprobe.exe')
        if(system() == 'Darwin' and not myFFmpeg):
            newF = path.join(dirPath, f'mac-ffmpeg{sep()}bin{sep()}ffprobe')

        if(newF is not None and path.isfile(newF)):
            self.myPath = newF
        else:
            self.myPath = 'ffprobe'
            try:
                pipeToConsole([self.myPath, '-h'])
            except FileNotFoundError:
                if(system() == 'Darwin'):
                    self.mylog.error('No ffprobe found, download via homebrew or restore' \
                        ' the included binary.')
                elif(system() == 'Windows'):
                    self.mylog.error('No ffprobe found, download ffprobe with your' \
                        ' favorite package manager (ex chocolatey), or restore the' \
                        ' included binary.')
                else:
                    self.mylog.error('ffprobe must be on PATH. Download ffprobe by running:\n' \
                        '  sudo apt-get install libavformat-dev libavfilter-dev libavdevice-dev ffmpeg' \
                        '\nOr something similar depending on your distro.')

    def log(self, message):
        if(self.FFdebug):
            print(message)

    def getPath(self) -> str:
        return self.myPath

    def updateLog(self, log):
        self.mylog = log

    def run(self, cmd: list):
        cmd.insert(0, self.myPath)

        if(None in cmd):
            self.mylog.bug(f'None in cmd. {cmd}')
        self.log(cmd)
        subprocess.call(cmd)

    def pipe(self, cmd: list) -> str:
        full_cmd = [self.myPath, '-v', 'error'] + cmd

        self.mylog.debug(full_cmd)
        output = pipeToConsole(full_cmd)
        self.mylog.debug(output)

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
            self.mylog.error(f'getFrameRate had an invalid output: {output}')

    def getAudioTracks(self, file):
        output = self.pipe(['-select_streams', 'a', '-show_entries', 'stream=index',
            '-of', 'compact=p=0:nk=1', file]).strip()

        numbers = cleanList(output.split('\n'), '\r\t')
        self.log(f'Track data: {numbers}')
        if(numbers[0].isnumeric()):
            return len(numbers)
        else:
            self.mylog.warning('ffprobe had an invalid output.')
            return 1 # Assume there's one audio track.

    def getSubtitleTracks(self, file):
        output = self.pipe(['-select_streams', 's', '-show_entries', 'stream=index',
            '-of', 'compact=p=0:nk=1', file]).strip()

        numbers = cleanList(output.split('\n'), '\r\t')
        self.log(f'Track data: {numbers}')
        if(numbers[0].isnumeric()):
            return len(numbers)
        else:
            self.mylog.warning('Invalid output when detecting number of subtitle tracks.')
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
            return str(int(output) / 1000) + ' kHz'
        return 'N/A'

    def getPrettyBitrate(self, file, the_type='v', track=0) -> str:
        output = self.getBitrate(file, the_type, track)
        if(output.isnumeric()):
            # This does get used by ffmpeg so be careful.
            return str(round(int(output) / 1000)) + 'k'
        return 'N/A'

class FFmpeg():
    def __init__(self, dirPath, myFFmpeg: bool, FFdebug, log):

        self.mylog = log
        self.FFdebug = FFdebug

        newF = None
        if(system() == 'Windows' and not myFFmpeg):
            newF = path.join(dirPath, f'win-ffmpeg{sep()}bin{sep()}ffmpeg.exe')
        if(system() == 'Darwin' and not myFFmpeg):
            newF = path.join(dirPath, f'mac-ffmpeg{sep()}bin{sep()}ffmpeg')

        if(newF is not None and path.isfile(newF)):
            self.myPath = newF
        else:
            self.myPath = 'ffmpeg'
            try:
                pipeToConsole([self.myPath, '-h'])
            except FileNotFoundError:
                if(system() == 'Darwin'):
                    self.mylog.error('No ffmpeg found, download via homebrew or restore' \
                        ' the included binaries.')
                elif(system() == 'Windows'):
                    self.mylog.error('No ffmpeg found, download ffmpeg with your' \
                        ' favorite package manager (ex chocolatey), or restore the' \
                        ' included binaries.')
                else:
                    self.mylog.error('FFmpeg must be on PATH. Download ffmpeg by running:\n' \
                        '  sudo apt-get install libavformat-dev libavfilter-dev libavdevice-dev ffmpeg' \
                        '\nOr something similar depending on your distro.')

    def log(self, message):
        if(self.FFdebug):
            print(message)

    def getPath(self) -> str:
        return self.myPath

    def updateLog(self, log):
        self.mylog = log

    def run(self, cmd: list):
        cmd = [self.myPath, '-y'] + cmd
        if(self.FFdebug):
            cmd.extend(['-hide_banner'])
        else:
            cmd.extend(['-nostats', '-loglevel', 'error'])
        self.mylog.debug(cmd)

        subprocess.call(cmd)

    def Popen(self, cmd: list):
        cmd = [self.myPath] + cmd
        if(self.FFdebug):
            return subprocess.Popen(cmd, stdout=subprocess.PIPE)
        return subprocess.Popen(cmd, stdout=subprocess.PIPE, stderr=subprocess.DEVNULL)

    def pipe(self, cmd: list) -> str:
        cmd = [self.myPath, '-y'] + cmd

        self.mylog.debug(cmd)
        output = pipeToConsole(cmd)
        self.mylog.debug(output)

        return output

    def getVersion(self):
        ffmpegVersion = self.pipe(['-version']).split('\n')[0]
        ffmpegVersion = ffmpegVersion.replace('ffmpeg version', '').strip()
        return ffmpegVersion.split(' ')[0]

