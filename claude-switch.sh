#!/bin/zsh
#
#  claude-switch.sh  -  Claude Desktop (macOS) account profile switcher
#  (one account active at a time; MOVE-BASED, mirrors the Windows claude-switch.ps1)
#
#  Usage:
#    claude-switch.sh <name>             switch to profile <name>, then launch Claude
#    claude-switch.sh --list             list profiles / show the active one
#    claude-switch.sh <name> --no-launch switch only, do not launch
#    claude-switch.sh --setup            (maintenance) ensure shared infra is linked everywhere
#    claude-switch.sh --menu             interactive menu: add / pick a profile by number
#    claude-switch.sh --stop             fully close Claude Desktop + all its children (run this
#                                        before updating the app, or it may fail with a file lock)
#
#  Why move-based (and how macOS differs from Windows):
#    On Windows the live Claude folder is reached through an MSIX junction, and making it a junction
#    itself created a DOUBLE junction that broke Claude's atomic writes (write tmp -> rename) of NEW
#    files. macOS has no such junction: ~/Library/Application Support/Claude is a plain real folder,
#    and a single symlink does NOT break rename() there. We still keep the proven move-based design
#    for parity and safety: the live folder is always a REAL folder (like a normal install), and
#    switching MOVES the active profile out to a store and MOVES the target profile in. Same-volume
#    moves are instant renames, so switching is fast and safe. Heavy account-neutral folders are
#    symlinked in from a single shared store so new profiles don't re-download the ~6 GB VM bundle.
#
#  Layout:
#    Live (active)  ~/Library/Application Support/Claude                      (REAL folder)
#    Inactive       ~/Library/Application Support/ClaudeProfiles/<name>
#    Shared infra   ~/Library/Application Support/ClaudeShared/<vm_bundles|claude-code|claude-code-vm>
#    Active marker  ~/Library/Application Support/ClaudeActiveProfile.txt

emulate -L zsh
setopt pipe_fail extended_glob

# Account-neutral folders shared across all profiles via symlinks.
typeset -ga SHARED_FOLDERS=(vm_bundles claude-code claude-code-vm)

typeset -g APP_BUNDLE_ID='com.anthropic.claudefordesktop'
typeset -g APP_PATH='/Applications/Claude.app'

# --- Paths -------------------------------------------------------------------
typeset -g SUPPORT="$HOME/Library/Application Support"
typeset -g LIVE="$SUPPORT/Claude"
typeset -g STORE="$SUPPORT/ClaudeProfiles"
typeset -g SHARED="$SUPPORT/ClaudeShared"
typeset -g MARKER="$SUPPORT/ClaudeActiveProfile.txt"
typeset -g CC_CANON="$SHARED/cc-sessions-canonical"
typeset -g LAM_CANON="$SHARED/lam-sessions-canonical"
typeset -g CC_MAP="$SHARED/cc-sync-map.json"
typeset -g LOCKDIR="$SHARED/claude-switch.lock"
typeset -g LOCK_HELD=0

die()  { print -u2 -- "error: $*"; exit 1; }
info() { print -- "$*"; }

# --- Process handling --------------------------------------------------------
#
# Every process that belongs to Claude Desktop: the app bundle processes (image under
# /Applications/Claude.app) PLUS everything they spawned. The children - the Claude Code CLI, its
# MCP servers, the sandbox VM - run from the Application Support/Claude subfolders and carry the
# live user-data-dir on their command line, so an app-path-only match would miss them. We take the
# whole tree down: leftover children hold handles inside Live that can break a folder move
# mid-switch, and keep files locked during an app update. Roots are matched PER PROCESS (by its own
# command line), never seeded from one "main" PID, so a lingering helper or an orphaned CLI/VM child
# is still caught on its own. The current process and its ANCESTORS are never returned, so running
# this from a shell can't make it kill itself.

typeset -gA PROC_PPID PROC_CMD PROTECT

# Fill PROC_PPID / PROC_CMD (pid -> ppid / full command line).
_load_proc_table() {
  PROC_PPID=(); PROC_CMD=()
  local pid ppid cmd
  while IFS=$'\t' read -r pid ppid cmd; do
    [[ -z $pid ]] && continue
    PROC_PPID[$pid]=$ppid
    PROC_CMD[$pid]=$cmd
  done < <(ps -axww -o pid=,ppid=,command= | sed -E 's/^[[:space:]]*([0-9]+)[[:space:]]+([0-9]+)[[:space:]]+/\1'$'\t''\2'$'\t''/')
}

# True if the command line looks like a Claude Desktop process (app or a live child).
_is_claude_cmd() {
  local cmd=$1 s
  [[ $cmd == *"$APP_PATH/"* ]] && return 0
  [[ $cmd == *"--user-data-dir=$LIVE"* ]] && return 0
  for s in $SHARED_FOLDERS; do [[ $cmd == *"$LIVE/$s/"* ]] && return 0; done
  return 1
}

# Protect the current process and every ancestor of it.
_build_protect() {
  PROTECT=()
  local p=$$
  while [[ -n $p && $p != 0 && -z ${PROTECT[$p]-} ]]; do
    PROTECT[$p]=1
    p=${PROC_PPID[$p]-}
  done
}

# True if we are running from INSIDE Claude Desktop (an ancestor is a Claude process). Stopping the
# app from within would tear down our own host session, so destructive ops refuse in that case.
_running_inside_claude() {
  local p=${PROC_PPID[$$]-}
  while [[ -n $p && $p != 0 && $p != 1 ]]; do
    _is_claude_cmd "${PROC_CMD[$p]-}" && return 0
    p=${PROC_PPID[$p]-}
  done
  return 1
}

# Print the pids of the whole Claude Desktop tree (roots + descendants), excluding PROTECT.
_claude_pids() {
  _load_proc_table
  _build_protect
  local pid pp c
  typeset -A children seen
  for pid in ${(k)PROC_PPID}; do
    pp=${PROC_PPID[$pid]}
    children[$pp]="${children[$pp]-} $pid"
  done
  local -a queue out
  for pid in ${(k)PROC_CMD}; do
    [[ -n ${PROTECT[$pid]-} ]] && continue
    if _is_claude_cmd "${PROC_CMD[$pid]}"; then queue+=$pid; fi
  done
  while (( ${#queue} )); do
    pid=${queue[1]}; shift queue
    [[ -n ${seen[$pid]-} ]] && continue
    seen[$pid]=1
    [[ -n ${PROTECT[$pid]-} ]] && continue
    out+=$pid
    for c in ${=children[$pid]-}; do queue+=$c; done
  done
  print -l -- $out
}

# Fully close Claude Desktop and everything it spawned. Success is verified against concrete pids,
# not against whether detection can still see them: we remember every pid we ever spot and only
# return once all are gone, so a child that drops out of a later scan can't make us report success
# while it still holds a lock.
stop_claude() {
  _load_proc_table
  if _running_inside_claude; then
    die "refusing to stop Claude Desktop from inside it (that would kill this session). Run claude-switch from Terminal.app instead."
  fi
  typeset -A tracked
  local i pid
  local -a alive
  for (( i = 0; i < 30; i++ )); do
    for pid in $(_claude_pids); do tracked[$pid]=1; done
    alive=()
    for pid in ${(k)tracked}; do kill -0 $pid 2>/dev/null && alive+=$pid; done
    (( ${#alive} == 0 )) && return 0
    for pid in $alive; do kill -TERM $pid 2>/dev/null; done
    sleep 0.15
    for pid in $alive; do kill -0 $pid 2>/dev/null && kill -KILL $pid 2>/dev/null; done
    sleep 0.1
  done
  alive=()
  for pid in ${(k)tracked}; do kill -0 $pid 2>/dev/null && alive+=$pid; done
  if (( ${#alive} )); then
    die "Claude Desktop is still running and could not be closed: ${(j:, :)alive}. Close it manually, then retry."
  fi
}

# --- Profile name validation (guards path traversal; profile name becomes a folder) ---
assert_valid_name() {
  local name=$1
  if [[ -z $name || ! $name =~ '^[A-Za-z0-9._-]{1,64}$' || $name == '.' || $name == '..' ]]; then
    die "Invalid profile name '$name'. Use 1-64 characters: letters, digits, dot, dash, underscore (no spaces or path separators)."
  fi
}
# Non-fatal variant for interactive input.
valid_name() {
  local name=$1
  [[ -n $name && $name =~ '^[A-Za-z0-9._-]{1,64}$' && $name != '.' && $name != '..' ]]
}

# --- Active marker -----------------------------------------------------------
get_active() {
  [[ -f $MARKER ]] || return 1
  local v; v=$(< "$MARKER"); v=${v//[$'\t\r\n ']/}
  [[ -n $v ]] && print -r -- "$v"
}
set_active() { print -rn -- "$1" > "$MARKER"; }

# --- Cross-process lock (mkdir is atomic; released by an EXIT trap) -----------
acquire_lock() {
  mkdir -p -- "$SHARED"
  if [[ -d $LOCKDIR ]]; then
    local mtime now age
    mtime=$(stat -f %m "$LOCKDIR" 2>/dev/null) || mtime=0
    now=$(date +%s)
    age=$(( now - mtime ))
    (( age > 300 )) && rm -rf -- "$LOCKDIR"   # stale lock from a crashed run
  fi
  if ! mkdir -- "$LOCKDIR" 2>/dev/null; then
    die "Another claude-switch operation is in progress (lock: $LOCKDIR). If it is stale, remove that folder and retry."
  fi
  LOCK_HELD=1
  trap 'release_lock' EXIT INT TERM
}
release_lock() { (( LOCK_HELD )) && rm -rf -- "$LOCKDIR" 2>/dev/null; LOCK_HELD=0; }

# --- Shared infra symlinks ---------------------------------------------------
ensure_shared_links() {
  local profile_dir=$1 name share link
  mkdir -p -- "$SHARED"
  for name in $SHARED_FOLDERS; do
    share="$SHARED/$name"
    link="$profile_dir/$name"
    if [[ -e $link && ! -L $link ]]; then
      # A real folder sits where the symlink should be: seed the shared store from it (first time)
      # or drop it (shared store already exists), then link.
      if [[ -e $share ]]; then rm -rf -- "$link"
      else mv -- "$link" "$share"; fi
    fi
    if [[ -e $share && ! -e $link ]]; then
      ln -s -- "$share" "$link"
    fi
  done
  return 0
}

# --- Claude Code session sync (copy, not symlink) ----------------------------
# The desktop stores CC sessions per account under
#   claude-code-sessions/<accountUuid>/<orgUuid>/local_*.json
# Synced with a newest-wins copy through a canonical store on each switch (app stopped).
# CC_ACCT / CC_ORG / CC_EMAIL map profile name -> account/org uuid + free-text label.
typeset -gA CC_ACCT CC_ORG CC_EMAIL

load_cc_map() {
  CC_ACCT=(); CC_ORG=(); CC_EMAIL=()
  [[ -f $CC_MAP ]] || return 0
  local xml
  xml=$(plutil -convert xml1 -o - "$CC_MAP" 2>/dev/null) || {
    print -u2 -- "[cc-sync] map load failed (invalid JSON)"; return 0
  }
  # Walk the xml1 plist: top-level <key> = profile name, nested <key>/<string> = its fields.
  local parsed
  parsed=$(print -r -- "$xml" | awk '
    function unesc(s){ gsub(/^[ \t]*<(key|string)>/,"",s); gsub(/<\/(key|string)>[ \t]*$/,"",s);
                       gsub(/&lt;/,"<",s); gsub(/&gt;/,">",s); gsub(/&amp;/,"\\&",s); return s }
    /<dict>/  { depth++; next }
    /<\/dict>/{ depth--; next }
    depth==1 && /<key>/    { name=unesc($0); next }
    depth==2 && /<key>/    { field=unesc($0); next }
    depth==2 && /<string>/ { printf "%s\t%s\t%s\n", name, field, unesc($0) }
  ')
  local n f v
  while IFS=$'\t' read -r n f v; do
    [[ -z $n ]] && continue
    case $f in
      accountUuid) CC_ACCT[$n]=$v ;;
      orgUuid)     CC_ORG[$n]=$v ;;
      email)       CC_EMAIL[$n]=$v ;;
    esac
  done <<< "$parsed"
}

_json_escape() { local s=$1; s=${s//\\/\\\\}; s=${s//\"/\\\"}; print -rn -- "$s"; }

save_cc_map() {
  mkdir -p -- "$SHARED"
  local -a names; names=(${(ok)CC_ACCT})
  local tmp="$CC_MAP.tmp.$$" first=1 n
  {
    print -- "{"
    for n in $names; do
      (( first )) || print -- ","
      first=0
      printf '  "%s": { "accountUuid": "%s", "orgUuid": "%s", "email": "%s" }' \
        "$(_json_escape "$n")" "$(_json_escape "${CC_ACCT[$n]-}")" \
        "$(_json_escape "${CC_ORG[$n]-}")" "$(_json_escape "${CC_EMAIL[$n]-}")"
    done
    (( first )) || print --
    print -- "}"
  } > "$tmp"
  mv -- "$tmp" "$CC_MAP"
}

cc_view_dir() {
  local name=$1
  local acct=${CC_ACCT[$name]-} org=${CC_ORG[$name]-}
  [[ -n $acct && -n $org ]] || return 1
  print -r -- "$LIVE/claude-code-sessions/$acct/$org"
}

# newest-wins copy of local_*.json from $1 into $2
_sync_dir() {
  local src=$1 dst=$2 f base st dt
  [[ -d $src ]] || return 0
  mkdir -p -- "$dst"
  for f in "$src"/local_*.json(N); do
    base=${f:t}
    if [[ ! -e "$dst/$base" ]]; then
      cp -p -- "$f" "$dst/$base"
    else
      st=$(stat -f %m "$f" 2>/dev/null) || st=0
      dt=$(stat -f %m "$dst/$base" 2>/dev/null) || dt=0
      (( st > dt )) && cp -p -- "$f" "$dst/$base"
    fi
  done
  return 0
}

sync_pull_cc() { local v; v=$(cc_view_dir "$1") || return 0; _sync_dir "$v" "$CC_CANON"; }
sync_push_cc() {
  local v; v=$(cc_view_dir "$1") || return 0
  [[ -d $CC_CANON ]] || return 0
  _sync_dir "$CC_CANON" "$v"
  _rewrite_session_paths "$v" "${CC_ACCT[$1]-}" "${CC_ORG[$1]-}"
}

# --- Session CONTENT sync (local-agent-mode-sessions) -------------------------
# The index above only lists sessions; their actual content - outputs, uploads, audit log, the
# per-session config - lives account-keyed under
#   local-agent-mode-sessions/<accountUuid>/<orgUuid>/local_<id>{,/}
# Without syncing this, a switched-to account sees the session in its list but opens it empty
# ("project contents missing"). We union it through a canonical store like the index: session ids
# are uuids, so entries from different accounts never collide. Directories merge per-file
# newest-wins via rsync; the per-session local_*.json files use the same newest-wins copy as the
# index. Caches (rpm/, cowork-*-cache.json) are account-local and skipped - the app regenerates
# them.
typeset -g HAVE_RSYNC=0
command -v rsync >/dev/null 2>&1 && HAVE_RSYNC=1

lam_view_dir() {
  local name=$1
  local acct=${CC_ACCT[$name]-} org=${CC_ORG[$name]-}
  [[ -n $acct && -n $org ]] || return 1
  print -r -- "$LIVE/local-agent-mode-sessions/$acct/$org"
}

_sync_lam() {
  local src=$1 dst=$2 e base
  [[ -d $src ]] || return 0
  mkdir -p -- "$dst"
  for e in "$src"/local_*(N/); do   # session content dirs
    base=${e:t}
    if (( HAVE_RSYNC )); then
      rsync -a -u -- "$e/" "$dst/$base/"
    else
      [[ -e "$dst/$base" ]] || cp -Rp -- "$e" "$dst/$base"
    fi
  done
  _sync_dir "$src" "$dst"           # per-session local_*.json files (newest wins)
  return 0
}

# Session jsons embed ABSOLUTE paths that include the owning account's uuids
# (".../local-agent-mode-sessions/<acct>/<org>/local_<id>/outputs"). After copying a session to a
# different account's view, those paths still point at the OLD account and the session opens
# broken. Rewrite every <uuid>/<uuid> pair under local-agent-mode-sessions/ to the target
# account's pair. Runs on push only (canonical keeps whatever it captured; every push re-targets).
_rewrite_session_paths() {
  local dir=$1 acct=$2 org=$3 f
  [[ -n $acct && -n $org && -d $dir ]] || return 0
  local u8='[0-9a-fA-F]{8}' u4='[0-9a-fA-F]{4}' u12='[0-9a-fA-F]{12}'
  local uuid="$u8(-$u4){3}-$u12"
  for f in "$dir"/local_*.json(N); do
    LC_ALL=C sed -E -i '' \
      "s|local-agent-mode-sessions/$uuid/$uuid|local-agent-mode-sessions/$acct/$org|g" "$f"
  done
  return 0
}

sync_pull_lam() { local v; v=$(lam_view_dir "$1") || return 0; _sync_lam "$v" "$LAM_CANON"; }
sync_push_lam() {
  local v; v=$(lam_view_dir "$1") || return 0
  [[ -d $LAM_CANON ]] || return 0
  _sync_lam "$LAM_CANON" "$v"
  _rewrite_session_paths "$v" "${CC_ACCT[$1]-}" "${CC_ORG[$1]-}"
}

# --- Account identity detection ----------------------------------------------
typeset -g UUID_GLOB='[0-9a-fA-F](#c8)-[0-9a-fA-F](#c4)-[0-9a-fA-F](#c4)-[0-9a-fA-F](#c4)-[0-9a-fA-F](#c12)'

# accountUuid of whoever is logged in under Live, straight from the app's own config. This exists
# right after login even if the account has never created a session, which the session-scan
# heuristic below can't handle (a fresh account has no session files at all - the bootstrap gap
# that used to leave new profiles permanently unmapped and content sync silently disabled).
_config_account() {
  local cfg="$LIVE/config.json" acct
  [[ -f $cfg ]] || return 1
  acct=$(plutil -extract lastKnownAccountUuid raw -o - "$cfg" 2>/dev/null) || return 1
  [[ $acct == ${~UUID_GLOB} ]] || return 1
  print -r -- "$acct"
}

# orgUuid for a given account: prefer real org dirs under Live's session stores (pick the freshest
# if several), else fall back to the org-scoped dxt:allowlist* keys in config.json. config.json
# contains JSON null values, which plutil's plist conversion rejects, so the keys are grepped raw.
_org_for_account() {
  local acct=$1 root org_dir org f st latest
  local best_org='' best_t=-1
  for root in "$LIVE/claude-code-sessions" "$LIVE/local-agent-mode-sessions"; do
    for org_dir in "$root/$acct"/${~UUID_GLOB}(N/); do
      org=${org_dir:t}
      latest=$(stat -f %m "$org_dir" 2>/dev/null) || latest=0
      for f in "$org_dir"/local_*.json(N); do
        st=$(stat -f %m "$f" 2>/dev/null) || st=0
        (( st > latest )) && latest=$st
      done
      [[ $org == "$best_org" ]] && continue
      if (( latest > best_t )); then best_t=$latest; best_org=$org; fi
    done
  done
  if [[ -z $best_org && -f "$LIVE/config.json" ]]; then
    best_org=$(LC_ALL=C grep -oE '"dxt:allowlist[A-Za-z]*:[0-9a-fA-F]{8}(-[0-9a-fA-F]{4}){3}-[0-9a-fA-F]{12}"' \
      "$LIVE/config.json" 2>/dev/null | sed -E 's/.*:([0-9a-fA-F-]{36})"$/\1/' | sort -u | head -1)
  fi
  [[ -n $best_org ]] || return 1
  print -r -- "$best_org"
}

# Self-heal the map entry for profile <name> from whatever is sitting in Live right now. Primary
# source: the app's config.json (lastKnownAccountUuid + org detection above) - authoritative for
# who is logged in NOW and present even for a brand-new account with zero sessions. Fallback:
# whichever account/org pair has the freshest session file (covers app versions without
# lastKnownAccountUuid). Runs before pull (departing profile) and after activation (arriving
# profile), so logging into a different account under a profile fixes itself on the next switch.
update_cc_map_entry() {
  local name=$1
  local acct='' org='' note=''

  acct=$(_config_account) && org=$(_org_for_account "$acct") || { acct=''; org=''; }

  if [[ -z $acct || -z $org ]]; then
    # Fallback: freshest session file across all account/org dirs in Live.
    local sess="$LIVE/claude-code-sessions" acct_dir org_dir a o f st latest
    local best_t=-1 seen=0
    [[ -d $sess ]] || return 0
    for acct_dir in "$sess"/*(N/); do
      a=${acct_dir:t}
      for org_dir in "$acct_dir"/*(N/); do
        o=${org_dir:t}
        (( seen++ ))
        latest=-1
        for f in "$org_dir"/local_*.json(N); do
          st=$(stat -f %m "$f" 2>/dev/null) || st=0
          (( st > latest )) && latest=$st
        done
        (( latest < 0 )) && { latest=$(stat -f %m "$org_dir" 2>/dev/null) || latest=0; }
        if (( latest > best_t )); then best_t=$latest; acct=$a; org=$o; fi
      done
    done
    (( seen > 1 )) && note=" ($seen accounts seen under this profile, picked most recently active)"
  fi

  [[ -n $acct && -n $org ]] || return 0
  if [[ ${CC_ACCT[$name]-} == "$acct" && ${CC_ORG[$name]-} == "$org" ]]; then return 0; fi
  CC_ACCT[$name]=$acct
  CC_ORG[$name]=$org
  [[ -n ${CC_EMAIL[$name]-} ]] || CC_EMAIL[$name]=''
  save_cc_map
  info "[cc-sync] '$name' account changed -> map updated to $acct$note"
}

# --- Launch ------------------------------------------------------------------
launch_claude() {
  if open -b "$APP_BUNDLE_ID" 2>/dev/null; then :
  elif [[ -d $APP_PATH ]]; then open -a "$APP_PATH"
  else die "Claude Desktop not found (looked for $APP_PATH)."; fi
  info "Launching Claude..."
}

# --- Profile-name listing helper ---------------------------------------------
profile_names() {   # prints active first, then the rest, unique
  local active=$1 d
  local -a names
  [[ -n $active ]] && names+=$active
  for d in "$STORE"/*(N/); do [[ ${d:t} != "$active" ]] && names+=${d:t}; done
  print -l -- ${(u)names}
}

# =============================================================================
# Commands
# =============================================================================
cmd_stop() {
  acquire_lock
  stop_claude
  release_lock
  info "Claude Desktop and all its background processes are stopped."
  info "You can now update Claude Desktop safely."
}

cmd_setup() {
  acquire_lock
  stop_claude
  [[ -d $LIVE ]] && ensure_shared_links "$LIVE"
  local d
  for d in "$STORE"/*(N/); do ensure_shared_links "$d"; done
  release_lock
  info "[setup] shared infra ensured. Shared store: $SHARED"
}

cmd_list() {
  local active; active=$(get_active) || active=''
  print -- ""
  print -- "Active profile: ${active:-(none)}"
  print -- "\nProfiles:"
  local n
  for n in ${(f)"$(profile_names "$active")"}; do
    [[ -z $n ]] && continue
    if [[ $n == "$active" ]]; then print -- "* $n"; else print -- "  $n"; fi
  done
  print -- "\nSwitch with:  claude-switch <name>   (unknown name = new empty profile)\n"
}

cmd_menu() {
  local active choice newname target i
  local -a names
  while true; do
    active=$(get_active) || active=''
    names=(${(f)"$(profile_names "$active")"})
    names=(${names:#})   # drop empty entries

    print -- "\n=== claude-switch ==="
    print -- "Active: ${active:-(none)}"
    print -- ""
    for (( i = 1; i <= ${#names}; i++ )); do
      local mark=''; [[ ${names[i]} == "$active" ]] && mark='  [active]'
      print -- "  $i) ${names[i]}$mark"
    done
    print -- "  N) Add new profile"
    print -- "  Q) Quit"
    print -n -- "\nSelect: "
    if ! read -r choice; then return 0; fi

    [[ -z $choice || $choice == [Qq] ]] && return 0
    target=''
    if [[ $choice == [Nn] ]]; then
      print -n -- "New profile name: "; read -r newname || continue
      if ! valid_name "$newname"; then
        print -u2 -- "Invalid profile name. Use 1-64 letters, digits, dot, dash, underscore."; continue
      fi
      if (( ${names[(Ie)$newname]} )); then
        print -u2 -- "Profile '$newname' already exists - pick it from the list."; continue
      fi
      target=$newname
    elif [[ $choice == <-> ]] && (( choice >= 1 && choice <= ${#names} )); then
      target=${names[choice]}
    else
      print -u2 -- "Invalid choice."; continue
    fi
    exec "$ZSH_ARGZERO" "$target"
  done
}

# Restore a stashed profile back into Live after a failed activation.
_rollback_stash() {
  local sname=$1 spath=$2
  if [[ -n $spath && ! -e $LIVE && -e $spath ]]; then
    mv -- "$spath" "$LIVE" && set_active "$sname"
    print -u2 -- "[rollback] switch failed; restored '$sname' as the active profile."
  fi
}

cmd_switch() {
  local name=$1
  assert_valid_name "$name"

  _load_proc_table
  if _running_inside_claude; then
    die "refusing to switch profiles from inside Claude Desktop (stopping it would kill this session). Run claude-switch from Terminal.app instead."
  fi

  acquire_lock
  stop_claude

  local active; active=$(get_active) || active=''

  # Capture the outgoing account's CC sessions into the shared canonical store (Live still holds it).
  if [[ -n $active ]]; then
    update_cc_map_entry "$active" 2>/dev/null || print -u2 -- "[cc-sync] detect skipped"
    sync_pull_cc "$active" 2>/dev/null || print -u2 -- "[cc-sync] pull skipped"
    sync_pull_lam "$active" 2>/dev/null || print -u2 -- "[cc-sync] content pull skipped"
  fi

  if [[ $active != "$name" ]]; then
    # Seed the shared store from the outgoing profile BEFORE moving it away, so heavy
    # account-neutral folders (vm_bundles etc.) live in ClaudeShared once and the incoming
    # profile can symlink them instead of re-downloading the ~6 GB bundle.
    [[ -d $LIVE ]] && ensure_shared_links "$LIVE"

    # Stash the currently active profile (sitting at Live) back into the store.
    local stashed_name='' stashed_path=''
    if [[ -d $LIVE ]]; then
      [[ -n $active ]] || active='main'
      local dest="$STORE/$active"
      [[ -e $dest ]] && die "Cannot stash active profile: '$dest' already exists. Manual check needed."
      mv -- "$LIVE" "$dest" || die "Failed to stash active profile to '$dest'."
      stashed_name=$active; stashed_path=$dest
    fi

    # Activate the target profile (move it to Live), or create a fresh one.
    local tgt="$STORE/$name"
    if [[ -d $tgt ]]; then
      if ! mv -- "$tgt" "$LIVE"; then
        _rollback_stash "$stashed_name" "$stashed_path"
        die "Failed to activate profile '$name'."
      fi
    else
      if ! mkdir -p -- "$LIVE"; then
        _rollback_stash "$stashed_name" "$stashed_path"
        die "Failed to create profile '$name'."
      fi
      info "[new profile] '$name' created - log in with the new account after launch."
    fi
    set_active "$name"
  fi

  # Give the now-active account the full union of CC sessions (Live now holds the target).
  update_cc_map_entry "$name" 2>/dev/null || print -u2 -- "[cc-sync] detect skipped"
  sync_push_cc "$name" 2>/dev/null || print -u2 -- "[cc-sync] push skipped"
  sync_push_lam "$name" 2>/dev/null || print -u2 -- "[cc-sync] content push skipped"
  ensure_shared_links "$LIVE"
  release_lock
  info "Active profile -> '$name'"

  (( OPT_NOLAUNCH )) || launch_claude
}

# =============================================================================
# Argument parsing + dispatch
# =============================================================================
typeset -g OPT_LIST=0 OPT_NOLAUNCH=0 OPT_SETUP=0 OPT_MENU=0 OPT_STOP=0
typeset -g PROFILE_NAME=''
for arg in "$@"; do
  case $arg in
    -List|--list)          OPT_LIST=1 ;;
    -NoLaunch|--no-launch) OPT_NOLAUNCH=1 ;;
    -Setup|--setup)        OPT_SETUP=1 ;;
    -Menu|--menu)          OPT_MENU=1 ;;
    -Stop|--stop)          OPT_STOP=1 ;;
    -h|--help)
      sed -n '3,14p' "$ZSH_ARGZERO" | sed 's/^#[ ]\{0,1\}//'
      exit 0 ;;
    -*)  die "Unknown option: $arg" ;;
    *)   PROFILE_NAME=$arg ;;
  esac
done

[[ -d $APP_PATH ]] || die "Claude Desktop not found at $APP_PATH. Install it first."
mkdir -p -- "$STORE" "$SHARED"

if (( OPT_STOP )); then cmd_stop; exit 0; fi

load_cc_map

# First-ever original install: Live is a real folder but no marker yet -> name it 'main'.
if [[ -d $LIVE && ! -L $LIVE && ! -f $MARKER ]]; then
  set_active 'main'
fi

if (( OPT_SETUP )); then cmd_setup; exit 0; fi
if (( OPT_MENU )); then cmd_menu; exit 0; fi
if (( OPT_LIST )) || [[ -z $PROFILE_NAME ]]; then cmd_list; exit 0; fi

cmd_switch "$PROFILE_NAME"
