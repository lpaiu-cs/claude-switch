@echo off
rem ONE-TIME: share heavy infra (vm_bundles) across profiles + relabel current account to 'work'
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0setup-shared.ps1"
