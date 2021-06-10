'''fastAudio.py'''

import os

from auto_editor.utils.func import get_new_length, fnone
from auto_editor.utils.progressbar import ProgressBar
from auto_editor.scipy.wavfile import read, write

def convertAudio(ffmpeg, in_file, inp, out_file, codec, log):
    if(fnone(codec)):
        codec = inp.audio_streams[0]['codec']
    if(codec == 'pcm_s16le' and out_file.endswith('.m4a')):
        log.error('Codec: {} is not supported in the m4a container.'.format(codec))

    ffmpeg.run(['-i', in_file, '-acodec', codec, out_file])

def handleAudio(ffmpeg, in_file, audioBit, samplerate: str, temp, log) -> str:
    temp_file = os.path.join(temp, 'faAudio.wav')

    log.checkType(samplerate, 'samplerate', str)
    cmd = ['-i', in_file]
    if(not fnone(audioBit)):
        cmd.extend(['-b:a', audioBit])
    cmd.extend(['-ac', '2', '-ar', samplerate, '-vn', temp_file])

    ffmpeg.run(cmd)
    log.conwrite('')

    return temp_file

def fastAudio(in_file, out_file, chunks: list, speeds: list, log, fps: float,
    machineReadable, hideBar):
    import numpy as np

    def custom_speeds(a):
        return len([x for x in a if x != 1 and x != 99999]) > 0

    if(custom_speeds(speeds)):
        from audiotsm2 import phasevocoder
        from audiotsm2.io.array import ArrReader, ArrWriter

    if(len(chunks) == 1 and chunks[0][2] == 0):
        log.error('Trying to create an empty file.')

    samplerate, audioData = read(in_file)

    newL = get_new_length(chunks, speeds, fps)
    # Get the new length in samples with some extra leeway.
    estLeng = int(newL * samplerate * 1.5) + int(samplerate * 2)

    # Create an empty array for the new audio.
    newAudio = np.zeros((estLeng, 2), dtype=np.int16)

    channels = 2
    yPointer = 0

    audioProgress = ProgressBar(len(chunks), 'Creating new audio', machineReadable,
        hideBar)

    for chunkNum, chunk in enumerate(chunks):
        audioSampleStart = int(chunk[0] / fps * samplerate)
        audioSampleEnd = int(audioSampleStart + (samplerate / fps) * (chunk[1] - chunk[0]))

        theSpeed = speeds[chunk[2]]
        if(theSpeed != 99999):
            spedChunk = audioData[audioSampleStart:audioSampleEnd]

            if(theSpeed == 1):
                yPointerEnd = yPointer + spedChunk.shape[0]
                newAudio[yPointer:yPointerEnd] = spedChunk
            else:
                spedupAudio = np.zeros((0, 2), dtype=np.int16)
                with ArrReader(spedChunk, channels, samplerate, 2) as reader:
                    with ArrWriter(spedupAudio, channels, samplerate, 2) as writer:
                        phasevocoder(reader.channels, speed=theSpeed).run(
                            reader, writer
                        )
                        spedupAudio = writer.output

                yPointerEnd = yPointer + spedupAudio.shape[0]
                newAudio[yPointer:yPointerEnd] = spedupAudio

            myL = chunk[1] - chunk[0]
            mySamples = (myL / fps) * samplerate
            newSamples = int(mySamples / theSpeed)

            yPointer = yPointer + newSamples
        else:
            # Speed is too high so skip this section.
            yPointerEnd = yPointer

        audioProgress.tick(chunkNum)

    log.debug('Total Samples: {}'.format(yPointer))
    log.debug('Samples per Frame: {}'.format(samplerate / fps))
    log.debug('Expected video length: {}'.format(yPointer / (samplerate / fps)))
    newAudio = newAudio[:yPointer]
    write(out_file, samplerate, newAudio)

    log.conwrite('')
