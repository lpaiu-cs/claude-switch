#Requires -Version 5.1
<#
  claude-switch.ps1  -  Claude Desktop (MSIX) account profile switcher
  (one account active at a time; MOVE-BASED so the app sees a single junction)

  Usage:
    claude-switch.ps1 <name>            switch to profile <name>, then launch Claude
    claude-switch.ps1 -List             list profiles / show the active one
    claude-switch.ps1 <name> -NoLaunch  switch only, do not launch
    claude-switch.ps1 -Setup            (maintenance) ensure shared infra is linked everywhere

  Why move-based:
    %APPDATA%\Claude is an MSIX junction -> ...\LocalCache\Roaming\Claude  (the "Live" folder).
    If we make Live ITSELF a junction to a profile, the app reaches its data through TWO
    junctions. Atomic writes (tmp file -> rename) of NEW files then fail with ENOENT, so a
    fresh/empty profile crashes on launch (git-worktrees.json). Existing files (overwrite) work,
    which is why a populated profile launches but an empty one does not.
    Fix: keep Live as a REAL folder = the active profile (single junction, like a normal install).
    Switching = move the active profile out to the store and move the target profile in.
    Moves are same-volume renames (instant), and inner shared junctions keep their absolute targets.

  Layout:
    Live (active)  %LOCALAPPDATA%\Packages\<pkg>\LocalCache\Roaming\Claude   (REAL folder)
    Inactive       ...\Roaming\ClaudeProfiles\<name>
    Shared infra   ...\Roaming\ClaudeShared\<vm_bundles|claude-code|claude-code-vm>  (junctioned in)
    Active marker  ...\Roaming\ClaudeActiveProfile.txt
#>

[CmdletBinding()]
param(
  [Parameter(Position = 0)]
  [string]$ProfileName,
  [switch]$List,
  [switch]$NoLaunch,
  [switch]$Setup
)

$ErrorActionPreference = 'Stop'

# Account-neutral folders shared across all profiles via junctions.
$SharedFolders = @('vm_bundles', 'claude-code', 'claude-code-vm')

function Resolve-ClaudePaths {
  $pkg = Get-AppxPackage -Name 'Claude' | Select-Object -First 1
  if (-not $pkg) { throw "Claude package not found (Get-AppxPackage -Name Claude)." }
  $appId   = @((Get-AppxPackageManifest $pkg).Package.Applications.Application)[0].Id
  $roaming = Join-Path $env:LOCALAPPDATA "Packages\$($pkg.PackageFamilyName)\LocalCache\Roaming"
  [pscustomobject]@{
    Aumid   = "$($pkg.PackageFamilyName)!$appId"
    Roaming = $roaming
    Live    = Join-Path $roaming 'Claude'
    Store   = Join-Path $roaming 'ClaudeProfiles'
    Shared  = Join-Path $roaming 'ClaudeShared'
    Marker  = Join-Path $roaming 'ClaudeActiveProfile.txt'
    CCCanon = Join-Path $roaming 'ClaudeShared\cc-sessions-canonical'
    CCMap   = Join-Path $roaming 'ClaudeShared\cc-sync-map.json'
  }
}

function Stop-ClaudeDesktop {
  $isClaude = { $_.Path -and $_.Path -like '*WindowsApps*Claude*' }
  Get-Process -Name 'Claude' -ErrorAction SilentlyContinue |
    Where-Object $isClaude |
    Stop-Process -Force -ErrorAction SilentlyContinue
  for ($i = 0; $i -lt 30; $i++) {
    if (-not (Get-Process -Name 'Claude' -ErrorAction SilentlyContinue | Where-Object $isClaude)) { return }
    Start-Sleep -Milliseconds 200
  }
  # Still alive after ~6s: refuse to proceed rather than fail later with a cryptic file-lock error.
  if (Get-Process -Name 'Claude' -ErrorAction SilentlyContinue | Where-Object $isClaude) {
    throw "Claude Desktop is still running and could not be closed. Close it manually, then retry."
  }
}

function Remove-Junction([string]$path) {
  if (Test-Path $path) { cmd /c rmdir "$path" | Out-Null }
}

# Guard against path traversal / reserved names: a profile name becomes a folder under the store.
function Assert-ValidProfileName([string]$name) {
  if ([string]::IsNullOrWhiteSpace($name) -or $name -notmatch '^[A-Za-z0-9._-]{1,64}$' -or $name -eq '.' -or $name -eq '..') {
    throw "Invalid profile name '$name'. Use 1-64 characters: letters, digits, dot, dash, underscore (no spaces or path separators)."
  }
  $reserved = @('CON', 'PRN', 'AUX', 'NUL') + (1..9 | ForEach-Object { "COM$_" }) + (1..9 | ForEach-Object { "LPT$_" })
  if ($reserved -contains $name.ToUpperInvariant()) {
    throw "Invalid profile name '$name'. That is a reserved Windows device name."
  }
}

function Get-Active {
  if (Test-Path $P.Marker) {
    $v = Get-Content $P.Marker -Raw -ErrorAction SilentlyContinue
    if ($v) { $v = $v.Trim() }
    if ($v) { return $v }
  }
  return $null
}
function Set-Active([string]$name) {
  Set-Content -Path $P.Marker -Value $name -NoNewline -Encoding Ascii
}

# Cross-process guard so two overlapping switches can't corrupt the move-based layout.
function Acquire-Lock {
  $lock = Join-Path $P.Roaming 'claude-switch.lock'
  $existing = Get-Item $lock -Force -ErrorAction SilentlyContinue
  if ($existing -and ((Get-Date) - $existing.LastWriteTime).TotalMinutes -gt 5) {
    Remove-Item -LiteralPath $lock -Force -ErrorAction SilentlyContinue  # stale lock from a crashed run
  }
  try { New-Item -ItemType File -Path $lock -ErrorAction Stop | Out-Null }
  catch { throw "Another claude-switch operation is in progress (lock: $lock). If it is stale, delete that file and retry." }
  return $lock
}
function Release-Lock([string]$lock) {
  if ($lock) { Remove-Item -LiteralPath $lock -Force -ErrorAction SilentlyContinue }
}

function Ensure-SharedLinks([string]$profileDir) {
  New-Item -ItemType Directory -Force -Path $P.Shared | Out-Null
  foreach ($name in $SharedFolders) {
    $shareTarget = Join-Path $P.Shared $name
    $link        = Join-Path $profileDir $name
    $item        = Get-Item $link -Force -ErrorAction SilentlyContinue
    if ($item -and -not $item.LinkType) {
      if (Test-Path $shareTarget) { Remove-Item -LiteralPath $link -Recurse -Force }
      else { Move-Item -LiteralPath $link -Destination $shareTarget }
      $item = $null
    }
    if ((Test-Path $shareTarget) -and (-not $item)) {
      cmd /c mklink /J "$link" "$shareTarget" | Out-Null
    }
  }
}

# --- Claude Code session sharing (sync, not junction: junctions break atomic writes) ---
# The desktop indexes CC sessions under  claude-code-sessions\<accountUuid>\<orgUuid>\local_*.json,
# keyed per desktop account. We can't junction it (atomic tmp->rename ENOENTs through a junction),
# so at each switch (app stopped) we copy real files between a shared canonical store and the
# active account's view dir. $CCSyncMap maps profile name -> {accountUuid, orgUuid}.
function Get-CCViewDir([string]$name) {
  if (-not $CCSyncMap.ContainsKey($name)) { return $null }
  $m = $CCSyncMap[$name]
  if (-not $m.accountUuid -or -not $m.orgUuid) { return $null }
  return (Join-Path $P.Live ("claude-code-sessions\{0}\{1}" -f $m.accountUuid, $m.orgUuid))
}
function Sync-PullCC([string]$name) {
  # active account's view (at Live) -> canonical (newest wins)
  $view = Get-CCViewDir $name
  if (-not $view -or -not (Test-Path $view)) { return }
  New-Item -ItemType Directory -Force -Path $P.CCCanon | Out-Null
  Get-ChildItem $view -Filter 'local_*.json' -File -ErrorAction SilentlyContinue | ForEach-Object {
    $dst = Join-Path $P.CCCanon $_.Name
    if (-not (Test-Path $dst) -or $_.LastWriteTimeUtc -gt (Get-Item $dst).LastWriteTimeUtc) {
      Copy-Item -LiteralPath $_.FullName -Destination $dst -Force
    }
  }
}
function Sync-PushCC([string]$name) {
  # canonical -> active account's view (newest wins); real files, so atomic writes stay safe
  $view = Get-CCViewDir $name
  if (-not $view -or -not (Test-Path $P.CCCanon)) { return }
  New-Item -ItemType Directory -Force -Path $view | Out-Null
  Get-ChildItem $P.CCCanon -Filter 'local_*.json' -File -ErrorAction SilentlyContinue | ForEach-Object {
    $dst = Join-Path $view $_.Name
    if (-not (Test-Path $dst) -or $_.LastWriteTimeUtc -gt (Get-Item $dst).LastWriteTimeUtc) {
      Copy-Item -LiteralPath $_.FullName -Destination $dst -Force
    }
  }
}

$P = Resolve-ClaudePaths
New-Item -ItemType Directory -Force -Path $P.Store, $P.Shared | Out-Null

# Load the CC sync map (profile name -> account/org uuids). Missing/invalid = sync disabled.
$CCSyncMap = @{}
if (Test-Path $P.CCMap) {
  try {
    (Get-Content $P.CCMap -Raw | ConvertFrom-Json).PSObject.Properties |
      ForEach-Object { $CCSyncMap[$_.Name] = $_.Value }
  } catch { Write-Host "[cc-sync] map load failed: $($_.Exception.Message)" -ForegroundColor DarkYellow }
}

# --- Normalize: convert legacy junction-based Live into a real (move-based) Live ---
$liveItem = Get-Item $P.Live -Force -ErrorAction SilentlyContinue
if ($liveItem -and $liveItem.LinkType) {
  Write-Host "[normalize] converting junction-based layout to move-based (one junction)..." -ForegroundColor Cyan
  Stop-ClaudeDesktop
  $name = Split-Path -Leaf (@($liveItem.Target)[0])
  Remove-Junction $P.Live
  $src = Join-Path $P.Store $name
  if (Test-Path $src) { Move-Item -LiteralPath $src -Destination $P.Live }
  else { New-Item -ItemType Directory -Force -Path $P.Live | Out-Null }
  Set-Active $name
  $liveItem = Get-Item $P.Live -Force -ErrorAction SilentlyContinue
}
# First-ever original install: Live is a real folder but no marker yet -> name it 'main'.
if ($liveItem -and -not $liveItem.LinkType -and -not (Test-Path $P.Marker)) {
  Set-Active 'main'
}

# --- Maintenance: ensure shared infra is linked into active + all stored profiles ---
if ($Setup) {
  $lock = Acquire-Lock
  try {
    Stop-ClaudeDesktop
    if (Test-Path $P.Live) { Ensure-SharedLinks $P.Live }
    Get-ChildItem $P.Store -Directory -ErrorAction SilentlyContinue | ForEach-Object {
      Ensure-SharedLinks $_.FullName
    }
    Write-Host "[setup] shared infra ensured. Shared store: $($P.Shared)" -ForegroundColor Green
  } finally { Release-Lock $lock }
  return
}

# --- List ---
if ($List -or -not $ProfileName) {
  $active = Get-Active
  Write-Host "`nActive profile: " -NoNewline
  Write-Host ($(if ($active) { $active } else { '(none)' })) -ForegroundColor Green
  Write-Host "`nProfiles:"
  $names = New-Object System.Collections.Generic.List[string]
  if ($active) { $names.Add($active) }
  Get-ChildItem $P.Store -Directory -ErrorAction SilentlyContinue | ForEach-Object {
    if ($_.Name -ne $active) { $names.Add($_.Name) }
  }
  $names | Sort-Object -Unique | ForEach-Object {
    $mark = if ($_ -eq $active) { '* ' } else { '  ' }
    Write-Host ("  {0}{1}" -f $mark, $_)
  }
  Write-Host "`nSwitch with:  claude-switch <name>   (unknown name = new empty profile)`n"
  return
}

# --- Switch (move-based) ---
Assert-ValidProfileName $ProfileName
$lock = Acquire-Lock
try {
  Stop-ClaudeDesktop
  $active = Get-Active
  # Capture the outgoing/active account's CC sessions into the shared canonical store
  # (Live still holds the active profile here). Never let a sync error block switching.
  try { if ($active) { Sync-PullCC $active } } catch { Write-Host "[cc-sync] pull skipped: $($_.Exception.Message)" -ForegroundColor DarkYellow }
  if ($active -ne $ProfileName) {
    # Stash the currently active profile (sitting at Live) back into the store.
    $stashed = $null
    if (Test-Path $P.Live) {
      if (-not $active) { $active = 'main' }
      $dest = Join-Path $P.Store $active
      if (Test-Path $dest) { throw "Cannot stash active profile: '$dest' already exists. Manual check needed." }
      Move-Item -LiteralPath $P.Live -Destination $dest
      $stashed = @{ Name = $active; Path = $dest }
    }
    try {
      # Activate the target profile (move it to Live), or create a fresh one.
      $tgt = Join-Path $P.Store $ProfileName
      if (Test-Path $tgt) {
        Move-Item -LiteralPath $tgt -Destination $P.Live
      } else {
        New-Item -ItemType Directory -Force -Path $P.Live | Out-Null
        Write-Host "[new profile] '$ProfileName' created - log in with the new account after launch." -ForegroundColor Yellow
      }
      Set-Active $ProfileName
    } catch {
      # Activation failed mid-switch: never leave Live missing - put the stashed profile back.
      if ($stashed -and -not (Test-Path $P.Live) -and (Test-Path $stashed.Path)) {
        Move-Item -LiteralPath $stashed.Path -Destination $P.Live
        Set-Active $stashed.Name
        Write-Host "[rollback] switch failed; restored '$($stashed.Name)' as the active profile." -ForegroundColor Yellow
      }
      throw
    }
  }
  # Give the now-active account the full union of CC sessions (Live now holds the target).
  try { Sync-PushCC $ProfileName } catch { Write-Host "[cc-sync] push skipped: $($_.Exception.Message)" -ForegroundColor DarkYellow }
  Ensure-SharedLinks $P.Live
  Write-Host "Active profile -> '$ProfileName'" -ForegroundColor Green

  if (-not $NoLaunch) {
    Start-Process "shell:AppsFolder\$($P.Aumid)"
    Write-Host "Launching Claude..." -ForegroundColor Green
  }
} finally {
  Release-Lock $lock
}
