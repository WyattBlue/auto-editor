---
title: Range Syntax
---

## How Do I Cut the Beginning or End Segment in My Video?

Range syntax is useful for making manual edits in addition to automatic edits. Here's how you cut out the first and last 30 seconds:
```sh
auto-editor video.mp4 --cut start,30sec -30sec,end
```

You can also guarantee those sections would be included, regardless of loudness with:
```sh
auto-editor video.mp4 --keep start,30sec -30sec,end
```

## How Range Syntax Works
The `--keep`, `--cut`, `--set-speed`, and `--set-action` options all use time range syntax.

It describes two numbers, the start and end point, separated by a singe comma `,`. The start number is inclusive, while the end number is exclusive.

```sh
# This will cut out the first frame: frame 0
auto-editor example.mp4 --cut 0,1

# This will cut out five frames: frames 0, 1, 2, 3, 4
# frame 5 will still exist because the end point is exclusive
auto-editor example.mp4 --cut 0,5

# Cuts out 60 frames
auto-editor example.mp4 --cut 10,70
```

## Variables
Time range syntax allows two variables: `start` and `end`
`start` is the same as `0`
`end` is the length of the timeline before any edits are applied.

```sh
# This will cut out everything in the beginning
auto-editor example.mp4 --cut start,300

# This will keep everything besides the beginning, overriding other edits
auto-editor example.mp4 --keep 300,end

# This will cut out everything
auto-editor example.mp4 --cut start,end
```

## Units
The default unit is the timeline's timebase. Since specifying the range in this unit can sometimes be annoying. You can use the `sec` unit to specify the range in seconds. (Note that the seconds range will be rounded to the nearest timebase to you don't have any more precision than usual).

```sh
# Cut out the first 10 seconds.
auto-editor example.mp4 --cut start,10secs
```
You can also use `s`, `sec`, `second`, or `seconds`, depending on your preference.

## Negative Indexes
Negative numbers can be used to count down starting from the end.
 * `-60,end` selects the last 60 frames
 * `1sec,-30secs` selects from the first second, to the last 30 seconds from the end.

## Speed for Range
The `--set-speed-for-range` option has a slight twist on time range syntax. It accepts three numbers. `speed`, `start`, and `end`, separated by commas. `speed` can be a decimal number, but not negative. `start` and `end` work as described above.

```sh
# Set the speed to 2x from frame 0 to frame 29
auto-editor example.mp4 --set-speed-for-range 2,0,30

# Set the speed to 0.5x
auto-editor example.mp4 --set-speed-for-range 0.5,start,end
```

<a class="next" href="./file-size">Next: File Size</a>
