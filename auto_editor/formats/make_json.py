'''formats/json_cutlist.py'''

"""
Make a pre-edited file reference that can be inputted back into auto-editor.
"""

import os
import json

def read_json_cutlist(json_file, version, log):
    with open(json_file, 'r') as f:
        data = json.load(f)

    if(data['presets']['version'] != version):
        log.warning('This json file was generated using a different '
            'version of auto-editor.')

    media_file = data['timeline']['media_file']

    if(not os.path.isfile(media_file)):
        log.error('Could not locate media file: {}'.format(media_file))

    speeds = data['presets']['speeds']
    chunks = data['timeline']['chunks']

    return media_file, chunks, speeds


def make_json_cutlist(media_file, out, version, chunks, speeds, log):
    if(not out.endswith('.json')):
        log.error('Output extension must be .json')

    data = {}
    data['presets'] = {
        'version': version,
        'speeds': speeds,
    }
    data['timeline']= {
        'media_file': os.path.abspath(media_file),
        'chunks': chunks,
    }

    with open(out, 'w') as outfile:
        json.dump(data, outfile, indent=4)
