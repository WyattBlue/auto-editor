from __future__ import annotations

from fractions import Fraction
from typing import overload

import numpy as np
from numpy.typing import NDArray

from auto_editor.utils.log import Log
from auto_editor.utils.types import time

"""
To prevent duplicate code being pasted between scripts, common functions should be
put here. Every function should be pure with no side effects.
"""


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


def remove_small(
    has_loud: NDArray[np.bool_], lim: int, replace: int, with_: int
) -> NDArray[np.bool_]:
    start_p = 0
    active = False
    for j, item in enumerate(has_loud):
        if item == replace:
            if not active:
                start_p = j
                active = True
            # Special case for end.
            if j == len(has_loud) - 1:
                if j - start_p < lim:
                    has_loud[start_p : j + 1] = with_
        else:
            if active:
                if j - start_p < lim:
                    has_loud[start_p:j] = with_
                active = False
    return has_loud


@overload
def set_range(
    arr: NDArray[np.float_],
    range_syntax: list[list[str]],
    tb: Fraction,
    with_: float,
    log: Log,
) -> NDArray[np.float_]:
    pass


@overload
def set_range(
    arr: NDArray[np.bool_],
    range_syntax: list[list[str]],
    tb: Fraction,
    with_: float,
    log: Log,
) -> NDArray[np.bool_]:
    pass


def set_range(arr, range_syntax, tb, with_, log):
    def replace_variables_to_values(val: str, tb: Fraction, log: Log) -> int:
        if val == "start":
            return 0
        if val == "end":
            return len(arr)

        try:
            value = time(val)
        except TypeError as e:
            log.error(e)
        if isinstance(value, int):
            return value
        return round(float(value) * tb)

    for _range in range_syntax:
        pair = []
        for val in _range:
            num = replace_variables_to_values(val, tb, log)
            if num < 0:
                num += len(arr)
            pair.append(num)
        arr[pair[0] : pair[1]] = with_
    return arr


def cook(has_loud: NDArray[np.bool_], min_clip: int, min_cut: int) -> NDArray[np.bool_]:
    has_loud = remove_small(has_loud, min_clip, replace=1, with_=0)
    has_loud = remove_small(has_loud, min_cut, replace=0, with_=1)
    return has_loud


def apply_margin(
    has_loud: NDArray[np.bool_], has_loud_length: int, start_m: int, end_m: int
) -> NDArray[np.bool_]:

    # Find start and end indexes.
    start_index = []
    end_index = []
    for j in range(1, has_loud_length):
        if has_loud[j] != has_loud[j - 1]:
            if has_loud[j]:
                start_index.append(j)
            else:
                end_index.append(j)

    # Apply margin
    if start_m > 0:
        for i in start_index:
            has_loud[max(i - start_m, 0) : i] = True
    if start_m < 0:
        for i in start_index:
            has_loud[i : min(i - start_m, has_loud_length)] = False

    if end_m > 0:
        for i in end_index:
            has_loud[i : min(i + end_m, has_loud_length)] = True
    if end_m < 0:
        for i in end_index:
            has_loud[max(i + end_m, 0) : i] = False

    return has_loud


def merge(start_list: np.ndarray, end_list: np.ndarray) -> NDArray[np.bool_]:
    result = np.zeros((len(start_list)), dtype=np.bool_)

    for i, item in enumerate(start_list):
        if item == True:
            where = np.where(end_list[i:])[0]
            if len(where) > 0:
                result[i : where[0]] = True
    return result


def get_stdout(cmd: list[str]) -> str:
    from subprocess import PIPE, Popen

    stdout, _ = Popen(cmd, stdout=PIPE, stderr=PIPE).communicate()
    return stdout.decode("utf-8", "replace")


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

    if sys.platform == "win64" or sys.platform == "win32":
        from os import startfile

        try:
            startfile(path)
        except OSError:
            log.warning("Could not find application to open file.")
    else:
        try:  # should work on MacOS and some Linux distros
            run(["open", path])
        except Exception:
            try:  # should work on WSL2
                run(["cmd.exe", "/C", "start", path])
            except Exception:
                try:  # should work on most other Linux distros
                    run(["xdg-open", path])
                except Exception:
                    log.warning("Could not open output file.")


def append_filename(path: str, val: str) -> str:
    from os.path import splitext

    root, ext = splitext(path)
    return root + val + ext
