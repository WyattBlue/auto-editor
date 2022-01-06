'''formats/json_cutlist.py'''

"""
Make a pre-edited file reference that can be inputted back into auto-editor.
"""

import os
import sys
import json

from typing import Tuple, List
from auto_editor.utils.log import Log

def read_json_cutlist(json_file, log):
    # type: (str, Log) -> Tuple[str, List[Tuple[int, int, float]]]
    with open(json_file, 'r') as f:
        data = json.load(f)

    source = data['timeline']['source']

    if(not os.path.isfile(source)):
        log.error(f"Could not locate media file: '{source}'")

    chunks = data['timeline']['chunks']

    return source, chunks


def make_json_cutlist(media_file, out, chunks, log):
    # type: (str, str | int, List[Tuple[int, int, float]], Log) -> None
    data = {
        'version': '0.1.0',
        'timeline': {
            'source': os.path.abspath(media_file),
            'chunks': chunks,
        },
    }

    if(isinstance(out, str)):
        if(not out.endswith('.json')):
            log.error('Output extension must be .json')

        with open(out, 'w') as outfile:
            json.dump(data, outfile, indent=2)
    else:
        json.dump(data, sys.stdout, indent=2)

