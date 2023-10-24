from __future__ import annotations

import os
import sys
from difflib import get_close_matches
from fractions import Fraction
from typing import Any

from auto_editor.ffwrapper import FFmpeg, FileInfo
from auto_editor.lang.json import Lexer, Parser, dump
from auto_editor.lib.err import MyError
from auto_editor.timeline import TlAudio, TlImage, TlRect, TlVideo, VSpace, v1, v3
from auto_editor.utils.cmdkw import ParserError, Required
from auto_editor.utils.log import Log
from auto_editor.utils.types import (
    CoerceError,
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


class cAttrs:
    __slots__ = ("name", "attrs")

    def __init__(self, name: str, *attrs: tuple[str, Any, Any]):
        self.name = name
        self.attrs = attrs


video_builder = cAttrs(
    "video",
    ("start", natural, Required),
    ("dur", natural, Required),
    ("src", src, Required),
    ("offset", natural, 0),
    ("speed", number, 1),
    ("stream", natural, 0),
)
audio_builder = cAttrs(
    "audio",
    ("start", natural, Required),
    ("dur", natural, Required),
    ("src", src, Required),
    ("offset", natural, 0),
    ("speed", number, 1),
    ("volume", threshold, 1),
    ("stream", natural, 0),
)
img_builder = cAttrs(
    "image",
    ("start", natural, Required),
    ("dur", natural, Required),
    ("src", src, Required),
    ("x", int, "50%"),
    ("y", int, "50%"),
    ("opacity", threshold, 1),
    ("anchor", anchor, "ce"),
    ("rotate", number, 0),
)

rect_builder = cAttrs(
    "rect",
    ("start", natural, Required),
    ("dur", natural, Required),
    ("x", int, Required),
    ("y", int, Required),
    ("width", int, Required),
    ("height", int, Required),
    ("anchor", anchor, "ce"),
    ("fill", color, "#c4c4c4"),
)

visual_objects = {
    "rect": (TlRect, rect_builder),
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

    for vlayers in tl["v"]:
        if vlayers:
            v_out: VSpace = []
            for vdict in vlayers:
                if "name" not in vdict:
                    log.error("Invalid video object: name not specified")
                if vdict["name"] not in visual_objects:
                    log.error(f"Unknown video object: {vdict['name']}")
                my_vobj, my_build = visual_objects[vdict["name"]]

                try:
                    my_dict = parse_obj(vdict, my_build)
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

                try:
                    my_dict = parse_obj(adict, my_build)
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
    with open(path, encoding="utf-8", errors="ignore") as f:
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


def parse_obj(obj: dict[str, Any], build: cAttrs) -> dict[str, Any]:
    kwargs: dict[str, Any] = {}

    del obj["name"]

    def var_f(n: str, c: Any, v: Any) -> Any:
        return c(v)

    for attr in build.attrs:
        kwargs[attr[0]] = var_f(*attr) if attr[2] is not Required else attr[1]

    for key, val in obj.items():
        found = False
        for attr in build.attrs:
            if key == attr[0]:
                try:
                    kwargs[key] = var_f(key, attr[1], val)
                except CoerceError as e:
                    raise ParserError(e)
                found = True
                break

        if not found:
            all_names = {attr[0] for attr in build.attrs}
            if matches := get_close_matches(key, all_names):
                more = f"\n    Did you mean:\n        {', '.join(matches)}"
            else:
                more = f"\n    keywords available:\n        {', '.join(all_names)}"

            raise ParserError(f"{build.name} got an unexpected keyword '{key}'\n{more}")

    for k, v in kwargs.items():
        if v is Required:
            raise ParserError(f"'{k}' must be specified.")

    return kwargs


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
