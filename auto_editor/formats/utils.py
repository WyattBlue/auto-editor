'''utils.py'''

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
        return '1280', '720'
    else:
        return inp.video_streams[0]['width'], inp.video_streams[0]['height']

def indent(base: int, *args: str) -> str:
    r = ''
    for line in args:
        r += ('\t' * base) + line + '\n'
    return r

def fix_url(path: str, resolve: bool) -> str:
    from urllib.parse import quote
    from platform import system
    from os.path import abspath

    if(system() == 'Windows'):
        if(resolve):
            return 'file:///' + quote(abspath(path)).replace('%5C', '/')
        return'file://localhost/' + quote(abspath(path)).replace('%5C', '/')
    return 'file://localhost' + abspath(path)
