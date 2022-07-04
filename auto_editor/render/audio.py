import os
import wave
from typing import List

from auto_editor.render.tsm.phasevocoder import phasevocoder
from auto_editor.timeline import Timeline
from auto_editor.utils.log import Log
from auto_editor.utils.progressbar import ProgressBar
from auto_editor.wavfile import read


def make_new_audio(
    timeline: Timeline, progress: ProgressBar, temp: str, log: Log
) -> List[str]:
    samplerate = timeline.samplerate
    fps = timeline.fps
    output = []
    samples = {}

    for l, layer in enumerate(timeline.a):
        progress.start(len(layer), "Creating new audio")

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

            samp_start = int(clip.offset / fps * samplerate)
            samp_end = int((clip.offset + clip.dur) / fps * samplerate)
            if samp_end > len(samp_list):
                samp_end = len(samp_list)

            if clip.speed == 1:
                writer.writeframesraw(samp_list[samp_start:samp_end])  # type: ignore
            else:
                data = phasevocoder(2, clip.speed, samp_list[samp_start:samp_end])
                if data.shape[0] != 0:
                    writer.writeframesraw(data)  # type: ignore

            progress.tick(c)

        writer.close()
        progress.end()

    return output
