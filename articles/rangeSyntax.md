# `--cut_out`, `--ignore`, and Range Syntax


## `--cut_out`

is used to remove any sections of the media specified. For example:

```
auto-editor example.mp4 --cut_out 0-5
```

Will remove the first five seconds of `example.mp4`

And:

```
auto-editor example.mp4 --cut_out 20-end
```

Will remove all of `example.mp4` besides the first 20 seconds.


You can also use decimals:

```
auto-editor example.mp4 --cut_out 10.7-23.4
```

and it will cut out the range from 10.7 seconds to 23.4 seconds.


## `--ignore`

Ignore does the inverse of `--cut_out`, it ensures that auto-editor does not cut out anything in that section (**Ignore** loudness).

It can be used along with `--cut_out`.

```
auto-editor example.mp4 --ignore 0-20 --cut_out 20-end
```

or used byitself.

```
auto-editor example.mp4 --ignore 20-30
```

both `--cut_out` and `--ignore` use range syntax so any range that is recognized by `--cut_out` will be recongized `--ignore` or any future option that uses it.

## Range Syntax

Range syntax is a special data type for declaring ranges.

It follows the pattern: `{float}-{float} ...` using a hythen to delimate between the start and end point, and is in seconds instead of the usual "frames" unit.

It can be repeated infinitely. So

```
auto-editor example.mp4 --cut_out 0-10 20-30 40-45
```

is possible.


### Out-of-bounds and Edge Cases.

Range syntax is gracious on what it allows.

You can go out of bounds.

