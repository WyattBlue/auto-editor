def safe_mkdir(path: str) -> str:
    from os import mkdir
    from shutil import rmtree

    try:
        mkdir(path)
    except OSError:
        rmtree(path)
        mkdir(path)
    return path


def indent(base: int, *lines: str) -> str:
    new_lines = ""
    for line in lines:
        new_lines += ("\t" * base) + line + "\n"
    return new_lines
