<div align="center">

# claude-switch

**Use more than one Claude Desktop account on Windows.**
Switch in a second, stay logged in, keep your work session.

[**English**](#quick-start) · [**한국어**](#한국어) · [Download](https://github.com/lpaiu-cs/claude-switch/releases/latest) · [Changelog](CHANGELOG.md)

</div>

```
=== claude-switch ===
Active: main

  1) main  [active]
  2) work
  N) Add new profile
  Q) Quit

Select:
```

Pick a number, press Enter. Claude reopens on that account.

> [!NOTE]
> Unofficial community tool. Not affiliated with or endorsed by Anthropic. It works on Claude
> Desktop's local data folders, which are undocumented and can change between app updates.
> Use at your own risk.

---

## Quick start

**You need:** Windows 10/11 · Claude Desktop **from the Microsoft Store** (the download from
the website won't work) · logged in at least once.

Windows PowerShell 5.1 is already on your machine — nothing to install.

### Option A — download (no developer tools)

1. Get `claude-switch-<version>.zip` from the [latest release](https://github.com/lpaiu-cs/claude-switch/releases/latest).
2. Right-click the zip → **Extract All**. Running it from inside the zip does not work.
3. Double-click **`시작하기.cmd`**.

If Windows says *"Windows protected your PC"*, click **More info → Run anyway**. That prompt
shows up for any script downloaded from the internet.

The zip also contains **`사용설명서.md`**, a plain-language Korean walkthrough for people who
don't use a terminal.

### Option B — clone

```powershell
git clone https://github.com/lpaiu-cs/claude-switch.git
cd claude-switch
.\claude-switch.ps1 -Menu
```

Either way, **keep the files together in one folder** — each `.cmd` finds `claude-switch.ps1`
next to itself.

On the first run, your current install is labelled `main` and becomes your first profile.
Nothing is moved or deleted.

### Add a second account

Run the menu, press **`N`**, type a name (`work`, `personal`, …), then log in with the other
account when Claude opens. That's it.

Names allow **1–64** characters: letters, digits, `.`, `-`, `_`. No spaces or slashes.

---

## Everyday use

Double-click any of these:

| File | What it does |
| --- | --- |
| **`시작하기.cmd`** | **Start here.** Checks your setup, explains the options, opens the menu |
| `menu.cmd` | The menu on its own — pick a profile by number, or add one |
| `1-main.cmd` | Jump straight to `main`, then launch Claude |
| `2-work.cmd` | Jump straight to `work`, then launch Claude |
| `list.cmd` | Show profiles and which one is active |
| `stop.cmd` | Fully close Claude and everything it started — **run before updating the app** |

To add a launcher for another profile, copy `2-work.cmd` and change the name inside.

<details>
<summary><b>Command line reference</b></summary>

```powershell
.\claude-switch.ps1 <name>            # switch to <name>, then launch Claude
.\claude-switch.ps1 <name> -NoLaunch  # switch only
.\claude-switch.ps1 -Menu             # interactive numbered menu
.\claude-switch.ps1 -List             # list profiles / show the active one
.\claude-switch.ps1 -Stop             # fully close Claude + all its children
.\claude-switch.ps1 -Setup            # (maintenance) re-link shared folders into every profile
.\claude-switch.ps1 -Version          # print this copy's version
```

Switching to a name that doesn't exist creates an empty profile — the same thing `N` does in
the menu.

</details>

---

## ⚠️ Before you update Claude Desktop

Closing the window with **X** does not fully close Claude. If you update while leftovers are
still running, the update fails and normally needs a **reboot** to unstick:

```
C:\Program Files\WindowsApps\Claude_<version>_x64__...
Another program is currently using this file.
```

**Do this instead:**

```
1-main.cmd  →  (use Claude)  →  stop.cmd  →  update  →  1-main.cmd
```

Two rules: **update from the `main` profile**, and **run `stop.cmd` first**.

Already stuck? You don't need to reboot — run `stop.cmd` and relaunch. Details in
[Troubleshooting](#troubleshooting).

<details>
<summary><b>Why X isn't enough</b></summary>

Claude Desktop is an MSIX (Store) package. Closing the window leaves two kinds of survivors:

- **Background package processes** — renderer / Node-utility / crashpad helpers that still carry
  the app's *package identity*.
- **Child processes** it spawned — the Claude Code CLI and the sandbox VM, running out of the
  junctioned `claude-code` / `vm_bundles` folders.

While *any* process carries the package identity, Windows treats the package as **in use**, so
an update can't replace the installed files. The half-applied update only finalises after a
reboot, because that's what finally kills the leftovers.

`stop.cmd` takes down the **whole process tree** instead: the main app, every background package
process, and every child. Each process is matched on its own evidence — a lingering helper by its
`WindowsApps` path, a junctioned CLI/VM child by its folder — rather than trusting one live "main"
process, and the result is confirmed against the actual PIDs. So it can't report "closed" while
something still holds the lock.

This is also why a normal profile switch now stops the whole tree: a leftover child holding a
handle inside the live folder would break the folder move.

Updating from `main` keeps the shared, account-neutral folders (`vm_bundles`, `claude-code`,
`claude-code-vm`) consistent for every profile. After a big update you can re-link them anywhere
with `claude-switch.ps1 -Setup`.

</details>

---

## Troubleshooting

| Symptom | Fix |
| --- | --- |
| Switch fails with an error | Claude didn't close. Run `stop.cmd`, then retry. |
| "Claude package not found" | You have the website build, not the Store one. Install Claude from the Microsoft Store, log in once, retry. |
| Window flashes and vanishes | You ran it from inside the zip. Extract it to a folder first. |
| `another claude-switch operation is in progress` | A previous run died mid-way. Wait 5 minutes and the stale lock clears itself. |
| Update fails: `Another program is currently using this file` | See below. |
| Not sure what's going on | Run `list.cmd` — it shows every profile and the active one. |

<details>
<summary><b>Recovering a stuck update (no reboot)</b></summary>

Updating straight from the in-app prompt without `stop.cmd` can leave the update **stuck**: the
new version registers, but the relaunched window freezes and Windows closes it ("Application
Hang"), and/or every later launch dies with the `Another program is currently using this file`
dialog.

Same root cause as above, on the app's own update path: the updater's quit-for-update doesn't
take the whole tree down either — it logs `beforeQuitForUpdate` and never reaches the
quit-cleanup steps — so **old-version processes survive the swap**. They can sit for days holding
files under `WindowsApps\Deleted\Claude_<oldversion>...`, and every launch then resumes the
pending deployment and races it, reproducing the dialog until they die. That's why only a reboot
seemed to help.

Upstream reports: [anthropics/claude-code#76357](https://github.com/anthropics/claude-code/issues/76357),
[#75337](https://github.com/anthropics/claude-code/issues/75337).

A reboot isn't actually needed:

1. **Run `stop.cmd`.** It matches the stale old-version processes too — their image path still
   matches `WindowsApps...Claude` even after the package folder moved under `Deleted` — so it
   kills exactly the lock holders a reboot would.
2. **If you use the Claude in Chrome extension, close Chrome too.** Per
   [#75337](https://github.com/anthropics/claude-code/issues/75337), its native-messaging host
   carries the package identity and is respawned by Chrome, not by Claude.
3. **Launch Claude again** (`1-main.cmd`). Still complaining? From an elevated PowerShell run
   `Stop-Service CoworkVMService` and retry. Last resort — updates normally handle that service
   themselves.

</details>

---

## How it works

### Where things live

```
Active profile   ...\LocalCache\Roaming\Claude                    ← a REAL folder
Inactive         ...\LocalCache\Roaming\ClaudeProfiles\<name>
Shared folders   ...\LocalCache\Roaming\ClaudeShared\<vm_bundles|claude-code|claude-code-vm>
Active marker    ...\LocalCache\Roaming\ClaudeActiveProfile.txt
```

### Switching is a move, not a link

1. Close Claude Desktop. If it won't close, abort — nothing gets moved under a lock.
2. Move the active profile out to `ClaudeProfiles\<active>`.
3. Move the target profile in from `ClaudeProfiles\<target>`.
4. Re-link the shared folders, update the marker, launch Claude.

Same-volume moves are instant renames, so a switch takes about a second. If step 3 fails partway,
step 2 is **rolled back** — you're never left without an active profile.

<details>
<summary><b>Why not just make <code>Claude</code> a junction? (it breaks the app)</b></summary>

Claude Desktop keeps all of an account's data under one folder that Windows already exposes
through an MSIX junction:

```
%APPDATA%\Claude   ->   %LOCALAPPDATA%\Packages\<PackageFamilyName>\LocalCache\Roaming\Claude
```

The obvious trick is to make that `Claude` folder *itself* a junction pointing at a per-account
profile. The data is then reached through **two** junctions, and Claude's atomic writes
(`write tmp -> rename`) of **new** files fail with `ENOENT` — for example `git-worktrees.json`.

A profile that already has data happens to launch, because those files exist and the write is an
overwrite. A fresh, empty profile crashes on first run.

claude-switch avoids the double junction entirely: the live `Claude` folder is always a real
folder, exactly like a normal install — one junction, the app's own. That's why switching moves
folders instead of re-pointing a link.

</details>

### Shared folders, stored once

The heavy account-neutral folders — `vm_bundles` (~11 GB), `claude-code`, `claude-code-vm` — live
**once** in `ClaudeShared` and are junctioned into every profile. A new account reuses them
instead of re-provisioning, which is what used to cause the "claude update error" on a fresh
profile. Re-link them any time with `-Setup`.

### Claude Code sessions sync themselves

Claude Desktop stores Claude Code sessions per account under
`claude-code-sessions\<accountUuid>\<orgUuid>\local_*.json`. These **can't** be junctioned — same
atomic-write problem — so claude-switch syncs them newest-wins through a canonical store on every
switch, while the app is closed.

You don't need to configure anything. The profile-to-account map self-heals: on each switch,
claude-switch finds whichever `accountUuid\orgUuid` folder has the freshest session file in the
outgoing profile and repairs that profile's entry if it's missing or stale, then does the same for
the incoming profile. So **logging into a different account under an existing profile** fixes
itself on your next switch — no UUID hunting.

<details>
<summary><b>The map file, if you want to inspect or edit it</b></summary>

It lives at `ClaudeShared\cc-sync-map.json`:

```json
{
  "work": { "accountUuid": "xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx", "orgUuid": "yyyyyyyy-yyyy-yyyy-yyyy-yyyyyyyyyyyy", "email": "" },
  "main": { "accountUuid": "aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa", "orgUuid": "bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb", "email": "" }
}
```

Hand-editing is only useful to disambiguate a profile where you've logged into more than one
account over time — the automatic pick is whichever account has the most recently modified session
file.

If the file is missing, sync starts out disabled for profiles with no entry and fills itself in as
you switch. `email` is a free-text label for you; the script never reads it.

</details>

---

## Safety

- **Never deletes logins.** Switching only *moves* folders. Your account data is preserved.
- **Won't run under a lock.** If Claude can't be closed, the switch aborts before touching files.
- **Rollback on failure.** A failed activation restores the previously active profile.
- **Name validation.** Profile names are validated so they can't escape the store directory.
- **Concurrency guard.** A lock file stops two overlapping switches from corrupting state, and
  clears itself after 5 minutes if a run dies.

## Caveats

- Windows only, and only the **Store (MSIX)** build of Claude Desktop.
- Relies on Claude Desktop's internal folder layout, which a future update may change.
- One account active at a time. This tool makes swapping fast; it doesn't run two at once.
- Junctions need profiles on the same volume — they are, since everything sits under
  `LocalAppData`.

---

<details>
<summary><b>For maintainers — cutting a release</b></summary>

Versions follow [SemVer](https://semver.org/). `$ScriptVersion` in `claude-switch.ps1` is the
single source of truth, and the tag must match it — the build fails otherwise.

1. Bump `$ScriptVersion` and add the matching `CHANGELOG.md` entry.
2. Commit, then tag and push:
   ```powershell
   git tag -a v1.0.0 -m "claude-switch v1.0.0"
   git push origin v1.0.0
   ```
3. The `Release` workflow builds `dist/claude-switch-<version>.zip`, smoke-tests `-Version`,
   verifies the archive contents, and publishes the GitHub Release with the zip and its
   `.sha256`.

Build locally without tagging:

```powershell
.\tools\build-release.ps1
```

Running the workflow manually (`workflow_dispatch`) builds and uploads the archive as a CI
artifact without publishing — useful for inspecting the bundle before tagging.

The archive ships only what an end user needs: `claude-switch.ps1`, the `.cmd` helpers,
`시작하기.cmd`, `사용설명서.md`, `README.md`, `CHANGELOG.md`, `LICENSE`. `examples/`, `tools/`,
and `.github/` are excluded.

**`examples/setup-shared.ps1`** is the author's personal one-time migration — it relabels an
existing `main` account to `work` and carves out the shared store. It is **not needed for a fresh
install**; use `claude-switch.ps1 -Setup` for normal shared-folder linking. Kept as a reference
for how the restructure was done.

</details>

## License

[MIT](LICENSE)

<br>

---

<div align="center">

# 한국어

[English](#claude-switch)

**Windows에서 Claude Desktop 계정을 여러 개 쓰는 도구입니다.**
1초 만에 전환되고, 로그인이 유지되고, 작업 세션이 유지됩니다.

</div>

```
=== claude-switch ===
Active: main

  1) main  [active]
  2) work
  N) Add new profile
  Q) Quit

Select:
```

번호를 고르고 Enter를 누르면 그 계정으로 Claude가 다시 열립니다.

> [!NOTE]
> 비공식 커뮤니티 도구이며 Anthropic과 제휴하거나 승인받은 것이 아닙니다. 문서화되지 않은
> Claude Desktop의 로컬 데이터 폴더를 다루며, 이 구조는 앱 업데이트로 바뀔 수 있습니다.
> 사용에 따른 책임은 사용자에게 있습니다.

---

## 빠르게 시작하기

**필요한 것:** Windows 10/11 · **Microsoft Store에서 설치한** Claude Desktop(홈페이지에서 받은
버전은 동작하지 않습니다) · 최소 한 번 로그인한 상태.

Windows PowerShell 5.1은 이미 컴퓨터에 있습니다. 설치할 것은 없습니다.

### 방법 A — 내려받기 (개발 도구 필요 없음)

1. [최신 릴리스](https://github.com/lpaiu-cs/claude-switch/releases/latest)에서
   `claude-switch-<버전>.zip` 을 받습니다.
2. zip에 마우스 오른쪽 클릭 → **압축 풀기**. zip 안에서 바로 실행하면 동작하지 않습니다.
3. **`시작하기.cmd`** 를 두 번 클릭합니다.

*"Windows가 PC를 보호했습니다"* 창이 뜨면 **추가 정보 → 실행**을 누르세요. 인터넷에서 받은
스크립트에는 항상 나오는 안내입니다.

압축 안에는 터미널을 쓰지 않는 분을 위한 단계별 안내서 **`사용설명서.md`** 도 함께 들어 있습니다.

### 방법 B — clone

```powershell
git clone https://github.com/lpaiu-cs/claude-switch.git
cd claude-switch
.\claude-switch.ps1 -Menu
```

어느 방법이든 **파일은 같은 폴더에 함께 두세요.** 각 `.cmd` 는 자기 옆에 있는
`claude-switch.ps1` 을 찾습니다.

처음 실행하면 지금 설치본이 `main` 이라는 이름을 받고 첫 번째 프로필이 됩니다. 옮기거나 지우는
것은 없습니다.

### 두 번째 계정 추가하기

메뉴에서 **`N`** 을 누르고 이름(`work`, `personal` 등)을 입력한 뒤, Claude가 열리면 다른 계정으로
로그인하세요. 끝입니다.

이름은 **1~64자**의 영문자, 숫자, `.`, `-`, `_` 만 됩니다. 한글·공백·경로 구분자는 안 됩니다.

---

## 평소 사용법

아래 파일을 두 번 클릭하면 됩니다.

| 파일 | 하는 일 |
| --- | --- |
| **`시작하기.cmd`** | **여기서 시작.** 환경을 확인하고 사용법을 안내한 뒤 메뉴를 띄웁니다 |
| `menu.cmd` | 메뉴만 띄우기 — 번호로 프로필 선택 또는 추가 |
| `1-main.cmd` | `main` 으로 바로 전환하고 Claude 실행 |
| `2-work.cmd` | `work` 으로 바로 전환하고 Claude 실행 |
| `list.cmd` | 프로필 목록과 현재 활성 프로필 표시 |
| `stop.cmd` | Claude와 그것이 띄운 모든 것을 완전히 종료 — **앱 업데이트 전에 실행** |

다른 프로필용 실행기가 필요하면 `2-work.cmd` 를 복사해 안의 이름만 바꾸세요.

<details>
<summary><b>명령줄 사용법</b></summary>

```powershell
.\claude-switch.ps1 <이름>            # <이름>으로 전환 후 Claude 실행
.\claude-switch.ps1 <이름> -NoLaunch  # 전환만 하고 실행하지 않음
.\claude-switch.ps1 -Menu             # 대화형 번호 메뉴
.\claude-switch.ps1 -List             # 프로필 목록 / 활성 프로필 표시
.\claude-switch.ps1 -Stop             # Claude와 모든 자식 프로세스를 완전히 종료
.\claude-switch.ps1 -Setup            # (유지보수) 공유 폴더를 모든 프로필에 다시 연결
.\claude-switch.ps1 -Version          # 현재 사본의 버전 출력
```

없는 이름으로 전환하면 빈 프로필이 새로 만들어집니다. 메뉴의 `N` 과 같은 동작입니다.

</details>

---

## ⚠️ Claude Desktop을 업데이트하기 전에

창의 **X** 를 눌러도 Claude는 완전히 닫히지 않습니다. 남은 프로세스가 있는 상태로 업데이트하면
업데이트가 실패하고, 보통 **재부팅**해야 풀립니다.

```
C:\Program Files\WindowsApps\Claude_<버전>_x64__...
다른 프로그램이 현재 이 파일을 사용 중입니다.
(Another program is currently using this file.)
```

**이 순서로 하세요.**

```
1-main.cmd  →  (Claude 사용)  →  stop.cmd  →  업데이트  →  1-main.cmd
```

규칙 두 개: **`main` 프로필에서 업데이트**, 그리고 **먼저 `stop.cmd`**.

이미 꼬였다면 재부팅은 필요 없습니다. `stop.cmd` 를 실행하고 다시 열면 됩니다. 자세한 내용은
[문제 해결](#문제-해결)에 있습니다.

<details>
<summary><b>X 로는 왜 부족한가</b></summary>

Claude Desktop은 MSIX(Store) 패키지입니다. 창을 닫아도 두 종류가 살아남습니다.

- **백그라운드 패키지 프로세스** — 앱의 *패키지 정체성(package identity)* 을 그대로 지닌
  렌더러 / Node 유틸리티 / crashpad 헬퍼.
- **앱이 띄운 자식 프로세스** — 정션된 `claude-code` / `vm_bundles` 폴더에서 실행되는 Claude Code
  CLI와 샌드박스 VM.

패키지 정체성을 가진 프로세스가 **하나라도** 살아 있으면 Windows는 패키지를 **사용 중**으로
판단해 업데이트가 설치 파일을 교체하지 못합니다. 반쯤 적용된 업데이트는 재부팅해야 마무리되는데,
재부팅이 바로 그 남은 프로세스들을 죽이기 때문입니다.

`stop.cmd` 는 대신 **프로세스 트리 전체** 를 종료합니다 — 메인 앱, 모든 백그라운드 패키지
프로세스, 모든 자식. 탐지는 살아있는 하나의 "메인" 프로세스에 의존하지 않고 프로세스마다 자기
근거로 판정하며(남은 헬퍼는 `WindowsApps` 경로로, 정션된 CLI/VM 자식은 자기 폴더로), 결과도 실제
PID로 확인합니다. 그래서 무언가 아직 잠금을 쥐고 있는데 "닫힘"으로 오보하지 않습니다.

일반 프로필 전환도 트리 전체를 종료하는 이유가 같습니다. 살아남은 자식이 활성 폴더 안에 핸들을
걸고 있으면 폴더 이동이 깨집니다.

`main` 에서 업데이트하면 모든 프로필이 공유하는 계정 무관 폴더(`vm_bundles`, `claude-code`,
`claude-code-vm`)도 일관되게 유지됩니다. 큰 업데이트 후에는 언제든 `claude-switch.ps1 -Setup`
으로 다시 연결할 수 있습니다.

</details>

---

## 문제 해결

| 증상 | 해결 |
| --- | --- |
| 전환하다 오류가 납니다 | Claude가 안 닫힌 경우입니다. `stop.cmd` 실행 후 다시 시도하세요. |
| "Claude package not found" | Store 버전이 아닙니다. Microsoft Store에서 Claude를 설치하고 한 번 로그인한 뒤 다시 시도하세요. |
| 창이 열렸다가 바로 사라집니다 | zip 안에서 실행했습니다. 먼저 압축을 풀어 폴더로 꺼내세요. |
| `another claude-switch operation is in progress` | 이전 작업이 비정상 종료됐습니다. 5분 기다리면 잠금이 자동으로 풀립니다. |
| 업데이트 실패: `다른 프로그램이 현재 이 파일을 사용 중입니다` | 아래 항목을 보세요. |
| 상황을 모르겠습니다 | `list.cmd` 를 실행하면 모든 프로필과 활성 프로필이 보입니다. |

<details>
<summary><b>이미 꼬인 업데이트 복구하기 (재부팅 불필요)</b></summary>

`stop.cmd` 없이 앱 안의 안내로 바로 업데이트하면 **꼬인 상태**로 남을 수 있습니다. 새 버전 등록은
성공하는데, 다시 뜬 창이 얼어붙어 Windows가 종료시키거나("응답 없음" / Application Hang), 이후
실행할 때마다 `Another program is currently using this file` 대화상자와 함께 죽습니다.

원인은 위와 같고, 앱 자체의 업데이트 경로에서 발생합니다. 업데이터의 quit-for-update도 트리
전체를 내리지 못해서 — `beforeQuitForUpdate` 만 기록되고 정상 종료 단계까지 가지 않습니다 —
**구버전 프로세스가 교체 후에도 살아남습니다.** 이 프로세스들은
`WindowsApps\Deleted\Claude_<구버전>...` 아래 파일을 며칠씩 붙들고 있을 수 있고, 그 상태에서는
실행할 때마다 미완료 배포가 재개되며 실행과 경합해 같은 대화상자가 반복됩니다. 재부팅만 답인 것
처럼 보였던 이유입니다.

업스트림 리포트: [anthropics/claude-code#76357](https://github.com/anthropics/claude-code/issues/76357),
[#75337](https://github.com/anthropics/claude-code/issues/75337).

실제로는 재부팅이 필요 없습니다.

1. **`stop.cmd` 를 실행합니다.** 구버전 잔류 프로세스도 잡습니다. 패키지 폴더가 `Deleted` 로
   옮겨진 뒤에도 이미지 경로가 `WindowsApps...Claude` 에 매칭되기 때문에, 재부팅이 죽였을 바로 그
   잠금 보유자들만 종료합니다.
2. **Claude in Chrome 확장을 쓴다면 Chrome도 닫으세요.**
   [#75337](https://github.com/anthropics/claude-code/issues/75337)에 따르면 네이티브 메시징
   호스트가 패키지 정체성을 지닌 채 Claude가 아니라 Chrome에 의해 되살아납니다.
3. **Claude를 다시 실행합니다** (`1-main.cmd`). 그래도 같은 오류가 나오면 관리자 PowerShell에서
   `Stop-Service CoworkVMService` 를 실행하고 다시 시도하세요. 최후 수단이며, 보통은 업데이트가
   이 서비스를 알아서 처리합니다.

</details>

---

## 동작 원리

### 어디에 저장되나

```
활성 프로필     ...\LocalCache\Roaming\Claude                    ← 실제 폴더
비활성          ...\LocalCache\Roaming\ClaudeProfiles\<이름>
공유 폴더       ...\LocalCache\Roaming\ClaudeShared\<vm_bundles|claude-code|claude-code-vm>
활성 표식       ...\LocalCache\Roaming\ClaudeActiveProfile.txt
```

### 전환은 링크가 아니라 이동

1. Claude Desktop을 종료합니다. 닫히지 않으면 중단합니다 — 잠긴 상태로 아무것도 옮기지 않습니다.
2. 활성 프로필을 `ClaudeProfiles\<active>` 로 옮겨냅니다.
3. 대상 프로필을 `ClaudeProfiles\<target>` 에서 옮겨 넣습니다.
4. 공유 폴더를 다시 연결하고, 표식을 갱신하고, Claude를 실행합니다.

같은 볼륨 내 이동은 즉시 처리되는 이름 변경이라 전환은 1초 정도입니다. 3단계가 도중에 실패하면
2단계가 **롤백**되어, 활성 프로필이 없는 상태로 남지 않습니다.

<details>
<summary><b>그냥 <code>Claude</code> 폴더를 정션으로 만들면 안 되나? (앱이 망가집니다)</b></summary>

Claude Desktop은 계정 데이터를 전부 한 폴더에 두고, Windows는 이미 그 폴더를 MSIX 정션으로
노출합니다.

```
%APPDATA%\Claude   ->   %LOCALAPPDATA%\Packages\<PackageFamilyName>\LocalCache\Roaming\Claude
```

흔히 떠올리는 방법은 그 `Claude` 폴더 *자체* 를 프로필로 향하는 정션으로 만드는 것입니다. 그러면
데이터가 정션을 **두 번** 거쳐 도달하게 되고, Claude의 원자적 쓰기(`임시 파일 작성 -> 이름 변경`)
가 **새 파일** 에 대해 `ENOENT` 로 실패합니다. 예: `git-worktrees.json`.

이미 데이터가 있는 프로필은 그 파일들이 존재해서 덮어쓰기가 되므로 우연히 실행됩니다. 하지만
비어 있는 새 프로필은 첫 실행에서 크래시가 납니다.

claude-switch는 이중 정션을 아예 피합니다. 활성 `Claude` 폴더는 항상 실제 폴더 — 일반 설치와
똑같이 앱 자신의 정션 하나뿐 — 로 유지됩니다. 그래서 링크를 바꾸는 대신 폴더를 옮깁니다.

</details>

### 무거운 폴더는 한 번만 저장

계정과 무관한 무거운 폴더 — `vm_bundles`(약 11GB), `claude-code`, `claude-code-vm` — 는
`ClaudeShared` 에 **한 번만** 저장되고 모든 프로필에 정션으로 연결됩니다. 새 계정은 이를 다시
받지 않고 재사용합니다. 예전에 빈 새 프로필에서 "claude update error" 가 나던 원인이 바로 이
부분입니다. 언제든 `-Setup` 으로 다시 연결할 수 있습니다.

### Claude Code 세션은 알아서 동기화됩니다

Claude Desktop은 Claude Code 세션을 계정별로
`claude-code-sessions\<accountUuid>\<orgUuid>\local_*.json` 아래에 저장합니다. 이 파일들은 정션으로
연결할 수 **없어서**(같은 원자적 쓰기 문제) claude-switch가 전환할 때마다 앱이 닫힌 상태에서 정규
저장소를 거쳐 "최신 우선" 으로 동기화합니다.

설정할 것은 없습니다. 프로필 ↔ 계정 매핑은 스스로 고쳐집니다. 전환할 때마다 나가는 프로필에서
가장 최근에 수정된 세션 파일이 있는 `accountUuid\orgUuid` 폴더를 찾아, 매핑이 없거나 예전 값이면
갱신하고, 들어오는 프로필에 대해서도 같은 확인을 합니다. 그래서 **기존 프로필에 다른 계정으로
로그인** 해도 다음 전환 때 알아서 맞춰집니다. UUID를 직접 찾을 필요가 없습니다.

<details>
<summary><b>매핑 파일을 직접 보거나 고치고 싶다면</b></summary>

`ClaudeShared\cc-sync-map.json` 에 있습니다.

```json
{
  "work": { "accountUuid": "xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx", "orgUuid": "yyyyyyyy-yyyy-yyyy-yyyy-yyyyyyyyyyyy", "email": "" },
  "main": { "accountUuid": "aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa", "orgUuid": "bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb", "email": "" }
}
```

직접 고칠 필요가 있는 경우는 한 프로필에서 여러 계정을 번갈아 로그인해 모호해진 때뿐입니다.
자동 선택은 가장 최근에 세션 파일이 수정된 계정을 고릅니다.

파일이 없으면 아직 매핑이 없는 프로필은 동기화가 꺼진 채로 시작하고, 전환할 때마다 스스로
채워집니다. `email` 은 참고용 메모이고 스크립트는 읽지 않습니다.

</details>

---

## 안전성

- **로그인을 지우지 않습니다.** 전환은 폴더를 *옮기기만* 하고 계정 데이터는 보존됩니다.
- **잠긴 상태로 실행하지 않습니다.** Claude를 닫을 수 없으면 파일을 건드리기 전에 중단합니다.
- **실패 시 롤백.** 활성화가 실패하면 직전 활성 프로필을 복구합니다.
- **이름 검증.** 프로필 이름이 저장소 폴더를 벗어나지 못하도록 검증합니다.
- **동시 실행 방지.** 잠금 파일로 겹치는 전환을 막고, 작업이 죽으면 5분 뒤 자동으로 풀립니다.

## 주의 사항

- Windows 전용이며 **Store(MSIX)** 버전 Claude Desktop에서만 동작합니다.
- Claude Desktop의 내부 폴더 구조에 의존하므로 향후 업데이트로 바뀔 수 있습니다.
- 한 번에 한 계정만 활성화됩니다. 이 도구는 그 전환을 빠르게 해주는 것이고, 동시 실행은 아닙니다.
- 정션은 프로필이 같은 볼륨에 있어야 하는데, 모든 데이터가 `LocalAppData` 아래라 충족됩니다.

## 라이선스

[MIT](LICENSE)
