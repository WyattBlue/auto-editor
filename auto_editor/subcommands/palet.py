from __future__ import annotations

import sys

from auto_editor.lang.palet import Lexer, Parser, env, interpret
from auto_editor.lib.err import MyError


def main(sys_args: list[str] = sys.argv[1:]) -> None:
    if sys_args:
        with open(sys_args[0], encoding="utf-8", errors="ignore") as file:
            program_text = file.read()

        try:
            interpret(env, Parser(Lexer(sys_args[0], program_text, True)))
        except (MyError, ZeroDivisionError) as e:
            sys.stderr.write(f"error: {e}\n")
            sys.exit(1)

    else:
        from .repl import main

        main(sys_args)


if __name__ == "__main__":
    main()
