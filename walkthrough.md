# Trace-Installer Walkthrough

The `Trace-Installer.ps1` script allows you to monitor an installer on Windows 11 and generate a clean uninstall script.

## Prerequisites
- **OS**: Windows 11 (or Windows 10)
- **PowerShell**: 5.1 or 7+
- **Privileges**: Administrator (Required for Registry access)
- **Execution Policy**: Must allow script execution (e.g., `RemoteSigned` or `Bypass`)

## Setup
If you receive a "running scripts is disabled" error, run the following command in an Administrator PowerShell window:

```powershell
Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope CurrentUser
```

Or run the script with bypass mode:
```powershell
powershell -ExecutionPolicy Bypass -File .\Trace-Installer.ps1 ...
```

## Usage

### 1. Basic Tracing
Open PowerShell as Administrator and run:

```powershell
.\Trace-Installer.ps1 -InstallerPath "C:\Path\To\Setup.exe"
```

The script will:
1. Take a baseline snapshot of the Registry (`HKLM:\SOFTWARE`, `HKCU:\Software`).
2. Start monitoring changes on the entire System Drive (`$env:SystemDrive`, usually `C:\`) recursively.
3. Launch the installer.
4. Wait for you to finish the installation.
5. Press **Enter** in the console when the installer is finished.
6. Generate `Uninstall-App.ps1`.

### 2. Automated Testing (with Dummy Installer)
A `Dummy-Installer.ps1` is provided for testing.

```powershell
.\Trace-Installer.ps1 -InstallerPath "powershell" -InstallerArgs "-File .\Dummy-Installer.ps1" -OutputPath "Uninstall-Dummy.ps1" -AutoExit
```

## Generated Uninstaller
The output script `Uninstall-App.ps1` will contain commands to:
- Remove created Registry Keys.
- Revert modified Registry Values.
- Delete created Files and Directories.

> [!WARNING]
> Always review the generated `Uninstall-App.ps1` before running it. While safety checks are in place, automated deletion carries risks.

## Limitations
- **Registry Snapshots**: Uses a recursive snapshot approach which may take 10-20 seconds before and after installation.
- **File System**: Monitors `$env:SystemDrive` recursively. High volume of events may occur on active systems.
