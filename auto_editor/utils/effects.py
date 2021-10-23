
import numpy as np

# Included Libraries
from auto_editor.analyze import audio_detection

from .interpolate import interpolate


def boolean_expression(val, data, sampleRate, fps, log):
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
    # cmdRects = [start,end,10,20,20,30]
    print(cmdRects)
    rects = []
    for ms in cmdRects:


        # Handle Boolean Expressions. Mostly the same as zoom.
        start_list, end_list = None, None
        if(start.startswith('audio')):
            start_list = boolean_expression(start, audioData, sampleRate, fps, log)

        if(end.startswith('audio')):
            if(start_list is None):
                log.error('The start parameter must also have a boolean expression.')
            end_list = boolean_expression(end, audioData, sampleRate, fps, log)

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
            start_list = boolean_expression(start, audioData, sampleRate, fps, log)

        if(end.startswith('audio')):
            if(start_list is None):
                log.error('The start parameter must also be a boolean expression.')
            end_list = boolean_expression(end, audioData, sampleRate, fps, log)

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
