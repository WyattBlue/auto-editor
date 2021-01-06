import os
import re
import sys

invalidExtensions = ['.txt', '.md', '.rtf', '.csv', '.cvs', '.html', '.htm',
      '.xml', '.yaml', '.png', '.jpeg', '.jpg', '.gif', '.exe', '.doc',
      '.docx', '.odt', '.pptx', '.xlsx', '.xls', 'ods', '.pdf', '.bat', '.dll',
      '.prproj', '.psd', '.aep', '.zip', '.rar', '.7z', '.java', '.class', '.js',
      '.c', '.cpp', '.csharp', '.py', '.app', '.git', '.github', '.gitignore',
      '.db', '.ini', '.BIN', '.svg', '.in', '.pyc', '.log', '.xsd', '.ffpreset',
      '.kys', '.essentialsound', '']

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


def validInput(inputs: list, ffmpeg, log) -> list:
    inputList = []
    for myInput in inputs:
        if(os.path.isdir(myInput)):
            inputList += sorted(validFiles(myInput, invalidExtensions))
        elif(os.path.isfile(myInput)):

            # Ignore folders
            if(os.path.isdir(myInput)):
                continue

            # Throw error if file referenced doesn't exist.
            if(not os.path.isfile(myInput)):
                log.error(f"{myInput} doesn't exist!")

            # Check if the file format is valid.
            fileFormat = myInput[myInput.rfind('.'):]

            if(fileFormat in invalidExtensions):
                log.error(f'Invalid file extension "{fileFormat}" for {myInput}')
            inputList.append(myInput)

        elif(myInput.startswith('http://') or myInput.startswith('https://')):
            basename = re.sub(r'\W+', '-', myInput)

            try:
                import youtube_dl
            except ImportError:
                log.error('Download the youtube-dl pip library to download URLs.')

            from usefulFunctions import ProgressBar

            if(not os.path.isfile(basename + '.mp4')):

                ytbar = ProgressBar(100, 'Downloading')
                def my_hook(d):
                    nonlocal ytbar
                    if(d['status'] == 'downloading'):
                        p = d['_percent_str']
                        p = p.replace('%','')
                        ytbar.tick(float(p))

                ydl_opts = {
                    'nocheckcertificate': True,
                    'outtmpl': basename,
                    'ffmpeg_location': ffmpeg,
                    'format': 'bestvideo[ext=mp4]+bestaudio[ext=m4a]/mp4',
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

            inputList.append(basename + '.mp4')
        else:
            log.error('Could not find file: ' + myInput)

    return inputList
