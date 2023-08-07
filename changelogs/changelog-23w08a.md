# 23w08a

## What's Changed
- `auto-editor info` now displays the audio stream's channel count
- `--add` now uses palet for parsing instead of having a little parsing language for each attribute. 
```shell
#  old way, adding special characters like newline and tab was terrible 
auto-editor --add 'text:0,60,This is my text!
Wow,font=Arial'

#  new clean and explicit way
auto-editor --add 'text:0,60,"This is my text!\nWow",font="Arial"'
```
- The palet scripting language, and its [associated docs](https://auto-editor.com/ref/23w08a/palet), has been greatly improved. For a normal auto-editor, palet doesn't matter right now, but allow for new and exciting auto-editor functionally in the future.

**Full Changelog**: https://github.com/WyattBlue/auto-editor/compare/23w04a...23w08a

