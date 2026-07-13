#!/bin/zsh
# Switch to the 'work' profile, then launch Claude Desktop.
cd -- "${0:A:h}" || exit 1
./claude-switch.sh work
