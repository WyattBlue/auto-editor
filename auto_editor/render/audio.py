from __future__ import annotations

from pathlib import Path
from platform import system
from subprocess import PIPE

import numpy as np

from auto_editor.ffwrapper import FFmpeg, FileInfo
from auto_editor.lang.json import Lexer, Parser
from auto_editor.lang.palet import env
from auto_editor.lib.contracts import andc, between_c, is_int_or_float
from auto_editor.lib.err import MyError
from auto_editor.output import Ensure
from auto_editor.timeline import v3
from auto_editor.utils.bar import Bar
from auto_editor.utils.cmdkw import ParserError, parse_with_palet, pAttr, pAttrs
from auto_editor.utils.log import Log
from auto_editor.utils.types import Args
from auto_editor.wavfile import AudioData, read, write

norm_types = {
    "ebu": pAttrs(
        "ebu",
        pAttr("i", -24.0, andc(is_int_or_float, between_c(-70, 5))),
        pAttr("lra", 7.0, andc(is_int_or_float, between_c(1, 50))),
        pAttr("tp", -2.0, andc(is_int_or_float, between_c(-9, 0))),
        pAttr("gain", 0.0, andc(is_int_or_float, between_c(-99, 99))),
    ),
    "peak": pAttrs(
        "peak",
        pAttr("t", -8.0, andc(is_int_or_float, between_c(-99, 0))),
    ),
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
        obj_dict = parse_with_palet(attrs, obj, env)
        obj_dict["tag"] = norm_type
        return obj_dict
    except ParserError as e:
        log.error(e)


def parse_ebu_bytes(norm: dict, stderr: bytes, log: Log) -> list[str]:
    start = end = 0
    lines = stderr.splitlines()

    for index, line in enumerate(lines):
        if line.startswith(b"[Parsed_loudnorm"):
            start = index + 1
            continue
        if start != 0 and line.startswith(b"}"):
            end = index + 1
            break

    if start == 0 or end == 0:
        log.error(f"Invalid loudnorm stats.\n{stderr!r}")

    try:
        parsed = Parser(Lexer("loudnorm", b"\n".join(lines[start:end]))).expr()
    except MyError:
        log.error(f"Invalid loudnorm stats.\n{start=},{end=}\n{stderr!r}")

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

    return [
        "-af",
        f"loudnorm=i={norm['i']}:lra={norm['lra']}:tp={norm['tp']}:offset={target_offset}"
        f":measured_i={m_i}:measured_lra={m_lra}:measured_tp={m_tp}"
        f":measured_thresh={m_thresh}:linear=true:print_format=json",
    ]


def parse_peak_bytes(t: float, stderr: bytes, log: Log) -> list[str]:
    peak_level = None
    for line in stderr.splitlines():
        if line.startswith(b"[Parsed_astats_0") and b"Peak level dB:" in line:
            try:
                peak_level = float(line.split(b":")[1])
            except Exception:
                log.error(f"Invalid `astats` stats.\n{stderr!r}")
            break

    if peak_level is None:
        log.error(f"Invalid `astats` stats.\n{stderr!r}")

    adjustment = t - peak_level
    log.debug(f"current peak level: {peak_level}")
    log.print(f"peak adjustment: {adjustment}")
    return ["-af", f"volume={adjustment}"]


def apply_audio_normalization(
    ffmpeg: FFmpeg, norm: dict, pre_master: Path, path: Path, log: Log
) -> None:
    if norm["tag"] == "ebu":
        first_pass = (
            f"loudnorm=i={norm['i']}:lra={norm['lra']}:tp={norm['tp']}:"
            f"offset={norm['gain']}:print_format=json"
        )
    else:
        first_pass = "astats=measure_overall=Peak_level:measure_perchannel=0"

    log.debug(f"audio norm first pass: {first_pass}")

    stderr = ffmpeg.Popen(
        [
            "-hide_banner",
            "-i",
            f"{pre_master}",
            "-af",
            first_pass,
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

    if norm["tag"] == "ebu":
        cmd = parse_ebu_bytes(norm, stderr, log)
    else:
        assert "t" in norm
        cmd = parse_peak_bytes(norm["t"], stderr, log)

    ffmpeg.run(["-i", f"{pre_master}"] + cmd + [f"{path}"])


def make_new_audio(
    tl: v3, ensure: Ensure, args: Args, ffmpeg: FFmpeg, bar: Bar, temp: str, log: Log
) -> list[str]:
    sr = tl.sr
    tb = tl.tb
    output = []
    samples: dict[tuple[FileInfo, int], AudioData] = {}

    norm = parse_norm(args.audio_normalize, log)

    af_tick = 0

    if not tl.a or not tl.a[0]:
        log.error("Trying to render empty audio timeline")

    for i, layer in enumerate(tl.a):
        bar.start(len(layer), "Creating new audio")

        path = Path(temp, f"new{i}.wav")
        output.append(f"{path}")
        arr: AudioData | None = None

        for c, clip in enumerate(layer):
            if (clip.src, clip.stream) not in samples:
                audio_path = ensure.audio(clip.src, clip.stream)
                samples[(clip.src, clip.stream)] = read(audio_path)[1]

            if arr is None:
                leng = max(round((layer[-1].start + layer[-1].dur) * sr / tb), sr // tb)
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

            samp_list = samples[(clip.src, clip.stream)]
            samp_start = round(clip.offset * clip.speed * sr / tb)
            samp_end = round((clip.offset + clip.dur) * clip.speed * sr / tb)
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

    try:
        Path(temp, "asdf.map").unlink(missing_ok=True)
    except PermissionError:
        pass
    return output
