#!/bin/zsh
# Switch to the 'main' profile, then launch Claude Desktop.
# Use this profile for Claude Desktop app updates / app-level maintenance.
cd -- "${0:A:h}" || exit 1
./claude-switch.sh main
