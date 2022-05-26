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
        samplerate, s = read(os.path.join(temp, f"{x}-{t}.wav"))
        samples.append(s)

    assert samplerate != 0

    progress.start(len(clips), "Creating new audio")
    fps = timeline.fps

    main_writer = wave.open(os.path.join(temp, f"new{t}.wav"), "wb")
    main_writer.setnchannels(2)
    main_writer.setframerate(samplerate)
    main_writer.setsampwidth(2)

    for c, clip in enumerate(clips):
        sample_start = int(clip.offset / fps * samplerate)
        sample_end = int((clip.offset + clip.dur) / fps * samplerate)

        samp_list = samples[clip.src]

        if sample_end > len(samp_list):
            sample_end = len(samp_list)

        if clip.speed == 1:
            main_writer.writeframes(samp_list[sample_start:sample_end])  # type: ignore
        else:
            output = phasevocoder(2, clip.speed, samp_list[sample_start:sample_end])
            if output.shape[0] != 0:
                main_writer.writeframes(output)  # type: ignore

        progress.tick(c)
    progress.end()
