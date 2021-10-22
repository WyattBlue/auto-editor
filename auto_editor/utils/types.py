'''utils/types.py'''

import os.path
import sys

from .func import clean_list

def error(message):
    # type: (str) -> None
    print('Error! {}'.format(message), file=sys.stderr)
    sys.exit(1)

def split_num_str(val, error_func):
    # type: (str, Any) -> tuple(2)
    index = 0
    for item in val:
        if(not item.isdigit() and item != ' ' and item != '.' and item != '-'):
            break
        index += 1
    num, unit = val[:index], val[index:]
    if('.' in num):
        try:
            float(num)
        except ValueError:
            error_func('{} is not a valid number')
        return float(num), unit
    if('-' in num):
        try:
            int(num)
        except ValueError:
            error_func('{} is not a valid number')
    return int(num), unit

def file_type(path):
    # type: (str) -> str
    if(not os.path.isfile(path)):
        error('Auto-Editor could not find the file: {}'.format(path))
    return path

def unit_check(unit, allowed_units):
    # type: (list, str) -> None
    if(unit not in allowed_units):
        error('Unsupported unit: {}'.format(unit))


def float_type(val):
    # type: (str) -> float
    num, unit = split_num_str(val, error)
    unit_check(unit, ['%', ''])
    if(unit == '%'):
        return float(num / 100)
    return float(num)

def sample_rate_type(val):
    # type: (str) -> int
    num, unit = split_num_str(val, error)
    unit_check(unit, ['Hz', 'kHz', ''])
    if(unit == 'kHz'):
        return int(num * 1000)
    return int(num)

def frame_units():
    return ['f', 'frame', 'frames']

def second_units():
    return ['s', 'sec', 'secs', 'second', 'seconds']

def frame_type(val):
    # type: (str) -> int | str
    num, unit = split_num_str(val, error)
    unit_check(unit, [''] + frame_units() + second_units())

    if(unit in second_units()):
        return str(num).strip()
    return int(num)

def comma_type(inp, min_args=1, max_args=None, name=''):
    inp = clean_list(inp.split(','), '\r\n\t')
    if(min_args > len(inp)):
        error('Too few comma arguments for {}.'.format(name))
    if(max_args is not None and len(inp) > max_args):
        error('Too many comma arguments for {}.'.format(name))
    return inp

def range_type(inp):
    return comma_type(inp, 2, 2, 'range_type')

def speed_range_type(inp):
    return comma_type(inp, 3, 3, 'speed_range_type')

def block_type(inp):
    return comma_type(inp, 1, None, 'block_type')
