from dataclasses import dataclass

from auto_editor.utils.types import Align

# start - When the clip starts in the timeline
# dur - The duration of the clip in the timeline before speed is applied
# offset - When from the source to start playing the media at


@dataclass
class VideoObj:
    start: int
    dur: int
    offset: int
    speed: float
    src: int
    stream: int = 0


@dataclass
class AudioObj:
    start: int
    dur: int
    offset: int
    speed: float
    src: int
    stream: int = 0


@dataclass
class TextObj:
    start: int
    dur: int
    content: str
    x: int = "centerX"  # type: ignore
    y: int = "centerY"  # type: ignore
    size: int = 55
    font: str = "Arial"
    align: Align = "left"
    fill: str = "#FFF"
    stroke: int = 0
    strokecolor: str = "#000"


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
