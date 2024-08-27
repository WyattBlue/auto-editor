---
title: Why It's Time to Remove `--silent-threshold`
author: WyattBlue
date: July 26, 2022
desc: `--silent-threshold` has been with us since the literal first day of auto-editor's existence. However, it's continued usage has become problematic. It's finally time to put this aging option to rest.
---
TL;DR use `--edit audio:threshold=NUM` instead.

---
`--silent-threshold` has been with us since the [literal first day of auto-editor's existence](https://github.com/WyattBlue/auto-editor/blob/3a2211573742c0e3eb9bcc6e55e21cbcdca661e6/auto-editor.py). However, it's continued usage has become problematic. It's finally time to put this aging option to rest.

### Reason 1: It's Too Ambiguous
Every threshold controls what is considered silent and loud, yet `--silent-threshold` only controls audio threshold. This used to make sense when auto-editor used to only have one way of automatically editing files. But now, it's not so obvious that it still only controls audio threshold, or really, that `--silent-threshold` only controls the default value of the `threshold` attribute of `--edit`, which leads us to...

### Reason 2: `--edit`'s Syntax Is So Much Nicer
With `--edit`'s syntax, you can edit multiple tracks with different thresholds, something never possible with the `--silent-threshold`.

```
auto-editor multi-track.mov --edit 'audio:stream=0,threshold=0.04 or audio:stream=1,threshold=0.09'
```

It's also much clearer how threshold impacts the editing process while `--silent-threshold` is much more opaque on how it exactly works and how it interacts with `--edit`. Why bother explaining how `--silent-threshold` interacts with `--edit` to every user when `--edit` is better in every way?

### Reason 3: It’s Used Surprisingly Little Out in the Wild

`--silent-threshold` and it's alias `-t` is used surprising little in scripts. I look at [GitHub's Dependency Graph](https://github.com/WyattBlue/auto-editor/network/dependents?package_id=UGFja2FnZS0xMzQ0MTE1MzMz) and watch various YouTube videos showcasing auto-editor to gauge how options are used in the real world, and in all usages I can find, it's never mentioned at all. This might be both that `4%` is a very good default that doesn't need changing and/or how audio threshold works is unintuitive, which is why it is never explained or used. Whatever the case, this lack of usage means `--silent-threshold` can be removed without causing annoyance.

---
### Appendix: Why Not Create a Macro?
When I removed `--export-to-premiere` and `--export-to-final-cut-pro` options, I used a 'macro' that essentially silently treats `'--export-to-premiere'` like `'--export premiere'` and this allowed users to write the option in the "old style", blissfully unaware of any changes, even when the option and it's help text technically doesn't exist anymore. The reason why I didn't use a similar strategy for `--silent-threshold` is that any script makers who feel the need to change silent threshold, are the people most who would benefit from the flexibility of `--edit`.
