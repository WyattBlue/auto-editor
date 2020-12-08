'''usefulFunctions.py'''

"""
To prevent duplicate code being pasted between scripts, common functions should be
put here. No code here should modify or create video/audio files.
"""

# Internal libraries
import sys
from shutil import get_terminal_size
from time import time, localtime

class Log():
    def __init__(self, show_debug=False, ffmpeg=False, quiet=False):
        self.is_debug = show_debug
        self.is_ffmpeg = ffmpeg
        self.quiet = quiet

    @staticmethod
    def error(message):
        print('Error!', message, file=sys.stderr)
        sys.exit(1)

    def warning(self, message):
        if(not self.quiet):
            print('Warning!', message, file=sys.stderr)

    def print(self, message, end='\n'):
        if(not self.quiet):
            print(message, end=end)

    def conwrite(self, message: str):
        if(not self.quiet):
            numSpaces = get_terminal_size().columns - len(message) - 3
            print('  ' + message + ' ' * numSpaces, end='\r', flush=True)

    # When something's definitely wrong with the program.
    @staticmethod
    def bug(message, bug_type='bug report'):
        print('Error!', message, f'\n\nCreate a {bug_type} at',
            'https://github.com/WyattBlue/auto-editor/issues/\n', file=sys.stderr)
        sys.exit(1)

    def checkType(self, data, name, correct_type):
        if(not isinstance(data, correct_type)):
            badtype = type(data).__name__
            goodtype = correct_type.__name__
            self.bug(f'Variable "{name}" was not a {goodtype}, but a {badtype}',
                'bug report')

    def debug(self, message):
        if(self.is_debug):
            print(message)

    def ffmpeg(self, message):
        if(self.is_ffmpeg):
            print(message)


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


def getBinaries(plat, dirPath, myFFmpeg: bool):
    from os import path

    newF = None
    newP = None
    if(plat == 'Windows' and not myFFmpeg):
        newF = path.join(dirPath, 'win-ffmpeg/bin/ffmpeg.exe')
        newP = path.join(dirPath, 'win-ffmpeg/bin/ffprobe.exe')
    if(plat == 'Darwin' and not myFFmpeg):
        newF = path.join(dirPath, 'mac-ffmpeg/bin/ffmpeg')
        newP = path.join(dirPath, 'mac-ffmpeg/bin/ffprobe')
    if(newF is not None and path.isfile(newF)):
        ffmpeg = newF
        ffprobe = newP
    else:
        ffmpeg = 'ffmpeg'
        ffprobe = 'ffprobe'
    return ffmpeg, ffprobe


def ffAddDebug(cmd: list, isFF: bool) -> list:
    if(isFF):
        cmd.extend(['-hide_banner'])
    else:
        cmd.extend(['-nostats', '-loglevel', '8'])
    return cmd


def getNewLength(chunks: list, speeds: list, fps: float) -> float:
    timeInFrames = 0
    for chunk in chunks:
        leng = chunk[1] - chunk[0]
        if(speeds[chunk[2]] < 99999):
            timeInFrames += leng * (1 / speeds[chunk[2]])
    return timeInFrames / fps


def prettyTime(myTime: float) -> str:
    newTime = localtime(myTime)

    hours = newTime.tm_hour
    minutes = newTime.tm_min

    if(hours == 0):
        hours = 12
    if(hours > 12):
        hours -= 12
    ampm = 'PM' if newTime.tm_hour >= 12 else 'AM'
    return f'{hours:02}:{minutes:02} {ampm}'


def bar(termsize, title, doneStr, togoStr, percentDone, newTime):
    bar = f'  ⏳{title}: [{doneStr}{togoStr}] {percentDone}% done ETA {newTime}'
    if(len(bar) > termsize - 2):
        bar = bar[:termsize - 2]
    else:
        bar += ' ' * (termsize - len(bar) - 4)
    print(bar, end='\r', flush=True)


class ProgressBar():
    def __init__(self, total, title='Please wait'):
        self.total = total
        self.beginTime = time()
        self.title = title
        self.len_title = len(title)

        newTime =  prettyTime(self.beginTime)
        termsize = get_terminal_size().columns
        try:
            barLen = max(1, termsize - (self.len_title + 50))
            bar(termsize, title, '', '░' * int(barLen), 0, newTime)
        except UnicodeEncodeError:
            print(f'   0% done ETA {newTime}')
            self.allow_unicode = False
        else:
            self.allow_unicode = True

    def tick(self, index):
        termsize = get_terminal_size().columns

        percentDone = min(100, round((index+1) / self.total * 100, 1))
        if(percentDone == 0): # Prevent dividing by zero.
            percentPerSec = 0
        else:
            percentPerSec = (time() - self.beginTime) / percentDone

        newTime = prettyTime(self.beginTime + (percentPerSec * 100))
        if(self.allow_unicode):
            barLen = max(1, termsize - (self.len_title + 50))
            done = round(percentDone / (100 / barLen))
            doneStr = '█' * done
            togoStr = '░' * int(barLen - done)
            bar(termsize, self.title, doneStr, togoStr, percentDone, newTime)
        else:
            print(f'   {percentDone}% done ETA {newTime}')


def isLatestVersion(version, log) -> bool:
    try:
        from requests import get
        latestVersion = get('https://raw.githubusercontent.com/' \
            'wyattblue/auto-editor/master/resources/version.txt')
        return latestVersion == version
    except ImportError:
        pass
    except Exception as err:
        log.debug('Connection Error: ' + str(err))

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
                log.warning('Could not open output file.')
