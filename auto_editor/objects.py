from dataclasses import dataclass

from auto_editor.utils.types import float_type, anchor_type

@dataclass
class TimelineObject:
    start: int
    dur: int

@dataclass
class _Basic(TimelineObject):
    x1: int
    y1: int
    x2: int
    y2: int
    fill: str = '#000'
    width: int = 0
    outline: str = 'blue'

@dataclass
class RectangleObject(_Basic):
    _type: str = 'rectangle'

@dataclass
class EllipseObject(_Basic):
    _type: str = 'ellipse'

@dataclass
class TextObject(TimelineObject):
    content: str
    x: int = 'centerX'
    y: int = 'centerY'
    size: int = 30
    font: str = 'default'
    align: str = 'left'
    fill: str = '#FFF'
    _type: str = 'text'

@dataclass
class ImageObject(TimelineObject):
    src: str
    x: int = 'centerX'
    y: int = 'centerY'
    opacity: float_type = 1
    anchor: anchor_type = 'ce'
    _type: str = 'image'
