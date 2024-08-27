---
title: Nim vs Zig
author: WyattBlue
date: July 13, 2023
desc: Nim and Zig look similar on the surface. Both are modern statically-typed compiled languages. However, a closer examination with reveal stark differences.
---

Nim and Zig look similar on the surface. Both are modern statically-typed compiled languages. However, a closer examination with reveal stark differences.

---

## Memory Management
In Zig, you manually manage memory. This is typically done by picking an allocator and passing it explicitly. This allows you to pick and choose which strategy to use for each component for your project.

Nim has 'multi-paradigm' memory management, meaning  you choose which strategy of automatic memory management to use.

For example, there is `arc`, a minimal gc for hard realtime systems. `refc` for larger projects, `go` for interoping with golang, and so forth. Nim even has experimental support for turning off the garbage collector entirely, but you can no longer use most of the standard library unless you can tolerate memory leaks (Even fixed-sized arrays leak memory in this mode).

In short, Zig prioritizes control, while Nim prioritizes developer speed.

## Having an Interpreted Mode
Nim has a special mode called [NimScript](https://nim-lang.org/docs/nimscript.html) that turns Nim into an interpreted language with short command-like functions. It works a bit like bash/zsh/powershell, but unlike those programs, it's truly cross-platform - you don't have to write a separate script for Windows.

Zig does not have such a mode.

## Read Eval Print Loop
Nim has an experimental repl (via `nim secret`), unfortunately, it currently does not support most of the standard library so it's limited to basic expressions. Even in this form, however, it is still occasionally helpful.

Zig does not appear to have a repl even though [there has been discussion on this](https://github.com/ziglang/zig/issues/596).

## Macros
Nim programmers can write macros by accessing Nim's AST via `std/macros` and there a number of useful default macros that Nim has, such as `std/enumerate`.

Zig takes a hard-line stance against any preprocessor or macro in its quest to keep the language simple. Zig believes this to be so appealing that they put it on the front page of their website.

## Verbosity
To test how verbose each language, I've written a small program in each of them to compare.

Naïve FizzBuzz written in Zig:
```
const std = @import("std"); 

pub fn main() !void { 
    const stdout_file = std.io.getStdOut().writer();
    var bw = std.io.bufferedWriter(stdout_file);
    const stdout = bw.writer();

    var i: usize = 1;
    while (i <= 100) {
        if (i % 15 == 0) {
            try stdout.print("FizzBuzz\n", .{});
        } else if (i % 3 == 0) {
            try stdout.print("Fizz\n", .{});
        } else if (i % 5 == 0) {
            try stdout.print("Buzz\n", .{});
        } else {
            try stdout.print("{}\n", .{i});
        }
        i += 1;
    }
    try bw.flush();
}
```

Naïve FizzBuzz written in Nim:
```
for i in 1..100:
    if i mod 15 == 0:
        echo "FizzBuzz"
    elif i mod 3 == 0:
        echo "Fizz"
    elif i mod 5 == 0:
        echo "Buzz"
    else:
        echo i
```

As you can see, Nim is shorter than Zig. In Zig's defense, it's buffering is made very explicit and will be consistent across platforms, but come on, this is FizzBuzz!

Also, for some reason, Zig doesn't have a for loop construct even though it's trying to appeal to C/JavaScript programmers. I don't why this is the case.

## Conclusion 
I prefer Nim, both because it prioritizes what I need, but also because it aligns with my values, such as having AST macros, a minimalist OOP system, closures, and having an orthogonal design in general.

Zig seems like a fine choice if you really want C performance but want to avoid the many pain points of actually writing C ([a somewhat crowded space](https://ziglang.org/learn/why_zig_rust_d_cpp/)). However, I don't think Zig's value for simplicity is helpful. It's just going to shift the complexity to user code.
