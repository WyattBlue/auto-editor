'''validateInput.py'''

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

def validFiles(path: str, badExts: list):
    for f in os.listdir(path):
        if(f[f.rfind('.'):] not in badExts and not os.path.isdir(f)
            and not f.startswith('.')):
            yield os.path.join(path, f)


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


def validInput(inputs: list, ffmpeg, args, log) -> list:
    inputList = []
    for myInput in inputs:
        if(os.path.isdir(myInput)):
            inputList += sorted(validFiles(myInput, invalidExtensions))
        elif(os.path.isfile(myInput)):

            _, fileFormat = os.path.splitext(myInput)
            if(fileFormat == ''):
                log.error('File must have an extension.')

            if(fileFormat in invalidExtensions):
                log.error('Invalid file extension "{}" for {}'.format(fileFormat, myInput))
            inputList.append(myInput)

        elif(myInput.startswith('http://') or myInput.startswith('https://')):
            outtmpl = re.sub(r'\W+', '-', myInput)

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
                    nonlocal ytbar
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
                        ydl.download([myInput])
                    except youtube_dl.utils.DownloadError:
                        log.conwrite('')
                        log.error('YouTube-dl: Connection Refused.')

                log.conwrite('')

            inputList.append(outtmpl)
        else:
            log.error('Could not find file: {}'.format(myInput))

    return inputList
