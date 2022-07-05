import os
import random
import re
from dataclasses import asdict, dataclass, fields
from typing import Any, Callable, Dict, List, Optional, TypeVar, Union

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
    parse_dataclass,
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
    stream: Stream = 0
    threshold: float = -1


@dataclass
class Motion:
    threshold: float = 0.02
    blur: int = 9
    width: int = 400


@dataclass
class Pixeldiff:
    threshold: int = 1


@dataclass
class Random:
    cutchance: float = 0.5
    seed: int = -1


def get_attributes(attrs_str: str, dataclass: T, log: Log) -> T:
    attrs = parse_dataclass(attrs_str, dataclass, log)

    dic_value = asdict(attrs)
    dic_type: Dict[str, Union[type, Callable[[Any], Any]]] = {}
    for field in fields(attrs):
        dic_type[field.name] = field.type

    # Convert to the correct types
    for k, _type in dic_type.items():

        if _type == float:
            _type = number
        elif _type == Stream:
            _type = stream

        try:
            attrs.__setattr__(k, _type(dic_value[k]))
        except (ValueError, TypeError) as e:
            log.error(e)

    return attrs


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
    inputs: List[FileInfo],
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
        robj = get_attributes(attrs_str, Random, log)
        if robj.cutchance > 1 or robj.cutchance < 0:
            log.error(f"random:cutchance must be between 0 and 1")
        if robj.seed == -1:
            robj.seed = random.randint(0, 2147483647)
        l = get_media_duration(inp.path, i, fps, temp, log) - 1

        random.seed(robj.seed)
        log.debug(f"Seed: {robj.seed}")

        a = random.choices((0, 1), weights=(robj.cutchance, 1 - robj.cutchance), k=l)

        return np.asarray(a, dtype=np.bool_)
    if method == "audio":
        audio = get_attributes(attrs_str, Audio, log)
        if audio.threshold == -1:
            audio.threshold = args.silent_threshold
        if audio.stream == "all":
            total_list: Optional[NDArray[np.bool_]] = None
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

        mobj = get_attributes(attrs_str, Motion, log)
        motion_list = motion_detection(inp.path, fps, progress, mobj.width, mobj.blur)
        return np.fromiter((x >= mobj.threshold for x in motion_list), dtype=np.bool_)

    if method == "pixeldiff":
        if len(inp.videos) == 0:
            if not strict:
                return get_all_list(inp.path, i, fps, temp, log)
            log.error("Video stream '0' does not exist.")

        pobj = get_attributes(attrs_str, Pixeldiff, log)
        pixel_list = pixel_difference(inp.path, fps, progress)
        return np.fromiter((x >= pobj.threshold for x in pixel_list), dtype=np.bool_)

    raise ValueError(f"Unreachable. {method=}")


def get_has_loud(
    token_str: str,
    i: int,
    inputs: List[FileInfo],
    fps: float,
    progress: ProgressBar,
    temp: str,
    log: Log,
    args: Args,
) -> NDArray[np.bool_]:

    METHOD_ATTRS_SEP = ":"
    METHODS = ("audio", "motion", "pixeldiff", "random", "none", "all")

    result_array: Optional[NDArray[np.bool_]] = None
    operand: Optional[str] = None

    logic_funcs: Dict[str, BoolOperand] = {
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
    inputs: List[FileInfo],
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
