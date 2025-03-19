import sys
from dataclasses import dataclass, field

import bv
from bv.subtitles.subtitle import AssSubtitle

from auto_editor.json import dump
from auto_editor.vanparse import ArgumentParser


@dataclass(slots=True)
class SubdumpArgs:
    help: bool = False
    input: list[str] = field(default_factory=list)
    json: bool = False


def main(sys_args: list[str] = sys.argv[1:]) -> None:
    parser = ArgumentParser("subdump")
    parser.add_required("input", nargs="*")
    parser.add_argument("--json", flag=True)
    args = parser.parse_args(SubdumpArgs, sys_args)

    do_filter = True

    if args.json:
        data = {}
        for input_file in args.input:
            container = bv.open(input_file)
            for s in range(len(container.streams.subtitles)):
                entry_data = []

                input_stream = container.streams.subtitles[s]
                assert input_stream.time_base is not None
                for packet in container.demux(input_stream):
                    if (
                        packet.dts is None
                        or packet.pts is None
                        or packet.duration is None
                    ):
                        continue

                    start = packet.pts * input_stream.time_base
                    end = start + packet.duration * input_stream.time_base

                    startf = round(float(start), 3)
                    endf = round(float(end), 3)

                    if do_filter and endf - startf <= 0.02:
                        continue

                    for sub in packet.decode():
                        if isinstance(sub, AssSubtitle):
                            content = sub.dialogue.decode("utf-8", errors="ignore")
                            entry_data.append([startf, endf, content])

                data[f"{input_file}:{s}"] = entry_data
            container.close()

        dump(data, sys.stdout, indent=4)
        return

    for i, input_file in enumerate(args.input):
        with bv.open(input_file) as container:
            for s in range(len(container.streams.subtitles)):
                print(f"file: {input_file} ({s}:{container.streams.subtitles[s].name})")
                for sub2 in container.decode(subtitles=s):
                    if isinstance(sub2, AssSubtitle):
                        print(sub2.ass.decode("utf-8", errors="ignore"))
        print("------")


if __name__ == "__main__":
    main()
