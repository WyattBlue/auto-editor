'''render/audio.py'''

from auto_editor.scipy.wavfile import read

from auto_editor.audiotsm2 import phasevocoder
from auto_editor.audiotsm2.io.array import ArrReader, ArrWriter
from auto_editor.audiotsm2.io.wav import WavWriter

import numpy as np

def make_new_audio(input_path, output_path, chunks, log, fps, progress):

    if(len(chunks) == 1 and chunks[0][2] == 0):
        log.error('Trying to create an empty file.')

    samplerate, audio_samples = read(input_path)

    channels = 2
    samplewidth = 2

    progress.start(len(chunks), 'Creating new audio')

    with WavWriter(output_path, 2, samplerate) as main_writer:
        for c, chunk in enumerate(chunks):
            sample_start = int(chunk[0] / fps * samplerate)
            sample_end = int(sample_start + (samplerate / fps) * (chunk[1] - chunk[0]))

            the_speed = chunk[2]

            if(the_speed == 1):
                main_writer.write(audio_samples[sample_start:sample_end].T / 32676)
            elif(the_speed != 99999):
                sped_chunk = audio_samples[sample_start:sample_end]
                spedup_audio = np.zeros((0, 2), dtype=np.int16)
                with ArrReader(sped_chunk, channels, samplerate, samplewidth) as reader:
                    with ArrWriter(spedup_audio, channels, samplerate, samplewidth) as writer:
                        phasevocoder(reader.channels, speed=the_speed).run(
                            reader, writer
                        )
                        spedup_audio = writer.output
                        main_writer.write(spedup_audio.T / 32676)

            progress.tick(c)
        progress.end()
