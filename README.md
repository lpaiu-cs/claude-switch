# claude-switch

Switch between multiple **Claude Desktop** (Microsoft Store / MSIX) account profiles on
Windows — one account active at a time, no re-download of the multi-gigabyte VM bundle,
and your logins preserved across switches.

> Unofficial community tool. Not affiliated with or endorsed by Anthropic. It manipulates
> Claude Desktop's local data folders, which are undocumented and can change between app
> updates. Use at your own risk.

---

## Why this exists

Claude Desktop (the Store build) keeps all of an account's data under a single folder that
Windows exposes through an MSIX junction:

```
%APPDATA%\Claude   ->   %LOCALAPPDATA%\Packages\<PackageFamilyName>\LocalCache\Roaming\Claude
```

There's no built-in way to keep two accounts side by side. The obvious trick — making that
`Claude` folder *itself* a junction pointing at a per-account profile — **breaks the app**:
the data is then reached through *two* junctions, and Claude's atomic writes (`write tmp ->
rename`) of **new** files fail with `ENOENT` (e.g. `git-worktrees.json`). A populated profile
happens to launch (those files already exist, so it's an overwrite), but a fresh/empty
profile crashes on first run.

**claude-switch avoids the double junction entirely.** The live `Claude` folder is always a
**real folder** — exactly like a normal install (one junction). Switching accounts *moves*
the active profile out to a store and *moves* the target profile in. Same-volume moves are
instant renames, so switching is fast and safe.

---

## Requirements

- Windows 10 / 11
- **Claude Desktop installed from the Microsoft Store** (MSIX package named `Claude`)
- Windows PowerShell 5.1 (ships with Windows — no install needed)

---

## Install

1. Download or clone this repo anywhere (keep the files together):
   ```
   git clone https://github.com/lpaiu-cs/claude-switch.git
   ```
2. That's it. Use the `.cmd` helpers by double-clicking, or call `claude-switch.ps1` from a
   terminal.

The first time you run it, the current install is automatically labeled `main` and becomes
your first profile.

---

## Usage

### Quick helpers (double-click)

| File          | Action                                             |
| ------------- | -------------------------------------------------- |
| `1-main.cmd`  | Switch to the `main` profile, then launch Claude   |
| `2-work.cmd`  | Switch to the `work` profile, then launch Claude   |
| `list.cmd`    | List profiles and show which one is active         |

### From a terminal

```powershell
.\claude-switch.ps1 <name>            # switch to <name>, then launch Claude
.\claude-switch.ps1 -List             # list profiles / show the active one
.\claude-switch.ps1 <name> -NoLaunch  # switch only, don't launch
.\claude-switch.ps1 -Setup            # (maintenance) link shared infra into every profile
```

- Switching to an **unknown name** creates a new empty profile — just log in with the other
  account after Claude launches.
- Profile names must be **1–64 characters** of letters, digits, `.`, `-`, or `_`
  (no spaces or path separators).

To add per-profile launchers, copy `2-work.cmd` and change the profile name passed to the
script.

---

## How it works

### Layout

```
Live (active)   ...\LocalCache\Roaming\Claude                         (REAL folder)
Inactive        ...\LocalCache\Roaming\ClaudeProfiles\<name>
Shared infra    ...\LocalCache\Roaming\ClaudeShared\<vm_bundles|claude-code|claude-code-vm>
Active marker   ...\LocalCache\Roaming\ClaudeActiveProfile.txt
```

### Switching (move-based)

1. Close Claude Desktop (abort if it won't close, so nothing moves under a lock).
2. Move the active profile from `Live` back into `ClaudeProfiles\<active>`.
3. Move the target profile from `ClaudeProfiles\<target>` into `Live`.
4. Re-link shared infra, update the active marker, and (optionally) launch Claude.

If step 3 fails partway, the previous profile is automatically **rolled back** into `Live`
so you're never left without an active profile.

### Shared infrastructure

Account-neutral, heavy folders — `vm_bundles` (~11 GB), `claude-code`, `claude-code-vm` — are
stored **once** in `ClaudeShared` and junctioned into each profile. New profiles reuse them
instead of re-provisioning, which is what used to cause the "claude update error" on a fresh
empty profile. Run `-Setup` any time to (re)link them everywhere.

### Claude Code session sync (optional)

Claude Desktop stores Claude Code sessions per desktop account under
`claude-code-sessions\<accountUuid>\<orgUuid>\local_*.json`. These **can't** be junctioned
(same atomic-write problem), so `claude-switch` syncs them with a newest-wins copy through a
canonical store each time you switch (while the app is closed).

To enable it, create `ClaudeShared\cc-sync-map.json` mapping each profile to its account and
org UUIDs:

```json
{
  "work": { "accountUuid": "xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx", "orgUuid": "yyyyyyyy-yyyy-yyyy-yyyy-yyyyyyyyyyyy" },
  "main": { "accountUuid": "aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa", "orgUuid": "bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb" }
}
```

Find the UUIDs by looking under `...\Roaming\Claude\claude-code-sessions\` while that account
is the active profile. If the file is missing or invalid, sync is simply disabled — switching
still works.

---

## Safety & robustness

- **Never deletes logins.** Switching only *moves* folders; your account data is preserved.
- **Won't run under a lock.** If Claude Desktop can't be closed, the switch aborts before
  touching any files.
- **Name validation.** Profile names are validated to prevent path traversal.
- **Rollback on failure.** A failed activation restores the previously active profile.
- **Concurrency guard.** A lock file prevents two overlapping switches from corrupting state.

---

## `examples/`

`examples/setup-shared.ps1` is the author's **personal one-time migration** (it relabels an
existing `main` account to `work` and carves out the shared store). It is **not needed for a
fresh install** — for general shared-infra linking use `claude-switch.ps1 -Setup`. It's kept
as a reference for how the shared-store restructure was done.

---

## Caveats

- Windows-only, and only for the **Store (MSIX)** build of Claude Desktop.
- Relies on Claude Desktop's internal folder layout, which may change in a future update.
- Junctions require profiles to sit on the same volume — they do, since everything lives
  under `LocalAppData`.

---

## License

[MIT](LICENSE)
