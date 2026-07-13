#!/bin/zsh
# Interactive menu: add accounts / switch between Claude Desktop profiles by number.
cd -- "${0:A:h}" || exit 1
./claude-switch.sh --menu
