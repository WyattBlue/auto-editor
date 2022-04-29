import sys
import json
import os.path

from typing import Dict, Union, Any

import av

av.logging.set_level(av.logging.PANIC)


def info_options(parser):
    parser.add_argument("--json", flag=True, help="Export info in JSON format.")
    parser.add_argument(
        "--include-vfr",
        "--has-vfr",
        flag=True,
        help="Display the number of Variable Frame Rate (VFR) frames.",
    )
    parser.add_argument("--ffmpeg-location", help="Point to your custom ffmpeg file.")
    parser.add_argument(
        "--my-ffmpeg",
        flag=True,
        help="Use the ffmpeg on your PATH instead of the one packaged.",
    )
    parser.add_required(
        "input", nargs="*", help="The path to a file you want inspected."
    )
    return parser


def main(sys_args=sys.argv[1:]):
    from auto_editor.utils.log import Log
    from auto_editor.utils.func import aspect_ratio
    from auto_editor.vanparse import ArgumentParser
    from auto_editor.ffwrapper import FFmpeg, FileInfo

    parser = info_options(ArgumentParser("info"))
    args = parser.parse_args(sys_args)

    ffmpeg = FFmpeg(args.ffmpeg_location, args.my_ffmpeg, False)

    file_info: Dict[str, Union[List[Dict[str, Any]], Dict[str, Any]]] = {}

    for file in args.input:
        if not os.path.isfile(file):
            Log().error(f"Could not find file: {file}")

        inp = FileInfo(file, ffmpeg, Log())

        if len(inp.videos) + len(inp.audios) + len(inp.subtitles) == 0:
            file_info[file] = {"media": "invalid"}
            continue

        file_info[file] = {
            "video": [],
            "audio": [],
            "subtitle": [],
            "container": {},
        }

        container = av.open(file, "r")

        for track, stream in enumerate(inp.videos):
            pix_fmt = container.streams.video[track].pix_fmt
            time_base = str(container.streams.video[track].time_base)
            cc_time_base = str(container.streams.video[track].codec_context.time_base)
            w, h = stream.width, stream.height
            w_, h_ = aspect_ratio(w, h)

            fps = stream.fps
            if fps is not None and int(fps) == float(fps):
                fps = int(fps)

            vid = {
                "codec": stream.codec,
                "pix_fmt": pix_fmt,
                "fps": fps,
                "resolution": [w, h],
                "aspect ratio": [w_, h_],
                "timebase": time_base,
                "cc timebase": cc_time_base,
                "bitrate": stream.bitrate,
                "lang": stream.lang,
            }
            file_info[file]["video"].append(vid)

        for track, stream in enumerate(inp.audios):
            aud = {
                "codec": stream.codec,
                "samplerate": stream.samplerate,
                "bitrate": stream.bitrate,
                "lang": stream.lang,
            }
            file_info[file]["audio"].append(aud)

        for track, stream in enumerate(inp.subtitles):
            sub = {"codec": stream.codec, "lang": stream.lang}
            file_info[file]["subtitle"].append(sub)

        cont = {"duration": inp.duration, "bitrate": inp.bitrate}

        if args.include_vfr:
            fps_mode = ffmpeg.pipe(
                [
                    "-i",
                    file,
                    "-hide_banner",
                    "-vf",
                    "vfrdet",
                    "-an",
                    "-f",
                    "null",
                    "-",
                ]
            ).strip()
            if "VFR:" in fps_mode:
                fps_mode = (fps_mode[fps_mode.index("VFR:") :]).strip()

            cont["fps_mode"] = fps_mode

        file_info[file]["container"] = cont

    if args.json:
        print(json.dumps(file_info, indent=4))
        return

    def stream_to_text(text: str, label: str, streams) -> str:
        if len(streams) > 0:
            text += f" - {label}:\n"

        for s, stream in enumerate(streams):
            text += f"   - track {s}:\n"
            for key, value in stream.items():
                if value is not None:
                    if isinstance(value, list):
                        sep = "x" if key == "resolution" else ":"
                        value = sep.join([str(x) for x in value])

                    text += f"     - {key}: {value}\n"
        return text

    text = ""
    for name, info in file_info.items():
        text += f"{name}:\n"
        if "media" in info:
            text += " - invalid media\n\n"
            continue

        for label, streams in info.items():
            if isinstance(streams, dict):
                text += f" - container:\n"
                for key, value in streams.items():
                    text += f"   - {key}: {value}\n"
            else:
                text = stream_to_text(text, label, streams)
        text += "\n"

    sys.stdout.write(text)


if __name__ == "__main__":
    main()
