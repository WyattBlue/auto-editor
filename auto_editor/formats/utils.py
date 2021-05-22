'''utils.py'''

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
