<#
.SYNOPSIS
    Traces an installer exe and generates an uninstaller script.

.DESCRIPTION
    This script monitors file system changes and registry changes while an executable is running.
    It takes a pre-snapshot of the registry and sets up FileSystemWatchers before launching the installer.
    After the installer finishes, it takes a post-snapshot of the registry.
    Finally, it compares the data and generates a PowerShell script to reverse the changes.

.PARAMETER InstallerPath
    The path to the executable installer to trace.

.PARAMETER OutputPath
    The path to save the generated uninstall script. Default is 'Uninstall-App.ps1'.

.EXAMPLE
    .\Trace-Installer.ps1 -InstallerPath "C:\Downloads\Setup.exe"
#>

param(
    [Parameter(Mandatory = $true)]
    [string]$InstallerPath,

    [string]$OutputPath = "Uninstall-App.ps1",
    [string]$InstallerArgs,
    [switch]$AutoExit
)

# --- Configuration ---
$MonitoredHives = @("HKLM:\SOFTWARE", "HKCU:\Software")


# Monitor the entire System Drive but exclude noisy system folders
# Note: This can generate a high volume of events.
$MonitoredPaths = @(
    "$env:SystemDrive\" 
)

# Paths to ignore events from (Starts With check)
$IgnoredPaths = @(
    "$env:SystemRoot\Temp",
    "$env:SystemRoot\Prefetch",
    "$env:SystemRoot\Logs",
    "$env:SystemRoot\ServiceProfiles",
    "$env:ProgramData\Microsoft\Windows\WER"
)

# --- Helper Functions ---

function Get-RegistrySnapshot {
    param([string[]]$Hives)
    Write-Host "Taking Registry Snapshot (this may take a moment)..." -ForegroundColor Cyan
    $Snapshot = @{}
    
    foreach ($HiveStr in $Hives) {
        # Map Hive String to .NET RegistryHive
        $BaseKey = $null
        $SubKeyPath = ""
        
        if ($HiveStr -match "HKLM:\\(.*)") {
            $BaseKey = [Microsoft.Win32.Registry]::LocalMachine
            $SubKeyPath = $matches[1]
        }
        elseif ($HiveStr -match "HKCU:\\(.*)") {
            $BaseKey = [Microsoft.Win32.Registry]::CurrentUser
            $SubKeyPath = $matches[1]
        }
        
        if ($BaseKey) {
            Write-Host "  Snapshotting: $HiveStr" -ForegroundColor DarkGray
            
            # Queue for recursion: Tuple(KeyPath, RegistryKeyObject)
            $Queue = [System.Collections.Generic.Queue[Object]]::new()
            
            try {
                $Root = $BaseKey.OpenSubKey($SubKeyPath, $false) # Read-only
                if ($Root) {
                    $Queue.Enqueue(@{ Path = $HiveStr; Key = $Root })
                }
            }
            catch {
                Write-Warning "Could not open root key: $HiveStr"
            }
            
            while ($Queue.Count -gt 0) {
                $Node = $Queue.Dequeue()
                $CurrentPath = $Node.Path
                $CurrentKey = $Node.Key
                
                try {
                    $ValueNames = $CurrentKey.GetValueNames()
                    $Values = @{}
                    
                    if ($ValueNames.Count -gt 0) {
                        foreach ($Name in $ValueNames) {
                            $Values[$Name] = $CurrentKey.GetValue($Name, $null, [Microsoft.Win32.RegistryValueOptions]::DoNotExpandEnvironmentNames)
                        }
                    }
                    $Snapshot[$CurrentPath] = $Values

                    # Enqueue Subkeys
                    $SubKeyNames = $CurrentKey.GetSubKeyNames()
                    foreach ($Name in $SubKeyNames) {
                        try {
                            $NextKey = $CurrentKey.OpenSubKey($Name, $false)
                            if ($NextKey) {
                                $Queue.Enqueue(@{ Path = "$CurrentPath\$Name"; Key = $NextKey })
                            }
                        }
                        catch { 
                            # Access denied to subkey
                        }
                    }
                }
                catch {
                    # Write-Warning "Error reading key: $CurrentPath"
                }
                finally {
                    # IMPORTANT: We must NOT dispose the key if we just passed it to the queue?
                    # Actually, we dequeue, process, enque children, then we can dispose the CURRENT key object?
                    # The root key needs to be closed at the end.
                    # With OpenSubKey, we get a new object. We should dispose it after we are done with it and its children are enqueued?
                    # No, we need the parent to open the child? No, OpenSubKey opens relative to current.
                    
                    # Optimization: In .NET Registry, we are holding handles.
                    # To be safe and simple, let GC handle it or explicit dispose.
                    if ($CurrentKey -ne $Root) {
                        $CurrentKey.Dispose()
                    }
                }
            }
            
            if ($Root) { $Root.Dispose() }
        }
    }
    
    Write-Host "  Snapshot complete. Captured $($Snapshot.Count) keys." -ForegroundColor DarkGray
    return $Snapshot
}


function Start-FileMonitoring {
    param([string[]]$Paths, [string[]]$IgnoredPaths)
    Write-Host "Starting File System Monitoring..." -ForegroundColor Cyan
    
    # Thread-safe queue to store events from multiple watchers
    $EventQueue = [System.Collections.Concurrent.ConcurrentQueue[PSCustomObject]]::new()
    $Watchers = @()
    $Subscribers = @()

    # Action block for handling events
    $Action = {
        $Queue = $Event.MessageData.Queue
        $Ignored = $Event.MessageData.IgnoredPaths
        $SourceEventArgs = $Event.SourceEventArgs
        
        $EventType = $SourceEventArgs.ChangeType
        $FullPath = $SourceEventArgs.FullPath
        
        # Fast Noise Filtering
        $Skip = $false
        foreach ($Ignore in $Ignored) {
            if ($FullPath.StartsWith($Ignore, [System.StringComparison]::OrdinalIgnoreCase)) {
                $Skip = $true
                break
            }
        }
        
        if (-not $Skip) {
            $OldPath = $null
            if ($EventType -eq 'Renamed') {
                $OldPath = $SourceEventArgs.OldFullPath
            }
            
            $EventData = [PSCustomObject]@{
                Timestamp = [DateTime]::Now
                Type      = $EventType
                Path      = $FullPath
                OldPath   = $OldPath
            }
            $Queue.Enqueue($EventData)
        }
    }

    # Error Action
    $ErrorAction = {
        $Exception = $Event.SourceEventArgs.GetException()
        Write-Warning "FileSystemWatcher Error: $($Exception.Message)"
        if ($Exception.GetType().Name -eq "InternalBufferOverflowException") {
            Write-Warning "BUFFER OVERFLOW detected! Some file events were lost. Try increasing buffer size or reducing scope."
        }
    }

    foreach ($Path in $Paths) {
        if (Test-Path -Path $Path) {
            Write-Host "  Monitoring: $Path" -ForegroundColor DarkGray
            try {
                $Watcher = New-Object System.IO.FileSystemWatcher
                $Watcher.Path = $Path
                $Watcher.IncludeSubdirectories = $true
                $Watcher.InternalBufferSize = 65536 # 64KB buffer
                
                # Bundle data for the action
                $MessageData = [PSCustomObject]@{
                    Queue        = $EventQueue
                    IgnoredPaths = $IgnoredPaths
                }

                # Register for specific events
                $Subscribers += Register-ObjectEvent -InputObject $Watcher -EventName Created -Action $Action -MessageData $MessageData
                $Subscribers += Register-ObjectEvent -InputObject $Watcher -EventName Changed -Action $Action -MessageData $MessageData
                $Subscribers += Register-ObjectEvent -InputObject $Watcher -EventName Deleted -Action $Action -MessageData $MessageData
                $Subscribers += Register-ObjectEvent -InputObject $Watcher -EventName Renamed -Action $Action -MessageData $MessageData
                $Subscribers += Register-ObjectEvent -InputObject $Watcher -EventName Error   -Action $ErrorAction -MessageData $MessageData
                
                $Watcher.EnableRaisingEvents = $true
                $Watchers += $Watcher
            }
            catch {
                Write-Warning "Failed to setup watcher for $Path : $_"
            }
        }
    }
    
    return [PSCustomObject]@{
        Watchers    = $Watchers
        Subscribers = $Subscribers
        Queue       = $EventQueue
    }
}

function Stop-FileMonitoring {
    param($MonitoringContext)
    Write-Host "Stopping File System Monitoring..." -ForegroundColor Cyan
    
    # 1. Disable raising events
    foreach ($Watcher in $MonitoringContext.Watchers) {
        $Watcher.EnableRaisingEvents = $false
        $Watcher.Dispose()
    }

    # 2. Unregister subscribers
    foreach ($Subscriber in $MonitoringContext.Subscribers) {
        Unregister-Event -SubscriptionId $Subscriber.Id
    }

    # 3. Drain Queue
    $Events = @()
    $Queue = $MonitoringContext.Queue
    while ($Queue.Count -gt 0) {
        $Item = $null
        if ($Queue.TryDequeue([ref]$Item)) {
            $Events += $Item
        }
    }
    
    Write-Host "Captured $($Events.Count) file system events." -ForegroundColor Gray
    return $Events
}

function Compare-RegistrySnapshots {
    param($Pre, $Post)
    Write-Host "Comparing Registry Snapshots ($($Post.Count) keys)..." -ForegroundColor Cyan
    
    $CreatedKeys = [System.Collections.Generic.List[string]]::new()
    $DeletedKeys = [System.Collections.Generic.List[string]]::new()
    $ModifiedValues = [System.Collections.Generic.List[Object]]::new()
    
    $Counter = 0
    $Total = $Post.Count
    $ReportInterval = [Math]::Max(1, [int]($Total / 100)) # Report every 1%

    # 1. Check for Created Keys (In Post but not Pre)
    foreach ($Key in $Post.Keys) {
        $Counter++
        if ($Counter % $ReportInterval -eq 0) {
            Write-Progress -Activity "Comparing Registry" -Status "Processing Key $Counter of $Total" -PercentComplete (($Counter / $Total) * 100)
        }

        if (-not $Pre.ContainsKey($Key)) {
            $CreatedKeys.Add($Key)
        }
        else {
            # Key exists in both, check values
            $PreValues = $Pre[$Key]
            $PostValues = $Post[$Key]
            
            # Optimization: If counts differ, something changed. 
            # If counts match, we still need to check content.
            
            foreach ($ValName in $PostValues.Keys) {
                # If value is new or changed
                # Note: comparing arrays (REG_BINARY) with -ne might be incorrect (reference eq), 
                # but for simple uninstallers, we mostly care about strings/dwords.
                # For byte arrays, -ne compares reference, so it defaults to "changed", which is safe (false positive).
                
                if (-not $PreValues.ContainsKey($ValName)) {
                    $ModifiedValues.Add([PSCustomObject]@{
                            Key       = $Key
                            ValueName = $ValName
                            Value     = $PostValues[$ValName]
                        })
                }
                elseif ($null -eq $PreValues[$ValName]) {
                    if ($null -ne $PostValues[$ValName]) {
                        $ModifiedValues.Add([PSCustomObject]@{
                                Key       = $Key
                                ValueName = $ValName
                                Value     = $PostValues[$ValName]
                            })
                    }
                }
                elseif ($PreValues[$ValName].GetType().IsArray) {
                    # Simple array comparison
                    $P = $PreValues[$ValName]
                    $N = $PostValues[$ValName]
                    if (($null -eq $N) -or ($P.Length -ne $N.Length) -or (Compare-Object $P $N -SyncWindow 0)) {
                        $ModifiedValues.Add([PSCustomObject]@{
                                Key       = $Key
                                ValueName = $ValName
                                Value     = $PostValues[$ValName]
                            })
                    }
                }
                elseif ($PreValues[$ValName] -ne $PostValues[$ValName]) {
                    $ModifiedValues.Add([PSCustomObject]@{
                            Key       = $Key
                            ValueName = $ValName
                            Value     = $PostValues[$ValName]
                        })
                }
            }
        }
    }
    Write-Progress -Activity "Comparing Registry" -Completed

    # 2. Check for Deleted Keys (In Pre but not Post)
    # This is another O(N) loop. 
    # Only run if needed? Yes, let's run it but fast.
    $PreKeys = $Pre.Keys
    $PreCount = $PreKeys.Count
    $pCounter = 0
    
    foreach ($Key in $PreKeys) {
        $pCounter++
        if ($pCounter % 10000 -eq 0) {
            Write-Progress -Activity "Checking for Deleted Keys" -Status "$pCounter / $PreCount" -PercentComplete (($pCounter / $PreCount) * 100)
        }
        if (-not $Post.ContainsKey($Key)) {
            $DeletedKeys.Add($Key)
        }
    }
    Write-Progress -Activity "Checking for Deleted Keys" -Completed
    
    return @{
        CreatedKeys    = $CreatedKeys
        DeletedKeys    = $DeletedKeys
        ModifiedValues = $ModifiedValues
    }
}


function New-Uninstaller {
    param($FileEvents, $RegistryDiff, $OutputPath)
    Write-Host "Generating Uninstaller at $OutputPath..." -ForegroundColor Green
    
    $Sb = [System.Text.StringBuilder]::new()
    
    $Sb.AppendLine("# Uninstaller Script Generated by Trace-Installer.ps1") | Out-Null
    $Sb.AppendLine("# Generated on: $(Get-Date)") | Out-Null
    $Sb.AppendLine("# CAUTION: Review this script before running.") | Out-Null
    $Sb.AppendLine("") | Out-Null
    $Sb.AppendLine("Write-Host 'Starting Uninstall...' -ForegroundColor Cyan") | Out-Null
    $Sb.AppendLine("`$ErrorActionPreference = 'SilentlyContinue'") | Out-Null
    $Sb.AppendLine("") | Out-Null

    # --- Registry Removal ---
    $Sb.AppendLine("# --- Registry Cleanup ---") | Out-Null

    $Sb.AppendLine(@"
# Ensure explorer doesn't lock shell extensions
Write-Host "Restarting Explorer to release locks..." -ForegroundColor Cyan
Stop-Process -Name explorer -Force -ErrorAction SilentlyContinue
Start-Sleep -Seconds 2
"@) | Out-Null
    
    # 1. remove created keys (Optimized to Root Trees)
    # Optimization: Filter for root keys created during install
    $CreatedKeys = $RegistryDiff.CreatedKeys | Sort-Object Length
    $RootKeys = [System.Collections.Generic.List[string]]::new()
    foreach ($key in $CreatedKeys) {
        $isSub = $false
        foreach ($root in $RootKeys) {
            if ($key.StartsWith($root + "\", [System.StringComparison]::OrdinalIgnoreCase)) {
                $isSub = $true
                break
            }
        }
        if (-not $isSub) { $RootKeys.Add($key) }
    }

    $Sb.AppendLine("`$RegKeys = @(") | Out-Null
    foreach ($k in $RootKeys) { $Sb.AppendLine("    '$($k -replace "'", "''")'") | Out-Null }
    $Sb.AppendLine(")") | Out-Null

    $Sb.AppendLine(@"
Write-Host "Cleaning Registry ($($RootKeys.Count) root keys)..."
foreach (`$key in `$RegKeys) {
    Write-Host "Removing: `$key" -ForegroundColor Gray
    # Only use slow safety timeout for shell extensions or if it's in a known sensitive area
    if (`$key -match "ShellEx|ContextMenuHandlers|InprocServer32") {
        `$job = Start-Job -ScriptBlock { param(`$path) Remove-Item -Path `$path -Recurse -Force } -ArgumentList `$key
        if (`$job | Wait-Job -Timeout 5) {
            Receive-Job `$job
        } else {
            Write-Warning "Timed out removing `$key. It might be locked."
            Stop-Job `$job
        }
        Remove-Job `$job
    } else {
        Remove-Item -Path `$key -Recurse -Force -ErrorAction SilentlyContinue
    }
}
Write-Host "Restarting Explorer..." -ForegroundColor Cyan
Start-Process explorer
"@) | Out-Null

    # 2. Revert modified values
    foreach ($Mod in $RegistryDiff.ModifiedValues) {
        $Key = $Mod.Key
        $Name = $Mod.ValueName
        $Value = $Mod.Value
        
        $Sb.AppendLine("Write-Host 'Reverting Registry Value: $Key\$Name'") | Out-Null
        
        if ($Value -is [string]) {
            # Escape single quotes and handle potential carriage returns
            $SafeValue = ($Value -replace "'", "''") -replace "`r", ""
            $Sb.AppendLine("Set-ItemProperty -Path '$Key' -Name '$Name' -Value '$SafeValue' -Force") | Out-Null
        }
        elseif ($Value -is [bool]) {
            # Boolean needs $true/$false
            $BoolStr = if ($Value) { "`$true" } else { "`$false" }
            $Sb.AppendLine("Set-ItemProperty -Path '$Key' -Name '$Name' -Value $BoolStr -Force") | Out-Null
        }
        elseif ($Value.GetType().IsArray) {
            # Array handling: Convert to @('v1', 'v2')
            $Elements = @()
            foreach ($item in $Value) {
                if ($null -eq $item) { continue }
                if ($item -is [string]) {
                    # Escape single quotes and wrap in single quotes
                    $esc = ($item -replace "'", "''") -replace "`r", ""
                    $Elements += "'$esc'"
                }
                else {
                    $Elements += $item.ToString()
                }
            }
            $ValStr = $Elements -join ", "
            $Sb.AppendLine("Set-ItemProperty -Path '$Key' -Name '$Name' -Value @($ValStr) -Force") | Out-Null
        }
        else {
            # For numbers, etc.
            $Sb.AppendLine("Set-ItemProperty -Path '$Key' -Name '$Name' -Value $Value -Force") | Out-Null
        }
    }
    $Sb.AppendLine("") | Out-Null

    # --- File Removal ---
    $Sb.AppendLine("# --- File Cleanup ---") | Out-Null
    
    # Process Creation events
    # We need to filter out things that were created and then deleted?
    # Or just try to delete everything that was created. 
    # Also, we should unique the paths.
    
    $CreatedFiles = $FileEvents | Where-Object { $_.Type -eq 'Created' } | Select-Object -ExpandProperty Path -Unique
    $RenamedFiles = $FileEvents | Where-Object { $_.Type -eq 'Renamed' } | Select-Object -ExpandProperty Path -Unique
    
    $AllPathsToRemove = $CreatedFiles + $RenamedFiles | Select-Object -Unique
    
    # Sort by length descending to delete files inside folders before folders
    $AllPathsToRemove = $AllPathsToRemove | Sort-Object Length -Descending

    foreach ($Path in $AllPathsToRemove) {
        # Safety check: Don't delete C:\, C:\Windows, etc.
        if ($Path -match "^[A-Za-z]:\\$" -or $Path -eq "$env:SystemRoot" -or $Path -eq "$env:SystemRoot\System32") {
            Write-Warning "Skipping dangerous path removal: $Path"
            continue 
        }
        
        # Extra Safety: Check against important system folders
        if ($Path.StartsWith("$env:SystemRoot\System32", [System.StringComparison]::OrdinalIgnoreCase) -and -not $Path.Contains("Bluebeam")) {
            # If it's in System32 and doesn't explicitly look like it belongs to our app (heuristic), warn/comment out
            $Sb.AppendLine("# WARNING: Safety Skip for System32 file (Manual Review Needed): $Path") | Out-Null
            $Sb.AppendLine("# if (Test-Path '$Path') { Remove-Item -Path '$Path' -Force }") | Out-Null
            continue
        }

        if ($Path -match "^[A-Za-z]:\\$" -or $Path -eq "C:\Windows") {
            continue 
        }

        $Sb.AppendLine("Write-Host 'Removing: $Path'") | Out-Null
        $Sb.AppendLine("if (Test-Path '$Path') { Remove-Item -Path '$Path' -Recurse -Force -ErrorAction SilentlyContinue }") | Out-Null
    }

    $Sb.AppendLine("") | Out-Null
    $Sb.AppendLine("Write-Host 'Uninstall Complete.' -ForegroundColor Green") | Out-Null

    Set-Content -Path $OutputPath -Value $Sb.ToString()
}

# --- Main Execution ---

try {
    Write-Host "Starting Trace for: $InstallerPath" -ForegroundColor Green

    # 1. Pre-Installation Snapshot
    $PreRegSnapshot = Get-RegistrySnapshot -Hives $MonitoredHives

    # 2. Start File Monitoring
    $MonitoringContext = Start-FileMonitoring -Paths $MonitoredPaths -IgnoredPaths $IgnoredPaths

    # 3. Launch Installer
    Write-Host "Launching Installer..." -ForegroundColor Yellow
    
    $Command = Get-Command -Name $InstallerPath -ErrorAction SilentlyContinue
    
    if (Test-Path $InstallerPath -PathType Leaf) {
        if (-not [string]::IsNullOrWhiteSpace($InstallerArgs)) {
            $Process = Start-Process -FilePath $InstallerPath -ArgumentList $InstallerArgs -PassThru
        }
        else {
            $Process = Start-Process -FilePath $InstallerPath -PassThru
        }
        Write-Host "Installer PID: $($Process.Id)" -ForegroundColor DarkGray
    }
    elseif ($Command) {
        # It's a command on the PATH
        if (-not [string]::IsNullOrWhiteSpace($InstallerArgs)) {
            $Process = Start-Process -FilePath $InstallerPath -ArgumentList $InstallerArgs -PassThru
        }
        else {
            $Process = Start-Process -FilePath $InstallerPath -PassThru
        }
        Write-Host "Installer PID: $($Process.Id)" -ForegroundColor DarkGray
    }
    else {
        Write-Warning "Installer not found at '$InstallerPath' and not a valid command."
    }

    if ($Process) {
        if ($Process.HasExited) {
            Write-Host "Installer exited immediately." -ForegroundColor Yellow
        }
        
        if ($AutoExit) {
            Write-Host "Waiting for installer process ($($Process.Id)) to exit..." -ForegroundColor Yellow
            $Process.WaitForExit()
            Write-Host "Installer process exited." -ForegroundColor Green
        }
        else {
            Read-Host "Press Enter when installation is complete"
        }
    }
    else {
        Read-Host "Press Enter to stop tracing (Installer execution failed or skipped)"
    }

    # 4. Stop File Monitoring
    $FileEvents = Stop-FileMonitoring -MonitoringContext $MonitoringContext

    # 5. Post-Installation Snapshot
    $PostRegSnapshot = Get-RegistrySnapshot -Hives $MonitoredHives

    # 6. Compare Registry
    $RegistryDiff = Compare-RegistrySnapshots -Pre $PreRegSnapshot -Post $PostRegSnapshot

    # 7. Generate Script
    New-Uninstaller -FileEvents $FileEvents -RegistryDiff $RegistryDiff -OutputPath $OutputPath

    Write-Host "Done." -ForegroundColor Green
}
catch {
    Write-Error "An error occurred: $_"
    Write-Error "$($_.ScriptStackTrace)"
}
