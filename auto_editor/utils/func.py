from typing import List, Tuple, Union, overload

import numpy as np
from numpy.typing import NDArray

from auto_editor.utils.log import Log
from auto_editor.utils.types import Chunks, time

"""
To prevent duplicate code being pasted between scripts, common functions should be
put here. Every function should be pure with no side effects.
"""

# Turn long silent/loud array to formatted chunk list.
# Example: [1, 1, 1, 2, 2] => [(0, 3, 1), (3, 5, 2)]
def chunkify(arr: Union[np.ndarray, List[int]]) -> Chunks:
    arr_length = len(arr)

    chunks = []
    start = 0
    for j in range(1, arr_length):
        if arr[j] != arr[j - 1]:
            chunks.append((start, j, arr[j - 1]))
            start = j
    chunks.append((start, arr_length, arr[j]))
    return chunks


def to_timecode(secs: float, fmt: str) -> str:
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
    range_syntax: List[List[str]],
    fps: float,
    with_: int,
    log: Log,
) -> NDArray[np.float_]:
    pass


@overload
def set_range(
    arr: NDArray[np.bool_],
    range_syntax: List[List[str]],
    fps: float,
    with_: int,
    log: Log,
) -> NDArray[np.bool_]:
    pass


def set_range(arr, range_syntax, fps, with_, log):
    def replace_variables_to_values(val: str, fps: float, log: Log) -> int:
        if val == "start":
            return 0
        if val == "end":
            return len(arr)

        try:
            value = time(val)
        except TypeError as e:
            log.error(f"{e}")
        if isinstance(value, int):
            return value
        return round(float(value) * fps)

    for _range in range_syntax:
        print(_range)
        pair = []
        for val in _range:
            num = replace_variables_to_values(val, fps, log)
            if num < 0:
                num += len(arr)
            pair.append(num)
        arr[pair[0] : pair[1]] = with_
    return arr


def seconds_to_frames(value: Union[int, str], fps: float) -> int:
    if isinstance(value, str):
        return int(float(value) * fps)
    return value


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


def apply_mark_as(
    has_loud: NDArray[np.bool_], has_loud_length: int, fps: float, args, log: Log
) -> NDArray[np.bool_]:

    if args.mark_as_loud != []:
        has_loud = set_range(has_loud, args.mark_as_loud, fps, args.video_speed, log)

    if args.mark_as_silent != []:
        has_loud = set_range(has_loud, args.mark_as_silent, fps, args.silent_speed, log)
    return has_loud


def to_speed_list(
    has_loud: NDArray[np.bool_], video_speed: float, silent_speed: float
) -> NDArray[np.float_]:

    speed_list = has_loud.astype(float)

    # WARN: This breaks if speed is allowed to be 0
    speed_list[speed_list == 1] = video_speed
    speed_list[speed_list == 0] = silent_speed

    return speed_list


def merge(start_list: np.ndarray, end_list: np.ndarray) -> NDArray[np.bool_]:
    result = np.zeros((len(start_list)), dtype=np.bool_)

    for i, item in enumerate(start_list):
        if item == True:
            where = np.where(end_list[i:])[0]
            if len(where) > 0:
                result[i : where[0]] = True
    return result


def parse_dataclass(unsplit_arguments, dataclass, log):
    from dataclasses import fields

    # Positional Arguments
    #    --rectangle 0,end,10,20,20,30,#000, ...
    # Keyword Arguments
    #    --rectangle start=0,end=end,x1=10, ...

    ARG_SEP = ","
    KEYWORD_SEP = "="

    d_name = dataclass.__name__

    keys = [field.name for field in fields(dataclass)]
    kwargs = {}
    args = []

    allow_positional_args = True

    if unsplit_arguments == "":
        return dataclass()

    for i, arg in enumerate(unsplit_arguments.split(ARG_SEP)):
        if i + 1 > len(keys):
            log.error(f"{d_name} has too many arguments, starting with '{arg}'.")

        if KEYWORD_SEP in arg:
            allow_positional_args = False

            parameters = arg.split(KEYWORD_SEP)
            if len(parameters) > 2:
                log.error(f"{d_name} invalid syntax: '{arg}'.")
            key, val = parameters
            if key not in keys:
                log.error(f"{d_name} got an unexpected keyword '{key}'")

            kwargs[key] = val
        elif allow_positional_args:
            args.append(arg)
        else:
            log.error(f"{d_name} positional argument follows keyword argument.")

    try:
        dataclass_instance = dataclass(*args, **kwargs)
    except TypeError as err:
        err_list = [d_name] + str(err).split(" ")[1:]
        log.error(" ".join(err_list))

    return dataclass_instance


def get_stdout(cmd: List[str]) -> str:
    from subprocess import PIPE, STDOUT, Popen

    stdout, _ = Popen(cmd, stdout=PIPE, stderr=STDOUT).communicate()
    return stdout.decode("utf-8", "replace")


def aspect_ratio(width: int, height: int) -> Union[Tuple[int, int], Tuple[None, None]]:
    if height == 0:
        return None, None

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
