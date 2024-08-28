#!/usr/bin/env python3

import os
import sys

# Put 'auto_editor' in Python path
sys.path.append(os.path.dirname(os.path.dirname(__file__)))

import auto_editor.vanparse as vanparse
from auto_editor.__main__ import main_options
from auto_editor.lang.palet import Lexer, Parser, env, interpret
from auto_editor.lang.stdenv import make_standard_env
from auto_editor.vanparse import OptionText


def main():
    parser = vanparse.ArgumentParser("Auto-Editor")
    parser = main_options(parser)

    with open("src/ref/options.html", "w") as file:
        file.write(
            '{{ header-desc "Options" "These are the options and flags that auto-editor uses." }}\n'
            "<body>\n"
            "{{ nav }}\n"
            '<section class="section">\n'
            '<div class="container">\n'
        )
        for op in parser.args:
            if isinstance(op, OptionText):
                file.write(f"<h2>{op.text}</h2>\n")
            else:
                file.write(f"<h3><code>{op.names[0]}</code></h3>\n")
                if len(op.names) > 1:
                    file.write(
                        "<h4><code>"
                        + "</code> <code>".join(op.names[1:])
                        + "</code></h4>\n"
                    )

                file.write(f"<p>{op.help}</p>\n")

        file.write("</div>\n</section>\n</body>\n</html>\n\n")

    env.update(make_standard_env())
    with open("doc.pal") as sourcefile:
        try:
            interpret(env, Parser(Lexer("doc.pal", sourcefile.read())))
        except Exception as e:
            print(e)
            quit(1)

if __name__ == "__main__":
    main()
