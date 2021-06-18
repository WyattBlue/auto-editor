'''cutting.py'''

from __future__ import print_function

import numpy as np

def combine_audio_motion(audioList, motionList, based, log):
    # (audioList: np.ndarray, motionList: np.ndarray, based: str, log) -> np.ndarray:

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


def combine_segment(hasLoud, segment, fps):
    for item in segment:
        start, end = item['segment']
        start = int(start * fps)
        end = int(end * fps)
        hasLoud[start:end] = False
    return hasLoud


def removeSmall(hasLoud, lim, replace, with_):
    # (hasLoud: np.ndarray, lim: int, replace: bool, with_: bool) -> np.ndarray:
    startP = 0
    active = False
    for j, item in enumerate(hasLoud):
        if(item == replace):
            if(not active):
                startP = j
                active = True
            # Special case for end.
            if(j == len(hasLoud) - 1):
                if(j - startP < lim):
                    hasLoud[startP:j+1] = with_
        else:
            if(active):
                if(j - startP < lim):
                    hasLoud[startP:j] = with_
                active = False
    return hasLoud


def isNumber(val):
    return val.replace('.', '', 1).isdigit()

def setRange(hasLoud, syntaxRange, fps, with_, log):
    # (hasLoud: np.ndarray, syntaxRange, fps: float, with_, log) -> np.ndarray:

    def replaceVarsWithVals(item):
        if(isNumber(item)):
            return int(item)
        if(item == 'start'):
            return 0
        if(item == 'end'):
            return len(hasLoud)
        if(item.startswith('sec')):
            log.error('Seconds unit not implemented in this function.')
        log.error('Variable {} not avaiable in this context.'.format(item))

    def ConvertToFrames(num):
        # (num) -> int:
        num = replaceVarsWithVals(num)
        if(num < 0):
            num = len(hasLoud) - num
        return num

    for item in syntaxRange:
        pair = list(map(ConvertToFrames, item))
        hasLoud[pair[0]:pair[1]] = with_
    return hasLoud


def secToFrames(value, fps):
    if(isinstance(value, str)):
        return int(float(value) * fps)
    return value

def cook(hasLoud, minClip, minCut):
    # (hasLoud: np.ndarray, minClip: int, minCut: int) -> np.ndarray:
    hasLoud = removeSmall(hasLoud, minClip, replace=1, with_=0)
    hasLoud = removeSmall(hasLoud, minCut, replace=0, with_=1)
    return hasLoud


# Turn long silent/loud array to formatted chunk list.
# Example: [True, True, True, False, False] => [[0, 3, 1], [3, 5, 0]]
def chunkify(hasLoud, hasLoudLengthCache=None):
    # () -> list:
    if(hasLoudLengthCache is None):
        hasLoudLengthCache = len(hasLoud)

    chunks = []
    startP = 0
    for j in range(1, hasLoudLengthCache):
        if(hasLoud[j] != hasLoud[j - 1]):
            chunks.append([startP, j, int(hasLoud[j-1])])
            startP = j
    chunks.append([startP, hasLoudLengthCache, int(hasLoud[j])])
    return chunks


def applySpacingRules(hasLoud, speeds, fps, args, log):
    # (hasLoud: np.ndarray, speeds: list, fps: float, args, log) -> list:
    frameMargin = secToFrames(args.frame_margin, fps)
    minClip = secToFrames(args.min_clip_length, fps)
    minCut = secToFrames(args.min_cut_length, fps)

    hasLoud = cook(hasLoud, minClip, minCut)
    hasLoudLengthCache = len(hasLoud)

    def applyFrameMargin(hasLoud, hasLoudLengthCache, frameMargin):
        # () -> np.ndarray:
        new = np.zeros((hasLoudLengthCache), dtype=np.uint8)
        for i in range(hasLoudLengthCache):
            start = int(max(0, i - frameMargin))
            end = int(min(hasLoudLengthCache, i+1+frameMargin))
            new[i] = min(1, np.max(hasLoud[start:end]))
        return new

    hasLoud = applyFrameMargin(hasLoud, hasLoudLengthCache, frameMargin)

    if(args.mark_as_loud != []):
        hasLoud = setRange(hasLoud, args.mark_as_loud, fps, 1, log)

    if(args.mark_as_silent != []):
        hasLoud = setRange(hasLoud, args.mark_as_silent, fps, 0, log)

    # Remove small clips/cuts created by applying other rules.
    hasLoud = cook(hasLoud, minClip, minCut)

    if(args.cut_out != []):
        cut_speed_index = speeds.index(99999)
        hasLoud = setRange(hasLoud, args.cut_out, fps, cut_speed_index, log)

    if(args.set_speed_for_range != []):
        for item in args.set_speed_for_range:
            my_speed_index = speeds.index(float(item[0]))
            hasLoud = setRange(hasLoud, [item[1:]], fps, my_speed_index, log)

    return chunkify(hasLoud, hasLoudLengthCache)


def applyBasicSpacing(hasLoud, fps, minClip, minCut, log):
    # (hasLoud: np.ndarray, fps: float, minClip: int, minCut: int, log)
    minClip = secToFrames(minClip, fps)
    minCut = secToFrames(minCut, fps)

    hasLoud = cook(hasLoud, minClip, minCut)
    return chunkify(hasLoud)


def merge(start_list, end_list):
    # (start_list: np.ndarray, end_list: np.ndarray) -> np.ndarray:
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
    # (val: str, data, sampleRate, fps, log) -> list:
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
            chunks = applyBasicSpacing(merge(start_list, end_list), fps, 0, 0, log)
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
            chunks = applyBasicSpacing(merge(start_list, end_list), fps, 0, 0, log)
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
