Windows에서 **Claude Desktop(Microsoft Store 버전)의 여러 계정을 번갈아 쓰는** 도구입니다.
계정을 바꿔도 로그인이 유지되고, 11GB짜리 VM 번들을 다시 내려받지 않습니다.

---

## 컴퓨터를 잘 모르신다면 (설치 방법)

1. 아래 **Assets** 에서 **`claude-switch-{{VERSION}}.zip`** 을 클릭해 내려받으세요.
2. 내려받은 zip 파일에 **마우스 오른쪽 클릭 → 압축 풀기**
   - 압축을 풀지 않고 안에서 바로 실행하면 동작하지 않습니다.
3. 압축을 푼 폴더에서 **`시작하기.cmd`** 를 두 번 클릭하세요.
   - "Windows가 PC를 보호했습니다" 창이 뜨면 **추가 정보 → 실행** 을 누르세요. 정상입니다.
4. 번호를 골라 Enter를 누르면 계정이 바뀌고 Claude가 열립니다.

자세한 설명은 압축 안의 **`사용설명서.md`** 에 있습니다.

> **Claude Desktop을 업데이트하기 전에는 `stop.cmd` 를 먼저 실행하세요.**
> 그러지 않으면 "다른 프로그램이 현재 이 파일을 사용 중입니다" 오류로 업데이트가 실패하고
> 재부팅이 필요해집니다.

### 필요한 것

- Windows 10 / 11
- **Microsoft Store에서 설치한** Claude Desktop (홈페이지 설치 버전은 지원하지 않습니다)
- Windows PowerShell 5.1 (Windows에 기본 포함 — 따로 설치할 필요 없습니다)

---

## For developers

Download `claude-switch-{{VERSION}}.zip`, extract it anywhere, and run `menu.cmd` or call
`claude-switch.ps1` directly. `claude-switch.ps1 -Version` reports the version.

```powershell
.\claude-switch.ps1 <name>            # switch to <name>, then launch Claude
.\claude-switch.ps1 -List             # list profiles / show the active one
.\claude-switch.ps1 -Menu             # interactive numbered menu
.\claude-switch.ps1 -Stop             # close Claude Desktop + all children (before updating)
.\claude-switch.ps1 -Setup            # (maintenance) re-link shared infra into every profile
```

Verify the download:

```powershell
Get-FileHash .\claude-switch-{{VERSION}}.zip -Algorithm SHA256
```

Compare against `claude-switch-{{VERSION}}.zip.sha256`.

Full change list: [CHANGELOG.md](https://github.com/lpaiu-cs/claude-switch/blob/v{{VERSION}}/CHANGELOG.md)

---

Unofficial community tool, not affiliated with or endorsed by Anthropic. It manipulates Claude
Desktop's undocumented local data folders, which can change between app updates. Use at your
own risk.
