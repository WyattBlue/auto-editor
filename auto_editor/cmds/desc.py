from __future__ import annotations

import sys
from dataclasses import dataclass, field

from auto_editor.ffwrapper import initFileInfo
from auto_editor.utils.log import Log
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
        src = initFileInfo(path, Log())
        if src.description is not None:
            sys.stdout.write(f"\n{src.description}\n\n")
        else:
            sys.stdout.write("\nNo description.\n\n")


if __name__ == "__main__":
    main()
