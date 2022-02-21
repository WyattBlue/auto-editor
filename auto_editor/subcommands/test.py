# Internal Libraries
import os
import sys
import shutil
import platform
import subprocess
from time import perf_counter

# Typing
from typing import Callable, NoReturn, Optional, Union

# Included Libraries
from auto_editor.utils.func import clean_list
import auto_editor.vanparse as vanparse

def test_options(parser):
    parser.add_argument('--ffprobe-location', default='ffprobe',
        help='Set a custom path to the ffprobe location.')
    parser.add_argument('--only', '-n', nargs='*')
    parser.add_argument('--help', '-h', action='store_true',
        help='Print info about the program or an option and exit.')
    parser.add_required('category', nargs=1, choices=['cli', 'sub', 'api', 'unit', 'all'],
        help='Set what category of tests to run.')
    return parser


class FFprobe:
    def __init__(self, path: str):
        self.path = path

    def run(self, cmd: list[str]) -> str:
        cmd.insert(0, self.path)
        process = subprocess.Popen(cmd, stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT)
        stdout, __ = process.communicate()
        return stdout.decode('utf-8')

    def pipe(self, cmd: list[str]) -> str:
        full_cmd = [self.path, '-v', 'error'] + cmd
        process = subprocess.Popen(full_cmd, stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT)
        stdout, __ = process.communicate()
        return stdout.decode('utf-8')

    def _get(self, file, stream, the_type, track, of='compact=p=0:nk=1') -> str:
        return self.pipe(['-select_streams', '{}:{}'.format(the_type, track),
            '-show_entries', 'stream={}'.format(stream), '-of', of, file]).strip()

    def getResolution(self, file: str) -> str:
        return self._get(file, 'height,width', 'v', 0, of='csv=s=x:p=0')

    def getTimeBase(self, file: str) -> str:
        return self.pipe(['-select_streams', 'v', '-show_entries',
            'stream=avg_frame_rate', '-of', 'compact=p=0:nk=1', file]).strip()

    def getFrameRate(self, file: str) -> float:
        nums = clean_list(self.getTimeBase(file).split('/'), '\r\t\n')
        return int(nums[0]) / int(nums[1])

    def getAudioCodec(self, file: str, track: int=0) -> str:
        return self._get(file, 'codec_name', 'a', track)

    def getVideoCodec(self, file: str, track: int=0) -> str:
        return self._get(file, 'codec_name', 'v', track)

    def getSampleRate(self, file: str, track: int=0) -> str:
        return self._get(file, 'sample_rate', 'a', track)

    def getVLanguage(self, file: str) -> str:
        return self.pipe(['-show_entries', 'stream=index:stream_tags=language',
            '-select_streams', 'v', '-of', 'compact=p=0:nk=1', file]).strip()

    def getALanguage(self, file: str) -> str:
        return self.pipe(['-show_entries', 'stream=index:stream_tags=language',
            '-select_streams', 'a', '-of', 'compact=p=0:nk=1', file]).strip()

    def AudioBitRate(self, file: str) -> str:

        def bitrate_format(num: Union[int, float]) -> str:
            magnitude = 0
            while abs(num) >= 1000:
                magnitude += 1
                num /= 1000.0
            num = round(num)
            return '%d%s' % (num, ['', 'k', 'm', 'g', 't', 'p'][magnitude])

        exact_bitrate = self._get(file, 'bit_rate', 'a', 0)
        return bitrate_format(int(exact_bitrate))


def pipe_to_console(cmd: list[str]) -> tuple[int, str, str]:
    process = subprocess.Popen(cmd, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
    stdout, stderr = process.communicate()
    return process.returncode, stdout.decode('utf-8'), stderr.decode('utf-8')


def cleanup(the_dir: str) -> None:
    for item in os.listdir(the_dir):
        item = os.path.join(the_dir, item)
        if ('_ALTERED' in item or item.endswith('.xml') or item.endswith('.json')
            or item.endswith('.fcpxml') or item.endswith('.mlt')):
            os.remove(item)
        if item.endswith('_tracks'):
            shutil.rmtree(item)


def clean_all() -> None:
    cleanup('resources')
    cleanup(os.getcwd())


def get_runner() -> list:
    if platform.system() == 'Windows':
        return ['py', '-m', 'auto_editor']
    return ['python3', '-m', 'auto_editor']


def run_program(cmd: list[str]) -> None:
    no_open = '.' in cmd[0]
    cmd = get_runner() + cmd

    if no_open:
        cmd += ['--no_open']

    returncode, stdout, stderr = pipe_to_console(cmd)
    if returncode > 0:
        raise Exception('{}\n{}\n'.format(stdout, stderr))


def check_for_error(cmd: list[str], match=None) -> None:
    returncode, stdout, stderr = pipe_to_console(get_runner() + cmd)
    if returncode > 0:
        if 'Error!' in stderr:
            if match is not None and match not in stderr:
                raise Exception('Could\'t find "{}"'.format(match))
        else:
            raise Exception('Program crashed.\n{}\n{}'.format(stdout, stderr))
    else:
        raise Exception('Program should not respond with a code 0.')

def inspect(path: str, *args) -> None:
    if not os.path.exists(path):
        raise Exception(f"Path '{path}' does not exist.")

    for item in args:
        func = item[0]
        expected_output = item[1]
        if func(path) != expected_output:
            # Cheating on float numbers to allow 30 to equal 29.99944409236961
            if isinstance(expected_output, float):
                from math import ceil
                if ceil(func(path) * 100) == expected_output * 100:
                    continue
            if expected_output.endswith('k'):
                a = int(func(path)[:-1])
                b = int(expected_output[:-1])

                # Allow bitrate to have slight differences.
                if abs(a - b) < 2:
                    continue

            raise Exception(
                f'Inspection Failed. Was {func(path)}, Expected {expected_output}.'
            )


def make_np_list(in_file: str, compare_file: str, the_speed: float) -> None:
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

    if not np.array_equal(spedup_audio, loaded['a']):
        if spedup_audio.shape == loaded['a'].shape:
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

    def run_test(self, func: Callable, cleanup=None, allow_fail=False) -> None:
        if self.args.only != [] and func.__name__ not in self.args.only:
            return

        start = perf_counter()
        try:
            func()
            end = perf_counter() - start
        except Exception as e:
            self.failed_tests += 1
            print(f"Test '{func.__name__}' failed.")
            print(e)
            if not allow_fail:
                clean_all()
                sys.exit(1)
        else:
            self.passed_tests += 1
            print(f"Test '{func.__name__}' passed: {round(end, 2)} secs")
            if cleanup is not None:
                cleanup()

    def end(self) -> NoReturn:
        print('{}/{}'.format(self.passed_tests, self.passed_tests + self.failed_tests))
        clean_all()
        sys.exit(0)


def main(sys_args: Optional[list[str]]=None):
    parser = vanparse.ArgumentParser('test', 'version')
    parser = test_options(parser)

    if sys_args is None:
        sys_args = sys.argv[1:]

    try:
        args = parser.parse_args(sys_args)
    except vanparse.ParserError as e:
        print(e)
        sys.exit(1)

    ffprobe = FFprobe(args.ffprobe_location)

    # Sanity check for ffprobe
    if ffprobe.getFrameRate('example.mp4') != 30.0:
        print('getFrameRate did not equal 30.0')
        sys.exit(1)


    ### Tests ###

    def help_tests():
        """check the help option, its short, and help on options and groups."""
        run_program(['--help'])
        run_program(['-h'])
        run_program(['--frame_margin', '--help'])
        run_program(['--frame_margin', '-h'])
        run_program(['--help', '--help'])
        run_program(['-h', '--help'])
        run_program(['--help', '-h'])
        run_program(['-h', '--help'])


    def version_test():
        """Test version flags and debug by itself."""
        run_program(['--version'])
        run_program(['-v'])
        run_program(['-V'])
        run_program(['--debug'])


    def parser_test():
        check_for_error(['example.mp4', '--block'], 'needs argument')


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
        chunks = [
            (0, 10, 1),
            (10, 20, 99999),
            (20, 30, 1),
            (30, 40, 99999),
            (40, 50, 1),
            (50, 60, 99999),
        ]
        test.edit(chunks)

        if test.contents != [[0, 10, "A"], [10, 20, "C"], [20, 30, "E"]]:
            raise ValueError('Incorrect subtitle results.')


    def tsm_1a5_test():
        make_np_list('resources/example_cut_s16le.wav',
            'resources/example_1.5_speed.npz', 1.5)


    def tsm_0a5_test():
        make_np_list('resources/example_cut_s16le.wav',
            'resources/example_0.5_speed.npz', 0.5)


    def tsm_2a0_test():
        make_np_list('resources/example_cut_s16le.wav',
            'resources/example_2.0_speed.npz', 2)


    def info():
        run_program(['info', 'example.mp4'])
        run_program(['info', 'resources/man_on_green_screen.mp4'])
        run_program(['info', 'resources/multi-track.mov'])
        run_program(['info', 'resources/newCommentary.mp3'])
        run_program(['info', 'resources/test.mkv'])


    def levels():
        run_program(['levels', 'resources/multi-track.mov'])
        run_program(['levels', 'resources/newCommentary.mp3'])


    def subdump():
        run_program(['subdump', 'resources/subtitle.mp4'])


    def grep():
        run_program(['grep', 'boop', 'resources/subtitle.mp4'])


    def desc():
        run_program(['desc', 'example.mp4'])


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


    # Issue #200
    def url_test():
        run_program(['https://github.com/WyattBlue/auto-editor/raw/master/example.mp4'])


    # Issue #172
    def bitrate_test():
        run_program(['example.mp4', '--audio_bitrate', '50k'])
        inspect(
            'example_ALTERED.mp4',
            [ffprobe.AudioBitRate, '50k'],
        )


    # Issue #184
    def unit_tests():
        """
        Make sure all units are working appropriately. That includes:

         - Seconds units: s, sec, secs, second, seconds
         - Frame units:   f, frame, frames
         - Sample units:  Hz, kHz
         - Percent:       %
        """

        run_program(['example.mp4', '--mark_as_loud', '20s,22sec', '25secs,26.5seconds'])
        run_program(['example.mp4', '--sample_rate', '44100'])
        run_program(['example.mp4', '--sample_rate', '44100 Hz'])
        run_program(['example.mp4', '--sample_rate', '44.1 kHz'])
        run_program(['example.mp4', '--silent_threshold', '4%'])


    def backwards_range_test():
        """
        Cut out the last 5 seconds of a media file by using negative number in the
        range.
        """
        run_program(['example.mp4', '--edit', 'none', '--cut_out', '-5secs,end'])
        run_program(['example.mp4', '--edit', 'all', '--add_in', '-5secs,end'])


    def cut_out_test():
        run_program(['example.mp4', '--edit', 'none', '--video_speed', '2', '--silent_speed',
            '3', '--cut_out', '2secs,10secs'])
        run_program(['example.mp4', '--edit', 'all', '--video_speed', '2', '--add_in',
            '2secs,10secs'])


    def gif_test():
        """
        Feed auto-editor a gif file and make sure it can spit out a correctly formated
        gif. No editing is requested.
        """
        run_program(['resources/man_on_green_screen.gif', '--edit', 'none'])
        inspect(
            'resources/man_on_green_screen_ALTERED.gif',
            [ffprobe.getVideoCodec, 'gif'],
        )


    def margin_tests():
        run_program(['example.mp4', '-m', '3'])
        run_program(['example.mp4', '--margin', '3'])
        run_program(['example.mp4', '-m', '0.3sec'])
        run_program(['example.mp4', '-m', '6f,-3secs'])
        run_program(['example.mp4', '-m', '3,5 frames'])
        run_program(['example.mp4', '-m', '0.4 seconds'])


    def input_extension():
        """Input file must have an extension. Throw error if none is given."""

        shutil.copy('example.mp4', 'example')
        check_for_error(['example', '--no_open'], 'must have an extension.')
        os.remove('example')


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


    def progress_ops_test():
        run_program(['example.mp4', '--machine_readable_progress'])
        run_program(['example.mp4', '--no_progress'])


    def silent_threshold():
        run_program(['resources/newCommentary.mp3', '--silent_threshold', '0.1'])


    def track_tests():
        run_program(['resources/multi-track.mov', '--cut_by_all_tracks'])
        run_program(['resources/multi-track.mov', '--keep_tracks_seperate'])
        run_program(['example.mp4', '--cut_by_this_audio', 'resources/newCommentary.mp3'])


    def json_tests():
        run_program(['example.mp4', '--export_as_json'])
        run_program(['example.json'])


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


    def various_errors_test():
        check_for_error(['example.mp4', '--add_rectangle', '0,60', '--cut_out', '60,end'])


    def effect_tests():
        """Test rendering video objects"""
        run_program(['create', 'test', '--width', '640', '--height', '360', '-o',
            'testsrc.mp4'])
        inspect(
            'testsrc.mp4',
            [ffprobe.getFrameRate, 30.0],
            [ffprobe.getResolution, '640x360'],
        )
        run_program(['testsrc.mp4', '--mark_as_loud', 'start,end', '--add_rectangle',
            '0,30,0,200,100,300,fill=#43FA56,stroke=10'])
        os.remove('testsrc_ALTERED.mp4')
        os.remove('testsrc.mp4')


    def render_text():
        run_program(['example.mp4', '--add-text', 'start,end,This is my text'])


    def check_font_error():
        check_for_error(
            ['example.mp4', '--add-text', 'start,end,text,0,0,30,notafont'], 'not found'
        )


    def export_tests():
        for test_name in ('aac.m4a', 'alac.m4a', 'pcm_f32le.wav', 'multi-track.mov',
            'pcm_s32le.wav', 'subtitle.mp4', 'test.mkv'):

            test_file = f'resources/{test_name}'
            run_program([test_file])
            run_program([test_file, '-exp'])
            run_program([test_file, '-exf'])
            run_program([test_file, '-exs'])
            run_program([test_file, '--export_as_clip_sequence'])
            run_program([test_file, '--preview'])
            cleanup('resources')


    def codec_tests():
        run_program(['example.mp4', '--video_codec', 'h264'])
        run_program(['example.mp4', '--audio_codec', 'ac3'])


    def combine_tests():
        run_program(['example.mp4', '--mark_as_silent', '0,171', '-o', 'hmm.mp4'])
        run_program(['example.mp4', 'hmm.mp4', '--combine_files', '--debug'])
        os.remove('hmm.mp4')


    def motion_tests():
        run_program(['resources/man_on_green_screen.mp4', '--edit_based_on', 'motion',
            '--debug', '--frame_margin', '0', '-mcut', '0', '-mclip', '0'])
        run_program(['resources/man_on_green_screen.mp4', '--edit_based_on', 'motion',
            '--motion_threshold', '0'])

    ### Runners ###

    tester = Tester(args)

    if args.category in ('unit', 'all'):
        tester.run_test(subtitle_tests)
        tester.run_test(tsm_1a5_test)
        tester.run_test(tsm_0a5_test, allow_fail=True)
        tester.run_test(tsm_2a0_test)

    if args.category in ('sub', 'all'):
        tester.run_test(info)
        tester.run_test(levels)
        tester.run_test(subdump)
        tester.run_test(grep)
        tester.run_test(desc)

    if args.category in ('cli', 'all'):
        tester.run_test(help_tests)
        tester.run_test(version_test)
        tester.run_test(parser_test)
        tester.run_test(example_tests, allow_fail=True)
        tester.run_test(url_test)
        tester.run_test(bitrate_test)
        tester.run_test(unit_tests)
        tester.run_test(backwards_range_test)
        tester.run_test(cut_out_test)
        tester.run_test(gif_test, cleanup=clean_all)
        tester.run_test(margin_tests)
        tester.run_test(input_extension)
        tester.run_test(output_extension)
        tester.run_test(progress_ops_test)
        tester.run_test(silent_threshold)
        tester.run_test(track_tests)
        tester.run_test(json_tests)
        tester.run_test(scale_tests)
        tester.run_test(various_errors_test)
        tester.run_test(effect_tests, cleanup=clean_all)
        tester.run_test(render_text)
        tester.run_test(check_font_error)
        tester.run_test(export_tests)
        tester.run_test(codec_tests)
        tester.run_test(combine_tests)
        tester.run_test(motion_tests)

    tester.end()

if __name__ == '__main__':
    main()
