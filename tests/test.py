import argparse
import concurrent.futures
import hashlib
import os
import shutil
import subprocess
import sys
from collections.abc import Callable
from fractions import Fraction
from hashlib import sha256
from tempfile import mkdtemp
from time import perf_counter

import av
from av import AudioStream, VideoStream
from ffwrapper import FileInfo
from log import Log


def test_options() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description="Test options")
    parser.add_argument("--only", "-n", nargs="*", default=[])
    parser.add_argument("--no-failfast", action="store_true", default=False)
    return parser


def pipe_to_console(cmd: list[str]) -> tuple[int, str, str]:
    process = subprocess.Popen(cmd, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
    stdout, stderr = process.communicate()
    return process.returncode, stdout.decode("utf-8"), stderr.decode("utf-8")


all_files = (
    "aac.m4a",
    "alac.m4a",
    "wav/pcm-f32le.wav",
    "wav/pcm-s32le.wav",
    "multi-track.mov",
    "mov_text.mp4",
    "testsrc.mkv",
)
log = Log(is_debug=True)


def fileinfo(path: str) -> FileInfo:
    return FileInfo.init(path, log)


def calculate_sha256(filename: str) -> str:
    sha256_hash = hashlib.sha256()
    with open(filename, "rb") as f:
        for byte_block in iter(lambda: f.read(4096), b""):
            sha256_hash.update(byte_block)
    return sha256_hash.hexdigest()


class SkipTest(Exception):
    pass


class Runner:
    def __init__(self) -> None:
        self.program = ["./auto-editor"]
        self.temp_dir = mkdtemp()

    def main(self, inputs: list[str], cmd: list[str], output: str | None = None) -> str:
        assert inputs
        cmd = self.program + inputs + cmd + ["--no-open", "--progress", "none"]
        temp_dir = self.temp_dir
        if not os.path.exists(temp_dir):
            raise ValueError("Where's the temp dir")
        if output is None:
            new_root = sha256("".join(cmd).encode()).hexdigest()[:16]
            output = os.path.join(temp_dir, new_root)
        else:
            root, ext = os.path.splitext(output)
            if inputs and ext == "":
                output = root + os.path.splitext(inputs[0])[1]
            output = os.path.join(temp_dir, output)

        returncode, stdout, stderr = pipe_to_console(cmd + ["--output", output])
        if returncode > 0:
            raise Exception(f"Test returned: {returncode}\n{stdout}\n{stderr}\n")

        return output

    def raw(self, cmd: list[str]) -> str:
        returncode, stdout, stderr = pipe_to_console(self.program + cmd)
        if returncode > 0:
            raise Exception(f"{stdout}\n{stderr}\n")
        return stdout

    def check(self, cmd: list[str], match=None) -> None:
        returncode, stdout, stderr = pipe_to_console(self.program + cmd)
        if returncode > 0:
            if "Error!" in stderr:
                if match is not None and match not in stderr:
                    raise Exception(f'Could\'t find "{match}"')
            else:
                raise Exception(
                    f"Program crashed but should have shown an error.\n{' '.join(cmd)}\n{stdout}\n{stderr}"
                )
        else:
            raise Exception("Program should not respond with code 0 but did!")

    def test_help(self):
        """check the help option, its short, and help on options and groups."""
        self.raw(["--help"])
        self.raw(["-h"])
        self.raw(["--margin", "--help"])
        self.raw(["--edit", "-h"])
        self.raw(["--help", "--help"])
        self.raw(["-h", "--help"])
        self.raw(["--help", "-h"])

    def test_version(self):
        """Test version flags and debug by itself."""
        v1 = self.raw(["--version"])
        v2 = self.raw(["-V"])
        assert "." in v1 and len(v1) > 4
        assert v1 == v2

    def test_parser(self):
        self.check(["example.mp4", "--margin"], "needs argument")

    def info(self):
        self.raw(["info", "example.mp4"])
        self.raw(["info", "resources/only-video/man-on-green-screen.mp4"])
        self.raw(["info", "resources/multi-track.mov"])
        self.raw(["info", "resources/new-commentary.mp3"])
        self.raw(["info", "resources/testsrc.mkv"])

    def levels(self):
        self.raw(["levels", "resources/multi-track.mov"])
        self.raw(["levels", "resources/new-commentary.mp3"])

    def subdump(self):
        self.raw(["subdump", "resources/mov_text.mp4"])
        self.raw(["subdump", "resources/webvtt.mkv"])

    def desc(self):
        self.raw(["desc", "example.mp4"])

    def test_movflags(self) -> None:
        file = "resources/testsrc.mp4"
        out = self.main([file], ["--faststart"]) + ".mp4"
        fast = calculate_sha256(out)
        with av.open(out) as container:
            assert isinstance(container.streams[0], VideoStream)
            assert isinstance(container.streams[1], AudioStream)

        out = self.main([file], ["--no-faststart"]) + ".mp4"
        nofast = calculate_sha256(out)
        with av.open(out) as container:
            assert isinstance(container.streams[0], VideoStream)
            assert isinstance(container.streams[1], AudioStream)

        out = self.main([file], ["--fragmented"]) + ".mp4"
        frag = calculate_sha256(out)
        with av.open(out) as container:
            assert isinstance(container.streams[0], VideoStream)
            assert isinstance(container.streams[1], AudioStream)

        assert fast != nofast, "+faststart is not being applied"
        assert frag not in (fast, nofast), "fragmented output should diff."

    def test_example(self) -> None:
        out = self.main(["example.mp4"], [], output="example_ALTERED.mp4")
        with av.open(out) as container:
            assert container.duration is not None
            assert container.duration > 17300000 and container.duration < 2 << 24

            assert len(container.streams) == 2
            video = container.streams[0]
            audio = container.streams[1]
            assert isinstance(video, VideoStream)
            assert isinstance(audio, AudioStream)
            assert video.base_rate == 30
            assert video.average_rate is not None
            assert video.average_rate == 30, video.average_rate
            assert (video.width, video.height) == (1280, 720)
            assert video.codec.name == "h264"
            assert video.language == "eng"
            assert audio.codec.name == "aac"
            assert audio.sample_rate == 48000
            assert audio.language == "eng"
            assert audio.layout.name == "stereo"

    def test_video_to_mp3(self) -> None:
        out = self.main(["example.mp4"], [], output="example_ALTERED.mp3")
        with av.open(out) as container:
            assert container.duration is not None
            assert container.duration > 17300000 and container.duration < 2 << 24

            assert len(container.streams) == 1
            audio = container.streams[0]
            assert isinstance(audio, AudioStream)
            assert audio.codec.name in ("mp3", "mp3float")
            assert audio.sample_rate == 48000
            assert audio.layout.name == "stereo"

    def test_to_mono(self) -> None:
        out = self.main(["example.mp4"], ["-layout", "mono"], output="example_mono.mp4")
        with av.open(out) as container:
            assert container.duration is not None
            assert container.duration > 17300000 and container.duration < 2 << 24

            assert len(container.streams) == 2
            video = container.streams[0]
            audio = container.streams[1]
            assert isinstance(video, VideoStream)
            assert isinstance(audio, AudioStream)
            assert video.base_rate == 30
            assert video.average_rate is not None
            assert video.average_rate == 30, video.average_rate
            assert (video.width, video.height) == (1280, 720)
            assert video.codec.name == "h264"
            assert video.language == "eng"
            assert audio.codec.name == "aac"
            assert audio.sample_rate == 48000
            assert audio.language == "eng"
            assert audio.layout.name == "mono"

    # PR #260
    def test_high_speed(self):
        self.check(["example.mp4", "--video-speed", "99998"], "empty")

    # Issue #184
    def test_units(self):
        self.main(["example.mp4"], ["--edit", "all/e", "--set-speed", "125%,-30,end"])
        self.main(["example.mp4"], ["--edit", "audio:threshold=4%"])

    def test_sr_units(self):
        self.main(["example.mp4"], ["--sample_rate", "44100 Hz"])
        self.main(["example.mp4"], ["--sample_rate", "44.1 kHz"])

    def test_video_speed(self):
        self.main(["example.mp4"], ["--video-speed", "1.5"])

    def test_backwards_range(self):
        """
        Cut out the last 5 seconds of a media file by using negative number in the
        range.
        """
        self.main(["example.mp4"], ["--edit", "none", "--cut_out", "-5secs,end"])
        self.main(["example.mp4"], ["--edit", "all/e", "--add_in", "-5secs,end"])

    def test_cut_out(self):
        self.main(
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
        self.main(
            ["example.mp4"],
            ["--edit", "all/e", "--video_speed", "2", "--add_in", "2secs,10secs"],
        )

    def test_gif(self):
        """
        Feed auto-editor a gif file and make sure it can spit out a correctly formatted
        gif. No editing is requested.
        """
        input = ["resources/only-video/man-on-green-screen.gif"]
        out = self.main(input, ["--edit", "none", "--cut-out", "2sec,end"], "out.gif")
        assert fileinfo(out).videos[0].codec == "gif"

    def test_margin(self):
        self.main(["example.mp4"], ["-m", "3"])
        self.main(["example.mp4"], ["-m", "0.3sec"])
        self.main(["example.mp4"], ["-m", "0.1 seconds"])
        self.main(["example.mp4"], ["-m", "6,-3secs"])

    def test_input_extension(self):
        """Input file must have an extension. Throw error if none is given."""
        path = os.path.join(self.temp_dir, "example")
        shutil.copy("example.mp4", path)
        self.check([path, "--no-open"], "must have an extension")

    def test_silent_threshold(self):
        with av.open("resources/new-commentary.mp3") as container:
            assert container.duration is not None
            assert container.duration / av.time_base == 6.732

        out = self.main(
            ["resources/new-commentary.mp3"], ["--edit", "audio:threshold=0.1"]
        )
        out += ".mp3"

        with av.open(out) as container:
            assert container.duration is not None
            assert container.duration / av.time_base == 6.552

    def test_track(self):
        out = self.main(["resources/multi-track.mov"], []) + ".mov"
        assert len(fileinfo(out).audios) == 2

    def test_export_json(self):
        out = self.main(["example.mp4"], ["--export", "v1"], "c77130d763d40e8.json")
        self.main([out], [])
        out = self.main(["example.mp4"], ["--export", "v1"], "c77130d763d40e8.v1")
        self.main([out], [])

    def test_import_v1(self):
        path = os.path.join(self.temp_dir, "v1.json")
        with open(path, "w") as file:
            file.write(
                """{"version": "1", "source": "example.mp4", "chunks": [ [0, 26, 1.0], [26, 34, 0] ]}"""
            )

        self.main([path], [])

    def test_res_with_v1(self):
        v1 = self.main(["example.mp4"], ["--export", "v1"], "input.v1")
        out = self.main([v1], ["-res", "720,720"], "output.mp4")

        output = fileinfo(out)
        assert output.videos[0].width == 720
        assert output.videos[0].height == 720
        assert len(output.audios) == 1

    def test_premiere_named_export(self) -> None:
        self.main(["example.mp4"], ["--export", 'premiere:name="Foo Bar"'])

    def test_export_subtitles(self) -> None:
        raise SkipTest()  # TODO
        # cn = fileinfo(self.main(["resources/mov_text.mp4"], [], "movtext_out.mp4"))

        # assert len(cn.videos) == 1
        # assert len(cn.audios) == 1
        # assert len(cn.subtitles) == 1

        cn = fileinfo(self.main(["resources/webvtt.mkv"], [], "webvtt_out.mkv"))
        assert len(cn.videos) == 1
        assert len(cn.audios) == 1
        assert len(cn.subtitles) == 1

    def test_scale(self) -> None:
        cn = fileinfo(self.main(["example.mp4"], ["--scale", "1.5"], "scale.mp4"))
        assert cn.videos[0].fps == 30
        assert cn.videos[0].width == 1920
        assert cn.videos[0].height == 1080
        assert cn.audios[0].samplerate == 48000

        cn = fileinfo(self.main(["example.mp4"], ["--scale", "0.2"], "scale.mp4"))
        assert cn.videos[0].fps == 30
        assert cn.videos[0].width == 256
        assert cn.videos[0].height == 144
        assert cn.audios[0].samplerate == 48000

    def test_resolution(self):
        out = self.main(
            ["example.mp4"], ["-res", "700,380", "-b", "darkgreen"], "green"
        )
        cn = fileinfo(out)

        assert cn.videos[0].fps == 30
        assert cn.videos[0].width == 700
        assert cn.videos[0].height == 380
        assert cn.audios[0].samplerate == 48000

    # def test_premiere_multi(self):
    #     p_xml = self.main([f"resources/multi-track.mov"], ["-exp"], "multi.xml")

    #     cn = fileinfo(self.main([p_xml], []))
    #     assert len(cn.videos) == 1
    #     assert len(cn.audios) == 2

    def test_premiere(self) -> None:
        for test_name in all_files:
            if test_name == "multi-track.mov":
                continue

            p_xml = self.main([f"resources/{test_name}"], ["-exp"], "out.xml")

            # TODO: Support premiere XML as input.
            # self.main([p_xml], [])

    def test_export(self):
        for test_name in all_files:
            test_file = f"resources/{test_name}"
            self.main([test_file], ["--export", "final-cut-pro:version=10"])
            self.main([test_file], ["--export", "final-cut-pro:version=11"])
            self.main([test_file], ["-exs"])
            self.main([test_file], ["--stats"])

    def test_clip_sequence(self) -> None:
        for test_name in all_files:
            test_file = f"resources/{test_name}"
            self.main([test_file], ["--export", "clip-sequence"])

    def test_codecs(self) -> None:
        self.main(["example.mp4"], ["--video-codec", "h264"])
        self.main(["example.mp4"], ["--audio-codec", "ac3"])

    # Issue #241
    def test_multi_track_edit(self):
        out = self.main(
            ["example.mp4", "resources/multi-track.mov"],
            ["--edit", "audio:stream=1"],
            "multi-track_ALTERED.mov",
        )
        assert len(fileinfo(out).audios) == 2

    def test_concat(self):
        out = self.main(["example.mp4"], ["--cut-out", "0,171"], "hmm.mp4")
        self.main(["example.mp4", out], ["--debug"])

    def test_concat_mux_tracks(self):
        inputs = ["example.mp4", "resources/multi-track.mov"]
        out = self.main(inputs, ["--mix-audio-streams"], "concat_mux.mov")
        assert len(fileinfo(out).audios) == 1

    def test_concat_multi_tracks(self):
        out = self.main(
            ["resources/multi-track.mov", "resources/multi-track.mov"], [], "out.mov"
        )
        assert len(fileinfo(out).audios) == 2
        inputs = ["example.mp4", "resources/multi-track.mov"]
        out = self.main(inputs, [], "out.mov")
        assert len(fileinfo(out).audios) == 2

    def test_frame_rate(self):
        cn = fileinfo(self.main(["example.mp4"], ["-r", "15", "--no-seek"], "fr.mp4"))
        video = cn.videos[0]
        assert video.fps == 15, video.fps
        assert video.duration - 17.33333333333333333333333 < 3, video.duration

        cn = fileinfo(self.main(["example.mp4"], ["-r", "20"], "fr.mp4"))
        video = cn.videos[0]
        assert video.fps == 20, video.fps
        assert video.duration - 17.33333333333333333333333 < 2

    def test_frame_rate_60(self):
        cn = fileinfo(self.main(["example.mp4"], ["-r", "60"], "fr60.mp4"))
        video = cn.videos[0]

        assert video.fps == 60, video.fps
        assert video.duration - 17.33333333333333333333333 < 0.3

    # def embedded_image(self):
    #     out1 = self.main(["resources/embedded-image/h264-png.mp4"], [])
    #     cn = fileinfo(out1)
    #     assert cn.videos[0].codec == "h264"
    #     assert cn.videos[1].codec == "png"

    #     out2 = self.main(["resources/embedded-image/h264-mjpeg.mp4"], [])
    #     cn = fileinfo(out2)
    #     assert cn.videos[0].codec == "h264"
    #     assert cn.videos[1].codec == "mjpeg"

    #     out3 = self.main(["resources/embedded-image/h264-png.mkv"], [])
    #     cn = fileinfo(out3)
    #     assert cn.videos[0].codec == "h264"
    #     assert cn.videos[1].codec == "png"

    #     out4 = self.main(["resources/embedded-image/h264-mjpeg.mkv"], [])
    #     cn = fileinfo(out4)
    #     assert cn.videos[0].codec == "h264"
    #     assert cn.videos[1].codec == "mjpeg"

    def test_motion(self):
        self.main(
            ["resources/only-video/man-on-green-screen.mp4"],
            ["--edit", "motion", "--margin", "0"],
        )
        self.main(
            ["resources/only-video/man-on-green-screen.mp4"],
            ["--edit", "motion:threshold=0,width=200"],
        )

    def test_edit_positive(self):
        self.main(["resources/multi-track.mov"], ["--edit", "audio:stream=all"])
        self.main(["resources/multi-track.mov"], ["--edit", "not audio:stream=all"])
        self.main(
            ["resources/multi-track.mov"],
            ["--edit", "(or (not audio:threshold=4%) audio:stream=1)"],
        )
        self.main(
            ["resources/multi-track.mov"],
            ["--edit", "(or (not audio:threshold=4%) (not audio:stream=1))"],
        )

    def test_edit_negative(self):
        self.check(
            ["resources/wav/example-cut-s16le.wav", "--edit", "motion"],
            "video stream",
        )
        self.check(
            ["resources/only-video/man-on-green-screen.gif", "--edit", "audio"],
            "audio stream",
        )

    def test_yuv442p(self):
        self.main(["resources/test_yuv422p.mp4"], [])

    def test_prores(self):
        out = self.main(["resources/testsrc.mp4"], ["-c:v", "prores"], "prores.mkv")
        assert fileinfo(out).videos[0].pix_fmt == "yuv422p10le"

        out2 = self.main([out], ["-c:v", "prores"], "prores2.mkv")
        assert fileinfo(out2).videos[0].pix_fmt == "yuv422p10le"

    def test_decode_hevc(self):
        out = self.main(["resources/testsrc-hevc.mp4"], ["-c:v", "h264"]) + ".mp4"
        output = fileinfo(out)
        assert output.videos[0].codec == "h264"
        assert output.videos[0].pix_fmt == "yuv420p"

    def test_encode_hevc(self):
        if len(os.getenv("DISABLE_HEVC", "")) > 0:
            raise SkipTest()
        out = self.main(["resources/testsrc.mp4"], ["-c:v", "hevc"], "out.mkv")
        output = fileinfo(out)
        assert output.videos[0].codec == "hevc"
        assert output.videos[0].pix_fmt == "yuv420p"

    #  Issue 280
    def test_SAR(self) -> None:
        out = self.main(["resources/SAR-2by3.mp4"], [], "2by3_out.mp4")
        assert fileinfo(out).videos[0].sar == Fraction(2, 3)

    def test_audio_norm_f(self) -> None:
        self.main(["example.mp4"], ["--audio-normalize", "#f"])

    def test_audio_norm_ebu(self) -> None:
        self.main(
            ["example.mp4"], ["--audio-normalize", "ebu:i=-5,lra=20,gain=5,tp=-1"]
        )


def run_tests(tests: list[Callable], args) -> None:
    if args.only != []:
        tests = list(filter(lambda t: t.__name__ in args.only, tests))

    total_time = 0.0
    real_time = perf_counter()
    passed = 0
    total = len(tests)

    def timed_test(test_func):
        start_time = perf_counter()
        skipped = False
        try:
            test_func()
            success = True
        except SkipTest:
            skipped = True
        except Exception as e:
            success = False
            exception = e
        end_time = perf_counter()
        duration = end_time - start_time

        if skipped:
            return (SkipTest, duration, None)
        elif success:
            return (True, duration, None)
        else:
            return (False, duration, exception)

    with concurrent.futures.ThreadPoolExecutor() as executor:
        future_to_data = {}
        for test in tests:
            future = executor.submit(timed_test, test)
            future_to_data[future] = test

        index = 0
        for future in concurrent.futures.as_completed(future_to_data):
            test = future_to_data[future]
            name = test.__name__
            success, dur, exception = future.result()
            total_time += dur
            index += 1

            msg = f"{name:<26} ({index}/{total})  {round(dur, 2):<5} secs  "
            if success == SkipTest:
                passed += 1
                print(f"{msg}[\033[38;2;125;125;125;mSKIPPED\033[0m]", flush=True)
            elif success:
                passed += 1
                print(f"{msg}[\033[1;32mPASSED\033[0m]", flush=True)
            else:
                print(f"{msg}\033[1;31m[FAILED]\033[0m", flush=True)
                if args.no_failfast:
                    print(f"\n{exception}")
                else:
                    print("")
                    raise exception

    real_time = round(perf_counter() - real_time, 2)
    total_time = round(total_time, 2)
    print(
        f"\nCompleted  {passed}/{total}\nreal time: {real_time} secs   total: {total_time} secs"
    )


def main():
    args = test_options().parse_args()
    run = Runner()
    tests = []
    test_methods = {
        name: getattr(run, name)
        for name in dir(Runner)
        if callable(getattr(Runner, name)) and name not in ["main", "raw", "check"]
    }
    tests.extend([test_methods[name] for name in ["info", "levels", "subdump", "desc"]])
    tests.extend(
        [
            getattr(run, name)
            for name in dir(Runner)
            if callable(getattr(Runner, name)) and name.startswith("test_")
        ]
    )
    try:
        run_tests(tests, args)
    except KeyboardInterrupt:
        print("Testing Interrupted by User.")
        shutil.rmtree(run.temp_dir)
        sys.exit(1)
    shutil.rmtree(run.temp_dir)


if __name__ == "__main__":
    main()
