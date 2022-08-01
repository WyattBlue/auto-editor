# Image helper functions

from __future__ import annotations

from typing import Dict, Tuple, Union

import av
from PIL import Image, ImageChops, ImageDraw, ImageFont

from auto_editor.make_layers import Visual, VSpace
from auto_editor.objects import EllipseObj, ImageObj, RectangleObj, TextObj
from auto_editor.utils.log import Log

av.logging.set_level(av.logging.PANIC)


def apply_anchor(x: int, y: int, w: int, h: int, anchor: str) -> tuple[int, int]:
    if anchor == "ce":
        x = int((x * 2 - w) / 2)
        y = int((y * 2 - h) / 2)
    if anchor == "tr":
        x -= w
    if anchor == "bl":
        y -= h
    if anchor == "br":
        x -= w
        y -= h
    # Pillow uses 'tl' by default
    return x, y


def one_pos_two_pos(
    x: int, y: int, w: int, h: int, anchor: str
) -> tuple[int, int, int, int]:
    # Convert: x, y, width, height -> x1, y1, x2, y2
    if anchor == "ce":
        x1 = x - int(w / 2)
        x2 = x + int(w / 2)
        y1 = y - int(h / 2)
        y2 = y + int(h / 2)

        return x1, y1, x2, y2

    if anchor in ("tr", "br"):
        x1 = x - w
        x2 = x
    else:
        x1 = x
        x2 = x + w

    if anchor in ("tl", "tr"):
        y1 = y
        y2 = y + h
    else:
        y1 = y
        y2 = y - h

    return x1, y1, x2, y2


FontCache = Dict[str, Tuple[Union[ImageFont.FreeTypeFont, ImageFont.ImageFont], float]]
ImgCache = Dict[str, Image.Image]


def make_caches(vtl: VSpace, log: Log) -> tuple[FontCache, ImgCache]:
    font_cache: FontCache = {}
    img_cache: ImgCache = {}
    for layer in vtl:
        for obj in layer:
            if isinstance(obj, TextObj) and (obj.font, obj.size) not in font_cache:
                try:
                    if obj.font == "default":
                        font_cache[(obj.font, obj.size)] = ImageFont.load_default()
                    else:
                        font_cache[(obj.font, obj.size)] = ImageFont.truetype(
                            obj.font, obj.size
                        )
                except OSError:
                    log.error(f"Font '{obj.font}' not found.")

            if isinstance(obj, ImageObj) and obj.src not in img_cache:
                img_cache[obj.src] = Image.open(obj.src).convert("RGBA")

    return font_cache, img_cache


def render_image(
    frame: av.VideoFrame, obj: Visual, font_cache: FontCache, img_cache: ImgCache
) -> av.VideoFrame:
    img = frame.to_image().convert("RGBA")

    if isinstance(obj, ImageObj):
        obj_img = img_cache[obj.src]
    if isinstance(obj, TextObj):
        obj_img = Image.new("RGBA", img.size)
        _draw = ImageDraw.Draw(obj_img)
        text_w, text_h = _draw.textsize(
            obj.content, font=font_cache[(obj.font, obj.size)], stroke_width=obj.stroke
        )
        obj_img = Image.new("RGBA", (text_w, text_h), (255, 255, 255, 0))
    if isinstance(obj, (RectangleObj, EllipseObj)):
        obj_img = Image.new("RGBA", (obj.width + 1, obj.height), (255, 255, 255, 0))

    draw = ImageDraw.Draw(obj_img)

    if isinstance(obj, TextObj):
        draw.text(
            (0, 0),
            obj.content,
            font=font_cache[(obj.font, obj.size)],
            fill=obj.fill,
            align=obj.align,
            stroke_width=obj.stroke,
            stroke_fill=obj.strokecolor,
        )

    if isinstance(obj, RectangleObj):
        draw.rectangle(
            (0, 0, obj.width, obj.height),
            fill=obj.fill,
            width=obj.stroke,
            outline=obj.strokecolor,
        )

    if isinstance(obj, EllipseObj):
        draw.ellipse(
            (0, 0, obj.width, obj.height),
            fill=obj.fill,
            width=obj.stroke,
            outline=obj.strokecolor,
        )

    # Do Anti-Aliasing
    obj_img = obj_img.resize([s * 3 for s in obj_img.size])
    obj_img = obj_img.resize([s // 3 for s in obj_img.size], resample=Image.BICUBIC)

    obj_img = obj_img.rotate(
        obj.rotate, expand=True, resample=Image.BICUBIC, fillcolor=(255, 255, 255, 0)
    )
    obj_img = ImageChops.multiply(
        obj_img,
        Image.new("RGBA", obj_img.size, (255, 255, 255, int(obj.opacity * 255))),
    )
    img.paste(
        obj_img,
        apply_anchor(obj.x, obj.y, obj_img.size[0], obj_img.size[1], obj.anchor),
        obj_img,
    )
    return frame.from_image(img)
