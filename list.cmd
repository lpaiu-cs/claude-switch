@echo off
rem List profiles / show the current active profile
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0claude-switch.ps1" -List
pause
