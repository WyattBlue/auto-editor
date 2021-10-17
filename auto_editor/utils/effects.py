
import numpy as np

# Included Libraries
from .interpolate import interpolate


def values(val, log, _type, total_frames, width, height):
    if(val == 'centerX'):
        return int(width / 2)
    if(val == 'centerY'):
        return int(height / 2)
    if(val == 'start'):
        return 0
    if(val == 'end'):
        return total_frames - 1
    if(val == 'width'):
        return width
    if(val == 'height'):
        return height

    if(not isinstance(val, int)
        and not (val.replace('.', '', 1)).replace('-', '', 1).isdigit()):
        log.error('Variable {} not implemented.'.format(val))
    return _type(val)


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


def get_effects(audio_samples, sample_rate, fps, args, log):
    effects = []
    if(args.zoom != []):
        from auto_editor.cutting import applyZooms
        effects += applyZooms(args.zoom, audio_samples, sample_rate, fps, log)
    if(args.rectangle != []):
        from auto_editor.cutting import applyRects
        effects += applyRects(args.rectangle, audio_samples, sample_rate, fps, log)
    return effects


def applyRects(cmdRects, audioData, sampleRate, fps, log):
    print(cmdRects)
    rects = []
    for ms in cmdRects:

        start, end, x1, y1, x2, y2 = ms[:6]

        color = '#000'
        thickness = -1
        if(len(ms) > 6):
            color = ms[6]
        if(len(ms) > 7):
            thickness = int(ms[7])

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


def make_effects_sheet(effects, total_frames, width, height, log):
    effect_sheet = []
    for effect in effects:
        if(effect[0] == 'rectangle'):

            rectx1_sheet = np.zeros((total_frames + 1), dtype=int)
            recty1_sheet = np.zeros((total_frames + 1), dtype=int)
            rectx2_sheet = np.zeros((total_frames + 1), dtype=int)
            recty2_sheet = np.zeros((total_frames + 1), dtype=int)
            rectco_sheet = np.zeros((total_frames + 1, 3), dtype=int)
            rect_t_sheet = np.zeros((total_frames + 1), dtype=int)

            r = effect[1:]

            for i in range(6):
                r[i] = values(r[i], log, int, total_frames, width, height)

            rectx1_sheet[r[0]:r[1]] = r[2]
            recty1_sheet[r[0]:r[1]] = r[3]
            rectx2_sheet[r[0]:r[1]] = r[4]
            recty2_sheet[r[0]:r[1]] = r[5]
            rectco_sheet[r[0]:r[1]] = r[6]
            rect_t_sheet[r[0]:r[1]] = r[7]

            effect_sheet.append(
                ['rectangle', rectx1_sheet, recty1_sheet, rectx2_sheet, recty2_sheet,
                rectco_sheet, rect_t_sheet]
            )

        if(effect[0] == 'zoom'):

            zoom_sheet = np.ones((total_frames + 1), dtype=float)
            zoomx_sheet = np.full((total_frames + 1), int(width / 2), dtype=float)
            zoomy_sheet = np.full((total_frames + 1), int(height / 2), dtype=float)

            z = effect[1:]
            z[0] = values(z[0], log, int, total_frames, width, height)
            z[1] = values(z[1], log, int, total_frames, width, height)

            if(z[7] is not None): # hold value
                z[7] = values(z[7], log, int, total_frames, width, height)

            if(z[7] is None or z[7] > z[1]):
                zoom_sheet[z[0]:z[1]] = interpolate(z[2], z[3], z[1] - z[0], log,
                    method=z[6])
            else:
                zoom_sheet[z[0]:z[0]+z[7]] = interpolate(z[2], z[3], z[7], log,
                    method=z[6])
                zoom_sheet[z[0]+z[7]:z[1]] = z[3]

            zoomx_sheet[z[0]:z[1]] = values(z[4], log, float, total_frames, width, height)
            zoomy_sheet[z[0]:z[1]] = values(z[5], log, float, total_frames, width, height)

            effect_sheet.append(
                ['zoom', zoom_sheet, zoomx_sheet, zoomy_sheet]
            )
    return effect_sheet
