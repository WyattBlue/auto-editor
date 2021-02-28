'''usefulFunctions.py'''

"""
To prevent duplicate code being pasted between scripts, common functions should be
put here. No function should modify or create video/audio files on its own.
"""

# Internal Libraries
import sys
from platform import system
from shutil import get_terminal_size
from time import time, localtime

class Log():
    def __init__(self, show_debug=False, quiet=False, temp=None):
        self.is_debug = show_debug
        self.quiet = quiet
        self.temp = temp

    def debug(self, message):
        if(self.is_debug):
            print(message)

    def cleanup(self):
        if(self.temp is None):
            return

        from shutil import rmtree
        rmtree(self.temp)
        self.debug('   - Removed Temp Directory.')

    def conwrite(self, message: str):
        if(not self.quiet):
            numSpaces = get_terminal_size().columns - len(message) - 3
            print('  ' + message + ' ' * numSpaces, end='\r', flush=True)

    def error(self, message):
        self.conwrite('')
        message = message.replace('\t', '    ')
        print('Error!', message, file=sys.stderr)
        self.cleanup()
        sys.exit(1)

    def bug(self, message, bug_type='bug report'):
        self.conwrite('')
        URL = 'https://github.com/WyattBlue/auto-editor/issues/'
        print('Error!', message,
            "\n\nThis is not a normal error.\n This message will only show up if there's",
            'something definitely wrong with the program.',
            f'\nCreate a {bug_type} at:\n  {URL}', file=sys.stderr)
        self.cleanup()
        sys.exit(1)

    def warning(self, message):
        if(not self.quiet):
            print('Warning!', message, file=sys.stderr)

    def print(self, message, end='\n'):
        if(not self.quiet):
            print(message, end=end)

    def checkType(self, data, name, correct_type):
        if(not isinstance(data, correct_type)):
            badtype = type(data).__name__
            goodtype = correct_type.__name__
            self.bug(f'Variable "{name}" was not a {goodtype}, but a {badtype}',
                'bug report')


class Timer():
    def __init__(self, quiet=False):
        self.start_time = time()
        self.quiet = quiet

    def stop(self):
        from datetime import timedelta

        timeLength = round(time() - self.start_time, 2)
        minutes = timedelta(seconds=round(timeLength))
        if(not self.quiet):
            print(f'Finished. took {timeLength} seconds ({minutes})')


def pipeToConsole(myCommands: list) -> str:
    import subprocess
    process = subprocess.Popen(myCommands, stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT)
    stdout, __ = process.communicate()
    return stdout.decode()


def sep() -> str:
    if(system() == 'Windows'):
        return '\\'
    return '/'


def cleanList(x: list, rm_chars: str) -> list:

    no = str.maketrans('', '', rm_chars)
    x = [s.translate(no) for s in x]
    x = [s for s in x if s != '']

    return x


class FFprobe():
    def __init__(self, dirPath, myFFmpeg: bool, FFdebug, log):
        from os import path

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
        import subprocess
        full_cmd = [self.myPath] + cmd

        if(None in cmd):
            self.mylog.bug(f'None in cmd. {cmd}')

        self.log(full_cmd)
        subprocess.call(full_cmd)

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

    def getFrameRate(self, file) -> float:
        # r_frame_rate is better than avg_frame_rate for getting constant frame rate.
        output = self.pipe(['-select_streams', 'v', '-show_entries',
            'stream=r_frame_rate', '-of', 'compact=p=0:nk=1', file]).strip()
        nums = output.split('/')
        nums = cleanList(nums, '\r\t\n')

        try:
            return int(nums[0]) / int(nums[1])
        except (ZeroDivisionError, IndexError, ValueError):
            self.mylog.error(f'getFrameRate had an invalid output: {output}')

    def getAudioTracks(self, file):
        output = self.pipe(['-select_streams', 'a', '-show_entries', 'stream=index',
            '-of', 'compact=p=0:nk=1', file]).strip()

        numbers = output.split('\n')
        # Remove extra characters that can appear in certain environments
        numbers = cleanList(numbers, '\r\t')

        self.log('Track data: ' + str(numbers))
        if(numbers[0].isnumeric()):
            return len(numbers)
        else:
            self.mylog.warning('ffprobe had an invalid output.')
            return 1 # Assume there's one audio track.

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

        from os import path

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
            cmd.extend(['-nostats', '-loglevel', '8'])
        self.mylog.debug(cmd)

        import subprocess
        subprocess.call(cmd)

    def pipe(self, cmd: list) -> str:
        cmd = [self.myPath, '-y'] + cmd

        self.mylog.debug(cmd)
        output = pipeToConsole(cmd)
        self.mylog.debug(output)

        return output


def getNewLength(chunks: list, speeds: list, fps: float) -> float:
    timeInFrames = 0
    for chunk in chunks:
        leng = chunk[1] - chunk[0]
        if(speeds[chunk[2]] < 99999):
            timeInFrames += leng * (1 / speeds[chunk[2]])
    return timeInFrames / fps


def prettyTime(myTime: float, ampm: bool) -> str:
    newTime = localtime(myTime)

    hours = newTime.tm_hour
    minutes = newTime.tm_min

    if(ampm):
        if(hours == 0):
            hours = 12
        if(hours > 12):
            hours -= 12
        ampm = 'PM' if newTime.tm_hour >= 12 else 'AM'
        return f'{hours:02}:{minutes:02} {ampm}'
    return f'{hours:02}:{minutes:02}'

def bar(termsize, title, doneStr, togoStr, percentDone, newTime):
    bar = f'  ⏳{title}: [{doneStr}{togoStr}] {percentDone}% done ETA {newTime}'
    if(len(bar) > termsize - 2):
        bar = bar[:termsize - 2]
    else:
        bar += ' ' * (termsize - len(bar) - 4)
    print(bar, end='\r', flush=True)


class ProgressBar():
    def __init__(self, total, title='Please wait', machineReadable=False, hide=False):

        self.total = total
        self.beginTime = time()
        self.title = title
        self.len_title = len(title)
        self.machine = machineReadable
        self.hide = hide
        self.ampm = True

        if(not self.machine):
            if(system() == 'Darwin'):
                try:
                    dateFormat = pipeToConsole(['defaults', 'read',
                        'com.apple.menuextra.clock', 'DateFormat'])
                    self.ampm = 'a' in dateFormat
                except FileNotFoundError:
                    pass

        newTime = prettyTime(self.beginTime, self.ampm)
        termsize = get_terminal_size().columns

        if(hide):
            pass
        elif(machineReadable):
            self.beginTime = round(self.beginTime)
            print(f'{title}~0~{total}~{self.beginTime}~{self.beginTime}', end='\r',
                flush=True)
        else:
            try:
                barLen = max(1, termsize - (self.len_title + 50))
                bar(termsize, title, '', '░' * int(barLen), 0, newTime)
            except UnicodeEncodeError:
                print(f'   0% done ETA {newTime}')
                self.allow_unicode = False
            else:
                self.allow_unicode = True

    def tick(self, index):

        if(self.hide):
            return

        percentDone = min(100, round((index+1) / self.total * 100, 1))
        if(percentDone == 0): # Prevent dividing by zero.
            percentPerSec = 0
        else:
            percentPerSec = (time() - self.beginTime) / percentDone

        newTime = prettyTime(self.beginTime + (percentPerSec * 100), self.ampm)

        if(self.machine):
            index = min(index, self.total)
            raw = int(self.beginTime + (percentPerSec * 100))
            print(f'{self.title}~{index}~{self.total}~{self.beginTime}~{raw}',
                end='\r', flush=True)
            return

        termsize = get_terminal_size().columns

        if(self.allow_unicode):
            barLen = max(1, termsize - (self.len_title + 50))
            done = round(percentDone / (100 / barLen))
            doneStr = '█' * done
            togoStr = '░' * int(barLen - done)
            bar(termsize, self.title, doneStr, togoStr, percentDone, newTime)
        else:
            print(f'   {percentDone}% done ETA {newTime}')


def isLatestVersion(version: str, log) -> bool:
    if('dev' not in version):
        try:
            from requests import get
            latestVersion = get('https://raw.githubusercontent.com/' \
                'wyattblue/auto-editor/master/resources/version.txt')
            return latestVersion.text == version
        except ImportError:
            pass
        except Exception as err:
            log.debug('Connection Error: ' + str(err))
    return True

def humanReadableTime(rawTime: float) -> str:
    units = 'seconds'
    if(rawTime >= 3600):
        rawTime = round(rawTime / 3600, 1)
        if(rawTime % 1 == 0):
            rawTime = round(rawTime)
        units = 'hours'
    if(rawTime >= 60):
        rawTime = round(rawTime / 60, 1)
        if(rawTime >= 10 or rawTime % 1 == 0):
            rawTime = round(rawTime)
        units = 'minutes'
    return f'{rawTime} {units}'

def smartOpen(newOutput: str, log):
    from subprocess import call
    try:  # should work on Windows
        from os import startfile
        startfile(newOutput)
    except (AttributeError, ImportError):
        try:  # should work on MacOS and most Linux versions
            call(['open', newOutput])
        except:
            try: # should work on WSL2
                call(['cmd.exe', '/C', 'start', newOutput])
            except:
                try: # should work on various other Linux distros
                    call(['xdg-open', newOutput])
                except:
                    log.warning('Could not open output file.')

def hex_to_bgr(inp: str, log) -> list:
    import re
    if(re.compile(r'#[a-fA-F0-9]{3}(?:[a-fA-F0-9]{3})?$').match(inp)):
        if(len(inp) < 5):
            return [int(inp[i]*2, 16) for i in (3, 2, 1)]
        return [int(inp[i:i+2], 16) for i in (5, 3, 1)]
    else:
        log.error(f'Invalid hex code: {inp}')
