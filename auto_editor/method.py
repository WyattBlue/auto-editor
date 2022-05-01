import os
import random
from math import ceil
from dataclasses import dataclass, asdict, fields

from typing import List, Tuple, Union, Dict, Any, Callable, Type, TypeVar

import numpy as np

from auto_editor.wavfile import read
from auto_editor.utils.log import Log
from auto_editor.utils.func import parse_dataclass
from auto_editor.utils.types import float_type, StreamType, stream_type
from auto_editor.utils.progressbar import ProgressBar
from auto_editor.ffwrapper import FileInfo

T = TypeVar("T")


def get_attributes(attrs_str: str, dataclass: T, log: Log) -> T:
    attrs: T = parse_dataclass(attrs_str, dataclass, log)

    dic_value = asdict(attrs)
    dic_type: Dict[str, Union[type, Callable[[Any], Any]]] = {}
    for field in fields(attrs):
        dic_type[field.name] = field.type

    # Convert to the correct types
    for k, _type in dic_type.items():

        if _type == float:
            _type = float_type
        elif _type == StreamType:
            _type = stream_type

        try:
            attrs.__setattr__(k, _type(dic_value[k]))
        except (ValueError, TypeError) as e:
            log.error(str(e))

    return attrs


def get_media_duration(path: str, fps: float, temp: str, log: Log) -> int:

    audio_path = os.path.join(temp, "0.wav")

    if os.path.isfile(audio_path):
        sample_rate, audio_samples = read(audio_path)
        sample_rate_per_frame = sample_rate / fps
        return ceil(audio_samples.shape[0] / sample_rate_per_frame)

    import av

    container = av.open(path)

    if len(container.streams.video) < 1:
        log.error("Could not get media duration")

    video = av.open(path, "r").streams.video[0]
    return int(float(video.duration * video.time_base) * fps)


def get_audio_list(
    stream: StreamType,
    threshold: float,
    fps: float,
    progress: ProgressBar,
    temp: str,
    log: Log,
) -> np.ndarray:

    from auto_editor.analyze.audio import audio_detection

    path = os.path.join(temp, f"{stream}.wav")

    if os.path.isfile(path):
        sample_rate, audio_samples = read(path)
    else:
        log.error(f"Audio stream '{stream}' does not exist.")

    audio_list = audio_detection(audio_samples, sample_rate, fps, progress)

    del audio_samples

    return np.fromiter((x > threshold for x in audio_list), dtype=np.bool_)


def operand_combine(a: np.ndarray, b: np.ndarray, call: Callable) -> np.ndarray:
    if len(a) > len(b):
        b = np.resize(b, len(a))
    if len(b) > len(a):
        a = np.resize(a, len(b))

    return call(a, b)


def get_stream_data(
    method: str,
    attrs,
    args,
    inp: FileInfo,
    progress: ProgressBar,
    temp: str,
    log: Log,
) -> np.ndarray:

    if method == "none":
        return np.ones(
            (get_media_duration(inp.path, inp.gfps, temp, log)), dtype=np.bool_
        )
    if method == "all":
        return np.zeros(
            (get_media_duration(inp.path, inp.gfps, temp, log)), dtype=np.bool_
        )
    if method == "random":
        if attrs.cutchance > 1 or attrs.cutchance < 0:
            log.error(f"random:cutchance must be between 0 and 1")
        l = get_media_duration(inp.path, inp.gfps, temp, log)

        random.seed(attrs.seed)
        log.debug(f"Seed: {attrs.seed}")

        a = random.choices((0, 1), weights=(attrs.cutchance, 1 - attrs.cutchance), k=l)

        return np.asarray(a, dtype=np.bool_)
    if method == "audio":
        if attrs.stream == "all":
            total_list = None
            for i in range(len(inp.audios)):
                audio_list = get_audio_list(
                    i, attrs.threshold, inp.gfps, progress, temp, log
                )
                if total_list is None:
                    total_list = audio_list
                else:
                    total_list = operand_combine(total_list, audio_list, np.logical_or)

            if total_list is None:
                log.error("Input has no audio streams.")
            return total_list
        else:
            return get_audio_list(
                attrs.stream, attrs.threshold, inp.gfps, progress, temp, log
            )
    if method == "motion":
        from auto_editor.analyze.motion import motion_detection

        if len(inp.videos) == 0:
            log.error("Video stream '0' does not exist.")

        motion_list = motion_detection(inp, progress, attrs.width, attrs.blur)
        return np.fromiter((x >= attrs.threshold for x in motion_list), dtype=np.bool_)

    # "pixeldiff"
    from auto_editor.analyze.pixeldiff import pixel_difference

    if len(inp.videos) == 0:
        log.error("Video stream '0' does not exist.")

    pixel_list = pixel_difference(inp, progress)
    return np.fromiter((x >= attrs.threshold for x in pixel_list), dtype=np.bool_)


def get_has_loud(
    method_str: str, inp: FileInfo, progress: ProgressBar, temp: str, log: Log, args
) -> np.ndarray:
    @dataclass
    class Audio:
        stream: StreamType = 0
        threshold: float = args.silent_threshold

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
        seed: int = random.randint(0, 2147483647)

    KEYWORD_SEP = " "
    METHOD_ATTRS_SEP = ":"

    result_array = None
    operand = None

    logic_funcs = {
        "and": np.logical_and,
        "or": np.logical_or,
        "xor": np.logical_xor,
    }

    Methods = Union[Type[Audio], Type[Motion], Type[Pixeldiff], Type[Random], None]

    method_str = method_str.replace("_", " ")  # Allow old style `--edit` to work

    for method in method_str.split(KEYWORD_SEP):

        if method == "":  # Skip whitespace
            continue

        if METHOD_ATTRS_SEP in method:
            method, attrs_str = method.split(METHOD_ATTRS_SEP)
        else:
            attrs_str = ""

        if method in ("audio", "motion", "pixeldiff", "random", "none", "all"):
            if result_array is not None and operand is None:
                log.error("Logic operator must be between two editing methods.")

            if method == "audio":
                attrs: Methods = get_attributes(attrs_str, Audio, log)
            elif method == "motion":
                attrs = get_attributes(attrs_str, Motion, log)
            elif method == "pixeldiff":
                attrs = get_attributes(attrs_str, Pixeldiff, log)
            elif method == "random":
                attrs = get_attributes(attrs_str, Random, log)
            else:
                attrs = None

            stream_data = get_stream_data(method, attrs, args, inp, progress, temp, log)

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

        elif method in ("and", "or", "xor"):
            if operand is not None:
                log.error("Invalid Editing Syntax.")
            if result_array is None:
                log.error(f"'{method}' operand needs two arguments.")
            operand = method
        elif method == "not":
            if operand is not None:
                log.error("Invalid Editing Syntax.")
            operand = method
        else:
            log.error(f"Unknown method/operator: '{method}'")

    if operand is not None:
        log.error(f"Dangling operand: '{operand}'")

    assert result_array is not None
    return result_array


def get_chunks(
    inp: FileInfo, args, progress: ProgressBar, temp: str, log: Log
) -> List[Tuple[int, int, float]]:
    from auto_editor.cutting import (
        to_speed_list,
        set_range,
        chunkify,
        apply_mark_as,
        apply_margin,
        seconds_to_frames,
        cook,
    )

    start_margin, end_margin = args.frame_margin

    fps = inp.gfps

    start_margin = seconds_to_frames(start_margin, fps)
    end_margin = seconds_to_frames(end_margin, fps)
    min_clip = seconds_to_frames(args.min_clip_length, fps)
    min_cut = seconds_to_frames(args.min_cut_length, fps)

    has_loud = get_has_loud(args.edit_based_on, inp, progress, temp, log, args)
    has_loud_length = len(has_loud)

    has_loud = apply_mark_as(has_loud, has_loud_length, fps, args, log)
    has_loud = cook(has_loud, min_clip, min_cut)
    has_loud = apply_margin(has_loud, has_loud_length, start_margin, end_margin)

    # Remove small clips/cuts created by applying other rules.
    has_loud = cook(has_loud, min_clip, min_cut)

    speed_list = to_speed_list(has_loud, args.video_speed, args.silent_speed)

    if args.cut_out != []:
        speed_list = set_range(speed_list, args.cut_out, fps, 99999, log)

    if args.add_in != []:
        speed_list = set_range(speed_list, args.add_in, fps, args.video_speed, log)

    if args.set_speed_for_range != []:
        for item in args.set_speed_for_range:
            speed_list = set_range(speed_list, [item[1:]], fps, item[0], log)

    return chunkify(speed_list, has_loud_length)
