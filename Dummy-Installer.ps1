# Dummy-Installer.ps1
# Simulates an installation process by creating files and registry keys.

$AppName = "TestApp_TraceTest"
$InstallDir = Join-Path $env:APPDATA $AppName
$RegKey = "HKCU:\Software\$AppName"

Write-Host "Simulating Installation of $AppName..." -ForegroundColor Cyan

# 1. Create Directory
if (-not (Test-Path $InstallDir)) {
    Write-Host "Creating Directory: $InstallDir"
    New-Item -Path $InstallDir -ItemType Directory -Force | Out-Null
}

# 2. Create Files
Write-Host "Creating Files..."
Set-Content -Path (Join-Path $InstallDir "config.ini") -Value "[Settings]`nMode=Test"
Set-Content -Path (Join-Path $InstallDir "readme.txt") -Value "This is a test app."

# 3. Create Registry Key
Write-Host "Creating Registry Key: $RegKey"
if (-not (Test-Path $RegKey)) {
    New-Item -Path $RegKey -Force | Out-Null
}
Set-ItemProperty -Path $RegKey -Name "Version" -Value "1.0.0"
Set-ItemProperty -Path $RegKey -Name "InstallDate" -Value (Get-Date).ToString()

Write-Host "Installation Complete." -ForegroundColor Green
Start-Sleep -Seconds 2 # Keeping it open briefly
