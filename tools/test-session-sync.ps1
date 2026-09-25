#Requires -Version 5.1
$ErrorActionPreference = 'Stop'
# Load functions only: never resolve or modify the installed Claude profile.
$tokens = $null; $errors = $null
$ast = [System.Management.Automation.Language.Parser]::ParseFile(
  (Join-Path $PSScriptRoot '..\claude-switch.ps1'), [ref]$tokens, [ref]$errors)
if ($errors.Count) { throw ($errors | Out-String) }
foreach ($f in $ast.FindAll({ param($n) $n -is [System.Management.Automation.Language.FunctionDefinitionAst] }, $false)) {
  . ([scriptblock]::Create($f.Extent.Text))
}
function Assert($ok, $message) { if (-not $ok) { throw $message } }
function Bytes($path) { [Convert]::ToBase64String([IO.File]::ReadAllBytes($path)) }
$root = Join-Path ([IO.Path]::GetTempPath()) ('claude-switch-test-' + [guid]::NewGuid())
$P = [pscustomobject]@{
  Live = Join-Path $root 'live'
  Shared = Join-Path $root 'shared'
  CCCanon = Join-Path $root 'shared\canonical'
  CCMap = Join-Path $root 'shared\map.json'
  Marker = Join-Path $root 'active.txt'
}
$CCSyncMap = @{}
try {
  New-Item -ItemType Directory -Path $P.Live, $P.CCCanon -Force | Out-Null
  Set-Active 'new'
  $source = Join-Path $P.CCCanon 'local_existing.json'
  Set-Content $source '{"sessionId":"local_existing"}'
  Sync-PushCC 'new'
  Assert ($null -eq (Get-CCViewDir 'new')) 'Pre-login profile should have no account mapping'

  # The first login creates an empty account/org directory, not a local session.
  $view = Join-Path $P.Live 'claude-code-sessions\account\org'
  New-Item -ItemType Directory -Path $view -Force | Out-Null
  Update-CCMapEntry 'new'
  Sync-PullCC 'new'
  Sync-PushCC 'new'
  $dest = Join-Path $view 'local_existing.json'
  Assert (Test-Path $dest) 'First-login profile did not receive canonical sessions'
  Assert ((Bytes $source) -eq (Bytes $dest)) 'Import changed session bytes'
  Assert (-not (Get-Item $view).LinkType) 'Session directory must stay real'
  Set-Content $dest '{"sessionId":"local_existing","newer":true}'
  (Get-Item $dest).LastWriteTimeUtc = [datetime]::UtcNow.AddMinutes(1)
  Sync-PushCC 'new'
  Assert ((Get-Content $dest -Raw) -match 'newer') 'Push overwrote a newer destination'
  Sync-PullCC 'new'
  Assert ((Bytes $source) -eq (Bytes $dest)) 'Pull lost newer changes'

  # Stub only the interactive boundary; no app is stopped or launched in tests.
  function Read-Host { return '' }
  function powershell { $script:relaunched = $true }
  $script:relaunched = $false
  Complete-CCFirstLogin 'new'
  Assert $script:relaunched 'Login completion did not re-run the normal switch path'
  $script:relaunched = $false
  Set-Active 'other'
  Complete-CCFirstLogin 'new'
  Assert (-not $script:relaunched) 'Login completion switched away from another active profile'
  Set-Active 'new'
  $P.Live = Join-Path $root 'not-logged-in'
  Complete-CCFirstLogin 'new'
  Assert (-not $script:relaunched) 'Login completion restarted before login'
  Write-Output 'PASS: first-login import, byte preservation, newest-wins, and login completion guards'
} finally {
  $resolved = [IO.Path]::GetFullPath($root)
  $temp = [IO.Path]::GetFullPath([IO.Path]::GetTempPath()).TrimEnd('\') + '\'
  if (-not $resolved.StartsWith($temp, [StringComparison]::OrdinalIgnoreCase) -or
      (Split-Path $resolved -Leaf) -notlike 'claude-switch-test-*') { throw 'Unsafe test cleanup path' }
  Remove-Item -LiteralPath $resolved -Recurse -Force
}
