@echo off
rem Switch to the 'main' profile, then launch Claude Desktop
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0claude-switch.ps1" main
