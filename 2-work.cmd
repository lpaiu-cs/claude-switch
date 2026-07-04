@echo off
rem Switch to the 'work' profile, then launch Claude Desktop
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0claude-switch.ps1" work
