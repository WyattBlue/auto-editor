from __future__ import annotations

from typing import TYPE_CHECKING

import numpy as np

if TYPE_CHECKING:
    from collections.abc import Callable
    from fractions import Fraction

    from numpy.typing import NDArray

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
    if fmt in {"srt", "mov_text"}:
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


def get_stdout(cmd: list[str]) -> str:
    from subprocess import DEVNULL, PIPE, Popen

    stdout = Popen(cmd, stdin=DEVNULL, stdout=PIPE, stderr=PIPE).communicate()[0]
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
