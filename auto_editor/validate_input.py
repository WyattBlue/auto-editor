'''validate_input.py'''

import os
import re
import sys

from auto_editor.utils.progressbar import ProgressBar
from auto_editor.utils.log import Log
from typing import Optional

class MyLogger():
    @staticmethod
    def debug(msg):
        print(msg)

    @staticmethod
    def warning(msg):
        print(msg, file=sys.stderr)

    @staticmethod
    def error(msg):
        if("'Connection refused'" in msg):
            pass
        else:
            print(msg, file=sys.stderr)


def parse_bytes(bytestr) -> Optional[int]:
    # Parse a string indicating a byte quantity into an integer.
    matchobj = re.match(r'(?i)^(\d+(?:\.\d+)?)([kMGTPEZY]?)$', bytestr)
    if(matchobj is None):
        return None
    number = float(matchobj.group(1))
    multiplier = 1024.0 ** 'bkmgtpezy'.index(matchobj.group(2).lower())
    return round(number * multiplier)


def sponsor_block_api(_id: str, categories: list, log: Log) -> Optional[dict]:
    from urllib import request
    from urllib.error import HTTPError
    import json

    cat_url = 'categories=['
    for i, cat in enumerate(categories):
        if(i == 0):
            cat_url += '"{}"'.format(cat)
        else:
            cat_url += ',"{}"'.format(cat)
    cat_url += ']'

    try:
        contents = request.urlopen(
            'https://sponsor.ajay.app/api/skipSegments?videoID={}&{}'.format(_id, cat_url))
        return json.loads(contents.read())
    except HTTPError:
        log.warning("Couldn't find skipSegments for id: {}".format(_id))
        return None

def download_video(my_input, args, ffmpeg, log: Log):
    log.conwrite('Downloading video...')
    if('@' in my_input):
        res = my_input[my_input.index('@')+1:]
        if(' ' in res):
            res = res[:res.index(' ')]
        res = res.strip()
        my_input= my_input[:my_input.index(' ')]
    else:
        res = '720'

    outtmpl = re.sub(r'\W+', '-', my_input)
    if(outtmpl.endswith('-mp4')):
        outtmpl = outtmpl[:-4]
    outtmpl += '.mp4'

    if(args.download_dir is not None):
        outtmpl = os.path.join(args.download_dir, outtmpl)

    try:
        import yt_dlp
    except ImportError:
        log.error('Download the yt-dlp python library to download URLs.\n'
            '   pip3 install yt-dlp')

    if(not os.path.isfile(outtmpl)):
        ytbar = ProgressBar(100, 'Downloading')
        def my_hook(d):
            if(d['status'] == 'downloading'):
                ytbar.tick(float(d['_percent_str'].replace('%','')))

        def abspath(path):
            if(path is None):
                return None
            return os.path.abspath(path)

        ydl_opts = {
            'nocheckcertificate': not args.check_certificate,
            'outtmpl': outtmpl,
            'ffmpeg_location': ffmpeg.path,
            'format': f'bestvideo[ext=mp4][height<={res}]+bestaudio[ext=m4a]',
            'ratelimit': parse_bytes(args.limit_rate),
            'logger': MyLogger(),
            'cookiefile': abspath(args.cookies),
            'download_archive': abspath(args.download_archive),
            'progress_hooks': [my_hook],
        }

        for item, key in ydl_opts.items():
            if(item is None):
                del ydl_opts[key]

        try:
            with yt_dlp.YoutubeDL(ydl_opts) as ydl:
                ydl.download([my_input])
        except yt_dlp.utils.DownloadError as error:
            if('format is not available' in str(error)):
                del ydl_opts['format']
                with yt_dlp.YoutubeDL(ydl_opts) as ydl:
                    ydl.download([my_input])
            else:
                log.error('yt-dlp: Download Error.')

        log.conwrite('')
    return outtmpl


def get_segment(args, my_input, log: Log):
    if(args.block is not None):
        if(args.id is not None):
            return sponsor_block_api(args.id, args.block, log)
        match = re.search(r'youtube\.com/watch\?v=(?P<match>[A-Za-z0-9_-]{11})',
            my_input)
        if(match):
            youtube_id = match.groupdict()['match']
            return sponsor_block_api(youtube_id, args.block, log)
    return None

def valid_input(inputs, ffmpeg, args, log: Log):
    new_inputs = []
    segments = []
    for my_input in inputs:
        if(os.path.isfile(my_input)):
            _, ext = os.path.splitext(my_input)
            if(ext == ''):
                log.error('File must have an extension.')

            new_inputs.append(my_input)
            segments.append(get_segment(args, my_input, log))

        elif(my_input.startswith('http://') or my_input.startswith('https://')):
            new_inputs.append(download_video(my_input, args, ffmpeg, log))
            segments.append(get_segment(args, my_input, log))
        else:
            if(os.path.isdir(my_input)):
                log.error('Input must be a file or url.')
            log.error('Could not find file: {}'.format(my_input))

    return new_inputs, segments
