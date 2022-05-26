import os.path
import subprocess
from fractions import Fraction
from typing import Tuple

from auto_editor.ffwrapper import FFmpeg
from auto_editor.objects import EllipseObj, ImageObj, RectangleObj, TextObj
from auto_editor.output import get_vcodec, video_quality
from auto_editor.timeline import Timeline
from auto_editor.utils.encoder import encoders
from auto_editor.utils.log import Log
from auto_editor.utils.progressbar import ProgressBar

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


def pix_fmt_allowed(pix_fmt: str) -> bool:
    return pix_fmt in allowed_pix_fmt


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
    args,
    progress: ProgressBar,
    rules,
    temp: str,
    log: Log,
) -> Tuple[str, bool]:
    try:
        import av

        av.logging.set_level(av.logging.PANIC)
    except ImportError:
        log.import_error("av")
    try:
        from PIL import Image, ImageChops, ImageDraw, ImageFont
    except ImportError:
        log.import_error("Pillow")

    font_cache = {}
    img_cache = {}
    for layer in timeline.v:
        for obj in layer:
            if isinstance(obj, TextObj) and obj.font not in font_cache:
                try:
                    font_cache[obj.font] = ImageFont.truetype(obj.font, obj.size)
                except OSError:
                    if obj.font == "default":
                        font_cache["default"] = ImageFont.load_default()
                    else:
                        log.error(f"Font '{obj.font}' not found.")

            if isinstance(obj, ImageObj) and obj.src not in img_cache:
                source = Image.open(obj.src)
                source = source.convert("RGBA")
                source = source.rotate(obj.rotate, expand=True)
                source = ImageChops.multiply(
                    source,
                    Image.new(
                        "RGBA", source.size, (255, 255, 255, int(obj.opacity * 255))
                    ),
                )
                img_cache[obj.src] = source

    def render_frame(frame, pix_fmt: str, timeline, index):
        img = frame.to_image().convert("RGBA")

        for layer in timeline.v:
            for obj in layer:
                obj_img = Image.new("RGBA", img.size, (255, 255, 255, 0))
                draw = ImageDraw.Draw(obj_img)

                if isinstance(obj, TextObj):
                    text_w, text_h = draw.textsize(
                        obj.content, font=font_cache[obj.font]
                    )
                    pos = apply_anchor(obj.x, obj.y, text_w, text_h, "ce")
                    draw.text(
                        pos,
                        obj.content,
                        font=font_cache[obj.font],
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

        return frame.from_image(img).reformat(format=pix_fmt)

    chunks = timeline.chunks

    if chunks is None:
        log.error("Timeline too complex")

    inp = timeline.inp

    if chunks[-1][2] == 99999:
        chunks.pop()

    progress.start(chunks[-1][1], "Creating new video")

    cn = av.open(inp.path, "r")
    pix_fmt = cn.streams.video[0].pix_fmt

    target_pix_fmt = pix_fmt

    if not pix_fmt_allowed(pix_fmt):
        target_pix_fmt = "yuv420p"

    my_codec = get_vcodec(args.video_codec, inp, rules)

    apply_video_later = True

    if my_codec in encoders:
        apply_video_later = encoders[my_codec]["pix_fmt"].isdisjoint(allowed_pix_fmt)

    if args.scale != 1:
        apply_video_later = False

    log.debug(f"apply video quality settings now: {not apply_video_later}")

    stream = cn.streams.video[0]
    stream.thread_type = "AUTO"

    width = stream.width
    height = stream.height

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
        cmd = video_quality(cmd, args, inp, rules)

    cmd.append(spedup)

    process2 = ffmpeg.Popen(
        cmd, stdin=subprocess.PIPE, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL
    )
    assert process2.stdin is not None

    input_equavalent = Fraction(0, 1)
    output_equavalent = 0
    chunk = chunks.pop(0)

    tou = int(stream.time_base.denominator / stream.average_rate)
    log.debug(f"Tou: {tou}")

    seek = 10
    seek_frame = None
    frames_saved = 0

    # Keyframes are usually spread out every 5 seconds or less.
    if args.no_seek:
        SEEK_COST = 4294967295
    else:
        SEEK_COST = int(stream.average_rate * 5)
    SEEK_RETRY = SEEK_COST // 2

    # Converting between two different framerates is a lot like applying a speed.
    fps_convert = Fraction(stream.average_rate, Fraction(timeline.fps))

    try:
        for frame in cn.decode(stream):
            # frame.time == frame.pts * stream.time_base
            index = round(frame.time * timeline.fps)
            index2 = round(frame.time * stream.average_rate)

            if frame.key_frame:
                log.debug(f"Keyframe {index} {frame.pts}")

            if seek_frame is not None:
                log.debug(f"Skipped {index - seek_frame} frames")
                frames_saved += index - seek_frame
                seek_frame = None

            if index > chunk[1]:
                if chunks:
                    chunk = chunks.pop(0)
                else:
                    break

            if chunk[2] == 99999:
                if chunk[1] - index2 > SEEK_COST and index2 > seek:
                    seek = index2 + SEEK_RETRY

                    seek_frame = index
                    cn.seek(chunk[1] * tou, stream=stream)
            else:
                input_equavalent += Fraction(1, Fraction(chunk[2]) * fps_convert)

            while input_equavalent > output_equavalent:
                # frame = render_frame(frame, target_pix_fmt, timeline, index)
                if pix_fmt != target_pix_fmt:
                    frame = frame.reformat(format=target_pix_fmt)

                in_bytes = frame.to_ndarray().tobytes()
                process2.stdin.write(in_bytes)
                output_equavalent += 1

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

    # Unfortunately, scaling has to be a concrete step.
    if args.scale != 1:
        sped_input = os.path.join(temp, "spedup0.mp4")
        spedup = os.path.join(temp, "scale0.mp4")

        cmd = [
            "-i",
            sped_input,
            "-vf",
            f"scale=iw*{args.scale}:ih*{args.scale}",
            spedup,
        ]

        check_errors = ffmpeg.pipe(cmd)
        if "Error" in check_errors or "failed" in check_errors:
            if "-allow_sw 1" in check_errors:
                cmd.insert(-1, "-allow_sw")
                cmd.insert(-1, "1")
            # Run again to show errors even if it might not work.
            ffmpeg.run(cmd)

    return spedup, apply_video_later
