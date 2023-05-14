from __future__ import annotations

import os
import sys
from fractions import Fraction
from typing import Any

from auto_editor.ffwrapper import FFmpeg, FileInfo
from auto_editor.lang.json import Lexer, Parser, dump
from auto_editor.lib.err import MyError
from auto_editor.timeline import (
    TlAudio,
    TlEllipse,
    TlImage,
    TlRect,
    TlText,
    TlVideo,
    Visual,
    v1,
    v3,
)
from auto_editor.utils.cmdkw import (
    ParserError,
    Required,
    cAttr,
    cAttrs,
    parse_dataclass,
)
from auto_editor.utils.log import Log
from auto_editor.utils.types import (
    align,
    anchor,
    color,
    natural,
    number,
    src,
    threshold,
)

"""
Make a pre-edited file reference that can be inputted back into auto-editor.
"""

video_builder = cAttrs(
    "video",
    cAttr("start", natural, Required),
    cAttr("dur", natural, Required),
    cAttr("src", src, Required),
    cAttr("offset", natural, 0),
    cAttr("speed", number, 1),
    cAttr("stream", natural, 0),
)
audio_builder = cAttrs(
    "audio",
    cAttr("start", natural, Required),
    cAttr("dur", natural, Required),
    cAttr("src", src, Required),
    cAttr("offset", natural, 0),
    cAttr("speed", number, 1),
    cAttr("volume", threshold, 1),
    cAttr("stream", natural, 0),
)
text_builder = cAttrs(
    "text",
    cAttr("start", natural, Required),
    cAttr("dur", natural, Required),
    cAttr("content", str, Required),
    cAttr("x", int, "50%"),
    cAttr("y", int, "50%"),
    cAttr("font", str, "Arial"),
    cAttr("size", natural, 55),
    cAttr("align", align, "left"),
    cAttr("opacity", threshold, 1),
    cAttr("anchor", anchor, "ce"),
    cAttr("rotate", number, 0),
    cAttr("fill", str, "#FFF"),
    cAttr("stroke", natural, 0),
    cAttr("strokecolor", color, "#000"),
)

img_builder = cAttrs(
    "image",
    cAttr("start", natural, Required),
    cAttr("dur", natural, Required),
    cAttr("src", src, Required),
    cAttr("x", int, "50%"),
    cAttr("y", int, "50%"),
    cAttr("opacity", threshold, 1),
    cAttr("anchor", anchor, "ce"),
    cAttr("rotate", number, 0),
    cAttr("stroke", natural, 0),
    cAttr("strokecolor", color, "#000"),
)

rect_builder = cAttrs(
    "rect",
    cAttr("start", natural, Required),
    cAttr("dur", natural, Required),
    cAttr("x", int, Required),
    cAttr("y", int, Required),
    cAttr("width", int, Required),
    cAttr("height", int, Required),
    cAttr("opacity", threshold, 1),
    cAttr("anchor", anchor, "ce"),
    cAttr("rotate", number, 0),
    cAttr("fill", color, "#c4c4c4"),
    cAttr("stroke", natural, 0),
    cAttr("strokecolor", color, "#000"),
)
ellipse_builder = rect_builder

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


def check_attrs(data: object, log: Log, *attrs: str) -> None:
    if not isinstance(data, dict):
        log.error("Data is in wrong shape!")

    for attr in attrs:
        if attr not in data:
            log.error(f"'{attr}' attribute not found!")


def check_file(path: str, log: Log) -> None:
    if not os.path.isfile(path):
        log.error(f"Could not locate media file: '{path}'")


def read_v3(tl: Any, ffmpeg: FFmpeg, log: Log) -> v3:
    check_attrs(
        tl,
        log,
        "sources",
        "background",
        "v",
        "a",
        "timebase",
        "resolution",
        "samplerate",
    )

    sources: dict[str, FileInfo] = {}
    for _id, path in tl["sources"].items():
        check_file(path, log)
        sources[_id] = FileInfo(path, ffmpeg, log)

    bg = tl["background"]
    sr = tl["samplerate"]
    res = (tl["resolution"][0], tl["resolution"][1])
    tb = Fraction(tl["timebase"])

    v: Any = []
    a: Any = []

    def dict_to_args(d: dict) -> str:
        attrs = []
        for k, v in d.items():
            if k != "name":
                attrs.append(f"{k}={v}")
        return ",".join(attrs)

    for vlayers in tl["v"]:
        if vlayers:
            v_out: list[Visual] = []
            for vdict in vlayers:
                if "name" not in vdict:
                    log.error("Invalid video object: name not specified")
                if vdict["name"] not in visual_objects:
                    log.error(f"Unknown video object: {vdict['name']}")
                my_vobj, my_build = visual_objects[vdict["name"]]

                text = dict_to_args(vdict)
                try:
                    my_dict = parse_dataclass(text, my_build, coerce_default=True)
                    v_out.append(my_vobj(**my_dict))
                except ParserError as e:
                    log.error(e)

            v.append(v_out)

    for alayers in tl["a"]:
        if alayers:
            a_out = []
            for adict in alayers:
                if "name" not in adict:
                    log.error("Invalid audio object: name not specified")
                if adict["name"] not in audio_objects:
                    log.error(f"Unknown audio object: {adict['name']}")
                my_aobj, my_build = audio_objects[adict["name"]]

                text = dict_to_args(adict)
                try:
                    my_dict = parse_dataclass(text, my_build, coerce_default=True)
                    a_out.append(my_aobj(**my_dict))
                except ParserError as e:
                    log.error(e)

            a.append(a_out)

    return v3(sources, tb, sr, res, bg, v, a, None)


def read_v1(tl: Any, ffmpeg: FFmpeg, log: Log) -> v3:
    from auto_editor.make_layers import clipify, make_av

    check_attrs(tl, log, "source", "chunks")

    chunks = tl["chunks"]
    path = tl["source"]

    check_file(path, log)

    src = FileInfo(path, ffmpeg, log)
    sources = {"0": src}

    v, a = make_av([clipify(chunks, "0", 0)], sources, [0])

    return v3(
        sources,
        src.get_fps(),
        src.get_sr(),
        src.get_res(),
        "#000",
        v,
        a,
        v1(src, chunks),
    )


def read_json(path: str, ffmpeg: FFmpeg, log: Log) -> v3:
    with open(path) as f:
        try:
            tl = Parser(Lexer(path, f)).expr()
        except MyError as e:
            log.error(e)

    check_attrs(tl, log, "version")

    ver = tl["version"]

    if ver == "3":
        return read_v3(tl, ffmpeg, log)
    if ver == "1":
        return read_v1(tl, ffmpeg, log)
    if type(ver) is not str:
        log.error("version needs to be a string")
    log.error(f"Importing version {ver} timelines is not supported.")


def make_json_timeline(ver: int, out: str | int, tl: v3, log: Log) -> None:
    if ver not in (3, 1):
        log.error(f"Version {ver} is not supported!")

    if isinstance(out, str):
        if not out.endswith(".json"):
            log.error("Output extension must be .json")
        outfile: Any = open(out, "w")
    else:
        outfile = sys.stdout

    if ver == 3:
        dump(tl.as_dict(), outfile, indent=2)
    else:
        if tl.v1 is None:
            log.error("Timeline can't be converted to v1 format")
        dump(tl.v1.as_dict(), outfile, indent=2)

    if isinstance(out, str):
        outfile.close()
    else:
        print("")  # Flush stdout
