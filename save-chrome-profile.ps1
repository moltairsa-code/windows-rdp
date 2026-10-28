param(
  [string]$ProfilePath = "C:\Users\rdpuser\AppData\Local\Google\Chrome\User Data",
  [string]$MigrationPath = "D:\Migration",
  [string]$CodexPath = (Join-Path $env:USERPROFILE ".codex"),
  [string]$SpotifyPath = (Join-Path $env:APPDATA "Spotify"),
  [string]$EncryptionKey,
  [string]$KeyFilePath,
  [switch]$CloseChrome
)

$ErrorActionPreference = "Stop"
if ([string]::IsNullOrWhiteSpace($EncryptionKey) -and (Test-Path $KeyFilePath)) {
  $secureKey = Get-Content $KeyFilePath -Raw | ConvertTo-SecureString
  $keyPointer = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($secureKey)
  try { $EncryptionKey = [Runtime.InteropServices.Marshal]::PtrToStringBSTR($keyPointer) }
  finally { [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($keyPointer) }
}
if ([string]::IsNullOrWhiteSpace($EncryptionKey)) { throw "An encryption key or DPAPI-protected key file is required." }
$key = [Convert]::FromBase64String($EncryptionKey)
if ($key.Length -ne 32) { throw "CHROME_PROFILE_KEY must decode to 32 bytes." }
if (-not (Test-Path (Join-Path $ProfilePath "Local State"))) {
  Write-Host "Chrome profile not found; no profile archive created."
  exit 0
}

if ($CloseChrome) {
  Get-Process -Name chrome -ErrorAction SilentlyContinue | ForEach-Object {
    if ($_.MainWindowHandle -ne 0) { [void]$_.CloseMainWindow() }
  }
  $deadline = (Get-Date).AddSeconds(20)
  while ((Get-Process -Name chrome -ErrorAction SilentlyContinue) -and (Get-Date) -lt $deadline) {
    Start-Sleep -Seconds 2
  }
  if (Get-Process -Name chrome -ErrorAction SilentlyContinue) {
    Stop-Process -Name chrome -Force -ErrorAction SilentlyContinue
    Start-Sleep -Seconds 2
  }
}

$work = Join-Path $env:TEMP ("chrome-profile-" + [guid]::NewGuid().ToString("N"))
$stagedProfile = Join-Path $work "User Data"
$zipPath = Join-Path $work "profile.zip"
$chromeFolder = Join-Path $MigrationPath "chrome"
$archivePath = Join-Path $chromeFolder "profile.enc"
$encryptedTemp = "$archivePath.tmp"
New-Item -ItemType Directory -Force -Path $stagedProfile,$chromeFolder | Out-Null

try {
  $chromeRoot = Join-Path $stagedProfile "Chrome\User Data"
  New-Item -ItemType Directory -Force -Path $chromeRoot | Out-Null
  Copy-Item (Join-Path $ProfilePath "Local State") $chromeRoot -Force
  $sourceDefault = Join-Path $ProfilePath "Default"
  $targetDefault = Join-Path $chromeRoot "Default"
  New-Item -ItemType Directory -Force -Path $targetDefault | Out-Null

  # Keep login-bearing profile files and session state while leaving bulky caches out.
  Get-ChildItem $sourceDefault -File -Force | Where-Object {
    $_.Name -notmatch '^(History($|-)|Favicons($|-)|LOCK|LOG($|\.)|DawnGraphiteCache|DawnWebGPUCache)'
  } | ForEach-Object { Copy-Item $_.FullName $targetDefault -Force -ErrorAction Stop }

  $keepDirectories = @(
    "Accounts", "Extension State", "IndexedDB", "Local Extension Settings",
    "Local Storage", "Network", "Session Storage", "Sessions",
    "Sessions_Encrypted", "Sync Data"
  )
  foreach ($name in $keepDirectories) {
    $source = Join-Path $sourceDefault $name
    if (Test-Path $source) {
      $target = Join-Path $targetDefault $name
      New-Item -ItemType Directory -Force -Path $target | Out-Null
      Get-ChildItem $source -Force | ForEach-Object {
        Copy-Item $_.FullName $target -Recurse -Force -ErrorAction Stop
      }
    }
  }

  # Preserve Codex login/config/session data but omit reinstallable packages and caches.
  if (Test-Path $CodexPath) {
    $codexRoot = Join-Path $stagedProfile "Codex"
    New-Item -ItemType Directory -Force -Path $codexRoot | Out-Null
    Get-ChildItem $CodexPath -Force | Where-Object {
      $_.Name -notin @("cache", "packages", "tmp", ".tmp", ".sandbox", ".sandbox-bin", ".sandbox-secrets", "logs")
    } | ForEach-Object { Copy-Item $_.FullName $codexRoot -Recurse -Force -ErrorAction Stop }
  }

  # Keep Spotify's per-user profile only; the app and Spicetify are installed on each runner.
  if (Test-Path $SpotifyPath) {
    $spotifyRoot = Join-Path $stagedProfile "Spotify"
    New-Item -ItemType Directory -Force -Path $spotifyRoot | Out-Null
    foreach ($name in @("Users", "prefs")) {
      $source = Join-Path $SpotifyPath $name
      if (Test-Path $source) { Copy-Item $source $spotifyRoot -Recurse -Force -ErrorAction Stop }
    }
  }

  Compress-Archive -Path (Join-Path $stagedProfile "*") -DestinationPath $zipPath -CompressionLevel Optimal -Force
  $plain = [IO.File]::ReadAllBytes($zipPath)
  $nonce = [byte[]]::new(12)
  $tag = [byte[]]::new(16)
  $cipher = [byte[]]::new($plain.Length)
  [Security.Cryptography.RandomNumberGenerator]::Fill($nonce)
  $aes = [Security.Cryptography.AesGcm]::new($key, 16)
  try { $aes.Encrypt($nonce, $plain, $cipher, $tag) } finally { $aes.Dispose() }

  $magic = [Text.Encoding]::ASCII.GetBytes("CHPF1")
  $stream = [IO.File]::Open($encryptedTemp, [IO.FileMode]::Create, [IO.FileAccess]::Write, [IO.FileShare]::None)
  try {
    $stream.Write($magic, 0, $magic.Length)
    $stream.Write($nonce, 0, $nonce.Length)
    $stream.Write($tag, 0, $tag.Length)
    $stream.Write($cipher, 0, $cipher.Length)
    $stream.Flush()
  } finally { $stream.Dispose() }
  Move-Item $encryptedTemp $archivePath -Force
  Write-Host "Encrypted Chrome profile snapshot saved: $([math]::Round((Get-Item $archivePath).Length / 1MB,1)) MiB."
} finally {
  Remove-Item $work -Recurse -Force -ErrorAction SilentlyContinue
  if (Test-Path $encryptedTemp) { Remove-Item $encryptedTemp -Force -ErrorAction SilentlyContinue }
  [Array]::Clear($key, 0, $key.Length)
}
