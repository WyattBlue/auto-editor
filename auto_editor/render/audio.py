'''render/audio.py'''

from auto_editor.scipy.wavfile import read

from auto_editor.audiotsm2 import phasevocoder
from auto_editor.audiotsm2.io.array import ArrReader, ArrWriter
from auto_editor.audiotsm2.io.wav import WavWriter

import numpy as np

def make_new_audio(input_path, output_path, chunks, speeds, log, fps, progress):

    if(len(chunks) == 1 and chunks[0][2] == 0):
        log.error('Trying to create an empty file.')

    samplerate, audio_samples = read(input_path)

    channels = 2
    y_pointer = 0

    progress.start(len(chunks), 'Creating new audio')

    with WavWriter(output_path, 2, samplerate) as main_writer:
        for c, chunk in enumerate(chunks):
            sample_start = int(chunk[0] / fps * samplerate)
            sample_end = int(sample_start + (samplerate / fps) * (chunk[1] - chunk[0]))

            the_speed = speeds[chunk[2]]
            if(the_speed != 99999):
                sped_chunk = audio_samples[sample_start:sample_end]

                if(the_speed == 1):
                    y_end_pointer = y_pointer + sped_chunk.shape[0]
                    main_writer.write(sped_chunk.T / 32676)
                else:
                    spedup_audio = np.zeros((0, 2), dtype=np.int16)
                    with ArrReader(sped_chunk, channels, samplerate, 2) as reader:
                        with ArrWriter(spedup_audio, channels, samplerate, 2) as writer:
                            phasevocoder(reader.channels, speed=the_speed).run(
                                reader, writer
                            )
                            spedup_audio = writer.output
                            y_end_pointer = y_pointer + spedup_audio.shape[0]
                            main_writer.write(spedup_audio.T  / 32676)

                my_samples = ((chunk[1] - chunk[0]) / fps) * samplerate
                new_samples = int(my_samples / the_speed)

                y_pointer = y_pointer + new_samples
            else:
                # Completely cut this section.
                y_end_pointer = y_pointer

            progress.tick(c)
        progress.end()
