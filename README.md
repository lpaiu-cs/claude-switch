# claude-switch

**English** | [한국어](#한국어)

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

> **Update Claude Desktop from the `main` profile.** Run app updates — and other app-level
> maintenance — while `main` is active (launch it with `1-main.cmd`). See
> [Updating Claude Desktop](#updating-claude-desktop) below.

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

### Updating Claude Desktop

**Perform Claude Desktop app updates (and other app-level maintenance) while the `main`
profile is active** — launch it with `1-main.cmd`. Because the heavy, account-neutral
infrastructure (`vm_bundles`, `claude-code`, `claude-code-vm`) is shared across all profiles
through junctions, keeping updates on the single designated `main` profile is what keeps that
shared infrastructure consistent and every account working correctly. After a major update you
can re-link the shared folders into all profiles at any time with `claude-switch.ps1 -Setup`.

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

---

## 한국어

[English](#claude-switch)

Windows에서 여러 **Claude Desktop**(Microsoft Store / MSIX) 계정 프로필을 전환하는 도구입니다 —
한 번에 하나의 계정만 활성화되고, 수 기가바이트짜리 VM 번들을 다시 내려받지 않으며, 전환해도
로그인이 유지됩니다.

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

### 요구 사항

- Windows 10 / 11
- **Microsoft Store에서 설치한 Claude Desktop** (MSIX 패키지 이름 `Claude`)
- Windows PowerShell 5.1 (Windows 기본 제공 — 별도 설치 불필요)

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

> **Claude Desktop 업데이트는 `main` 프로필에서 하세요.** 앱 업데이트 및 기타 앱 수준
> 유지보수는 `main`이 활성인 상태(`1-main.cmd`로 실행)에서 수행하세요. 아래
> [Claude Desktop 업데이트하기](#claude-desktop-업데이트하기) 참고.

#### 터미널에서

```powershell
.\claude-switch.ps1 <이름>            # <이름>으로 전환 후 Claude 실행
.\claude-switch.ps1 -List             # 프로필 목록 / 활성 프로필 표시
.\claude-switch.ps1 <이름> -NoLaunch  # 전환만 하고 실행하지 않음
.\claude-switch.ps1 -Setup            # (유지보수) 공유 인프라를 모든 프로필에 연결
```

- **없는 이름**으로 전환하면 빈 프로필이 새로 만들어집니다 — Claude 실행 후 다른 계정으로
  로그인하면 됩니다.
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

**Claude Desktop 앱 업데이트(및 기타 앱 수준 유지보수)는 `main` 프로필이 활성인 상태에서
수행하세요** — `1-main.cmd`로 실행합니다. 계정과 무관한 무거운 인프라(`vm_bundles`,
`claude-code`, `claude-code-vm`)가 정션으로 모든 프로필에 공유되기 때문에, 지정된 단일
프로필(`main`)에서 업데이트를 유지해야 그 공유 인프라가 일관되게 유지되고 모든 계정이 올바르게
동작합니다. 대규모 업데이트 후에는 언제든 `claude-switch.ps1 -Setup`으로 공유 폴더를 모든
프로필에 다시 연결할 수 있습니다.

#### Claude Code 세션 동기화 (선택)

Claude Desktop은 Claude Code 세션을 데스크톱 계정별로
`claude-code-sessions\<accountUuid>\<orgUuid>\local_*.json` 아래에 저장합니다. 이 파일들은
정션으로 연결할 수 **없어서**(같은 원자적 쓰기 문제), `claude-switch`는 전환할 때마다(앱이 닫힌
상태에서) 정규 저장소를 거쳐 "최신 우선" 복사로 동기화합니다.

활성화하려면 `ClaudeShared\cc-sync-map.json`을 만들어 각 프로필을 계정·조직 UUID에 매핑하세요:

```json
{
  "work": { "accountUuid": "xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx", "orgUuid": "yyyyyyyy-yyyy-yyyy-yyyy-yyyyyyyyyyyy" },
  "main": { "accountUuid": "aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa", "orgUuid": "bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb" }
}
```

해당 계정이 활성 프로필일 때 `...\Roaming\Claude\claude-code-sessions\` 아래를 보면 UUID를
찾을 수 있습니다. 파일이 없거나 형식이 잘못되면 동기화만 비활성화되고 전환은 정상 동작합니다.

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

- Windows 전용이며 **Store(MSIX)** 버전 Claude Desktop에서만 동작합니다.
- Claude Desktop의 내부 폴더 구조에 의존하므로 향후 업데이트로 바뀔 수 있습니다.
- 정션은 프로필이 같은 볼륨에 있어야 하는데, 모든 데이터가 `LocalAppData` 아래에 있으므로 이
  조건은 충족됩니다.

### 라이선스

[MIT](LICENSE)
