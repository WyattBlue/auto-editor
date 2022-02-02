import os.path
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
