'''cutting.py'''

import numpy as np

from auto_editor.utils.types import split_num_str

def combine_audio_motion(audioList, motionList, based, log):
    # type: (np.ndarray, np.ndarray, str, Any) -> np.ndarray

    if(based == 'audio' or based == 'not_audio'):
        if(max(audioList) == 0):
            log.error('There was no place where audio exceeded the threshold.')
    if(based == 'motion' or based == 'not_motion'):
        if(max(motionList) == 0):
            log.error('There was no place where motion exceeded the threshold.')

    if(audioList is not None and max(audioList) == 0):
        log.warning('There was no place where audio exceeded the threshold.')
    if(motionList is not None and max(motionList) == 0):
        log.warning('There was no place where motion exceeded the threshold.')

    if(based == 'audio'):
        return audioList

    if(based == 'motion'):
        return motionList

    if(based == 'not_audio'):
        return np.invert(audioList)

    if(based == 'not_motion'):
        return np.invert(motionList)

    if(based == 'audio_and_motion'):
        return audioList & motionList

    if(based == 'audio_or_motion'):
        return audioList | motionList

    if(based == 'audio_xor_motion'):
        return np.bitwise_xor(audioList, motionList)

    if(based == 'audio_and_not_motion'):
        return audioList & np.invert(motionList)

    if(based == 'not_audio_and_motion'):
        return np.invert(audioList) & motionList

    if(based == 'not_audio_and_not_motion'):
        return np.invert(audioList) & np.invert(motionList)
    return None


def combine_segment(has_loud, segment, fps):
    for item in segment:
        start, end = item['segment']
        start = int(start * fps)
        end = int(end * fps)
        has_loud[start:end] = False
    return has_loud


def removeSmall(has_loud, lim, replace, with_):
    # type: (np.ndarray, int, int, int) -> np.ndarray
    startP = 0
    active = False
    for j, item in enumerate(has_loud):
        if(item == replace):
            if(not active):
                startP = j
                active = True
            # Special case for end.
            if(j == len(has_loud) - 1):
                if(j - startP < lim):
                    has_loud[startP:j+1] = with_
        else:
            if(active):
                if(j - startP < lim):
                    has_loud[startP:j] = with_
                active = False
    return has_loud


def str_is_number(val):
    # type: (str) -> bool
    return val.replace('.', '', 1).replace('-', '', 1).isdigit()


def str_starts_with_number(val):
    # type: (str) -> bool
    if(val.startswith('-')):
        val = val[1:]
    val = val.replace('.', '', 1)
    return val[0].isdigit()


def setRange(has_loud, range_syntax, fps, with_, log):
    # type: (...) -> np.ndarray

    def replace_variables_to_values(item, fps, log):
        # type: (str, float | int, Any) -> int
        if(str_is_number(item)):
            return int(item)
        if(str_starts_with_number(item)):
            value, unit = split_num_str(item, log.error)
            if(unit in ['', 'f', 'frame', 'frames']):
                if(isinstance(value, float)):
                    log.error('float type cannot be used with frame unit')
                return value
            if(unit in ['s', 'sec', 'secs', 'second', 'seconds']):
                return round(value * fps)
            log.error('Unknown unit: {}'.format(unit))
        if(item == 'start'):
            return 0
        if(item == 'end'):
            return len(has_loud)
        log.error("variable '{}' not available.".format(item))

    def var_val_to_frames(val, fps, log):
        # type: (str, float | int, Any) -> int
        num = replace_variables_to_values(val, fps, log)
        if(num < 0):
            num += len(has_loud)
        return num

    for item in range_syntax:
        pair = []
        for val in item:
            pair.append(var_val_to_frames(val, fps, log))
        has_loud[pair[0]:pair[1]] = with_
    return has_loud


def seconds_to_frames(value, fps):
    # type: (int | str, float) -> int
    if(isinstance(value, str)):
        return int(float(value) * fps)
    return value

def cook(has_loud, minClip, minCut):
    # type: (np.ndarray, int, int) -> np.ndarray
    has_loud = removeSmall(has_loud, minClip, replace=1, with_=0)
    has_loud = removeSmall(has_loud, minCut, replace=0, with_=1)
    return has_loud


# Turn long silent/loud array to formatted chunk list.
# Example: [1, 1, 1, 0, 0] => [[0, 3, 1], [3, 5, 0]]
def chunkify(has_loud, has_loud_length=None):
    # type: (np.ndarray, int | None) -> list[list[int]]
    if(has_loud_length is None):
        has_loud_length = len(has_loud)

    chunks = []
    startP = 0
    for j in range(1, has_loud_length):
        if(has_loud[j] != has_loud[j - 1]):
            chunks.append([startP, j, int(has_loud[j-1])])
            startP = j
    chunks.append([startP, has_loud_length, int(has_loud[j])])
    return chunks


# Turn chunk list into silent/loud like array.
# Example: [[0, 3, 1], [3, 5, 0]] => [1, 1, 1, 0, 0]
def chunks_to_has_loud(chunks):
    # type: (list[list[int]]) -> np.ndarray
    duration = chunks[len(chunks) - 1][1]
    has_loud = np.zeros((duration), dtype=np.uint8)

    for chunk in chunks:
        if(chunk[2] != 0):
            has_loud[chunk[0]:chunk[1]] = chunk[2]
    return has_loud


def apply_frame_margin(has_loud, has_loud_length, frame_margin):
    # type: (np.ndarray, int, int) -> np.ndarray
    new = np.zeros((has_loud_length), dtype=np.uint8)
    for i in range(has_loud_length):
        start = int(max(0, i - frame_margin))
        end = int(min(has_loud_length, i+1+frame_margin))
        new[i] = min(1, np.max(has_loud[start:end]))
    return new


def apply_mark_as(has_loud, has_loud_length, fps, args, log):
    # type: (...) -> np.ndarray
    if(args.mark_as_loud != []):
        has_loud = setRange(has_loud, args.mark_as_loud, fps, 1, log)

    if(args.mark_as_silent != []):
        has_loud = setRange(has_loud, args.mark_as_silent, fps, 0, log)
    return has_loud

def apply_spacing_rules(has_loud, has_loud_length, minClip, minCut, speeds, fps, args, log):
    # type: (...) -> list[list[int]]
    if(args.cut_out != []):
        has_loud = setRange(has_loud, args.cut_out, fps, speeds.index(99999), log)

    if(args.add_in != []):
        has_loud = setRange(has_loud, args.add_in, fps, speeds.index(args.video_speed), log)

    if(args.set_speed_for_range != []):
        for item in args.set_speed_for_range:
            my_speed_index = speeds.index(float(item[0]))
            has_loud = setRange(has_loud, [item[1:]], fps, my_speed_index, log)

    return chunkify(has_loud, has_loud_length)


def apply_basic_spacing(has_loud, fps, minClip, minCut, log):
    # type: (np.ndarray, float, int, int, Any) -> list[list[int]]
    minClip = seconds_to_frames(minClip, fps)
    minCut = seconds_to_frames(minCut, fps)

    has_loud = cook(has_loud, minClip, minCut)
    return chunkify(has_loud)


def merge(start_list, end_list):
    # type: (np.ndarray, np.ndarray) -> np.ndarray
    merge = np.zeros((len(start_list)), dtype=np.bool_)

    startP = 0
    for item in start_list:
        if(item == True):
            where_list = np.where(end_list[startP:])[0]
            if(len(where_list) > 0):
                merge[startP:where_list[0]] = True
        startP += 1
    return merge

