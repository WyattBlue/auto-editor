# 22w43a

## Changes
Add Python 3.11 support, drop Python 3.8 support
Improve Premiere Pro and ShotCut XML reading

## New Features
--edit now has direct access to the `margin` `mincut` `minclip` `cook` functions. Along with `or` `and` `xor` `not`

```
--edit '(or (margin 5 motion:4%) (cook 6 3 audio:threshold=4%))
```

## Bug Fixes
Fix `or` `and` `xor` length resizing. Old behavior added random data instead of just filling zeros.

**Full Changelog**: https://github.com/WyattBlue/auto-editor/compare/22w39a...22w43a

