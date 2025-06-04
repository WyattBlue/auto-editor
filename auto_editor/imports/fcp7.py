from __future__ import annotations

import xml.etree.ElementTree as ET
from fractions import Fraction
from typing import TYPE_CHECKING
from urllib.parse import unquote
from xml.etree.ElementTree import Element

from auto_editor.ffwrapper import FileInfo
from auto_editor.timeline import ASpace, Clip, Template, VSpace, v3

if TYPE_CHECKING:
    from auto_editor.utils.log import Log


SUPPORTED_EFFECTS = ("timeremap",)


def show(ele: Element, limit: int, depth: int = 0) -> None:
    print(
        f"{' ' * (depth * 4)}<{ele.tag} {ele.attrib}> {ele.text.strip() if ele.text is not None else ''}"
    )
    for child in ele:
        if isinstance(child, Element) and depth < limit:
            show(child, limit, depth + 1)


def read_filters(clipitem: Element, log: Log) -> float:
    for effect_tag in clipitem:
        if effect_tag.tag in {"enabled", "start", "end"}:
            continue
        if len(effect_tag) < 3:
            log.error("<effect> requires: <effectid> <name> and one <parameter>")
        for i, effects in enumerate(effect_tag):
            if i == 0 and effects.tag != "name":
                log.error("<effect>: <name> must be first tag")
            if i == 1 and effects.tag != "effectid":
                log.error("<effect>: <effectid> must be second tag")
                if effects.text not in SUPPORTED_EFFECTS:
                    log.error(f"`{effects.text}` is not a supported effect.")

            if i > 1:
                for j, parms in enumerate(effects):
                    if j == 0:
                        if parms.tag != "parameterid":
                            log.error("<parameter>: <parameterid> must be first tag")
                        if parms.text != "speed":
                            break

                    if j > 0 and parms.tag == "value":
                        if parms.text is None:
                            log.error("<value>: number required")
                        return float(parms.text) / 100

    return 1.0


def uri_to_path(uri: str) -> str:
    # Handle inputs like:
    # /Users/wyattblue/projects/auto-editor/example.mp4
    # file:///Users/wyattblue/projects/auto-editor/example.mp4
    # file:///C:/Users/WyattBlue/projects/auto-editor/example.mp4
    # file://localhost/Users/wyattblue/projects/auto-editor/example.mp4

    if uri.startswith("file://localhost/"):
        uri = uri[16:]
    elif uri.startswith("file://"):
        # Windows-style paths
        uri = uri[8:] if len(uri) > 8 and uri[9] == ":" else uri[7:]
    else:
        return uri
    return unquote(uri)


def read_tb_ntsc(tb: int, ntsc: bool) -> Fraction:
    if ntsc:
        if tb == 24:
            return Fraction(24000, 1001)
        if tb == 30:
            return Fraction(30000, 1001)
        if tb == 60:
            return Fraction(60000, 1001)
        return tb * Fraction(999, 1000)

    return Fraction(tb)


def fcp7_read_xml(path: str, log: Log) -> v3:
    def xml_bool(val: str) -> bool:
        if val == "TRUE":
            return True
        if val == "FALSE":
            return False
        raise TypeError("Value must be 'TRUE' or 'FALSE'")

    try:
        tree = ET.parse(path)
    except FileNotFoundError:
        log.error(f"Could not find '{path}'")

    root = tree.getroot()

    def parse(ele: Element, schema: dict) -> dict:
        new: dict = {}
        for key, val in schema.items():
            if isinstance(val, dict) and "__arr" in val:
                new[key] = []

        is_arr = False
        for child in ele:
            if child.tag not in schema:
                continue

            if schema[child.tag] is None:
                new[child.tag] = child
                continue

            if isinstance(schema[child.tag], dict):
                val = parse(child, schema[child.tag])
                is_arr = "__arr" in schema[child.tag]
            else:
                val = schema[child.tag](child.text)

            if child.tag in new:
                if not is_arr:
                    log.error(f"<{child.tag}> can only occur once")
                new[child.tag].append(val)
            else:
                new[child.tag] = [val] if is_arr else val

        return new

    def check(ele: Element, tag: str) -> None:
        if tag != ele.tag:
            log.error(f"Expected '{tag}' tag, got '{ele.tag}'")

    check(root, "xmeml")
    check(root[0], "sequence")
    result = parse(
        root[0],
        {
            "name": str,
            "duration": int,
            "rate": {
                "timebase": Fraction,
                "ntsc": xml_bool,
            },
            "media": None,
        },
    )

    tb = read_tb_ntsc(result["rate"]["timebase"], result["rate"]["ntsc"])
    av = parse(
        result["media"],
        {
            "video": None,
            "audio": None,
        },
    )

    sources: dict[str, FileInfo] = {}
    vobjs: VSpace = []
    aobjs: ASpace = []

    vclip_schema = {
        "format": {
            "samplecharacteristics": {
                "width": int,
                "height": int,
            },
        },
        "track": {
            "__arr": "",
            "clipitem": {
                "__arr": "",
                "start": int,
                "end": int,
                "in": int,
                "out": int,
                "file": None,
                "filter": None,
            },
        },
    }

    aclip_schema = {
        "format": {"samplecharacteristics": {"samplerate": int}},
        "track": {
            "__arr": "",
            "clipitem": {
                "__arr": "",
                "start": int,
                "end": int,
                "in": int,
                "out": int,
                "file": None,
                "filter": None,
            },
        },
    }

    sr = 48000
    res = (1920, 1080)

    if "video" in av:
        tracks = parse(av["video"], vclip_schema)

        if "format" in tracks:
            width = tracks["format"]["samplecharacteristics"]["width"]
            height = tracks["format"]["samplecharacteristics"]["height"]
            res = width, height

        for t, track in enumerate(tracks["track"]):
            if len(track["clipitem"]) > 0:
                vobjs.append([])
            for clipitem in track["clipitem"]:
                file_id = clipitem["file"].attrib["id"]
                if file_id not in sources:
                    fileobj = parse(clipitem["file"], {"pathurl": str})

                    if "pathurl" in fileobj:
                        sources[file_id] = FileInfo.init(
                            uri_to_path(fileobj["pathurl"]),
                            log,
                        )
                    else:
                        show(clipitem["file"], 3)
                        log.error(
                            f"'pathurl' child element not found in {clipitem['file'].tag}"
                        )

                if "filter" in clipitem:
                    speed = read_filters(clipitem["filter"], log)
                else:
                    speed = 1.0

                start = clipitem["start"]
                dur = clipitem["end"] - start
                offset = clipitem["in"]

                vobjs[t].append(
                    Clip(start, dur, sources[file_id], offset, stream=0, speed=speed)
                )

    if "audio" in av:
        tracks = parse(av["audio"], aclip_schema)
        if "format" in tracks:
            sr = tracks["format"]["samplecharacteristics"]["samplerate"]

        for t, track in enumerate(tracks["track"]):
            if len(track["clipitem"]) > 0:
                aobjs.append([])
            for clipitem in track["clipitem"]:
                file_id = clipitem["file"].attrib["id"]
                if file_id not in sources:
                    fileobj = parse(clipitem["file"], {"pathurl": str})
                    sources[file_id] = FileInfo.init(
                        uri_to_path(fileobj["pathurl"]), log
                    )

                if "filter" in clipitem:
                    speed = read_filters(clipitem["filter"], log)
                else:
                    speed = 1.0

                start = clipitem["start"]
                dur = clipitem["end"] - start
                offset = clipitem["in"]

                aobjs[t].append(
                    Clip(start, dur, sources[file_id], offset, stream=0, speed=speed)
                )

    T = Template.init(sources[next(iter(sources))], sr, res=res)
    return v3(tb, "#000", T, vobjs, aobjs, v1=None)
