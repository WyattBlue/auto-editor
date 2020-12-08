import os
import re
import youtube_dl

from usefulFunctions import ProgressBar

invalidExtensions = ['.txt', '.md', '.rtf', '.csv', '.cvs', '.html', '.htm',
    '.xml', '.json', '.yaml', '.png', '.jpeg', '.jpg', '.gif', '.exe', '.doc',
    '.docx', '.odt', '.pptx', '.xlsx', '.xls', 'ods', '.pdf', '.bat', '.dll',
    '.prproj', '.psd', '.aep', '.zip', '.rar', '.7z', '.java', '.class', '.js',
    '.c', '.cpp', '.csharp', '.py', '.app', '.git', '.github', '.gitignore',
    '.db', '.ini', '.BIN']


def validFiles(path: str, badExts: list):
    for f in os.listdir(path):
        if(f[f.rfind('.'):] not in badExts and not os.path.isdir(f)):
            yield os.path.join(path, f)



def validInput(inputs:list, ffmpeg, log) -> list:

    class MyLogger(object):
        def debug(self, msg):
            pass

        def warning(self, msg):
            log.warning(msg)

        def error(self, msg):
            log.error(msg)

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
            fileFormat = INPUT_FILE[INPUT_FILE.rfind('.'):]

            if(fileFormat in invalidExtensions):
                log.error(f'Invalid file extension "{fileFormat}" for {myInput}')
            inputList.append(myInput)

        elif(myInput.startswith('http://') or myInput.startswith('https://')):
            basename = re.sub(r'\W+', '-', myInput)

            if(not os.path.isfile(basename + '.mp4')):

                ytbar = ProgressBar(100, 'Downloading')
                def my_hook(d):
                    nonlocal ytbar

                    if d['status'] == 'downloading':
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
                    ydl.download([myInput])
                log.conwrite('')

            inputList.append(basename + '.mp4')
        else:
            log.error('Could not find file: ' + myInput)

    return inputList
