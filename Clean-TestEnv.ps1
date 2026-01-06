# Clean-TestEnv.ps1
# Removes artifacts created by Dummy-Installer.ps1 to ensure a clean slate.

$AppName = "TestApp_TraceTest"
$InstallDir = Join-Path $env:APPDATA $AppName
$RegKey = "HKCU:\Software\$AppName"

Write-Host "Cleaning up Test Environment..." -ForegroundColor Yellow

# 1. Remove Directory
if (Test-Path $InstallDir) {
    Write-Host "Removing Directory: $InstallDir"
    Remove-Item -Path $InstallDir -Recurse -Force -ErrorAction SilentlyContinue
} else {
    Write-Host "Directory not found (Clean): $InstallDir" -ForegroundColor DarkGray
}

# 2. Remove Registry Key
if (Test-Path $RegKey) {
    Write-Host "Removing Registry Key: $RegKey"
    Remove-Item -Path $RegKey -Recurse -Force -ErrorAction SilentlyContinue
} else {
    Write-Host "Registry Key not found (Clean): $RegKey" -ForegroundColor DarkGray
}

Write-Host "Environment Cleaned." -ForegroundColor Green
