'''utils/log.py'''

import sys
from shutil import rmtree, get_terminal_size
from time import perf_counter, sleep

class Timer():
    __slots__ = ['start_time', 'quiet']
    def __init__(self, quiet=False):
        self.start_time = perf_counter()
        self.quiet = quiet

    def stop(self):
        from datetime import timedelta

        second_len = round(perf_counter() - self.start_time, 2)
        minute_len = timedelta(seconds=round(second_len))
        if(not self.quiet):
            print('Finished. took {} seconds ({})'.format(second_len, minute_len))

class Log():
    __slots__ = ['is_debug', 'quiet', 'temp']
    def __init__(self, show_debug=False, quiet=False, temp=None):
        self.is_debug = show_debug
        self.quiet = quiet
        self.temp = temp

    def debug(self, message):
        if(self.is_debug):
            self.conwrite('')
            print('Debug: {}'.format(message), file=sys.stderr)

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

    def conwrite(self, message):
        if(not self.quiet):
            buffer = get_terminal_size().columns - len(message) - 3
            try:
                print('  ' + message + ' ' * buffer, end='\r', flush=True)
            except TypeError:
                print('  ' + message + ' ' * buffer, end='\r')

    def error(self, message):
        self.conwrite('')
        message = message.replace('\t', '    ')
        print('Error! {}'.format(message), file=sys.stderr)
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

    def bug(self, message, bug_type='bug report'):
        self.conwrite('')
        URL = 'https://github.com/WyattBlue/auto-editor/issues/'
        print('Error! {}\n\nSomething went wrong!\nCreate a {} at:\n  {}'.format(
            message, bug_type, URL), file=sys.stderr)
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
