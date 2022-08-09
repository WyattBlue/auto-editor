from __future__ import annotations

import os
import wave

from auto_editor.timeline import Timeline
from auto_editor.utils.bar import Bar
from auto_editor.utils.log import Log
from auto_editor.wavfile import read
from auto_editor.ffwrapper import FFmpeg


def make_new_audio(
    timeline: Timeline, ffmpeg: FFmpeg, bar: Bar, temp: str, log: Log
) -> list[str]:
    samplerate = timeline.samplerate
    tb = timeline.timebase
    output = []
    samples = {}

    for l, layer in enumerate(timeline.a):
        bar.start(len(layer), "Creating new audio")

        # See: https://github.com/python/cpython/blob/3.10/Lib/wave.py
        path = os.path.join(temp, f"new{l}.wav")
        output.append(path)
        writer = wave.open(path, "wb")
        writer.setnchannels(2)
        writer.setframerate(samplerate)
        writer.setsampwidth(2)

        for c, clip in enumerate(layer):
            if f"{clip.src}-{clip.stream}" not in samples:
                audio_path = os.path.join(temp, f"{clip.src}-{clip.stream}.wav")
                assert os.path.exists(audio_path), f"{audio_path} Not found"
                samples[f"{clip.src}-{clip.stream}"] = read(audio_path)[1]

            samp_list = samples[f"{clip.src}-{clip.stream}"]

            samp_start = clip.offset * samplerate // tb
            samp_end = (clip.offset + clip.dur) * samplerate // tb
            if samp_end > len(samp_list):
                samp_end = len(samp_list)

            if clip.speed == 1:
                writer.writeframesraw(samp_list[samp_start:samp_end])  # type: ignore
            else:
                tsm = os.path.join(temp, "tsm.wav")
                tsm_out = os.path.join(temp, "tsm_out.wav")

                writer2 = wave.open(tsm, "wb")
                writer2.setnchannels(2)
                writer2.setframerate(samplerate)
                writer2.setsampwidth(2)
                writer2.writeframes(samp_list[samp_start:samp_end])  # type: ignore
                writer2.close()
                del writer2

                cmd = ["-hide_banner", "-y", "-i", tsm, "-af"]

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

                tsm_samps = read(tsm_out)[1]
                if tsm_samps.shape[0] != 0:
                    writer.writeframesraw(tsm_samps)  # type:ignore
                del tsm_samps

            bar.tick(c)

        writer.close()
        bar.end()

    return output
