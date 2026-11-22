---
title: levels
---

`levels` displays individual "edit method" stream values before the threshold procedure (if any) is applied. It mainly exists to be used by other programs so they can build on auto-editor's media analysis.

Because typical levels output is so long, it won't be displayed verbatim.

```
auto-editor levels example.mp4

@start
0.00003
0.00009
0.00009
0.00006
0.00269
0.0166
0.05057
0.15363
0.18131
(Continues for about 1,250 more lines)
0.0
0.0
0.0
```

levels uses `--edit` to determine what is being analyzed, which by default is `audio`.

<a class="next" href="./subdump">Next: subdump</a>
