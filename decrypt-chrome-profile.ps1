param(
  [string]$ArchivePath = "D:\Migration\chrome\profile.enc",
  [string]$StagingPath = "C:\ProgramData\RunnerState",
  [string]$TargetUser = "rdpuser",
  [Parameter(Mandatory = $true)]
  [string]$EncryptionKey
)

$ErrorActionPreference = "Stop"
if (-not (Test-Path $ArchivePath)) {
  Write-Host "No encrypted Chrome profile archive found."
  exit 0
}

$key = [Convert]::FromBase64String($EncryptionKey)
if ($key.Length -ne 32) { throw "CHROME_PROFILE_KEY must decode to 32 bytes." }
$work = Join-Path $env:RUNNER_TEMP ("chrome-restore-" + [guid]::NewGuid().ToString("N"))
$zipPath = Join-Path $work "profile.zip"
$stagingRoot = Split-Path $StagingPath -Parent
try {
  $blob = [IO.File]::ReadAllBytes($ArchivePath)
  $magic = [Text.Encoding]::ASCII.GetBytes("CHPF1")
  if ($blob.Length -lt 33) { throw "Chrome profile archive is truncated." }
  for ($i = 0; $i -lt $magic.Length; $i++) {
    if ($blob[$i] -ne $magic[$i]) { throw "Chrome profile archive has an unknown format." }
  }

  $nonce = [byte[]]::new(12)
  $tag = [byte[]]::new(16)
  [Array]::Copy($blob, 5, $nonce, 0, 12)
  [Array]::Copy($blob, 17, $tag, 0, 16)
  $cipherLength = $blob.Length - 33
  $cipher = [byte[]]::new($cipherLength)
  $plain = [byte[]]::new($cipherLength)
  [Array]::Copy($blob, 33, $cipher, 0, $cipherLength)
  $aes = [Security.Cryptography.AesGcm]::new($key, 16)
  try { $aes.Decrypt($nonce, $cipher, $tag, $plain) } finally { $aes.Dispose() }

  Remove-Item $stagingRoot -Recurse -Force -ErrorAction SilentlyContinue
  New-Item -ItemType Directory -Force -Path $stagingRoot,$work | Out-Null
  [IO.File]::WriteAllBytes($zipPath, $plain)
  Expand-Archive -Path $zipPath -DestinationPath $stagingRoot -Force
  if (-not (Test-Path (Join-Path $StagingPath "Chrome\User Data\Local State"))) {
    throw "Decrypted Chrome profile is missing Local State."
  }

  $account = "$env:COMPUTERNAME\$TargetUser"
  & icacls.exe $stagingRoot /grant "${account}:(OI)(CI)RX" /T /C | Out-Host
  if ($LASTEXITCODE -ne 0) { throw "Could not grant $TargetUser access to the staged Chrome profile." }
  Write-Host "Encrypted Chrome profile decrypted and staged for $TargetUser's first logon."
} finally {
  Remove-Item $work -Recurse -Force -ErrorAction SilentlyContinue
  [Array]::Clear($key, 0, $key.Length)
}
