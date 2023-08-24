from __future__ import annotations

from typing import TYPE_CHECKING
from xml.etree.ElementTree import Element

if TYPE_CHECKING:
    from pathlib import Path

    from auto_editor.ffwrapper import FileInfo
    from auto_editor.utils.log import Log


def show(ele: Element, limit: int, depth: int = 0) -> None:
    print(
        f"{' ' * (depth * 4)}<{ele.tag} {ele.attrib}> {ele.text.strip() if ele.text is not None else ''}"
    )
    for child in ele:
        if isinstance(child, Element) and depth < limit:
            show(child, limit, depth + 1)


def make_tracks_dir(src: FileInfo) -> Path:
    from os import mkdir
    from shutil import rmtree

    fold = src.path.parent / f"{src.path.stem}_tracks"

    try:
        mkdir(fold)
    except OSError:
        rmtree(fold)
        mkdir(fold)

    return fold


class Validator:
    def __init__(self, log: Log):
        self.log = log

    def parse(self, ele: Element, schema: dict) -> dict:
        new: dict = {}

        for key, val in schema.items():
            if isinstance(val, dict) and "__arr" in val:
                new[key] = []

        is_arr = False
        for child in ele:
            if child.tag not in schema:
                continue

            if schema[child.tag] is None:
                new[child.tag] = child
                continue

            if isinstance(schema[child.tag], dict):
                val = self.parse(child, schema[child.tag])
                is_arr = "__arr" in schema[child.tag]
            else:
                val = schema[child.tag](child.text)

            if child.tag in new:
                if not is_arr:
                    self.log.error(f"<{child.tag}> can only occur once")
                new[child.tag].append(val)
            else:
                new[child.tag] = [val] if is_arr else val

        return new

    def check(self, ele: Element, tag: str) -> None:
        if tag != ele.tag:
            self.log.error(f"Expected '{tag}' tag, got '{ele.tag}'")
