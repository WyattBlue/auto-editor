---
title: Range Syntax
---

# Range Syntax
## How Do I Cut the Beginning or End Segment in My Video?

Range syntax is useful for making manual edits in addition to automatic edits. Here's how you cut out the first and last 30 seconds:
```
auto-editor video.mp4 --cut-out start,30sec -30sec,end
```

You can also guarantee those sections would be included, regardless of loudness with:
```
auto-editor video.mp4 --add-in start,30sec -30sec,end
```

## How Range Syntax Works
The `--add-in`, `--cut-out`, `--mark-as-loud`, `--mark-as-silent` options all use time range syntax.

It describes two numbers, the start and end point, separated by a singe comma `,`. The start number is inclusive, while the end number is exclusive.

```
# This will cut out the first frame: frame 0
auto-editor example.mp4 --cut-out 0,1

# This will cut out five frames: frames 0, 1, 2, 3, 4
# frame 5 will still exist because the end point is exclusive
auto-editor example.mp4 --cut-out 0,5

# Cuts out 60 frames
auto-editor example.mp4 --cut-out 10,70

# No frame will be cut here
auto-editor example.mp4 --cut-out 0,0
```

## Variables
Time range syntax allows two variables: `start` and `end`
`start` is the same as `0`
`end` is the length of the timeline before any edits are applied.

```
# This will mark everything in the beginning as silent
auto-editor example.mp4 --mark-as-silent start,300

# This will mark everything besides the beginning as loud
auto-editor example.mp4 --mark-as-loud 300,end

# This will cut out everything
auto-editor example.mp4 --cut-out start,end
```

## Units
The default unit is the timeline's timebase. Since specifying the range in this unit can sometimes be annoying. You can use the `sec` unit to specify the range in seconds. (Note that the seconds range will be rounded to the nearest timebase to you don't have any more precision than usual).

```
# Cut out the first 10 seconds.
auto-editor example.mp4 --cut-out start,10secs
```
You can also use `s`, `sec`, `second`, or `seconds`, depending on your preference.

## Multiple Ranges
All options discussed here support specifying multiple ranges at the same time. Overlapping ranges are allowed.

```
auto-editor example.mp4 --cut-out 0,20 45,60, 234,452
```

## Negative Indexes
Negative numbers can be used to count down starting from the end.
 * `-60,end` selects the last 60 frames
 * `1sec,-30secs` selects from the first second, to the last 30 seconds from the end.

## Speed for Range
The `--set-speed-for-range` option has a slight twist on time range syntax. It accepts three numbers. `speed`, `start`, and `end`, separated by commas. `speed` can be a decimal number, but not negative. `start` and `end` work as described above.

```
# Set the speed to 2x from frame 0 to frame 29
auto-editor example.mp4 --set-speed-for-range 2,0,30

# Set the speed to 0.5x
auto-editor example.mp4 --set-speed-for-range 0.5,start,end
```

