from dataclasses import dataclass

from auto_editor.utils.types import (
    float_type, anchor_type, color_type, text_content, align_type
)

@dataclass
class TimelineObject:
    start: int
    dur: int

@dataclass
class RectangleObject(TimelineObject):
    x: int
    y: int
    width: int
    height: int
    anchor: anchor_type = 'ce'
    fill: color_type = '#c4c4c4'
    stroke: int = 0
    strokecolor: color_type = '#000'
    _type: str = 'rectangle'

@dataclass
class EllipseObject(TimelineObject):
    x: int
    y: int
    width: int
    height: int
    anchor: anchor_type = 'ce'
    fill: color_type = '#c4c4c4'
    stroke: int = 0
    strokecolor: color_type = '#000'
    _type: str = 'ellipse'

@dataclass
class TextObject(TimelineObject):
    content: text_content
    x: int = 'centerX'
    y: int = 'centerY'
    size: int = 30
    font: str = 'default'
    align: align_type = 'left'
    fill: color_type = '#000'
    stroke: int = 0
    strokecolor: color_type = '#000'
    _type: str = 'text'

@dataclass
class ImageObject(TimelineObject):
    src: str
    x: int = 'centerX'
    y: int = 'centerY'
    opacity: float_type = 1
    anchor: anchor_type = 'ce'
    rotate: float = 0 # in degrees
    _type: str = 'image'
