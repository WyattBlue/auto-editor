"""
Make a pre-edited file reference that can be inputted back into auto-editor.
"""

import os
import sys
import json

from typing import Tuple, List
from auto_editor.utils.log import Log

def read_json_timeline(json_file, log):
    # type: (str, Log) -> Tuple[str, str, List[Tuple[int, int, float]]]
    with open(json_file, 'r') as f:
        data = json.load(f)

    source = data['source']
    if(not os.path.isfile(source)):
        log.error(f"Could not locate media file: '{source}'")

    background = data['background']

    return background, source, data['chunks']


def make_json_timeline(media_file, out, obj_sheet, chunks, fps, background, log):
    # type: (str, str | int, List[Tuple[int, int, float]], Log) -> None
    data = {
        'version': '0.2.0',
        'source': os.path.abspath(media_file),
        'background': background,
        'chunks': chunks,
        'timeline': obj_sheet.all,
    }

    if(isinstance(out, str)):
        if(not out.endswith('.json')):
            log.error('Output extension must be .json')

        with open(out, 'w') as outfile:
            json.dump(data, outfile, indent=2, default=lambda o: o.__dict__)
    else:
        json.dump(data, sys.stdout, indent=2, default=lambda o: o.__dict__)

