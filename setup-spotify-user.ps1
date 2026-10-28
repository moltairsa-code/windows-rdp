param(
  [int]$WaitForLoginSeconds = 120
)

$ErrorActionPreference = "Stop"
$markerDirectory = Join-Path $env:LOCALAPPDATA "RdpRunner"
$marker = Join-Path $markerDirectory "spotify-spicetify-ready"
if (Test-Path $marker) {
  Write-Host "Spotify and Spicetify are already configured on this runner."
  exit 0
}

Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope CurrentUser -Force

$storeSpotify = Get-AppxPackage -Name "SpotifyAB.SpotifyMusic" -ErrorAction SilentlyContinue
if ($storeSpotify) {
  throw "The Microsoft Store Spotify app is installed. Spicetify needs the desktop installer from Spotify's website."
}

$spotifyExeCandidates = @(
  (Join-Path $env:APPDATA "Spotify\Spotify.exe"),
  (Join-Path $env:LOCALAPPDATA "Spotify\Spotify.exe")
)
$spotifyExe = $spotifyExeCandidates | Where-Object { Test-Path $_ } | Select-Object -First 1

if (-not $spotifyExe) {
  $installer = Join-Path $env:TEMP "SpotifyFullSetupX64.exe"
  Write-Host "Preparing Spotify's official full desktop installer."
  if (-not (Test-Path $installer)) {
    Write-Host "Downloading installer."
    Invoke-WebRequest -Uri "https://download.scdn.co/SpotifyFullSetupX64.exe" -OutFile $installer -UseBasicParsing
  }
  $signature = Get-AuthenticodeSignature $installer
  if ($signature.Status -ne "Valid" -or $signature.SignerCertificate.Subject -notmatch "Spotify AB") {
    throw "Spotify installer signature validation failed."
  }
  $install = Start-Process -FilePath $installer -ArgumentList "/silent /skip-app-launch" -Wait -PassThru

  $deadline = (Get-Date).AddMinutes(2)
  do {
    Start-Sleep -Seconds 2
    $spotifyExe = $spotifyExeCandidates | Where-Object { Test-Path $_ } | Select-Object -First 1
  } until ($spotifyExe -or (Get-Date) -ge $deadline)
  if (-not $spotifyExe) { throw "Spotify installation failed with exit code $($install.ExitCode); Spotify.exe was not found." }
}

$spicetify = Get-Command spicetify -ErrorAction SilentlyContinue
if (-not $spicetify) {
  Write-Host "Installing Spicetify CLI."
  Invoke-WebRequest -UseBasicParsing "https://raw.githubusercontent.com/spicetify/cli/main/install.ps1" | Invoke-Expression
}

$spicetifyExe = Join-Path $env:LOCALAPPDATA "spicetify\spicetify.exe"
if (-not (Test-Path $spicetifyExe)) {
  $spicetify = Get-Command spicetify -ErrorAction SilentlyContinue
  if (-not $spicetify) { throw "Spicetify CLI installation did not create the command." }
  $spicetifyExe = $spicetify.Source
}

if (-not (Get-Process -Name Spotify -ErrorAction SilentlyContinue)) {
  Write-Host "Spotify is opening. Sign in and leave it open for at least 60 seconds; Spicetify setup continues after $WaitForLoginSeconds seconds."
  Start-Process -FilePath $spotifyExe
}
Start-Sleep -Seconds $WaitForLoginSeconds

# Spicetify must patch Spotify while the client is closed.
Get-Process -Name Spotify -ErrorAction SilentlyContinue | ForEach-Object {
  if ($_.MainWindowHandle -ne 0) { [void]$_.CloseMainWindow() }
}
$closeDeadline = (Get-Date).AddSeconds(20)
while ((Get-Process -Name Spotify -ErrorAction SilentlyContinue) -and (Get-Date) -lt $closeDeadline) {
  Start-Sleep -Seconds 2
}
if (Get-Process -Name Spotify -ErrorAction SilentlyContinue) {
  Stop-Process -Name Spotify -Force -ErrorAction SilentlyContinue
  Start-Sleep -Seconds 2
}

$marketplaceInstaller = Join-Path $env:TEMP "spm.ps1"
Invoke-WebRequest -UseBasicParsing `
  "https://raw.githubusercontent.com/spicetify/spicetify-marketplace/main/resources/install.ps1" `
  -OutFile $marketplaceInstaller
& $marketplaceInstaller -BypassAdmin

& $spicetifyExe config current_theme marketplace --bypass-admin
if ($LASTEXITCODE -ne 0) { throw "Spicetify theme configuration failed with exit code $LASTEXITCODE." }
& $spicetifyExe backup apply --bypass-admin
if ($LASTEXITCODE -ne 0) { throw "Spicetify backup/apply failed with exit code $LASTEXITCODE." }

New-Item -ItemType Directory -Force -Path $markerDirectory | Out-Null
Set-Content -Path $marker -Value (Get-Date -Format o)
Write-Host "Done! Reopening Spotify with Marketplace."
Start-Process -FilePath $spotifyExe
