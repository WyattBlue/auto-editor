import os.path
import subprocess
from dataclasses import dataclass
from math import ceil
from typing import Dict, List, Tuple, Union

import av
from PIL import Image, ImageChops, ImageDraw, ImageFont, ImageOps

from auto_editor.ffwrapper import FFmpeg
from auto_editor.objects import EllipseObj, ImageObj, RectangleObj, TextObj, VideoObj
from auto_editor.output import get_vcodec, video_quality
from auto_editor.timeline import Timeline, Visual
from auto_editor.utils.container import Container
from auto_editor.utils.encoder import encoders
from auto_editor.utils.log import Log
from auto_editor.utils.progressbar import ProgressBar
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
) -> Tuple[int, int]:
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
) -> Tuple[int, int, int, int]:
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
    progress: ProgressBar,
    ctr: Container,
    temp: str,
    log: Log,
) -> Tuple[str, bool]:

    FontCache = Dict[
        str, Tuple[Union[ImageFont.FreeTypeFont, ImageFont.ImageFont], float]
    ]

    font_cache: FontCache = {}
    img_cache: Dict[str, Image.Image] = {}
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

    decoders = []
    tous = []
    pix_fmts = []
    for cn in cns:
        stream = cn.streams.video[0]
        stream.thread_type = "AUTO"

        tous.append(int(stream.time_base.denominator / stream.average_rate))
        pix_fmts.append(stream.pix_fmt)
        decoders.append(cn.decode(stream))

    log.debug(f"Tous: {tous}")
    log.debug(f"Clips: {timeline.v}")

    target_pix_fmt = pix_fmts[0] if pix_fmts[0] in allowed_pix_fmt else "yuv420p"
    my_codec = get_vcodec(args.video_codec, inp, ctr)

    apply_video_later = True

    if my_codec in encoders:
        apply_video_later = encoders[my_codec]["pix_fmt"].isdisjoint(allowed_pix_fmt)

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
        f"{timeline.fps}",
        "-i",
        "-",
        "-pix_fmt",
        target_pix_fmt,
    ]

    if apply_video_later:
        cmd.extend(["-c:v", "mpeg4", "-qscale:v", "1"])
    else:
        cmd = video_quality(cmd, args, inp, ctr)

    cmd.append(spedup)

    process2 = ffmpeg.Popen(
        cmd, stdin=subprocess.PIPE, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL
    )
    assert process2.stdin is not None

    seek = 10
    seek_frame = None
    frames_saved = 0

    # Keyframes are usually spread out every 5 seconds or less.
    if args.no_seek:
        SEEK_COST = 4294967295
    else:
        SEEK_COST = int(cns[0].streams.video[0].average_rate * 5)
    SEEK_RETRY = SEEK_COST // 2

    progress.start(timeline.end, "Creating new video")

    null_img = Image.new("RGB", (width, height), args.background)
    null_frame = av.VideoFrame.from_image(null_img).reformat(format=target_pix_fmt)

    frame_index = -1
    try:
        for index in range(timeline.end):
            # Add objects to obj_list
            obj_list: List[Union[VideoFrame, Visual]] = []
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
                    if frame_index > obj.index:
                        log.debug(f"Seek: {frame_index} -> beginning")
                        cns[obj.src].seek(0)
                        frame = next(decoders[obj.src])
                        frame_index = round(frame.time * timeline.fps)

                    while frame_index < obj.index:
                        # Check if skipping ahead is worth it.
                        if obj.index - frame_index > SEEK_COST and frame_index > seek:
                            seek = frame_index + SEEK_RETRY
                            seek_frame = frame_index
                            log.debug(f"Seek: {frame_index} -> {obj.index}")
                            cns[obj.src].seek(
                                obj.index * tous[obj.src],
                                stream=cns[obj.src].streams.video[0],
                            )

                        try:
                            frame = next(decoders[obj.src])
                            frame_index = round(frame.time * timeline.fps)
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

            process2.stdin.write(frame.to_ndarray().tobytes())

            if index % 3 == 0:
                progress.tick(index)

        progress.end()
        process2.stdin.close()
        process2.wait()
    except (OSError, BrokenPipeError):
        progress.end()
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
