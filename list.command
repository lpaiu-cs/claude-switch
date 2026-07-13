#!/bin/zsh
# List profiles / show the current active profile.
cd -- "${0:A:h}" || exit 1
./claude-switch.sh --list
print -n -- "\nPress Return to close..."; read -r _
