# Zooming
last modified February 13, 2021.
This command will be available in release 21w06a.


The `--zoom` option allows auto-editor to zoom in or out in any place. In order for the `--zoom` option to work, it needs at least 3 values:

 1. when to start applying the zoom
 1. when to stop applying the zoom
 1. the starting zoom level

This is entered in as:

```
--zoom {start},{end},{start_level}
```

or using real numbers,

```
--zoom 0,20,1.5
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

`testsrc.mp4` is used instead of `example.mp4` because it provides more clarity.

---

Zooming is not implemented in the av render method, and will not be used when exporting to other editors until 21w07a or greater.
