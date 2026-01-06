# Ralph Plan

[x] Research PowerShell methods for tracing file and registry changes (FileSystemWatcher, Registry Auditing, Snapshots).
[x] Create `Trace-Installer.ps1` scaffold.
[x] Implement File System monitoring (FileSystemWatcher).
[x] Implement Registry monitoring (Snapshot diff vs Polling).
[x] Implement Uninstaller generation logic.
[x] Verification: Create a dummy installer script for testing.
[x] Verification: Run Trace-Installer against dummy installer and verify Uninstall script. (Verified by User)
[x] Bluebeam Trace: Successfully traced Bluebeam Revu 21.8.0 installation (12k file events, 2.2k registry keys).
[x] Optimization: Implemented noise filtering, buffer overflow protection, and safety checks.
[x] Debugging: Fixed uninstaller syntax, encoding corruption, and shell-extension hangs.
[x] Final Uninstaller: Generated high-performance, sanitized uninstaller with Explorer restart and timeout guards.
[x] Tool Integration: Ported all uninstaller improvements back into `Trace-Installer.ps1`.
[x] Cleanup: Removed temporary testing and fix scripts from the repository.
