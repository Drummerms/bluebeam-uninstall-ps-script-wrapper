# Installer Tracer and Uninstaller Generator Plan

## Goal Description
Create a script `Trace-Installer.ps1` that monitors a Windows executable installer and records all file and registry changes. After installation, it generates a custom `Uninstall-App.ps1` script to remove all traces of the application.

## User Review Required
> [!IMPORTANT]
> **Registry Monitoring Strategy**: Real-time registry monitoring (recording *every* intermediate read/write) in pure PowerShell without external drivers (like Sysmon) is performance-prohibitive and unreliable. This solution will use **Registry Snapshots (Before/After)** to detect changes. This satisfies the goal of removing *created* artifacts but technically captures the "net change" rather than a continuous stream of registry operations.
>
> **File Monitoring Strategy**: We will use `System.IO.FileSystemWatcher` for real-time file monitoring on the entire System Drive (`$env:SystemDrive`) recursively to capture all changes. Events will be queued and processed after installation.

## Proposed Changes

### Scripts

#### [NEW] [Trace-Installer.ps1](file:///Users/michaelsablatura/Github/bluebeam-uninstall-ps-script-wrapper/Trace-Installer.ps1)
The main script that:
1.  Takes a pre-install Registry Snapshot (HKLM:\SOFTWARE, HKCU:\Software).
2.  Starts background jobs or runspaces for `FileSystemWatcher` on key directories.
3.  Launches the target executable using `Start-Process -Wait`.
4.  Stops monitoring.
5.  Takes a post-install Registry Snapshot and compares.
6.  Generates the `Uninstall-App.ps1` script based on the diffs.

#### [NEW] [Uninstall-Template.ps1](file:///Users/michaelsablatura/Github/bluebeam-uninstall-ps-script-wrapper/Uninstall-Template.ps1)
(Optional) A template or inline here-string used to generate the uninstaller.

## Verification Plan

### Automated Tests
- Create a `Dummy-Installer.ps1` that:
    - Creates a directory in `AppData` (`TestApp_TraceTest`).
    - Creates files within that directory.
    - Adds a Registry Key `HKCU\Software\TestApp_TraceTest`.
- Run `Trace-Installer.ps1` against this dummy installer.
- Verify `Uninstall-TestApp.ps1` is generated.
- Run `Uninstall-TestApp.ps1` and verify artifacts are gone.

### Manual Verification
- Review the generated script to ensure no system-critical paths are targeted for deletion (Safety whitelist).
