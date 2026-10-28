$ErrorActionPreference = "Stop"

$programFilesX86 = [Environment]::GetEnvironmentVariable("ProgramFiles(x86)")
$chromeCandidates = @(
  (Join-Path $env:ProgramFiles "Google\Chrome\Application\chrome.exe"),
  (Join-Path $programFilesX86 "Google\Chrome\Application\chrome.exe")
) | Where-Object { $_ -and (Test-Path $_) }

if (-not $chromeCandidates) {
  $installer = Join-Path $env:RUNNER_TEMP "chrome-enterprise-x64.msi"
  $installerUrl = "https://dl.google.com/dl/chrome/install/googlechromestandaloneenterprise64.msi"
  Write-Host "Downloading the official Chrome Enterprise installer."
  Invoke-WebRequest -Uri $installerUrl -OutFile $installer
  $install = Start-Process -FilePath "msiexec.exe" `
    -ArgumentList @("/i", "`"$installer`"", "/qn", "/norestart") `
    -Wait -PassThru
  if ($install.ExitCode -notin @(0, 3010)) {
    throw "Chrome MSI installation failed with exit code $($install.ExitCode)."
  }
}

$migration = $env:MIGRATION
if ([string]::IsNullOrWhiteSpace($migration)) { $migration = "D:\Migration" }
$restoreScript = Join-Path $migration "chrome\restore-profile.ps1"
$restoreSource = Join-Path $PSScriptRoot "restore-chrome-profile.ps1"
New-Item -ItemType Directory -Force -Path (Split-Path $restoreScript) | Out-Null
Copy-Item $restoreSource $restoreScript -Force

$rdpUser = $env:RDP_USER
if ([string]::IsNullOrWhiteSpace($rdpUser)) { $rdpUser = "rdpuser" }
$account = "$env:COMPUTERNAME\$rdpUser"
$taskName = "Restore Chrome profile for $rdpUser"
$powershellExe = Join-Path $env:SystemRoot "System32\WindowsPowerShell\v1.0\powershell.exe"
$chromeStage = Join-Path $env:ProgramData "RunnerState"
$taskArgs = "-NoProfile -ExecutionPolicy Bypass -File `"$restoreScript`" -SourceProfilePath `"$chromeStage`""
$action = New-ScheduledTaskAction -Execute $powershellExe -Argument $taskArgs
$trigger = New-ScheduledTaskTrigger -AtLogOn -User $account
$principal = New-ScheduledTaskPrincipal -UserId $account -LogonType Interactive -RunLevel Limited
Register-ScheduledTask -TaskName $taskName -Action $action -Trigger $trigger -Principal $principal -Force | Out-Null

$spotifyScript = Join-Path $migration "spotify\setup-user.ps1"
$spotifySource = Join-Path $PSScriptRoot "setup-spotify-user.ps1"
New-Item -ItemType Directory -Force -Path (Split-Path $spotifyScript) | Out-Null
Copy-Item $spotifySource $spotifyScript -Force

$spotifyTaskName = "Install Spotify and configure Spicetify for $rdpUser"
$spotifyTaskArgs = "-NoProfile -ExecutionPolicy Bypass -File `"$spotifyScript`" -WaitForLoginSeconds 120 -ProfileStatePath `"$env:ProgramData\RunnerState\Spotify`""
$spotifyAction = New-ScheduledTaskAction -Execute $powershellExe -Argument $spotifyTaskArgs
$spotifyTrigger = New-ScheduledTaskTrigger -AtLogOn -User $account
$spotifyPrincipal = New-ScheduledTaskPrincipal -UserId $account -LogonType Interactive -RunLevel Limited
Register-ScheduledTask -TaskName $spotifyTaskName -Action $spotifyAction -Trigger $spotifyTrigger -Principal $spotifyPrincipal -Force | Out-Null

Write-Host "Chrome profile restore and Spotify/Spicetify setup will run when $rdpUser signs in."
