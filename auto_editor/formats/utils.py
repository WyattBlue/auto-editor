from typing import Tuple, Optional
from auto_editor.ffwrapper import FileInfo


def safe_mkdir(path: str) -> str:
    from shutil import rmtree
    from os import mkdir

    try:
        mkdir(path)
    except OSError:
        rmtree(path)
        mkdir(path)
    return path


def get_width_height(inp: FileInfo) -> Tuple[Optional[str], Optional[str]]:
    if len(inp.video_streams) == 0:
        return None, None
    else:
        return inp.video_streams[0]["width"], inp.video_streams[0]["height"]


def indent(base: int, *lines: str) -> str:
    new_lines = ""
    for line in lines:
        new_lines += ("\t" * base) + line + "\n"
    return new_lines
