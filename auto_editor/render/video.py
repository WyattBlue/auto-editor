from __future__ import annotations

import os.path
from dataclasses import dataclass
from math import ceil
from subprocess import DEVNULL, PIPE
from typing import TYPE_CHECKING

import av
from PIL import Image, ImageChops, ImageDraw, ImageOps

from auto_editor.output import video_quality
from auto_editor.timeline import TlImage, TlRect, TlVideo
from auto_editor.utils.encoder import encoders

if TYPE_CHECKING:
    from collections.abc import Iterator

    from auto_editor.ffwrapper import FFmpeg, FileInfo
    from auto_editor.timeline import v3
    from auto_editor.utils.bar import Bar
    from auto_editor.utils.container import Container
    from auto_editor.utils.log import Log
    from auto_editor.utils.types import Args

    ImgCache = dict[FileInfo, Image.Image]


av.logging.set_level(av.logging.PANIC)


@dataclass(slots=True)
class VideoFrame:
    index: int
    src: FileInfo


# From: github.com/PyAV-Org/PyAV/blob/main/av/video/frame.pyx
allowed_pix_fmt = {
    "yuv420p",
    "yuvj420p",
    "yuv444p",
    "yuvj444p",
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


def render_av(
    ffmpeg: FFmpeg,
    tl: v3,
    args: Args,
    bar: Bar,
    ctr: Container,
    temp: str,
    log: Log,
) -> tuple[str, bool]:
    img_cache: ImgCache = {}
    for layer in tl.v:
        for pobj in layer:
            if isinstance(pobj, TlImage) and pobj.src not in img_cache:
                img_cache[pobj.src] = Image.open(pobj.src.path).convert("RGBA")

    src = tl.src
    cns: dict[FileInfo, av.container.InputContainer] = {}
    decoders: dict[FileInfo, Iterator[av.video.frame.VideoFrame] | None] = {}
    seek_cost: dict[FileInfo, int] = {}
    tous: dict[FileInfo, int] = {}

    target_pix_fmt = "yuv420p"  # Reasonable default

    first_src: FileInfo | None = None
    for src in tl.sources:
        if first_src is None:
            first_src = src

        if src not in cns:
            cns[src] = av.open(f"{src.path}")

    for src, cn in cns.items():
        if len(cn.streams.video) == 0:
            decoders[src] = None
            tous[src] = 0
            seek_cost[src] = 0
        else:
            stream = cn.streams.video[0]
            stream.thread_type = "AUTO"

            if args.no_seek or stream.average_rate is None or stream.time_base is None:
                sc_val = 4294967295  # 2 ** 32 - 1
                tou = 0
            else:
                # Keyframes are usually spread out every 5 seconds or less.
                sc_val = int(stream.average_rate * 5)
                tou = int(stream.time_base.denominator / stream.average_rate)

            seek_cost[src] = sc_val
            tous[src] = tou
            decoders[src] = cn.decode(stream)

            if src == first_src and stream.pix_fmt is not None:
                target_pix_fmt = stream.pix_fmt

    log.debug(f"Tous: {tous}")
    log.debug(f"Clips: {tl.v}")

    target_pix_fmt = target_pix_fmt if target_pix_fmt in allowed_pix_fmt else "yuv420p"
    log.debug(f"Target pix_fmt: {target_pix_fmt}")

    apply_video_later = True

    if args.scale != 1:
        apply_video_later = False
    elif args.video_codec in encoders:
        apply_video_later = set(encoders[args.video_codec]).isdisjoint(allowed_pix_fmt)

    log.debug(f"apply video quality settings now: {not apply_video_later}")

    width, height = tl.res
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
        f"{tl.tb}",
        "-i",
        "-",
        "-pix_fmt",
        target_pix_fmt,
    ]

    if apply_video_later:
        cmd += ["-c:v", "mpeg4", "-qscale:v", "1"]
    else:
        cmd += video_quality(args, ctr)

    # Setting SAR requires re-encoding so we do it here.
    if src is not None and src.videos and (sar := src.videos[0].sar) is not None:
        cmd.extend(["-vf", f"setsar={sar}"])

    cmd.append(spedup)

    process2 = ffmpeg.Popen(cmd, stdin=PIPE, stdout=DEVNULL, stderr=DEVNULL)
    assert process2.stdin is not None

    # First few frames can have an abnormal keyframe count, so never seek there.
    seek = 10

    seek_frame = None
    frames_saved = 0

    bar.start(tl.end, "Creating new video")

    null_img = Image.new("RGB", (width, height), args.background)
    null_frame = av.VideoFrame.from_image(null_img).reformat(format=target_pix_fmt)

    frame_index = -1
    try:
        for index in range(tl.end):
            obj_list: list[VideoFrame | TlRect | TlImage] = []
            for layer in tl.v:
                for lobj in layer:
                    if isinstance(lobj, TlVideo):
                        if index >= lobj.start and index < (lobj.start + lobj.dur):
                            _i = lobj.offset + round((index - lobj.start) * lobj.speed)
                            obj_list.append(VideoFrame(_i, lobj.src))
                    elif index >= lobj.start and index < lobj.start + lobj.dur:
                        obj_list.append(lobj)

            frame = null_frame
            for obj in obj_list:
                if isinstance(obj, VideoFrame):
                    my_stream = cns[obj.src].streams.video[0]
                    if frame_index > obj.index:
                        log.debug(f"Seek: {frame_index} -> 0")
                        cns[obj.src].seek(0)
                        try:
                            it = decoders[obj.src]
                            assert it is not None
                            frame = next(it)
                            frame_index = round(frame.time * tl.tb)
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
                            it = decoders[obj.src]
                            assert it is not None
                            frame = next(it)
                            frame_index = round(frame.time * tl.tb)
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

                else:
                    frame = render_image(frame, obj, img_cache)

            if frame.format.name != target_pix_fmt:
                frame = frame.reformat(format=target_pix_fmt)
                bar.tick(index)
            elif index % 3 == 0:
                bar.tick(index)

            process2.stdin.write(frame.to_ndarray().tobytes())

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
