# app-tracer 🚀

A powerful PowerShell-based tool for tracing software installations and automatically generating clean uninstaller scripts.

## Overview

`Trace-Installer.ps1` monitors file system and registry changes during an installation process. It compares the system state before and after the installer runs, then generates a PowerShell script to reverse all identified changes, ensuring a clean removal of the application.

## Prerequisites

- **Windows PowerShell 5.1** or **PowerShell 7+**
- **Administrator Privileges:** Required for monitoring system-wide file and registry changes.

## Usage

### Basic Usage

To trace an installer and generate a default `Uninstall-App.ps1` script:

```powershell
.\Trace-Installer.ps1 -InstallerPath "C:\Path\To\Setup.exe"
```

### Advanced Usage

Specify a custom output path for the uninstaller and provide arguments to the installer:

```powershell
.\Trace-Installer.ps1 -InstallerPath "C:\Path\To\Setup.exe" -OutputPath "Uninstall-MySoftware.ps1" -InstallerArgs "/S"
```

### Parameters

- `-InstallerPath`: (Mandatory) The full path to the executable installer.
- `-OutputPath`: The path where the generated uninstaller script will be saved. (Default: `Uninstall-App.ps1`)
- `-InstallerArgs`: Any command-line arguments to pass to the installer (e.g., `/S` for silent install).
- `-AutoExit`: If specified, the script will wait for the installer process to exit automatically before proceeding. If not specified, it will wait for user input (Press Enter) to stop tracing.

## How it Works

1. **Pre-Snapshot:** Captures the current state of `HKLM:\SOFTWARE` and `HKCU:\Software`.
2. **Monitoring:** Sets up `FileSystemWatcher` instances on the system drive (excluding noisy system folders).
3. **Execution:** Launches the specified installer.
4. **Post-Snapshot:** Captures the registry state after installation is complete.
5. **Comparison:** Identifies new/modified files and registry keys.
6. **Generation:** Produces a robust PowerShell script that restarts Explorer (to release locks), removes registry entries, and deletes files.

## Caution ⚠️

Always review the generated uninstaller script before execution, especially in production environments. The script includes safety checks for sensitive system paths, but manual verification is recommended.
