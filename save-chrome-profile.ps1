param(
  [string]$MigrationPath = "D:\Migration",
  [string]$ProfilePath = (Join-Path $env:LOCALAPPDATA "Google\Chrome\User Data\Default")
)

$ErrorActionPreference = "Stop"
$destinationDirectory = Join-Path $MigrationPath "chrome\Default"
New-Item -ItemType Directory -Force -Path $destinationDirectory | Out-Null

# These files retain bookmarks and ordinary browser preferences. Do not add
# Cookies, Login Data, Local State, or extension storage to this snapshot.
foreach ($name in @("Bookmarks", "Preferences")) {
  $source = Join-Path $ProfilePath $name
  if (-not (Test-Path $source)) { continue }

  $destination = Join-Path $destinationDirectory $name
  $copied = $false
  for ($attempt = 1; $attempt -le 3 -and -not $copied; $attempt++) {
    try {
      Copy-Item $source $destination -Force -ErrorAction Stop
      $copied = $true
      Write-Host "Saved Chrome $name."
    } catch {
      if ($attempt -eq 3) { throw "Could not save Chrome ${name}: $_" }
      Start-Sleep -Seconds 2
    }
  }
}
