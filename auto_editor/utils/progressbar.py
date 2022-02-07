import sys
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


class ProgressBar():
    def tick(self, index):

        if self.hide:
            return

        percent = min(100, round((index+1) / self.total * 100, 1))
        if percent == 0:
            percent_rate = 0
        else:
            percent_rate = (time() - self.begin_time) / percent

        new_time = _pretty_time(self.begin_time + (percent_rate * 100), self.ampm)

        if self.machine:
            index = min(index, self.total)
            raw = int(self.begin_time + (percent_rate * 100))
            print('{}~{}~{}~{}~{}'.format(
                self.title, index, self.total, self.begin_time, raw),
                end='\r', flush=True)
            return

        columns = get_terminal_size().columns
        bar_len = max(1, columns - (self.len_title + 36))
        done_nums = round(percent / (100 / bar_len))

        done = self.done_char * done_nums
        togo = self.togo_char * int(bar_len - done_nums)

        bar = f'  {self.icon}{self.title}: [{done}{togo}] {percent}% done ETA {new_time}'

        if len(bar) > columns - 2:
            bar = bar[:columns - 2]
        else:
            bar += ' ' * (columns - len(bar) - 4)

        sys.stdout.write(bar + '\r')
        try:
            sys.stdout.flush()
        except AttributeError:
            pass

    def start(self, total, title='Please wait'):
        self.title = title
        self.len_title = len(title)
        self.total = total
        self.begin_time = time()

        try:
            self.tick(0)
        except UnicodeEncodeError:
            self.icon = '& '
            self.togo_char = '-'
            self.done_char = '#'

            self.tick(0)

    @staticmethod
    def end():
        sys.stdout.write(' ' * (get_terminal_size().columns - 2) + '\r')

    def __init__(self, machine_readable=False, hide=False):
        self.machine = machine_readable
        self.hide = hide

        self.icon = '⏳'
        self.togo_char = '░'
        self.done_char = '█'

        self.ampm = True
        if system() == 'Darwin' and not self.machine:
            try:
                date_format = get_stdout(['defaults', 'read', 'com.apple.menuextra.clock',
                    'DateFormat'])
                self.ampm = 'a' in date_format
            except FileNotFoundError:
                pass
