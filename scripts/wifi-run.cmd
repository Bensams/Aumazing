@echo off
setlocal
rem The .ps1 holds the window open itself (Press Enter to close), so no pause here.
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0wifi-run.ps1" %*
exit /b %ERRORLEVEL%
