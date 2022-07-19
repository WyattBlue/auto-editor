from __future__ import annotations

import os
import random
import re
from dataclasses import dataclass
from typing import Any, Callable, NamedTuple, TypeVar

import numpy as np
from numpy.typing import NDArray

from auto_editor.analyze.audio import audio_detection
from auto_editor.analyze.motion import motion_detection
from auto_editor.analyze.pixeldiff import pixel_difference
from auto_editor.ffwrapper import FileInfo
from auto_editor.utils.func import (
    apply_margin,
    apply_mark_as,
    cook,
    seconds_to_frames,
    set_range,
    to_speed_list,
)
from auto_editor.utils.log import Log
from auto_editor.utils.progressbar import ProgressBar
from auto_editor.utils.types import Args, Stream, number, stream
from auto_editor.wavfile import read

T = TypeVar("T", bound=type)
BoolList = NDArray[np.bool_]
BoolOperand = Callable[[BoolList, BoolList], BoolList]


@dataclass
class Audio:
    stream: Stream
    threshold: float


@dataclass
class Motion:
    threshold: float
    blur: int
    width: int


@dataclass
class Pixeldiff:
    threshold: int


@dataclass
class Random:
    cutchance: float = 0.5
    seed: int = -1


class Attr(NamedTuple):
    names: tuple[str]
    coerce: Any
    default: Any


audio_builder = [Attr(("stream", "track"), stream, 0), Attr(("threshold",), number, -1)]
motion_builder = [
    Attr(("threshold",), number, 0.02),
    Attr(("blur",), int, 9),
    Attr(("width",), int, 400),
]
pixeldiff_builder = [Attr(("threshold",), int, 1)]
random_builder = [Attr(("cutchance",), number, 0.5), Attr(("seed",), int, -1)]


def get_attributes(attrs_str: str, dataclass: T, builder: list[Attr], log: Log) -> T:
    kwargs: dict[str, Any] = {}
    for attr in builder:
        kwargs[attr.names[0]] = attr.default

    if attrs_str == "":
        return dataclass(**kwargs)

    ARG_SEP = ","
    KEYWORD_SEP = "="
    d_name = dataclass.__name__
    allow_positional_args = True

    for i, arg in enumerate(attrs_str.split(ARG_SEP)):
        if i + 1 > len(builder):
            log.error(f"{d_name} has too many arguments, starting with '{arg}'.")

        if KEYWORD_SEP in arg:
            allow_positional_args = False

            parameters = arg.split(KEYWORD_SEP)
            if len(parameters) > 2:
                log.error(f"{d_name} invalid syntax: '{arg}'.")

            key, val = parameters
            found = False
            for attr in builder:
                if key in attr.names:
                    try:
                        kwargs[attr.names[0]] = attr.coerce(val)
                    except (TypeError, ValueError) as e:
                        log.error(e)
                    found = True
                    break

            if not found:
                from difflib import get_close_matches

                keys = set()
                for attr in builder:
                    for name in attr.names:
                        keys.add(name)

                more = ""
                if matches := get_close_matches(key, keys):
                    more = f"\n    Did you mean:\n        {', '.join(matches)}"

                log.error(f"{d_name} got an unexpected keyword '{key}'\n{more}")

        elif allow_positional_args:
            try:
                kwargs[builder[i].names[0]] = builder[i].coerce(arg)
            except (TypeError, ValueError) as e:
                log.error(e)
        else:
            log.error(f"{d_name} positional argument follows keyword argument.")

    return dataclass(**kwargs)


def get_media_duration(path: str, i: int, fps: float, temp: str, log: Log) -> int:
    audio_path = os.path.join(temp, f"{i}-0.wav")
    if os.path.isfile(audio_path):
        sample_rate, audio_samples = read(audio_path)
        sample_rate_per_frame = sample_rate / fps

        dur = round(audio_samples.shape[0] / sample_rate_per_frame)
        log.debug(f"Dur (audio): {dur}")
        return dur

    import av

    cn = av.open(path, "r")

    if len(cn.streams.video) < 1:
        log.error("Could not get media duration")

    video = cn.streams.video[0]
    dur = int(float(video.duration * video.time_base) * fps)
    log.debug(f"Dur (video): {dur}")
    return dur


def get_audio_list(
    i: int,
    stream: int,
    threshold: float,
    fps: float,
    progress: ProgressBar,
    temp: str,
    log: Log,
) -> BoolList:
    if os.path.isfile(path := os.path.join(temp, f"{i}-{stream}.wav")):
        sample_rate, audio_samples = read(path)
    else:
        raise TypeError(f"Audio stream '{stream}' does not exist.")

    audio_list = audio_detection(audio_samples, sample_rate, fps, progress, log)
    return np.fromiter((x > threshold for x in audio_list), dtype=np.bool_)


def operand_combine(a: BoolList, b: BoolList, call: BoolOperand) -> BoolList:
    if len(a) > len(b):
        b = np.resize(b, len(a))
    if len(b) > len(a):
        a = np.resize(a, len(b))

    return call(a, b)


def get_all_list(path: str, i: int, fps: float, temp: str, log: Log) -> BoolList:
    return np.zeros(get_media_duration(path, i, fps, temp, log) - 1, dtype=np.bool_)


def get_stream_data(
    method: str,
    attrs_str: str,
    args: Args,
    i: int,
    inputs: list[FileInfo],
    fps: float,
    progress: ProgressBar,
    temp: str,
    log: Log,
) -> BoolList:

    inp = inputs[0]
    strict = len(inputs) < 2

    if method == "none":
        return np.ones(
            get_media_duration(inp.path, i, fps, temp, log) - 1, dtype=np.bool_
        )
    if method == "all":
        return get_all_list(inp.path, i, fps, temp, log)
    if method == "random":
        robj = get_attributes(attrs_str, Random, random_builder, log)
        if robj.seed == -1:
            robj.seed = random.randint(0, 2147483647)
        if robj.cutchance > 1 or robj.cutchance < 0:
            log.error(f"random:cutchance must be between 0 and 1")

        l = get_media_duration(inp.path, i, fps, temp, log) - 1
        random.seed(robj.seed)
        log.debug(f"Seed: {robj.seed}")

        a = random.choices((0, 1), weights=(robj.cutchance, 1 - robj.cutchance), k=l)

        return np.asarray(a, dtype=np.bool_)
    if method == "audio":
        audio = get_attributes(attrs_str, Audio, audio_builder, log)
        if audio.threshold == -1:
            audio.threshold = args.silent_threshold
        if audio.stream == "all":
            total_list: NDArray[np.bool_] | None = None
            for s in range(len(inp.audios)):
                try:
                    audio_list = get_audio_list(
                        i, s, audio.threshold, fps, progress, temp, log
                    )
                    if total_list is None:
                        total_list = audio_list
                    else:
                        total_list = operand_combine(
                            total_list, audio_list, np.logical_or
                        )
                except TypeError as e:
                    if not strict:
                        return get_all_list(inp.path, i, fps, temp, log)
                    log.error(e)

            if total_list is None:
                if not strict:
                    return get_all_list(inp.path, i, fps, temp, log)
                log.error("Input has no audio streams.")
            return total_list
        else:
            try:
                return get_audio_list(
                    i, audio.stream, audio.threshold, fps, progress, temp, log
                )
            except TypeError as e:
                if not strict:
                    return get_all_list(inp.path, i, fps, temp, log)
                log.error(e)
    if method == "motion":
        if len(inp.videos) == 0:
            if not strict:
                return get_all_list(inp.path, i, fps, temp, log)
            log.error("Video stream '0' does not exist.")

        mobj = get_attributes(attrs_str, Motion, motion_builder, log)
        motion_list = motion_detection(inp.path, fps, progress, mobj.width, mobj.blur)
        return np.fromiter((x >= mobj.threshold for x in motion_list), dtype=np.bool_)

    if method == "pixeldiff":
        if len(inp.videos) == 0:
            if not strict:
                return get_all_list(inp.path, i, fps, temp, log)
            log.error("Video stream '0' does not exist.")

        pobj = get_attributes(attrs_str, Pixeldiff, pixeldiff_builder, log)
        pixel_list = pixel_difference(inp.path, fps, progress)
        return np.fromiter((x >= pobj.threshold for x in pixel_list), dtype=np.bool_)

    raise ValueError(f"Unreachable. {method=}")


def get_has_loud(
    token_str: str,
    i: int,
    inputs: list[FileInfo],
    fps: float,
    progress: ProgressBar,
    temp: str,
    log: Log,
    args: Args,
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
                token, attrs_str, args, i, inputs, fps, progress, temp, log
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


def get_speed_list(
    i: int,
    inputs: list[FileInfo],
    fps: float,
    args: Args,
    progress: ProgressBar,
    temp: str,
    log: Log,
) -> NDArray[np.float_]:

    start_margin, end_margin = args.frame_margin

    start_margin = seconds_to_frames(start_margin, fps)
    end_margin = seconds_to_frames(end_margin, fps)
    min_clip = seconds_to_frames(args.min_clip_length, fps)
    min_cut = seconds_to_frames(args.min_cut_length, fps)

    has_loud = get_has_loud(
        args.edit_based_on, i, inputs, fps, progress, temp, log, args
    )
    has_loud_length = len(has_loud)

    has_loud = apply_mark_as(has_loud, has_loud_length, fps, args, log)
    has_loud = cook(has_loud, min_clip, min_cut)
    has_loud = apply_margin(has_loud, has_loud_length, start_margin, end_margin)

    # Remove small clips/cuts created by applying other rules.
    has_loud = cook(has_loud, min_clip, min_cut)

    speed_list = to_speed_list(has_loud, args.video_speed, args.silent_speed)

    if len(args.cut_out) > 0:
        speed_list = set_range(speed_list, args.cut_out, fps, 99999, log)

    if len(args.add_in) > 0:
        speed_list = set_range(speed_list, args.add_in, fps, args.video_speed, log)

    for item in args.set_speed_for_range:
        speed_list = set_range(speed_list, [list(item[1:])], fps, item[0], log)

    return speed_list
