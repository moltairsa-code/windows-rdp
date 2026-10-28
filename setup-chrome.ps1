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
$taskName = "Restore Chrome settings for $rdpUser"
$powershellExe = Join-Path $env:SystemRoot "System32\WindowsPowerShell\v1.0\powershell.exe"
$taskArgs = "-NoProfile -ExecutionPolicy Bypass -File `"$restoreScript`" -MigrationPath `"$migration`""
$action = New-ScheduledTaskAction -Execute $powershellExe -Argument $taskArgs
$trigger = New-ScheduledTaskTrigger -AtLogOn -User $account
$principal = New-ScheduledTaskPrincipal -UserId $account -LogonType Interactive -RunLevel Limited
Register-ScheduledTask -TaskName $taskName -Action $action -Trigger $trigger -Principal $principal -Force | Out-Null

Write-Host "Chrome is installed and reusable settings will restore when $rdpUser signs in."
