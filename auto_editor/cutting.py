'''cutting.py'''

from __future__ import print_function

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
                return int(round(value * fps))
            log.error('Unknown unit: {}'.format(unit))
        if(item == 'start'):
            return 0
        if(item == 'end'):
            return len(has_loud)
        log.error('Variable {} not available.'.format(item))

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
# Example: [True, True, True, False, False] => [[0, 3, 1], [3, 5, 0]]
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


def handleBoolExp(val, data, sampleRate, fps, log):
    # type: (...) -> np.ndarray
    invert = False

    if('>' in val and '<' in val):
        log.error('Cannot have both ">" and "<" in same expression.')
    if('>' in val):
        exp = val.split('>')
    elif('<' in val):
        exp = val.split('<')
        invert = True
    else:
        log.error('audio array needs ">" or "<".')

    if(len(exp) != 2):
        log.error('Only one expression supported, not {}.'.format(len(exp)-1))

    if(data is None or sampleRate is None):
        log.error('No audio data found.')

    from auto_editor.analyze import audio_detection
    new_list = audio_detection(data, sampleRate, float(exp[1]), fps, log)

    if(invert):
        new_list = np.invert(new_list)

    return new_list


def applyRects(cmdRects, audioData, sampleRate, fps, log):
    from auto_editor.utils.func import hex_to_bgr

    rects = []
    for ms in cmdRects:
        if(len(ms) < 6):
            log.error('Too few comma arguments for rectangle option.')

        if(len(ms) > 8):
            log.error('Too many comma arguments for rectangle option.')

        start, end, x1, y1, x2, y2 = ms[:6]

        color = '#000'
        thickness = -1
        if(len(ms) > 6):
            color = ms[6]
        if(len(ms) > 7):
            thickness = int(ms[7])
        color = hex_to_bgr(color, log)

        # Handle Boolean Expressions. Mostly the same as zoom.
        start_list, end_list = None, None
        if(start.startswith('audio')):
            start_list = handleBoolExp(start, audioData, sampleRate, fps, log)

        if(end.startswith('audio')):
            if(start_list is None):
                log.error('The start parameter must also have a boolean expression.')
            end_list = handleBoolExp(end, audioData, sampleRate, fps, log)

        if(start_list is None):
            rects.append(['rectangle', start, end, x1, y1, x2, y2, color, thickness])

        elif(end_list is None):
            # Handle if end is not a boolean expression.
            indexs = np.where(start_list)[0]
            if(indexs != []):
                rects.append(['rectangle', str(indexs[0]), end, x1, y1, x2, y2, color,
                    thickness])
        else:
            chunks = apply_basic_spacing(merge(start_list, end_list), fps, 0, 0, log)
            for item in chunks:
                if(item[2] == 1):
                    rects.append(['rectangle', str(item[0]), str(item[1]), x1, y1, x2, y2,
                        color, thickness])

            if(rects == []):
                log.warning('No rectangles applied.')
            else:
                log.print(' {} rectangles applied.'.format(len(rects)))

    return rects


def applyZooms(cmdZooms, audioData, sampleRate, fps, log):
    zooms = []
    for ms in cmdZooms:

        start, end = ms[:2]

        start_zoom = float(ms[2])

        if(len(ms) == 3):
            end_zoom = start_zoom
        else:
            end_zoom = float(ms[3])

        x = 'centerX'
        y = 'centerY'
        inter = 'linear'
        hold = None

        if(len(ms) > 4):
            x, y = ms[4:6]

        if(len(ms) > 6):
            inter = ms[6]

        if(len(ms) > 7):
            hold = ms[7]

        start_list, end_list = None, None
        if(start.startswith('audio')):
            start_list = handleBoolExp(start, audioData, sampleRate, fps, log)

        if(end.startswith('audio')):
            if(start_list is None):
                log.error('The start parameter must also have a boolean expression.')
            end_list = handleBoolExp(end, audioData, sampleRate, fps, log)

        if(start_list is None):
            zooms.append(['zoom', start, end, start_zoom, end_zoom, x, y, inter, hold])

        elif(end_list is None):
            # Handle if end is not a boolean expression.
            indexs = np.where(start_list)[0]
            if(indexs != []):
                zooms.append(['zoom', str(indexs[0]), end, start_zoom, end_zoom, x, y,
                    inter, hold])
        else:
            chunks = apply_basic_spacing(merge(start_list, end_list), fps, 0, 0, log)
            for item in chunks:
                if(item[2] == 1):
                    zooms.append(['zoom', str(item[0]), str(item[1]), start_zoom,
                        end_zoom, x, y, inter, hold])

            if(zooms == []):
                log.warning('No zooms applied.')
            else:
                log.print(' {} zooms applied.'.format(len(zooms)))

    log.debug(zooms)
    return zooms
