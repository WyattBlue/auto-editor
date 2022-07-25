from __future__ import annotations

from dataclasses import dataclass
from fractions import Fraction

from auto_editor.ffwrapper import FileInfo
from auto_editor.make_layers import ASpace, Visual, VSpace, make_layers
from auto_editor.objects import (
    EllipseObj,
    ImageObj,
    RectangleObj,
    TextObj,
    VideoObj,
    ellipse_builder,
    img_builder,
    parse_dataclass,
    rect_builder,
    text_builder,
)
from auto_editor.utils.bar import Bar
from auto_editor.utils.chunks import Chunks
from auto_editor.utils.log import Log
from auto_editor.utils.types import Args


@dataclass
class Timeline:
    inputs: list[FileInfo]
    timebase: Fraction
    samplerate: int
    res: tuple[int, int]
    background: str
    v: VSpace
    a: ASpace
    chunks: Chunks | None = None

    @property
    def inp(self) -> FileInfo:
        return self.inputs[0]

    @property
    def end(self) -> int:
        end = 0
        for vclips in self.v:
            if len(vclips) > 0:
                v = vclips[-1]
                if isinstance(v, VideoObj):
                    end = max(end, max(1, round(v.start + (v.dur / v.speed))))
                else:
                    end = max(end, v.start + v.dur)
        for aclips in self.a:
            if len(aclips) > 0:
                a = aclips[-1]
                end = max(end, max(1, round(a.start + (a.dur / a.speed))))

        return end

    def out_len(self) -> float:
        out_len: float = 0
        for vclips in self.v:
            dur: float = 0
            for v_obj in vclips:
                if isinstance(v_obj, VideoObj):
                    dur += v_obj.dur / v_obj.speed
                else:
                    dur += v_obj.dur
            out_len = max(out_len, dur)
        for aclips in self.a:
            dur = 0
            for aclip in aclips:
                dur += aclip.dur / aclip.speed
            out_len = max(out_len, dur)
        return out_len


def make_timeline(
    inputs: list[FileInfo], args: Args, sr: int, bar: Bar, temp: str, log: Log
) -> Timeline:

    if inputs:
        tb = inputs[0].get_fps() if args.frame_rate is None else args.frame_rate
        res = inputs[0].get_res() if args.resolution is None else args.resolution
    else:
        tb, res = Fraction(30), (1920, 1080)

    chunks, vclips, aclips = make_layers(
        inputs,
        tb,
        args.edit_based_on,
        args.frame_margin,
        args.min_cut_length,
        args.min_clip_length,
        args.cut_out,
        args.add_in,
        args.mark_as_silent,
        args.mark_as_loud,
        args.set_speed_for_range,
        args.silent_speed,
        args.video_speed,
        bar,
        temp,
        log,
    )

    timeline = Timeline(inputs, tb, sr, res, args.background, vclips, aclips, chunks)

    w, h = res
    _vars: dict[str, int] = {
        "width": w,
        "height": h,
        "start": 0,
        "end": timeline.end,
    }

    pool: list[Visual] = []
    for key, obj_str in args.pool:
        if key == "add_text":
            pool.append(
                parse_dataclass(obj_str, TextObj, text_builder, log, _vars, True)
            )
        if key == "add_rectangle":
            pool.append(
                parse_dataclass(obj_str, RectangleObj, rect_builder, log, _vars, True)
            )
        if key == "add_ellipse":
            pool.append(
                parse_dataclass(obj_str, EllipseObj, ellipse_builder, log, _vars, True)
            )
        if key == "add_image":
            pool.append(
                parse_dataclass(obj_str, ImageObj, img_builder, log, _vars, True)
            )

    for obj in pool:
        # Higher layers are visually on top
        # TODO: Use less layers.
        timeline.v.append([obj])

    return timeline
