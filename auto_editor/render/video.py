from __future__ import annotations

from dataclasses import dataclass
from typing import TYPE_CHECKING

import av
import numpy as np

from auto_editor.output import parse_bitrate
from auto_editor.timeline import TlImage, TlRect, TlVideo

if TYPE_CHECKING:
    from collections.abc import Iterator
    from typing import Any

    from auto_editor.ffwrapper import FileInfo
    from auto_editor.timeline import v3
    from auto_editor.utils.bar import Bar
    from auto_editor.utils.log import Log
    from auto_editor.utils.types import Args


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
                            graph.link_nodes(
                                graph.add_buffer(template=my_stream),
                                graph.add("scale", f"{obj.width}:-1"),
                                graph.add("buffersink"),
                            ).vpush(frame)
                            frame = graph.vpull()
                        img_cache[(obj.src, obj.width)] = frame.to_ndarray(
                            format="rgb24"
                        )
                        break
    return img_cache


def render_av(
    output: av.container.OutputContainer, tl: v3, args: Args, bar: Bar, log: Log
) -> Any:
    from_ndarray = av.VideoFrame.from_ndarray

    src = tl.src
    cns: dict[FileInfo, av.container.InputContainer] = {}
    decoders: dict[FileInfo, Iterator[av.VideoFrame]] = {}
    seek_cost: dict[FileInfo, int] = {}
    tous: dict[FileInfo, int] = {}

    target_pix_fmt = "yuv420p"  # Reasonable default
    target_fps = tl.tb  # Always constant
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

    if args.video_codec == "gif":
        _c = av.Codec("gif", "w")
        if _c.video_formats is not None and target_pix_fmt in (
            f.name for f in _c.video_formats
        ):
            target_pix_fmt = target_pix_fmt
        else:
            target_pix_fmt = "rgb8"
        del _c
    else:
        target_pix_fmt = (
            target_pix_fmt if target_pix_fmt in allowed_pix_fmt else "yuv420p"
        )

    ops = {"mov_flags": "faststart"}
    output_stream = output.add_stream(args.video_codec, rate=target_fps, options=ops)
    yield output_stream
    if not isinstance(output_stream, av.VideoStream):
        log.error(f"Not a known video codec: {args.video_codec}")
    if src.videos and src.videos[0].lang is not None:
        output_stream.metadata["language"] = src.videos[0].lang

    if args.scale == 1.0:
        target_width, target_height = tl.res
        scale_graph = None
    else:
        target_width = max(round(tl.res[0] * args.scale), 2)
        target_height = max(round(tl.res[1] * args.scale), 2)
        scale_graph = av.filter.Graph()
        scale_graph.link_nodes(
            scale_graph.add(
                "buffer", video_size="1x1", time_base="1/1", pix_fmt=target_pix_fmt
            ),
            scale_graph.add("scale", f"{target_width}:{target_height}"),
            scale_graph.add("buffersink"),
        )

    output_stream.width = target_width
    output_stream.height = target_height
    output_stream.pix_fmt = target_pix_fmt
    output_stream.framerate = target_fps

    color_range = src.videos[0].color_range
    colorspace = src.videos[0].color_space
    color_prim = src.videos[0].color_primaries
    color_trc = src.videos[0].color_transfer

    if color_range == 1 or color_range == 2:
        output_stream.color_range = color_range
    if colorspace in (0, 1) or (colorspace >= 3 and colorspace < 16):
        output_stream.colorspace = colorspace
    if color_prim == 1 or (color_prim >= 4 and color_prim < 17):
        output_stream.color_primaries = color_prim
    if color_trc == 1 or (color_trc >= 4 and color_trc < 22):
        output_stream.color_trc = color_trc

    if args.video_bitrate != "auto":
        output_stream.bit_rate = parse_bitrate(args.video_bitrate, log)
        log.debug(f"video bitrate: {output_stream.bit_rate}")
    else:
        log.debug(f"[auto] video bitrate: {output_stream.bit_rate}")

    if src is not None and src.videos and (sar := src.videos[0].sar) is not None:
        output_stream.sample_aspect_ratio = sar

    # First few frames can have an abnormal keyframe count, so never seek there.
    seek = 10
    seek_frame = None
    frames_saved = 0

    bar.start(tl.end, "Creating new video")

    bg = args.background
    null_frame = make_solid(target_width, target_height, target_pix_fmt, bg)
    frame_index = -1

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

        if tl.v1 is not None:
            # When there can be valid gaps in the timeline.
            frame = null_frame
        # else, use the last frame

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
                        cns[obj.src].seek(obj.index * tous[obj.src], stream=my_stream)

                    try:
                        frame = next(decoders[obj.src])
                        frame_index = round(frame.time * tl.tb)
                    except StopIteration:
                        log.debug(f"No source frame at {index=}. Using null frame")
                        frame = null_frame
                        break

                    if seek_frame is not None:
                        log.debug(f"Skipped {frame_index - seek_frame} frame indexes")
                        frames_saved += frame_index - seek_frame
                        seek_frame = None
                    if frame.key_frame:
                        log.debug(f"Keyframe {frame_index} {frame.pts}")

                if (frame.width, frame.height) != tl.res:
                    width, height = tl.res
                    graph = av.filter.Graph()
                    graph.link_nodes(
                        graph.add_buffer(template=my_stream),
                        graph.add(
                            "scale",
                            f"{width}:{height}:force_original_aspect_ratio=decrease:eval=frame",
                        ),
                        graph.add("pad", f"{width}:{height}:-1:-1:color={bg}"),
                        graph.add("buffersink"),
                    ).vpush(frame)
                    frame = graph.vpull()
            elif isinstance(obj, TlRect):
                graph = av.filter.Graph()
                x, y = obj.x, obj.y
                graph.link_nodes(
                    graph.add_buffer(template=my_stream),
                    graph.add(
                        "drawbox",
                        f"x={x}:y={y}:w={obj.width}:h={obj.height}:color={obj.fill}:t=fill",
                    ),
                    graph.add("buffersink"),
                ).vpush(frame)
                frame = graph.vpull()
            elif isinstance(obj, TlImage):
                img = img_cache[(obj.src, obj.width)]
                array = frame.to_ndarray(format="rgb24")

                overlay_h, overlay_w, _ = img.shape
                x_pos, y_pos = obj.x, obj.y

                x_start = max(x_pos, 0)
                y_start = max(y_pos, 0)
                x_end = min(x_pos + overlay_w, frame.width)
                y_end = min(y_pos + overlay_h, frame.height)

                # Clip the overlay image to fit into the frame
                overlay_x_start = max(-x_pos, 0)
                overlay_y_start = max(-y_pos, 0)
                overlay_x_end = overlay_w - max((x_pos + overlay_w) - frame.width, 0)
                overlay_y_end = overlay_h - max((y_pos + overlay_h) - frame.height, 0)
                clipped_overlay = img[
                    overlay_y_start:overlay_y_end, overlay_x_start:overlay_x_end
                ]

                # Create a region of interest (ROI) on the video frame
                roi = array[y_start:y_end, x_start:x_end]

                # Blend the overlay image with the ROI based on the opacity
                roi = (1 - obj.opacity) * roi + obj.opacity * clipped_overlay
                array[y_start:y_end, x_start:x_end] = roi
                array = np.clip(array, 0, 255).astype(np.uint8)

                frame = from_ndarray(array, format="rgb24")

        if scale_graph is not None and frame.width != target_width:
            scale_graph.vpush(frame)
            frame = scale_graph.vpull()

        if frame.format.name != target_pix_fmt:
            frame = frame.reformat(format=target_pix_fmt)
            bar.tick(index)
        elif index % 3 == 0:
            bar.tick(index)

        yield from_ndarray(frame.to_ndarray(), format=frame.format.name)

    bar.end()
    log.debug(f"Total frames saved seeking: {frames_saved}")
