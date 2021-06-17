'''validateInput.py'''

from __future__ import print_function

import os
import re
import sys

from auto_editor.utils.progressbar import ProgressBar

invalidExtensions = ['.txt', '.md', '.rtf', '.csv', '.cvs', '.html', '.htm',
      '.xml', '.yaml', '.png', '.jpeg', '.jpg', '.gif', '.exe', '.doc',
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


def sponsor_block_api(_id, log):
    # All categories:
    # ['sponsor', 'intro', 'outro', 'selfpromo', 'interaction', 'music_offtopic']
    from urllib import request as request
    from urllib.error import HTTPError
    import json
    try:
        contents = request.urlopen(
            'https://sponsor.ajay.app/api/skipSegments?videoID={}'.format(_id))
        return json.loads(contents.read())
    except HTTPError:
        log.error("Couldn't find skipSegments for id: {}".format(_id))

    """
    Example output:

    [
    {'category': 'sponsor', 'segment': [82.253, 99.75], 'UUID': 'db0f799...', 'videoDuration': 586},
    {'category': 'sponsor', 'segment': [525.1, 571.378], 'UUID': '5d1a16b...', 'videoDuration': 586}
    ]
    """

def download_video(my_input, args, log):
    if(args.block_sponsors):
        match = re.search(r'youtube\.com/watch\?v=(?P<match>[A-Za-z0-9_-]{11})', my_input)
        if(match):
            youtube_id =  match.groupdict()['match']
            sponsor_block_api(youtube_id, log)

    outtmpl = re.sub(r'\W+', '-', my_input)

    if(outtmpl.endswith('-mp4')):
        outtmpl = outtmpl[:-4]
    outtmpl += '.mp4'

    if(args.output_dir is not None):
        outtmpl = os.path.join(args.output_dir, outtmpl)

    try:
        import youtube_dl
    except ImportError:
        log.error('Download the youtube-dl python library to download URLs.\n' \
            '   pip3 install youtube-dl')

    if(not os.path.isfile(outtmpl)):
        ytbar = ProgressBar(100, 'Downloading')
        def my_hook(d):
            if(d['status'] == 'downloading'):
                ytbar.tick(float(d['_percent_str'].replace('%','')))

        ydl_opts = {
            'nocheckcertificate': not args.check_certificate,
            'outtmpl': outtmpl,
            'ffmpeg_location': ffmpeg.getPath(),
            'format': args.format,
            'logger': MyLogger(),
            'progress_hooks': [my_hook],
        }

        with youtube_dl.YoutubeDL(ydl_opts) as ydl:
            try:
                ydl.download([my_input])
            except youtube_dl.utils.DownloadError:
                log.conwrite('')
                log.error('YouTube-dl: Connection Refused.')

        log.conwrite('')
    return outtmpl


def _valid_files(path, bad_exts):
    # (path: str, badExts: list)
    for f in os.listdir(path):
        if(f[f.rfind('.'):] not in bad_exts and not os.path.isdir(f)
            and not f.startswith('.')):
            yield os.path.join(path, f)


def valid_input(inputs, ffmpeg, args, log):
    # (inputs: list, ffmpeg, args, log) -> list:
    new_inputs = []
    segments = []
    for my_input in inputs:
        if(os.path.isdir(my_input)):
            new_inputs += sorted(_valid_files(my_input, invalidExtensions))
        elif(os.path.isfile(my_input)):
            _, ext = os.path.splitext(my_input)
            if(ext == ''):
                log.error('File must have an extension.')

            if(ext in invalidExtensions):
                log.error('Invalid file extension "{}" for {}'.format(ext, my_input))
            new_inputs.append(my_input)
            segments.append(None)

        elif(my_input.startswith('http://') or my_input.startswith('https://')):
            output_template, segment = download_video(my_input, args, log)
            new_inputs.append(output_template)
            segments.append(segment)
        else:
            log.error('Could not find file: {}'.format(my_input))

    return new_inputs, segments
