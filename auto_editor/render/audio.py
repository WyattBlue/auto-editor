import wave

import numpy as np

from auto_editor.scipy.wavfile import read

from auto_editor.audiotsm2 import phasevocoder
from auto_editor.audiotsm2.io.array import ArrReader, ArrWriter

from auto_editor.utils.log import Log
from auto_editor.utils.progressbar import ProgressBar
from typing import List, Tuple

def make_new_audio(
    input_path: str,
    output_path: str,
    chunks: List[Tuple[int, int, float]],
    log: Log,
    fps: float,
    progress: ProgressBar
) -> None:

    if len(chunks) == 1 and chunks[0][2] == 99999:
        log.error('Trying to create an empty file.')

    samplerate, audio_samples = read(input_path)

    channels = 2
    samplewidth = 2

    progress.start(len(chunks), 'Creating new audio')


    def write(writer, buffer):
        np.clip(buffer, -1, 1, out=buffer)

        frames = (buffer.T.reshape((-1,)) * 32676).astype(np.int16).tobytes()
        writer.writeframes(frames)
        del frames

    main_writer = wave.open(output_path, 'wb')
    main_writer.setnchannels(2)
    main_writer.setframerate(samplerate)
    main_writer.setsampwidth(2)

    for c, chunk in enumerate(chunks):
        sample_start = int(chunk[0] / fps * samplerate)
        sample_end = int(sample_start + (samplerate / fps) * (chunk[1] - chunk[0]))

        the_speed = chunk[2]

        if the_speed == 1:
            write(main_writer, audio_samples[sample_start:sample_end].T / 32676)
        elif the_speed != 99999:
            sped_chunk = audio_samples[sample_start:sample_end]
            spedup_audio = np.zeros((0, 2), dtype=np.int16)
            with ArrReader(sped_chunk, channels, samplerate, samplewidth) as reader:
                with ArrWriter(spedup_audio, channels, samplerate, samplewidth) as writer:
                    phasevocoder(reader.channels, speed=the_speed).run(
                        reader, writer
                    )
                    spedup_audio = writer.output
                    write(main_writer, spedup_audio.T / 32676)

        progress.tick(c)
    progress.end()
