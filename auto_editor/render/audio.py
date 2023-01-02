from __future__ import annotations

import os

import numpy as np

from auto_editor.ffwrapper import FFmpeg
from auto_editor.output import Ensure
from auto_editor.timeline import v3
from auto_editor.utils.bar import Bar
from auto_editor.utils.log import Log
from auto_editor.wavfile import AudioData, read, write


def make_new_audio(
    tl: v3, ensure: Ensure, ffmpeg: FFmpeg, bar: Bar, temp: str, log: Log
) -> list[str]:
    sr = tl.sr
    tb = tl.tb
    output = []
    samples = {}

    af_tick = 0

    if not tl.a or not tl.a[0]:
        log.error("Trying to render empty audio timeline")

    for l, layer in enumerate(tl.a):
        bar.start(len(layer), "Creating new audio")

        path = os.path.join(temp, f"new{l}.wav")
        output.append(path)
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
                    os.path.join(temp, "asdf.map"),
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
                af = os.path.join(temp, f"af{af_tick}.wav")
                af_out = os.path.join(temp, f"af{af_tick}_out.wav")

                # Windows can't replace a file that's already in use, so we have to
                # cycle through file names.
                af_tick = (af_tick + 1) % 3

                write(af, sr, samp_list[samp_start:samp_end])
                ffmpeg.run(["-i", af, "-af", ",".join(filters), af_out])
                clip_arr = read(af_out)[1]

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
            write(path, sr, arr)
        bar.end()

    try:
        os.remove(os.path.join(temp, "asdf.map"))
    except Exception:
        pass

    return output
