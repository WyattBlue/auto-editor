__version__ = "1.1.1"

import os.path
from platform import system, machine

def get_path() -> str:
    _os = system()
    _arch = machine().lower()
    _interdir = _os if _os != "Darwin" else f"{_os}-{_arch}"
    program = "ffmpeg.exe" if _os == "Windows" else "ffmpeg"

    dirpath = os.path.dirname(os.path.realpath(__file__))
    file_path = os.path.join(dirpath, _interdir, program)

    return file_path if os.path.isfile(file_path) else "ffmpeg"
