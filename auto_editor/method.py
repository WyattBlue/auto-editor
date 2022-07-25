from __future__ import annotations

import os
import random
import re
from dataclasses import dataclass
from fractions import Fraction
from typing import Callable

import numpy as np
from numpy.typing import NDArray

from auto_editor.analyze.audio import audio_detection, audio_length
from auto_editor.analyze.motion import motion_detection
from auto_editor.analyze.pixeldiff import pixel_difference
from auto_editor.ffwrapper import FileInfo
from auto_editor.objects import Attr, parse_dataclass
from auto_editor.utils.bar import Bar
from auto_editor.utils.log import Log
from auto_editor.utils.types import Stream, natural, stream, threshold
from auto_editor.wavfile import read

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
    cutchance: float = 0.5
    seed: int = -1


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
random_builder = [Attr(("cutchance",), threshold, 0.5), Attr(("seed",), int, -1)]


def get_media_length(path: str, i: int, tb: Fraction, temp: str, log: Log) -> int:
    # Read first audio track.

    audio_path = os.path.join(temp, f"{i}-0.wav")
    if os.path.isfile(audio_path):
        sr, samples = read(audio_path)
        return audio_length(len(samples), sr, tb, log)

    # If there's no audio, get length in video metadata.
    import av

    av.logging.set_level(av.logging.PANIC)
    cn = av.open(path, "r")
    if len(cn.streams.video) < 1:
        log.error("Could not get media duration")

    video = cn.streams.video[0]
    dur = int(video.duration * video.time_base * tb)
    log.debug(f"Video duration: {dur}")
    return dur


def get_audio_list(
    i: int,
    stream: int,
    threshold: float,
    tb: Fraction,
    bar: Bar,
    temp: str,
    log: Log,
) -> BoolList:
    if os.path.isfile(path := os.path.join(temp, f"{i}-{stream}.wav")):
        sr, samples = read(path)
    else:
        raise TypeError(f"Audio stream '{stream}' does not exist.")

    audio_list = audio_detection(samples, sr, tb, bar, log)
    return np.fromiter((x > threshold for x in audio_list), dtype=np.bool_)


def operand_combine(a: BoolList, b: BoolList, call: BoolOperand) -> BoolList:
    if len(a) > len(b):
        b = np.resize(b, len(a))
    if len(b) > len(a):
        a = np.resize(a, len(b))

    return call(a, b)


def get_all_list(path: str, i: int, tb: Fraction, temp: str, log: Log) -> BoolList:
    return np.zeros(get_media_length(path, i, tb, temp, log) - 1, dtype=np.bool_)


def get_stream_data(
    method: str,
    attrs_str: str,
    i: int,
    inputs: list[FileInfo],
    timebase: Fraction,
    bar: Bar,
    temp: str,
    log: Log,
) -> BoolList:

    inp = inputs[0]
    strict = len(inputs) < 2

    if method == "none":
        return np.ones(
            get_media_length(inp.path, i, timebase, temp, log) - 1, dtype=np.bool_
        )
    if method == "all":
        return get_all_list(inp.path, i, timebase, temp, log)
    if method == "random":
        robj = parse_dataclass(attrs_str, Random, random_builder, log)
        if robj.seed == -1:
            robj.seed = random.randint(0, 2147483647)

        l = get_media_length(inp.path, i, timebase, temp, log) - 1
        random.seed(robj.seed)
        log.debug(f"Seed: {robj.seed}")

        a = random.choices((0, 1), weights=(robj.cutchance, 1 - robj.cutchance), k=l)

        return np.asarray(a, dtype=np.bool_)
    if method == "audio":
        audio = parse_dataclass(attrs_str, Audio, audio_builder, log)
        if audio.stream == "all":
            total_list: NDArray[np.bool_] | None = None
            for s in range(len(inp.audios)):
                try:
                    audio_list = get_audio_list(
                        i, s, audio.threshold, timebase, bar, temp, log
                    )
                    if total_list is None:
                        total_list = audio_list
                    else:
                        total_list = operand_combine(
                            total_list, audio_list, np.logical_or
                        )
                except TypeError as e:
                    if not strict:
                        return get_all_list(inp.path, i, timebase, temp, log)
                    log.error(e)

            if total_list is None:
                if not strict:
                    return get_all_list(inp.path, i, timebase, temp, log)
                log.error("Input has no audio streams.")
            return total_list
        else:
            try:
                return get_audio_list(
                    i, audio.stream, audio.threshold, timebase, bar, temp, log
                )
            except TypeError as e:
                if not strict:
                    return get_all_list(inp.path, i, timebase, temp, log)
                log.error(e)
    if method == "motion":
        mobj = parse_dataclass(attrs_str, Motion, motion_builder, log)

        if mobj.stream >= len(inp.videos):
            if not strict:
                return get_all_list(inp.path, i, timebase, temp, log)
            log.error(f"Video stream '{mobj.stream}' does not exist.")

        motion_list = motion_detection(
            inp.path, mobj.stream, timebase, bar, mobj.width, mobj.blur
        )
        return np.fromiter((x >= mobj.threshold for x in motion_list), dtype=np.bool_)

    if method == "pixeldiff":
        pobj = parse_dataclass(attrs_str, Pixeldiff, pixeldiff_builder, log)

        if pobj.stream >= len(inp.videos):
            if not strict:
                return get_all_list(inp.path, i, timebase, temp, log)
            log.error(f"Video stream '{pobj.stream}' does not exist.")

        pixel_list = pixel_difference(inp.path, pobj.stream, timebase, bar)
        return np.fromiter((x >= pobj.threshold for x in pixel_list), dtype=np.bool_)

    raise ValueError(f"Unreachable. {method=}")


def get_has_loud(
    token_str: str,
    i: int,
    inputs: list[FileInfo],
    timebase: Fraction,
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
            token, attrs_str = token.split(METHOD_ATTRS_SEP)
            if token not in METHODS:
                log.error(f"'{token}': Token not allowed to have attributes.")
        else:
            attrs_str = ""

        if token in METHODS:
            if result_array is not None and operand is None:
                log.error("Logic operator must be between two editing methods.")

            stream_data = get_stream_data(
                token, attrs_str, i, inputs, timebase, bar, temp, log
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
