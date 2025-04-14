from __future__ import annotations

from fractions import Fraction
from io import BytesIO
from pathlib import Path
from typing import TYPE_CHECKING

import bv
import numpy as np
from bv import AudioFrame
from bv.filter.loudnorm import stats

from auto_editor.ffwrapper import FileInfo
from auto_editor.json import load
from auto_editor.lang.palet import env
from auto_editor.lib.contracts import andc, between_c, is_int_or_float
from auto_editor.lib.err import MyError
from auto_editor.timeline import TlAudio, v3
from auto_editor.utils.cmdkw import ParserError, parse_with_palet, pAttr, pAttrs
from auto_editor.utils.func import parse_bitrate
from auto_editor.utils.log import Log

if TYPE_CHECKING:
    from collections.abc import Iterator
    from typing import Any

    from auto_editor.__main__ import Args

    AudioData = np.ndarray


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


def parse_ebu_bytes(norm: dict, stat: bytes, log: Log) -> tuple[str, str]:
    try:
        parsed = load("loudnorm", stat)
    except MyError:
        log.error(f"Invalid loudnorm stats.\n{stat!r}")

    for key in {"input_i", "input_tp", "input_lra", "input_thresh", "target_offset"}:
        val_ = parsed[key]
        assert isinstance(val_, int | float | str | bytes)
        val = float(val_)
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
    norm: dict, pre_master: Path, path: Path, log: Log
) -> None:
    if norm["tag"] == "ebu":
        first_pass = (
            f"i={norm['i']}:lra={norm['lra']}:tp={norm['tp']}:offset={norm['gain']}"
        )
        log.debug(f"audio norm first pass: {first_pass}")
        with bv.open(f"{pre_master}") as container:
            stats_ = stats(first_pass, container.streams.audio[0])

        name, filter_args = parse_ebu_bytes(norm, stats_, log)
    else:
        assert "t" in norm

        def get_peak_level(frame: AudioFrame) -> float:
            # Calculate peak level in dB
            # Should be equivalent to: -af astats=measure_overall=Peak_level:measure_perchannel=0
            max_amplitude = np.abs(frame.to_ndarray()).max()
            if max_amplitude > 0.0:
                return -20.0 * np.log10(max_amplitude)
            return -99.0

        with bv.open(pre_master) as container:
            max_peak_level = -99.0
            assert len(container.streams.video) == 0
            for frame in container.decode(audio=0):
                peak_level = get_peak_level(frame)
                max_peak_level = max(max_peak_level, peak_level)

        adjustment = norm["t"] - max_peak_level
        log.debug(f"current peak level: {max_peak_level}")
        log.print(f"peak adjustment: {adjustment:.3f}dB")
        name, filter_args = "volume", f"{adjustment}"

    with bv.open(pre_master) as container:
        input_stream = container.streams.audio[0]

        output_file = bv.open(path, mode="w")
        output_stream = output_file.add_stream("pcm_s16le", rate=input_stream.rate)

        graph = bv.filter.Graph()
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
                    assert isinstance(aframe, AudioFrame)
                    output_file.mux(output_stream.encode(aframe))
                except (bv.BlockingIOError, bv.EOFError):
                    break

        output_file.mux(output_stream.encode(None))
        output_file.close()


def process_audio_clip(
    clip: TlAudio, samp_list: AudioData, samp_start: int, samp_end: int, sr: int
) -> np.ndarray:
    to_s16 = bv.AudioResampler(format="s16", layout="stereo", rate=sr)
    input_buffer = BytesIO()

    with bv.open(input_buffer, "w", format="wav") as container:
        output_stream = container.add_stream(
            "pcm_s16le", sample_rate=sr, format="s16", layout="stereo"
        )

        frame = AudioFrame.from_ndarray(
            samp_list[:, samp_start:samp_end], format="s16p", layout="stereo"
        )
        frame.rate = sr

        for reframe in to_s16.resample(frame):
            container.mux(output_stream.encode(reframe))
        container.mux(output_stream.encode(None))

    input_buffer.seek(0)

    input_file = bv.open(input_buffer, "r")
    input_stream = input_file.streams.audio[0]

    graph = bv.filter.Graph()
    args = [graph.add_abuffer(template=input_stream)]

    if clip.speed != 1:
        if clip.speed > 10_000:
            for _ in range(3):
                args.append(graph.add("atempo", f"{clip.speed ** (1 / 3)}"))
        elif clip.speed > 100:
            for _ in range(2):
                args.append(graph.add("atempo", f"{clip.speed**0.5}"))
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

    all_frames = []
    resampler = bv.AudioResampler(format="s16p", layout="stereo", rate=sr)

    for frame in input_file.decode(input_stream):
        graph.push(frame)
        while True:
            try:
                aframe = graph.pull()
                assert isinstance(aframe, AudioFrame)

                for resampled_frame in resampler.resample(aframe):
                    all_frames.append(resampled_frame.to_ndarray())

            except (bv.BlockingIOError, bv.EOFError):
                break

    return np.concatenate(all_frames, axis=1)


def mix_audio_files(sr: int, audio_paths: list[str], output_path: str) -> None:
    mixed_audio = None
    max_length = 0

    # First pass: determine the maximum length
    for path in audio_paths:
        container = bv.open(path)
        stream = container.streams.audio[0]

        # Calculate duration in samples
        assert stream.duration is not None
        assert stream.time_base is not None
        duration_samples = int(stream.duration * sr / stream.time_base.denominator)
        max_length = max(max_length, duration_samples)
        container.close()

    # Second pass: read and mix audio
    for path in audio_paths:
        container = bv.open(path)
        stream = container.streams.audio[0]

        resampler = bv.audio.resampler.AudioResampler(
            format="s16", layout="mono", rate=sr
        )

        audio_array: list[np.ndarray] = []
        for frame in container.decode(audio=0):
            frame.pts = None
            resampled = resampler.resample(frame)[0]
            audio_array.extend(resampled.to_ndarray().flatten())

        # Pad or truncate to max_length
        current_audio = np.array(audio_array[:max_length])
        if len(current_audio) < max_length:
            current_audio = np.pad(
                current_audio, (0, max_length - len(current_audio)), "constant"
            )

        if mixed_audio is None:
            mixed_audio = current_audio.astype(np.float32)
        else:
            mixed_audio += current_audio.astype(np.float32)

        container.close()

    if mixed_audio is None:
        raise ValueError("mixed_audio is None")

    # Normalize the mixed audio
    max_val = np.max(np.abs(mixed_audio))
    if max_val > 0:
        mixed_audio = mixed_audio * (32767 / max_val)
    mixed_audio = mixed_audio.astype(np.int16)  # type: ignore

    output_container = bv.open(output_path, mode="w")
    output_stream = output_container.add_stream("pcm_s16le", rate=sr)

    chunk_size = sr  # Process 1 second at a time
    for i in range(0, len(mixed_audio), chunk_size):
        # Shape becomes (1, samples) for mono
        chunk = np.array([mixed_audio[i : i + chunk_size]])

        frame = AudioFrame.from_ndarray(chunk, format="s16", layout="mono")
        frame.rate = sr
        frame.pts = i  # Set presentation timestamp

        output_container.mux(output_stream.encode(frame))

    output_container.mux(output_stream.encode(None))
    output_container.close()


def file_to_ndarray(src: FileInfo, stream: int, sr: int) -> np.ndarray:
    all_frames = []

    resampler = bv.AudioResampler(format="s16p", layout="stereo", rate=sr)

    with bv.open(src.path) as container:
        for frame in container.decode(audio=stream):
            for resampled_frame in resampler.resample(frame):
                all_frames.append(resampled_frame.to_ndarray())

    return np.concatenate(all_frames, axis=1)


def ndarray_to_file(audio_data: np.ndarray, rate: int, out: str | Path) -> None:
    layout = "stereo"

    with bv.open(out, mode="w") as output:
        stream = output.add_stream("pcm_s16le", rate=rate, format="s16", layout=layout)

        frame = bv.AudioFrame.from_ndarray(audio_data, format="s16p", layout=layout)
        frame.rate = rate

        output.mux(stream.encode(frame))
        output.mux(stream.encode(None))


def ndarray_to_iter(
    audio_data: np.ndarray, fmt: bv.AudioFormat, rate: int
) -> Iterator[AudioFrame]:
    chunk_size = rate // 4  # Process 0.25 seconds at a time

    resampler = bv.AudioResampler(rate=rate, format=fmt, layout="stereo")
    for i in range(0, audio_data.shape[1], chunk_size):
        chunk = audio_data[:, i : i + chunk_size]

        frame = AudioFrame.from_ndarray(chunk, format="s16p", layout="stereo")
        frame.rate = rate
        # frame.time_base = Fraction(1, rate)
        frame.pts = i

        yield from resampler.resample(frame)


def make_new_audio(
    output: bv.container.OutputContainer,
    audio_format: bv.AudioFormat,
    tl: v3,
    args: Args,
    log: Log,
) -> tuple[list[bv.AudioStream], list[Iterator[AudioFrame]]]:
    audio_inputs = []
    audio_gen_frames = []
    audio_streams: list[bv.AudioStream] = []
    audio_paths = _make_new_audio(tl, audio_format, args, log)

    src = tl.src
    assert src is not None

    for i, audio_path in enumerate(audio_paths):
        audio_stream = output.add_stream(
            args.audio_codec,
            rate=tl.sr,
            format=audio_format,
            layout="stereo",
            time_base=Fraction(1, tl.sr),
        )
        if not isinstance(audio_stream, bv.AudioStream):
            log.error(f"Not a known audio codec: {args.audio_codec}")

        if args.audio_bitrate != "auto":
            audio_stream.bit_rate = parse_bitrate(args.audio_bitrate, log)
            log.debug(f"audio bitrate: {audio_stream.bit_rate}")
        else:
            log.debug(f"[auto] audio bitrate: {audio_stream.bit_rate}")
        if i < len(src.audios) and src.audios[i].lang is not None:
            audio_stream.metadata["language"] = src.audios[i].lang  # type: ignore

        audio_streams.append(audio_stream)

        if isinstance(audio_path, str):
            audio_input = bv.open(audio_path)
            audio_inputs.append(audio_input)
            audio_gen_frames.append(audio_input.decode(audio=0))
        else:
            audio_gen_frames.append(audio_path)

    return audio_streams, audio_gen_frames


def _make_new_audio(tl: v3, fmt: bv.AudioFormat, args: Args, log: Log) -> list[Any]:
    sr = tl.sr
    tb = tl.tb
    output: list[Any] = []
    samples: dict[tuple[FileInfo, int], AudioData] = {}

    norm = parse_norm(args.audio_normalize, log)
    temp = log.temp

    if not tl.a[0]:
        log.error("Trying to render empty audio timeline")

    for i, layer in enumerate(tl.a):
        path = Path(temp, f"new{i}.wav")
        arr: AudioData | None = None
        use_iter = False

        for c, clip in enumerate(layer):
            if (clip.src, clip.stream) not in samples:
                log.conwrite("Writing audio to memory")
                samples[(clip.src, clip.stream)] = file_to_ndarray(
                    clip.src, clip.stream, sr
                )

            log.conwrite("Creating audio")
            if arr is None:
                leng = max(round((layer[-1].start + layer[-1].dur) * sr / tb), sr // tb)
                arr = np.zeros(shape=(2, leng), dtype=np.int16)

            samp_list = samples[(clip.src, clip.stream)]

            samp_start = round(clip.offset * clip.speed * sr / tb)
            samp_end = round((clip.offset + clip.dur) * clip.speed * sr / tb)
            if samp_end > samp_list.shape[1]:
                samp_end = samp_list.shape[1]

            if clip.speed != 1 or clip.volume != 1:
                clip_arr = process_audio_clip(clip, samp_list, samp_start, samp_end, sr)
            else:
                clip_arr = samp_list[:, samp_start:samp_end]

            # Mix numpy arrays
            start = clip.start * sr // tb
            clip_samples = clip_arr.shape[1]
            if start + clip_samples > arr.shape[1]:
                # Shorten `clip_arr` if bigger than expected.
                arr[:, start:] += clip_arr[:, : arr.shape[1] - start]
            else:
                arr[:, start : start + clip_samples] += clip_arr

        if arr is not None:
            if norm is None:
                if args.mix_audio_streams:
                    ndarray_to_file(arr, sr, path)
                else:
                    use_iter = True
            else:
                pre_master = Path(temp, "premaster.wav")
                ndarray_to_file(arr, sr, pre_master)
                apply_audio_normalization(norm, pre_master, path, log)

        if use_iter and arr is not None:
            output.append(ndarray_to_iter(arr, fmt, sr))
        else:
            output.append(f"{path}")

    if args.mix_audio_streams and len(output) > 1:
        new_a_file = f"{Path(temp, 'new_audio.wav')}"
        mix_audio_files(sr, output, new_a_file)
        return [new_a_file]

    return output
