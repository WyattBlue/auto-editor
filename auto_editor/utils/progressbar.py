'''utils/progressbar.py'''

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
        ampm_marker = 'PM' if new_time.tm_hour >= 12 else 'AM'
        return '{:02}:{:02} {}'.format(hours, minutes, ampm_marker)
    return '{:02}:{:02}'.format(hours, minutes)

def bar(columns, title, done, togo, percent, new_time):
    bar = '  ⏳{}: [{}{}] {}% done ETA {}'.format(title, done, togo, percent, new_time)
    if(len(bar) > columns - 2):
        bar = bar[:columns - 2]
    else:
        bar += ' ' * (columns - len(bar) - 4)
    try:
        print(bar, end='\r', flush=True)
    except TypeError:
        print(bar, end='\r')


class ProgressBar():
    def tick(self, index):

        if(self.hide):
            return

        percentDone = min(100, round((index+1) / self.total * 100, 1))
        if(percentDone == 0): # Prevent dividing by zero.
            percentPerSec = 0
        else:
            percentPerSec = (time() - self.begin_time) / percentDone

        new_time = _pretty_time(self.begin_time + (percentPerSec * 100), self.ampm)

        if(self.machine):
            index = min(index, self.total)
            raw = int(self.begin_time + (percentPerSec * 100))
            print('{}~{}~{}~{}~{}'.format(
                self.title, index, self.total, self.begin_time, raw),
                end='\r', flush=True)
            return

        columns = get_terminal_size().columns

        if(self.allow_unicode):
            bar_len = max(1, columns - (self.len_title + 50))
            done = round(percentDone / (100 / bar_len))
            togo = '░' * int(bar_len - done)
            bar(columns, self.title, '█' * done, togo, percentDone, new_time)
        else:
            print('   {}% done ETA {}'.format(percentDone, new_time))

    def start(self, total, title='Please wait'):
        self.title = title
        self.len_title = len(title)
        self.total = total
        self.begin_time = time()

        if(self.allow_unicode is None):
            self.allow_unicode = True
            try:
                self.tick(0)
            except UnicodeEncodeError:
                self.allow_unicode = False
                self.tick(0)
        else:
            self.tick(0)

    @staticmethod
    def end():
        print(' ' * max(1, get_terminal_size().columns - 2), end='\r')

    def __init__(self, machine_readable=False, hide=False):
        self.machine = machine_readable
        self.hide = hide
        self.allow_unicode = None

        self.ampm = True
        if(system() == 'Darwin' and not self.machine):
            try:
                date_format = get_stdout(['defaults', 'read',
                    'com.apple.menuextra.clock', 'DateFormat'])
                self.ampm = 'a' in date_format
            except FileNotFoundError:
                pass
