import wave

import numpy as np

from auto_editor.wavfile import read
from auto_editor.render.tsm import phasevocoder, ArrReader, ArrWriter
from auto_editor.utils.log import Log
from auto_editor.utils.progressbar import ProgressBar

from typing import List, Tuple


def make_new_audio(
    input_path: str,
    output_path: str,
    chunks: List[Tuple[int, int, float]],
    log: Log,
    fps: float,
    progress: ProgressBar,
) -> None:

    if len(chunks) == 1 and chunks[0][2] == 99999:
        log.error("Trying to create an empty file.")

    progress.start(len(chunks), "Creating new audio")

    samplerate, audio_samples = read(input_path)

    main_writer = wave.open(output_path, "wb")
    main_writer.setnchannels(2)
    main_writer.setframerate(samplerate)
    main_writer.setsampwidth(2)

    for c, chunk in enumerate(chunks):
        sample_start = int(chunk[0] / fps * samplerate)
        sample_end = int(sample_start + (samplerate / fps) * (chunk[1] - chunk[0]))

        the_speed = chunk[2]

        if the_speed == 1:
            main_writer.writeframes(audio_samples[sample_start:sample_end])  # type: ignore
        elif the_speed != 99999:
            sped_chunk = audio_samples[sample_start:sample_end]

            reader = ArrReader(sped_chunk)
            writer = ArrWriter(np.zeros((0, 2), dtype=np.int16))

            phasevocoder(2, speed=the_speed).run(reader, writer)
            if writer.output.shape[0] != 0:
                main_writer.writeframes(writer.output)

        progress.tick(c)
    progress.end()
