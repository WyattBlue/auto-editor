# type: ignore

from dataclasses import dataclass, asdict, fields

from typing import List, Tuple, Dict, Union

from auto_editor.utils.log import Log
from auto_editor.utils.types import (
    float_type,
    anchor_type,
    color_type,
    text_content,
    align_type,
)
from auto_editor.ffwrapper import FileInfo
from auto_editor.method import parse_dataclass


@dataclass
class Rectangle:
    start: int
    dur: int
    x: int
    y: int
    width: int
    height: int
    anchor: anchor_type = "ce"
    fill: color_type = "#c4c4c4"
    stroke: int = 0
    strokecolor: color_type = "#000"
    _type: str = "rectangle"


@dataclass
class Ellipse:
    start: int
    dur: int
    x: int
    y: int
    width: int
    height: int
    anchor: anchor_type = "ce"
    fill: color_type = "#c4c4c4"
    stroke: int = 0
    strokecolor: color_type = "#000"
    _type: str = "ellipse"


@dataclass
class Text:
    start: int
    dur: int
    content: text_content
    x: int = "centerX"
    y: int = "centerY"
    size: int = 30
    font: str = "default"
    align: align_type = "left"
    fill: color_type = "#000"
    stroke: int = 0
    strokecolor: color_type = "#000"
    _type: str = "text"


@dataclass
class Image:
    start: int
    dur: int
    src: str
    x: int = "centerX"
    y: int = "centerY"
    opacity: float_type = 1
    anchor: anchor_type = "ce"
    rotate: float = 0  # in degrees
    _type: str = "image"


class Sheet:
    __slots__ = ("all", "sheet")

    def __init__(
        self, args, inp: FileInfo, chunks: List[Tuple[int, int, float]], log: Log
    ) -> None:

        ending = chunks[:]
        if ending[-1][2] == 99999:
            ending.pop()

        end = 0
        if ending:
            end = ending[-1][1]

        _vars = {
            "width": inp.gwidth,
            "height": inp.gheight,
            "centerX": inp.gwidth // 2,
            "centerY": inp.gheight // 2,
            "start": 0,
            "end": end,
        }

        self.all = []
        self.sheet: Dict[int, List[int]] = {}

        def _values(val, _type, _vars: Dict[str, int]):
            if val is None:
                return None

            if _type is str:
                return str(val)  # Skip replacing variables with vals.

            for key, item in _vars.items():
                if val == key:
                    return _type(item)

            try:
                _type(val)
            except TypeError as e:
                log.error(str(e))
            except Exception:
                log.error(f"variable '{val}' is not defined.")

            return _type(val)

        pool = []

        for o in args.add_text:
            pool.append(parse_dataclass(o, Text, log))
        for o in args.add_rectangle:
            pool.append(parse_dataclass(o, Rectangle, log))
        for o in args.add_ellipse:
            pool.append(parse_dataclass(o, Ellipse, log))
        for o in args.add_image:
            pool.append(parse_dataclass(o, Image, log))

        for index, obj in enumerate(pool):

            dic_value = asdict(obj)
            dic_type = {}
            for field in fields(obj):
                dic_type[field.name] = field.type

            # Convert to the correct types
            for k, _type in dic_type.items():
                obj.__setattr__(k, _values(dic_value[k], _type, _vars))

            if obj.dur < 1:
                log.error(f"dur's value must be greater than 0. Was '{dur}'.")

            for frame in range(obj.start, obj.start + obj.dur, 1):
                if frame in self.sheet:
                    self.sheet[frame].append(index)
                else:
                    self.sheet[frame] = [index]

            self.all.append(obj)
