"""
Make a pre-edited file reference that can be inputted back into auto-editor.
"""

import os
import sys
import json

from auto_editor.utils.log import Log

def check_attrs(data, log: Log, *attrs: str):
    for attr in attrs:
        if attr not in data:
            log.error(f"'{attr}' attribute not found!")

def check_file(path: str, log: Log):
    if not os.path.isfile(path):
        log.error(f"Could not locate media file: '{path}'")

def read_json_timeline(json_file: str, log: Log):
    with open(json_file, 'r') as f:
        data = json.load(f)

    check_attrs(data, log, 'version')

    if data['version'] not in ('0.1.0', '0.2.0'):
        log.error(f'Unsupported version: {version}')

    if data['version'] == '0.1.0':
        check_attrs(data, log, 'source', 'chunks')
        check_file(data['source'], log)

        return '#000', data['source'], data['chunks']

    # version 0.2.0
    check_attrs(data, log, 'source', 'background', 'chunks', 'timeline')
    check_file(data['source'], log)

    return data['background'], data['source'], data['chunks']


def make_json_timeline(version, media_file, out, obj_sheet, chunks, fps, background, log):

    if version not in ('0.1.0', '0.2.0'):
        log.error(f'Version {version} is not supported!')

    if version == '0.1.0':
        data = {
            'version': '0.1.0',
            'source': os.path.abspath(media_file)
            'chunks': chunks,
        }
    if version == '0.2.0':
        data = {
            'version': '0.2.0',
            'source': os.path.abspath(media_file),
            'background': background,
            'chunks': chunks,
            'timeline': obj_sheet.all,
        }

    if isinstance(out, str):
        if not out.endswith('.json'):
            log.error('Output extension must be .json')

        with open(out, 'w') as outfile:
            json.dump(data, outfile, indent=2, default=lambda o: o.__dict__)
    else:
        json.dump(data, sys.stdout, indent=2, default=lambda o: o.__dict__)
        print('')  # Flush stdout
