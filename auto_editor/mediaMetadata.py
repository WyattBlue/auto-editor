'''mediaMetadata.py'''

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


def getVideoCodec(file: str, ffmpeg, log, vcodec: str) -> str:
    if(vcodec == 'copy'):
        output = ffmpeg.pipe(['-i', file, '-hide_banner'])
        try:
            matchDict = re.search(r'Video:\s(?P<grp>\w+?)\s', output).groupdict()
            vcodec = matchDict['grp']
            log.debug('Video Codec: ' + str(vcodec))
        except AttributeError:
            log.warning("Couldn't automatically detect video codec.")
    if(vcodec is None or vcodec == 'uncompressed'):
        vcodec = 'mpeg4'
    return vcodec


def getAudioCodec(ffprobe, file):
    return ffprobe.pipe(['-select_streams', 'a:0', '-show_entries', 'stream=codec_name',
        '-of', 'compact=p=0:nk=1', file]).strip()


def getSampleRate(file: str, ffmpeg, sr) -> str:
    if(sr is None):
        output = ffmpeg.pipe(['-i', file, '-hide_banner'])
        try:
            matchDict = re.search(r'\s(?P<grp>\w+?)\sHz', output).groupdict()
            return matchDict['grp']
        except AttributeError:
            return '48000'
    return str(sr)


def getAudioBitrate(file: str, ffprobe, log, abit: str) -> str:
    if(abit is None):
        if(file.endswith('.mkv')):
            return None
        else:
            output = ffprobe.pipe(['-select_streams',
                'a:0', '-show_entries', 'stream=bit_rate', '-of',
                'compact=p=0:nk=1', file]).strip()
            if(output.isnumeric()):
                return str(round(int(output) / 1000)) + 'k'
            else:
                log.warning("Couldn't automatically detect audio bitrate.")
                log.debug('Setting audio bitrate to 500k')
                log.debug(f'Output: {output}')
                return '500k'
    return str(abit)


def ffmpegFPS(ffmpeg, path: str, log) -> float:
    output = ffmpeg.pipe(['-i', path, '-hide_banner'])
    try:
        matchDict = re.search(r'\s(?P<fps>[\d\.]+?)\stbr', output).groupdict()
        return float(matchDict['fps'])
    except AttributeError:
        log.warning('frame rate detection failed.\n' \
            'If your video has a variable frame rate, ignore this message.')
        return 30.0
