# type: ignore
from __future__ import annotations

import json
import logging
import os
import platform
import shutil
import subprocess
import sys
from dataclasses import dataclass, field
from fractions import Fraction
from time import perf_counter
from typing import Callable

import av

from auto_editor.vanparse import ArgumentParser

av.logging.set_level(av.logging.PANIC)


@dataclass
class TestArgs:
    only: list[str] = field(default_factory=list)
    help: bool = False
    category: str = "cli"


def test_options(parser):
    parser.add_argument("--only", "-n", nargs="*")
    parser.add_required(
        "category",
        nargs=1,
        choices=("cli", "sub", "api", "all"),
        metavar="category [options]",
    )
    return parser


def pipe_to_console(cmd: list[str]) -> tuple[int, str, str]:
    process = subprocess.Popen(cmd, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
    stdout, stderr = process.communicate()
    return process.returncode, stdout.decode("utf-8"), stderr.decode("utf-8")


class Runner:
    def __init__(self) -> None:
        if platform.system() == "Windows":
            self.program = ["py", "-m", "auto_editor"]
        else:
            self.program = ["python3", "-m", "auto_editor"]

    def main(
        self, inputs: list[str], cmd: list[str], output: str | None = None
    ) -> str | None:
        cmd = self.program + inputs + cmd + ["--no-open"]

        if output is not None:
            root, ext = os.path.splitext(output)
            if inputs and ext == "":
                output = root + os.path.splitext(inputs[0])[1]
            cmd += ["--output", output]

        if output is None and inputs:
            root, ext = os.path.splitext(inputs[0])

            if "--export_as_json" in cmd:
                output = f"{root}.json"
            else:
                output = f"{root}_ALTERED{ext}"

        returncode, stdout, stderr = pipe_to_console(cmd)
        if returncode > 0:
            raise Exception(f"{stdout}\n{stderr}\n")

        return output

    def raw(self, cmd: list[str]) -> None:
        returncode, stdout, stderr = pipe_to_console(self.program + cmd)
        if returncode > 0:
            raise Exception(f"{stdout}\n{stderr}\n")

    def check(self, cmd: list[str], match=None) -> None:
        returncode, stdout, stderr = pipe_to_console(self.program + cmd)
        if returncode > 0:
            if "Error!" in stderr:
                if match is not None and match not in stderr:
                    raise Exception(f'Could\'t find "{match}"')
            else:
                raise Exception(f"Program crashed.\n{stdout}\n{stderr}")
        else:
            raise Exception("Program should not respond with code 0 but did!")


class Tester:
    def __init__(self) -> None:
        pass

    def run(self, tests: list[Callable], args: TestArgs) -> None:
        def clean_all() -> None:
            def clean(the_dir: str) -> None:
                for item in os.listdir(the_dir):
                    item = os.path.join(the_dir, item)
                    if (
                        "_ALTERED" in item
                        or item.endswith(".xml")
                        or item.endswith(".fcpxml")
                        or item.endswith(".mlt")
                    ):
                        os.remove(item)
                    if item.endswith("_tracks"):
                        shutil.rmtree(item)

            clean("resources")
            clean(os.getcwd())

        if args.only != []:
            tests = list(filter(lambda t: t.__name__ in args.only, tests))

        for passed, test in enumerate(tests):
            start = perf_counter()

            try:
                outputs = test()
                end = perf_counter() - start
            except KeyboardInterrupt:
                print(f"Testing Interrupted by User.")
                clean_all()
                sys.exit(1)
            except Exception as e:
                print(f"Test '{test.__name__}' ({passed}/{len(tests)}) failed.\n{e}")
                logging.error("", exc_info=True)
                clean_all()
                sys.exit(1)

            print(f"Test '{test.__name__}' passed: {round(end, 2)} secs")

            if outputs is not None:
                if isinstance(outputs, str):
                    outputs = [outputs]

                for out in outputs:
                    if os.path.isfile(out):
                        os.remove(out)

        print(f"{passed+1}/{len(tests)}")


def main(sys_args: list[str] | None = None):
    if sys_args is None:
        sys_args = sys.argv[1:]

    args = test_options(ArgumentParser("test")).parse_args(TestArgs, sys_args)

    run = Runner()

    ### Tests ###

    ## API Tests ##

    def read_api_0_1():
        run.check(
            ["resources/json/0.1-non-zero-start.json"],
            "Error! First chunk must start with 0",
        )
        run.check(["resources/json/0.1-disjoint.json"], "Error! Chunk disjointed at")

    def help_tests():
        """check the help option, its short, and help on options and groups."""
        run.raw(["--help"])
        run.raw(["-h"])
        run.raw(["--frame_margin", "--help"])
        run.raw(["--frame_margin", "-h"])
        run.raw(["--help", "--help"])
        run.raw(["-h", "--help"])
        run.raw(["--help", "-h"])
        run.raw(["-h", "--help"])

    def version_test():
        """Test version flags and debug by itself."""
        run.raw(["--version"])
        run.raw(["-V"])

    def parser_test():
        run.check(["example.mp4", "--video-speed"], "needs argument")

    def info():
        run.raw(["info", "example.mp4"])
        run.raw(["info", "resources/only-video/man-on-green-screen.mp4"])
        run.raw(["info", "resources/multi-track.mov"])
        run.raw(["info", "resources/new-commentary.mp3"])
        run.raw(["info", "resources/testsrc.mkv"])

    def levels():
        run.raw(["levels", "resources/multi-track.mov"])
        run.raw(["levels", "resources/new-commentary.mp3"])

    def subdump():
        run.raw(["subdump", "resources/subtitle.mp4"])

    def grep():
        run.raw(["grep", "boop", "resources/subtitle.mp4"])

    def desc():
        run.raw(["desc", "example.mp4"])

    def example():
        out = run.main(inputs=["example.mp4"], cmd=[])
        with av.open(out) as cn:
            video = cn.streams.video[0]
            assert video.average_rate == 30
            assert video.time_base == Fraction(1, 30)
            assert video.width == 1280
            assert video.height == 720
            assert video.codec.name == "h264"
            assert cn.streams.audio[0].codec.name == "aac"
            assert cn.streams.audio[0].rate == 48000
            assert video.language == "eng"
            assert cn.streams.audio[0].language == "eng"

        return out

    # PR #260
    def high_speed_test():
        return run.main(inputs=["example.mp4"], cmd=["--video-speed", "99998"])

    # Issue #288
    def expand_chunks():
        out = run.main(
            inputs=["example.mp4"],
            cmd=["--silent-speed", "1"],
            output="out.json",
        )
        with open(out) as file:
            api = json.load(file)
        assert len(api["chunks"]) > 4, "Chunks should not combine"
        return out

    # Issue #184
    def units():
        run.main(["example.mp4"], ["--mark_as_loud", "20s,22sec", "25secs,26.5seconds"])
        run.main(["example.mp4"], ["--edit", "all", "--set-speed", "125%,-30,end"])
        run.main(["example.mp4"], ["--sample_rate", "44_100"])
        run.main(["example.mp4"], ["--margin", "3_0"])
        run.main(["example.mp4"], ["--sample_rate", "44100 Hz"])
        run.main(["example.mp4"], ["--sample_rate", "44.1 kHz"])
        return run.main(["example.mp4"], ["--edit", "audio:threshold=4%"])

    def video_speed():
        return run.main(["example.mp4"], ["--video-speed", "1.5"])

    def backwards_range():
        """
        Cut out the last 5 seconds of a media file by using negative number in the
        range.
        """
        run.main(["example.mp4"], ["--edit", "none", "--cut_out", "-5secs,end"])
        return run.main(["example.mp4"], ["--edit", "all", "--add_in", "-5secs,end"])

    def cut_out():
        run.main(
            ["example.mp4"],
            [
                "--edit",
                "none",
                "--video_speed",
                "2",
                "--silent_speed",
                "3",
                "--cut_out",
                "2secs,10secs",
            ],
        )
        return run.main(
            ["example.mp4"],
            ["--edit", "all", "--video_speed", "2", "--add_in", "2secs,10secs"],
        )

    def gif():
        """
        Feed auto-editor a gif file and make sure it can spit out a correctly formated
        gif. No editing is requested.
        """
        out = run.main(
            ["resources/only-video/man-on-green-screen.gif"], ["--edit", "none"]
        )
        with av.open(out) as cn:
            assert cn.streams.video[0].codec.name == "gif"
        return out

    def margin_tests():
        run.main(["example.mp4"], ["-m", "3"])
        run.main(["example.mp4"], ["--margin", "3"])
        run.main(["example.mp4"], ["-m", "0.3sec"])
        run.main(["example.mp4"], ["-m", "6,-3secs"])
        return run.main(["example.mp4"], ["-m", "0.4 seconds", "--stats"])

    def input_extension():
        """Input file must have an extension. Throw error if none is given."""

        shutil.copy("example.mp4", "example")
        run.check(["example", "--no-open"], "must have an extension.")

        return "example"

    def output_extension():
        # Add input extension to output name if no output extension is given.
        out = run.main(inputs=["example.mp4"], cmd=[], output="out")
        assert out == "out.mp4"
        with av.open(out) as cn:
            assert cn.streams.video[0].codec.name == "h264"

        out = run.main(inputs=["resources/testsrc.mkv"], cmd=[], output="out")
        assert out == "out.mkv"
        with av.open(out) as cn:
            assert cn.streams.video[0].codec.name == "h264"

        return "out.mp4", "out.mkv"

    def progress():
        run.main(["example.mp4"], ["--progress", "machine"])
        run.main(["example.mp4"], ["--progress", "none"])
        return run.main(["example.mp4"], ["--progress", "ascii"])

    def silent_threshold():
        return run.main(
            ["resources/new-commentary.mp3"], ["--edit", "audio:threshold=0.1"]
        )

    def track_tests():
        return run.main(["resources/multi-track.mov"], ["--keep_tracks_seperate"])

    def json_tests():
        out = run.main(["example.mp4"], ["--export_as_json"])
        out2 = run.main([out], [])
        return out, out2

    def resolution_and_scale():
        with av.open(run.main(["example.mp4"], ["--scale", "1.5"])) as cn:
            assert cn.streams.video[0].average_rate == 30
            assert cn.streams.video[0].width == 1920
            assert cn.streams.video[0].height == 1080
            assert cn.streams.audio[0].rate == 48000

        with av.open(run.main(["example.mp4"], ["--scale", "0.2"])) as cn:
            assert cn.streams.video[0].average_rate == 30
            assert cn.streams.video[0].width == 256
            assert cn.streams.video[0].height == 144
            assert cn.streams.audio[0].rate == 48000

        out = run.main(["example.mp4"], ["-res", "700,380", "-b", "darkgreen"])
        with av.open(out) as cn:
            assert cn.streams.video[0].average_rate == 30
            assert cn.streams.video[0].width == 700
            assert cn.streams.video[0].height == 380
            assert cn.streams.audio[0].rate == 48000

        return out

    def obj_makes_video():
        out = run.main(
            ["resources/new-commentary.mp3"],
            ["--add", "rectangle:0,30,0,0,300,300,fill=blue"],
            "out.mp4",
        )
        with av.open(out) as cn:
            assert len(cn.streams.video) == 1
            assert len(cn.streams.audio) == 1
            assert cn.streams.video[0].width == 1920
            assert cn.streams.video[0].height == 1080
            assert cn.streams.video[0].average_rate == 30

        return out

    def various_errors():
        run.check(["example.mp4", "--add", "rectangle:0,60", "--cut-out", "60,end"])

    def render_video_objs():
        out = run.main(
            ["resources/testsrc.mp4"],
            [
                "--mark_as_loud",
                "start,end",
                "--add",
                "rectangle:0,30,0,200,100,300,fill=#43FA56,stroke=10",
            ],
        )

        # Every element should be visible, order should be preserved.
        run.main(
            ["example.mp4"],
            [
                "--add",
                "ellipse:0,30,50%,50%,300,300,fill=red",
                "rectangle:0,30,500,440,400,200,fill=skyblue",
                "ellipse:0,30,50%,50%,100,100,fill=darkgreen",
                "--edit",
                "none",
                "--cut-out",
                "30,end",
            ],
        )

        # Both ellipses should be visible
        out2 = run.main(
            ["example.mp4"],
            [
                "--add",
                "ellipse:0,60,50%,50%,300,300,fill=darkgreen",
                "ellipse:0,30,50%,50%,200,200,fill=green",
                "--edit",
                "none",
                "--cut-out",
                "60,end",
            ],
        )

        return out, out2

    def render_text():
        return run.main(
            ["example.mp4"], ["--add", "text:0,30,This is my text,font=default"]
        )

    def check_font_error():
        run.check(["example.mp4", "--add", "text:0,30,text,0,0,notafont"], "not found")

    def export():
        results = set()
        all_files = (
            "aac.m4a",
            "alac.m4a",
            "wav/pcm-f32le.wav",
            "wav/pcm-s32le.wav",
            "multi-track.mov",
            "subtitle.mp4",
            "testsrc.mkv",
        )

        for test_name in all_files:
            test_file = f"resources/{test_name}"
            results.add(run.main([test_file], []))
            run.main([test_file], ["--edit", "none"])
            run.main([test_file], ["-exp"])
            run.main([test_file], ["-exf"])
            run.main([test_file], ["-exs"])
            run.main([test_file], ["--export_as_clip_sequence"])
            run.main([test_file], ["--stats"])

        return tuple(results)

    def codec_tests():
        run.main(["example.mp4"], ["--video_codec", "h264"])
        return run.main(["example.mp4"], ["--audio_codec", "ac3"])

    # Issue #241
    def multi_track_edit():
        out = run.main(
            ["example.mp4", "resources/multi-track.mov"],
            ["--edit", "audio:stream=1"],
            "out.mov",
        )
        with av.open(out) as cn:
            assert len(cn.streams.audio) == 1

        return out

    def concat():
        out = run.main(["example.mp4"], ["--mark_as_silent", "0,171"], "hmm.mp4")
        out2 = run.main(["example.mp4", "hmm.mp4"], ["--debug"])
        return out, out2

    def concat_mux_tracks():
        out = run.main(["example.mp4", "resources/multi-track.mov"], [], "out.mov")
        with av.open(out) as cn:
            assert len(cn.streams.audio) == 1
        return out

    def concat_multiple_tracks():
        out = run.main(
            ["resources/multi-track.mov", "resources/multi-track.mov"],
            ["--keep-tracks-separate"],
            "out.mov",
        )
        with av.open(out) as cn:
            assert len(cn.streams.audio) == 2, f"audio streams: {len(cn.streams.audio)}"

        out = run.main(
            ["example.mp4", "resources/multi-track.mov"],
            ["--keep-tracks-separate"],
            "out.mov",
        )
        with av.open(out) as cn:
            assert len(cn.streams.audio) == 2

        return out

    def frame_rate():
        with av.open(run.main(["example.mp4"], ["-r", "15", "--no-seek"])) as cn:
            video = cn.streams.video[0]
            assert video.average_rate == 15
            assert video.time_base == Fraction(1, 15)
            dur = float(video.duration * video.time_base)
            assert dur - 17.33333333333333333333333 < 3

        with av.open(run.main(["example.mp4"], ["-r", "20"])) as cn:
            video = cn.streams.video[0]
            assert video.average_rate == 20
            assert video.time_base == Fraction(1, 20)
            dur = float(video.duration * video.time_base)
            assert dur - 17.33333333333333333333333 < 2

        with av.open(out := run.main(["example.mp4"], ["-r", "60"])) as cn:
            video = cn.streams.video[0]
            assert video.average_rate == 60
            assert video.time_base == Fraction(1, 60)
            dur = float(video.duration * video.time_base)
            assert dur - 17.33333333333333333333333 < 0.3

        return out

    def image():
        out1 = run.main(["resources/embedded-image/h264-png.mp4"], [])
        with av.open(out1) as cn:
            assert cn.streams.video[0].codec.name == "h264"
            assert cn.streams.video[1].codec.name == "png"

        out2 = run.main(["resources/embedded-image/h264-mjpeg.mp4"], [])
        with av.open(out2) as cn:
            assert cn.streams.video[0].codec.name == "h264"
            assert cn.streams.video[1].codec.name == "mjpeg"

        out3 = run.main(["resources/embedded-image/h264-png.mkv"], [])
        with av.open(out3) as cn:
            assert cn.streams.video[0].codec.name == "h264"
            assert cn.streams.video[1].codec.name == "png"

        out4 = run.main(["resources/embedded-image/h264-mjpeg.mkv"], [])
        with av.open(out4) as cn:
            assert cn.streams.video[0].codec.name == "h264"
            assert cn.streams.video[1].codec.name == "mjpeg"

        return out1, out2, out3, out4

    def motion():
        out = run.main(
            ["resources/only-video/man-on-green-screen.mp4"],
            ["--edit", "motion", "--margin", "0", "-mcut", "0", "-mclip", "0"],
        )
        out2 = run.main(
            ["resources/only-video/man-on-green-screen.mp4"],
            ["--edit", "motion:threshold=0,width=200"],
        )
        return out, out2

    def edit_positive_tests():
        run.main(["resources/multi-track.mov"], ["--edit", "audio:stream=all"])
        run.main(["resources/multi-track.mov"], ["--edit", "not audio:stream=all"])
        out = run.main(
            ["resources/multi-track.mov"],
            ["--edit", "not audio:threshold=4% or audio:stream=1"],
        )
        # '--edit', 'not audio:threshold=4% or not audio:stream=1'
        return out

    def edit_negative_tests():
        run.check(
            ["resources/wav/example-cut-s16le.wav", "--edit", "motion"],
            "Video stream '0' does not exist",
        )
        run.check(
            ["resources/only-video/man-on-green-screen.gif", "--edit", "audio"],
            "Audio stream '0' does not exist",
        )
        run.check(["example.mp4", "--edit", "not"], "Error! Dangling operand: 'not'")
        run.check(
            ["example.mp4", "--edit", "audio and"], "Error! Dangling operand: 'and'"
        )
        run.check(
            ["example.mp4", "--edit", "and"],
            "Error! 'and' operand needs two arguments.",
        )
        run.check(
            ["example.mp4", "--edit", "and audio"],
            "Error! 'and' operand needs two arguments.",
        )
        run.check(
            ["example.mp4", "--edit", "or audio"],
            "Error! 'or' operand needs two arguments.",
        )
        run.check(
            ["example.mp4", "--edit", "audio four audio"],
            "Error! Unknown method/operator: 'four'",
        )
        run.check(
            ["example.mp4", "--edit", "audio audio"],
            "Logic operator must be between two editing methods",
        )

    def yuv442p():
        return run.main(["resources/test_yuv422p.mp4"], [])

    #  Issue 280
    def SAR():
        out = run.main(["resources/SAR-2by3.mp4"], [])
        with av.open(out) as cn:
            assert cn.streams.video[0].sample_aspect_ratio == Fraction(2, 3)
        return out

    tests = []

    if args.category in ("api", "all"):
        tests.append(read_api_0_1)

    if args.category in ("sub", "all"):
        tests.extend([info, levels, subdump, grep, desc])

    if args.category in ("cli", "all"):
        tests.extend(
            [
                video_speed,
                expand_chunks,
                SAR,
                yuv442p,
                obj_makes_video,
                edit_positive_tests,
                edit_negative_tests,
                multi_track_edit,
                concat_mux_tracks,
                concat_multiple_tracks,
                render_video_objs,
                resolution_and_scale,
                various_errors,
                render_text,
                check_font_error,
                frame_rate,
                help_tests,
                version_test,
                parser_test,
                concat,
                example,
                export,
                high_speed_test,
                units,
                backwards_range,
                cut_out,
                image,
                gif,
                margin_tests,
                input_extension,
                output_extension,
                progress,
                silent_threshold,
                track_tests,
                json_tests,
                codec_tests,
                motion,
            ]
        )

    Tester().run(tests, args)


if __name__ == "__main__":
    main()
