#!/bin/zsh
# Fully close Claude Desktop and every process it spawned (Claude Code CLI, MCP servers,
# sandbox VM). Run this BEFORE updating Claude Desktop so the update is not blocked by a
# running helper. Must be run from Terminal/Finder, NOT from inside Claude Desktop.
cd -- "${0:A:h}" || exit 1
./claude-switch.sh --stop
print -n -- "\nPress Return to close..."; read -r _
