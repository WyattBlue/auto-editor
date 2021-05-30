'''usefulFunctions.py'''

"""
To prevent duplicate code being pasted between scripts, common functions should be
put here. No function should modify or create video/audio files on its own.
"""

def pipeToConsole(cmd):
    import subprocess
    process = subprocess.Popen(cmd, stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT)
    stdout, __ = process.communicate()
    return stdout.decode()

def cleanList(x: list, rm_chars: str):
    no = str.maketrans('', '', rm_chars)
    x = [s.translate(no) for s in x]
    return [s for s in x if s != '']

def aspect_ratio(width: int, height: int):
    if(height == 0):
        return None, None

    def gcd(a, b):
        while b:
            a, b = b, a % b
        return a

    c = gcd(width, height)
    return width // c, height // c

def getNewLength(chunks: list, speeds: list, fps: float):
    timeInFrames = 0
    for chunk in chunks:
        leng = chunk[1] - chunk[0]
        if(speeds[chunk[2]] < 99999):
            timeInFrames += leng * (1 / speeds[chunk[2]])
    return timeInFrames / fps

def humanReadableTime(time_in_secs):
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

def openWithSystemDefault(path, log):
    from subprocess import call
    try:  # should work on Windows
        from os import startfile
        startfile(path)
    except ImportError:
        try:  # should work on MacOS and most Linux versions
            call(['open', path])
        except Exception:
            try: # should work on WSL2
                call(['cmd.exe', '/C', 'start', path])
            except Exception:
                try: # should work on various other Linux distros
                    call(['xdg-open', path])
                except Exception:
                    log.warning('Could not open output file.')

def hex_to_bgr(hex_str, log):
    import re
    if(re.compile(r'#[a-fA-F0-9]{3}(?:[a-fA-F0-9]{3})?$').match(hex_str)):
        if(len(hex_str) < 5):
            return [int(hex_str[i]*2, 16) for i in (3, 2, 1)]
        return [int(hex_str[i:i+2], 16) for i in (5, 3, 1)]
    log.error('Invalid hex code: {}'.format(hex_str))

def fNone(val):
    return val == 'none' or val == 'unset' or val is None
