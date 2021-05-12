New Release!
**New in 21w19a**

---

Changed how `--cut_out` works.
 * The format `--cut_out start-end` has been changed to `--cut_out start,end`
 * It now also cuts sections off regardless of what silent speed is.

Replaced `--ignore` with `--mark_as_loud`. It also uses commas instead of hyphens.

Added `--mark_as_silent`, Mark a given range as silent. This is dependent on what silent speed is.

Added `--set_speed_for_range`. Allows you to set a custom speed for any section.
args are: `{speed},{starting point},{ending point}`

---

The default video codec has been changed from 'uncompressed' to 'copy'.



