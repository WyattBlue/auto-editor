# 23w20a

## What's Changed
- fcp7 backend (Premiere and DaVinci Resolve)
  - You can now export multiple video files into one xml
  - The xml now respects the number of channels the audio has and no longer assumes it's always 2
- v3 timeline backend
  - the `"timeline"` key has been flatten and removed
  - `"version"` value has been changed `"unstable:3.0"` -> `"3"`
  - the `"dur"` attribute for all timeline objects is now always the "real" duration even if the speed is != 1. This makes many internal operations simpler and imitates how fcp7 represents timing.
 - v1 timeline importing and exporting is back
 - All v(NUMBER) timelines now no longer use or accept semantic versioning

**Full Changelog**: https://github.com/WyattBlue/auto-editor/compare/23w15a...23w20a

