---
title: Supporting DaVinci Resolve Again
author: WyattBlue
date: March 20, 2023
desc: no-index
---
In [December of 2021](https://github.com/WyattBlue/auto-editor/releases/tag/21w50a), I removed support for DaVinci Resolve because of then unresolved bugs and because of my frustration working with the editor. Even with the removal, people still tried to use Resolve with the `--export premiere` export. A large segment of users continued to believe Resolve was still supported, especially by late 2022-2023, even amount some app users. For that reason, I took a second look at supporting DaVinci and concluded that support was possible.

In the branch master, `resolve` is now a possible value for `--export`. Internally, it uses the same format `premiere` uses. While there are some bugs reported by users like multi-track audio timelines not working, I will to investigate and fix those issues.
