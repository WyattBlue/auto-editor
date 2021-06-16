'''utils/progressbar.py'''

from __future__ import print_function

from time import time, localtime
from platform import system
from shutil import get_terminal_size

from .func import get_stdout

def _pretty_time(my_time: float, ampm: bool) -> str:
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

        if(system() == 'Darwin' and not self.machine):
            try:
                dateFormat = get_stdout(['defaults', 'read',
                    'com.apple.menuextra.clock', 'DateFormat'])
                self.ampm = 'a' in dateFormat
            except FileNotFoundError:
                pass

        self.allow_unicode = True
        try:
            self.tick(0)
        except UnicodeEncodeError:
            newTime = _pretty_time(self.beginTime, self.ampm)
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

        new_time = _pretty_time(self.beginTime + (percentPerSec * 100), self.ampm)

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
