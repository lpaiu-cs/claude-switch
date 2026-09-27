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

# Cowork content: hidden/nested files and empty dirs arrive as clones; a newer destination is kept.
src=$T/lam-src dst=$T/lam-dst
mkdir -p $src/local_A/.claude/projects/p $src/local_A/outputs $src/local_A/uploads $dst
print -rn one > $src/local_A/.claude/projects/p/t.jsonl
nfd=$'가'.txt                      # decomposed Hangul, as macOS apps write it
print -rn x > $src/local_A/uploads/$nfd
print -rn '{"lastActivityAt":1}' > $src/local_A.json
_sync_lam $src $dst
[[ $(<$dst/local_A/.claude/projects/p/t.jsonl) == one ]] || fail "a hidden nested session file was not copied"
[[ -d $dst/local_A/outputs ]] || fail "an empty session dir (outputs/) was not recreated"
[[ $(cd $dst/local_A/uploads && find . -type f) == ./$nfd ]] || fail "a file name's Unicode form changed in the copy"
[[ -e $dst/local_A.json ]] || fail "the session json was not copied"
print -rn newer > $dst/local_A/.claude/projects/p/t.jsonl
_sync_lam $src $dst
[[ $(<$dst/local_A/.claude/projects/p/t.jsonl) == newer ]] || fail "sync overwrote a newer destination file"

print "PASS: stale-copy protection, mtime tie-break, new-session copy, Cowork content copy"
