'''usefulFunctions.py'''

"""
To prevent duplicate code being pasted between scripts, common functions should be
put here. No code here should modify or create video/audio files.
"""

# Internal libraries
from shutil import get_terminal_size
from time import time, localtime

class Log():
    def __init__(self, show_debug=False, ffmpeg=False):
        self.is_debug = show_debug
        self.is_ffmpeg = ffmpeg

    def error(message):
        print('Error!', message)
        import sys
        sys.exit(1)

    def warning(message):
        print('Warning!', message)

    def debug(self, message):
        if(self.is_debug):
            print(message)

    def ffmpeg(self, message):
        if(self.is_ffmpeg):
            print(message)


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


def getNewLength(chunks: list, speeds: list, fps: float) -> float:
    timeInFrames = 0
    for chunk in chunks:
        leng = chunk[1] - chunk[0]
        if(speeds[chunk[2]] < 99999):
            timeInFrames += leng * (1 / speeds[chunk[2]])
    return timeInFrames / fps


def prettyTime(newTime: float) -> str:
    newTime = localtime(newTime)
    hours = newTime.tm_hour

    if(hours == 0):
        hours = 12
    if(hours > 12):
        hours -= 12

    if(newTime.tm_hour >= 12):
        ampm = 'PM'
    else:
        ampm = 'AM'

    minutes = newTime.tm_min
    return f'{hours:02}:{minutes:02} {ampm}'


def vidTracks(videoFile: str, ffprobe: str, log) -> int:
    """
    Return the number of audio tracks in a video file.
    """
    import subprocess

    cmd = [ffprobe, videoFile, '-hide_banner', '-loglevel', 'panic',
        '-show_entries', 'stream=index', '-select_streams', 'a', '-of',
        'compact=p=0:nk=1']

    # Read what ffprobe piped in.
    process = subprocess.Popen(cmd, stdout=subprocess.PIPE, stderr=subprocess.STDOUT)
    stdout, __ = process.communicate()
    output = stdout.decode()
    numbers = output.split('\n')
    try:
        test = int(numbers[0])
        return len(numbers) - 1
    except ValueError:
        log.warning('ffprobe had an invalid output.')
        return 1 # Assume there's one audio track.


def conwrite(message: str):
    numSpaces = get_terminal_size().columns - len(message) - 3
    print('  ' + message + ' ' * numSpaces, end='\r', flush=True)


def progressBar(index, total, beginTime, title='Please wait'):
    termsize = get_terminal_size().columns
    barLen = max(1, termsize - (len(title) + 50))

    percentDone = round((index+1) / total * 100, 1)
    done = round(percentDone / (100 / barLen))
    doneStr = '█' * done
    togoStr = '░' * int(barLen - done)

    if(percentDone == 0): # Prevent dividing by zero.
        percentPerSec = 0
    else:
        percentPerSec = (time() - beginTime) / percentDone

    newTime = prettyTime(beginTime + (percentPerSec * 100))

    bar = f'  ⏳{title}: [{doneStr}{togoStr}] {percentDone}% done ETA {newTime}'
    if(len(bar) > termsize - 2):
        bar = bar[:termsize - 2]
    else:
        bar += ' ' * (termsize - len(bar) - 4)
    try:
        print(bar, end='\r', flush=True)
    except UnicodeEncodeError:
        print(f'   {percentDone}% done ETA {newTime}')
