from __future__ import annotations

import xml.etree.ElementTree as ET
from typing import TYPE_CHECKING, Any, cast

from auto_editor.timeline import v3
from auto_editor.utils.func import aspect_ratio, to_timecode

if TYPE_CHECKING:
    from collections.abc import Sequence

    from auto_editor.timeline import TlAudio, TlVideo
    from auto_editor.utils.log import Log

"""
Shotcut uses the MLT timeline format

See docs here:
https://mltframework.org/docs/mltxml/

"""


def shotcut_read_mlt(path: str, log: Log) -> v3:
    raise NotImplementedError


def shotcut_write_mlt(output: str, tl: v3) -> None:
    mlt = ET.Element(
        "mlt",
        attrib={
            "LC_NUMERIC": "C",
            "version": "7.9.0",
            "title": "Shotcut version 22.09.23",
            "producer": "main_bin",
        },
    )

    width, height = tl.res
    num, den = aspect_ratio(width, height)
    tb = tl.tb

    ET.SubElement(
        mlt,
        "profile",
        attrib={
            "description": "automatic",
            "width": f"{width}",
            "height": f"{height}",
            "progressive": "1",
            "sample_aspect_num": "1",
            "sample_aspect_den": "1",
            "display_aspect_num": f"{num}",
            "display_aspect_den": f"{den}",
            "frame_rate_num": f"{tb.numerator}",
            "frame_rate_den": f"{tb.denominator}",
            "colorspace": "709",
        },
    )

    playlist_bin = ET.SubElement(mlt, "playlist", id="main_bin")
    ET.SubElement(playlist_bin, "property", name="xml_retain").text = "1"

    global_out = to_timecode(tl.out_len() / tb, "standard")

    producer = ET.SubElement(mlt, "producer", id="bg")

    ET.SubElement(producer, "property", name="length").text = global_out
    ET.SubElement(producer, "property", name="eof").text = "pause"
    ET.SubElement(producer, "property", name="resource").text = "#000"  # background
    ET.SubElement(producer, "property", name="mlt_service").text = "color"
    ET.SubElement(producer, "property", name="mlt_image_format").text = "rgba"
    ET.SubElement(producer, "property", name="aspect_ratio").text = "1"

    playlist = ET.SubElement(mlt, "playlist", id="background")
    ET.SubElement(
        playlist,
        "entry",
        attrib={"producer": "bg", "in": "00:00:00.000", "out": global_out},
    ).text = "1"

    chains = 0
    producers = 0

    if tl.v:
        clips: Sequence[TlVideo | TlAudio] = cast(Any, tl.v[0])
    elif tl.a:
        clips = tl.a[0]
    else:
        clips = []

    for clip in clips:
        src = clip.src
        length = to_timecode((clip.offset + clip.dur) / tb, "standard")

        if clip.speed == 1:
            resource = f"{src.path}"
            caption = f"{src.path.stem}"
            chain = ET.SubElement(
                mlt, "chain", attrib={"id": f"chain{chains}", "out": length}
            )
        else:
            chain = ET.SubElement(
                mlt, "producer", attrib={"id": f"producer{producers}", "out": length}
            )
            resource = f"{clip.speed}:{src.path}"
            caption = f"{src.path.stem} ({clip.speed}x)"

            producers += 1

        ET.SubElement(chain, "property", name="length").text = length
        ET.SubElement(chain, "property", name="resource").text = resource

        if clip.speed != 1:
            ET.SubElement(chain, "property", name="warp_speed").text = f"{clip.speed}"
            ET.SubElement(chain, "property", name="warp_pitch").text = "1"
            ET.SubElement(chain, "property", name="mlt_service").text = "timewarp"

        ET.SubElement(chain, "property", name="caption").text = caption

        chains += 1

    main_playlist = ET.SubElement(mlt, "playlist", id="playlist0")
    ET.SubElement(main_playlist, "property", name="shotcut:video").text = "1"
    ET.SubElement(main_playlist, "property", name="shotcut:name").text = "V1"

    producers = 0
    for i, clip in enumerate(clips):
        _in = to_timecode(clip.offset / tb, "standard")
        _out = to_timecode((clip.offset + clip.dur) / tb, "standard")

        tag_name = f"chain{i}"
        if clip.speed != 1:
            tag_name = f"producer{producers}"
            producers += 1

        ET.SubElement(
            main_playlist,
            "entry",
            attrib={"producer": tag_name, "in": _in, "out": _out},
        )

    tractor = ET.SubElement(
        mlt,
        "tractor",
        attrib={"id": "tractor0", "in": "00:00:00.000", "out": global_out},
    )
    ET.SubElement(tractor, "property", name="shotcut").text = "1"
    ET.SubElement(tractor, "property", name="shotcut:projectAudioChannels").text = "2"
    ET.SubElement(tractor, "track", producer="background")
    ET.SubElement(tractor, "track", producer="playlist0")

    tree = ET.ElementTree(mlt)

    ET.indent(tree, space="\t", level=0)

    tree.write(output, xml_declaration=True, encoding="utf-8")
