'''generateTestMedia.py'''

import os
import time
import subprocess

def generateTestMedia(ffmpeg, output, fps, duration, width, height):
    try:
        os.remove(output)
    except FileNotFoundError:
        pass

    # Create sine wav.
    subprocess.call([ffmpeg, '-y', '-f', 'lavfi', '-i',
        'sine=frequency=1000:duration=0.2', 'short.wav'])

    # Pad audio.
    subprocess.call([ffmpeg, '-y', '-i', 'short.wav', '-af', 'apad', '-t', '1',
        'beep.wav'])

    # Generate video with no audio.
    subprocess.call([ffmpeg, '-y', '-f', 'lavfi', '-i',
        f'testsrc=duration={duration}:size={width}x{height}:rate={fps}', '-pix_fmt',
        'yuv420p', output])

    # Add empty audio channel to video.
    subprocess.call([ffmpeg, '-y', '-f', 'lavfi', '-i',
        'anullsrc=channel_layout=stereo:sample_rate=44100', '-i', output, '-c:v',
        'copy', '-c:a', 'aac', '-shortest', 'pre' + output])

    # Mux Video with repeating audio.
    subprocess.call([ffmpeg, '-y', '-i', 'pre' + output, '-filter_complex',
        'amovie=beep.wav:loop=0,asetpts=N/SR/TB[aud];[0:a][aud]amix[a]',
        '-map', '0:v', '-map', '[a]', '-c:v', 'copy', '-c:a', 'aac', '-b:a', '256k',
        '-shortest', output])

    time.sleep(1)
    os.remove('short.wav')
    os.remove('beep.wav')
    os.remove('pre' + output)
