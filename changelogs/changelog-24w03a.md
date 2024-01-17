# 24w03a

## What's Changed
 - Analyzing motion is now 1.3x faster. 
 - Changing the aspect ratio (adding padding) is now 2.7x faster.
 - Better support for the `yuv444p` `yuvj444p` pix_fmt's
 - Dropped the Pillow dependency
 - Upgrade pyav to 12.0.2

## Breaking Changes
 - Removed `--mark-as-loud` and `--mark-as-silent`. Use `--add-in`, `--cut-out` instead.
 - Removed `pixeldiff` as an option for `--edit`. Use `motion` instead.

**Full Changelog**: https://github.com/WyattBlue/auto-editor/compare/23w51a...24w03a
