'''fastAudio.py'''

from usefulFunctions import ProgressBar, getNewLength, sep, fNone

def convertAudio(ffmpeg, ffprobe, theFile, INPUT_FILE, outFile, args, log):
    log.debug(f'Convering internal audio file: {theFile} to {outFile}')

    realCodec = args.audio_codec
    if(fNone(realCodec)):
        realCodec = ffprobe.getAudioCodec(INPUT_FILE)
    if(realCodec == 'pcm_s16le' and outFile.endswith('.m4a')):
        log.error(f'Codec: {realCodec} is not supported in the m4a container.')

    ffmpeg.run(['-i', theFile, '-acodec', realCodec, outFile])


def handleAudio(ffmpeg, theFile, audioBit, samplerate: str, temp, log) -> str:
    TEMPFILE = f'{temp}{sep()}faAudio.wav'

    log.checkType(samplerate, 'samplerate', str)
    cmd = ['-i', theFile]
    if(not fNone(audioBit)):
        cmd.extend(['-b:a', audioBit])
        log.checkType(audioBit, 'audioBit', str)
    cmd.extend(['-ac', '2', '-ar', samplerate, '-vn', TEMPFILE])

    ffmpeg.run(cmd)
    log.conwrite('')

    return TEMPFILE


def fastAudio(theFile, outFile, chunks: list, speeds: list, log, fps: float,
    machineReadable, hideBar):
    from wavfile import read, write
    import os

    import numpy as np

    log.checkType(chunks, 'chunks', list)
    log.checkType(speeds, 'speeds', list)

    def speedsOtherThan1And99999(a: list) -> bool:
        return len([x for x in a if x != 1 and x != 99999]) > 0

    if(speedsOtherThan1And99999(speeds)):
        from audiotsm2 import phasevocoder
        from audiotsm2.io.array import ArrReader, ArrWriter

    if(len(chunks) == 1 and chunks[0][2] == 0):
        log.error('Trying to create an empty file.')

    if(not os.path.isfile(theFile)):
        log.error('fastAudio.py could not find file: ' + theFile)

    samplerate, audioData = read(theFile)

    newL = getNewLength(chunks, speeds, fps)
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

    log.debug('\n   - Total Samples: ' + str(yPointer))
    log.debug('   - Samples per Frame: ' + str(samplerate / fps))
    log.debug('   - Expected video length: ' + str(yPointer / (samplerate / fps)))
    newAudio = newAudio[:yPointer]
    write(outFile, samplerate, newAudio)

    log.conwrite('')
