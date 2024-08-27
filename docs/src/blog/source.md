---
title: The `--source` Option
author: WyattBlue
date: October 16, 2022
desc: no-index
---
### What Does the `--source` Option Do?
Auto-Editor allows you to create timeline objects with your files, however, typing/dragging the file path every time an object is declared is a pain. What `--source` does is map a path to a short and reusable label. You can use that label to reference the file without using it's path.

```
# Map a path to the label "dog"
--source dog:/Users/wyattblue/Downloads/dog-123.png
```

Right now, `src` only accepts source names and not the file path directly. This might change in the future.
Also, user defined labels cannot:
 * Contain `, = . : ; ( ) / \ [ ] { } ' " | # < > & ^ % $ _ @` anywhere
 * Contain the space character
 * Start with a with a digit or a dash (`0 1 2 3 4 5 6 7 8 9 -`)
 * Be greater than 55 characters
 * Contain an invalid UTF-8 character

This is partly because of limitations on file path names, *cough* Windows *cough*, but also to make parsing easy and forwards compatible.
The reason *User defined* is there is that paths given to auto-editor without a label are assigned a name, `0`, `1`, `2` and beyond.

```
# How you would use `--source` in a real situation
auto-editor movie.mp4 movie2.mp4 --source dog:/Users/wyattblue/Downloads/dog-123.png \
--add image:0,30,src=dog
```
