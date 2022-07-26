from __future__ import annotations

import os.path
from dataclasses import dataclass
from math import ceil
from subprocess import DEVNULL, PIPE
from typing import Dict, Tuple, Union

import av
from PIL import Image, ImageChops, ImageDraw, ImageFont, ImageOps

from auto_editor.ffwrapper import FFmpeg
from auto_editor.make_layers import Visual
from auto_editor.objects import EllipseObj, ImageObj, RectangleObj, TextObj, VideoObj
from auto_editor.output import video_quality
from auto_editor.timeline import Timeline
from auto_editor.utils.bar import Bar
from auto_editor.utils.container import Container
from auto_editor.utils.encoder import encoders
from auto_editor.utils.log import Log
from auto_editor.utils.types import Args

av.logging.set_level(av.logging.PANIC)


@dataclass
class VideoFrame:
    index: int
    src: int


# From: github.com/PyAV-Org/PyAV/blob/main/av/video/frame.pyx
allowed_pix_fmt = {
    "yuv420p",
    "yuvj420p",
    "rgb48be",
    "rgb48le",
    "rgb64be",
    "rgb64le",
    "rgb24",
    "bgr24",
    "argb",
    "rgba",
    "abgr",
    "bgra",
    "gray",
    "gray8",
    "gray16be",
    "gray16le",
    "rgb8",
    "bgr8",
    "pal8",
}


def apply_anchor(
    x: int, y: int, width: int, height: int, anchor: str
) -> tuple[int, int]:
    if anchor == "ce":
        x = int((x * 2 - width) / 2)
        y = int((y * 2 - height) / 2)
    if anchor == "tr":
        x -= width
    if anchor == "bl":
        y -= height
    if anchor == "br":
        x -= width
        y -= height
    # Pillow uses 'tl' by default
    return x, y


def one_pos_two_pos(
    x: int, y: int, width: int, height: int, anchor: str
) -> tuple[int, int, int, int]:
    """Convert: x, y, width, height -> x1, y1, x2, y2"""

    if anchor == "ce":
        x1 = x - int(width / 2)
        x2 = x + int(width / 2)
        y1 = y - int(height / 2)
        y2 = y + int(height / 2)

        return x1, y1, x2, y2

    if anchor in ("tr", "br"):
        x1 = x - width
        x2 = x
    else:
        x1 = x
        x2 = x + width

    if anchor in ("tl", "tr"):
        y1 = y
        y2 = y + height
    else:
        y1 = y
        y2 = y - height

    return x1, y1, x2, y2


def render_av(
    ffmpeg: FFmpeg,
    timeline: Timeline,
    args: Args,
    bar: Bar,
    ctr: Container,
    temp: str,
    log: Log,
) -> tuple[str, bool]:

    FontCache = Dict[
        str, Tuple[Union[ImageFont.FreeTypeFont, ImageFont.ImageFont], float]
    ]

    font_cache: FontCache = {}
    img_cache: dict[str, Image.Image] = {}
    for layer in timeline.v:
        for vobj in layer:
            if isinstance(vobj, TextObj) and (vobj.font, vobj.size) not in font_cache:
                try:
                    if vobj.font == "default":
                        font_cache[(vobj.font, vobj.size)] = ImageFont.load_default()
                    else:
                        font_cache[(vobj.font, vobj.size)] = ImageFont.truetype(
                            vobj.font, vobj.size
                        )
                except OSError:
                    log.error(f"Font '{vobj.font}' not found.")

            if isinstance(vobj, ImageObj) and vobj.src not in img_cache:
                source = Image.open(vobj.src)
                source = source.convert("RGBA")
                source = source.rotate(vobj.rotate, expand=True)
                source = ImageChops.multiply(
                    source,
                    Image.new(
                        "RGBA", source.size, (255, 255, 255, int(vobj.opacity * 255))
                    ),
                )
                img_cache[vobj.src] = source

    inp = timeline.inp
    cns = [av.open(inp.path, "r") for inp in timeline.inputs]

    target_pix_fmt = "yuv420p"  # Reasonable default
    decoders = []
    tous = []
    seek_cost = []
    for c, cn in enumerate(cns):
        if len(cn.streams.video) == 0:
            decoders.append(None)
            tous.append(0)
            seek_cost.append(0)
        else:
            stream = cn.streams.video[0]
            stream.thread_type = "AUTO"

            if args.no_seek or stream.average_rate is None:
                sc_val = 4294967295  # 2 ** 32 - 1
                tou = 0
            else:
                # Keyframes are usually spread out every 5 seconds or less.
                sc_val = int(stream.average_rate * 5)
                tou = int(stream.time_base.denominator / stream.average_rate)

            seek_cost.append(sc_val)
            tous.append(tou)
            decoders.append(cn.decode(stream))

            if c == 0:
                target_pix_fmt = stream.pix_fmt

    log.debug(f"Tous: {tous}")
    log.debug(f"Clips: {timeline.v}")

    target_pix_fmt = target_pix_fmt if target_pix_fmt in allowed_pix_fmt else "yuv420p"
    log.debug(f"Target pix_fmt: {target_pix_fmt}")

    apply_video_later = True

    if args.video_codec in encoders:
        apply_video_later = encoders[args.video_codec]["pix_fmt"].isdisjoint(
            allowed_pix_fmt
        )

    if args.scale != 1:
        apply_video_later = False

    log.debug(f"apply video quality settings now: {not apply_video_later}")

    width, height = timeline.res
    spedup = os.path.join(temp, "spedup0.mp4")

    cmd = [
        "-hide_banner",
        "-y",
        "-f",
        "rawvideo",
        "-c:v",
        "rawvideo",
        "-pix_fmt",
        target_pix_fmt,
        "-s",
        f"{width}*{height}",
        "-framerate",
        f"{timeline.timebase}",
        "-i",
        "-",
        "-pix_fmt",
        target_pix_fmt,
    ]

    if apply_video_later:
        cmd.extend(["-c:v", "mpeg4", "-qscale:v", "1"])
    else:
        cmd = video_quality(cmd, args, inp, ctr)

    # Setting SAR requires re-encoding so we do it here.
    if timeline.inputs and timeline.inputs[0].videos:
        if (sar := timeline.inputs[0].videos[0].sar) is not None:
            cmd.extend(["-vf", f"setsar={sar.replace(':', '/')}"])

    cmd.append(spedup)

    process2 = ffmpeg.Popen(cmd, stdin=PIPE, stdout=DEVNULL, stderr=DEVNULL)
    assert process2.stdin is not None

    # First few frames can have an abnormal keyframe count, so never seek there.
    seek = 10

    seek_frame = None
    frames_saved = 0

    bar.start(timeline.end, "Creating new video")

    null_img = Image.new("RGB", (width, height), args.background)
    null_frame = av.VideoFrame.from_image(null_img).reformat(format=target_pix_fmt)

    frame_index = -1
    try:
        for index in range(timeline.end):
            # Add objects to obj_list
            obj_list: list[VideoFrame | Visual] = []
            for layer in timeline.v:
                for lobj in layer:
                    if isinstance(lobj, VideoObj):
                        if index >= lobj.start and index < lobj.start + ceil(
                            lobj.dur / lobj.speed
                        ):
                            obj_list.append(
                                VideoFrame(
                                    lobj.offset
                                    + round((index - lobj.start) * lobj.speed),
                                    lobj.src,
                                )
                            )
                    elif index >= lobj.start and index < lobj.start + lobj.dur:
                        obj_list.append(lobj)

            # Render obj_list
            frame = null_frame
            for obj in obj_list:
                if isinstance(obj, VideoFrame):
                    my_stream = cns[obj.src].streams.video[0]
                    if frame_index > obj.index:
                        log.debug(f"Seek: {frame_index} -> 0")
                        cns[obj.src].seek(0)
                        try:
                            frame = next(decoders[obj.src])
                            frame_index = round(frame.time * timeline.timebase)
                        except StopIteration:
                            pass

                    while frame_index < obj.index:
                        # Check if skipping ahead is worth it.
                        if (
                            obj.index - frame_index > seek_cost[obj.src]
                            and frame_index > seek
                        ):
                            seek = frame_index + (seek_cost[obj.src] // 2)
                            seek_frame = frame_index
                            log.debug(f"Seek: {frame_index} -> {obj.index}")
                            cns[obj.src].seek(
                                obj.index * tous[obj.src],
                                stream=my_stream,
                            )

                        try:
                            frame = next(decoders[obj.src])
                            frame_index = round(frame.time * timeline.timebase)
                        except StopIteration:
                            log.debug(f"No source frame at {index=}. Using null frame")
                            frame = null_frame
                            break

                        if seek_frame is not None:
                            log.debug(
                                f"Skipped {frame_index - seek_frame} frame indexes"
                            )
                            frames_saved += frame_index - seek_frame
                            seek_frame = None
                        if frame.key_frame:
                            log.debug(f"Keyframe {frame_index} {frame.pts}")

                    if frame.width != width or frame.height != height:
                        img = frame.to_image().convert("RGB")
                        if img.width > width or img.height > height:
                            factor = ceil(max(width / img.width, height / img.height))
                            img = ImageOps.scale(img, factor)
                        img = ImageOps.pad(img, (width, height), color=args.background)
                        frame = frame.from_image(img).reformat(format=target_pix_fmt)

                # Render visual objects
                else:
                    img = frame.to_image().convert("RGBA")
                    obj_img = Image.new("RGBA", img.size, (255, 255, 255, 0))
                    draw = ImageDraw.Draw(obj_img)

                    if isinstance(obj, TextObj):
                        text_w, text_h = draw.textsize(
                            obj.content, font=font_cache[(obj.font, obj.size)]
                        )
                        pos = apply_anchor(obj.x, obj.y, text_w, text_h, "ce")
                        draw.text(
                            pos,
                            obj.content,
                            font=font_cache[(obj.font, obj.size)],
                            fill=obj.fill,
                            align=obj.align,
                            stroke_width=obj.stroke,
                            stroke_fill=obj.strokecolor,
                        )

                    if isinstance(obj, RectangleObj):
                        draw.rectangle(
                            one_pos_two_pos(
                                obj.x, obj.y, obj.width, obj.height, obj.anchor
                            ),
                            fill=obj.fill,
                            width=obj.stroke,
                            outline=obj.strokecolor,
                        )

                    if isinstance(obj, EllipseObj):
                        draw.ellipse(
                            one_pos_two_pos(
                                obj.x, obj.y, obj.width, obj.height, obj.anchor
                            ),
                            fill=obj.fill,
                            width=obj.stroke,
                            outline=obj.strokecolor,
                        )

                    if isinstance(obj, ImageObj):
                        img_w, img_h = img_cache[obj.src].size
                        pos = apply_anchor(obj.x, obj.y, img_w, img_h, obj.anchor)
                        obj_img.paste(img_cache[obj.src], pos)

                    img = Image.alpha_composite(img, obj_img)
                    frame = frame.from_image(img).reformat(format=target_pix_fmt)

            if frame.format.name != target_pix_fmt:
                frame = frame.reformat(format=target_pix_fmt)
            process2.stdin.write(frame.to_ndarray().tobytes())

            if index % 3 == 0:
                bar.tick(index)

        bar.end()
        process2.stdin.close()
        process2.wait()
    except (OSError, BrokenPipeError):
        bar.end()
        ffmpeg.run_check_errors(cmd, log, True)
        log.error("FFmpeg Error!")

    log.debug(f"Total frames saved seeking: {frames_saved}")

    if args.scale != 1:
        sped_input = os.path.join(temp, "spedup0.mp4")
        spedup = os.path.join(temp, "scale0.mp4")
        scale_filter = f"scale=iw*{args.scale}:ih*{args.scale}"

        cmd = ["-i", sped_input, "-vf", scale_filter, spedup]

        check_errors = ffmpeg.pipe(cmd)
        if "Error" in check_errors or "failed" in check_errors:
            if "-allow_sw 1" in check_errors:
                cmd.insert(-1, "-allow_sw")
                cmd.insert(-1, "1")
            # Run again to show errors even if it might not work.
            ffmpeg.run(cmd)

    return spedup, apply_video_later
