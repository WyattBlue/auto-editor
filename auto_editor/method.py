import os
from dataclasses import dataclass, asdict, fields

import numpy as np

from auto_editor.utils.log import Log


def get_audio_list(stream, threshold, fps, progress, temp, log):
    from auto_editor.analyze.audio import audio_detection
    from auto_editor.scipy.wavfile import read

    path = os.path.join(temp, f'{stream}.wav')

    if os.path.isfile(path):
        sample_rate, audio_samples = read(path)
    else:
        log.error(f"Audio stream '{stream}' does not exist.")

    audio_list = audio_detection(audio_samples, sample_rate, threshold, fps, progress)

    del audio_samples

    return audio_list


def or_combine(a: np.ndarray, b: np.ndarray) -> np.ndarray:
    if len(a) > len(b):
        b = np.resize(b, len(a))
    if len(b) > len(a):
        a = np.resize(a, len(b))
    return a | b


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
                    total_list = or_combine(total_list, audio_list)

            if total_list is None:
                log.error('Input has no audio streams.')
            return total_list
        else:
            return get_audio_list(attrs.stream, attrs.threshold, fps, progress, temp, log)


    if method == 'motion':
        from auto_editor.analyze.motion import motion_detection

        return motion_detection(
            inp.path, fps, attrs.threshold, progress, attrs.width, attrs.blur
        )


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
        threshold: float = 0.02
        blur: int = 9
        width: int = 400

    KEYWORD_SEP = ' '
    METHOD_ATTRS_SEP = ':'

    result_array = None

    for method in method_str.split(KEYWORD_SEP):

        if METHOD_ATTRS_SEP in method:
            method, attrs_str = method.split(METHOD_ATTRS_SEP)
        else:
            attrs_str = ''

        if method == 'audio':
            attrs = get_attributes(attrs_str, Audio, log)
        elif method == 'motion':
            attrs = get_attributes(attrs_str, Motion, log)
        else:
            attrs = None

        if method in ('audio', 'motion', 'none', 'all'):
            stream_data = get_stream_data(
                method, attrs, args, inp, fps, progress, temp, log
            )

            if result_array is None:
                result_array = stream_data
        else:
            log.error(f"Editing method: '{method}' is not supported.")

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
