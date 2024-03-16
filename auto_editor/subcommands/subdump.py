import sys

import av
from av.subtitles.subtitle import SubtitleSet


def main(sys_args: list[str] = sys.argv[1:]) -> None:
    for i, input_file in enumerate(sys_args):
        with av.open(input_file) as container:
            for s in range(len(container.streams.subtitles)):
                print(f"file: {input_file} ({s}:{container.streams.subtitles[s].name})")
                for packet in container.demux(subtitles=s):
                    for item in packet.decode():
                        if type(item) is SubtitleSet and item:
                            if item[0].type == b"ass":
                                print(item[0].ass.decode("utf-8"))
                            elif item[0].type == b"text":
                                print(item[0].text)
        print("------")


if __name__ == "__main__":
    main()
