#!/bin/zsh
# Session-sync rules of claude-switch.sh. Loads only its functions into a throwaway HOME: never
# touches the real Claude profile and never stops or launches anything.
emulate -L zsh
fail() { print -u2 -- "FAIL: $*"; exit 1 }
T=$(mktemp -d "${TMPDIR:-/tmp}/claude-switch-test.XXXXXX") || exit 1
trap 'rm -rf -- "$T"' EXIT
export HOME=$T
source "${0:A:h}/../claude-switch.sh"

view=$T/view canon=$T/canon
mkdir -p $view $canon
# The 2026-09-27 loss: a stale copy the app re-saved on focus (newest mtime) vs. real progress.
print -rn '{"cliSessionId":"old","lastActivityAt":100}' > $view/local_X.json
print -rn '{"cliSessionId":"new","lastActivityAt": 200}' > $canon/local_X.json   # Cowork files are pretty-printed
touch -t 202601010000 $canon/local_X.json
_sync_dir $view $canon
[[ $(<$canon/local_X.json) == *'"new"'* ]] || fail "a stale copy with a newer mtime overwrote newer work"
_sync_dir $canon $view
[[ $(<$view/local_X.json) == *'"new"'* ]] || fail "newer work did not replace the stale copy"

# Same activity: newer mtime still wins, so renames/archive flags keep propagating.
print -rn '{"title":"renamed","lastActivityAt":200}' > $view/local_X.json
_sync_dir $view $canon
[[ $(<$canon/local_X.json) == *renamed* ]] || fail "tie on lastActivityAt did not fall back to mtime"

print -rn '{"lastActivityAt":1}' > $view/local_Y.json
_sync_dir $view $canon
[[ -e $canon/local_Y.json ]] || fail "a new session was not copied"

print "PASS: stale-copy protection, mtime tie-break, new-session copy"
