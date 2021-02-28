# Rectangle Effect
last modified February 28, 2021. 21w08a.

## Introduction
The rectangle effect option will overlay a rectangle on a video.

The arguments are:

```
--rectangle {start},{end},{x1},{y1},{x2},{y2},{color},{thickness}
```

or using real values:

```
--rectangle 0,30,0,100,200,300,#5ADAE8,15
```

Which means: overlay a rectangle from frame 0 to frame 30, fill at point (0, 100) and point (200, 300), color it with hex #5ADAE8, and set the thickness to 15 pixels.

The rectangle completely solid if the thickness value is left out.
The color will default to black if not specified.

The rectangle option needs at least 6 comma arguments.

### Note

Boolean Expressions are supported for this option just like with zooming.

---

Support for zooming and other effects for Premiere Pro coming soon!
