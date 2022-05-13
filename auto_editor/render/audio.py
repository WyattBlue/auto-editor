import wave
from typing import List

import numpy as np

from auto_editor.objects import AudioObj
from auto_editor.render.tsm import ArrReader, ArrWriter, phasevocoder
from auto_editor.utils.log import Log
from auto_editor.utils.progressbar import ProgressBar
from auto_editor.wavfile import read


def make_new_audio(
    input_path: str,
    output_path: str,
    clips: List[AudioObj],
    fps: float,
    progress: ProgressBar,
    log: Log,
) -> None:

    if len(clips) == 0:
        log.error("Trying to create an empty file.")

    progress.start(len(clips), "Creating new audio")

    samplerate, audio_samples = read(input_path)

    main_writer = wave.open(output_path, "wb")
    main_writer.setnchannels(2)
    main_writer.setframerate(samplerate)
    main_writer.setsampwidth(2)

    for c, clip in enumerate(clips):
        sample_start = int(clip.offset / fps * samplerate)
        sample_end = int((clip.offset + clip.dur) / fps * samplerate)

        if clip.speed == 1:
            main_writer.writeframes(audio_samples[sample_start:sample_end])  # type: ignore
        else:
            sped_chunk = audio_samples[sample_start:sample_end]

            reader = ArrReader(sped_chunk)
            writer = ArrWriter(np.zeros((0, 2), dtype=np.int16))

            phasevocoder(2, speed=clip.speed).run(reader, writer)
            if writer.output.shape[0] != 0:
                main_writer.writeframes(writer.output)

        progress.tick(c)
    progress.end()
