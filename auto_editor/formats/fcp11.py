from __future__ import annotations

from typing import TYPE_CHECKING, Any, cast
from xml.etree.ElementTree import Element, ElementTree, SubElement, indent

if TYPE_CHECKING:
    from collections.abc import Sequence
    from fractions import Fraction

    from auto_editor.ffwrapper import FileInfo
    from auto_editor.timeline import TlAudio, TlVideo, v3
    from auto_editor.utils.log import Log


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
    if s.color_space == 5:  # "bt470bg"
        return "5-1-6 (Rec. 601 PAL)"
    if s.color_space == 6:  # "smpte170m"
        return "6-1-6 (Rec. 601 NTSC)"
    if s.color_primaries == 9:  # "bt2020"
        # See: https://video.stackexchange.com/questions/22059/how-to-identify-hdr-video
        if s.color_transfer in {16, 18}:  # "smpte2084" "arib-std-b67"
            return "9-18-9 (Rec. 2020 HLG)"
        return "9-1-9 (Rec. 2020)"

    return "1-1-1 (Rec. 709)"


def make_name(src: FileInfo, tb: Fraction) -> str:
    if src.get_res()[1] == 720 and tb == 30:
        return "FFVideoFormat720p30"
    if src.get_res()[1] == 720 and tb == 25:
        return "FFVideoFormat720p25"
    return "FFVideoFormatRateUndefined"


def fcp11_write_xml(
    group_name: str, version: int, output: str, resolve: bool, tl: v3, log: Log
) -> None:
    def fraction(val: int) -> str:
        if val == 0:
            return "0s"
        return f"{val * tl.tb.denominator}/{tl.tb.numerator}s"

    src = tl.src
    assert src is not None

    proj_name = src.path.stem
    src_dur = int(src.duration * tl.tb)
    tl_dur = src_dur if resolve else tl.out_len()

    if version == 11:
        ver_str = "1.11"
    elif version == 10:
        ver_str = "1.10"
    else:
        log.error(f"Unknown final cut pro version: {version}")

    fcpxml = Element("fcpxml", version=ver_str)
    resources = SubElement(fcpxml, "resources")

    for i, one_src in enumerate(tl.unique_sources()):
        SubElement(
            resources,
            "format",
            id=f"r{i * 2 + 1}",
            name=make_name(one_src, tl.tb),
            frameDuration=fraction(1),
            width=f"{tl.res[0]}",
            height=f"{tl.res[1]}",
            colorSpace=get_colorspace(one_src),
        )
        r2 = SubElement(
            resources,
            "asset",
            id=f"r{i * 2 + 2}",
            name=one_src.path.stem,
            start="0s",
            hasVideo="1" if one_src.videos else "0",
            format=f"r{i * 2 + 1}",
            hasAudio="1" if one_src.audios else "0",
            audioSources="1",
            audioChannels=f"{2 if not one_src.audios else one_src.audios[0].channels}",
            duration=fraction(tl_dur),
        )
        SubElement(
            r2, "media-rep", kind="original-media", src=one_src.path.resolve().as_uri()
        )

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

    def make_clip(ref: str, clip: TlVideo | TlAudio) -> None:
        clip_properties = {
            "name": proj_name,
            "ref": ref,
            "offset": fraction(clip.start),
            "duration": fraction(clip.dur),
            "start": fraction(clip.offset),
            "tcFormat": "NDF",
        }
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

    if tl.v and tl.v[0]:
        clips: Sequence[TlVideo | TlAudio] = cast(Any, tl.v[0])
    elif tl.a and tl.a[0]:
        clips = tl.a[0]
    else:
        clips = []

    all_refs: list[str] = ["r2"]
    if resolve:
        for i in range(1, len(tl.a)):
            all_refs.append(f"r{(i + 1) * 2}")

    for my_ref in reversed(all_refs):
        for clip in clips:
            make_clip(my_ref, clip)

    tree = ElementTree(fcpxml)
    indent(tree, space="\t", level=0)
    tree.write(output, xml_declaration=True, encoding="utf-8")
