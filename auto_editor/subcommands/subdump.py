import sys
from dataclasses import dataclass, field

from auto_editor.utils.log import Log

import av


def main(sys_args: list[str] = sys.argv[1:]) -> None:
    for i, input_file in enumerate(sys_args):
        with av.open(input_file) as container:
            for s in range(len(container.streams.subtitles)):
                print(f"file: {input_file} ({s})")
                for packet in container.demux(subtitles=s):
                    for item in packet.decode():
                        if type(item) is av.subtitles.subtitle.SubtitleSet and item:
                            if item[0].type == b"ass":
                                print(item[0].ass.decode("utf-8"))
                            else:
                                print(item[0].text)
        print("------")



if __name__ == "__main__":
    main()
