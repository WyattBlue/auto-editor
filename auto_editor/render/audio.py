from __future__ import annotations

import io
from pathlib import Path
from platform import system
from subprocess import PIPE

import av
import numpy as np

from auto_editor.ffwrapper import FFmpeg, FileInfo
from auto_editor.lang.json import Lexer, Parser
from auto_editor.lang.palet import env
from auto_editor.lib.contracts import andc, between_c, is_int_or_float
from auto_editor.lib.err import MyError
from auto_editor.output import Ensure
from auto_editor.timeline import TlAudio, v3
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


def parse_ebu_bytes(norm: dict, stderr: bytes, log: Log) -> tuple[str, str]:
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

    for key in ("input_i", "input_tp", "input_lra", "input_thresh", "target_offset"):
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

    filter = (
        f"i={norm['i']}:lra={norm['lra']}:tp={norm['tp']}:offset={target_offset}"
        f":measured_i={m_i}:measured_lra={m_lra}:measured_tp={m_tp}"
        f":measured_thresh={m_thresh}:linear=true:print_format=json"
    )
    return "loudnorm", filter


def apply_audio_normalization(
    ffmpeg: FFmpeg, norm: dict, pre_master: Path, path: Path, log: Log
) -> None:
    if norm["tag"] == "ebu":
        first_pass = (
            f"loudnorm=i={norm['i']}:lra={norm['lra']}:tp={norm['tp']}:"
            f"offset={norm['gain']}:print_format=json"
        )
        log.debug(f"audio norm first pass: {first_pass}")
        file_null = "NUL" if system() in ("Windows", "cli") else "/dev/null"
        cmd = [
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
        ]
        process = ffmpeg.Popen(cmd, stdin=PIPE, stdout=PIPE, stderr=PIPE)
        stderr = process.communicate()[1]
        name, filter_args = parse_ebu_bytes(norm, stderr, log)
    else:
        assert "t" in norm

        def get_peak_level(frame: av.AudioFrame) -> float:
            # Calculate peak level in dB
            # Should be equivalent to: -af astats=measure_overall=Peak_level:measure_perchannel=0
            max_amplitude = np.abs(frame.to_ndarray()).max()
            if max_amplitude > 0.0:
                return -20.0 * np.log10(max_amplitude)
            return -99.0

        with av.open(pre_master) as container:
            max_peak_level = -99.0
            assert len(container.streams.video) == 0
            for frame in container.decode(audio=0):
                peak_level = get_peak_level(frame)
                max_peak_level = max(max_peak_level, peak_level)

        adjustment = norm["t"] - max_peak_level
        log.debug(f"current peak level: {max_peak_level}")
        log.print(f"peak adjustment: {adjustment:.3f}dB")
        name, filter_args = "volume", f"{adjustment}"

    with av.open(pre_master) as container:
        input_stream = container.streams.audio[0]

        output_file = av.open(path, mode="w")
        output_stream = output_file.add_stream("pcm_s16le", rate=input_stream.rate)

        graph = av.filter.Graph()
        graph.link_nodes(
            graph.add_abuffer(template=input_stream),
            graph.add(name, filter_args),
            graph.add("abuffersink"),
        ).configure()
        for frame in container.decode(input_stream):
            graph.push(frame)
            while True:
                try:
                    aframe = graph.pull()
                    assert isinstance(aframe, av.AudioFrame)
                    output_file.mux(output_stream.encode(aframe))
                except (av.BlockingIOError, av.EOFError):
                    break

        output_file.mux(output_stream.encode(None))
        output_file.close()


def process_audio_clip(
    clip: TlAudio, samp_list: AudioData, samp_start: int, samp_end: int, sr: int
) -> AudioData:
    input_buffer = io.BytesIO()
    write(input_buffer, sr, samp_list[samp_start:samp_end])
    input_buffer.seek(0)

    input_file = av.open(input_buffer, "r")
    input_stream = input_file.streams.audio[0]

    output_bytes = io.BytesIO()
    output_file = av.open(output_bytes, mode="w", format="wav")
    output_stream = output_file.add_stream("pcm_s16le", rate=sr)

    graph = av.filter.Graph()
    args = [graph.add_abuffer(template=input_stream)]

    if clip.speed != 1:
        if clip.speed > 10_000:
            for _ in range(3):
                args.append(graph.add("atempo", f"{clip.speed ** (1/3)}"))
        elif clip.speed > 100:
            for _ in range(2):
                args.append(graph.add("atempo", f"{clip.speed ** 0.5}"))
        elif clip.speed >= 0.5:
            args.append(graph.add("atempo", f"{clip.speed}"))
        else:
            start = 0.5
            while start * 0.5 > clip.speed:
                start *= 0.5
                args.append(graph.add("atempo", "0.5"))
            args.append(graph.add("atempo", f"{clip.speed / start}"))

    if clip.volume != 1:
        args.append(graph.add("volume", f"{clip.volume}"))

    args.append(graph.add("abuffersink"))
    graph.link_nodes(*args).configure()

    for frame in input_file.decode(input_stream):
        graph.push(frame)
        while True:
            try:
                aframe = graph.pull()
                assert isinstance(aframe, av.AudioFrame)
                output_file.mux(output_stream.encode(aframe))
            except (av.BlockingIOError, av.EOFError):
                break

    # Flush the stream
    output_file.mux(output_stream.encode(None))

    input_file.close()
    output_file.close()

    output_bytes.seek(0)
    has_filesig = output_bytes.read(4)
    output_bytes.seek(0)
    if not has_filesig:  # Can rarely happen when clip is extremely small
        return np.empty((0, 2), dtype=np.int16)

    return read(output_bytes)[1]


def make_new_audio(
    tl: v3, ensure: Ensure, args: Args, ffmpeg: FFmpeg, bar: Bar, log: Log
) -> list[str]:
    sr = tl.sr
    tb = tl.tb
    output = []
    samples: dict[tuple[FileInfo, int], AudioData] = {}

    norm = parse_norm(args.audio_normalize, log)

    temp = log.temp

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
                with open(audio_path, "rb") as file:
                    samples[(clip.src, clip.stream)] = read(file)[1]

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

            if clip.speed != 1 or clip.volume != 1:
                clip_arr = process_audio_clip(clip, samp_list, samp_start, samp_end, sr)
            else:
                clip_arr = samp_list[samp_start:samp_end]

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
