'''mediaMetadata.py'''

from usefulFunctions import pipeToConsole
import re

def vidTracks(videoFile: str, ffprobe: str, log) -> int:
    """
    Return the number of audio tracks in a video file.
    """
    numbers = pipeToConsole([ffprobe, videoFile, '-hide_banner', '-loglevel',
        'panic', '-show_entries', 'stream=index', '-select_streams', 'a', '-of',
        'compact=p=0:nk=1']).split('\n')

    # Remove all \r chars that can appear in certain environments
    numbers = [s.replace('\r', '') for s in numbers]

    log.ffmpeg('Track data: ' + str(numbers))
    if(numbers[0].isnumeric()):
        return len(numbers) - 1
    else:
        log.warning('ffprobe had an invalid output.')
        return 1 # Assume there's one audio track.


def getVideoCodec(file: str, ffmpeg: str, log, vcodec: str) -> str:
    if(vcodec == 'copy'):
        output = pipeToConsole([ffmpeg, '-i', file, '-hide_banner'])
        try:
            matchDict = re.search(r'Video:\s(?P<grp>\w+?)\s', output).groupdict()
            vcodec = matchDict['grp']
            log.debug('Video Codec: ' + str(vcodec))
        except AttributeError:
            log.warning("Couldn't automatically detect video codec.")
    if(vcodec is None or vcodec == 'uncompressed'):
        vcodec = 'copy'
    return vcodec


def getSampleRate(file: str, ffmpeg: str, sr) -> str:
    if(sr is None):
        output = pipeToConsole([ffmpeg, '-i', file, '-hide_banner'])
        try:
            matchDict = re.search(r'\s(?P<grp>\w+?)\sHz', output).groupdict()
            return matchDict['grp']
        except AttributeError:
            return '48000'
    return str(sr)


def getAudioBitrate(file: str, ffprobe: str, log, abit: str) -> str:
    if(abit is None):
        if(file.endswith('.mkv')):
            return None
        else:
            output = pipeToConsole([ffprobe, '-v', 'error', '-select_streams',
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


def ffmpegFPS(ffmpeg: str, path: str, log) -> float:
    output = pipeToConsole([ffmpeg, '-i', path, '-hide_banner'])
    try:
        matchDict = re.search(r'\s(?P<fps>[\d\.]+?)\stbr', output).groupdict()
        return float(matchDict['fps'])
    except AttributeError:
        log.warning('frame rate detection failed.\n' \
            'If your video has a variable frame rate, ignore this message.')
        return 30.0
