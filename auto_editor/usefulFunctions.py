'''usefulFunctions.py'''

"""
To prevent duplicate code being pasted between scripts, common functions should be
put here. No function should modify or create video/audio files on its own.
"""

# Internal libraries
import sys
from shutil import get_terminal_size
from time import time, localtime

class Log():
    def __init__(self, show_debug=False, ffmpeg=False, quiet=False, temp=None):
        self.is_debug = show_debug
        self.is_ffmpeg = ffmpeg
        self.quiet = quiet
        self.temp = temp

    def debug(self, message):
        if(self.is_debug):
            print(message)

    def ffmpeg(self, message):
        if(self.is_ffmpeg):
            print(message)

    def cleanup(self):
        if(self.temp is None):
            return

        from shutil import rmtree
        rmtree(self.temp)

        if(self.is_debug):
            self.debug(f'   - Removed Temp Directory.')

    def error(self, message):
        print('Error!', message, file=sys.stderr)
        self.cleanup()
        sys.exit(1)

    # When something's definitely wrong with the program.
    def bug(self, message, bug_type='bug report'):
        print('Error!', message, f'\n\nCreate a {bug_type} at',
            'https://github.com/WyattBlue/auto-editor/issues/\n', file=sys.stderr)
        self.cleanup()
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


class FFprobe():
    def __init__(self, plat, dirPath, myFFmpeg: bool):
        from os import path

        newF = None
        if(plat == 'Windows' and not myFFmpeg):
            newF = path.join(dirPath, 'win-ffmpeg/bin/ffprobe.exe')
        if(plat == 'Darwin' and not myFFmpeg):
            newF = path.join(dirPath, 'mac-ffmpeg/bin/ffprobe')

        if(newF is not None and path.isfile(newF)):
            self.myPath = newF
        else:
            self.myPath = 'ffprobe'

    def getPath(self) -> str:
        return self.myPath

    def run(self, cmd: list):
        import subprocess
        subprocess.call([self.myPath] + cmd)

    def pipe(self, cmd: list) -> str:
        return pipeToConsole([self.myPath, '-v', 'error'] + cmd)


class FFmpeg():
    def __init__(self, plat, dirPath, myFFmpeg: bool, show: bool):
        from os import path

        self.show = show
        newF = None
        if(plat == 'Windows' and not myFFmpeg):
            newF = path.join(dirPath, 'win-ffmpeg/bin/ffmpeg.exe')
        if(plat == 'Darwin' and not myFFmpeg):
            newF = path.join(dirPath, 'mac-ffmpeg/bin/ffmpeg')

        if(newF is not None and path.isfile(newF)):
            self.myPath = newF
        else:
            self.myPath = 'ffmpeg'

    def getPath(self) -> str:
        return self.myPath

    def run(self, cmd: list):
        cmd = [self.myPath, '-y'] + cmd
        if(self.show):
            cmd.extend(['-hide_banner'])
        else:
            cmd.extend(['-nostats', '-loglevel', '8'])
        if(self.show):
            print(cmd)

        import subprocess
        subprocess.call(cmd)

    def pipe(self, cmd: list) -> str:
        cmd = [self.myPath, '-y'] + cmd

        if(self.show):
            print(cmd)
        output = pipeToConsole(cmd)
        if(self.show):
            print(output)

        return output


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
    def __init__(self, total, title='Please wait', machineReadable=False, hide=False):

        self.total = total
        self.beginTime = time()
        self.title = title
        self.len_title = len(title)
        self.machine = machineReadable
        self.hide = hide

        newTime = prettyTime(self.beginTime)
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

        newTime = prettyTime(self.beginTime + (percentPerSec * 100))

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
