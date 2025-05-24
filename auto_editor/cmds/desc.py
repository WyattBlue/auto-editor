import sys
from dataclasses import dataclass, field

import bv

from auto_editor.vanparse import ArgumentParser


@dataclass(slots=True)
class DescArgs:
    help: bool = False
    input: list[str] = field(default_factory=list)


def desc_options(parser: ArgumentParser) -> ArgumentParser:
    parser.add_required("input", nargs="*")
    return parser


def main(sys_args: list[str] = sys.argv[1:]) -> None:
    args = desc_options(ArgumentParser("desc")).parse_args(DescArgs, sys_args)
    for path in args.input:
        try:
            container = bv.open(path)
            desc = container.metadata.get("description", None)
        except Exception:
            desc = None
        sys.stdout.write("\nNo description.\n\n" if desc is None else f"\n{desc}\n\n")


if __name__ == "__main__":
    main()
