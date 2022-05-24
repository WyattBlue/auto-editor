from typing import List, Tuple, TypeVar, Union
from auto_editor.utils.log import Log
from auto_editor.utils.types import split_num_str, ChunkType

import numpy as np

"""
To prevent duplicate code being pasted between scripts, common functions should be
put here. Every function should be pure with no side effects.
"""

T = TypeVar("T")

# Turn long silent/loud array to formatted chunk list.
# Example: [1, 1, 1, 2, 2] => [(0, 3, 1), (3, 5, 2)]
def chunkify(arr: np.ndarray) -> ChunkType:
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


def remove_small(has_loud: T, lim: int, replace: int, with_: int) -> T:
    startP = 0
    active = False
    for j, item in enumerate(has_loud):
        if item == replace:
            if not active:
                startP = j
                active = True
            # Special case for end.
            if j == len(has_loud) - 1:
                if j - startP < lim:
                    has_loud[startP : j + 1] = with_
        else:
            if active:
                if j - startP < lim:
                    has_loud[startP:j] = with_
                active = False
    return has_loud


def str_is_number(val: str) -> bool:
    return val.replace(".", "", 1).replace("-", "", 1).isdigit()


def str_starts_with_number(val: str) -> bool:
    if val.startswith("-"):
        val = val[1:]
    val = val.replace(".", "", 1)
    return val[0].isdigit()


def set_range(has_loud: T, range_syntax: list, fps: float, with_: int, log: Log) -> T:
    def replace_variables_to_values(val: str, fps: float, log: Log) -> int:
        if str_is_number(val):
            return int(val)
        if str_starts_with_number(val):
            try:
                value, unit = split_num_str(val)
            except TypeError as e:
                log.error(str(e))

            if unit in ("", "f", "frame", "frames"):
                if isinstance(value, float):
                    log.error("float type cannot be used with frame unit")
                return int(value)
            if unit in ("s", "sec", "secs", "second", "seconds"):
                return round(value * fps)
            log.error(f"Unknown unit: {unit}")

        if val == "start":
            return 0
        if val == "end":
            return len(has_loud)
        return log.error(f"variable '{val}' not available.")

    def var_val_to_frames(val: str, fps: float, log: Log) -> int:
        num = replace_variables_to_values(val, fps, log)
        if num < 0:
            num += len(has_loud)
        return num

    for item in range_syntax:
        pair = []
        for val in item:
            pair.append(var_val_to_frames(val, fps, log))
        has_loud[pair[0] : pair[1]] = with_
    return has_loud


def seconds_to_frames(value: Union[int, str], fps: float) -> int:
    if isinstance(value, str):
        return int(float(value) * fps)
    return value


def cook(has_loud: np.ndarray, min_clip: int, min_cut: int) -> np.ndarray:
    has_loud = remove_small(has_loud, min_clip, replace=1, with_=0)
    has_loud = remove_small(has_loud, min_cut, replace=0, with_=1)
    return has_loud


def apply_margin(
    has_loud: np.ndarray, has_loud_length: int, start_m: int, end_m: int
) -> np.ndarray:

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
    has_loud: np.ndarray, has_loud_length: int, fps: float, args, log: Log
) -> np.ndarray:

    if args.mark_as_loud != []:
        has_loud = set_range(has_loud, args.mark_as_loud, fps, args.video_speed, log)

    if args.mark_as_silent != []:
        has_loud = set_range(has_loud, args.mark_as_silent, fps, args.silent_speed, log)
    return has_loud


def to_speed_list(
    has_loud: np.ndarray, video_speed: float, silent_speed: float
) -> np.ndarray:

    speed_list = has_loud.astype(float)

    # This code will break is speed is allowed to be 0
    speed_list[speed_list == 1] = video_speed
    speed_list[speed_list == 0] = silent_speed

    return speed_list


def merge(start_list: np.ndarray, end_list: np.ndarray) -> np.ndarray:
    merge = np.zeros((len(start_list)), dtype=np.bool_)

    startP = 0
    for item in start_list:
        if item == True:
            where_list = np.where(end_list[startP:])[0]
            if len(where_list) > 0:
                merge[startP : where_list[0]] = True
        startP += 1
    return merge


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
    from subprocess import Popen, PIPE, STDOUT

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


def human_readable_time(time_in_secs: Union[int, float]) -> str:
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
