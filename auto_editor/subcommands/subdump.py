import sys

import av
from av.subtitles.subtitle import AssSubtitle, TextSubtitle


def main(sys_args: list[str] = sys.argv[1:]) -> None:
    for i, input_file in enumerate(sys_args):
        with av.open(input_file) as container:
            for s in range(len(container.streams.subtitles)):
                print(f"file: {input_file} ({s}:{container.streams.subtitles[s].name})")
                for packet in container.demux(subtitles=s):
                    for subset in packet.decode():
                        for sub in subset.rects:
                            if isinstance(sub, AssSubtitle):
                                print(sub.ass.decode("utf-8", errors="ignore"))
                            elif isinstance(sub, TextSubtitle):
                                print(sub.text.decode("utf-8", errors="ignore"))
        print("------")


if __name__ == "__main__":
    main()
