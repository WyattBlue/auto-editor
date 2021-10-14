
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
