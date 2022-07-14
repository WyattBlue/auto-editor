__version__ = "1.0.0"

import os.path
from platform import system

def get_path():
    program = "ffmpeg.exe" if system() == "Windows" else "ffmpeg"
    dirpath = os.path.dirname(os.path.realpath(__file__))
    file_path = os.path.join(dirpath, system(), program)
    return file_path if os.path.isfile(file_path) else "ffmpeg"
