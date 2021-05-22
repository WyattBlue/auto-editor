'''usefulFunctions.py'''

"""
To prevent duplicate code being pasted between scripts, common functions should be
put here. No function should modify or create video/audio files on its own.
"""

# Internal Libraries
import sys
from platform import system
from shutil import rmtree, get_terminal_size
from time import time, localtime, sleep

class Log():
    def __init__(self, show_debug=False, quiet=False, temp=None):
        self.is_debug = show_debug
        self.quiet = quiet
        self.temp = temp

    def debug(self, message):
        if(self.is_debug):
            self.conwrite('')
            print('debug {}'.format(message))

    def cleanup(self):
        if(self.temp is None):
            return
        try:
            rmtree(self.temp)
            self.debug('Removed Temp Directory.')
        except PermissionError:
            sleep(0.1)
            try:
                rmtree(self.temp)
                self.debug('Removed Temp Directory.')
            except PermissionError:
                self.debug('Failed to delete temp dir.')

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
            '\nCreate a {} at:\n  {}'.format(bug_type, URL), file=sys.stderr)
        self.cleanup()
        sys.exit(1)

    def warning(self, message):
        if(not self.quiet):
            print('Warning! {}'.format(message), file=sys.stderr)

    def print(self, message, end='\n'):
        if(not self.quiet):
            print(message, end=end)

    def checkType(self, data, name, correct_type):
        if(not isinstance(data, correct_type)):
            badtype = type(data).__name__
            goodtype = correct_type.__name__
            self.bug('Variable "{}" was not a {}, but a {}'.format(
                name, goodtype, badtype), 'bug report')


class Timer():
    def __init__(self, quiet=False):
        self.start_time = time()
        self.quiet = quiet

    def stop(self):
        from datetime import timedelta

        second_len = round(time() - self.start_time, 2)
        minute_len = timedelta(seconds=round(second_len))
        if(not self.quiet):
            print('Finished. took {} seconds ({})'.format(second_len, minute_len))


def pipeToConsole(myCommands: list) -> str:
    import subprocess
    process = subprocess.Popen(myCommands, stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT)
    stdout, __ = process.communicate()
    return stdout.decode()

def cleanList(x: list, rm_chars: str) -> list:
    no = str.maketrans('', '', rm_chars)
    x = [s.translate(no) for s in x]
    return [s for s in x if s != '']

def getNewLength(chunks: list, speeds: list, fps: float) -> float:
    timeInFrames = 0
    for chunk in chunks:
        leng = chunk[1] - chunk[0]
        if(speeds[chunk[2]] < 99999):
            timeInFrames += leng * (1 / speeds[chunk[2]])
    return timeInFrames / fps

def prettyTime(my_time: float, ampm: bool) -> str:
    new_time = localtime(my_time)

    hours = new_time.tm_hour
    minutes = new_time.tm_min

    if(ampm):
        if(hours == 0):
            hours = 12
        if(hours > 12):
            hours -= 12
        ampm = 'PM' if new_time.tm_hour >= 12 else 'AM'
        return '{:02}:{:02} {}'.format(hours, minutes, ampm)
    return '{:02}:{:02}'.format(hours, minutes)

def bar(termsize, title, done, togo, percent, new_time):
    bar = '  ⏳{}: [{}{}] {}% done ETA {}'.format(title, done, togo, percent, new_time)
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

        self.allow_unicode = True
        try:
            self.tick(0)
        except UnicodeEncodeError:
            newTime = prettyTime(self.beginTime, self.ampm)
            print('   0% done ETA {}'.format(newTime))
            self.allow_unicode = False

    def tick(self, index):

        if(self.hide):
            return

        percentDone = min(100, round((index+1) / self.total * 100, 1))
        if(percentDone == 0): # Prevent dividing by zero.
            percentPerSec = 0
        else:
            percentPerSec = (time() - self.beginTime) / percentDone

        new_time = prettyTime(self.beginTime + (percentPerSec * 100), self.ampm)

        if(self.machine):
            index = min(index, self.total)
            raw = int(self.beginTime + (percentPerSec * 100))
            print('{}~{}~{}~{}~{}'.format(
                self.title, index, self.total, self.beginTime, raw),
                end='\r', flush=True)
            return

        termsize = get_terminal_size().columns

        if(self.allow_unicode):
            bar_len = max(1, termsize - (self.len_title + 50))
            done = round(percentDone / (100 / bar_len))
            togo = '░' * int(bar_len - done)
            bar(termsize, self.title, '█' * done, togo, percentDone, new_time)
        else:
            print('   {}% done ETA {}'.format(percentDone, new_time))

def humanReadableTime(time_in_secs: float) -> str:
    units = 'seconds'
    if(time_in_secs >= 3600):
        time_in_secs = round(time_in_secs / 3600, 1)
        if(time_in_secs % 1 == 0):
            time_in_secs = round(time_in_secs)
        units = 'hours'
    if(time_in_secs >= 60):
        time_in_secs = round(time_in_secs / 60, 1)
        if(time_in_secs >= 10 or time_in_secs % 1 == 0):
            time_in_secs = round(time_in_secs)
        units = 'minutes'
    return '{} {}'.format(time_in_secs, units)

def openWithSystemDefault(path: str, log):
    from subprocess import call
    try:  # should work on Windows
        from os import startfile
        startfile(path)
    except ImportError:
        try:  # should work on MacOS and most Linux versions
            call(['open', path])
        except Exception as err:
            try: # should work on WSL2
                call(['cmd.exe', '/C', 'start', path])
            except Exception as err:
                try: # should work on various other Linux distros
                    call(['xdg-open', path])
                except Exception as err:
                    log.warning('Could not open output file.')

def hex_to_bgr(inp: str, log) -> list:
    import re
    if(re.compile(r'#[a-fA-F0-9]{3}(?:[a-fA-F0-9]{3})?$').match(inp)):
        if(len(inp) < 5):
            return [int(inp[i]*2, 16) for i in (3, 2, 1)]
        return [int(inp[i:i+2], 16) for i in (5, 3, 1)]
    else:
        log.error('Invalid hex code: {}'.format(inp))

def fNone(val):
    return val == 'none' or val == 'unset' or val is None
