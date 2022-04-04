import os
from dataclasses import dataclass, asdict, fields

from typing import Union, Callable

import numpy as np

from auto_editor.utils.log import Log
from auto_editor.utils.progressbar import ProgressBar


def get_audio_list(
    stream: Union[int, str],
    threshold: float,
    fps: float,
    progress: ProgressBar,
    temp: str,
    log: Log,
) -> np.ndarray:

    from auto_editor.analyze.audio import audio_detection
    from auto_editor.scipy.wavfile import read

    path = os.path.join(temp, f'{stream}.wav')

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


def get_stream_data(method: str, attrs, args, inp, fps, progress, temp, log):

    from auto_editor.analyze.generic import get_np_list

    audio_samples, sample_rate = None, None

    if method == 'none':
        return get_np_list(inp.path, audio_samples, sample_rate, fps, np.ones)
    if method == 'all':
        return get_np_list(inp.path, audio_samples, sample_rate, fps, np.zeros)
    if method == 'audio':
        if attrs.stream == 'all':
            total_list = None
            for i in range(len(inp.audio_streams)):
                audio_list = get_audio_list(i, attrs.threshold, fps, progress, temp, log)
                if total_list is None:
                    total_list = audio_list
                else:
                    total_list = operand_combine(total_list, audio_list, np.logical_or)

            if total_list is None:
                log.error('Input has no audio streams.')
            return total_list
        else:
            return get_audio_list(attrs.stream, attrs.threshold, fps, progress, temp, log)
    if method == 'motion':
        from auto_editor.analyze.motion import motion_detection

        if len(inp.video_streams) == 0:
            log.error("Video stream '0' does not exist.")

        motion_list = motion_detection(inp.path, fps, progress, attrs.width, attrs.blur)
        return np.fromiter((x >= attrs.threshold for x in motion_list), dtype=np.bool_)

    if method == 'pixeldiff':
        from auto_editor.analyze.pixeldiff import pixel_difference

        if len(inp.video_streams) == 0:
            log.error("Video stream '0' does not exist.")

        pixel_list = pixel_difference(inp.path, fps, progress)
        return np.fromiter((x >= attrs.threshold for x in pixel_list), dtype=np.bool_)

def get_attributes(attrs_str, dataclass, log):
    from auto_editor.vanparse import parse_dataclass, ParserError

    try:
        attrs = parse_dataclass(attrs_str, dataclass)
    except ParserError as e:
        log.error(str(e))

    dic_value = asdict(attrs)
    dic_type = {}
    for field in fields(attrs):
        dic_type[field.name] = field.type

    # Convert to the correct types
    for k, _type in dic_type.items():
        try:
            attrs.__setattr__(k, _type(dic_value[k]))
        except (ValueError, TypeError) as e:
            log.error(str(e))

    return attrs


def get_has_loud(method_str, inp, fps, progress, temp, log, args):

    from auto_editor.utils.types import float_type

    def stream_type(val: str):
        if val == 'all':
            return val
        return int(val)

    @dataclass
    class Audio:
        stream: stream_type = 0
        threshold: float_type = args.silent_threshold

    @dataclass
    class Motion:
        threshold: float_type = 0.02
        blur: int = 9
        width: int = 400

    @dataclass
    class Pixeldiff:
        threshold: int = 1

    KEYWORD_SEP = ' '
    METHOD_ATTRS_SEP = ':'

    result_array = None
    operand = None

    logic_funcs = {
        'and': np.logical_and,
        'or': np.logical_or,
        'xor': np.logical_xor,
    }

    method_str = method_str.replace('_', ' ')  # Allow old style `--edit` to work

    for method in method_str.split(KEYWORD_SEP):

        if method == '':  # Skip whitespace
            continue

        if METHOD_ATTRS_SEP in method:
            method, attrs_str = method.split(METHOD_ATTRS_SEP)
        else:
            attrs_str = ''

        if method == 'audio':
            attrs = get_attributes(attrs_str, Audio, log)
        elif method == 'motion':
            attrs = get_attributes(attrs_str, Motion, log)
        elif method == 'pixeldiff':
            attrs = get_attributes(attrs_str, Pixeldiff, log)
        else:
            attrs = None

        if method in ('audio', 'motion', 'pixeldiff', 'none', 'all'):

            if result_array is not None and operand is None:
                log.error("Logic operator must be between two editing methods.")

            stream_data = get_stream_data(
                method, attrs, args, inp, fps, progress, temp, log
            )

            if operand == 'not':
                result_array = np.logical_not(stream_data)
                operand = None
            elif result_array is None:
                result_array = stream_data
            elif operand in ('and', 'or', 'xor'):
                result_array = operand_combine(result_array, stream_data, logic_funcs[operand])
                operand = None

        elif method in ('and', 'or', 'xor'):
            if operand is not None:
                log.error('Invalid Editing Syntax.')
            if result_array is None:
                log.error(f"'{method}' operand needs two arguments.")
            operand = method
        elif method == 'not':
            if operand is not None:
                log.error('Invalid Editing Syntax.')
            operand = method
        else:
            log.error(f"Unknown method/operator: '{method}'")

    if operand is not None:
        log.error(f"Dangling operand: '{operand}'")

    return result_array


def get_chunks(inp, fps, args, progress, temp, log):
    from auto_editor.cutting import (to_speed_list, set_range, chunkify, apply_mark_as,
        apply_margin, seconds_to_frames, cook)

    start_margin, end_margin = args.frame_margin

    start_margin = seconds_to_frames(start_margin, fps)
    end_margin = seconds_to_frames(end_margin, fps)
    min_clip = seconds_to_frames(args.min_clip_length, fps)
    min_cut = seconds_to_frames(args.min_cut_length, fps)

    has_loud = get_has_loud(args.edit_based_on, inp, fps, progress, temp, log, args)
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
