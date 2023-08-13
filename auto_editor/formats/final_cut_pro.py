from __future__ import annotations

from typing import TYPE_CHECKING, Any, cast
from xml.etree.ElementTree import Element, ElementTree, SubElement, indent

if TYPE_CHECKING:
    from collections.abc import Sequence

    from auto_editor.ffwrapper import FileInfo
    from auto_editor.timeline import TlAudio, TlVideo, v3

"""
Export a FCPXML 11 file readable with Final Cut Pro 10.6.8 or later.

See docs here:
https://developer.apple.com/documentation/professional_video_applications/fcpxml_reference

"""


def get_colorspace(src: FileInfo) -> str:
    # See: https://developer.apple.com/documentation/professional_video_applications/fcpxml_reference/asset#3686496

    if not src.videos:
        return "1-1-1 (Rec. 709)"

    s = src.videos[0]
    if s.pix_fmt == "rgb24":
        return "sRGB IEC61966-2.1"
    if s.color_space == "smpte170m":
        return "6-1-6 (Rec. 601 NTSC)"
    if s.color_space == "bt470bg":
        return "5-1-6 (Rec. 601 PAL)"
    if s.color_primaries == "bt2020":
        # See: https://video.stackexchange.com/questions/22059/how-to-identify-hdr-video
        if s.color_transfer in ("arib-std-b67", "smpte2084"):
            return "9-18-9 (Rec. 2020 HLG)"
        return "9-1-9 (Rec. 2020)"

    return "1-1-1 (Rec. 709)"


def fcp_xml(group_name: str, output: str, tl: v3) -> None:

    def fraction(val: int) -> str:
        if val == 0:
            return "0s"
        return f"{val * tl.tb.denominator}/{tl.tb.numerator}s"

    for _, _src in tl.sources.items():
        src = _src
        break

    proj_name = src.path.stem
    tl_dur = tl.out_len()
    src_dur = int(src.duration * tl.tb)

    fcpxml = Element("fcpxml", version="1.11")
    resources = SubElement(fcpxml, "resources")
    SubElement(
        resources,
        "format",
        id="r1",
        name=f"FFVideoFormat{tl.res[1]}p{int(tl.tb)}",
        frameDuration=fraction(1),
        width=f"{tl.res[0]}",
        height=f"{tl.res[1]}",
        colorSpace=get_colorspace(src),
    )
    r2 = SubElement(
        resources,
        "asset",
        id="r2",
        name=proj_name,
        start="0s",
        hasVideo="1" if tl.v and tl.v[0] else "0",
        format="r1",
        hasAudio="1" if tl.a and tl.a[0] else "0",
        audioSources="1",
        audioChannels=f"{2 if not src.audios else src.audios[0].channels}",
        duration=fraction(tl_dur),
    )
    SubElement(r2, "media-rep", kind="original-media", src=src.path.resolve().as_uri())

    lib = SubElement(fcpxml, "library")
    evt = SubElement(lib, "event", name=group_name)
    proj = SubElement(evt, "project", name=proj_name)
    sequence = SubElement(
        proj,
        "sequence",
        format="r1",
        tcStart="0s",
        tcFormat="NDF",
        audioLayout="mono" if src.audios and src.audios[0].channels == 1 else "stereo",
        audioRate="44.1k" if tl.sr == 44100 else "48k",
    )
    spine = SubElement(sequence, "spine")

    if tl.v and tl.v[0]:
        clips: Sequence[TlVideo | TlAudio] = cast(Any, tl.v[0])
    elif tl.a and tl.a[0]:
        clips = tl.a[0]
    else:
        clips = []

    for clip in clips:
        clip_properties = {
            "name": proj_name,
            "ref": "r2",
            "offset": fraction(clip.start),
            "duration": fraction(clip.dur),
            "start": fraction(int(clip.offset // clip.speed)),
            "tcFormat": "NDF",
        }
        if clip.start == 0:
            del clip_properties["start"]

        asset = SubElement(spine, "asset-clip", clip_properties)
        if clip.speed != 1:
            # See the "Time Maps" section.
            # https://developer.apple.com/documentation/professional_video_applications/fcpxml_reference/story_elements/timemap/

            timemap = SubElement(asset, "timeMap")
            SubElement(timemap, "timept", time="0s", value="0s", interp="smooth2")
            SubElement(
                timemap,
                "timept",
                time=fraction(int(src_dur // clip.speed)),
                value=fraction(src_dur),
                interp="smooth2",
            )

    tree = ElementTree(fcpxml)
    indent(tree, space="\t", level=0)
    tree.write(output, xml_declaration=True, encoding="utf-8")
