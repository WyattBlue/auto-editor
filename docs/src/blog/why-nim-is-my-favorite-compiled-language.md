---
title: Why Nim Is My Favorite Compiled Language 
author: WyattBlue
date: June 3, 2023
desc: While there are many other low to medium level languages, Nim hits all the sweet spots for me.
---

Of all the compiled languages I've seriously considered: C, C++, Rust, Go, and Nim, Nim is by far my favorite and the language I will continue to use in the future. 

---
First on my perspective. I'm a Python guy that means I would like a language that both has similar semantics to Python and still crank out code pretty quickly. Also, because I work professionally, I have limited time to review each language, and will be approaching them all as a beginner.

## C
My first language I reviewed was C. Both Python and FFmpeg are written in C so it was a natural choice. For my project [calc-in-c](https://github.com/WyattBlue/calc-in-c), I felt I was making fast progress. Eventually, however, I had problems. There are no hash-maps builtin, nor builtin vectors, nor a standard way to use third-party libs, and you have to learn to avoid certain standard functions because a lot of them are straight up terrible. 

## C++
C++ solves points 1 and 2, but point 4 is a lot worse because C++ has so many language features and only some of them are well thought out. Also C and C++ has diverged significantly so many positive improvements in C are not in C++.

## Rust
This is when I started thinking about Rust, but at the time, I was intimated by both by the dense syntax and the Borrow Checker. I also considered Go since it seemed easier, but the fact that you can't link C libraries in Go without Cgo, (which has its own limitations that I don't really understand, but I'm told are serious)

Later in time, I tried to rewrite my simple command-line calculator in Rust, but I found it difficult and frustrating. Rust standard libraries for processing input and output for the shell was not working how I expected. One issue was when the user typed when the prompt was displayed. It would display like this:

```
>
2 + 2
```

Instead of like this:

```
> 2 + 2
```

Rust also wouldn't flush stdout when I wanted it to, when both C and Python did what I expected the first time. I ultimately abandoned the effort. Then I learned of Nim.

## Nim
I finished writing my calculator in Nim faster than in C. In fact, it was almost as fast as if I had written it in Python. I had so much developer velocity in Nim that I expanded my test project's scope and tried my hand at writing a small Scheme dialect. I ultimately got bools, integers, and floats, along with more math functions like `pow` and `modulo`. I did not implement parens or supporting arity besides 2 but that was okay because this was just a trial run and the language had already proved itself.

Nim is a really good fit for me since it tries hard to both look like Python and feel like Python. It has all the datatypes that I want builtin such as hash-maps and vectors (which Nim calls tables and sequences respectively) and it has an GC so you don't have to manage memory (you can tune or disable the GC if you need to). I've tried to think of any real downsides besides very small nitpicks. Since Nim compiles to C, which is then compiled to machine code, it both executes very fast and is very portable. Nim also has a JS backend which seems useful, but I have not yet played around on it. 

I cannot stress enough how fast it is to write programs in Nim. In fact, this very blog post is compiled to html by my program written Nim. Overall, Nim is a fantastic language and one where I look forward to using in the future.

