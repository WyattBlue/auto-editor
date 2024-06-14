import os
import sys

import av
import av._core

av.logging.set_level(av.logging.VERBOSE)


def remux(
    prompt: bool, vn: bool, an: bool, sn: bool, input_file: str, output_file: str
) -> None:
    try:
        input_container = av.open(input_file, "r")
    except av.error.FileNotFoundError:
        sys.stderr.write(f"Error opening input file {input_file}.\n")
        sys.exit(1)

    if prompt and os.path.exists(output_file):
        result = input(f"File '{output_file}' already exists. Overwrite? [y/N] ")
        if result.lower() != "y":
            sys.stderr.write("Not overwriting - exiting\n")
            sys.exit(1)

    output_container = av.open(output_file, "w")

    stream_mapping: dict[int, av.stream.Stream] = {}
    for stream in input_container.streams:
        if (
            (stream.type == "video" and vn)
            or (stream.type == "audio" and an)
            or (stream.type == "subtitle" and sn)
        ):
            continue

        output_stream = output_container.add_stream(template=stream)
        stream_mapping[stream.index] = output_stream

    for packet in input_container.demux():
        if packet.dts is None:
            continue

        if packet.stream.index in stream_mapping:
            packet.stream = stream_mapping[packet.stream.index]
            output_container.mux(packet)

    input_container.close()
    output_container.close()


def parse_args(args: list[str]) -> None:
    inputs = []
    outputs = []

    print_bf = False
    print_banner = True
    prompt = True
    vn = False
    an = False
    sn = False

    i = 0
    while i < len(args):
        arg = args[i]

        if arg == "-y":
            prompt = False
        elif arg == "-hide_banner":
            print_banner = False
        elif arg == "-vn":
            vn = True
        elif arg == "-an":
            an = True
        elif arg == "-sn":
            sn = True
        elif arg == "-bsfs":
            print_bf = True
        elif arg == "-i":
            i += 1
            if i < len(args):
                inputs.append(args[i])
        else:
            outputs.append(arg)
        i += 1

    if print_banner:
        by_config = {}
        for libname, config in sorted(av._core.library_meta.items()):
            version = config["version"]
            if version[0] >= 0:
                by_config.setdefault(
                    (config["configuration"], config["license"]), []
                ).append((libname, config))

        sys.stderr.write("ffmpeg version 6.1.1\n")
        sys.stderr.write("  built with\n")
        for (config, license), libs in by_config.items():
            sys.stderr.write(f"  configuration: {config}\n")
            for libname, config in libs:
                version = config["version"]
                sys.stderr.write(
                    f"  {libname:<13} {version[0]:3d}.{version[1]:3d}.{version[2]:3d}\n"
                )

    if print_bf:
        print("Bitstream filters:")
        return

    if not outputs:
        if args:
            sys.stderr.write("At least one output file must be specified\n")
        sys.exit(1)

    if not inputs:
        sys.stderr.write("Output file does not contain any stream\n")
        sys.exit(1)

    remux(prompt, vn, an, sn, inputs[0], outputs[0])


def main(sys_args: list[str] = sys.argv[1:]) -> None:
    parse_args(sys_args)


if __name__ == "__main__":
    main()
