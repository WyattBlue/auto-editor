# What's New in Range Syntax
last modified May 13, 2021. 21w19a.

Range syntax is the common format used in:

 - `--mark_as_loud`
 - `--mark_as_silent`
 - `--cut_out`
 - `--set_speed_for_range`

and describes a range in time based on frames from 0, the first frame, all the way till the end.

```
auto-editor example.mp4 --mark_as_silent 0,60
```

It accepts any integer greater than and equal to 0 and can take strings (variables) like 'start' and 'end'.

```
auto-editor example.mp4 --mark_as_loud 72,end
```

Range Syntax has a nargs value of '\*' meaning it can take any many ranges.

```
auto-editor example.mp4 --cut_out 0,20 45,60, 234,452
```

---

The `--set_speed_for_range` option has an additional argument for speed. The command:

```
auto-editor example.mp4 --set_speed_for_range 2,0,30
```

means set the speed of the video to twice as fast (2x) from the 0th frame to the 30th frame.


## Notes

before 21w19a. Range Syntax was second based and used hyphens as separators instead of commas.

The `--ignore` has been renamed to the more accurately described `--mark_as_loud`.


