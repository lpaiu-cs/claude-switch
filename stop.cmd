@echo off
rem Fully close Claude Desktop and every process it spawned (Claude Code CLI, Node services,
rem sandbox VM). Run this BEFORE updating Claude Desktop so the update isn't blocked by a locked
rem file ("Another program is currently using this file", which otherwise needs a reboot).
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0claude-switch.ps1" -Stop
pause
