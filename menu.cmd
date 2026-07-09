@echo off
rem Interactive menu: add accounts / switch between Claude Desktop profiles by number
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0claude-switch.ps1" -Menu
