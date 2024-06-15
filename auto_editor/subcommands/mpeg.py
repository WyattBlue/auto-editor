import os
import sys
from dataclasses import dataclass

import av
import av._core
from av.container import InputContainer, OutputContainer


@dataclass(slots=True)
class AvLog:
    level_set: int

    def level(self, val: int, msg: str) -> None:
        if self.level_set < val:
            return

        if val == 24:
            sys.stderr.write(f"\033[38;5;226;40m{msg}\033[0m\n")
        elif val == 16:
            sys.stderr.write(f"\033[38;5;208;40m{msg}\033[0m\n")
        elif val == 8:
            sys.stderr.write(f"\033[31;40m{msg}\033[0m\n")
        else:
            sys.stderr.write(f"{msg}\n")


def transcode(
    log: AvLog,
    vn: bool,
    an: bool,
    sn: bool,
    input_container: InputContainer,
    output_container: OutputContainer,
) -> None:
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


def parse_loglevel(args: list[str]) -> tuple[int, bool]:
    log_level = 32
    hide_banner = False

    def parse_level(v: str) -> int:
        if v in ("quiet", "-8"):
            return -8
        if v in ("panic", "0"):
            return 0
        if v in ("fatal", "8"):
            return 8
        if v in ("error", "16"):
            return 16
        if v in ("warning", "24"):
            return 24
        if v in ("info", "32"):
            return 32
        if v in ("verbose", "40"):
            return 40
        if v in ("debug", "48"):
            return 48
        if v in ("trace", "56"):
            return 56
        return 0

    i = 0
    while i < len(args):
        arg = args[i]
        if arg == "-hide_banner":
            hide_banner = True
        elif arg == "-loglevel":
            i += 1
            log_level = parse_level(args[i])
        i += 1

    return log_level, hide_banner


def parse_args(log: AvLog, hide_banner: bool, args: list[str]) -> None:
    inputs = []
    outputs = []

    print_bf = False
    overwrite = None
    vn = False
    an = False
    sn = False

    i = 0
    while i < len(args):
        arg = args[i]

        if arg == "-y":
            overwrite = True
        elif arg == "-n":
            overwrite = False
        elif arg == "-hide_banner":
            pass
        elif arg == "-log_level":
            i += 1
            pass
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

    if not hide_banner:
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

    if not outputs and not inputs:
        sys.stderr.write(
            "Universal media converter\nusage: ffmpeg [options] [[infile options] -i infile]... {[outfile options] outfile}...\n\n"
        )
        log.level(24, "Use -h to get full help or, even better, run 'man ffmpeg'")

    if not outputs:
        if args:
            log.level(16, "At least one output file must be specified")
        sys.exit(1)

    if not inputs:
        log.level(8, "Output file does not contain any stream")
        sys.exit(1)

    input_containers = []
    for input_file in inputs:
        try:
            input_containers.append(av.open(input_file, "r"))
        except av.error.FileNotFoundError:
            log.level(8, f"Error opening input file {input_file}.")
            sys.exit(1)

    output_containers = []
    for output_file in outputs:
        if os.path.exists(output_file):
            if overwrite is None:
                res = input(f"File '{output_file}' already exists. Overwrite? [y/N] ")
                if res.lower() != "y":
                    log.level(16, "Not overwriting - exiting")
                    sys.exit(1)
            elif not overwrite:
                log.level(16, f"File '{output_file}' already exists. Exiting.")
                log.level(8, f"Error opening output file {output_file}.")
                sys.exit(1)

        output_containers.append(av.open(output_file, "w"))

    transcode(log, vn, an, sn, input_containers[0], output_containers[0])


def main(sys_args: list[str] = sys.argv[1:]) -> None:
    log_level, hide_banner = parse_loglevel(sys_args)
    parse_args(AvLog(log_level), hide_banner, sys_args)


if __name__ == "__main__":
    main()
