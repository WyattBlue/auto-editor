'''utils/types.py'''

from __future__ import print_function

import os.path
import sys

from .func import clean_list

def error(message):
    print('Error! {}'.format(message), file=sys.stderr)
    sys.exit(1)

def file_type(path):
    if(not os.path.isfile(path)):
        error('Auto-Editor could not find the file: {}'.format(path))
    return path

def float_type(num):
    if(num.endswith('%')):
        return float(num[:-1]) / 100
    return float(num)

def sample_rate_type(num):
    if(num.endswith(' Hz')):
        return int(num[:-3])
    if(num.endswith(' kHz')):
        return int(float(num[:-4]) * 1000)
    if(num.endswith('kHz')):
        return int(float(num[:-3]) * 1000)
    if(num.endswith('Hz')):
        return int(num[:-2])
    return int(num)

def frame_type(num):
    # (num: str) -> int | str:
    if(num.endswith('f')):
        return int(num[:-1])
    if(num.endswith('sec')):
        return num[:-3]
    if(num.endswith('secs')):
        return num[:-4]
    if(num.endswith('s')):
        return num[:-1]
    return int(num)

def comma_type(inp, min_args=1, max_args=None, name=''):
    inp = clean_list(inp.split(','), '\r\n\t')
    if(min_args > len(inp)):
        error('Too few comma arguments for {}.'.format(name))
    if(max_args is not None and len(inp) > max_args):
        error('Too many comma arguments for {}.'.format(name))
    return inp

def zoom_type(inp):
    return comma_type(inp, 3, 8, 'zoom_type')

def rect_type(inp):
    return comma_type(inp, 6, 8, 'rect_type')

def range_type(inp):
    return comma_type(inp, 2, 2, 'range_type')

def speed_range_type(inp):
    return comma_type(inp, 3, 3, 'speed_range_type')
