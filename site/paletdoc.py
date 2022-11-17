from __future__ import annotations
from dataclasses import dataclass

@dataclass
class code:
    child: str


@dataclass
class text:
    children: list[str | code]


@dataclass
class proc:
    name: str
    procsig: tuple[list[str], str]
    argsig: list[tuple[str, str] | tuple[str, str, str]]
    summary: text


@dataclass
class syntax
    name: str
    summary: text


@dataclass
class value:
    name: str
    argsig: str
    summary: text

doc: dict[str, list[proc | value]] = {
    "Syntax": [
        syntax("define", )
    ],
    "Equality": [
        proc(
            "equal?",
            (["v1", "v2"], "boolean?"),
            [("v1", "any"), ("v2", "any")],
            text([
                "Returns ", code("#t"), " if ", code("v1"), " and ", code("v2"),
                " are the same type and have the same value, ", code("#f"), " otherwise."
            ]),
        )
    ],
    "Booleans": [
        proc(
            "boolean?",
            (["v"], "boolean?"),
            [("v", "any")],
            text([
                "Returns ", code("#t"), " if ", code("v"), " is ", code("#t"), " or ",
                code("#f"), ", ", code("#f"), " otherwise."
            ]),
        ),
        value("true", "boolean?", text(["An alias for ", code("#t"), "."])),
        value("false", "boolean?", text(["An alias for ", code("#f"), "."])),
    ],
    "Number Types": [
        proc(
            "number?",
            (["v"], "boolean?"),
            [("v", "any")],
            text([
                "Returns ", code("#t"), " if ", code("v"), " is a number, ", code("#f"),
                " otherwise.",
            ]),
        ),
        proc(
            "real?",
            (["v"], "boolean?"),
            [("v", "any")],
            text([
                "Returns ", code("#t"), " if ", code("v"), " is a real number, ",
                code("#f"), " otherwise.",
            ]),
        ),
        proc(
            "integer?",
            (["v"], "boolean?"),
            [("v", "any")],
            text([
                "Returns ", code("#t"), " if ", code("v"),
                " is an integer or a number that can be coerced to an integer without changing value, ",
                code("#f"), " otherwise.",
            ]),
        ),
        proc(
            "exact-integer?",
            (["v"], "boolean?"),
            [("v", "any")],
            text([
                "Returns ", code("#t"), " if ", code("v"), " is an integer and exact, ",
                code("#f"), " otherwise.",
            ]),
        ),
        proc(
            "exact-nonnegative-integer?",
            (["v"], "boolean?"),
            [("v", "any")],
            text([
                "Returns ", code("#t"), " if ", code("v"), " is an exact integer and "
                code("v"), "is greater than -1, ", code("#f"), " otherwise.",
            ]),
        ),
        proc(
            "zero?",
            (["v"], "boolean?"),
            [("v", "any")],
            text([
                "Returns ", code("#t"), " if ", code("v"), " is ", code("0"), ", ", code("#f"),
                " otherwise."
            ]),
        ),
        proc(
            "positive?",
            (["v"], "boolean?"),
            [("v", "any")],
            text([
                "Returns ", code("#t"), " if ", code("v"), " is greater than 0, ", code("#f"),
                " otherwise."
            ]),
        ),
        proc(
            "negative?",
            (["v"], "boolean?"),
            [("v", "any")],
            text([
                "Returns ", code("#t"), " if ", code("v"), " is less than 0, ", code("#f"),
                " otherwise."
            ]),
        ),
    ],
    "Numbers": [
        proc(
            "+",
            (["z", "..."], "number?"),
            [("z", "number?")],
            text([
                "Return the sum of ", code("z"),
                "s. Add from left to right. If no arguments are provided, the result is ",
                code("0"), ".",
            ]),
        ),
        proc(
            "-",
            (["z", "w", "..."], "number?"),
            [("z", "number?"), ("w", "number?")],
            text([
                "When no ", code("w"), "s are applied, return", code("(- 0 z)"),
                ". Otherwise, return the subtraction of ", code("w"), "s of ", code("z"),
                ".",
            ]),
        ),
        proc(
            "*",
            (["z", "..."], "number?"),
            [("z", "number?")],
            text([
                "Return the product of ", code("z"), "s. If no ", code("z"),
                "s are supplied, the result is ", code("1"), ".",
            ]),
        ),
        proc(
            "/",
            (["z", "w", "..."], "number?"),
            [("z", "number?"), ("w", "number?")],
            text([
                "When no ", code("w"), "s are applied, return ", code("(/ 1 z)"),
                ". Otherwise, return the division of ", code("w"), "s of ", code("z"),
                ".",
            ]),
        ),
        proc(
            "mod",
            (["n", "m"], "integer?"),
            [("n", "integer?"), ("m", "integer?")],
            text(["Return the modulo of ", code("n"), " and ", code("m"), "."]),
        ),
        proc(
            "modulo",
            (["n", "m"], "integer?"),
            [("n", "integer?"), ("m", "integer?")],
            text(["Clone of ", code("mod"), "."]),
        ),
        proc(
            "add1",
            (["z"], "number?"),
            [("z", "number?")],
            text(["Returns ", code("(+ z 1)"), "."]),
        ),
        proc("sub1",
            (["z"], "number?"),
            [("z", "number?")],
            text(["Returns ", code("(- z 1)"), "."]),
        ),
        proc(
            "=",
            (["z", "w", "..."], "boolean?"),
            [("z", "number?"), ("w", "number?")],
            text([
                "Returns ", code("#t"), " if all arguments are numerically equal, ",
                code("#f"), " otherwise.",
            ]),
        ),
        proc(
            "<",
            (["x", "y"], "boolean?"),
            [("x", "real?"), ("y", "real?")],
            text([
                "Returns ", code("#t"), " if ", code("x"), " is less than ", code("y"),
                ", ", code("#f"), " otherwise.",
            ]),
        ),
        proc(
            "<=",
            (["x", "y"], "boolean?"),
            [("x", "real?"), ("y", "real?")],
            text([
                "Returns ", code("#t"), " if ", code("x"), " is less than or equal to ",
                code("y"), ", ", code("#f"), " otherwise.",
            ]),
        ),
        proc(
            ">",
            (["x", "y"], "boolean?"),
            [("x", "real?"), ("y", "real?")],
            text([
                "Returns ", code("#t"), " if ", code("x"), " is greater than ", code("y"),
                ", ", code("#f"), " otherwise.",
            ]),
        ),
        proc(
            ">=",
            (["x", "y"], "boolean?"),
            [("x", "real?"), ("y", "real?")],
            text([
                "Returns ", code("#t"), " if ", code("x"), " is greater than or equal to ",
                code("y"), ", ", code("#f"), " otherwise.",
            ]),
        ),
        proc(
            "abs",
            (["x"], "real?"),
            [("x", "real?")],
            text(["Returns the absolute value of ", code("x"), "."]),
        ),
        proc(
            "max",
            (["x", "..."], "real?"),
            [("x", "real?")],
            text(["Returns largest value of the ", code("x"), "s."]),
        ),
        proc(
            "min",
            (["x", "..."], "real?"),
            [("x", "real?")],
            text(["Returns smallest value of the ", code("x"), "s."]),
        ),
    ],
    "Vectors": [
        proc(
            "vector?",
            (["v"], "boolean?"),
            [("v", "any")],
            text([
                "Returns ", code("#t"), " if ", code("v"), " is a vector, ",
                code("#f"), " otherwise."
            ]),
        ),
        proc(
            "vector",
            (["v", "..."], "vector?"),
            [("v", "any")],
            text([
                "Returns a new vector with ",
                code("v"), "s filled its slots in order."
            ]),
        ),
        proc(
            "vector-length",
            (["vec"], "exact-nonnegative-integer?"),
            [("vec", "vector?")],
            text(["Returns the length of ", code("vec"), "."]),
        ),
        proc(
            "vector-ref",
            (["vec", "pos"], "any"),
            [("vec", "vector?"), ("pos", "exact-integer?")],
            text([
                "Returns the element in slot ", code("pos"), " of ", code("vec"),
                ". Vectors are 0-index based. ", code("-1"), " and ", code("-2"),
                " will return the last and the second last elements respectively.",
            ]),
        ),
        proc(
            "make-vector",
            (["size", "[v]"], "vector?"),
            [("size", "exact-nonnegative-integer"), ("v", "any", "0")],
            text([
                "Returns a new vector with ", code("size"),
                " slots, all filled with ", code("v"), "s."
            ]),
        ),
        proc(
            "vector-pop!",
            (["vec"], "any"),
            [("vec", "vector?")],
            text(["Remove the last element of ", code("vec"), " and return it."]),
        ),
        proc(
            "vector-add!",
            (["vec", "v"], "none"),
            [("vec", "vector?"), ("v", "any")],
            text(["Append ", code("v"), " to the end of ", code("vec"), "."]),
        ),
        proc(
            "vector-set!",
            (["vec", "pos", "v"], "none"),
            [("vec", "vector?"), ("pos", "exact-integer?"), ("v", "any")],
            text(["Set slot ", code("pos"), " of ", code("vec"), " to ", code("v"), "."]),
        ),
        proc(
            "vector-extend!",
            (["vec", "vec2", "..."], "none"),
            [("vec", "vector?"), ("vec2", "vector?")],
            text([
                "Append all elements of ", code("vec2"), " to the end of ",
                code("vec"), " in order.",
            ]),
        ),
    ],
}
