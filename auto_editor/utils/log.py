'''utils/log.py'''

from typing import NoReturn

import sys
from shutil import rmtree, get_terminal_size
from time import perf_counter, sleep
from datetime import timedelta

class Timer():
    __slots__ = ['start_time', 'quiet']
    def __init__(self, quiet=False):
        self.start_time = perf_counter()
        self.quiet = quiet

    def stop(self):
        if(not self.quiet):
            second_len = round(perf_counter() - self.start_time, 2)
            minute_len = timedelta(seconds=round(second_len))

            sys.stdout.write(f'Finished. took {second_len} seconds ({minute_len})\n')

class Log():
    __slots__ = ['is_debug', 'quiet', 'temp']
    def __init__(self, show_debug=False, quiet=False, temp=None):
        self.is_debug = show_debug
        self.quiet = quiet
        self.temp = temp

    def debug(self, message: str):
        if(self.is_debug):
            self.conwrite('')
            sys.stderr.write(f'Debug: {message}\n')

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
            except Exception:
                self.debug('Failed to delete temp dir.')
        except FileNotFoundError:
            # that's ok, the folder we are trying to remove is already gone
            pass

    def conwrite(self, message: str):
        if(not self.quiet):
            buffer = get_terminal_size().columns - len(message) - 3
            sys.stdout.write('  ' + message + ' ' * buffer + '\r')
            try:
                sys.stdout.flush()
            except AttributeError:
                pass

    def error(self, message: str) -> NoReturn:
        self.conwrite('')
        message = message.replace('\t', '    ')
        sys.stderr.write(f'Error! {message}\n')
        self.cleanup()

        from platform import system

        if(system() == 'Linux'):
            sys.exit(1)
        else:
            try:
                sys.exit(1)
            except SystemExit:
                import os
                os._exit(1)

    def bug(self, message: str, bug_type='bug report') -> NoReturn:
        self.conwrite('')
        URL = 'https://github.com/WyattBlue/auto-editor/issues/'

        sys.stderr.write(
            'Error! {}\n\nSomething went wrong!\nCreate a {} at:\n  {}\n'.format(
                message, bug_type, URL))
        self.cleanup()
        sys.exit(1)

    def warning(self, message: str):
        if(not self.quiet):
            sys.stderr.write(f'Warning! {message}\n')

    def print(self, message: str):
        if(not self.quiet):
            sys.stdout.write(f'{message}\n')

    def checkType(self, data, name, correct_type):
        if(not isinstance(data, correct_type)):
            badtype = type(data).__name__
            goodtype = correct_type.__name__
            self.bug('Variable "{}" was not a {}, but a {}'.format(
                name, goodtype, badtype), 'bug report')
