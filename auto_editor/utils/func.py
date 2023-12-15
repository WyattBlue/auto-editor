from __future__ import annotations

from collections.abc import Callable
from fractions import Fraction

import numpy as np
from numpy.typing import NDArray

from auto_editor.utils.log import Log

BoolList = NDArray[np.bool_]
BoolOperand = Callable[[BoolList, BoolList], BoolList]


def boolop(a: BoolList, b: BoolList, call: BoolOperand) -> BoolList:
    if len(a) > len(b):
        k = np.copy(b)
        k.resize(len(a))
        b = k
    if len(b) > len(a):
        k = np.copy(a)
        k.resize(len(b))
        a = k

    return call(a, b)


def setup_tempdir(temp: str | None, log: Log) -> str:
    if temp is None:
        import tempfile

        return tempfile.mkdtemp()

    import os.path
    from os import listdir, mkdir

    if os.path.isfile(temp):
        log.error("Temp directory cannot be an already existing file.")
    if os.path.isdir(temp):
        if len(listdir(temp)) != 0:
            log.error("Temp directory should be empty!")
    else:
        mkdir(temp)

    return temp


def to_timecode(secs: float | Fraction, fmt: str) -> str:
    sign = ""
    if secs < 0:
        sign = "-"
        secs = -secs

    _m, _s = divmod(secs, 60)
    _h, _m = divmod(_m, 60)
    s, m, h = float(_s), int(_m), int(_h)

    if fmt == "webvtt":
        if h == 0:
            return f"{sign}{m:02d}:{s:06.3f}"
        return f"{sign}{h:02d}:{m:02d}:{s:06.3f}"
    if fmt == "mov_text":
        return f"{sign}{h:02d}:{m:02d}:" + f"{s:06.3f}".replace(".", ",", 1)
    if fmt == "standard":
        return f"{sign}{h:02d}:{m:02d}:{s:06.3f}"
    if fmt == "ass":
        return f"{sign}{h:d}:{m:02d}:{s:05.2f}"
    if fmt == "rass":
        return f"{sign}{h:d}:{m:02d}:{s:02.0f}"

    raise ValueError("to_timecode: Unreachable")


def mut_margin(arr: BoolList, start_m: int, end_m: int) -> None:
    # Find start and end indexes
    start_index = []
    end_index = []
    arrlen = len(arr)
    for j in range(1, arrlen):
        if arr[j] != arr[j - 1]:
            if arr[j]:
                start_index.append(j)
            else:
                end_index.append(j)

    # Apply margin
    if start_m > 0:
        for i in start_index:
            arr[max(i - start_m, 0) : i] = True
    if start_m < 0:
        for i in start_index:
            arr[i : min(i - start_m, arrlen)] = False

    if end_m > 0:
        for i in end_index:
            arr[i : min(i + end_m, arrlen)] = True
    if end_m < 0:
        for i in end_index:
            arr[max(i + end_m, 0) : i] = False


def merge(start_list: np.ndarray, end_list: np.ndarray) -> BoolList:
    result = np.zeros((len(start_list)), dtype=np.bool_)

    for i, item in enumerate(start_list):
        if item == True:
            where = np.where(end_list[i:])[0]
            if len(where) > 0:
                result[i : where[0]] = True
    return result


def get_stdout(cmd: list[str]) -> str:
    from subprocess import DEVNULL, PIPE, Popen

    stdout, _ = Popen(cmd, stdin=DEVNULL, stdout=PIPE, stderr=PIPE).communicate()
    return stdout.decode("utf-8", "replace")


def get_stdout_bytes(cmd: list[str]) -> bytes:
    from subprocess import DEVNULL, PIPE, Popen

    return Popen(cmd, stdin=DEVNULL, stdout=PIPE, stderr=PIPE).communicate()[0]


def aspect_ratio(width: int, height: int) -> tuple[int, int]:
    if height == 0:
        return (0, 0)

    def gcd(a: int, b: int) -> int:
        while b:
            a, b = b, a % b
        return a

    c = gcd(width, height)
    return width // c, height // c


def human_readable_time(time_in_secs: float) -> str:
    units = "seconds"
    if time_in_secs >= 3600:
        time_in_secs = round(time_in_secs / 3600, 1)
        if time_in_secs % 1 == 0:
            time_in_secs = round(time_in_secs)
        units = "hours"
    if time_in_secs >= 60:
        time_in_secs = round(time_in_secs / 60, 1)
        if time_in_secs >= 10 or time_in_secs % 1 == 0:
            time_in_secs = round(time_in_secs)
        units = "minutes"
    return f"{time_in_secs} {units}"


def open_with_system_default(path: str, log: Log) -> None:
    import sys
    from subprocess import run

    if sys.platform == "win32":
        from os import startfile

        try:
            startfile(path)
        except OSError:
            log.warning("Could not find application to open file.")
    else:
        try:  # MacOS case
            run(["open", path])
        except Exception:
            try:  # WSL2 case
                run(["cmd.exe", "/C", "start", path])
            except Exception:
                try:  # Linux case
                    run(["xdg-open", path])
                except Exception:
                    log.warning("Could not open output file.")


def append_filename(path: str, val: str) -> str:
    from os.path import splitext

    root, ext = splitext(path)
    return root + val + ext
