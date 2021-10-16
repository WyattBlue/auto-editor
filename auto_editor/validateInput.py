'''validateInput.py'''

import os
import re
import sys

from auto_editor.utils.progressbar import ProgressBar

invalidExtensions = ['.txt', '.md', '.rtf', '.csv', '.cvs', '.html', '.htm',
      '.xml', '.yaml', '.png', '.jpeg', '.jpg', '.exe', '.doc',
      '.docx', '.odt', '.pptx', '.xlsx', '.xls', 'ods', '.pdf', '.bat', '.dll',
      '.prproj', '.psd', '.aep', '.zip', '.rar', '.7z', '.java', '.class', '.js',
      '.c', '.cpp', '.csharp', '.py', '.app', '.git', '.github', '.gitignore',
      '.db', '.ini', '.BIN', '.svg', '.in', '.pyc', '.log', '.xsd', '.ffpreset',
      '.kys', '.essentialsound']

class MyLogger(object):
    @staticmethod
    def debug(msg):
        pass

    @staticmethod
    def warning(msg):
        print(msg, file=sys.stderr)

    @staticmethod
    def error(msg):
        if("'Connection refused'" in msg):
            pass
        else:
            print(msg, file=sys.stderr)


def parse_bytes(bytestr):
    # Parse a string indicating a byte quantity into an integer.
    matchobj = re.match(r'(?i)^(\d+(?:\.\d+)?)([kMGTPEZY]?)$', bytestr)
    if(matchobj is None):
        return None
    number = float(matchobj.group(1))
    multiplier = 1024.0 ** 'bkmgtpezy'.index(matchobj.group(2).lower())
    return round(number * multiplier)


def sponsor_block_api(_id, categories, log):
    # type: (str, list, Any) -> dict
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

def download_video(my_input, args, ffmpeg, log):
    outtmpl = re.sub(r'\W+', '-', my_input)
    if(outtmpl.endswith('-mp4')):
        outtmpl = outtmpl[:-4]
    outtmpl += '.mp4'

    if(args.output_dir is not None):
        outtmpl = os.path.join(args.output_dir, outtmpl)

    try:
        import youtube_dl
    except ImportError:
        log.error('Download the youtube-dl python library to download URLs.\n'
            '   pip3 install youtube-dl')

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
            'ffmpeg_location': ffmpeg.getPath(),
            'format': args.format,
            'ratelimit': parse_bytes(args.limit_rate),
            'logger': MyLogger(),
            'cookiefile': abspath(args.cookies),
            'download_archive': abspath(args.download_archive),
            'progress_hooks': [my_hook],
        }

        for item, key in ydl_opts.items():
            if(item is None):
                del ydl_opts[key]

        with youtube_dl.YoutubeDL(ydl_opts) as ydl:
            try:
                ydl.download([my_input])
            except youtube_dl.utils.DownloadError:
                log.conwrite('')
                log.error('YouTube-dl: Connection Refused.')

        log.conwrite('')
    return outtmpl

def _valid_files(path, bad_exts):
    for f in os.listdir(path):
        if(f[f.rfind('.'):] not in bad_exts and not os.path.isdir(f)
            and not f.startswith('.')):
            yield os.path.join(path, f)

def get_segment(args, my_input, log):
    if(args.block is not None):
        if(args.id is not None):
            return sponsor_block_api(args.id, args.block, log)
        match = re.search(r'youtube\.com/watch\?v=(?P<match>[A-Za-z0-9_-]{11})',
            my_input)
        if(match):
            youtube_id = match.groupdict()['match']
            return sponsor_block_api(youtube_id, args.block, log)
    return None

def valid_input(inputs, ffmpeg, args, log):
    new_inputs = []
    segments = []
    for my_input in inputs:
        if(os.path.isdir(my_input)):
            new_inputs += sorted(_valid_files(my_input, invalidExtensions))
            segments += [None] * (len(new_inputs) - len(segments))
        elif(os.path.isfile(my_input)):
            _, ext = os.path.splitext(my_input)
            if(ext == ''):
                log.error('File must have an extension.')

            if(ext in invalidExtensions):
                log.error('Invalid file extension "{}" for {}'.format(ext, my_input))
            new_inputs.append(my_input)
            segments.append(get_segment(args, my_input, log))

        elif(my_input.startswith('http://') or my_input.startswith('https://')):
            new_inputs.append(download_video(my_input, args, ffmpeg, log))
            segments.append(get_segment(args, my_input, log))
        else:
            log.error('Could not find file: {}'.format(my_input))

    return new_inputs, segments
