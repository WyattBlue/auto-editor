from __future__ import annotations
from dataclasses import dataclass


@dataclass
class code:
    val: str


@dataclass
class var:
    val: str


@dataclass
class text:
    children: list[str | code]


@dataclass
class proc:
    name: str
    sig: tuple[list, str]
    summary: text


@dataclass
class pred:  # predicate
    name: str
    summary: text


@dataclass
class syntax:
    name: str
    body: str
    summary: text


@dataclass
class value:
    name: str
    sig: str
    summary: text


bool_t = code("#t")
bool_f = code("#f")

doc = {
    "Definitions": [
        syntax(
            "define", "id expr",
            text(["Set ", var("id"), " to the result of ", var("expr"), "."]),
        ),
        syntax(
            "set!", "id expr",
            text([
                "Set the result of ", var("expr"), " to ", var("id"), " if ",
                var("id"), " is already defined. If ", var("id"),
                " is not defined, raise an error.",
            ]),
        ),
        syntax(
            "lambda", "args body",
            text([
                "Produces a procedure that accepts ", var("args"),
                " arguments and runs ", var("body"), " when called.",
            ]),
        ),
        syntax("λ", "args body", text(["Clone of ", var("lambda"), "."])),
    ],
    "Control Flow": [
        syntax(
            "if", "test-expr then-expr else-expr",
            text([
                "Evaluates ", var("test-expr"), ". If ", bool_t, " then evaluate ",
                var("then-expr"), " else evaluate ", var("else-expr"),
                ". An error will be raised if evaluated ",
                var("test-expr"), " is not a ", code("bool?"), ".",
            ]),
        ),
        syntax(
            "when", "test-expr body",
            text([
                "Evaluates ", var("test-expr"), ". If ", bool_t, " then evaluate ",
                var("body"), " else do nothing. An error will be raised if evaluated ",
                var("test-expr"), " is not a ", code("bool?"), ".",
            ]),
        ),
        syntax(
            "cond", "([test-clause then-body]... [else then-body])",
            text([
                "Evaluate each ", var("cond-clause"), ", if the clause is evaluated to ",
                bool_t, " then evaluate and return ", var("then-body"),
                ". If the clause is ", bool_f, ", continue to the next clause. ",
                "If there are no clauses left, return ", code("#<void>"),
                ". If the last ", var("test-clause"), " is ", var("else"),
                ", then its evaluated ", var("then-body"), ".",
            ]),
        ),
    ],
    "Loops": [
        syntax(
            "for",
            "([id seq-expr] ...) body",
            text([
                "Loop over ", var("seq-expr"), " by setting the variable ", var("id"),
                " to the nth item of ", var("seq-expr"), " and evaluating ",
                var("body"), ".",
            ]),
        ),
        syntax(
            "for/vector",
            "([id seq-expr] ...) body",
            text(["Like ", code("for"),
                " but returns a vector with the last evaluated elements of ",
                code("body"), ".",
            ]),
        ),
    ],
    "Equality": [
        proc(
            "equal?",
            ([("v1", "any"), ("v2", "any")], "bool?"),
            text([
                "Returns ", bool_t, " if ", var("v1"), " and ", var("v2"),
                " are the same type and have the same value, ", bool_f, " otherwise."
            ]),
        ),
        proc(
            "eq?",
            ([("v1", "any"), ("v2", "any")], "bool?"),
            text([
                "Returns ", bool_t, " if ", var("v1"), " and ", var("v2"),
                " refer to the same object in memory, ", bool_f, " otherwise."
            ]),
        ),
    ],
    "Booleans": [
        pred(
            "bool?",
            text([
                "Returns ", bool_t, " if ", var("v"), " is ", bool_t, " or ",
                bool_f, ", ", bool_f, " otherwise."
            ]),
        ),
        value("true", "bool?", text(["An alias for ", bool_t, "."])),
        value("false", "bool?", text(["An alias for ", bool_f, "."])),
    ],
    "Number Predicates": [
        pred(
            "number?",
            text([
                "Returns ", bool_t, " if ", var("v"), " is a number, ", bool_f,
                " otherwise.",
            ]),
        ),
        pred(
            "real?",
            text([
                "Returns ", bool_t, " if ", var("v"), " is a real number, ",
                bool_f, " otherwise.",
            ]),
        ),
        pred(
            "int?",
            text([
                "Returns ", bool_t, " if ", var("v"), " is an integer, ",
                bool_f, " otherwise.",
            ]),
        ),
        pred(
            "uint?",
            text([
                "Returns ", bool_t, " if ", var("v"), " is an integer and ",
                var("v"), " is greater than -1, ", bool_f, " otherwise.",
            ]),
        ),
        pred(
            "nat?",
            text([
                "Returns ", bool_t, " if ", var("v"), " is an integer and ",
                var("v"), " is greater than 0, ", bool_f, " otherwise.",
            ]),
        ),
        pred(
            "float?",
            text([
                "Returns ", bool_t, " if ", var("v"), " is a float, ",
                bool_f, " otherwise.",
            ]),
        ),
        pred(
            "frac?",
            text([
                "Returns ", bool_t, " if ", var("v"), " is a fraction",
                " (a rational number), ", bool_f, " otherwise.",
            ]),
        ),
        proc(
            "zero?",
            ([("z", "number?")], "bool?"),
            text(["Returns ", code("(= z 0)")])
        ),
        proc(
            "positive?",
            ([("x", "real?")], "bool?"),
            text(["Returns ", code("(> x 0)")])
        ),
        proc(
            "negative?",
            ([("x", "real?")], "bool?"),
            text(["Returns ", code("(< x 0)")])
        ),
        proc(
            "even?",
            ([("n", "int?")], "bool?"),
            text(["Returns ", code("(zero? (mod n 2))")]),
        ),
        proc(
            "odd?",
            ([("n", "int?")], "bool?"),
            text(["Returns ", code("(not (even? n))")]),
        ),
    ],
    "Numbers": [
        proc(
            "+",
            ([("z", "number?"), "..."], "number?"),
            text([
                "Return the sum of ", var("z"), "s. Add from left to right. "
                "If no arguments are provided, the result is 0.",
            ]),
        ),
        proc(
            "-",
            ([("z", "number?"), ("w", "number?"), "..."], "number?"),
            text([
                "When no ", var("w"), "s are applied, return ", code("(- 0 z)"),
                ". Otherwise, return the subtraction of ", var("w"), "s of ",
                var("z"), ".",
            ]),
        ),
        proc(
            "*",
            ([("z", "number?"), "..."], "number?"),
            text([
                "Return the product of ", var("z"), "s. If no ",
                var("z"), "s are supplied, the result is 1.",
            ]),
        ),
        proc(
            "/",
            ([("z", "number?"), ("w", "number?"), "..."], "number?"),
            text([
                "When no ", var("w"), "s are applied, return ", code("(/ 1 z)"),
                ". Otherwise, return the division of ", var("w"), "s of ", var("z"),
                ".",
            ]),
        ),
        proc(
            "mod",
            ([("n", "int?"), ("m", "int?")], "int?"),
            text(["Return the modulo of ", var("n"), " and ", var("m"), "."]),
        ),
        proc(
            "modulo",
            ([("n", "int?"), ("m", "int?")], "int?"),
            text(["Clone of ", code("mod"), "."]),
        ),
        proc(
            "add1",
            ([("z", "number?")], "number?"),
            text(["Returns ", code("(+ z 1)"), "."]),
        ),
        proc(
            "sub1",
            ([("z", "number?")], "number?"),
            text(["Returns ", code("(- z 1)"), "."]),
        ),
        proc(
            "=",
            ([("z", "number?"), ("w", "number?"), "..."], "bool?"),
            text([
                "Returns ", bool_t, " if all arguments are numerically equal, ",
                bool_f, " otherwise.",
            ]),
        ),
        proc(
            "<",
            ([("x", "real?"), ("y", "real?")], "bool?"),
            text([
                "Returns ", bool_t, " if ", var("x"), " is less than ", var("y"),
                ", ", bool_f, " otherwise.",
            ]),
        ),
        proc(
            "<=",
            ([("x", "real?"), ("y", "real?")], "bool?"),
            text([
                "Returns ", bool_t, " if ", var("x"), " is less than or equal to ",
                var("y"), ", ", bool_f, " otherwise.",
            ]),
        ),
        proc(
            ">",
            ([("x", "real?"), ("y", "real?")], "bool?"),
            text([
                "Returns ", bool_t, " if ", var("x"), " is greater than ",
                var("y"), ", ", bool_f, " otherwise.",
            ]),
        ),
        proc(
            ">=",
            ([("x", "real?"), ("y", "real?")], "bool?"),
            text([
                "Returns ", bool_t, " if ", var("x"),
                " is greater than or equal to ", var("y"), ", ", bool_f,
                " otherwise.",
            ]),
        ),
        proc(
            "abs",
            ([("x", "real?")], "real?"),
            text(["Returns the absolute value of ", var("x"), "."]),
        ),
        proc(
            "max",
            ([("x", "real?"), "..."], "real?"),
            text(["Returns largest value of the ", var("x"), "s."]),
        ),
        proc(
            "min",
            ([("x", "real?"), "..."], "real?"),
            text(["Returns smallest value of the ", var("x"), "s."]),
        ),
        proc(
            "real-part",
            ([("z", "number?")], "real?"),
            text(["Returns the real part of ", var("z"), "."]),
        ),
        proc(
            "imag-part",
            ([("z", "number?")], "real?"),
            text(["Returns the imaginary part of ", var("z"), "."]),
        ),
        proc(
            "round",
            ([("x", "real?")], "int?"),
            text([
                "Returns the closest integer to ", var("x"),
                ", resolving ties in favor of even numbers."
            ]),
        ),
        proc(
            "ceil",
            ([("x", "real?")], "int?"),
            text(["Returns the smallest integer bigger than ", var("x"), "."]),
        ),
        proc(
            "floor",
            ([("x", "real?")], "int?"),
            text(["Returns the largest integer less than ", var("x"), "."]),
        ),
        proc(
            "random",
            ([], "float?"),
            text(["Returns a random number between 0.0 inclusive to 1.0 exclusive."])
        ),
        proc(
            "randrange",
            ([
                ("start", "int?"),
                ("stop", "int?"),
                ("step", "(or/c (not/c 0) int?)", "1"),
            ], "int?"),
            text([
                "Returns a random int between ", var("start"), " and ", var("stop"),
                " inclusive."
            ]),
        ),
    ],
    "Exponents": [
        proc(
            "pow",
            ([("z", "real?"), ("w", "real?")], "real?"),
            text(["Returns ", var("z"), " raised to the ", var("w"), " power."]),
        ),
        proc(
            "sqrt",
            ([("z", "number?")], "number?"),
            text(["Returns the square root of ", var("z"), "."]),
        ),
        proc(
            "exp",
            ([("x", "real?")], "float?"),
            text(["Returns Euler's number raised to the ", var("z"), " power."]),
        ),
        proc(
            "log",
            ([("x", "real?"), ("b", "real?", "(exp 1)")], "float?"),
            text([
                "Returns the natural logarithm of ", var("x"), ".\n"
                "If ", var("b"), " is provided, it serves as an alternative base."
            ]),
        ),
    ],
    "Geometry": [
        proc(
            "sin",
            ([("z", "real?")], "float?"),
            text(["Returns the sine of ", var("z"), " in radians."])
        ),
        proc(
            "cos",
            ([("z", "real?")], "float?"),
            text(["Returns the cosine of ", var("z"), " in radians."])
        ),
        proc(
            "tan",
            ([("z", "real?")], "float?"),
            text(["Returns the tangent of ", var("z"), " in radians."])
        ),
        value(
            "pi",
            "float?",
            text([
                "A floating point approximation of 𝜋: "
                "the circumference of a circle divided by its diameter."
            ]),
        ),
    ],
    "Symbols": [
        pred(
            "symbol?",
            text([
                "Returns ", bool_t, " if ", var("v"), " is a symbol, ", bool_f,
                " otherwise.",
            ]),
        ),
        proc(
            "symbol->string",
            ([("sym", "symbol?")], "string?"),
            text([
                "Returns a new string whose characters are the same as in ", var("sym"), "."
            ]),
        ),
        proc(
            "string->symbol",
            ([("str", "string?")], "symbol?"),
            text([
                "Returns a symbol whose characters are the same as ", var("str"), "."
            ]),
        ),
    ],
    "Strings": [
        pred(
            "string?",
            text([
                "Returns ", bool_t, " if ", var("v"), " is a string, ", bool_f,
                " otherwise.",
            ]),
        ),
        pred(
            "char?",
            text([
                "Returns ", bool_t, " if ", var("v"), " is a char, ",
                bool_f, " otherwise.",
            ]),
        ),
        proc(
            "string",
            ([("char", "char?"), "..."], "string?"),
            text(["Returns a new string from the given ", var("char"), "s."]),
        ),
        proc(
            "string-append",
            ([("str", "string?"), "..."], "string?"),
            text(["Returns a new string concatenated from the given ", var("str"), "s"])
        ),
        proc(
            "string-upcase",
            ([("s", "string?")], "string?"),
            text(["Returns the string ", var("s"), " in upper case."]),
        ),
        proc(
            "string-downcase",
            ([("s", "string?")], "string?"),
            text(["Returns the string ", var("s"), " in lower case."]),
        ),
        proc(
            "string-titlecase",
            ([("s", "string?")], "string?"),
            text(["Returns the string ", var("s"), " in title case. "
                "The first letter of every word is capitalized and the rest is lower cased."
            ]),
        ),
        proc(
            "char->int",
            ([("char", "char?")], "int?"),
            text(["Returns the corresponding int to the given ", var("char"), "."]),
        ),
        proc(
            "int->char",
            ([("k", "int?")], "char?"),
            text(["Returns the character corresponding to ", var("k"), "."]),
        ),
        proc(
            "number->string",
            ([("z", "number?")], "string?"),
            text(["Returns ", var("z"), " as a string."]),
        ),
        proc(
            "~a",
            ([("v", "datum?")], "string?"),
            text(["TODO"]),
        ),
        proc(
            "~s",
            ([("v", "datum?")], "string?"),
            text(["TODO"]),
        ),
        proc(
            "~v",
            ([("v", "datum?")], "string?"),
            text(["TODO"]),
        ),
    ],
    "Vectors": [
        pred(
            "vector?",
            text([
                "Returns ", bool_t, " if ", var("v"), " is a vector, ", bool_f,
                " otherwise.",
            ]),
        ),
        proc(
            "vector",
            ([("v", "any"), "..."], "vector?"),
            text([
                "Returns a new vector with the ", var("v"),
                " args filled with its slots in order.",
            ]),
        ),
        proc(
            "make-vector",
            ([("size", "uint?"), ("v", "any", "0")], "vector?"),
            text([
                "Returns a new vector with ", var("size"), " slots, all filled with ",
                var("v"), "s.",
            ]),
        ),
        proc(
            "vector-pop!",
            ([("vec", "vector?")], "any"),
            text(["Remove the last element of ", var("vec"), " and return it."]),
        ),
        proc(
            "vector-add!",
            ([("vec", "vector?"), ("v", "any")], "none"),
            text(["Append ", var("v"), " to the end of ", var("vec"), "."]),
        ),
        proc(
            "vector-set!",
            ([("vec", "vector?"), ("pos", "int?"), ("v", "any")], "none"),
            text(["Set slot ", var("pos"), " of ", var("vec"), " to ", var("v"), "."]),
        ),
        proc(
            "vector-append",
            ([("vec", "vector?"), "..."], "vector?"),
            text([
                "Returns a new vector with all elements of ", var("vec"),
                "s appended in order."
            ]),
        ),
        proc(
            "vector-extend!",
            ([("vec", "vector?"), ("vec2", "vector?"), "..."], "none"),
            text([
                "Modify ", var("vec"), " so that all elements of", var("vec2"),
                "s are appended to the end of ", var("vec"), " in order.",
            ]),
        ),
        proc(
            "string->vector",
            ([("str", "string?")], "vector?"),
            text(["Returns a new string filled with the characters of ", var("str"), "."])
        ),
    ],
    "Arrays": [
        pred(
            "array?",
            text([
                "Returns ", bool_t, " if ", var("v"), " is an array, ",
                bool_f, " otherwise.",
            ]),
        ),
        proc(
            "array",
            ([("dtype", "symbol?"), ("v", "any"), "..."], "array?"),
            text([
                "Returns a freshly allocated array with ", var("dtype"),
                " as its datatype and the ", var("v"),
                " args as its values filled in order.",
            ]),
        ),
        proc(
            "make-array",
            ([("dtype", "symbol?"), ("size", "uint?"), ("v", "int?", "0")], "array?"),
            text([
                "Returns a freshly allocated array with ", var("dtype"),
                " as its datatype and the value ", var("v"), " filled.",
            ]),
        ),
        proc(
            "array-splice!",
            ([
                ("arr", "array?"),
                ("v", "real?"),
                ("start", "int?", "0"),
                ("stop", "int?", "(length arr)"),
            ], "array?"),
            text([
                "Modify ", var("arr"), " by setting ", var("start"), " to ",
                var("stop"), " to the value, ", var("v"),  ".",
            ]),
        ),
        proc(
            "count-nonzero",
            ([("arr", "array?")], "uint?"),
            text(["Returns the number of non-zeros in ", var("arr"), "."]),
        ),
        pred(
            "bool-array?",
            text([
                "Returns ", bool_t, " if ", var("v"),
                " is an array with 'bool as its datatype, ", bool_f, " otherwise."
            ]),
        ),
        proc(
            "bool-array",
            ([("v", "uint?"), "..."], "bool-array?"),
            text([
                "Returns a new boolean array with ", var("v"), " as its values."
            ]),
        ),
        proc(
            "margin",
            ([
                ("left", "int?"),
                ("right", "int?", "left"),
                ("arr", "bool-array?"),
            ], "bool-array?"),
            text([
                "Returns a new ", code("bool-array?"), " with ", var("left"), " and ",
                var("right"), " margin applied."
            ]),
        ),
        syntax(
            "and", "first-expr rest-expr ...",
            text([
                "Evaluate ", var("first-expr"), ", if the result is a bool-array?, ",
                "evaluate all ", var("rest-expr"), "s and return the logical-and of all arrays.",
                " If the result is ", bool_f, ", evaluate ", var("rest-expr"),
                " one at a time. Return immediately if any arg is ", bool_f,
                ", return ", bool_t, " if all values are ", bool_t, ".",
            ]),
        ),
        syntax(
            "or", "first-expr rest-expr ...",
            text([
                "Evaluate ", var("first-expr"), ", if the result is a bool-array?, ",
                "evaluate all ", var("rest-expr"), "s and return the logical-and of all arrays.",
                " If the result is ", bool_t, ", evaluate ", var("rest-expr"),
                " one at a time. Return immediately if any arg is ", bool_t,
                ", return ", bool_f, " if all values are ", bool_f, ".",
            ]),
        ),
        proc(
            "xor",
            ([
                ("expr1", "(or/c bool? bool-array?)"),
                ("expr2", "(or/c bool? bool-array?)"),
            ], "(or/c bool? bool-array?)"),
            text([
                "Returns a new boolean or boolean-array based on the exclusive-or of ",
                var("expr1"), " and ", var("expr2"), ". ", var("expr2"),
                " must be the same type as ", var("expr1"), "."
            ]),
        ),
        proc(
            "not",
            ([("h", "(or/c bool? bool-array?)")], "(or/c bool? bool-array?)"),
            text(["Returns the inverse of ", var("h"), "."]),
        ),
        proc(
            "mincut",
            ([("arr", "bool-array?"), ("x", "int?")], "bool-array?"),
            text([
                "TODO"
            ]),
        ),
        proc(
            "minclip",
            ([("arr", "bool-array?"), ("x", "int?")], "bool-array?"),
            text([
                "TODO"
            ]),
        ),
    ],
    "Pairs and Lists": [
        pred(
            "pair?",
            text([
                "Returns ", bool_t, " if ", var("v"), " is a pair, ",
                bool_f, " otherwise.",
            ]),
        ),
        pred(
            "null?",
            text([
                "Returns ", bool_t, " if ", var("v"), " is an empty list, ",
                bool_f, " otherwise.",
            ]),
        ),
        proc(
            "cons",
            ([("a", "any"), ("d", "any")], "pair?"),
            text([
                "Returns a newly allocated pair where the first item is set to ",
                var("a"), " and the second item set to ", var("d"), ".",
            ]),
        ),
        proc(
            "car",
            ([("p", "pair?")], "any?"),
            text([
                "Returns the first element of pair ", var("p"), ".",
            ]),
        ),
        proc(
            "cdr",
            ([("p", "pair?")], "any?"),
            text([
                "Returns the second element of pair ", var("p"), ".",
            ]),
        ),
        value("null", "null?", text(["The empty list."])),
        pred(
            "list?",
            text([
                "Returns ", bool_t, " if ", var("v"),
                 " is an empty list or a pair whose second element is a list.",
            ]),
        ),
        proc(
            "list",
            ([("v", "any"), "..."], "list?"),
            text(["Returns a list with ", var("v"), " in order."]),
        ),
        proc(
            "list-ref",
            ([("lst", "list?"), ("pos", "uint?")], "any"),
            text([
                "Returns the element of ", var("lst"), " at position ", var("pos"), ".",
            ]),
        ),
        proc(
            "vector->list",
            ([("vec", "vector?")], "list?"),
            text(["Returns a new list based on ", var("vec"), "."])
        ),
        proc(
            "list->vector",
            ([("lst", "list?")], "vector?"),
            text(["Returns a new vector based on ", var("lst"), "."])
        ),
        proc(
            "string->list",
            ([("str", "string?")], "list?"),
            text(["Returns a new list filled with the characters of ", var("str"), "."])
        ),
        proc(
            "caar",
            ([("v", "any")], "any"),
            text(["Returns ", code("(car (car v))")]),
        ),
        proc(
            "cadr",
            ([("v", "any")], "any"),
            text(["Returns ", code("(car (cdr v))")]),
        ),
        proc(
            "cdar",
            ([("v", "any")], "any"),
            text(["Returns ", code("(cdr (car v))")]),
        ),
        proc(
            "cddr",
            ([("v", "any")], "any"),
            text(["Returns ", code("(cdr (cdr v))")]),
        ),
    ],
    "Ranges": [
        pred(
            "range?",
            text([
                "Returns ", bool_t, " if ", var("v"), " is a range object, ",
                bool_f, " otherwise.",
            ]),
        ),
        proc(
            "range",
            ([
                ("start", "int?"),
                ("stop", "int?"),
                ("step", "(or/c (not/c 0) int?)", "1"),
            ], "range?"),
            text(["Returns a range object."]),
        ),
        proc(
            "range->vector",
            ([("rng", "range?")], "vector?"),
            text(["Returns a new vector based on ", var("rng"), "."])
        ),
        proc(
            "range->list",
            ([("rng", "range?")], "list?"),
            text(["Returns a new list based on ", var("rng"), "."])
        ),
    ],
    "Generic Sequences": [
        pred(
            "iterable?",
            text([
                "Returns ", bool_t, " if ", var("v"),
                " is a vector, array, string, hash, pair, or range, ", bool_f,
                " otherwise.",
            ]),
        ),
        pred(
            "sequence?",
            text([
                "Returns ", bool_t, " if ", var("v"),
                " is a vector, array, string, pair, or range, ", bool_f,
                " otherwise.",
            ]),
        ),
        proc(
            "length",
            ([("seq", "iterable?")], "uint?"),
            text(["Returns the length of ", var("seq"), "."]),
        ),
        proc(
            "ref",
            ([("seq", "iterable?"), ("pos", "int?")], "any"),
            text([
                "Returns the element of ", var("seq"), " at position ",
                var("pos"), ", where the first element is at position 0. ",
                "For sequences other than pair?, negative positions are allowed.",
            ]),
        ),
        proc(
            "slice",
            ([
                ("seq", "sequence?"),
                ("start", "int?"),
                ("stop", "int?", "(length seq)"),
                ("step", "int?", "1"),
            ], "sequence?"),
            text([
                "Returns the elements of ", var("seq"), " from ", var("start"),
                " inclusively to ", var("stop"), " exclusively. If ", var("step"),
                " is negative, then ", var("stop"), " is inclusive and  ",
                var("start"), " is exclusive.",
            ]),
        ),
        proc(
            "reverse",
            ([("seq", "sequence?")], "sequence?"),
            text(["Returns ", var("seq"), " in reverse order."]),
        ),
    ],
    "Hashmaps": [
        pred(
            "hash?",
            text([
                "Returns ", bool_t, " if ", var("v"), " is a hash table, ", bool_f,
                " otherwise.",
            ]),
        ),
        proc(
            "hash",
            ([("key", "any"), ("val", "any"), "..."], "hash?"),
            text(["Returns a newly constructed hash map from key-value pairs."]),
        ),
        proc(
            "has-key?",
            ([("hash", "hash?"), ("key", "any")], "bool?"),
            text([
                "Returns ", bool_t, " if ", var("key"), " is in the hash map, ", bool_f,
                " otherwise.",
            ]),
        ),
    ],
    "Actions": [
        proc(
            "sleep",
            ([("time", "(or/c int? float?)")], "void?"),
            text(["Adds a delay by ", var("time"), "seconds."]),
        ),
        proc(
            "error",
            ([("msg", "string?")], "none"),
            text(["Raises an exception with ", var("msg"), " as the message."])
        ),
        proc(
            "exit",
            ([("status", "uint?", "1")], "none"),
            text(["Immediately terminates the program."])
        ),
        proc(
            "begin",
            ([("datum", "any"), "..."], "any"),
            text(["Evaluates all arguments and returns the last one."])
        ),
    ],
    "Input / Output": [
        proc(
            "display",
            ([("datum", "any")], "void?"),
            text(["Display ", var("datum"), " to stdout."]),
        ),
        proc(
            "displayln",
            ([("datum", "any")], "void?"),
            text(["Display ", var("datum"), ", to stdout with a newline character."]),
        ),
        proc(
            "print",
            ([("datum", "any")], "void?"),
            text(["Display ", var("datum"), ", like REPL does."]),
        ),
        proc(
            "println",
            ([("datum", "any")], "void?"),
            text(["Display ", var("datum"), ", like REPL does with a newline character."]),
        ),
        syntax(
            "with-open",
            "(file-binding file-path file-mode) body-expr",
            text(["In the block, the file object to ", code("file-binding"), "\n.",
                code("(with-open (file \"todo.txt\" 'a) ((. file write) \"buy milk\"))"),
            ]),
        ),
    ],
    "Void": [
        pred(
            "void?",
            text([
                "Returns ", bool_t, " if ", var("v"), " is ", code("#<void>"), ", ",
                bool_f, " otherwise.",
            ]),
        ),
        proc(
            "void",
            ([("v", "any"), "..."], "void?"),
            text([
                "Returns the constant ", code("#<void>"), ". All ", var("v"),
                " arguments are ignored."
            ]),
        ),
    ],
    "Procedures": [
        pred(
            "procedure?",
            text(["Returns ", bool_t, " if ", var("v"), " is a procedure."]),
        ),
        proc(
            "map",
            ([("proc", "procedure?"), ("seq", "sequence?")], "sequence?"),
            text([
                "Returns a new sequence with the results of ", var("proc"),
                " applied to each element."
            ]),
        ),
        proc(
            "apply",
            ([("proc", "procedure?"), ("seq", "sequence?")], "any"),
            text([
                "Applies ", var("proc"), " given the ", var("seq"), " as the arguments."
            ]),
        ),
    ],
    "Objects": [
        pred(
            "object?",
            text(["Returns ", bool_t, " if ", var("v"), " is an object, ", bool_f,
                " otherwise. Anything that's not an object is a primitive."
            ]),
        ),
        proc(
            "attrs",
            ([("obj", "object?")], "vector?"),
            text(["Returns all attributes of ", var("obj"), " as a vector of strings."]),
        ),
        syntax(
            ".",
            "obj attr",
            text(["Returns the specified attribute on the object."]),
        ),
    ],
    "Reflection": [
        syntax(
            "eval", "body",
            text([
                "Evaluate body, if body is a vector or list, "
                "evaluate the vector/list, otherwise return the value."
            ]),
        ),
        syntax(
            "quote", "body",
            text([
                "Returns ", var("body"), " as its \"literalized\" form, "
                "a constant value with its binding names copied.",
            ]),
        ),
        proc(
            "var-exists?",
            ([("sym", "symbol?")], "bool?"),
            text([
                "Returns", bool_t, " if the variable corresponding to ", var("sym"),
                " is defined in the current environment, ", bool_f, " otherwise."
            ]),
        ),
    ],
    "Miscellaneous Predicates": [
        pred(
            "any",
            text(["Returns ", bool_t, " regardless of the value of ", var("v"), "."]),
        ),
    ],
}
