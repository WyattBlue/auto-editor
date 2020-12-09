'''makeCutList'''

"""
Make a pre-edited file reference that can be inputted back into auto-editor.
"""

# Internal libraries
import os
import json

def readCutList(jsonFile, version, log) -> list:
    with open(jsonFile, 'r') as f:
        data = json.load(f)

    if(data['presets']['version'] != version):
        log.warning('This json file was generated using a different version of auto-editor.')

    INPUT_FILE = data['timeline']['media_file']

    if(not os.path.isfile(INPUT_FILE)):
        log.error('Could not locate file: ' + INPUT_FILE)

    speeds = data['presets']['speeds']

    chunks = data['timeline']['chunks']

    return INPUT_FILE, chunks, speeds


def makeCutList(vidFile, out, version, chunks, speeds, log):

    if(not out.endswith('.json')):
        log.error('Output extension must be .json')

    data = {}
    data['presets'] = {
        'version': version,
        'speeds': speeds,
    }
    data['timeline']= {
        'media_file': os.path.abspath(vidFile),
        'chunks': chunks,
    }

    with open(out, 'w') as outfile:
        json.dump(data, outfile, indent=4)
