from __future__ import annotations

import os.path
from dataclasses import dataclass
from subprocess import DEVNULL, PIPE
from sys import platform
from typing import TYPE_CHECKING

import av
import numpy as np

from auto_editor.output import video_quality
from auto_editor.timeline import TlImage, TlRect, TlVideo
from auto_editor.utils.encoder import encoders
from auto_editor.utils.types import color

if TYPE_CHECKING:
    from collections.abc import Iterator

    from av.filter import FilterContext

    from auto_editor.ffwrapper import FFmpeg, FileInfo
    from auto_editor.timeline import v3
    from auto_editor.utils.bar import Bar
    from auto_editor.utils.container import Container
    from auto_editor.utils.log import Log
    from auto_editor.utils.types import Args


@dataclass(slots=True)
class VideoFrame:
    index: int
    src: FileInfo


def link_nodes(*nodes: FilterContext) -> None:
    for c, n in zip(nodes, nodes[1:]):
        c.link_to(n)


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
    # Use 'tl' by default
    return x, y


def make_solid(width: int, height: int, pix_fmt: str, bg: str) -> av.VideoFrame:
    hex_color = bg.lstrip("#").upper()
    rgb_color = tuple(int(hex_color[i : i + 2], 16) for i in (0, 2, 4))

    rgb_array = np.full((height, width, 3), rgb_color, dtype=np.uint8)
    rgb_frame = av.VideoFrame.from_ndarray(rgb_array, format="rgb24")
    return rgb_frame.reformat(format=pix_fmt)


def make_image_cache(tl: v3) -> dict[tuple[FileInfo, int], np.ndarray]:
    img_cache = {}
    for clip in tl.v:
        for obj in clip:
            if isinstance(obj, TlImage) and obj.src not in img_cache:
                with av.open(obj.src.path) as cn:
                    my_stream = cn.streams.video[0]
                    for frame in cn.decode(my_stream):
                        if obj.width != 0:
                            graph = av.filter.Graph()
                            link_nodes(
                                graph.add_buffer(template=my_stream),
                                graph.add("scale", f"{obj.width}:-1"),
                                graph.add("buffersink"),
                            )
                            graph.vpush(frame)
                            frame = graph.vpull()
                        img_cache[(obj.src, obj.width)] = frame.to_ndarray(
                            format="rgb24"
                        )
                        break
    return img_cache


def render_av(
    ffmpeg: FFmpeg,
    tl: v3,
    args: Args,
    bar: Bar,
    ctr: Container,
    temp: str,
    log: Log,
) -> tuple[str, bool]:
    src = tl.src
    cns: dict[FileInfo, av.container.InputContainer] = {}
    decoders: dict[FileInfo, Iterator[av.VideoFrame]] = {}
    seek_cost: dict[FileInfo, int] = {}
    tous: dict[FileInfo, int] = {}

    target_pix_fmt = "yuv420p"  # Reasonable default
    img_cache = make_image_cache(tl)

    first_src: FileInfo | None = None
    for src in tl.sources:
        if first_src is None:
            first_src = src

        if src not in cns:
            cns[src] = av.open(f"{src.path}")

    for src, cn in cns.items():
        if len(cn.streams.video) > 0:
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
    if args.video_codec in encoders:
        apply_video_later = set(encoders[args.video_codec]).isdisjoint(allowed_pix_fmt)

    log.debug(f"apply video quality settings now: {not apply_video_later}")

    if args.scale == 1.0:
        target_width, target_height = tl.res
        scale_graph = None
    else:
        target_width = max(round(tl.res[0] * args.scale), 2)
        target_height = max(round(tl.res[1] * args.scale), 2)
        scale_graph = av.filter.Graph()
        link_nodes(
            scale_graph.add(
                "buffer", video_size="1x1", time_base="1/1", pix_fmt=target_pix_fmt
            ),
            scale_graph.add("scale", f"{target_width}:{target_height}"),
            scale_graph.add("buffersink"),
        )

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
        f"{target_width}*{target_height}",
        "-framerate",
        f"{tl.tb}",
        "-i",
        "-",
        "-pix_fmt",
        target_pix_fmt,
    ]

    if platform == "darwin":
        # Fix videotoolbox issue with legacy macs
        cmd += ["-allow_sw", "1"]

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

    bg = color(args.background)
    null_frame = make_solid(target_width, target_height, target_pix_fmt, bg)
    frame_index = -1
    try:
        for index in range(tl.end):
            obj_list: list[VideoFrame | TlRect | TlImage] = []
            for layer in tl.v:
                for lobj in layer:
                    if isinstance(lobj, TlVideo):
                        if index >= lobj.start and index < (lobj.start + lobj.dur):
                            _i = round((lobj.offset + index - lobj.start) * lobj.speed)
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
                            frame = next(decoders[obj.src])
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
                            frame = next(decoders[obj.src])
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

                    if (frame.width, frame.height) != tl.res:
                        width, height = tl.res
                        graph = av.filter.Graph()
                        link_nodes(
                            graph.add_buffer(template=my_stream),
                            graph.add(
                                "scale",
                                f"{width}:{height}:force_original_aspect_ratio=decrease:eval=frame",
                            ),
                            graph.add("pad", f"{width}:{height}:-1:-1:color={bg}"),
                            graph.add("buffersink"),
                        )
                        graph.vpush(frame)
                        frame = graph.vpull()
                elif isinstance(obj, TlRect):
                    graph = av.filter.Graph()
                    x, y = apply_anchor(obj.x, obj.y, obj.width, obj.height, obj.anchor)
                    link_nodes(
                        graph.add_buffer(template=my_stream),
                        graph.add(
                            "drawbox",
                            f"x={x}:y={y}:w={obj.width}:h={obj.height}:color={obj.fill}:t=fill",
                        ),
                        graph.add("buffersink"),
                    )
                    graph.vpush(frame)
                    frame = graph.vpull()
                elif isinstance(obj, TlImage):
                    img = img_cache[(obj.src, obj.width)]
                    array = frame.to_ndarray(format="rgb24")

                    overlay_h, overlay_w, _ = img.shape
                    x_pos, y_pos = apply_anchor(
                        obj.x, obj.y, overlay_w, overlay_h, obj.anchor
                    )

                    x_start = max(x_pos, 0)
                    y_start = max(y_pos, 0)
                    x_end = min(x_pos + overlay_w, frame.width)
                    y_end = min(y_pos + overlay_h, frame.height)

                    # Clip the overlay image to fit into the frame
                    overlay_x_start = max(-x_pos, 0)
                    overlay_y_start = max(-y_pos, 0)
                    overlay_x_end = overlay_w - max(
                        (x_pos + overlay_w) - frame.width, 0
                    )
                    overlay_y_end = overlay_h - max(
                        (y_pos + overlay_h) - frame.height, 0
                    )
                    clipped_overlay = img[
                        overlay_y_start:overlay_y_end, overlay_x_start:overlay_x_end
                    ]

                    # Create a region of interest (ROI) on the video frame
                    roi = array[y_start:y_end, x_start:x_end]

                    # Blend the overlay image with the ROI based on the opacity
                    roi = (1 - obj.opacity) * roi + obj.opacity * clipped_overlay
                    array[y_start:y_end, x_start:x_end] = roi
                    array = np.clip(array, 0, 255).astype(np.uint8)

                    frame = av.VideoFrame.from_ndarray(array, format="rgb24")

            if scale_graph is not None and frame.width != target_width:
                scale_graph.vpush(frame)
                frame = scale_graph.vpull()

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

    return spedup, apply_video_later
