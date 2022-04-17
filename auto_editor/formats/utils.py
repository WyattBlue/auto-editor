from typing import Tuple
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


def get_width_height(inp: FileInfo) -> Tuple[str, str]:
    v = inp.videos
    if len(v) > 0 and v[0].width is not None and v[0].height is not None:
        return v[0].width, v[0].height
    return "1280", "720"


def indent(base: int, *lines: str) -> str:
    new_lines = ""
    for line in lines:
        new_lines += ("\t" * base) + line + "\n"
    return new_lines
