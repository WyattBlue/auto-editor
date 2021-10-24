'''render/audio.py'''

from auto_editor.utils.func import get_new_length, fnone
from auto_editor.scipy.wavfile import read, write

def convert_audio(ffmpeg, input_path, inp, output_path, codec, log):
    if(fnone(codec)):
        codec = inp.audio_streams[0]['codec']

    ffmpeg.run(['-i', input_path, '-acodec', codec, output_path])

def handle_audio(ffmpeg, input_path, bitrate, samplerate, temp, log):
    # type: (...) -> str
    import os.path
    temp_file = os.path.join(temp, 'faAudio.wav')

    log.checkType(samplerate, 'samplerate', str)
    cmd = ['-i', input_path]
    if(not fnone(bitrate)):
        cmd.extend(['-b:a', bitrate])
    cmd.extend(['-ac', '2', '-ar', samplerate, '-vn', temp_file])

    ffmpeg.run(cmd)
    log.conwrite('')

    return temp_file

def make_new_audio(input_path, output_path, chunks, speeds, log, fps, progress):
    import numpy as np

    def custom_speeds(a):
        # type: (list[int | float]) -> bool
        return len([x for x in a if x != 1 and x != 99999]) > 0

    if(custom_speeds(speeds)):
        from audiotsm2 import phasevocoder
        from audiotsm2.io.array import ArrReader, ArrWriter

    if(len(chunks) == 1 and chunks[0][2] == 0):
        log.error('Trying to create an empty file.')

    samplerate, audio_samples = read(input_path)

    # Get the new length in samples with some extra leeway.
    new_length = get_new_length(chunks, speeds, fps)
    estimated_length = int(new_length * samplerate * 1.5) + int(samplerate * 2)

    # Create an empty array for the new audio.
    new_audio = np.zeros((estimated_length, 2), dtype=np.int16)

    channels = 2
    y_pointer = 0

    progress.start(len(chunks), 'Creating new audio')

    for c, chunk in enumerate(chunks):
        sample_start = int(chunk[0] / fps * samplerate)
        sample_end = int(sample_start + (samplerate / fps) * (chunk[1] - chunk[0]))

        the_speed = speeds[chunk[2]]
        if(the_speed != 99999):
            sped_chunk = audio_samples[sample_start:sample_end]

            if(the_speed == 1):
                y_end_pointer = y_pointer + sped_chunk.shape[0]
                new_audio[y_pointer:y_end_pointer] = sped_chunk
            else:
                spedup_audio = np.zeros((0, 2), dtype=np.int16)
                with ArrReader(sped_chunk, channels, samplerate, 2) as reader:
                    with ArrWriter(spedup_audio, channels, samplerate, 2) as writer:
                        phasevocoder(reader.channels, speed=the_speed).run(
                            reader, writer
                        )
                        spedup_audio = writer.output

                y_end_pointer = y_pointer + spedup_audio.shape[0]
                new_audio[y_pointer:y_end_pointer] = spedup_audio

            my_samples = ((chunk[1] - chunk[0]) / fps) * samplerate
            new_samples = int(my_samples / the_speed)

            y_pointer = y_pointer + new_samples
        else:
            # Speed is too high so skip this section.
            y_end_pointer = y_pointer

        progress.tick(c)
    progress.end()

    log.debug('Total Samples: {}'.format(y_pointer))
    log.debug('Samples per Frame: {}'.format(samplerate / fps))
    log.debug('Expected video length: {}'.format(y_pointer / (samplerate / fps)))
    new_audio = new_audio[:y_pointer]
    write(output_path, samplerate, new_audio)
