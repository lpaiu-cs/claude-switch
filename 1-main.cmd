@echo off
rem Switch to the 'main' profile, then launch Claude Desktop
rem Use this profile for Claude Desktop app updates / app-level maintenance.
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0claude-switch.ps1" main
