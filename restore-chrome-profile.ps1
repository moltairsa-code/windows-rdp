param(
  [string]$MigrationPath = "D:\Migration"
)

$ErrorActionPreference = "Stop"
$sourceDirectory = Join-Path $MigrationPath "chrome\Default"
$profileDirectory = Join-Path $env:LOCALAPPDATA "Google\Chrome\User Data\Default"

if (-not (Test-Path $sourceDirectory)) {
  Write-Host "No saved Chrome settings found."
  exit 0
}

if (Get-Process -Name chrome -ErrorAction SilentlyContinue) {
  Write-Warning "Chrome is already running; leaving its profile untouched."
  exit 0
}

New-Item -ItemType Directory -Force -Path $profileDirectory | Out-Null
foreach ($name in @("Bookmarks", "Preferences")) {
  $source = Join-Path $sourceDirectory $name
  if (Test-Path $source) {
    Copy-Item $source (Join-Path $profileDirectory $name) -Force
    Write-Host "Restored Chrome $name."
  }
}

Write-Host "Chrome settings restored. Sign-in sessions and passwords are not included."
