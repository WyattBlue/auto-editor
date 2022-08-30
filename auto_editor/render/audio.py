from __future__ import annotations

import os

import numpy as np

from auto_editor.ffwrapper import FFmpeg
from auto_editor.output import Ensure
from auto_editor.timeline import Timeline
from auto_editor.utils.bar import Bar
from auto_editor.utils.log import Log
from auto_editor.wavfile import AudioData, read, write


def make_new_audio(
    timeline: Timeline, ensure: Ensure, ffmpeg: FFmpeg, bar: Bar, temp: str, log: Log
) -> list[str]:
    sr = timeline.samplerate
    tb = timeline.timebase
    output = []
    samples = {}

    if len(timeline.a) == 0 or len(timeline.a[0]) == 0:
        log.error("Trying to render empty audio timeline")

    for l, layer in enumerate(timeline.a):
        bar.start(len(layer), "Creating new audio")

        path = os.path.join(temp, f"new{l}.wav")
        output.append(path)
        arr: AudioData | None = None

        for c, clip in enumerate(layer):
            if f"{clip.src}-{clip.stream}" not in samples:
                audio_path = ensure.audio(
                    timeline.inputs[clip.src].path, clip.src, clip.stream
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

            if clip.speed == 1:
                clip_arr = samp_list[samp_start:samp_end]
            else:
                tsm = os.path.join(temp, "tsm.wav")
                tsm_out = os.path.join(temp, "tsm_out.wav")

                write(tsm, sr, samp_list[samp_start:samp_end])

                cmd = ["-i", tsm, "-af"]

                if clip.speed > 10_000:
                    atempo = ",".join([f"atempo={clip.speed}^.33333"] * 3)
                elif clip.speed > 100:
                    atempo = f"atempo=sqrt({clip.speed}),atempo=sqrt({clip.speed})"
                elif clip.speed >= 0.5:
                    atempo = f"atempo={clip.speed}"
                else:
                    start = 0.5
                    m = []
                    while start * 0.5 > clip.speed:
                        start *= 0.5
                        m.append("atempo=0.5")
                    m.append(f"atempo={clip.speed / start}")
                    atempo = ",".join(m)

                cmd.extend([atempo, tsm_out])
                ffmpeg.run(cmd)

                clip_arr = read(tsm_out)[1]

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
