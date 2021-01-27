'''test.py'''

"""
Test auto-editor and make sure everything is working.
"""

import os
import sys
import subprocess

def runTest(cmd):
    runner = ['python3', 'auto_editor/__main__.py']

    pretty_cmd = ' '.join(cmd)
    print(f'Running test: {pretty_cmd}')

    try:
        hmm = runner + cmd
        if('.' in cmd[0]):
            hmm += ['--no_open']

        subprocess.check_output(hmm)
    except subprocess.CalledProcessError as e:
        print('Test Failed.\n')
        print(e)
        sys.exit(1)
    else:
        print('Test Succeeded.\n')

def testAutoEditor():
    # Test Help Command
    runTest(['--help'])
    runTest(['-h'])
    runTest(['--frame_margin', '--help'])
    runTest(['--frame_margin', '-h'])
    runTest(['exportMediaOps', '--help'])
    runTest(['exportMediaOps', '-h'])
    runTest(['progressOps', '-h'])

    # Test the Help Command on itself.
    runTest(['--help', '--help'])
    runTest(['-h', '--help'])
    runTest(['--help', '-h'])
    runTest(['-h', '--help'])

    # Test version info
    runTest(['--version'])
    runTest(['-v'])
    runTest(['-V'])

    # Test debug info
    runTest(['--debug'])
    # --verbose by itself is UB.

    # Test info subcommand.
    runTest(['info', 'example.mp4'])
    runTest(['info', 'resources/man_on_green_screen.mp4'])
    runTest(['info', 'resources/multi-track.mov'])
    runTest(['info', 'resources/newCommentary.mp3'])
    runTest(['info', 'resources/test.mkv'])

    # Test example video.
    runTest(['example.mp4'])
    runTest(['example.mp4', '--verbose'])

    runTest(['example.mp4', '-m', '3'])
    runTest(['example.mp4', '-m', '0.3sec'])
    runTest(['example.mp4', '--frame_margin', '10'])
    runTest(['example.mp4', '--frame_margin', '2sec'])

    # Test ProgressOps
    runTest(['example.mp4', 'progressOps', '--machine_readable_progress'])
    runTest(['example.mp4', 'progressOps', '--no_progress'])

    # Test Audio File Input and Exporting
    runTest(['resources/newCommentary.mp3', '--silent_threshold', '0.1'])

    # Test Cut by All Tracks
    runTest(['resources/multi-track.mov', '--show_ffmpeg_debug', '--cut_by_all_tracks'])

    runTest(['resources/multi-track.mov', '--keep_tracks_seperate'])

    runTest(['example.mp4', '--cut_by_this_audio', 'resources/newCommentary.mp3'])

    runTest(['example.mp4', '--export_as_json'])
    runTest(['example.json'])

    runTest(['example.mp4', '-s', '2', '-mcut', '10'])
    runTest(['example.mp4', '-v', '2', '-mclip', '4'])
    runTest(['example.mp4', '--sounded_speed', '0.5'])
    runTest(['example.mp4', '--silent_speed', '0.5'])

    for item in os.listdir('resources'):
        item = f'resources/{item}'
        runTest([item])
        runTest([item, '-exp'])
        runTest([item, '-exr'])
        runTest([item, '--preview'])

    runTest(['example.mp4', 'exportMediaOps', '--video_codec', 'h264'])
    runTest(['example.mp4', 'exportMediaOps', '-vcodec', 'h264', '--preset', 'faster'])
    runTest(['example.mp4', 'exportMediaOps', '--audio_codec', 'ac3'])
    runTest(['resources/newCommentary.mp3', 'exportMediaOps', '-acodec', 'pcm_s16le'])

    runTest(['example.mp4', '--cut_out', '0-5.7', '-o', 'hmm.mp4'])
    runTest(['example.mp4', 'hmm.mp4', '--combine_files', '--debug'])

    runTest(['resources/man_on_green_screen.mp4', '--edit_based_on motion', '--debug', '--frame_margin', '0', '-mcut', '0', '-mclip', '0'])

if(__name__ == '__main__'):
    testAutoEditor()
