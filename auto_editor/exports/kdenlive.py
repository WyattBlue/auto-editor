import json
import xml.etree.ElementTree as ET
from os import getcwd
from uuid import uuid4

from auto_editor.timeline import Clip, v3
from auto_editor.utils.func import aspect_ratio, to_timecode

"""
kdenlive uses the MLT timeline format

See docs here:
https://mltframework.org/docs/mltxml/

kdenlive specifics:
https://github.com/KDE/kdenlive/blob/master/dev-docs/fileformat.md
"""


def kdenlive_write(output: str, tl: v3) -> None:
    mlt = ET.Element(
        "mlt",
        attrib={
            "LC_NUMERIC": "C",
            "version": "7.22.0",
            "producer": "main_bin",
            "root": f"{getcwd()}",
        },
    )

    width, height = tl.res
    num, den = aspect_ratio(width, height)
    tb = tl.tb
    seq_uuid = uuid4()

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

    # Reserved producer0
    global_out = to_timecode(len(tl) / tb, "standard")
    producer = ET.SubElement(mlt, "producer", id="producer0")
    ET.SubElement(producer, "property", name="length").text = global_out
    ET.SubElement(producer, "property", name="eof").text = "continue"
    ET.SubElement(producer, "property", name="resource").text = "black"
    ET.SubElement(producer, "property", name="mlt_service").text = "color"
    ET.SubElement(producer, "property", name="kdenlive:playlistid").text = "black_track"
    ET.SubElement(producer, "property", name="mlt_image_format").text = "rgba"
    ET.SubElement(producer, "property", name="aspect_ratio").text = "1"

    # Get all clips
    if tl.v:
        clips = [clip for clip in tl.v[0] if isinstance(clip, Clip)]
    elif tl.a:
        clips = tl.a[0]
    else:
        clips = []

    source_ids = {}
    source_id = 4
    clip_playlists = []
    chains = 0
    playlists = 0
    producers = 1
    a_channels = len(tl.a)
    v_channels = len(tl.v)
    warped_clips = [i for i, clip in enumerate(clips) if clip.speed != 1]

    # create all producers for warped clips
    for clip_idx in warped_clips:
        for i in range(a_channels + v_channels):
            clip = clips[clip_idx]
            path = str(clip.src.path)

            if path not in source_ids:
                source_ids[path] = str(source_id)
                source_id += 1

            prod = ET.SubElement(
                mlt,
                "producer",
                attrib={
                    "id": f"producer{producers}",
                    "in": "00:00:00.000",
                    "out": global_out,
                },
            )
            ET.SubElement(
                prod, "property", name="resource"
            ).text = f"{clip.speed}:{path}"
            ET.SubElement(prod, "property", name="warp_speed").text = str(clip.speed)
            ET.SubElement(prod, "property", name="warp_resource").text = path
            ET.SubElement(prod, "property", name="warp_pitch").text = "0"
            ET.SubElement(prod, "property", name="mlt_service").text = "timewarp"
            ET.SubElement(prod, "property", name="kdenlive:id").text = source_ids[path]

            if i < a_channels:
                ET.SubElement(prod, "property", name="vstream").text = "0"
                ET.SubElement(prod, "property", name="astream").text = str(
                    a_channels - 1 - i
                )
                ET.SubElement(prod, "property", name="set.test_audio").text = "0"
                ET.SubElement(prod, "property", name="set.test_video").text = "1"
            else:
                ET.SubElement(prod, "property", name="vstream").text = str(
                    v_channels - 1 - (i - a_channels)
                )
                ET.SubElement(prod, "property", name="astream").text = "0"
                ET.SubElement(prod, "property", name="set.test_audio").text = "1"
                ET.SubElement(prod, "property", name="set.test_video").text = "0"

            producers += 1

    # create chains, playlists and tractors for audio channels
    for i, audio in enumerate(tl.a):
        path = str(audio[0].src.path)

        if path not in source_ids:
            source_ids[path] = str(source_id)
            source_id += 1

        chain = ET.SubElement(mlt, "chain", attrib={"id": f"chain{chains}"})
        ET.SubElement(chain, "property", name="resource").text = path
        ET.SubElement(
            chain, "property", name="mlt_service"
        ).text = "avformat-novalidate"
        ET.SubElement(chain, "property", name="vstream").text = "0"
        ET.SubElement(chain, "property", name="astream").text = str(a_channels - 1 - i)
        ET.SubElement(chain, "property", name="set.test_audio").text = "0"
        ET.SubElement(chain, "property", name="set.test_video").text = "1"
        ET.SubElement(chain, "property", name="kdenlive:id").text = source_ids[path]

        for _i in range(2):
            playlist = ET.SubElement(mlt, "playlist", id=f"playlist{playlists}")
            clip_playlists.append(playlist)
            ET.SubElement(playlist, "property", name="kdenlive:audio_track").text = "1"
            playlists += 1

        tractor = ET.SubElement(
            mlt,
            "tractor",
            attrib={"id": f"tractor{chains}", "in": "00:00:00.000", "out": global_out},
        )
        ET.SubElement(tractor, "property", name="kdenlive:audio_track").text = "1"
        ET.SubElement(tractor, "property", name="kdenlive:timeline_active").text = "1"
        ET.SubElement(tractor, "property", name="kdenlive:audio_rec")
        ET.SubElement(
            tractor,
            "track",
            attrib={"hide": "video", "producer": f"playlist{playlists - 2}"},
        )
        ET.SubElement(
            tractor,
            "track",
            attrib={"hide": "video", "producer": f"playlist{playlists - 1}"},
        )
        chains += 1

    # create chains, playlists and tractors for video channels
    for i, video in enumerate(tl.v):
        path = f"{video[0].src.path}"  # type: ignore

        if path not in source_ids:
            source_ids[path] = str(source_id)
            source_id += 1

        chain = ET.SubElement(mlt, "chain", attrib={"id": f"chain{chains}"})
        ET.SubElement(chain, "property", name="resource").text = path
        ET.SubElement(
            chain, "property", name="mlt_service"
        ).text = "avformat-novalidate"
        ET.SubElement(chain, "property", name="vstream").text = str(v_channels - 1 - i)
        ET.SubElement(chain, "property", name="astream").text = "0"
        ET.SubElement(chain, "property", name="set.test_audio").text = "1"
        ET.SubElement(chain, "property", name="set.test_video").text = "0"
        ET.SubElement(chain, "property", name="kdenlive:id").text = source_ids[path]

        for _i in range(2):
            playlist = ET.SubElement(mlt, "playlist", id=f"playlist{playlists}")
            clip_playlists.append(playlist)
            playlists += 1

        tractor = ET.SubElement(
            mlt,
            "tractor",
            attrib={"id": f"tractor{chains}", "in": "00:00:00.000", "out": global_out},
        )
        ET.SubElement(tractor, "property", name="kdenlive:timeline_active").text = "1"
        ET.SubElement(
            tractor,
            "track",
            attrib={"hide": "audio", "producer": f"playlist{playlists - 2}"},
        )
        ET.SubElement(
            tractor,
            "track",
            attrib={"hide": "audio", "producer": f"playlist{playlists - 1}"},
        )
        chains += 1

    # final chain for the project bin
    path = str(clips[0].src.path)
    chain = ET.SubElement(mlt, "chain", attrib={"id": f"chain{chains}"})
    ET.SubElement(chain, "property", name="resource").text = path
    ET.SubElement(chain, "property", name="mlt_service").text = "avformat-novalidate"
    ET.SubElement(chain, "property", name="audio_index").text = "1"
    ET.SubElement(chain, "property", name="video_index").text = "0"
    ET.SubElement(chain, "property", name="vstream").text = "0"
    ET.SubElement(chain, "property", name="astream").text = "0"
    ET.SubElement(chain, "property", name="kdenlive:id").text = source_ids[path]

    groups = []
    group_counter = 0
    producers = 1

    for clip in clips:
        group_children: list[object] = []
        _in = to_timecode(clip.offset / tb, "standard")
        _out = to_timecode((clip.offset + clip.dur) / tb, "standard")
        path = str(clip.src.path)

        for i, playlist in enumerate(clip_playlists[::2]):
            # adding 1 extra frame for each previous group to the start time works but feels hacky?
            group_children.append(
                {
                    "data": f"{i}:{clip.start + group_counter}",
                    "leaf": "clip",
                    "type": "Leaf",
                }
            )
            clip_prod = ""

            if clip.speed == 1:
                clip_prod = f"chain{i}"
            else:
                clip_prod = f"producer{producers}"
                producers += 1

            entry = ET.SubElement(
                playlist,
                "entry",
                attrib={"producer": f"{clip_prod}", "in": _in, "out": _out},
            )
            ET.SubElement(entry, "property", name="kdenlive:id").text = source_ids[path]

        groups.append({"children": group_children[:], "type": "Normal"})
        group_counter += 1

    # default sequence tractor
    sequence = ET.SubElement(
        mlt,
        "tractor",
        attrib={"id": f"{{{seq_uuid}}}", "in": "00:00:00.000", "out": "00:00:00.000"},
    )
    ET.SubElement(sequence, "property", name="kdenlive:uuid").text = f"{{{seq_uuid}}}"
    ET.SubElement(sequence, "property", name="kdenlive:clipname").text = "Sequence 1"
    ET.SubElement(
        sequence, "property", name="kdenlive:sequenceproperties.groups"
    ).text = json.dumps(groups, indent=4)
    ET.SubElement(sequence, "track", producer="producer0")

    for i in range(chains):
        ET.SubElement(sequence, "track", producer=f"tractor{i}")

    # main bin
    playlist_bin = ET.SubElement(mlt, "playlist", id="main_bin")
    ET.SubElement(
        playlist_bin, "property", name="kdenlive:docproperties.uuid"
    ).text = f"{{{seq_uuid}}}"
    ET.SubElement(
        playlist_bin, "property", name="kdenlive:docproperties.version"
    ).text = "1.1"
    ET.SubElement(playlist_bin, "property", name="xml_retain").text = "1"
    ET.SubElement(
        playlist_bin,
        "entry",
        attrib={
            "producer": f"{{{seq_uuid}}}",
            "in": "00:00:00.000",
            "out": "00:00:00.000",
        },
    )
    ET.SubElement(
        playlist_bin,
        "entry",
        attrib={"producer": f"chain{chains}", "in": "00:00:00.000"},
    )

    # reserved last tractor for project
    tractor = ET.SubElement(
        mlt,
        "tractor",
        attrib={"id": f"tractor{chains}", "in": "00:00:00.000", "out": global_out},
    )
    ET.SubElement(tractor, "property", name="kdenlive:projectTractor").text = "1"
    ET.SubElement(
        tractor,
        "track",
        attrib={"producer": f"{{{seq_uuid}}}", "in": "00:00:00.000", "out": global_out},
    )
    tree = ET.ElementTree(mlt)

    ET.indent(tree, space="\t", level=0)

    if output == "-":
        print(ET.tostring(mlt, encoding="unicode"))
    else:
        tree.write(output, xml_declaration=True, encoding="utf-8")
