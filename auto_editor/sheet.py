from dataclasses import dataclass, asdict, fields

from typing import List, Tuple, Dict, Union, Callable, Any

from auto_editor.utils.log import Log
from auto_editor.utils.types import (
    float_type,
    anchor_type,
    color_type,
    align_type,
    AlignType,
)
from auto_editor.utils.func import parse_dataclass
from auto_editor.ffwrapper import FileInfo


@dataclass
class RectangleObj:
    start: int
    dur: int
    x: int
    y: int
    width: int
    height: int
    anchor: str = "ce"
    fill: str = "#c4c4c4"
    stroke: int = 0
    strokecolor: str = "#000"


@dataclass
class EllipseObj:
    start: int
    dur: int
    x: int
    y: int
    width: int
    height: int
    anchor: str = "ce"
    fill: str = "#c4c4c4"
    stroke: int = 0
    strokecolor: str = "#000"


@dataclass
class TextObj:
    start: int
    dur: int
    content: str
    x: int = "centerX"  # type: ignore
    y: int = "centerY"  # type: ignore
    size: int = 30
    font: str = "default"
    align: AlignType = "left"
    fill: str = "#000"
    stroke: int = 0
    strokecolor: str = "#000"
    _cache_font: Any = None


@dataclass
class ImageObj:
    start: int
    dur: int
    src: str
    x: int = "centerX"  # type: ignore
    y: int = "centerY"  # type: ignore
    opacity: float = 1
    anchor: str = "ce"
    rotate: float = 0  # in degrees
    _cache_src: Any = None


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

        _vars: Dict[str, int] = {
            "width": inp.gwidth,
            "height": inp.gheight,
            "centerX": inp.gwidth // 2,
            "centerY": inp.gheight // 2,
            "start": 0,
            "end": end,
        }

        self.all = []
        self.sheet: Dict[int, List[int]] = {}

        def _values(
            name: str,
            val: Union[int, str, float],
            _type: Union[type, Callable[[Any], Any]],
            _vars: Dict[str, int],
        ):
            if _type is Any:
                return None
            if _type is float and name != "rotate":
                _type = float_type
            elif _type == AlignType:
                _type = align_type
            elif name == "anchor":
                _type = anchor_type
            elif name in ("fill", "strokecolor"):
                _type = color_type

            if _type is int:
                for key, item in _vars.items():
                    if val == key:
                        return item

            try:
                _type(val)
            except TypeError as e:
                log.error(str(e))
            except Exception:
                log.error(f"variable '{val}' is not defined.")

            return _type(val)

        pool = []

        for o in args.add_text:
            pool.append(parse_dataclass(o, TextObj, log))
        for o in args.add_rectangle:
            pool.append(parse_dataclass(o, RectangleObj, log))
        for o in args.add_ellipse:
            pool.append(parse_dataclass(o, EllipseObj, log))
        for o in args.add_image:
            pool.append(parse_dataclass(o, ImageObj, log))

        for index, obj in enumerate(pool):

            dic_value = asdict(obj)
            dic_type = {}
            for field in fields(obj):
                dic_type[field.name] = field.type

            # Convert to the correct types
            for k, _type in dic_type.items():
                obj.__setattr__(k, _values(k, dic_value[k], _type, _vars))

            if obj.dur < 1:
                log.error(f"dur's value must be greater than 0. Was '{obj.dur}'.")

            for frame in range(obj.start, obj.start + obj.dur, 1):
                if frame in self.sheet:
                    self.sheet[frame].append(index)
                else:
                    self.sheet[frame] = [index]

            self.all.append(obj)
