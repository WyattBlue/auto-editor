from __future__ import annotations

import os.path
from dataclasses import dataclass
from fractions import Fraction

from auto_editor.ffwrapper import FFmpeg, FileInfo
from auto_editor.make_layers import make_layers
from auto_editor.objs.tl import (
    ASpace,
    TlAudio,
    TlEllipse,
    TlImage,
    TlRect,
    TlText,
    TlVideo,
    Visual,
    VSpace,
    audio_builder,
    ellipse_builder,
    img_builder,
    rect_builder,
    text_builder,
    video_builder,
)
from auto_editor.objs.util import _Vars, parse_dataclass
from auto_editor.output import Ensure
from auto_editor.utils.bar import Bar
from auto_editor.utils.chunks import Chunks
from auto_editor.utils.log import Log
from auto_editor.utils.types import Args


@dataclass
class Timeline:
    sources: dict[str, FileInfo]
    timebase: Fraction
    samplerate: int
    res: tuple[int, int]
    background: str
    v: VSpace
    a: ASpace
    chunks: Chunks | None = None

    @property
    def end(self) -> int:
        end = 0
        for vclips in self.v:
            if len(vclips) > 0:
                v = vclips[-1]
                if isinstance(v, TlVideo):
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
                if isinstance(v_obj, TlVideo):
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
    sources: dict[str, FileInfo],
    inputs: list[int],
    ffmpeg: FFmpeg,
    ensure: Ensure,
    args: Args,
    sr: int,
    bar: Bar,
    temp: str,
    log: Log,
) -> Timeline:

    inp = None if not inputs else sources[str(inputs[0])]

    if inp is None:
        tb, res = Fraction(30), (1920, 1080)
    else:
        tb = inp.get_fps() if args.frame_rate is None else args.frame_rate
        res = inp.get_res() if args.resolution is None else args.resolution
    del inp

    chunks, vclips, aclips = make_layers(
        sources,
        inputs,
        ensure,
        tb,
        args.edit_based_on,
        args.margin,
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

    for raw in args.source:
        exploded = raw.split(":")
        if len(exploded) != 2:
            log.error("source label:path must have one :")
        label, path = exploded
        if len(label) > 55:
            log.error("Label must not exceed 55 characters.")

        for ill_char in ",.;()/\\[]}{'\"|#&<>^%$_@ ":
            if ill_char in label:
                log.error(f"Label '{label}' contains illegal character: {ill_char}")

        if label[0] in "0123456789":
            log.error(f"Label '{label}' must not start with a digit")
        if label[0] == "-":
            log.error(f"Label '{label}' must not start with a dash")

        if not os.path.isfile(path):
            log.error(f"Path '{path}' is not a file")

        sources[label] = FileInfo(path, ffmpeg, log, label)

    timeline = Timeline(sources, tb, sr, res, args.background, vclips, aclips, chunks)

    w, h = res
    _vars: _Vars = {
        "width": w,
        "height": h,
        "end": timeline.end,
        "tb": timeline.timebase,
    }

    OBJ_ATTRS_SEP = ":"
    visual_objects = {
        "rectangle": (TlRect, rect_builder),
        "ellipse": (TlEllipse, ellipse_builder),
        "text": (TlText, text_builder),
        "image": (TlImage, img_builder),
        "video": (TlVideo, video_builder),
    }

    audio_objects = {
        "audio": (TlAudio, audio_builder),
    }

    pool: list[Visual] = []
    apool: list[TlAudio] = []

    for obj_attrs_str in args.add:
        exploded = obj_attrs_str.split(OBJ_ATTRS_SEP)
        if len(exploded) > 2 or len(exploded) == 0:
            log.error("Invalid object syntax")

        obj_s = exploded[0]
        attrs = "" if len(exploded) == 1 else exploded[1]

        try:
            if obj_s in visual_objects:
                pool.append(
                    parse_dataclass(attrs, visual_objects[obj_s], log, _vars, True)
                )
            elif obj_s in audio_objects:
                apool.append(
                    parse_dataclass(attrs, audio_objects[obj_s], log, _vars, True)
                )
            else:
                log.error(f"Unknown timeline object: '{obj_s}'")
        except TypeError as e:
            log.error(e)

    for vobj in pool:
        timeline.v.append([vobj])

    for aobj in apool:
        timeline.a.append([aobj])

    return timeline
