# Internal Libraries
import os
import sys
import shutil
import platform
import subprocess
from time import perf_counter

# External Libraries
import av
import numpy as np

# Typing
from typing import List, Tuple, Callable, NoReturn, Optional

# Included Libraries
import auto_editor.vanparse as vanparse

def test_options(parser):
    parser.add_argument('--only', '-n', nargs='*')
    parser.add_argument('--help', '-h', action='store_true',
        help='Print info about the program or an option and exit.')
    parser.add_required('category', nargs=1, choices=['cli', 'sub', 'api', 'unit', 'all'],
        help='Set what category of tests to run.')
    return parser


def av_inspect(path: str, *args):
    container = av.open(path, 'r')

    media = {}
    if len(container.streams.video) > 0:
        video = container.streams.video[0]
        media['fps'] = video.average_rate
        media['resolution'] = video.width, video.height
        media['vcodec'] = video.codec.name
        media['vlanguage'] = video.language

    if len(container.streams.audio) > 0:
        audio = container.streams.audio[0]
        media['samplerate'] = audio.rate
        media['acodec'] = audio.codec.name
        media['alanguage'] = audio.language

    for key, expected in args:
        if media[key] != expected:
            raise Exception(
                f"Media attribute '{key}' was '{media[key]}', expected '{expected}'."
            )


def pipe_to_console(cmd: List[str]) -> Tuple[int, str, str]:
    process = subprocess.Popen(cmd, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
    stdout, stderr = process.communicate()
    return process.returncode, stdout.decode('utf-8'), stderr.decode('utf-8')


def cleanup(the_dir: str) -> None:
    for item in os.listdir(the_dir):
        item = os.path.join(the_dir, item)
        if ('_ALTERED' in item or item.endswith('.xml') or item.endswith('.fcpxml')
            or item.endswith('.mlt')):
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


def run_program(cmd: List[str]) -> None:
    no_open = '.' in cmd[0]
    cmd = get_runner() + cmd

    if no_open:
        cmd += ['--no_open']

    returncode, stdout, stderr = pipe_to_console(cmd)
    if returncode > 0:
        raise Exception('{}\n{}\n'.format(stdout, stderr))


def check_for_error(cmd: List[str], match=None) -> None:
    returncode, stdout, stderr = pipe_to_console(get_runner() + cmd)
    if returncode > 0:
        if 'Error!' in stderr:
            if match is not None and match not in stderr:
                raise Exception('Could\'t find "{}"'.format(match))
        else:
            raise Exception('Program crashed.\n{}\n{}'.format(stdout, stderr))
    else:
        raise Exception('Program should not respond with a code 0.')


def make_np_list(in_file: str, compare_file: str, the_speed: float) -> None:
    from auto_editor.scipy.wavfile import read
    from auto_editor.audiotsm2 import phasevocoder
    from auto_editor.audiotsm2.io.array import ArrReader, ArrWriter

    _, sped_chunk = read(in_file)
    channels = 2

    reader = ArrReader(sped_chunk)
    writer = ArrWriter(np.zeros((0, 2), dtype=np.int16))

    phasevocoder(channels, speed=the_speed).run(reader, writer)

    spedup_audio = writer.output
    del writer
    del reader

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
        except KeyboardInterrupt:
            print(f'Testing Interrupted by User.')
            clean_all()
            sys.exit(1)
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


def main(sys_args: Optional[List[str]]=None):
    parser = vanparse.ArgumentParser('test', 'version')
    parser = test_options(parser)

    if sys_args is None:
        sys_args = sys.argv[1:]

    try:
        args = parser.parse_args(sys_args)
    except vanparse.ParserError as e:
        print(e)
        sys.exit(1)


    ### Tests ###

    ## API Tests ##

    def read_api_0_1():
        check_for_error(['resources/0.1-non-zero-start.json'], 'Error! First chunk must start with 0')
        check_for_error(['resources/0.1-disjoint.json'], 'Error! Chunk disjointed at')


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
        run_program(['example.mp4', '--video_codec', 'uncompressed'])
        av_inspect('example_ALTERED.mp4',
            ('fps', 30),
            ('resolution', (1280, 720), ),
            ('vcodec', 'mpeg4'),
            ('acodec', 'aac'),
            ('samplerate', 48000),
        )

        run_program(['example.mp4'])
        av_inspect('example_ALTERED.mp4',
            ('fps', 30),
            ('resolution', (1280, 720), ),
            ('vcodec', 'h264'),
            ('acodec', 'aac'),
            ('samplerate', 48000),
            ('vlanguage', 'eng'),
            ('alanguage', 'eng'),
        )

    # Issue #200
    def url_test():
        run_program(['https://github.com/WyattBlue/auto-editor/raw/master/example.mp4'])


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
        av_inspect('resources/man_on_green_screen_ALTERED.gif',
            ('vcodec', 'gif'),
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
        av_inspect('out.mp4',
            ('vcodec', 'h264'),
        )
        os.remove('out.mp4')

        run_program(['resources/test.mkv', '-o', 'out'])
        av_inspect('out.mkv',
            ('vcodec', 'h264'),
        )
        os.remove('out.mkv')


    def progress_ops_test():
        run_program(['example.mp4', '--progress', 'machine'])
        run_program(['example.mp4', '--progress', 'none'])
        run_program(['example.mp4', '--progress', 'ascii'])


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
        av_inspect('example_ALTERED.mp4',
            ('fps', 30),
            ('resolution', (1920, 1080), ),
            ('samplerate', 48000),
        )

        run_program(['example.mp4', '--scale', '0.2'])
        av_inspect('example_ALTERED.mp4',
            ('fps', 30),
            ('resolution', (256, 144), ),
            ('samplerate', 48000),
        )


    def various_errors_test():
        check_for_error(['example.mp4', '--add_rectangle', '0,60', '--cut_out', '60,end'])


    def effect_tests():
        """Test rendering video objects"""
        run_program(['resources/testsrc.mp4', '--mark_as_loud', 'start,end',
            '--add_rectangle', '0,30,0,200,100,300,fill=#43FA56,stroke=10'])
        os.remove('resources/testsrc_ALTERED.mp4')


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


    if args.category in ('api', 'all'):
        tester.run_test(read_api_0_1)

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
        tester.run_test(example_tests)
        tester.run_test(url_test)
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
