from typing import List, Tuple, Union
from auto_editor.utils.log import Log

"""
To prevent duplicate code being pasted between scripts, common functions should be
put here. No function should modify or create video/audio files on its own.
"""


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


def clean_list(x: List[str], rm_chars: str) -> List[str]:
    new_list = []
    for item in x:
        for char in rm_chars:
            item = item.replace(char, "")
        new_list.append(item)
    return new_list


def aspect_ratio(width: int, height: int) -> Union[Tuple[int, int], Tuple[None, None]]:
    if height == 0:
        return None, None

    def gcd(a: int, b: int) -> int:
        while b:
            a, b = b, a % b
        return a

    c = gcd(width, height)
    return width // c, height // c


def get_new_length(chunks: List[Tuple[int, int, float]], fps: float) -> float:
    time_in_frames = 0.0
    for chunk in chunks:
        leng = chunk[1] - chunk[0]
        if chunk[2] != 99999:
            time_in_frames += leng * (1 / chunk[2])
    return time_in_frames / fps


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


def fnone(val: object) -> bool:
    return val == "none" or val == "unset" or val is None


def append_filename(path: str, val: str) -> str:
    from os.path import splitext

    root, ext = splitext(path)
    return root + val + ext
