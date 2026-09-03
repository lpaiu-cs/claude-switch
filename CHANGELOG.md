# Changelog

All notable changes to this project are documented here.

This project follows [Semantic Versioning](https://semver.org/spec/v2.0.0.html).
Release tags are `v<version>` (e.g. `v1.0.0`), and `claude-switch.ps1 -Version` reports the
version of the copy you have.

## [Unreleased]

### Changed

- **`claude-code` and `claude-code-vm` are no longer shared between profiles.** Claude Desktop's
  bundled Claude Code updater unpacks a release to `claude.exe.decompress.tmp` and renames it onto
  `claude.exe`; that atomic *new-file* write fails with `ENOENT` through a junction. Every download
  finished and only the rename died, so the app silently logged `Falling back to installed version`
  and kept running the last CLI that installed before the updater changed its write strategy — ten
  releases, until the API rejected a model the pinned version didn't support. Both are real
  per-profile folders now (~1.2 GB per profile). `vm_bundles` (~11 GB) stays shared; its own bundle
  downloads hit the same failure and still need finalising by hand.
- **`-Setup` converts profiles that still hold the old junctions.** The junction is dropped with
  `rmdir` (which never touches the target) and the shared content is copied in. The shared
  originals are deliberately left behind — other profiles may still point at them — so remove
  `ClaudeShared\claude-code` and `ClaudeShared\claude-code-vm` by hand once every profile is done.

### Fixed

- **`-Stop` keeps matching Claude Code children after a folder stops being shared.** Process
  detection read the same `$SharedFolders` list that drives junction creation, so un-sharing a
  folder would have stopped `Stop-ClaudeDesktop` from matching processes running out of it —
  leaving the MSIX package in use and reviving the "Another program is currently using this file"
  update failure. The two meanings now have separate lists (`$SharedFolders` for what gets
  junctioned, `$ChildHostFolders` for where our children run).

## [1.0.0] - 2026-07-31

First tagged release. Packaged so it can be downloaded and run without any developer tooling.

### Added

- **Move-based profile switching** for Claude Desktop (Microsoft Store / MSIX). The live
  `Claude` folder stays a real folder, so the app is reached through a single junction exactly
  like a normal install. This avoids the double-junction layout that breaks Claude's atomic
  writes (`write tmp -> rename`) and crashes fresh profiles with `ENOENT`.
- **Rollback on a failed switch.** If activating the target profile fails partway, the previous
  profile is moved back into place so you are never left without an active profile.
- **Shared infrastructure store.** The heavy, account-neutral folders (`vm_bundles` ~11 GB,
  `claude-code`, `claude-code-vm`) live once in `ClaudeShared` and are junctioned into every
  profile, so a new account doesn't re-download the VM bundle. Re-link any time with `-Setup`.
- **Claude Code session sharing** across profiles via a canonical store with newest-wins sync,
  plus a self-healing profile -> account/org UUID map that corrects itself on the next switch.
- **`-Stop`**: terminates the entire Claude Desktop process tree, including background MSIX
  package processes and spawned children (Claude Code CLI, Node helpers, sandbox VM). Run it
  before updating Claude Desktop to prevent the "Another program is currently using this file"
  failure, and to clear an already-stuck update without a reboot.
- **`-Menu`**: interactive numbered menu to switch profiles or add a new one, so you don't need
  a `.cmd` per account.
- **`-List`**, **`-NoLaunch`**, and profile-name validation (1-64 chars of letters, digits,
  `.`, `-`, `_`; reserved Windows device names rejected) to keep a profile name from escaping
  the store directory.
- **Cross-process lock** so two overlapping switches can't corrupt the layout, with stale-lock
  recovery after 5 minutes.
- **Automatic migration** of a legacy junction-based layout to the move-based one, and automatic
  labeling of an existing install as profile `main` on first run.
- Double-click helpers: `1-main.cmd`, `2-work.cmd`, `list.cmd`, `menu.cmd`, `stop.cmd`.
- **`시작하기.cmd`** (start-here): guided entry point for non-technical users. Confirms Claude
  Desktop is the Store build and that the archive was actually extracted (rather than run from
  inside the zip), explains what will happen, then opens the profile menu.
- **`사용설명서.md`**: Korean quickstart guide shipped in the release archive.
- **`-Version`** switch and a `$ScriptVersion` constant.
- Release packaging via `tools/build-release.ps1` and a GitHub Actions workflow that builds the
  archive and publishes the release when a `v*` tag is pushed.

[1.0.0]: https://github.com/lpaiu-cs/claude-switch/releases/tag/v1.0.0
