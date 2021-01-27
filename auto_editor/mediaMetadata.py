'''mediaMetadata.py'''

"""
Outdated, should eventually be replaced by the FFprobe class.
"""

from usefulFunctions import pipeToConsole
import re

def vidTracks(videoFile: str, ffprobe, log) -> int:
    """
    Return the number of audio tracks in a video file.
    """
    numbers = ffprobe.pipe([videoFile, '-hide_banner', '-show_entries', 'stream=index',
        '-select_streams', 'a', '-of', 'compact=p=0:nk=1']).split('\n')

    # Remove all \r chars that can appear in certain environments
    numbers = [s.replace('\r', '') for s in numbers]
    # Remove all blanks
    numbers = [s for s in numbers if s != '']

    log.ffmpeg('Track data: ' + str(numbers))
    if(numbers[0].isnumeric()):
        return len(numbers)
    else:
        log.warning('ffprobe had an invalid output.')
        return 1 # Assume there's one audio track.


def ffmpegFPS(ffmpeg, path: str, log) -> float:
    output = ffmpeg.pipe(['-i', path, '-hide_banner'])
    try:
        matchDict = re.search(r'\s(?P<fps>[\d\.]+?)\stbr', output).groupdict()
        return float(matchDict['fps'])
    except AttributeError:
        log.warning('frame rate detection failed.\n' \
            'If your video has a variable frame rate, ignore this message.')
        return 30.0
