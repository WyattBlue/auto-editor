from __future__ import annotations

from io import StringIO, TextIOWrapper
from typing import TYPE_CHECKING

from auto_editor.ffwrapper import FileInfo
from auto_editor.lib.err import MyError

if TYPE_CHECKING:
    from typing import Any, NoReturn

    from _typeshed import SupportsWrite


class Token:
    __slots__ = ("type", "value")

    def __init__(self, type: int, value: object):
        self.type = type
        self.value = value

    def __str__(self) -> str:
        return f"{self.type=} {self.value=}"

    __repr__ = __str__


EOF, LCUR, RCUR, LBRAC, RBRAC, COL, COMMA, STR, VAL = range(9)
table = {
    "{": LCUR,
    "}": RCUR,
    "[": LBRAC,
    "]": RBRAC,
    ":": COL,
    ",": COMMA,
}
str_escape = {
    "\\": "\\",
    "/": "/",
    '"': '"',
    "b": "\b",
    "f": "\f",
    "n": "\n",
    "r": "\r",
    "t": "\t",
}


def normalize_string(v: str) -> str:
    for to, replace in str_escape.items():
        if to == "/":
            continue
        v = v.replace(replace, f"\\{to}")
    return v


class Lexer:
    __slots__ = ("filename", "text", "pos", "char", "lineno", "column")

    def __init__(self, filename: str, text: str | bytes | TextIOWrapper):
        self.filename = filename
        self.pos: int = 0
        self.lineno: int = 1
        self.column: int = 1

        if isinstance(text, bytes):
            self.text: str = text.decode("utf-8", "replace")
        elif isinstance(text, str):
            self.text = text
        else:
            self.text = text.read()

        self.char: str | None = self.text[self.pos] if text else None

    def error(self, msg: str) -> NoReturn:
        raise MyError(f"{msg}\n  at {self.filename}:{self.lineno}:{self.column}")

    def advance(self) -> None:
        if self.char == "\n":
            self.lineno += 1
            self.column = 0

        self.pos += 1

        if self.pos > len(self.text) - 1:
            self.char = None
        else:
            self.char = self.text[self.pos]
            self.column += 1

    def peek(self) -> str | None:
        peek_pos = self.pos + 1
        return None if peek_pos > len(self.text) - 1 else self.text[peek_pos]

    def string(self) -> str:
        result = StringIO()
        while self.char is not None and self.char != '"':
            if self.char == "\\":
                self.advance()
                if self.char is None:
                    break

                if self.char == "u":
                    buf = ""
                    for i in range(4):
                        self.advance()
                        if self.char is None:
                            self.error("\\u escape sequence needs 4 hexs")
                        buf += self.char
                    try:
                        result.write(chr(int(buf, 16)))
                    except ValueError:
                        self.error(f"Invalid \\u escape sequence: `{buf}`")
                if self.char in str_escape:
                    result.write(str_escape[self.char])
                    self.advance()
                    continue

                self.error(f"Unknown escape sequence `\\{self.char}` in string")
            else:
                result.write(self.char)
            self.advance()

        if self.char is None:
            self.error('Expected a closing `"`')

        self.advance()
        return result.getvalue()

    def number(self) -> Token:
        buf = StringIO()

        has_dot = False
        while self.char is not None and self.char in "-0123456789.":
            if self.char == ".":
                if has_dot:
                    self.error("Number has multiple `.`s")
                has_dot = True
            buf.write(self.char)
            self.advance()

        result = buf.getvalue()

        try:
            return Token(VAL, float(result) if has_dot else int(result))
        except ValueError:
            self.error(f"`{result}` is not a valid JSON Number")

    def is_whitespace(self) -> bool:
        return self.char is None or self.char in " \t\n\r\x0b\x0c"

    def get_next_token(self) -> Token:
        while self.char is not None:
            while self.char is not None and self.is_whitespace():
                self.advance()
            if self.char is None:
                break

            if self.char == '"':
                self.advance()
                return Token(STR, self.string())

            if self.char == "-":
                _peek = self.peek()
                if _peek is not None and _peek in "0123456789.":
                    return self.number()

            if self.char in "0123456789.":
                return self.number()

            if self.char in table:
                key = table[self.char]
                self.advance()
                return Token(key, None)

            keyword = ""
            for i in range(5):  # Longest valid keyword length
                if self.char is None or self.char in " \t\n\r\x0b\x0c[]}{,":
                    break
                keyword += self.char
                self.advance()

            if keyword == "true":
                return Token(VAL, True)
            if keyword == "false":
                return Token(VAL, False)
            if keyword == "null":
                return Token(VAL, None)

            self.error(f"Invalid keyword: `{keyword}`")
        return Token(EOF, None)


class Parser:
    __slots__ = ("lexer", "current_token")

    def __init__(self, lexer: Lexer):
        self.lexer = lexer
        self.current_token = self.lexer.get_next_token()

    def eat(self) -> None:
        self.current_token = self.lexer.get_next_token()

    def expr(self) -> Any:
        self.current_token

        if self.current_token.type in (STR, VAL):
            val = self.current_token.value
            self.eat()
            return val

        if self.current_token.type == LCUR:
            self.eat()

            my_dic = {}
            while self.current_token.type != RCUR:
                if self.current_token.type != STR:
                    if self.current_token.type in (LBRAC, VAL):
                        self.lexer.error("JSON Objects only allow strings as keys")
                    self.lexer.error("Expected closing `}`")
                key = self.current_token.value
                if key in my_dic:
                    self.lexer.error(f"Object has repeated key `{key}`")
                self.eat()
                if self.current_token.type != COL:
                    self.lexer.error("Expected `:`")
                self.eat()

                my_dic[key] = self.expr()
                if self.current_token.type != RCUR:
                    if self.current_token.type != COMMA:
                        self.lexer.error("Expected `,` between Object entries")
                    self.eat()
                    if self.current_token.type == RCUR:
                        self.lexer.error("Trailing `,` in Object")

            self.eat()
            return my_dic

        if self.current_token.type == LBRAC:
            self.eat()
            my_arr = []
            while self.current_token.type != RBRAC:
                my_arr.append(self.expr())
                if self.current_token.type != RBRAC:
                    if self.current_token.type != COMMA:
                        self.lexer.error("Expected `,` between array entries")
                    self.eat()
                    if self.current_token.type == RBRAC:
                        self.lexer.error("Trailing `,` in array")
            self.eat()
            return my_arr

        raise MyError(f"Unknown token: {self.current_token}")


def dump(
    data: object, file: SupportsWrite[str], indent: int | None = None, level: int = 0
) -> None:
    if data is True:
        file.write("true")
    elif data is False:
        file.write("false")
    elif data is None:
        file.write("null")
    elif isinstance(data, str):
        file.write(f'"{normalize_string(data)}"')
    elif isinstance(data, FileInfo):
        file.write(f'"{normalize_string(f"{data.path}")}"')
    elif isinstance(data, int | float):
        file.write(f"{data}")
    elif isinstance(data, list | tuple):
        file.write("[")
        if indent is not None:
            level += indent
            file.write("\n" + (" " * level))

        for item in data[:-1]:
            dump(item, file, indent, level)
            file.write(", " if indent is None else f",\n{' ' * level}")
        if data:
            dump(data[-1], file, indent, level)
        file.write("]" if indent is None else f"\n{' ' * (level - indent)}]")
    else:
        my_dic = data if isinstance(data, dict) else data.__dict__
        file.write("{")
        if indent is not None:
            level += indent
            file.write("\n" + (" " * level))
        not_first = False
        for key, item in my_dic.items():
            if not_first:
                file.write(", " if indent is None else f",\n{' ' * level}")
            dump(key, file, indent, level)
            file.write(": ")
            dump(item, file, indent, level)
            not_first = True

        if indent is not None:
            file.write(f"\n{' ' * (level - indent)}")
        file.write("}")
