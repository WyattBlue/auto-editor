from __future__ import annotations

import re
from dataclasses import dataclass
from typing import TYPE_CHECKING

import numpy as np

from auto_editor.analyze import (
    audio_levels,
    get_all,
    get_none,
    random_levels,
    to_threshold,
)
from auto_editor.objects import Attr, parse_dataclass
from auto_editor.utils.types import Stream, natural, stream, threshold

if TYPE_CHECKING:
    from fractions import Fraction
    from typing import Callable

    from numpy.typing import NDArray

    from auto_editor.ffwrapper import FileInfo
    from auto_editor.output import Ensure
    from auto_editor.utils.bar import Bar
    from auto_editor.utils.log import Log

    BoolList = NDArray[np.bool_]
    BoolOperand = Callable[[BoolList, BoolList], BoolList]


@dataclass
class Audio:
    threshold: float
    stream: Stream


@dataclass
class Motion:
    threshold: float
    stream: int
    blur: int
    width: int


@dataclass
class Pixeldiff:
    threshold: int
    stream: int


@dataclass
class Random:
    threshold: float
    seed: int


audio_builder = [
    Attr(("threshold",), threshold, 0.04),
    Attr(("stream", "track"), stream, 0),
]
motion_builder = [
    Attr(("threshold",), threshold, 0.02),
    Attr(("stream", "track"), natural, 0),
    Attr(("blur",), natural, 9),
    Attr(("width",), natural, 400),
]
pixeldiff_builder = [
    Attr(("threshold",), natural, 1),
    Attr(("stream", "track"), natural, 0),
]
random_builder = [Attr(("threshold",), threshold, 0.5), Attr(("seed",), int, -1)]


def operand_combine(a: BoolList, b: BoolList, call: BoolOperand) -> BoolList:
    if len(a) > len(b):
        b = np.resize(b, len(a))
    if len(b) > len(a):
        a = np.resize(a, len(b))

    return call(a, b)


def get_has_loud(
    token_str: str,
    inp: FileInfo,
    ensure: Ensure,
    strict: bool,
    tb: Fraction,
    bar: Bar,
    temp: str,
    log: Log,
) -> NDArray[np.bool_]:

    METHOD_ATTRS_SEP = ":"
    METHODS = ("audio", "motion", "pixeldiff", "random", "none", "all")

    result_array: NDArray[np.bool_] | None = None
    operand: str | None = None

    logic_funcs: dict[str, BoolOperand] = {
        "and": np.logical_and,
        "or": np.logical_or,
        "xor": np.logical_xor,
    }

    # See: https://stackoverflow.com/questions/1059559/
    for token in filter(None, re.split(r"[ _]+", token_str)):
        if METHOD_ATTRS_SEP in token:
            token, attrs = token.split(METHOD_ATTRS_SEP)
            if token not in METHODS:
                log.error(f"'{token}': Token not allowed to have attributes.")
        else:
            attrs = ""

        if token in METHODS:
            if result_array is not None and operand is None:
                log.error("Logic operator must be between two editing methods.")

            if token == "none":
                stream_data = get_none(ensure, inp, tb, temp, log)
            if token == "all":
                stream_data = get_all(ensure, inp, tb, temp, log)
            if token == "random":
                robj = parse_dataclass(attrs, Random, random_builder, log)
                stream_data = to_threshold(
                    random_levels(ensure, inp, robj, tb, temp, log),
                    robj.threshold,
                )
            if token == "audio":
                aobj = parse_dataclass(attrs, Audio, audio_builder, log)
                s = aobj.stream
                if s == "all":
                    total_list: NDArray[np.bool_] | None = None
                    for s in range(len(inp.audios)):
                        audio_list = to_threshold(
                            audio_levels(ensure, inp, s, tb, bar, strict, temp, log),
                            aobj.threshold,
                        )
                        if total_list is None:
                            total_list = audio_list
                        else:
                            total_list = operand_combine(
                                total_list, audio_list, np.logical_or
                            )
                    if total_list is None:
                        if strict:
                            log.error("Input has no audio streams.")
                        stream_data = get_all(ensure, inp, tb, temp, log)
                    else:
                        stream_data = total_list
                else:
                    stream_data = to_threshold(
                        audio_levels(ensure, inp, s, tb, bar, strict, temp, log),
                        aobj.threshold,
                    )

            if token == "motion":
                from auto_editor.analyze import motion_levels

                if inp.videos:
                    _vars = {"width": inp.videos[0].width}
                else:
                    _vars = {"width": 1}

                mobj = parse_dataclass(attrs, Motion, motion_builder, log, _vars)
                stream_data = to_threshold(
                    motion_levels(ensure, inp, mobj, tb, bar, strict, temp, log),
                    mobj.threshold,
                )

            if token == "pixeldiff":
                from auto_editor.analyze import pixeldiff_levels

                pobj = parse_dataclass(attrs, Pixeldiff, pixeldiff_builder, log)
                stream_data = to_threshold(
                    pixeldiff_levels(ensure, inp, pobj, tb, bar, strict, temp, log),
                    pobj.threshold,
                )

            if operand == "not":
                result_array = np.logical_not(stream_data)
                operand = None
            elif result_array is None:
                result_array = stream_data
            elif operand is not None and operand in ("and", "or", "xor"):
                result_array = operand_combine(
                    result_array, stream_data, logic_funcs[operand]
                )
                operand = None

        elif token in ("and", "or", "xor"):
            if operand is not None:
                log.error("Invalid Editing Syntax.")
            if result_array is None:
                log.error(f"'{token}' operand needs two arguments.")
            operand = token
        elif token == "not":
            if operand is not None:
                log.error("Invalid Editing Syntax.")
            operand = token
        else:
            log.error(f"Unknown method/operator: '{token}'")

    if operand is not None:
        log.error(f"Dangling operand: '{operand}'")

    assert result_array is not None
    return result_array
