# claude-switch

**English** | [한국어](#한국어)

Switch between multiple **Claude Desktop** account profiles — one account active at a time,
no re-download of the multi-gigabyte VM bundle, and your logins preserved across switches.

Works on both **Windows** (Microsoft Store / MSIX build, via `claude-switch.ps1`) and
**macOS** (via `claude-switch.sh`). The two ports share the same move-based design; see
[macOS](#macos) for the Mac-specific instructions and how it differs from Windows.

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

## Requirements (Windows)

- Windows 10 / 11
- **Claude Desktop installed from the Microsoft Store** (MSIX package named `Claude`)
- Windows PowerShell 5.1 (ships with Windows — no install needed)

> On a Mac? Jump to [macOS](#macos) — the same tool, ported to `claude-switch.sh`.

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

## Usage (Windows)

### Quick helpers (double-click)

| File          | Action                                             |
| ------------- | -------------------------------------------------- |
| `1-main.cmd`  | Switch to the `main` profile, then launch Claude   |
| `2-work.cmd`  | Switch to the `work` profile, then launch Claude   |
| `list.cmd`    | List profiles and show which one is active         |
| `menu.cmd`    | Interactive menu: pick a profile by number, or add a new one — no need to make a `.cmd` per profile |
| `stop.cmd`    | Fully close Claude Desktop and everything it spawned — **run this before updating the app** |

> **Update Claude Desktop from the `main` profile, and run `stop.cmd` first.** Run app
> updates — and other app-level maintenance — while `main` is active (launch it with
> `1-main.cmd`), and fully close the app with `stop.cmd` before you update. See
> [Updating Claude Desktop](#updating-claude-desktop) below.

### From a terminal

```powershell
.\claude-switch.ps1 <name>            # switch to <name>, then launch Claude
.\claude-switch.ps1 -List             # list profiles / show the active one
.\claude-switch.ps1 <name> -NoLaunch  # switch only, don't launch
.\claude-switch.ps1 -Setup            # (maintenance) link shared infra into every profile
.\claude-switch.ps1 -Menu             # interactive menu: pick a profile by number, or add one
.\claude-switch.ps1 -Stop             # fully close Claude Desktop + all its children (do this before updating)
```

- Switching to an **unknown name** creates a new empty profile — just log in with the other
  account after Claude launches. `-Menu` offers an "Add new profile" option that does the same
  thing, so you don't need to create a `.cmd` file for every account.
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

### Updating Claude Desktop

**Before updating, fully close the app with `stop.cmd`** (or `claude-switch.ps1 -Stop`), and
**perform the update while the `main` profile is active** — launch it with `1-main.cmd`.

Why `stop.cmd` matters: Claude Desktop is an MSIX (Store) package, and clicking the window's X
doesn't necessarily end everything it started. It leaves **background package processes** running —
renderer / Node-utility / crashpad helpers that still carry the app's package identity — and also
**child processes** it spawned (the Claude Code CLI, the sandbox VM) that run from the junctioned
`claude-code` / `vm_bundles` folders. While any process still carries the package identity, Windows
considers the package **in use**, so an update can't replace the installed files and fails with:

```
C:\Program Files\WindowsApps\Claude_<version>_x64__...
Another program is currently using this file.
```

The half-applied update then only finalizes after a **reboot** (which is what finally kills the
leftover processes). `stop.cmd` avoids all of this by terminating the **entire Claude Desktop
process tree** — the main app, every background package process, and every child it spawned — so no
file is locked when the update runs. Detection matches each process on its own (a lingering helper
by its WindowsApps path, a junctioned CLI/VM child by its folder) rather than relying on one live
"main" process, and success is confirmed against the actual PIDs — so it can't report "closed"
while something is still holding the lock. (This is also why a normal profile switch now takes down
the whole tree: a leftover child holding a handle inside the live folder could otherwise break the
folder move.)

Keeping updates on the single designated `main` profile also keeps the heavy, account-neutral
infrastructure (`vm_bundles`, `claude-code`, `claude-code-vm`, shared across all profiles through
junctions) consistent and every account working correctly. After a major update you can re-link
the shared folders into all profiles at any time with `claude-switch.ps1 -Setup`.

**Recommended update flow:** `1-main.cmd` → do your work → `stop.cmd` → update Claude Desktop →
relaunch with `1-main.cmd`.

### Claude Code session sync (automatic)

Claude Desktop stores Claude Code sessions per desktop account under
`claude-code-sessions\<accountUuid>\<orgUuid>\local_*.json`. These **can't** be junctioned
(same atomic-write problem), so `claude-switch` syncs them with a newest-wins copy through a
canonical store each time you switch (while the app is closed).

The profile-to-account mapping lives in `ClaudeShared\cc-sync-map.json`, but you don't need to
create or edit it by hand: on every switch, `claude-switch` looks at whichever
`accountUuid\orgUuid` folder actually has the freshest session file sitting in the outgoing
profile, and self-heals the map entry for that profile if it's missing or stale — then does the
same for the incoming profile right after activating it. So **logging into a different account
under an existing profile** (which changes its `accountUuid`) fixes the mapping automatically on
your very next switch — no manual UUID lookup needed.

The file still looks like this if you want to inspect or hand-edit it (e.g. to disambiguate a
profile where you've logged into more than one account over time — the heuristic picks whichever
account has the most recently modified session file):

```json
{
  "work": { "accountUuid": "xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx", "orgUuid": "yyyyyyyy-yyyy-yyyy-yyyy-yyyyyyyyyyyy", "email": "" },
  "main": { "accountUuid": "aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa", "orgUuid": "bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb", "email": "" }
}
```

If the file is missing, sync starts out disabled for profiles with no entry yet and fills itself
in as you switch. `email` is a free-text label for your own reference — it isn't read by the
script.

---

## macOS

The macOS port is `claude-switch.sh` (zsh). It mirrors the Windows tool's move-based design, so
everything under [How it works](#how-it-works) applies — only the platform mechanics differ.

### Requirements (macOS)

- macOS with **Claude Desktop** installed at `/Applications/Claude.app`
  (bundle id `com.anthropic.claudefordesktop`)
- zsh (the default macOS shell since Catalina) and the built-in `plutil` / `awk` / `pgrep`
  — no extra install needed

### Install

```bash
git clone https://github.com/lpaiu-cs/claude-switch.git
cd claude-switch
chmod +x claude-switch.sh *.command    # once, so the double-click launchers are runnable
```

As on Windows, the first run automatically labels your current install `main`.

> **Run it from Terminal (or the Finder launchers) — never from a shell *inside* Claude
> Desktop.** Switching/stopping tears down the whole Claude process tree; if it were launched
> from Claude's own embedded terminal that would kill the session running it. The script detects
> this case and refuses, but the clean way is a normal Terminal window.

### Quick helpers (double-click in Finder)

| File              | Action                                                              |
| ----------------- | ------------------------------------------------------------------- |
| `1-main.command`  | Switch to the `main` profile, then launch Claude                    |
| `2-work.command`  | Switch to the `work` profile, then launch Claude                    |
| `list.command`    | List profiles and show which one is active                          |
| `menu.command`    | Interactive menu: pick a profile by number, or add a new one        |
| `stop.command`    | Fully close Claude Desktop and everything it spawned — **run this before updating the app** |

> The first double-click of a `.command` may be blocked by Gatekeeper (“unidentified
> developer”). Right-click → **Open** once to approve it, or run the `.sh` from Terminal.

### From a terminal

```bash
./claude-switch.sh <name>            # switch to <name>, then launch Claude
./claude-switch.sh --list            # list profiles / show the active one
./claude-switch.sh <name> --no-launch # switch only, don't launch
./claude-switch.sh --setup           # (maintenance) link shared infra into every profile
./claude-switch.sh --menu            # interactive menu: pick a profile by number, or add one
./claude-switch.sh --stop            # fully close Claude Desktop + all its children (before updating)
```

Profile-name rules and the "unknown name = new empty profile" behavior are identical to Windows.

### Layout (macOS)

```
Live (active)   ~/Library/Application Support/Claude                          (REAL folder)
Inactive        ~/Library/Application Support/ClaudeProfiles/<name>
Shared infra    ~/Library/Application Support/ClaudeShared/<vm_bundles|claude-code|claude-code-vm>
Active marker   ~/Library/Application Support/ClaudeActiveProfile.txt
```

### How macOS differs from Windows

- **No MSIX junction, no double-junction trap.** On macOS `~/Library/Application Support/Claude`
  is a plain real folder, and a *single* symlink does not break Claude's atomic writes the way a
  doubled Windows junction does. The move-based design is kept anyway (it's proven and safe), and
  shared infra is linked in with ordinary **symlinks** (`ln -s`) instead of junctions.
- **Shared store is seeded on the first switch.** When you switch *away* from a profile, its heavy
  account-neutral folders (`vm_bundles` ≈ 6 GB, `claude-code`, `claude-code-vm`) are moved into
  `ClaudeShared` once and symlinked back, so the profile you switch *to* reuses them instead of
  re-downloading. Run `--setup` any time to (re)link them everywhere.
- **Process handling.** `--stop` closes the whole Claude Desktop tree — the app, its Electron
  helpers, and every child it spawned (the Claude Code CLI, its MCP servers, the sandbox VM),
  matched by the app path and the live `--user-data-dir`. Your own shell and its ancestors are
  never targeted, and the script refuses to run switch/stop from *inside* Claude Desktop.
- **Updating Claude Desktop.** Fully quit with `stop.command` (or `--stop`) before updating, and
  do updates from the `main` profile — same rationale as Windows, so the app's own files and the
  shared infrastructure stay consistent. **Recommended flow:** `1-main.command` → work →
  `stop.command` → update → relaunch with `1-main.command`.
- **Claude Code session sync** works exactly as described above; the map lives at
  `~/Library/Application Support/ClaudeShared/cc-sync-map.json`.
- **Session *content* is synced too.** On macOS the desktop keeps each session's actual data —
  `outputs/`, `uploads/`, the audit log, the per-session config — account-keyed under
  `local-agent-mode-sessions/<accountUuid>/<orgUuid>/local_<id>/`. Syncing only the index (as on
  Windows) would make a switched-to account list the session but open it empty. So each switch
  also unions the session content through `ClaudeShared/lam-sessions-canonical` (per-file
  newest-wins via `rsync`), and rewrites the absolute account-scoped paths embedded in the
  session JSONs to the incoming account's UUIDs so the sessions actually open. Caches
  (`rpm/`, `cowork-*-cache.json`) are skipped — the app regenerates them. Note this store grows
  with your sessions' outputs/uploads; prune old sessions in the app if it gets large.

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

- Windows requires the **Store (MSIX)** build of Claude Desktop; macOS requires the standard
  `/Applications/Claude.app` build.
- Relies on Claude Desktop's internal folder layout, which may change in a future update.
- Moves and junctions/symlinks require profiles to sit on the same volume — they do, since
  everything lives under `LocalAppData` (Windows) or `~/Library/Application Support` (macOS).
- On macOS, run it from Terminal or the Finder launchers, not from a shell inside Claude Desktop.

---

## License

[MIT](LICENSE)

---

## 한국어

[English](#claude-switch)

여러 **Claude Desktop** 계정 프로필을 전환하는 도구입니다 — 한 번에 하나의 계정만 활성화되고,
수 기가바이트짜리 VM 번들을 다시 내려받지 않으며, 전환해도 로그인이 유지됩니다.

**Windows**(Microsoft Store / MSIX, `claude-switch.ps1`)와 **macOS**(`claude-switch.sh`)에서 모두
동작합니다. 두 포트는 동일한 이동 기반 설계를 공유합니다 — Mac 전용 사용법과 차이점은
[macOS](#macos-1)를 참고하세요.

> 비공식 커뮤니티 도구이며 Anthropic과 제휴하거나 승인받은 것이 아닙니다. Claude Desktop의 로컬
> 데이터 폴더(문서화되지 않았고 앱 업데이트로 바뀔 수 있음)를 다룹니다. 사용에 따른 책임은
> 사용자에게 있습니다.

### 왜 필요한가

Claude Desktop(Store 버전)은 계정 데이터를 전부 하나의 폴더에 저장하고, Windows는 이를 MSIX
정션(junction)으로 노출합니다:

```
%APPDATA%\Claude   ->   %LOCALAPPDATA%\Packages\<PackageFamilyName>\LocalCache\Roaming\Claude
```

두 계정을 나란히 두는 기본 기능은 없습니다. 흔히 떠올리는 방법 — 그 `Claude` 폴더 *자체*를
프로필로 향하는 정션으로 만드는 것 — 은 **앱을 망가뜨립니다**. 데이터가 정션을 *두 번* 거쳐
도달하게 되고, Claude의 원자적 쓰기(`임시 파일 작성 -> 이름 변경`)가 **새 파일**에 대해
`ENOENT`로 실패합니다(예: `git-worktrees.json`). 이미 데이터가 있는 프로필은 우연히
실행되지만(기존 파일 덮어쓰기라서), 비어 있는 새 프로필은 첫 실행에서 크래시가 납니다.

**claude-switch는 이중 정션을 아예 피합니다.** 활성 `Claude` 폴더는 항상 **실제 폴더** — 일반
설치와 똑같이 정션 하나뿐 — 로 유지됩니다. 계정 전환은 활성 프로필을 저장소로 *옮겨내고* 대상
프로필을 *옮겨 넣는* 방식입니다. 같은 볼륨 내 이동은 즉시 처리되는 이름 변경이라 전환이 빠르고
안전합니다.

### 요구 사항 (Windows)

- Windows 10 / 11
- **Microsoft Store에서 설치한 Claude Desktop** (MSIX 패키지 이름 `Claude`)
- Windows PowerShell 5.1 (Windows 기본 제공 — 별도 설치 불필요)

> Mac 사용자라면 [macOS](#macos-1) 섹션으로 이동하세요 — 같은 도구를 `claude-switch.sh`로 포팅했습니다.

### 설치

1. 이 저장소를 아무 곳에나 내려받거나 클론합니다(파일들은 같은 폴더에 함께 두세요):
   ```
   git clone https://github.com/lpaiu-cs/claude-switch.git
   ```
2. 끝입니다. `.cmd` 헬퍼를 더블클릭하거나 터미널에서 `claude-switch.ps1`을 실행하세요.

처음 실행하면 현재 설치본이 자동으로 `main`으로 이름 붙고 첫 번째 프로필이 됩니다.

### 사용법

#### 빠른 헬퍼 (더블클릭)

| 파일          | 동작                                       |
| ------------- | ------------------------------------------ |
| `1-main.cmd`  | `main` 프로필로 전환 후 Claude 실행        |
| `2-work.cmd`  | `work` 프로필로 전환 후 Claude 실행        |
| `list.cmd`    | 프로필 목록과 현재 활성 프로필 표시        |
| `menu.cmd`    | 번호로 프로필을 고르거나 새로 추가하는 대화형 메뉴 — 프로필마다 `.cmd`를 만들 필요 없음 |
| `stop.cmd`    | Claude Desktop과 그것이 띄운 모든 프로세스를 완전히 종료 — **앱 업데이트 전에 실행** |

> **Claude Desktop 업데이트는 `main` 프로필에서, 먼저 `stop.cmd`로 앱을 완전히 종료한 뒤에
> 하세요.** 앱 업데이트 및 기타 앱 수준 유지보수는 `main`이 활성인 상태(`1-main.cmd`로 실행)에서
> 수행하고, 업데이트 직전에 `stop.cmd`로 앱을 완전히 닫으세요. 아래
> [Claude Desktop 업데이트하기](#claude-desktop-업데이트하기) 참고.

#### 터미널에서 (Windows)

```powershell
.\claude-switch.ps1 <이름>            # <이름>으로 전환 후 Claude 실행
.\claude-switch.ps1 -List             # 프로필 목록 / 활성 프로필 표시
.\claude-switch.ps1 <이름> -NoLaunch  # 전환만 하고 실행하지 않음
.\claude-switch.ps1 -Setup            # (유지보수) 공유 인프라를 모든 프로필에 연결
.\claude-switch.ps1 -Menu             # 대화형 메뉴: 번호로 프로필 선택 또는 새로 추가
.\claude-switch.ps1 -Stop             # Claude Desktop과 모든 자식 프로세스를 완전히 종료 (업데이트 전에 실행)
```

- **없는 이름**으로 전환하면 빈 프로필이 새로 만들어집니다 — Claude 실행 후 다른 계정으로
  로그인하면 됩니다. `-Menu`의 "Add new profile"도 똑같은 동작이라, 계정마다 `.cmd` 파일을
  따로 만들 필요가 없습니다.
- 프로필 이름은 **1~64자**의 영문자, 숫자, `.`, `-`, `_` 만 사용할 수 있습니다(공백·경로
  구분자 불가).

프로필별 실행기를 추가하려면 `2-work.cmd`를 복사해 스크립트에 넘기는 프로필 이름만 바꾸면 됩니다.

### 동작 원리

#### 레이아웃

```
활성 (Live)     ...\LocalCache\Roaming\Claude                         (실제 폴더)
비활성          ...\LocalCache\Roaming\ClaudeProfiles\<이름>
공유 인프라     ...\LocalCache\Roaming\ClaudeShared\<vm_bundles|claude-code|claude-code-vm>
활성 표식       ...\LocalCache\Roaming\ClaudeActiveProfile.txt
```

#### 전환 (이동 기반)

1. Claude Desktop을 종료합니다(닫히지 않으면 중단해서, 잠긴 상태로 아무것도 옮기지 않습니다).
2. 활성 프로필을 `Live`에서 `ClaudeProfiles\<active>`로 옮깁니다.
3. 대상 프로필을 `ClaudeProfiles\<target>`에서 `Live`로 옮깁니다.
4. 공유 인프라를 다시 연결하고, 활성 표식을 갱신한 뒤, (옵션) Claude를 실행합니다.

3단계가 도중에 실패하면 이전 프로필이 자동으로 `Live`로 **롤백**되어, 활성 프로필이 없는
상태로 남지 않습니다.

#### 공유 인프라

계정과 무관한 무거운 폴더 — `vm_bundles`(약 11 GB), `claude-code`, `claude-code-vm` — 는
`ClaudeShared`에 **한 번만** 저장되고 각 프로필에 정션으로 연결됩니다. 새 프로필은 이를 다시
프로비저닝하지 않고 재사용하며, 이것이 예전에 빈 새 프로필에서 "claude update error"를 일으키던
원인이었습니다. 언제든 `-Setup`으로 모든 곳에 다시 연결할 수 있습니다.

#### Claude Desktop 업데이트하기

**업데이트 전에 `stop.cmd`(또는 `claude-switch.ps1 -Stop`)로 앱을 완전히 종료하고**,
**업데이트는 `main` 프로필이 활성인 상태에서 수행하세요** — `1-main.cmd`로 실행합니다.

`stop.cmd`가 필요한 이유: Claude Desktop은 MSIX(Store) 패키지인데, 창의 X 버튼을 눌러도 앱이
띄운 것들이 전부 종료되지는 않습니다. **패키지 정체성(package identity)을 그대로 지닌 백그라운드
프로세스**(렌더러 / Node 유틸리티 / crashpad 헬퍼)가 남고, 앱이 띄운 **자식 프로세스**(Claude
Code CLI, 샌드박스 VM — 정션된 `claude-code` / `vm_bundles` 폴더에서 실행 파일을 로드)도 창을
닫아도 살아남습니다. 패키지 정체성을 가진 프로세스가 하나라도 살아 있으면 Windows는 패키지를
**사용 중**으로 판단해, 업데이트가 설치 파일을 교체하지 못하고 다음과 같이 실패합니다:

```
C:\Program Files\WindowsApps\Claude_<버전>_x64__...
Another program is currently using this file.
```

이렇게 반쯤 적용된 업데이트는 **재부팅**해야(남아 있던 프로세스가 그제서야 종료되면서)
마무리됩니다. `stop.cmd`는 **Claude Desktop 프로세스 트리 전체** — 메인 앱, 모든 백그라운드 패키지
프로세스, 앱이 띄운 모든 자식 — 를 종료해서 이 문제를 원천 차단하므로, 업데이트가 돌 때 잠긴
파일이 없습니다. 탐지는 하나의 살아있는 "메인" 프로세스에 의존하지 않고 프로세스마다 자기 자신으로
판정하며(남은 헬퍼는 WindowsApps 경로로, 정션된 CLI/VM 자식은 자기 폴더로), 성공 여부도 실제
PID로 확인합니다 — 그래서 무언가 아직 잠금을 쥐고 있는데 "닫힘"으로 오보하지 않습니다. (일반 프로필
전환도 이제 트리 전체를 종료합니다. 살아남은 자식이 활성 폴더 안에 핸들을 걸고 있으면 폴더 이동이
깨질 수 있기 때문입니다.)

지정된 단일 프로필(`main`)에서 업데이트를 유지하면 계정과 무관한 무거운 인프라(`vm_bundles`,
`claude-code`, `claude-code-vm` — 정션으로 모든 프로필에 공유됨)도 일관되게 유지되고 모든 계정이
올바르게 동작합니다. 대규모 업데이트 후에는 언제든 `claude-switch.ps1 -Setup`으로 공유 폴더를
모든 프로필에 다시 연결할 수 있습니다.

**권장 업데이트 순서:** `1-main.cmd` → 작업 → `stop.cmd` → Claude Desktop 업데이트 →
`1-main.cmd`로 다시 실행.

#### Claude Code 세션 동기화 (자동)

Claude Desktop은 Claude Code 세션을 데스크톱 계정별로
`claude-code-sessions\<accountUuid>\<orgUuid>\local_*.json` 아래에 저장합니다. 이 파일들은
정션으로 연결할 수 **없어서**(같은 원자적 쓰기 문제), `claude-switch`는 전환할 때마다(앱이 닫힌
상태에서) 정규 저장소를 거쳐 "최신 우선" 복사로 동기화합니다.

프로필 ↔ 계정 매핑은 `ClaudeShared\cc-sync-map.json`에 저장되지만, 직접 만들거나 편집할 필요는
없습니다: 전환할 때마다 나가는 프로필 쪽에서 실제로 가장 최근에 수정된 세션 파일이 들어 있는
`accountUuid\orgUuid` 폴더를 찾아, 매핑이 없거나 예전 값이면 자동으로 갱신합니다(들어오는
프로필이 활성화된 직후에도 동일하게 한 번 더 확인합니다). 그래서 **기존 프로필에 다른 계정으로
로그인**해서 `accountUuid`가 바뀌어도, 다음 전환 때 매핑이 알아서 고쳐집니다 — UUID를 직접 찾을
필요가 없습니다.

파일 내용을 확인하거나 직접 손보고 싶다면(예: 한 프로필에서 여러 계정을 번갈아 로그인해서
모호해진 경우 — 자동 감지는 가장 최근에 파일이 수정된 계정을 고릅니다) 형식은 여전히 이렇습니다:

```json
{
  "work": { "accountUuid": "xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx", "orgUuid": "yyyyyyyy-yyyy-yyyy-yyyy-yyyyyyyyyyyy", "email": "" },
  "main": { "accountUuid": "aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa", "orgUuid": "bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb", "email": "" }
}
```

파일이 없으면 아직 매핑이 없는 프로필은 동기화가 꺼진 채로 시작하고, 전환할 때마다 스스로
채워집니다. `email`은 참고용 메모일 뿐 스크립트 로직에서는 쓰지 않습니다.

### macOS

macOS 포트는 `claude-switch.sh`(zsh)입니다. Windows 도구의 이동 기반 설계를 그대로 따르므로
[동작 원리](#동작-원리)의 내용이 모두 적용되고, 플랫폼별 세부 구현만 다릅니다.

#### 요구 사항 (macOS)

- `/Applications/Claude.app`에 설치된 **Claude Desktop** (bundle id `com.anthropic.claudefordesktop`)
- zsh(Catalina 이후 macOS 기본 셸)와 기본 제공 `plutil` / `awk` / `pgrep` — 추가 설치 불필요

#### 설치

```bash
git clone https://github.com/lpaiu-cs/claude-switch.git
cd claude-switch
chmod +x claude-switch.sh *.command    # 더블클릭 런처를 실행 가능하게 (최초 1회)
```

Windows와 마찬가지로 처음 실행하면 현재 설치본이 자동으로 `main`으로 이름 붙습니다.

> **터미널(또는 Finder 런처)에서 실행하세요 — Claude Desktop *내부*의 셸에서는 실행하지 마세요.**
> 전환/종료는 Claude 프로세스 트리 전체를 내리므로, Claude 내장 터미널에서 실행하면 그 세션 자체가
> 죽습니다. 스크립트가 이 상황을 감지해 거부하지만, 일반 Terminal 창에서 실행하는 것이 정석입니다.

#### 빠른 헬퍼 (Finder에서 더블클릭)

| 파일              | 동작                                              |
| ----------------- | ------------------------------------------------- |
| `1-main.command`  | `main` 프로필로 전환 후 Claude 실행               |
| `2-work.command`  | `work` 프로필로 전환 후 Claude 실행               |
| `list.command`    | 프로필 목록과 현재 활성 프로필 표시               |
| `menu.command`    | 번호로 프로필을 고르거나 새로 추가하는 대화형 메뉴 |
| `stop.command`    | Claude Desktop과 그것이 띄운 모든 프로세스를 완전히 종료 — **앱 업데이트 전에 실행** |

> `.command`을 처음 더블클릭하면 Gatekeeper가 막을 수 있습니다("확인되지 않은 개발자").
> 한 번 우클릭 → **열기**로 승인하거나, 터미널에서 `.sh`를 직접 실행하세요.

#### 터미널에서 (macOS)

```bash
./claude-switch.sh <이름>            # <이름>으로 전환 후 Claude 실행
./claude-switch.sh --list            # 프로필 목록 / 활성 프로필 표시
./claude-switch.sh <이름> --no-launch # 전환만 하고 실행하지 않음
./claude-switch.sh --setup           # (유지보수) 공유 인프라를 모든 프로필에 연결
./claude-switch.sh --menu            # 대화형 메뉴: 번호로 프로필 선택 또는 새로 추가
./claude-switch.sh --stop            # Claude Desktop과 모든 자식 프로세스를 완전히 종료 (업데이트 전에 실행)
```

프로필 이름 규칙과 "없는 이름 = 빈 프로필 새로 생성" 동작은 Windows와 동일합니다.

#### 레이아웃 (macOS)

```
활성 (Live)     ~/Library/Application Support/Claude                          (실제 폴더)
비활성          ~/Library/Application Support/ClaudeProfiles/<이름>
공유 인프라     ~/Library/Application Support/ClaudeShared/<vm_bundles|claude-code|claude-code-vm>
활성 표식       ~/Library/Application Support/ClaudeActiveProfile.txt
```

#### macOS가 Windows와 다른 점

- **MSIX 정션이 없어 이중 정션 함정도 없음.** macOS에서 `~/Library/Application Support/Claude`는
  평범한 실제 폴더이고, *단일* 심볼릭 링크는 Windows의 이중 정션과 달리 Claude의 원자적 쓰기를
  깨뜨리지 않습니다. 그래도 검증된 이동 기반 설계를 유지하며, 공유 인프라는 정션 대신 일반
  **심볼릭 링크**(`ln -s`)로 연결합니다.
- **공유 저장소는 첫 전환에서 seed됩니다.** 어떤 프로필에서 *빠져나갈* 때 그 프로필의 무거운
  계정-무관 폴더(`vm_bundles` 약 6 GB, `claude-code`, `claude-code-vm`)를 `ClaudeShared`로 한 번
  옮겨 심링크로 되돌리므로, *전환해 들어가는* 프로필이 재다운로드 없이 재사용합니다. 언제든
  `--setup`으로 모든 곳에 다시 연결할 수 있습니다.
- **프로세스 처리.** `--stop`은 Claude Desktop 트리 전체 — 앱, Electron 헬퍼, 그리고 앱이 띄운 모든
  자식(Claude Code CLI, MCP 서버, 샌드박스 VM) — 를 앱 경로와 활성 `--user-data-dir`로 매칭해
  종료합니다. 자신의 셸과 그 조상은 절대 대상이 되지 않으며, Claude Desktop *내부*에서의
  전환/종료 실행은 거부합니다.
- **Claude Desktop 업데이트.** 업데이트 전에 `stop.command`(또는 `--stop`)로 완전히 종료하고,
  업데이트는 `main` 프로필에서 수행하세요 — Windows와 같은 이유로 앱 파일과 공유 인프라를
  일관되게 유지합니다. **권장 순서:** `1-main.command` → 작업 → `stop.command` → 업데이트 →
  `1-main.command`로 다시 실행.
- **Claude Code 세션 동기화**는 위 설명 그대로 동작하며, 매핑 파일은
  `~/Library/Application Support/ClaudeShared/cc-sync-map.json`에 있습니다.
- **세션 *내용*도 함께 동기화됩니다.** macOS에서는 데스크톱이 각 세션의 실제 데이터 —
  `outputs/`, `uploads/`, 감사 로그, 세션별 설정 — 를
  `local-agent-mode-sessions/<accountUuid>/<orgUuid>/local_<id>/` 아래에 계정 단위로 보관합니다.
  (Windows처럼) 인덱스만 동기화하면 전환한 계정에서 세션이 목록에는 보여도 열면 비어 있게
  됩니다. 그래서 전환할 때마다 세션 내용도 `ClaudeShared/lam-sessions-canonical`을 거쳐
  union으로 동기화하고(`rsync` 파일별 최신 우선), 세션 JSON에 박혀 있는 계정 UUID 절대경로를
  들어오는 계정의 UUID로 재작성해 세션이 실제로 열리게 합니다. 캐시(`rpm/`,
  `cowork-*-cache.json`)는 앱이 재생성하므로 건너뜁니다. 이 저장소는 세션의 outputs/uploads만큼
  커지니, 많이 쌓이면 앱에서 오래된 세션을 정리하세요.

### 안전성 & 견고함

- **로그인을 삭제하지 않습니다.** 전환은 폴더를 *옮기기만* 하며 계정 데이터는 보존됩니다.
- **잠긴 상태로 실행하지 않습니다.** Claude Desktop을 닫을 수 없으면 파일을 건드리기 전에
  전환을 중단합니다.
- **이름 검증.** 경로 탈출을 막기 위해 프로필 이름을 검증합니다.
- **실패 시 롤백.** 활성화가 실패하면 직전에 활성이던 프로필을 복구합니다.
- **동시 실행 방지.** 잠금 파일로 겹치는 전환이 상태를 손상시키지 못하게 합니다.

### examples/ 폴더

`examples/setup-shared.ps1`은 제작자의 **개인용 1회성 마이그레이션**입니다(기존 `main` 계정을
`work`로 이름 바꾸고 공유 저장소를 분리). 새로 설치하는 경우에는 **필요하지 않습니다** —
일반적인 공유 인프라 연결은 `claude-switch.ps1 -Setup`을 사용하세요. 공유 저장소 재구성이 어떻게
이뤄졌는지 보여주는 참고용으로만 남겨둡니다.

### 주의 사항

- Windows는 **Store(MSIX)** 버전 Claude Desktop이, macOS는 표준 `/Applications/Claude.app`
  버전이 필요합니다.
- Claude Desktop의 내부 폴더 구조에 의존하므로 향후 업데이트로 바뀔 수 있습니다.
- 이동과 정션/심링크는 프로필이 같은 볼륨에 있어야 하는데, 모든 데이터가 `LocalAppData`(Windows)
  또는 `~/Library/Application Support`(macOS) 아래에 있으므로 이 조건은 충족됩니다.
- macOS에서는 Claude Desktop 내부 셸이 아니라 터미널 또는 Finder 런처에서 실행하세요.

### 라이선스

[MIT](LICENSE)
