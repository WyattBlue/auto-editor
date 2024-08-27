---
title: Using Auto-Editor on Windows
---

# Using Auto-Editor on Windows
## Recommended Shell and Terminal
Use the [Windows Terminal](https://apps.microsoft.com/store/detail/windows-terminal/9N0DX20HK701) app with PowerShell when running auto-editor commands. Using the CMD shell isn't impossible, but you'll have to escape commands differently than shown in the docs.

### Shell vs. Terminal
A terminal is a GUI program that manages shells. It handles features like scrolling through history, and copy paste. A shell is a program that interacts with OS. Having a modern terminal means the terminal will look beautiful instead of ugly. Having a modern shell installed makes scripting much easier.

CMD is the older terminal/shell that Windows keeps around for compatibily reasons. I recommend using Windows Terminal plus Powershell instead.

## Running Auto-Editor on Many Files
Auto-Editor doesn't have an option that batch processes files, but you can achieve the same effect with a simple PowerShell script.

```
# Save to a new file with a ".ps1" extension
$files = "C:\Users\WyattBlue\MyDir\"
foreach ($f in Get-ChildItem $files) {
  auto-editor $(Join-Path -Path $files -ChildPath $f)
}
```
