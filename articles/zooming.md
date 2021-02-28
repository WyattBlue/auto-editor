# Zooming
last modified February 28, 2021. 21w08a.

## Introduction
The `--zoom` option allows auto-editor to zoom in or out in any place. In order for the `--zoom` option to work, it needs at least 3 values:

 1. when to start applying the zoom
 1. when to stop applying the zoom
 1. the starting zoom level

This is entered in as:

```
--zoom {start},{end},{start_zoom}
```

or using real numbers,

```
--zoom 0,20,1.5
```

Which means: start the zoom on the 0th frame, end on the 20th frame, and set the zoom level to 1.5x the original size.

To apply to a video, use this command:

```
auto-editor example.mp4 --zoom 0,20,1.5
```

The start and end parameters can also take in variables like... well, `start` and `end`.

```
auto-editor example.mp4 --zoom start,end,1.5
```

and it will evaulate to the starting and ending frames respectedly.
(A bit like [Range Syntax](https://github.com/WyattBlue/auto-editor/blob/master/articles/rangeSyntax.md) but uses frames instead of seconds.)


The zoom option can take another command argument, the ending level.

```
--zoom {start},{end},{start_level},{end_level}
```

This will change the zoom over time, allowing auto-editor to create "zoom ins" or "zoom outs". Example:

```
auto-editor example.mp4 --zoom 0,20,0.5,1.5
```

The zoom option can take more comma arguments, such as:

```
--zoom {start},{end},{start_zoom},{end_zoom},{x_pos},{y_pos},{interpolate_method}
```

`x_pos` and `y_pos` can be variables like `centerX`, `centerY`, `width`, and `height`, or just regular numbers.

`interpolate_method` is `linear` by default but can be changed `sine`, `start_sine` and `end_sine`.

## Boolean Expressions

Zooming can start and end whenever an event happens. One event can be when the average audio loudness of a frame is higher than a certain point.

Examples:

```
auto-editor example.mp4 --zoom audio>0.05,audio<0.03,1,1.2,centerX,centerY,sine
```

```
auto-editor example.mp4 --zoom audio>0.05,120,1,1.2,centerX,centerY,sine
```


## Additional Examples Commands

```
auto-editor testsrc.mp4 --ignore start-end --zoom start,end,1,2
```

```
auto-editor testsrc.mp4 --ignore start-end --zoom 0,30,5,0.5,centerX,centerY,sine 30,60,0.5,1,centerX,centerY,sine
```

```
auto-editor testsrc.mp4 --ignore start-end --zoom 20,60,0.8,1.5,100,height,start_sine
```

```
auto-editor testsrc.mp4 --ignore start-end --zoom start,60,0.8,1.5,width,height,sine
```

```
auto-editor testsrc.mp4 --ignore start-end --zoom 20,60,0.001,1.5,centerX,width,linear
```

```
auto-editor testsrc.mp4 --ignore start-end --zoom 20,60,0.5,3,centerY,centerX,end_sine
```

```
auto-editor testsrc.mp4 --zoom start,end,0.5,3,centerX,centerY,linear
```


### Notes
`--ignore start-end` simply tells auto-editor to not cut anywhere, this is not needed for zoom, but not putting can allow auto-editor to cut while a zoom is happening so it is useful for demonstration purposes.


You can generate `testsrc.mp4` with this command.

```
auto-editor generate_test -o 'testsrc.mp4'
```

---

Support for zooming and other effects for Premiere Pro coming soon!
