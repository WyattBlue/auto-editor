from __future__ import annotations

import json
import os
import sys

from auto_editor.ffwrapper import FFmpeg, FileInfo
from auto_editor.make_layers import clipify, make_av
from auto_editor.objs.export import ExJson, ExTimeline
from auto_editor.objs.tl import TlAudio, TlEllipse, TlImage, TlRect, TlText, TlVideo
from auto_editor.timeline import Timeline
from auto_editor.utils.chunks import Chunks
from auto_editor.utils.log import Log

"""
Make a pre-edited file reference that can be inputted back into auto-editor.
"""


def check_attrs(data: object, log: Log, *attrs: str) -> None:
    if not isinstance(data, dict):
        log.error("Data is in wrong shape!")
    for attr in attrs:
        if attr not in data:
            log.error(f"'{attr}' attribute not found!")


def check_file(path: str, log: Log) -> None:
    if not os.path.isfile(path):
        log.error(f"Could not locate media file: '{path}'")


def validate_chunks(chunks: object, log: Log) -> Chunks:
    if not isinstance(chunks, (list, tuple)):
        log.error("Chunks must be a list")

    if len(chunks) == 0:
        log.error("Chunks are empty!")

    new_chunks = []
    prev_end: int | None = None

    for i, chunk in enumerate(chunks):
        if len(chunk) != 3:
            log.error("Chunk must have a length of 3.")

        if i == 0 and chunk[0] != 0:
            log.error("First chunk must start with 0")

        if chunk[1] - chunk[0] < 1:
            log.error("Chunk duration must be at least 1")

        if chunk[2] <= 0 or chunk[2] > 99999:
            log.error("Chunk speed range must be >0 and <=99999")

        if prev_end is not None and chunk[0] != prev_end:
            log.error(f"Chunk disjointed at {chunk}")

        prev_end = chunk[1]

        new_chunks.append((chunk[0], chunk[1], float(chunk[2])))

    return new_chunks


class Version:
    __slots__ = ("major", "minor", "micro")

    def __init__(self, val: str, log: Log) -> None:
        ver_str = val.split(".")
        if len(ver_str) > 3:
            log.error("Version string: Too many separators!")
        while len(ver_str) < 3:
            ver_str.append("0")

        try:
            self.major, self.minor, self.micro = map(int, ver_str)
        except ValueError:
            log.error("Version string: Could not convert to int.")

    def __eq__(self, other: object) -> bool:
        if isinstance(other, tuple) and len(other) == 2:
            return (self.major, self.minor) == other
        return (self.major, self.minor, self.micro) == other

    def __str__(self) -> str:
        return f"{self.major}.{self.minor}.{self.micro}"


def read_json(path: str, ffmpeg: FFmpeg, log: Log) -> Timeline:
    with open(path) as f:
        data = json.load(f)

    check_attrs(data, log, "version")
    version = Version(data["version"], log)

    if version == (1, 0) or version == (0, 1):
        check_attrs(data, log, "source", "chunks")
        check_file(data["source"], log)

        chunks = validate_chunks(data["chunks"], log)
        src = FileInfo(data["source"], ffmpeg, log, "0")

        vspace, aspace = make_av([clipify(chunks, "0")], {"0": src}, [0])

        tb = src.get_fps()
        sr = src.get_samplerate()
        res = src.get_res()

        return Timeline({"0": src}, tb, sr, res, "#000", vspace, aspace, chunks)

    if version == (2, 0) or version == (0, 2):
        check_attrs(data, log, "timeline", "source")
        for path in data["source"].values():
            check_file(path, log)
        # return data["background"], data["source"], chunks

        raise ValueError("Importing v2 timelines not implemented.")

    log.error(f"Unsupported version: {version}")


def get_name(o: object) -> str:
    if isinstance(o, TlVideo):
        return "video"
    if isinstance(o, TlAudio):
        return "audio"
    if isinstance(o, TlRect):
        return "rectangle"
    if isinstance(o, TlEllipse):
        return "ellipse"
    if isinstance(o, TlImage):
        return "image"
    if isinstance(o, TlText):
        return "text"

    raise ValueError("Unreachable")


def make_json_timeline(
    obj: ExJson | ExTimeline,
    out: str | int,
    timeline: Timeline,
    log: Log,
) -> None:

    version = Version(obj.api, log)

    if version == (1, 0) or version == (0, 1):
        if timeline.chunks is None:
            log.error("Timeline too complex to convert to version 1.0")

        if "0" not in timeline.sources:
            log.debug(f"{timeline.sources}")
            log.error("API version 1 needs one source, got many")

        data: dict = {
            "version": "1.0.0",
            "source": timeline.sources["0"].abspath,
            "chunks": timeline.chunks,
        }
    elif version == (2, 0) or version == (0, 2):
        sources = {}
        for key, src in timeline.sources.items():
            sources[key] = src.abspath

        v = []
        for i, vlayer in enumerate(timeline.v):
            vb = []
            for vobj in vlayer:
                vb.append({"name": get_name(vobj)} | vobj.__dict__)
            if len(vb) > 0:
                v.append(vb)

        a = []
        for i, alayer in enumerate(timeline.a):
            ab = []
            for aobj in alayer:
                ab.append({"name": get_name(aobj)} | aobj.__dict__)
            if len(ab) > 0:
                a.append(ab)

        data = {
            "version": "2.0.0",
            "timeline": {
                "background": timeline.background,
                "resolution": timeline.res,
                "sources": sources,
                "timebase": str(timeline.timebase),
                "samplerate": timeline.samplerate,
                "v": v,
                "a": a,
            },
        }
    else:
        log.error(f"Version {version} is not supported!")

    if isinstance(out, str):
        if not out.endswith(".json"):
            log.error("Output extension must be .json")

        with open(out, "w") as outfile:
            json.dump(data, outfile, indent=2, default=lambda o: o.__dict__)
    else:
        json.dump(data, sys.stdout, indent=2, default=lambda o: o.__dict__)
        print("")  # Flush stdout
