'''renderWaveform.py'''

def renderWaveform(inFile, outFile, ffmpeg, size: str):

    ffmpeg.run(['-i', inFile, '-filter_complex',
        f'aformat=channel_layouts=mono,showwavespic=s={size}', '-frames:v', '1', outFile])
