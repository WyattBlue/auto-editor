import os.path
import re
from typing import Any, List, Tuple

from .func import clean_list

def split_num_str(val):
    # type: (str | int, Any) -> Tuple[int | float, str]
    if isinstance(val, int):
        return val, ''
    index = 0
    for item in val:
        if not item.isdigit() and item != ' ' and item != '.' and item != '-':
            break
        index += 1
    num, unit = val[:index], val[index:]
    if '.' in num:
        try:
            float(num)
        except ValueError:
            raise TypeError(f"Invalid number: '{val}'")
        return float(num), unit
    try:
        int(num)
    except ValueError:
        raise TypeError(f"Invalid number: '{val}'")
    return int(num), unit

def file_type(path):
    # type: (str) -> str
    if not os.path.isfile(path):
        raise TypeError(f'Auto-Editor could not find the file: {path}')
    return path

def unit_check(unit, allowed_units):
    # type: (str, List[str]) -> None
    if unit not in allowed_units:
        raise TypeError(f"Unknown unit: '{unit}'")

def float_type(val):
    # type: (str | int | float) -> float
    if isinstance(val, (int, float)):
        return float(val)

    num, unit = split_num_str(val)
    unit_check(unit, ['%', ''])
    if unit == '%':
        return float(num / 100)
    return float(num)

def sample_rate_type(val):
    # type: (str) -> int
    num, unit = split_num_str(val)
    unit_check(unit, ['Hz', 'kHz', ''])
    if unit == 'kHz':
        return int(num * 1000)
    return int(num)

def frame_units():
    return ['f', 'frame', 'frames']

def second_units():
    return ['s', 'sec', 'secs', 'second', 'seconds']

def frame_type(val):
    # type: (str) -> int | str
    num, unit = split_num_str(val)
    unit_check(unit, [''] + frame_units() + second_units())

    if unit in second_units():
        return str(num).strip()
    return int(num)

def anchor_type(val):
    allowed = ('tl', 'tr', 'bl', 'br', 'ce')
    if val not in allowed:
        raise TypeError('Anchor must be: ' + ' '.join(allowed))
    return val

def margin_type(val):
    # type: (str) -> Tuple[int | str, int | str]
    vals = val.split(',')
    if len(vals) == 1:
        vals.append(vals[0])
    if len(vals) != 2:
        raise TypeError('Too many comma arguments for margin_type')
    return frame_type(vals[0]), frame_type(vals[1])

def comma_type(inp, min_args=1, max_args=None, name=''):
    inp = clean_list(inp.split(','), '\r\n\t')
    if min_args > len(inp):
        raise TypeError(f'Too few comma arguments for {name}.')
    if max_args is not None and len(inp) > max_args:
        raise TypeError(f'Too many comma arguments for {name}.')
    return inp

def range_type(inp):
    return comma_type(inp, 2, 2, 'range_type')

def speed_range_type(inp):
    return comma_type(inp, 3, 3, 'speed_range_type')

def block_type(inp):
    return comma_type(inp, 1, None, 'block_type')

def text_content(val: str):
    return val.replace('\\n', '\n')

def align_type(val: str):
    allowed = ('left', 'right', 'center')
    if val not in allowed:
        raise TypeError('Align must be: ' + ' '.join(allowed))
    return val


def color_type(val: str):
    """
    Convert a color str into an RGB tuple

    Accepts:
        - color names (black, red, blue)
        - 3 digit hex codes (#FFF, #3AE)
        - 6 digit hex codes (#3F0401, #005601)
    """

    color = val.lower()

    if color in colormap:
        color = colormap[color]

    if re.match("#[a-f0-9]{3}$", color):
        return "#" + "".join([x*2 for x in color[1:]])

    if re.match("#[a-f0-9]{6}$", color):
        return color

    raise ValueError(f"Invalid Color: '{color}'")


colormap = {
    # Taken from https://www.w3.org/TR/css-color-4/#named-color
    "aliceblue": "#f0f8ff",
    "antiquewhite": "#faebd7",
    "aqua": "#00ffff",
    "aquamarine": "#7fffd4",
    "azure": "#f0ffff",
    "beige": "#f5f5dc",
    "bisque": "#ffe4c4",
    "black": "#000000",
    "blanchedalmond": "#ffebcd",
    "blue": "#0000ff",
    "blueviolet": "#8a2be2",
    "brown": "#a52a2a",
    "burlywood": "#deb887",
    "cadetblue": "#5f9ea0",
    "chartreuse": "#7fff00",
    "chocolate": "#d2691e",
    "coral": "#ff7f50",
    "cornflowerblue": "#6495ed",
    "cornsilk": "#fff8dc",
    "crimson": "#dc143c",
    "cyan": "#00ffff",
    "darkblue": "#00008b",
    "darkcyan": "#008b8b",
    "darkgoldenrod": "#b8860b",
    "darkgray": "#a9a9a9",
    "darkgrey": "#a9a9a9",
    "darkgreen": "#006400",
    "darkkhaki": "#bdb76b",
    "darkmagenta": "#8b008b",
    "darkolivegreen": "#556b2f",
    "darkorange": "#ff8c00",
    "darkorchid": "#9932cc",
    "darkred": "#8b0000",
    "darksalmon": "#e9967a",
    "darkseagreen": "#8fbc8f",
    "darkslateblue": "#483d8b",
    "darkslategray": "#2f4f4f",
    "darkslategrey": "#2f4f4f",
    "darkturquoise": "#00ced1",
    "darkviolet": "#9400d3",
    "deeppink": "#ff1493",
    "deepskyblue": "#00bfff",
    "dimgray": "#696969",
    "dimgrey": "#696969",
    "dodgerblue": "#1e90ff",
    "firebrick": "#b22222",
    "floralwhite": "#fffaf0",
    "forestgreen": "#228b22",
    "fuchsia": "#ff00ff",
    "gainsboro": "#dcdcdc",
    "ghostwhite": "#f8f8ff",
    "gold": "#ffd700",
    "goldenrod": "#daa520",
    "gray": "#808080",
    "grey": "#808080",
    "green": "#008000",
    "greenyellow": "#adff2f",
    "honeydew": "#f0fff0",
    "hotpink": "#ff69b4",
    "indianred": "#cd5c5c",
    "indigo": "#4b0082",
    "ivory": "#fffff0",
    "khaki": "#f0e68c",
    "lavender": "#e6e6fa",
    "lavenderblush": "#fff0f5",
    "lawngreen": "#7cfc00",
    "lemonchiffon": "#fffacd",
    "lightblue": "#add8e6",
    "lightcoral": "#f08080",
    "lightcyan": "#e0ffff",
    "lightgoldenrodyellow": "#fafad2",
    "lightgreen": "#90ee90",
    "lightgray": "#d3d3d3",
    "lightgrey": "#d3d3d3",
    "lightpink": "#ffb6c1",
    "lightsalmon": "#ffa07a",
    "lightseagreen": "#20b2aa",
    "lightskyblue": "#87cefa",
    "lightslategray": "#778899",
    "lightslategrey": "#778899",
    "lightsteelblue": "#b0c4de",
    "lightyellow": "#ffffe0",
    "lime": "#00ff00",
    "limegreen": "#32cd32",
    "linen": "#faf0e6",
    "magenta": "#ff00ff",
    "maroon": "#800000",
    "mediumaquamarine": "#66cdaa",
    "mediumblue": "#0000cd",
    "mediumorchid": "#ba55d3",
    "mediumpurple": "#9370db",
    "mediumseagreen": "#3cb371",
    "mediumslateblue": "#7b68ee",
    "mediumspringgreen": "#00fa9a",
    "mediumturquoise": "#48d1cc",
    "mediumvioletred": "#c71585",
    "midnightblue": "#191970",
    "mintcream": "#f5fffa",
    "mistyrose": "#ffe4e1",
    "moccasin": "#ffe4b5",
    "navajowhite": "#ffdead",
    "navy": "#000080",
    "oldlace": "#fdf5e6",
    "olive": "#808000",
    "olivedrab": "#6b8e23",
    "orange": "#ffa500",
    "orangered": "#ff4500",
    "orchid": "#da70d6",
    "palegoldenrod": "#eee8aa",
    "palegreen": "#98fb98",
    "paleturquoise": "#afeeee",
    "palevioletred": "#db7093",
    "papayawhip": "#ffefd5",
    "peachpuff": "#ffdab9",
    "peru": "#cd853f",
    "pink": "#ffc0cb",
    "plum": "#dda0dd",
    "powderblue": "#b0e0e6",
    "purple": "#800080",
    "rebeccapurple": "#663399",
    "red": "#ff0000",
    "rosybrown": "#bc8f8f",
    "royalblue": "#4169e1",
    "saddlebrown": "#8b4513",
    "salmon": "#fa8072",
    "sandybrown": "#f4a460",
    "seagreen": "#2e8b57",
    "seashell": "#fff5ee",
    "sienna": "#a0522d",
    "silver": "#c0c0c0",
    "skyblue": "#87ceeb",
    "slateblue": "#6a5acd",
    "slategray": "#708090",
    "slategrey": "#708090",
    "snow": "#fffafa",
    "springgreen": "#00ff7f",
    "steelblue": "#4682b4",
    "tan": "#d2b48c",
    "teal": "#008080",
    "thistle": "#d8bfd8",
    "tomato": "#ff6347",
    "turquoise": "#40e0d0",
    "violet": "#ee82ee",
    "wheat": "#f5deb3",
    "white": "#ffffff",
    "whitesmoke": "#f5f5f5",
    "yellow": "#ffff00",
    "yellowgreen": "#9acd32",
}
