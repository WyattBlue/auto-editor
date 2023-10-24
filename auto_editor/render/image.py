from __future__ import annotations

import av
from PIL import Image, ImageChops, ImageDraw

from auto_editor.ffwrapper import FileInfo
from auto_editor.timeline import TlImage, TlRect, VSpace
from auto_editor.utils.log import Log

av.logging.set_level(av.logging.PANIC)


def apply_anchor(x: int, y: int, w: int, h: int, anchor: str) -> tuple[int, int]:
    if anchor == "ce":
        x = (x * 2 - w) // 2
        y = (y * 2 - h) // 2
    if anchor == "tr":
        x -= w
    if anchor == "bl":
        y -= h
    if anchor == "br":
        x -= w
        y -= h
    # Pillow uses 'tl' by default
    return x, y


ImgCache = dict[str, Image.Image]


def make_cache(vtl: VSpace, sources: dict[str, FileInfo], log: Log) -> ImgCache:
    img_cache: ImgCache = {}
    for layer in vtl:
        for obj in layer:
            if isinstance(obj, TlImage) and obj.src not in img_cache:
                img_cache[obj.src] = Image.open(f"{sources[obj.src].path}").convert(
                    "RGBA"
                )

    return img_cache


def render_image(
    frame: av.VideoFrame, obj: TlRect | TlImage, img_cache: ImgCache
) -> av.VideoFrame:
    img = frame.to_image().convert("RGBA")

    x = obj.x
    y = obj.y

    if isinstance(obj, TlRect):
        w = obj.width
        h = obj.height
        newimg = Image.new("RGBA", (w, h), (255, 255, 255, 0))
        draw = ImageDraw.Draw(newimg)
        draw.rectangle((0, 0, w, h), fill=obj.fill)
    if isinstance(obj, TlImage):
        newimg = img_cache[obj.src]
        draw = ImageDraw.Draw(newimg)
        newimg = ImageChops.multiply(
            newimg,
            Image.new("RGBA", newimg.size, (255, 255, 255, int(obj.opacity * 255))),
        )

    img.paste(
        newimg,
        apply_anchor(x, y, newimg.size[0], newimg.size[1], obj.anchor),
        newimg,
    )
    return frame.from_image(img)
