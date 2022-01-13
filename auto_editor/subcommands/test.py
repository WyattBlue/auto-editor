'''subcommands/test.py'''

"""
Test auto-editor and make sure everything is working.
"""

# Internal Libraries
import os
import sys
import shutil
import platform
import subprocess
from time import perf_counter

# Included Libraries
from auto_editor.utils.func import clean_list
import auto_editor.vanparse as vanparse

def test_options(parser):
    parser.add_argument('--ffprobe_location', default='ffprobe',
        help='point to your custom ffprobe file.')
    parser.add_argument('--only', '-n', nargs='*')
    parser.add_argument('--help', '-h', action='store_true',
        help='print info about the program or an option and exit.')
    return parser

class FFprobe():
    def __init__(self, path):
        self.path = path

    def run(self, cmd):
        cmd.insert(0, self.path)
        process = subprocess.Popen(cmd, stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT)
        stdout, __ = process.communicate()
        return stdout.decode('utf-8')

    def pipe(self, cmd):
        full_cmd = [self.path, '-v', 'error'] + cmd
        process = subprocess.Popen(full_cmd, stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT)
        stdout, __ = process.communicate()
        return stdout.decode('utf-8')

    def _get(self, file, stream, the_type, track, of='compact=p=0:nk=1'):
        return self.pipe(['-select_streams', '{}:{}'.format(the_type, track),
            '-show_entries', 'stream={}'.format(stream), '-of', of, file]).strip()

    def getResolution(self, file):
        return self._get(file, 'height,width', 'v', 0, of='csv=s=x:p=0')

    def getTimeBase(self, file):
        return self.pipe(['-select_streams', 'v', '-show_entries',
            'stream=avg_frame_rate', '-of', 'compact=p=0:nk=1', file]).strip()

    def getFrameRate(self, file):
        nums = clean_list(self.getTimeBase(file).split('/'), '\r\t\n')
        return int(nums[0]) / int(nums[1])

    def getAudioCodec(self, file, track=0):
        return self._get(file, 'codec_name', 'a', track)

    def getVideoCodec(self, file, track=0):
        return self._get(file, 'codec_name', 'v', track)

    def getSampleRate(self, file, track=0):
        return self._get(file, 'sample_rate', 'a', track)

    def getVLanguage(self, file):
        return self.pipe(['-show_entries', 'stream=index:stream_tags=language',
            '-select_streams', 'v', '-of', 'compact=p=0:nk=1', file]).strip()

    def getALanguage(self, file):
        return self.pipe(['-show_entries', 'stream=index:stream_tags=language',
            '-select_streams', 'a', '-of', 'compact=p=0:nk=1', file]).strip()

    def AudioBitRate(self, file):

        def bitrate_format(num):
            magnitude = 0
            while abs(num) >= 1000:
                magnitude += 1
                num /= 1000.0
            num = round(num)
            return '%d%s' % (num, ['', 'k', 'm', 'g', 't', 'p'][magnitude])

        exact_bitrate = self._get(file, 'bit_rate', 'a', 0)
        return bitrate_format(int(exact_bitrate))


def pipe_to_console(cmd):
    process = subprocess.Popen(cmd, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
    stdout, stderr = process.communicate()
    return process.returncode, stdout.decode('utf-8'), stderr.decode('utf-8')

def cleanup(the_dir):
    for item in os.listdir(the_dir):
        item = os.path.join(the_dir, item)
        if('_ALTERED' in item or item.endswith('.xml') or item.endswith('.json')
            or item.endswith('.fcpxml') or item.endswith('.mlt')):
            os.remove(item)
        if(item.endswith('_tracks')):
            shutil.rmtree(item)

def clean_all():
    cleanup('resources')
    cleanup(os.getcwd())


def getRunner():
    if(platform.system() == 'Windows'):
        return ['py', '-m', 'auto_editor']
    return ['python3', '-m', 'auto_editor']


def run_program(cmd):
    no_open = '.' in cmd[0]
    cmd = getRunner() + cmd

    if(no_open):
        cmd += ['--no_open']

    returncode, stdout, stderr = pipe_to_console(cmd)
    if(returncode > 0):
        raise Exception('{}\n{}\n'.format(stdout, stderr))


def check_for_error(cmd, match=None):
    returncode, stdout, stderr = pipe_to_console(getRunner() + cmd)
    if(returncode > 0):
        if('Error!' in stderr):
            if(match is not None and match not in stderr):
                raise Exception('Could\'t find "{}"'.format(match))
        else:
            raise Exception('Program crashed.\n{}\n{}'.format(stdout, stderr))
    else:
        raise Exception('Program should not respond with a code 0.')

def inspect(path, *args):
    if(not os.path.exists(path)):
        raise Exception(f"Path '{path}' does not exist.")

    for item in args:
        func = item[0]
        expectedOutput = item[1]
        if(func(path) != expectedOutput):
            # Cheating on float numbers to allow 30 to equal 29.99944409236961
            if(isinstance(expectedOutput, float)):
                from math import ceil
                if(ceil(func(path) * 100) == expectedOutput * 100):
                    continue
            if(expectedOutput.endswith('k')):
                a = int(func(path)[:-1])
                b = int(expectedOutput[:-1])

                # Allow bitrate to have slight differences.
                if(abs(a - b) < 2):
                    continue

            raise Exception(
                f'Inspection Failed. Was {func(path)}, Expected {expectedOutput}.')


def make_np_list(in_file, compare_file, the_speed):
    import numpy as np
    from auto_editor.scipy.wavfile import read
    from auto_editor.audiotsm2 import phasevocoder
    from auto_editor.audiotsm2.io.array import ArrReader, ArrWriter

    samplerate, sped_chunk = read(in_file)
    spedup_audio = np.zeros((0, 2), dtype=np.int16)
    channels = 2

    with ArrReader(sped_chunk, channels, samplerate, 2) as reader:
        with ArrWriter(spedup_audio, channels, samplerate, 2) as writer:
            phasevocoder(reader.channels, speed=the_speed).run(
                reader, writer
            )
            spedup_audio = writer.output


    loaded = np.load(compare_file)

    if(not np.array_equal(spedup_audio, loaded['a'])):
        if(spedup_audio.shape == loaded['a'].shape):
            print(f'Both shapes ({spedup_audio.shape}) are same')
        else:
            print(spedup_audio.shape)
            print(loaded['a'].shape)

        result = np.subtract(spedup_audio, loaded['a'])

        print('result non-zero: {}'.format(np.count_nonzero(result)))
        print('len of spedup_audio: {}'.format(len(spedup_audio)))

        print(np.count_nonzero(result) / spedup_audio.shape[0], 'difference between arrays')

        raise Exception("file {} doesn't match array.".format(compare_file))

    # np.savez_compressed(out_file, a=spedup_audio)


class Tester():
    def __init__(self, args):
        self.passed_tests = 0
        self.failed_tests = 0
        self.args = args

    def run_test(self, name, func, description='', cleanup=None, allow_fail=False):
        if(self.args.only != [] and name not in self.args.only):
            return
        start = perf_counter()
        try:
            func()
            end = perf_counter() - start
        except Exception as e:
            self.failed_tests += 1
            print("Test '{}' failed.".format(name))
            print(e)
            if(not allow_fail):
                clean_all()
                sys.exit(1)
        else:
            self.passed_tests += 1
            print('{} Passed. {} secs.'.format(name, round(end, 2)))
            if(cleanup is not None):
                cleanup()

    def end(self):
        print('{}/{}'.format(self.passed_tests, self.passed_tests + self.failed_tests))
        clean_all()
        sys.exit(0)

def main(sys_args=None):
    parser = vanparse.ArgumentParser('test', 'version')
    parser = test_options(parser)

    if(sys_args is None):
        sys_args = sys.args[1:]

    try:
        args = parser.parse_args(sys_args)
    except vanparse.ParserError as e:
        print(e)
        sys.exit(1)

    ffprobe = FFprobe(args.ffprobe_location)

    tester = Tester(args)

    def help_tests():
        run_program(['--help'])
        run_program(['-h'])
        run_program(['--frame_margin', '--help'])
        run_program(['--frame_margin', '-h'])
        run_program(['--help', '--help'])
        run_program(['-h', '--help'])
        run_program(['--help', '-h'])
        run_program(['-h', '--help'])
    tester.run_test('help_tests', help_tests, description='check the help option, '
        'its short, and help on options and groups.')

    def version_debug():
        run_program(['--version'])
        run_program(['-v'])
        run_program(['-V'])

        run_program(['--debug'])

        # sanity check for example.mp4/ffprobe
        if(ffprobe.getFrameRate('example.mp4') != 30.0):
            print('getFrameRate did not equal 30.0')
            sys.exit(1)
    tester.run_test('version_tests', version_debug)


    def parser_test():
        check_for_error(['example.mp4', '--block'], 'needs argument')

    tester.run_test('parser_test', parser_test)

    def subtitle_tests():
        from auto_editor.render.subtitle import SubtitleParser
        test = SubtitleParser()
        test.contents = [
            [0, 10, "A"],
            [10, 20, "B"],
            [20, 30, "C"],
            [30, 40, "D"],
            [40, 50, "E"],
            [50, 60, "F"],
        ]
        chunks = [(0, 10, 1), (10, 20, 99999), (20, 30, 1), (30, 40, 99999), (40, 50, 1),
            (50, 60, 99999)]
        test.edit(chunks)

        if(test.contents != [[0, 10, "A"], [10, 20, "C"], [20, 30, "E"]]):
            raise ValueError('Incorrect subtitle results.')


    tester.run_test('subtitle_tests', subtitle_tests)

    def tsm_1a5_test():
        make_np_list('resources/example_cut_s16le.wav',
            'resources/example_1.5_speed.npz', 1.5)

    def tsm_0a5_test():
        make_np_list('resources/example_cut_s16le.wav',
            'resources/example_0.5_speed.npz', 0.5)

    def tsm_2a0_test():
        make_np_list('resources/example_cut_s16le.wav',
            'resources/example_2.0_speed.npz', 2)

    tester.run_test('tsm_1a5_test', tsm_1a5_test)
    tester.run_test('tsm_0a5_test', tsm_0a5_test, allow_fail=True)
    tester.run_test('tsm_2a0_test', tsm_2a0_test)

    def info_tests():
        run_program(['info', 'example.mp4'])
        run_program(['info', 'resources/man_on_green_screen.mp4'])
        run_program(['info', 'resources/multi-track.mov'])
        run_program(['info', 'resources/newCommentary.mp3'])
        run_program(['info', 'resources/test.mkv'])
    tester.run_test('info_tests', info_tests)

    def level_tests():
        run_program(['levels', 'resources/multi-track.mov'])
        run_program(['levels', 'resources/newCommentary.mp3'])
    tester.run_test('level_tests', level_tests)

    def example_tests():
        run_program(['example.mp4'])
        inspect(
            'example_ALTERED.mp4',
            [ffprobe.getFrameRate, 30.0],
            [ffprobe.getResolution, '1280x720'],
            [ffprobe.getVideoCodec, 'h264'],
            [ffprobe.getSampleRate, '48000'],
            [ffprobe.getVLanguage, '0|eng'],
            [ffprobe.getALanguage, '1|eng'],
        )
        run_program(['example.mp4', '--video_codec', 'uncompressed'])
        inspect(
            'example_ALTERED.mp4',
            [ffprobe.getFrameRate, 30.0],
            [ffprobe.getResolution, '1280x720'],
            [ffprobe.getVideoCodec, 'mpeg4'],
            [ffprobe.getSampleRate, '48000'],
        )
    tester.run_test('example_tests', example_tests)

    # Issue #200
    def url_test():
        run_program(['https://github.com/WyattBlue/auto-editor/raw/master/example.mp4'])
    tester.run_test('url_test', url_test)

    # Issue #172
    def bitrate_test():
        run_program(['example.mp4', '--audio_bitrate', '50k'])
        inspect(
            'example_ALTERED.mp4',
            [ffprobe.AudioBitRate, '50k'],
        )
    tester.run_test('bitrate_test', bitrate_test)

    # Issue #184
    def unit_tests():
        run_program(['example.mp4', '--mark_as_loud', '20s,22sec', '25secs,26.5seconds'])
        run_program(['example.mp4', '--sample_rate', '44100'])
        run_program(['example.mp4', '--sample_rate', '44100 Hz'])
        run_program(['example.mp4', '--sample_rate', '44.1 kHz'])
        run_program(['example.mp4', '--silent_threshold', '4%'])
    tester.run_test('unit_tests', unit_tests,
        description='''
        Make sure all units are working appropriately. That includes:
         - Seconds units: s, sec, secs, second, seconds
         - Frame units:   f, frame, frames
         - Sample units:  Hz, kHz
         - Percent:       %

        ''')

    def backwards_range_test():
        run_program(['example.mp4', '--edit', 'none', '--cut_out', '-5secs,end'])
        run_program(['example.mp4', '--edit', 'all', '--add_in', '-5secs,end'])
    tester.run_test('backwards_range_test', backwards_range_test, description='''
        Cut out the last 5 seconds of a media file by using negative number in the
        range.
        ''')

    def cut_out_test():
        run_program(['example.mp4', '--edit', 'none', '--video_speed', '2',
            '--silent_speed', '3', '--cut_out', '2secs,10secs'])
        run_program(['example.mp4', '--edit', 'all', '--video_speed', '2',
            '--add_in', '2secs,10secs'])
    tester.run_test('cut_out_test', cut_out_test)

    def gif_test():
        run_program(['resources/man_on_green_screen.gif', '--edit', 'none'])
        inspect(
            'resources/man_on_green_screen_ALTERED.gif',
            [ffprobe.getVideoCodec, 'gif'],
        )
    tester.run_test('gif_test', gif_test, description='''
        Feed auto-editor a gif file and make sure it can spit out a correctly formated
        gif. No editing is requested.
        ''',
        cleanup=clean_all)

    def margin_tests():
        run_program(['example.mp4', '-m', '3'])
        run_program(['example.mp4', '--margin', '3'])
        run_program(['example.mp4', '-m', '0.3sec'])
        run_program(['example.mp4', '-m', '6f,-3secs'])
        run_program(['example.mp4', '-m', '3,5 frames'])
        run_program(['example.mp4', '-m', '0.4 seconds'])
    tester.run_test('margin_tests', margin_tests)

    def input_extension():
        # Input file must have an extension. Throw error if none is given.
        shutil.copy('example.mp4', 'example')
        check_for_error(['example', '--no_open'], 'must have an extension.')
        os.remove('example')

    tester.run_test('input_extension', input_extension)

    def output_extension():
        # Add input extension to output name if no output extension is given.
        run_program(['example.mp4', '-o', 'out'])
        inspect(
            'out.mp4',
            [ffprobe.getVideoCodec, 'h264']
        )
        os.remove('out.mp4')

        run_program(['resources/test.mkv', '-o', 'out'])
        inspect(
            'out.mkv',
            [ffprobe.getVideoCodec, 'h264']
        )
        os.remove('out.mkv')

    tester.run_test('output_extension', output_extension)

    def progress_ops_test():
        run_program(['example.mp4', '--machine_readable_progress'])
        run_program(['example.mp4', '--no_progress'])
    tester.run_test('progress_ops_test', progress_ops_test)

    def silent_threshold():
        run_program(['resources/newCommentary.mp3', '--silent_threshold', '0.1'])
    tester.run_test('silent_threshold', silent_threshold)

    def track_tests():
        run_program(['resources/multi-track.mov', '--cut_by_all_tracks'])
        run_program(['resources/multi-track.mov', '--keep_tracks_seperate'])
        run_program(['example.mp4', '--cut_by_this_audio', 'resources/newCommentary.mp3'])
    tester.run_test('track_tests', track_tests)

    def json_tests():
        run_program(['example.mp4', '--export_as_json'])
        run_program(['example.json'])
    tester.run_test('json_tests', json_tests)

    def scale_tests():
        run_program(['example.mp4', '--scale', '1.5'])
        inspect(
            'example_ALTERED.mp4',
            [ffprobe.getFrameRate, 30.0],
            [ffprobe.getResolution, '1920x1080'],
            [ffprobe.getSampleRate, '48000'],
        )

        run_program(['example.mp4', '--scale', '0.2'])
        inspect(
            'example_ALTERED.mp4',
            [ffprobe.getFrameRate, 30.0],
            [ffprobe.getResolution, '256x144'],
            [ffprobe.getSampleRate, '48000'],
        )
    tester.run_test('scale_tests', scale_tests)

    def various_errors_test():
        check_for_error(['example.mp4', '--add_rectangle', '0,60', '--cut_out', '60,end'])

    tester.run_test('various_errors_test', various_errors_test)

    def effect_tests():
        run_program(['create', 'test', '--width', '640', '--height', '360', '-o',
            'testsrc.mp4'])
        inspect(
            'testsrc.mp4',
            [ffprobe.getFrameRate, 30.0],
            [ffprobe.getResolution, '640x360'],
        )
        run_program(['testsrc.mp4', '--mark_as_loud', 'start,end', '--add_rectangle',
            '0,30,0,200,100,300,#43FA56,10'])
        os.remove('testsrc_ALTERED.mp4')
        os.remove('testsrc.mp4')
    tester.run_test('effect_tests', effect_tests,
        description='test the rectangle object',
        cleanup=clean_all)

    def render_text():
        run_program(['example.mp4', '--add-text', 'start,end,This is my text'])

    tester.run_test('render_text', render_text)

    def check_font_error():
        check_for_error(
            ['example.mp4', '--add-text', 'start,end,text,0,0,30,notafont'],
            'not found')

    tester.run_test('check_font_error', check_font_error)

    def export_tests():
        for item in os.listdir('resources'):
            if('man_on_green_screen' in item or item.startswith('.') or '_ALTERED' in item
                or item.endswith('.npz')):
                continue
            item = 'resources/{}'.format(item)
            run_program([item])
            run_program([item, '-exp'])
            run_program([item, '-exf'])
            run_program([item, '-exs'])
            run_program([item, '--export_as_clip_sequence'])
            run_program([item, '--preview'])
            cleanup('resources')
    tester.run_test('export_tests', export_tests)

    def codec_tests():
        run_program(['example.mp4', '--video_codec', 'h264', '--preset', 'faster'])
        run_program(['example.mp4', '--audio_codec', 'ac3'])
    tester.run_test('codec_tests', codec_tests)

    def combine_tests():
        run_program(['example.mp4', '--mark_as_silent', '0,171', '-o', 'hmm.mp4'])
        run_program(['example.mp4', 'hmm.mp4', '--combine_files', '--debug'])
        os.remove('hmm.mp4')
    tester.run_test('combine_tests', combine_tests)

    def motion_tests():
        run_program(['resources/man_on_green_screen.mp4', '--edit_based_on', 'motion',
         '--debug', '--frame_margin', '0', '-mcut', '0', '-mclip', '0'])
        run_program(['resources/man_on_green_screen.mp4', '--edit_based_on', 'motion',
            '--motion_threshold', '0'])
    tester.run_test('motion_tests', motion_tests)

    tester.end()

if(__name__ == '__main__'):
    main()
