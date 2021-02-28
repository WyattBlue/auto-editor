'''testAutoEditor.py'''

"""
Test auto-editor and make sure everything is working.
"""

# Internal Libraries
import os
import sys
import shutil
import platform
import subprocess

# Included Libraries
from usefulFunctions import Log, FFprobe, sep

def getRunner():
    if(platform.system() == 'Windows'):
        return ['py', 'auto_editor/__main__.py']
    return ['python3', 'auto_editor/__main__.py']


def pipeToConsole(myCommands: list):
    print(myCommands)
    process = subprocess.Popen(myCommands, stdout=subprocess.PIPE,
        stderr=subprocess.PIPE)
    stdout, stderr = process.communicate()
    return process.returncode, stdout.decode(), stderr.decode()


def runTest(cmd):
    pretty_cmd = ' '.join(cmd)
    print(f'Running test: {pretty_cmd}')

    add_no_open = '.' in cmd[0]
    cmd = getRunner() + cmd
    if(add_no_open):
        cmd += ['--no_open']

    returncode, stdout, stderr = pipeToConsole(cmd)
    if(returncode > 0):
        print('Test Failed.\n')
        print(stdout)
        print(stderr)
        sys.exit(1)
    else:
        print('Test Succeeded.\n')


def checkForError(cmd):
    pretty_cmd = ' '.join(cmd)
    print(f'Running Error Test: {pretty_cmd}')

    returncode, stdout, stderr = pipeToConsole(getRunner() + cmd)
    if(returncode > 0):
        if('Error!' in stderr):
            print('Test Succeeded.')
        else:
            print('Test Failed.\n')
            print(f'Program crashed.\n{stdout}\n{stderr}')
            sys.exit(1)
    else:
        print('Test Failed.\n')
        print('Program responsed with a code 0, but should have failed.')
        sys.exit(1)


def cleanup(the_dir):
    for item in os.listdir(the_dir):
        item = f'{the_dir}{sep()}{item}'
        if('_ALTERED' in item or item.endswith('.xml') or item.endswith('.json')):
            os.remove(item)
        if(item.endswith('_tracks')):
            shutil.rmtree(item)


dirPath = os.path.dirname(os.path.realpath(__file__))
ffprobe = FFprobe(dirPath, True, False, Log())

def fullInspect(fileName, *args):
    for item in args:
        func = item[0]
        expectedOutput = item[1]

        if(func(fileName) != expectedOutput):

            # Cheating on fps to allow 30 to equal 29.99944409236961
            if(isinstance(expectedOutput, float)):
                from math import ceil
                if(ceil(func(fileName) * 100) == expectedOutput * 100):
                    continue

            print('Inspection Failed.')
            print(f'Expected Value: {expectedOutput} {type(expectedOutput)}')
            print(f'Actual Value: {func(fileName)} {type(func(fileName))}')
            sys.exit(1)
    print('Inspection Passed.')

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

    if(ffprobe.getFrameRate('example.mp4') != 30.0):
        print(f'getFrameRate did not equal 30.0')
        sys.exit(1)

    # Test info subcommand.
    runTest(['info', 'example.mp4'])
    runTest(['info', 'resources/man_on_green_screen.mp4'])
    runTest(['info', 'resources/multi-track.mov'])
    runTest(['info', 'resources/newCommentary.mp3'])
    runTest(['info', 'resources/test.mkv'])

    # Test example video.
    runTest(['example.mp4'])

    fullInspect(
        'example_ALTERED.mp4',
        [ffprobe.getFrameRate, 30.0],
        [ffprobe.getResolution, '1280x720'],
        [ffprobe.getVideoCodec, 'mpeg4'],
        [ffprobe.getSampleRate, '48000'],
    )

    runTest(['example.mp4', 'exportMediaOps', '-vcodec', 'copy', '--show_ffmpeg_debug'])
    fullInspect(
        'example_ALTERED.mp4',
        [ffprobe.getFrameRate, 30.0],
        [ffprobe.getResolution, '1280x720'],
        [ffprobe.getVideoCodec, 'h264'],
        [ffprobe.getSampleRate, '48000'],
    )

    runTest(['example.mp4', 'exportMediaOps', '-vcodec', 'h264', '--render', 'opencv'])
    fullInspect(
        'example_ALTERED.mp4',
        [ffprobe.getFrameRate, 30.0],
        [ffprobe.getResolution, '1280x720'],
        [ffprobe.getVideoCodec, 'h264'],
        [ffprobe.getSampleRate, '48000'],
    )

    runTest(['example.mp4', '-m', '3'])
    runTest(['example.mp4', '-m', '0.3sec'])

    # Test rejecting files with no extension.
    shutil.copy('example.mp4', 'example')
    checkForError(['example', '--no_open'])
    os.remove('example')

    # Test ProgressOps
    runTest(['example.mp4', 'progressOps', '--machine_readable_progress'])
    runTest(['example.mp4', 'progressOps', '--no_progress'])

    # Test mp4 to mkv
    runTest(['example.mp4', '-o', 'example.mkv'])
    os.remove('example.mkv')

    # Test mkv to mp4
    runTest(['resources/test.mkv', '-o', 'test.mp4'])
    os.remove('test.mp4')

    # Test Audio File Input and Exporting
    runTest(['resources/newCommentary.mp3', '--silent_threshold', '0.1'])

    # Test Cut by All Tracks
    runTest(['resources/multi-track.mov', '--cut_by_all_tracks'])

    runTest(['resources/multi-track.mov', '--keep_tracks_seperate'])

    runTest(['example.mp4', '--cut_by_this_audio', 'resources/newCommentary.mp3'])

    runTest(['example.mp4', '--export_as_json'])
    runTest(['example.json'])

    runTest(['example.mp4', '-s', '2', '-mcut', '10'])
    runTest(['example.mp4', '-v', '2', '-mclip', '4'])
    runTest(['example.mp4', '--sounded_speed', '0.5'])
    runTest(['example.mp4', '--silent_speed', '0.5'])

    runTest(['example.mp4', '--scale', '1.5', '--render', 'av'])
    fullInspect(
        'example_ALTERED.mp4',
        [ffprobe.getFrameRate, 30.0],
        [ffprobe.getResolution, '1920x1080'],
        [ffprobe.getSampleRate, '48000'],
    )

    runTest(['example.mp4', '--scale', '0.2', '--render', 'av'])
    fullInspect(
        'example_ALTERED.mp4',
        [ffprobe.getFrameRate, 30.0],
        [ffprobe.getResolution, '256x144'],
        [ffprobe.getSampleRate, '48000'],
    )

    runTest(['example.mp4', '--scale', '1.5', '--render', 'opencv'])
    fullInspect(
        'example_ALTERED.mp4',
        [ffprobe.getFrameRate, 30.0],
        [ffprobe.getResolution, '1920x1080'],
        [ffprobe.getSampleRate, '48000'],
    )

    runTest(['example.mp4', '--scale', '0.2', '--render', 'opencv'])
    fullInspect(
        'example_ALTERED.mp4',
        [ffprobe.getFrameRate, 30.0],
        [ffprobe.getResolution, '256x144'],
        [ffprobe.getSampleRate, '48000'],
    )

    checkForError(['example.mp4', '--zoom', '0,60,1.5', '--render', 'av'])
    checkForError(['example.mp4', '--zoom', '0'])
    checkForError(['example.mp4', '--zoom', '0,60'])

    checkForError(['example.mp4', '--rectangle', '0,60,0,10,10,20', '--render', 'av'])
    checkForError(['example.mp4', '--rectangle', '0,60'])

    checkForError(['example.mp4', '--background', '000'])

    runTest(['generate_test', '-o', 'testsrc.mp4'])
    fullInspect(
        'testsrc.mp4',
        [ffprobe.getFrameRate, 30.0],
        [ffprobe.getResolution, '640x360'],
    )

    runTest(['testsrc.mp4', '--ignore', 'start-end', '--zoom', '10,60,2'])

    runTest(['example.mp4', '--ignore', 'start-end', '--rectangle',
        'audio>0.05,audio<0.05,20,50,50,100', 'audio>0.1,audio<0.1,120,50,150,100'])

    runTest(['testsrc.mp4', '--ignore', 'start-end', '--zoom',
        'start,end,1,0.5,centerX,centerY,linear', '--scale', '0.5'])
    fullInspect(
        'testsrc_ALTERED.mp4',
        [ffprobe.getFrameRate, 30.0],
        [ffprobe.getResolution, '320x180'],
    )

    runTest(['testsrc.mp4', '--ignore', 'start-end', '--rectangle',
        '0,30,0,200,100,300,#43FA56,10'])

    os.remove('testsrc_ALTERED.mp4')
    os.remove('testsrc.mp4')

    cleanup(os.getcwd())
    cleanup('resources')

    for item in os.listdir('resources'):

        if('man_on_green_screen' in item or item.startswith('.') or item.endswith('.txt')):
            continue

        item = f'resources/{item}'
        runTest([item])
        runTest([item, '-exp'])
        runTest([item, '-exr'])
        runTest([item, '--preview'])

    runTest(['example.mp4', 'exportMediaOps', '-vcodec', 'h264', '--preset', 'faster'])
    runTest(['example.mp4', 'exportMediaOps', '--audio_codec', 'ac3'])
    runTest(['resources/newCommentary.mp3', 'exportMediaOps', '-acodec', 'pcm_s16le'])

    runTest(['example.mp4', '--cut_out', '0-5.7', '-o', 'hmm.mp4'])
    runTest(['example.mp4', 'hmm.mp4', '--combine_files', '--debug'])

    os.remove('hmm.mp4')

    runTest(['resources/man_on_green_screen.mp4', '--edit_based_on', 'motion', '--debug',
        '--frame_margin', '0', '-mcut', '0', '-mclip', '0'])

    cleanup('resources')
    cleanup(os.getcwd())

if(__name__ == '__main__'):
    testAutoEditor()
