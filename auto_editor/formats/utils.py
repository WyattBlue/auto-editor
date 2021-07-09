'''formats/utils.py'''

def safe_mkdir(path):
    from shutil import rmtree
    from os import mkdir
    try:
        mkdir(path)
    except OSError:
        rmtree(path)
        mkdir(path)
    return path

def get_width_height(inp):
    if(len(inp.video_streams) == 0):
        return None, None
    else:
        return inp.video_streams[0]['width'], inp.video_streams[0]['height']

def indent(base, *args):
    # type: (int, str) -> str
    r = ''
    for line in args:
        r += ('\t' * base) + line + '\n'
    return r
