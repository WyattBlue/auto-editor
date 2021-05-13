New Release!
**New in 21w19a**

---

Changed how `--cut_out` works. It removes sections regardless of what silent speed is.
 * The format `--cut_out start-end` has been changed to `--cut_out start,end`
 * `--cut_out` and other range options are now based on frames instead of seconds.

Replaced `--ignore` with `--mark_as_loud`. It also uses commas instead of hyphens.

Added `--mark_as_silent`, Mark a given range as silent. This is dependent on what silent speed is. Has same functionally as `--cut_out` before 21w19a.

Added `--set_speed_for_range`. Allows you to set a custom speed for any section.
args are: `{speed},{starting point},{ending point}`

---

`--video_codec`'s default has been changed from 'uncompressed' to 'copy'.

unset is a new value that all FFmpeg-based options can take and it means don't include this option in the FFmpeg commands.

