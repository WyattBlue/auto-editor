@echo off
powershell.exe -NoLogo -NoProfile -NonInteractive -ExecutionPolicy Bypass -File "%~dp0scripts\shorts.ps1" %*
exit /b %ERRORLEVEL%
