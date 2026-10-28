param(
  [string]$SourceProfilePath = "C:\ProgramData\RunnerState"
)

$ErrorActionPreference = "Stop"
$chromeSource = Join-Path $SourceProfilePath "Chrome\User Data"
if (Test-Path (Join-Path $chromeSource "Local State")) {
  if (Get-Process -Name chrome -ErrorAction SilentlyContinue) {
    Write-Warning "Chrome is already running; leaving its profile untouched for this logon."
  } else {
    $chromeDestination = Join-Path $env:LOCALAPPDATA "Google\Chrome\User Data"
    New-Item -ItemType Directory -Force -Path $chromeDestination | Out-Null
    Copy-Item (Join-Path $chromeSource "*") $chromeDestination -Recurse -Force
    Write-Host "Chrome profile files restored; Chrome will validate whether sessions transfer to this runner."
  }
}

$codexSource = Join-Path $SourceProfilePath "Codex"
if (Test-Path $codexSource) {
  $codexDestination = Join-Path $env:USERPROFILE ".codex"
  New-Item -ItemType Directory -Force -Path $codexDestination | Out-Null
  Copy-Item (Join-Path $codexSource "*") $codexDestination -Recurse -Force
  Write-Host "Codex configuration, login state, and user sessions restored."
}
