#Requires -Version 5.1
<#
  setup-shared.ps1  -  ONE-TIME restructure for claude-switch.

  NOTE (example / personal migration - NOT needed for a fresh install):
    This is the author's own one-time migration script. It assumes a specific starting
    state (a logged-in account sitting in a profile named 'main') and relabels it to
    'work'. For general shared-infra linking on any setup, use `claude-switch.ps1 -Setup`
    instead. Kept here only as a reference example of the shared-store restructure.

  What it does (safely, on the data the app actually uses):
    1. Moves account-neutral heavy folders (vm_bundles, claude-code, claude-code-vm)
       out of the current profile into a shared store, linked back via junctions.
       -> profiles become small; new profiles never re-provision the ~11 GB VM bundle
          (that was the cause of the "claude update error" on the empty profile).
    2. Relabels your current logged-in account: 'main' -> 'work'  (per your intent).
    3. Creates a fresh empty 'main' profile (with shared infra linked) for the 2nd account.

  Your current account's login files are never moved or deleted - the folder is just
  renamed. No re-login needed for it. Idempotent: re-running after success just reports.
#>

$ErrorActionPreference = 'Stop'
$SharedFolders = @('vm_bundles', 'claude-code', 'claude-code-vm')

$pkg = Get-AppxPackage -Name 'Claude' | Select-Object -First 1
if (-not $pkg) { throw 'Claude package not found.' }
$appId   = @((Get-AppxPackageManifest $pkg).Package.Applications.Application)[0].Id
$aumid   = "$($pkg.PackageFamilyName)!$appId"
$roaming = Join-Path $env:LOCALAPPDATA "Packages\$($pkg.PackageFamilyName)\LocalCache\Roaming"
$live    = Join-Path $roaming 'Claude'
$store   = Join-Path $roaming 'ClaudeProfiles'
$shared  = Join-Path $roaming 'ClaudeShared'
$main    = Join-Path $store 'main'
$work    = Join-Path $store 'work'

function Stop-ClaudeDesktop {
  Get-Process -Name 'Claude' -ErrorAction SilentlyContinue |
    Where-Object { $_.Path -and $_.Path -like '*WindowsApps*Claude*' } |
    Stop-Process -Force -ErrorAction SilentlyContinue
  for ($i = 0; $i -lt 40; $i++) {
    $a = Get-Process -Name 'Claude' -ErrorAction SilentlyContinue |
      Where-Object { $_.Path -and $_.Path -like '*WindowsApps*Claude*' }
    if (-not $a) { break }
    Start-Sleep -Milliseconds 200
  }
}

function Link-Shared([string]$profileDir) {
  foreach ($n in $SharedFolders) {
    $tgt = Join-Path $shared $n
    $lnk = Join-Path $profileDir $n
    $it  = Get-Item $lnk -Force -ErrorAction SilentlyContinue
    if ($it -and -not $it.LinkType) {
      if (Test-Path $tgt) { Remove-Item -LiteralPath $lnk -Recurse -Force }
      else { Move-Item -LiteralPath $lnk -Destination $tgt }
      $it = $null
    }
    if ((Test-Path $tgt) -and -not $it) { cmd /c mklink /J "$lnk" "$tgt" | Out-Null }
  }
}

function Is-LoggedIn([string]$dir) { return (Test-Path (Join-Path $dir 'buddy-tokens.json')) }

Write-Host '=== claude-switch one-time setup ===' -ForegroundColor Cyan
New-Item -ItemType Directory -Force -Path $store, $shared | Out-Null

# Idempotency: already relabeled?
if ((Test-Path $work) -and (Is-LoggedIn $work) -and -not (Is-LoggedIn $main)) {
  Write-Host "Already set up: 'work' holds your logged-in account; 'main' is the empty slot." -ForegroundColor Green
  Write-Host "Use 2-work.cmd (current account) / 1-main.cmd (log in the other account)."
  Read-Host 'Press Enter to close'
  return
}

# Sanity: the current account must be in 'main'.
if (-not (Test-Path $main) -or -not (Is-LoggedIn $main)) {
  throw "Expected your logged-in account in 'main' (buddy-tokens.json), but did not find it. Aborting so nothing is touched."
}

Write-Host 'Closing Claude Desktop...'
Stop-ClaudeDesktop

Write-Host '[1/5] Moving shared infra (vm_bundles, claude-code, claude-code-vm) to ClaudeShared...'
Link-Shared $main

if (Test-Path $work) {
  if ((Is-LoggedIn $work) -or (Test-Path (Join-Path $work 'config.json'))) {
    throw "'work' already contains account data. Aborting to avoid data loss."
  }
  Write-Host '[2/5] Removing the empty work profile...'
  cmd /c rmdir /s /q "$work" | Out-Null
}

Write-Host '[3/5] Relabeling current account: main -> work...'
Rename-Item -LiteralPath $main -NewName 'work'

Write-Host '[4/5] Pointing the live folder to work...'
if (Test-Path $live) { cmd /c rmdir "$live" | Out-Null }
cmd /c mklink /J "$live" "$work" | Out-Null

Write-Host '[5/5] Creating a fresh main profile for the second account...'
New-Item -ItemType Directory -Force -Path $main | Out-Null
Link-Shared $main

Write-Host ''
Write-Host 'Done.' -ForegroundColor Green
Write-Host '  work = your current account (now active)'
Write-Host '  main = empty, ready for the second account login'
Write-Host ''
Write-Host 'Launching Claude on your current (work) account...' -ForegroundColor Green
Start-Process "shell:AppsFolder\$aumid"
Write-Host ''
Write-Host 'Next: to add the 2nd account, double-click 1-main.cmd and log in there.'
Read-Host 'Press Enter to close'
