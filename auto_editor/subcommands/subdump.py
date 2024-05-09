import sys

import av


def main(sys_args: list[str] = sys.argv[1:]) -> None:
    for i, input_file in enumerate(sys_args):
        with av.open(input_file) as container:
            for s in range(len(container.streams.subtitles)):
                print(f"file: {input_file} ({s}:{container.streams.subtitles[s].name})")
                for packet in container.demux(subtitles=s):
                    for sub in packet.decode():
                        for val in sub.rects:
                            if isinstance(val, av.subtitles.subtitle.AssSubtitle):
                                print(val.ass.decode("utf-8", "ignore"))
                            elif isinstance(val, av.subtitles.subtitle.TextSubtitle):
                                print(val.text.decode("utf-8", "ignore"))
        print("------")


if __name__ == "__main__":
    main()
