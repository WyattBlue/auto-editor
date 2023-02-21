from __future__ import annotations

from typing import Union

import av
from PIL import Image, ImageChops, ImageDraw, ImageFont, ImageOps

from auto_editor.ffwrapper import FileInfo
from auto_editor.timeline import TlEllipse, TlImage, TlRect, TlText, Visual, VSpace
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


FontCache = dict[tuple[str, int], Union[ImageFont.FreeTypeFont, ImageFont.ImageFont]]
ImgCache = dict[str, Image.Image]


def make_caches(
    vtl: VSpace, sources: dict[str, FileInfo], log: Log
) -> tuple[FontCache, ImgCache]:
    font_cache: FontCache = {}
    img_cache: ImgCache = {}
    for layer in vtl:
        for obj in layer:
            if isinstance(obj, TlText) and (obj.font, obj.size) not in font_cache:
                try:
                    if obj.font == "default":
                        font_cache[(obj.font, obj.size)] = ImageFont.load_default()
                    else:
                        font_cache[(obj.font, obj.size)] = ImageFont.truetype(
                            obj.font, obj.size
                        )
                except OSError:
                    log.error(f"Font '{obj.font}' not found.")

            if isinstance(obj, TlImage) and obj.src not in img_cache:
                img_cache[obj.src] = Image.open(f"{sources[obj.src].path}").convert(
                    "RGBA"
                )

    return font_cache, img_cache


def render_image(
    frame: av.VideoFrame, obj: Visual, font_cache: FontCache, img_cache: ImgCache
) -> av.VideoFrame:
    img = frame.to_image().convert("RGBA")

    def z(h: int, x: int | float) -> int:
        if isinstance(x, float):
            return round(h * x)
        return x

    x = z(frame.width, obj.x)
    y = z(frame.height, obj.y)

    if isinstance(obj, (TlRect, TlEllipse)):
        w = z(frame.width, obj.width)
        h = z(frame.height, obj.height)

    if isinstance(obj, TlEllipse):
        # Adding +1 to width makes Ellipse look better.
        obj_img = Image.new("RGBA", (w + 1, h), (255, 255, 255, 0))
    if isinstance(obj, TlRect):
        obj_img = Image.new("RGBA", (w, h), (255, 255, 255, 0))

    if isinstance(obj, TlImage):
        obj_img = img_cache[obj.src]
        if obj.stroke > 0:
            obj_img = ImageOps.expand(obj_img, border=obj.stroke, fill=obj.strokecolor)

    if isinstance(obj, TlText):
        obj_img = Image.new("RGBA", img.size)
        _draw = ImageDraw.Draw(obj_img)
        text_w, text_h = _draw.textsize(
            obj.content, font=font_cache[(obj.font, obj.size)], stroke_width=obj.stroke
        )
        obj_img = Image.new("RGBA", (text_w, text_h), (255, 255, 255, 0))

    draw = ImageDraw.Draw(obj_img)

    if isinstance(obj, TlText):
        draw.text(
            (0, 0),
            obj.content,
            font=font_cache[(obj.font, obj.size)],
            fill=obj.fill,
            align=obj.align,
            stroke_width=obj.stroke,
            stroke_fill=obj.strokecolor,
        )

    if isinstance(obj, TlRect):
        draw.rectangle(
            (0, 0, w, h),
            fill=obj.fill,
            width=obj.stroke,
            outline=obj.strokecolor,
        )

    if isinstance(obj, TlEllipse):
        draw.ellipse(
            (0, 0, w, h),
            fill=obj.fill,
            width=obj.stroke,
            outline=obj.strokecolor,
        )

    # Do Anti-Aliasing
    obj_img = obj_img.resize((obj_img.size[0] * 3, obj_img.size[1] * 3))
    obj_img = obj_img.resize(
        (obj_img.size[0] // 3, obj_img.size[1] // 3), resample=Image.BICUBIC
    )

    obj_img = obj_img.rotate(
        obj.rotate, expand=True, resample=Image.BICUBIC, fillcolor=(255, 255, 255, 0)
    )
    obj_img = ImageChops.multiply(
        obj_img,
        Image.new("RGBA", obj_img.size, (255, 255, 255, int(obj.opacity * 255))),
    )
    img.paste(
        obj_img,
        apply_anchor(x, y, obj_img.size[0], obj_img.size[1], obj.anchor),
        obj_img,
    )
    return frame.from_image(img)
