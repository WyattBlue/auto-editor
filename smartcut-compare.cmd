@echo off
powershell.exe -NoLogo -NoProfile -NonInteractive -ExecutionPolicy Bypass -File "%~dp0scripts\smartcut-compare.ps1" %*
exit /b %ERRORLEVEL%
