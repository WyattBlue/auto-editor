'''resources/generate_test_video.py'''

"""
This is a helper script to generate test footage of arbitrary length.

This script never gets run in the main program.
"""

import subprocess
import argparse
import os
import time

parser = argparse.ArgumentParser()
parser.add_argument('-fps', type=float, default=30.0)
parser.add_argument('-duration', type=int, default=10)
parser.add_argument('-width', type=int, default=640)
parser.add_argument('-height', type=int, default=360)
parser.add_argument('-output', type=str, default='testsrc.mp4')
parser.add_argument('-ffmpeg', type=str, default='ffmpeg')

args = parser.parse_args()

try:
	os.remove(args.output)
except:
	pass

# Create sine wav.
subprocess.call([args.ffmpeg, '-y', '-f', 'lavfi', '-i',
    'sine=frequency=1000:duration=0.2', 'short.wav'])

# Pad audio.
subprocess.call([args.ffmpeg, '-y', '-i', 'short.wav', '-af', 'apad', '-t', '1',
    'beep.wav'])

# Generate video with no audio.
subprocess.call([args.ffmpeg, '-y', '-f', 'lavfi', '-i',
    f'testsrc=duration={args.duration}:size={args.width}x{args.height}:rate={args.fps}',
     '-pix_fmt', 'yuv420p', args.output])

# Add empty audio channel to video.
subprocess.call([args.ffmpeg, '-y', '-f', 'lavfi', '-i',
    'anullsrc=channel_layout=stereo:sample_rate=44100', '-i', args.output, '-c:v',
    'copy', '-c:a', 'aac', '-shortest', 'pre' + args.output])

# Mux Video with repeating audio.
subprocess.call([args.ffmpeg, '-y', '-i', 'pre' + args.output, '-filter_complex',
    'amovie=beep.wav:loop=0,asetpts=N/SR/TB[aud];[0:a][aud]amix[a]',
    '-map', '0:v', '-map', '[a]', '-c:v', 'copy', '-c:a', 'aac', '-b:a', '256k',
    '-shortest', args.output])

time.sleep(1)
os.remove('short.wav')
os.remove('beep.wav')
os.remove('pre' + args.output)