import os
import wave

from auto_editor.render.tsm.phasevocoder import phasevocoder
from auto_editor.timeline import Timeline
from auto_editor.utils.log import Log
from auto_editor.utils.progressbar import ProgressBar
from auto_editor.wavfile import read


def make_new_audio(
    t: int,
    temp: str,
    timeline: Timeline,
    progress: ProgressBar,
    log: Log,
) -> None:

    clips = timeline.a[t]
    if len(clips) == 0:
        log.error("Trying to create an empty file.")

    samples = []
    samplerate = 0
    for x in range(len(timeline.inputs)):
        audio_path = os.path.join(temp, f"{x}-{t}.wav")
        if os.path.exists(audio_path):
            samplerate, s = read(audio_path)
            samples.append(s)

    assert samplerate != 0

    progress.start(len(clips), "Creating new audio")
    fps = timeline.fps

    # See: https://github.com/python/cpython/blob/3.10/Lib/wave.py
    writer = wave.open(os.path.join(temp, f"new{t}.wav"), "wb")
    writer.setnchannels(2)
    writer.setframerate(samplerate)
    writer.setsampwidth(2)

    for c, clip in enumerate(clips):
        samp_list = samples[clip.src]

        samp_start = int(clip.offset / fps * samplerate)
        samp_end = int((clip.offset + clip.dur) / fps * samplerate)
        if samp_end > len(samp_list):
            samp_end = len(samp_list)

        if clip.speed == 1:
            writer.writeframesraw(samp_list[samp_start:samp_end])  # type: ignore
        else:
            output = phasevocoder(2, clip.speed, samp_list[samp_start:samp_end])
            if output.shape[0] != 0:
                writer.writeframesraw(output)  # type: ignore

        progress.tick(c)

    writer.close()
    progress.end()
