# 22w48a

### Bug Fixes
 - Fixed all of the subcommands not working when auto-editor is installed with pip
 - Make having the `readline` module optional for `repl`. This allows Windows to use it without immediately causing a traceback.

### Features
Auto-Editor can now read use its own v2 json timelines. v2 timelines are still undocumented and unstable[1] but is a step in the right direction and opens up the way for more powerful Premiere, ShotCut and FinalCutPro exports.

[1] In the sense that how it works can change from version to version. 

### Breaking Changes
Exporting v1 json timelines has been removed due to in part to format being entirely undocumented. Auto-Editor still uses a v1-format like structure for "Editor" exports and 

### What to Expect in the Future 
Besides making 'Premiere and friends' exports better, Auto-Editor will not work on new features till at least mid-Jan, 2023. Instead improving documentation will be the primary focus. 

**Full Changelog**: https://github.com/WyattBlue/auto-editor/compare/22w46a...22w48a

