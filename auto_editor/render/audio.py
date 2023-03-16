from __future__ import annotations

import json
from pathlib import Path
from platform import system
from subprocess import PIPE

import numpy as np

from auto_editor.ffwrapper import FFmpeg
from auto_editor.interpreter import env
from auto_editor.lib.contracts import Contract, andc, is_int_or_float
from auto_editor.objs.util import ParserError, parse_with_palet, smallAttr, smallAttrs
from auto_editor.output import Ensure
from auto_editor.timeline import v3
from auto_editor.utils.bar import Bar
from auto_editor.utils.log import Log
from auto_editor.utils.types import Args
from auto_editor.wavfile import AudioData, read, write

i_range = Contract("i-range", lambda i: i >= -70 and i <= -5)  # type: ignore
lra_range = Contract("lra-range", lambda i: i >= 1 and i <= 50)  # type: ignore
tp_range = Contract("tp-range", lambda i: i >= -9 and i <= 0)  # type: ignore
gain_range = Contract("gain-range", lambda i: i >= -99 and i <= 99)  # type: ignore

ebu_builder = smallAttrs(
    "ebu",
    smallAttr("i", -24.0, andc(is_int_or_float, i_range)),
    smallAttr("lra", 7.0, andc(is_int_or_float, lra_range)),
    smallAttr("tp", -2.0, andc(is_int_or_float, tp_range)),
    smallAttr("gain", 0.0, andc(is_int_or_float, gain_range)),
)

norm_types = {
    "ebu": ebu_builder,
}

file_null = "NUL" if system() in ("Windows", "cli") else "/dev/null"


def parse_norm(norm: str, log: Log) -> dict | None:
    if norm == "#f":
        return None

    exploded = norm.split(":", 1)
    norm_type = exploded[0]
    attrs = "" if len(exploded) == 1 else exploded[1]

    obj = norm_types.get(norm_type, None)
    if obj is None:
        log.error(f"Unknown audio normalize object: '{norm_type}'")

    try:
        return parse_with_palet(attrs, obj, env)
    except ParserError as e:
        log.error(e)


def apply_audio_normalization(
    ffmpeg: FFmpeg, norm: dict, pre_master: Path, path: Path, log: Log
) -> None:
    first_loudnorm = (
        f"[0]loudnorm=i={norm['i']}:lra={norm['lra']}:tp={norm['tp']}:"
        f"offset={norm['gain']}:print_format=json"
    )
    log.debug(f"loudnorm first pass: {first_loudnorm}")
    stderr = ffmpeg.Popen(
        [
            "-hide_banner",
            "-i",
            f"{pre_master}",
            "-filter_complex",
            first_loudnorm,
            "-vn",
            "-sn",
            "-f",
            "null",
            file_null,
        ],
        stdin=PIPE,
        stdout=PIPE,
        stderr=PIPE,
    ).communicate()[1]

    start = end = 0
    lines = stderr.splitlines()

    for index, line in enumerate(lines):
        if line.startswith(b"[Parsed_loudnorm"):
            start = index + 1
            continue
        if start != 0 and line.startswith(b"}"):
            end = index + 1
            break

    print(stderr)
    try:
        parsed = json.loads(b"\n".join(lines[start:end]))
    except json.decoder.JSONDecodeError as e:
        print(start, end)
        raise e

    for key in (
        "input_i",
        "input_tp",
        "input_lra",
        "input_thresh",
        "target_offset",
    ):
        val = float(parsed[key])
        if val == float("-inf"):
            parsed[key] = -99
        elif val == float("inf"):
            parsed[key] = 0
        else:
            parsed[key] = val

    log.debug(f"{parsed}")
    m_i = parsed["input_i"]
    m_tp = parsed["input_tp"]
    m_lra = parsed["input_lra"]
    m_thresh = parsed["input_thresh"]
    target_offset = parsed["target_offset"]

    ffmpeg.run(
        [
            "-i",
            f"{pre_master}",
            "-filter_complex",
            f"[0]loudnorm=i={norm['i']}:lra={norm['lra']}:tp={norm['tp']}:offset={target_offset}"
            f":measured_i={m_i}:measured_lra={m_lra}:measured_tp={m_tp}"
            f":measured_thresh={m_thresh}:linear=true:print_format=json[norm1]",
            "-map",
            "[norm1]",
            "-c:a:0",
            "pcm_s16le",
            f"{path}",
        ]
    )


def make_new_audio(
    tl: v3, ensure: Ensure, args: Args, ffmpeg: FFmpeg, bar: Bar, temp: str, log: Log
) -> list[str]:
    sr = tl.sr
    tb = tl.tb
    output = []
    samples = {}

    norm = parse_norm(args.audio_normalize, log)

    af_tick = 0

    if not tl.a or not tl.a[0]:
        log.error("Trying to render empty audio timeline")

    for l, layer in enumerate(tl.a):
        bar.start(len(layer), "Creating new audio")

        path = Path(temp, f"new{l}.wav")
        output.append(f"{path}")
        arr: AudioData | None = None

        for c, clip in enumerate(layer):
            if f"{clip.src}-{clip.stream}" not in samples:
                audio_path = ensure.audio(
                    f"{tl.sources[clip.src].path.resolve()}",
                    clip.src,
                    clip.stream,
                )
                samples[f"{clip.src}-{clip.stream}"] = read(audio_path)[1]

            if arr is None:
                leng = max(
                    round(
                        (layer[-1].start + (layer[-1].dur / layer[-1].speed)) * sr / tb
                    ),
                    sr // tb,
                )

                dtype = np.int32
                for _samp_arr in samples.values():
                    dtype = _samp_arr.dtype
                    break

                arr = np.memmap(
                    Path(temp, "asdf.map"),
                    mode="w+",
                    dtype=dtype,
                    shape=(leng, 2),
                )
                del leng

            samp_list = samples[f"{clip.src}-{clip.stream}"]

            samp_start = clip.offset * sr // tb
            samp_end = (clip.offset + clip.dur) * sr // tb
            if samp_end > len(samp_list):
                samp_end = len(samp_list)

            filters: list[str] = []

            if clip.speed != 1:
                if clip.speed > 10_000:
                    filters.extend([f"atempo={clip.speed}^.33333"] * 3)
                elif clip.speed > 100:
                    filters.extend(
                        [f"atempo=sqrt({clip.speed})", f"atempo=sqrt({clip.speed})"]
                    )
                elif clip.speed >= 0.5:
                    filters.append(f"atempo={clip.speed}")
                else:
                    start = 0.5
                    while start * 0.5 > clip.speed:
                        start *= 0.5
                        filters.append("atempo=0.5")
                    filters.append(f"atempo={clip.speed / start}")

            if clip.volume != 1:
                filters.append(f"volume={clip.volume}")

            if not filters:
                clip_arr = samp_list[samp_start:samp_end]
            else:
                af = Path(temp, f"af{af_tick}.wav")
                af_out = Path(temp, f"af{af_tick}_out.wav")

                # Windows can't replace a file that's already in use, so we have to
                # cycle through file names.
                af_tick = (af_tick + 1) % 3

                with open(af, "wb") as fid:
                    write(fid, sr, samp_list[samp_start:samp_end])

                ffmpeg.run(["-i", f"{af}", "-af", ",".join(filters), f"{af_out}"])
                clip_arr = read(f"{af_out}")[1]

            # Mix numpy arrays
            start = clip.start * sr // tb
            car_len = clip_arr.shape[0]

            if start + car_len > len(arr):
                # Clip 'clip_arr' if bigger than expected.
                arr[start:] += clip_arr[: len(arr) - start]
            else:
                arr[start : start + car_len] += clip_arr

            bar.tick(c)

        if arr is not None:
            if norm is None:
                with open(path, "wb") as fid:
                    write(fid, sr, arr)
            else:
                pre_master = Path(temp, "premaster.wav")
                with open(pre_master, "wb") as fid:
                    write(fid, sr, arr)

                apply_audio_normalization(ffmpeg, norm, pre_master, path, log)

        bar.end()

    Path(temp, "asdf.map").unlink(missing_ok=True)

    return output
