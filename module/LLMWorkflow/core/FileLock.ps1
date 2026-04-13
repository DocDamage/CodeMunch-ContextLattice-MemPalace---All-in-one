#requires -Version 5.1
<#
.SYNOPSIS
    File Locking and Concurrency Control for LLM Workflow platform.

.DESCRIPTION
    Provides cross-platform file locking with stale lock detection and safe reclamation.
    Implements the state safety invariant requirements from IMPROVEMENT_PROPOSALS.md section 6.4.

.NOTES
    File: FileLock.ps1
    Version: 1.1.0
    Author: LLM Workflow Team

.EXAMPLE
    # Acquire lock
    try {
        $lock = Lock-File -Name "sync" -TimeoutSeconds 30
        # Do work
    } finally {
        Unlock-File -Name "sync"
    }
#>

Set-StrictMode -Version Latest

# Script-level variables for lock tracking
$script:AcquiredLocks = @{}

<#
.SYNOPSIS
    Converts a PSCustomObject to a hashtable recursively.
.DESCRIPTION
    Helper function to provide compatibility with PowerShell 5.1 which doesn't
    support the -AsHashtable parameter on ConvertFrom-Json.
.PARAMETER InputObject
    The object to convert.
.OUTPUTS
    System.Collections.Hashtable
#>
function ConvertTo-Hashtable {
    [CmdletBinding()]
    param([Parameter(ValueFromPipeline = $true)]$InputObject)
    
    process {
        if ($null -eq $InputObject) { return $null }
        
        if ($InputObject -is [System.Collections.IEnumerable] -and $InputObject -isnot [string]) {
            $collection = @()
            foreach ($item in $InputObject) {
                $collection += (ConvertTo-Hashtable -InputObject $item)
            }
            return $collection
        }
        elseif ($InputObject -is [System.Management.Automation.PSCustomObject]) {
            $hash = @{}
            foreach ($property in $InputObject.PSObject.Properties) {
                $hash[$property.Name] = (ConvertTo-Hashtable -InputObject $property.Value)
            }
            return $hash
        }
        else {
            return $InputObject
        }
    }
}
$script:LockSchemaVersion = 1
$script:ValidLockNames = @('sync', 'heal', 'index', 'ingest', 'pack')

<#
.SYNOPSIS
    Validates a lock name against the canonical list.

.DESCRIPTION
    Ensures the lock name is one of the valid subsystem locks defined in section 4.2.

.PARAMETER Name
    The lock name to validate.

.OUTPUTS
    System.Boolean. True if valid, false otherwise.
#>
function Test-LockName {
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Name
    )

    return $script:ValidLockNames -contains $Name
}

<#
.SYNOPSIS
    Gets the path to the lock directory.

.DESCRIPTION
    Returns the canonical lock directory path as defined in section 4.2 of IMPROVEMENT_PROPOSALS.md.
    Creates the directory if it does not exist.

.PARAMETER ProjectRoot
    The project root directory. Defaults to current directory.

.OUTPUTS
    System.String. The full path to the locks directory.
#>
function Get-LockDirectory {
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [string]$ProjectRoot = "."
    )

    $resolvedRoot = Resolve-Path -Path $ProjectRoot -ErrorAction SilentlyContinue
    if (-not $resolvedRoot) {
        $resolvedRoot = $ProjectRoot
    }

    $lockDir = Join-Path $resolvedRoot ".llm-workflow\locks"
    
    if (-not (Test-Path -LiteralPath $lockDir)) {
        try {
            New-Item -ItemType Directory -Path $lockDir -Force | Out-Null
            Write-Verbose "[FileLock] Created lock directory: $lockDir"
        }
        catch {
            throw "Failed to create lock directory: $lockDir. Error: $_"
        }
    }

    return $lockDir
}

<#
.SYNOPSIS
    Creates the lock file content structure.

.DESCRIPTION
    Generates the JSON lock file content with all required metadata per section 6.4.

.PARAMETER RunId
    The run identifier. If not provided, a new one is generated.

.OUTPUTS
    System.Collections.Hashtable. The lock content structure.
#>
function New-LockContent {
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [string]$RunId = ""
    )

    if ([string]::IsNullOrWhiteSpace($RunId)) {
        $RunId = New-RunId
    }

    $hostname = [Environment]::MachineName
    if ([string]::IsNullOrWhiteSpace($hostname)) {
        $hostname = "unknown"
    }

    return @{
        schemaVersion = $script:LockSchemaVersion
        pid = $PID
        host = $hostname.ToLowerInvariant()
        executionMode = Get-ExecutionMode
        runId = $RunId
        timestamp = [DateTime]::UtcNow.ToString("yyyy-MM-ddTHH:mm:ssZ")
        user = [Environment]::UserName
    }
}

<#
.SYNOPSIS
    Gets the full path to a lock file.

.DESCRIPTION
    Constructs the canonical lock file path for a given lock name.

.PARAMETER Name
    The lock name (e.g., sync, heal, index, ingest, pack).

.PARAMETER ProjectRoot
    The project root directory. Defaults to current directory.

.OUTPUTS
    System.String. The full path to the lock file.
#>
function Get-LockFilePath {
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Name,
        
        [string]$ProjectRoot = "."
    )

    if (-not (Test-LockName -Name $Name)) {
        throw "Invalid lock name: $Name. Valid names are: $($script:ValidLockNames -join ', ')"
    }

    $lockDir = Get-LockDirectory -ProjectRoot $ProjectRoot
    return Join-Path $lockDir "$Name.lock"
}

<#
.SYNOPSIS
    Acquires a file lock with timeout support.

.DESCRIPTION
    Attempts to acquire a lock for a subsystem. Waits up to TimeoutSeconds for the lock
    to become available. Implements atomic lock creation with proper error handling.

.PARAMETER Name
    The lock name (e.g., sync, heal, index, ingest, pack).

.PARAMETER TimeoutSeconds
    Maximum time to wait for the lock. Default is 30 seconds. Use 0 for no wait.

.PARAMETER ProjectRoot
    The project root directory. Defaults to current directory.

.PARAMETER RunId
    Optional run identifier. If not provided, one is generated.

.PARAMETER Force
    Force acquire even if already held by this process (for nested locks).

.OUTPUTS
    PSObject. Lock information object with Name, Path, RunId, AcquiredAt properties.

.EXAMPLE
    $lock = Lock-File -Name "sync" -TimeoutSeconds 30
    try {
        # Perform synchronized work
    } finally {
        Unlock-File -Name "sync"
    }

.EXAMPLE
    # Non-blocking lock attempt
    $lock = Lock-File -Name "index" -TimeoutSeconds 0
    if ($lock) {
        # Got the lock
    }
#>
function Lock-File {
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Name,
        
        [ValidateRange(0, 3600)]
        [int]$TimeoutSeconds = 30,
        
        [string]$ProjectRoot = ".",
        
        [string]$RunId = "",
        
        [switch]$Force
    )

    # Validate lock name
    if (-not (Test-LockName -Name $Name)) {
        throw "Invalid lock name: $Name. Valid names are: $($script:ValidLockNames -join ', ')"
    }

    $lockPath = Get-LockFilePath -Name $Name -ProjectRoot $ProjectRoot
    $startTime = [DateTime]::Now
    $acquired = $false
    $lockContent = $null
    $myRunId = if ([string]::IsNullOrWhiteSpace($RunId)) { New-RunId } else { $RunId }

    Write-Verbose "[FileLock] Attempting to acquire lock '$Name' (RunId: $myRunId, PID: $PID, Host: $([Environment]::MachineName.ToLowerInvariant()))"

    # Check if we already hold this lock
    if ($script:AcquiredLocks.ContainsKey($Name) -and -not $Force) {
        throw "Lock '$Name' is already held by this process. Use -Force to allow nested locking."
    }

    while (-not $acquired) {
        try {
            # Check if lock file exists
            if (Test-Path -LiteralPath $lockPath) {
                # Try to read existing lock info
                try {
                    $existingContent = Get-Content -LiteralPath $lockPath -Raw -ErrorAction Stop | 
                        ConvertFrom-Json | ConvertTo-Hashtable
                    
                    # Validate lock content has required fields
                    if (-not $existingContent.pid -or -not $existingContent.host) {
                        Write-Warning "[FileLock] Lock file has missing fields, treating as corrupt"
                        Remove-StaleLock -Name $Name -ProjectRoot $ProjectRoot -Force
                        continue
                    }
                    
                    # Check if this is our own lock
                    if ($existingContent.pid -eq $PID -and $existingContent.host -eq [Environment]::MachineName.ToLowerInvariant()) {
                        if ($Force) {
                            Write-Verbose "[FileLock] Reusing existing lock held by this process"
                            $acquired = $true
                            $lockContent = $existingContent
                            break
                        }
                    }

                    # Check for stale lock
                    if (Test-StaleLock -Name $Name -ProjectRoot $ProjectRoot) {
                        Write-Verbose "[FileLock] Found stale lock, reclaiming"
                        Remove-StaleLock -Name $Name -ProjectRoot $ProjectRoot -Force
                    }
                    else {
                        # Lock is held by another active process
                        if ($TimeoutSeconds -eq 0) {
                            Write-Verbose "[FileLock] Lock held by another process (PID: $($existingContent.pid) on $($existingContent.host)), not waiting"
                            return $null
                        }

                        $elapsed = ([DateTime]::Now - $startTime).TotalSeconds
                        if ($elapsed -ge $TimeoutSeconds) {
                            throw "Timeout waiting for lock '$Name'. Lock held by PID $($existingContent.pid) on $($existingContent.host) since $($existingContent.timestamp)"
                        }

                        Write-Verbose "[FileLock] Lock held by PID $($existingContent.pid) on $($existingContent.host), waiting... ($([int]$elapsed)s elapsed)"
                        Start-Sleep -Milliseconds 100
                        continue
                    }
                }
                catch {
                    # Corrupt lock file, try to remove it
                    Write-Warning "[FileLock] Corrupt lock file detected, attempting to remove: $_"
                    try {
                        Remove-Item -LiteralPath $lockPath -Force -ErrorAction Stop
                        Write-Verbose "[FileLock] Removed corrupt lock file"
                    }
                    catch {
                        throw "Failed to remove corrupt lock file: $_"
                    }
                }
            }

            # Attempt to create the lock file atomically
            $lockContent = New-LockContent -RunId $myRunId
            $tempLockPath = "$lockPath.$PID.$([Guid]::NewGuid().ToString('N')).tmp"
            
            # Ensure lock directory exists
            $lockDir = Split-Path -Parent $lockPath
            if (-not (Test-Path -LiteralPath $lockDir)) {
                New-Item -ItemType Directory -Path $lockDir -Force | Out-Null
            }
            
            # Write to temp file first
            $lockJson = $lockContent | ConvertTo-Json -Depth 5
            [System.IO.File]::WriteAllText($tempLockPath, $lockJson, [System.Text.Encoding]::UTF8)
            Write-Verbose "[FileLock] Wrote temp lock file: $tempLockPath"

            # Atomic move (compatible with Windows PowerShell 5.1)
            try {
                if (Test-Path -LiteralPath $lockPath) {
                    # Lock was recreated by another process, retry
                    Remove-Item -LiteralPath $tempLockPath -Force -ErrorAction SilentlyContinue
                    Write-Verbose "[FileLock] Lock file appeared during creation, retrying"
                    Start-Sleep -Milliseconds 50
                    continue
                }
                [System.IO.File]::Move($tempLockPath, $lockPath)
                $acquired = $true
                Write-Verbose "[FileLock] Atomically moved temp file to lock file"
            }
            catch [System.IO.IOException] {
                # Another process got there first
                if (Test-Path -LiteralPath $tempLockPath) {
                    Remove-Item -LiteralPath $tempLockPath -Force -ErrorAction SilentlyContinue
                }
                
                if ($TimeoutSeconds -eq 0) {
                    return $null
                }

                $elapsed = ([DateTime]::Now - $startTime).TotalSeconds
                if ($elapsed -ge $TimeoutSeconds) {
                    throw "Timeout waiting for lock '$Name'"
                }

                Write-Verbose "[FileLock] Concurrent lock acquisition detected, retrying"
                Start-Sleep -Milliseconds 50
            }
        }
        catch {
            # Clean up temp file if it exists
            if (Test-Path -LiteralPath $tempLockPath) {
                Remove-Item -LiteralPath $tempLockPath -Force -ErrorAction SilentlyContinue
            }
            
            if ($_.Exception -is [System.IO.IOException] -and $_.Exception.Message -like "*Cannot create a file*") {
                # Lock contention, retry
                $elapsed = ([DateTime]::Now - $startTime).TotalSeconds
                if ($TimeoutSeconds -eq 0 -or $elapsed -ge $TimeoutSeconds) {
                    throw "Timeout waiting for lock '$Name'"
                }
                Write-Verbose "[FileLock] Lock contention, retrying after 50ms"
                Start-Sleep -Milliseconds 50
            }
            else {
                throw
            }
        }
    }

    if ($acquired) {
        $lockInfo = [pscustomobject]@{
            Name = $Name
            Path = $lockPath
            RunId = $lockContent.runId
            AcquiredAt = [DateTime]::UtcNow
            Content = $lockContent
        }

        # Track this lock
        $script:AcquiredLocks[$Name] = $lockInfo

        Write-Verbose "[FileLock] Lock '$Name' acquired successfully (RunId: $myRunId)"
        return $lockInfo
    }

    return $null
}

<#
.SYNOPSIS
    Releases a file lock.

.DESCRIPTION
    Removes the lock file and clears the lock tracking. Safe to call even if
    lock was not held (will warn but not error).

.PARAMETER Name
    The lock name to release.

.PARAMETER ProjectRoot
    The project root directory. Defaults to current directory.

.PARAMETER Force
    Force unlock even if not tracked as held by this process.

.OUTPUTS
    System.Boolean. True if lock was released, false if it wasn't held.

.EXAMPLE
    Unlock-File -Name "sync"
#>
function Unlock-File {
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Name,
        
        [string]$ProjectRoot = ".",
        
        [switch]$Force
    )

    # Validate lock name
    if (-not (Test-LockName -Name $Name)) {
        throw "Invalid lock name: $Name. Valid names are: $($script:ValidLockNames -join ', ')"
    }

    $lockPath = Get-LockFilePath -Name $Name -ProjectRoot $ProjectRoot

    Write-Verbose "[FileLock] Releasing lock '$Name'"

    # Check if we track this lock
    if (-not $script:AcquiredLocks.ContainsKey($Name) -and -not $Force) {
        if (Test-Path -LiteralPath $lockPath) {
            Write-Warning "[FileLock] Lock '$Name' was not tracked as held by this process. Use -Force to release anyway."
        }
        return $false
    }

    try {
        if (Test-Path -LiteralPath $lockPath) {
            # Verify it's our lock before removing
            try {
                $existingContent = Get-Content -LiteralPath $lockPath -Raw -ErrorAction Stop | 
                    ConvertFrom-Json | ConvertTo-Hashtable
                
                if ($existingContent.pid -ne $PID -and -not $Force) {
                    throw "Lock '$Name' is held by a different process (PID: $($existingContent.pid)). Use -Force to override."
                }
            }
            catch [System.Management.Automation.PSInvalidOperationException] {
                # JSON parsing failed, file might be corrupt
                Write-Warning "[FileLock] Lock file appears corrupt, forcing removal"
            }

            Remove-Item -LiteralPath $lockPath -Force -ErrorAction Stop
            Write-Verbose "[FileLock] Removed lock file: $lockPath"
        }

        # Remove from tracking
        $script:AcquiredLocks.Remove($Name)

        Write-Verbose "[FileLock] Lock '$Name' released successfully"
        return $true
    }
    catch {
        Write-Error "[FileLock] Failed to release lock '$Name': $_"
        return $false
    }
}

<#
.SYNOPSIS
    Tests if a lock is currently held.

.DESCRIPTION
    Checks if the lock file exists and contains valid lock information.
    Does NOT verify if the holding process is still active.

.PARAMETER Name
    The lock name to check.

.PARAMETER ProjectRoot
    The project root directory. Defaults to current directory.

.PARAMETER IncludeStale
    If specified, returns true even for stale locks. Default excludes stale locks.

.OUTPUTS
    System.Boolean. True if lock is held, false otherwise.

.EXAMPLE
    if (Test-FileLock -Name "sync") { Write-Host "Sync is locked" }
#>
function Test-FileLock {
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Name,
        
        [string]$ProjectRoot = ".",
        
        [switch]$IncludeStale
    )

    # Validate lock name
    if (-not (Test-LockName -Name $Name)) {
        Write-Verbose "[FileLock] Invalid lock name: $Name"
        return $false
    }

    try {
        $lockPath = Get-LockFilePath -Name $Name -ProjectRoot $ProjectRoot
    }
    catch {
        return $false
    }

    if (-not (Test-Path -LiteralPath $lockPath)) {
        return $false
    }

    if (-not $IncludeStale) {
        # Check if the lock is stale
        if (Test-StaleLock -Name $Name -ProjectRoot $ProjectRoot) {
            return $false
        }
    }

    # Lock file exists and is not stale (or we're including stale)
    return $true
}

<#
.SYNOPSIS
    Tests if a lock is stale (holding process no longer exists).

.DESCRIPTION
    Checks if the lock is held by a process that no longer exists or
    is running on a different host.

    Implements multiple stale detection heuristics:
    1. Check if host matches - if different host, use timestamp heuristic
    2. Check if process exists on same host
    3. Check if process is a PowerShell process (PID reuse detection)
    4. Check lock age against MaxLockAgeMinutes

.PARAMETER Name
    The lock name to check.

.PARAMETER ProjectRoot
    The project root directory. Defaults to current directory.

.PARAMETER MaxLockAgeMinutes
    Maximum age of a lock before it's considered stale (default: 60 minutes).

.OUTPUTS
    System.Boolean. True if lock is stale, false otherwise.

.EXAMPLE
    if (Test-StaleLock -Name "sync") { Remove-StaleLock -Name "sync" }
#>
function Test-StaleLock {
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Name,
        
        [string]$ProjectRoot = ".",
        
        [ValidateRange(1, 10080)]
        [int]$MaxLockAgeMinutes = 60
    )

    # Validate lock name
    if (-not (Test-LockName -Name $Name)) {
        Write-Verbose "[FileLock] Invalid lock name: $Name"
        return $false
    }

    try {
        $lockPath = Get-LockFilePath -Name $Name -ProjectRoot $ProjectRoot
    }
    catch {
        return $false
    }

    if (-not (Test-Path -LiteralPath $lockPath)) {
        return $false
    }

    try {
        $lockContent = Get-Content -LiteralPath $lockPath -Raw -ErrorAction Stop | 
            ConvertFrom-Json | ConvertTo-Hashtable
        
        # Validate required fields
        if (-not $lockContent.pid -or -not $lockContent.host -or -not $lockContent.timestamp) {
            Write-Verbose "[FileLock] Lock file missing required fields, treating as stale"
            return $true
        }
    }
    catch {
        # Corrupt lock file is considered stale
        Write-Verbose "[FileLock] Corrupt lock file detected, treating as stale: $_"
        return $true
    }

    # Check if lock is on this host
    $currentHost = [Environment]::MachineName.ToLowerInvariant()
    if ($lockContent.host -ne $currentHost) {
        # Can't verify remote process, use timestamp heuristic
        try {
            $lockTime = [DateTime]::Parse($lockContent.timestamp)
            $age = [DateTime]::UtcNow - $lockTime
            if ($age.TotalMinutes -gt $MaxLockAgeMinutes) {
                Write-Verbose "[FileLock] Remote lock is stale (age: $([int]$age.TotalMinutes) minutes)"
                return $true
            }
        }
        catch {
            # Invalid timestamp, consider stale
            Write-Verbose "[FileLock] Invalid timestamp in lock file, treating as stale"
            return $true
        }
        Write-Verbose "[FileLock] Remote lock on different host ($($lockContent.host)) is within age threshold"
        return $false
    }

    # Check if the process is still running
    try {
        $process = Get-Process -Id $lockContent.pid -ErrorAction Stop
        # Process exists, check if it's a PowerShell process and if start time makes sense
        if ($process.ProcessName -notmatch 'powershell|pwsh') {
            # PID reused by non-PowerShell process, lock is stale
            Write-Verbose "[FileLock] PID $($lockContent.pid) exists but is not PowerShell ($($process.ProcessName)), lock is stale"
            return $true
        }
        
        # Additional check: if we can get the process start time, verify it's not newer than the lock
        # This helps detect PID reuse where another PowerShell process got the same PID
        try {
            $lockTime = [DateTime]::Parse($lockContent.timestamp)
            if ($process.StartTime -gt $lockTime.AddMinutes(-1)) {
                # Process started after the lock was created (with 1 minute buffer)
                Write-Verbose "[FileLock] PID $($lockContent.pid) started after lock creation, treating as stale"
                return $true
            }
        }
        catch {
            # Can't get start time on some platforms, skip this check
            Write-Verbose "[FileLock] Could not verify process start time"
        }
        
        Write-Verbose "[FileLock] PID $($lockContent.pid) exists and is valid PowerShell process, lock is valid"
        return $false
    }
    catch [Microsoft.PowerShell.Commands.ProcessCommandException] {
        # Process not found - lock is stale
        Write-Verbose "[FileLock] PID $($lockContent.pid) not found, lock is stale"
        return $true
    }
    catch {
        # Any other error checking process - lock is potentially stale
        Write-Verbose "[FileLock] Error checking process $($lockContent.pid): $_. Treating as stale."
        return $true
    }
}

<#
.SYNOPSIS
    Reads the contents of a lock file.

.DESCRIPTION
    Retrieves and parses the lock file, returning a structured object
    with lock metadata.

.PARAMETER Name
    The lock name to read.

.PARAMETER ProjectRoot
    The project root directory. Defaults to current directory.

.OUTPUTS
    PSObject. Lock information with SchemaVersion, Pid, Host, ExecutionMode,
    RunId, Timestamp, User, IsStale, AgeMinutes properties.
    Returns $null if lock doesn't exist.

.EXAMPLE
    $info = Get-LockInfo -Name "sync"
    Write-Host "Lock held by $($info.User) on $($info.Host)"
#>
function Get-LockInfo {
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Name,
        
        [string]$ProjectRoot = "."
    )

    # Validate lock name
    if (-not (Test-LockName -Name $Name)) {
        Write-Warning "[FileLock] Invalid lock name: $Name"
        return $null
    }

    try {
        $lockPath = Get-LockFilePath -Name $Name -ProjectRoot $ProjectRoot
    }
    catch {
        return $null
    }

    if (-not (Test-Path -LiteralPath $lockPath)) {
        return $null
    }

    try {
        $content = Get-Content -LiteralPath $lockPath -Raw -ErrorAction Stop | 
            ConvertFrom-Json | ConvertTo-Hashtable

        # Calculate age
        $ageMinutes = $null
        try {
            $lockTime = [DateTime]::Parse($content.timestamp)
            $ageMinutes = ([DateTime]::UtcNow - $lockTime).TotalMinutes
        }
        catch {
            # Invalid timestamp
        }

        return [pscustomobject]@{
            SchemaVersion = $content.schemaVersion
            Pid = $content.pid
            Host = $content.host
            ExecutionMode = $content.executionMode
            RunId = $content.runId
            Timestamp = $content.timestamp
            User = $content.user
            IsStale = Test-StaleLock -Name $Name -ProjectRoot $ProjectRoot
            AgeMinutes = $ageMinutes
            RawContent = $content
        }
    }
    catch {
        Write-Warning "[FileLock] Failed to read lock file: $_"
        return $null
    }
}

<#
.SYNOPSIS
    Safely removes a stale lock.

.DESCRIPTION
    Verifies that a lock is stale before removing it. By default, requires
    confirmation unless -Force is specified.

.PARAMETER Name
    The lock name to remove.

.PARAMETER ProjectRoot
    The project root directory. Defaults to current directory.

.PARAMETER Force
    Skip confirmation and remove without interactive prompt.

.PARAMETER CheckOnly
    Only check if stale, don't actually remove.

.OUTPUTS
    System.Boolean. True if lock was removed or is stale (with CheckOnly), false otherwise.

.EXAMPLE
    Remove-StaleLock -Name "sync" -Force

.EXAMPLE
    # Check only, don't remove
    $isStale = Remove-StaleLock -Name "sync" -CheckOnly
#>
function Remove-StaleLock {
    [CmdletBinding(SupportsShouldProcess = $true)]
    [OutputType([bool])]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Name,
        
        [string]$ProjectRoot = ".",
        
        [switch]$Force,
        
        [switch]$CheckOnly
    )

    # Validate lock name
    if (-not (Test-LockName -Name $Name)) {
        Write-Warning "[FileLock] Invalid lock name: $Name"
        return $false
    }

    try {
        $lockPath = Get-LockFilePath -Name $Name -ProjectRoot $ProjectRoot
    }
    catch {
        Write-Warning "[FileLock] Invalid lock name: $Name"
        return $false
    }

    if (-not (Test-Path -LiteralPath $lockPath)) {
        Write-Verbose "[FileLock] Lock '$Name' does not exist"
        return $true  # Already gone
    }

    # Check if stale
    if (-not (Test-StaleLock -Name $Name -ProjectRoot $ProjectRoot)) {
        Write-Verbose "[FileLock] Lock '$Name' is not stale"
        return $false
    }

    if ($CheckOnly) {
        return $true
    }

    # Get lock info for display
    $lockInfo = Get-LockInfo -Name $Name -ProjectRoot $ProjectRoot

    $target = "Lock '$Name' held by $($lockInfo.User)@$($lockInfo.Host) (PID: $($lockInfo.Pid)) since $($lockInfo.Timestamp)"

    if ($Force -or $PSCmdlet.ShouldProcess($target, "Remove stale lock")) {
        try {
            # Backup the stale lock before removal
            $backupPath = "$lockPath.stale.$([DateTime]::Now.ToString('yyyyMMddHHmmss'))"
            Copy-Item -LiteralPath $lockPath -Destination $backupPath -Force

            Remove-Item -LiteralPath $lockPath -Force -ErrorAction Stop
            
            Write-Verbose "[FileLock] Stale lock '$Name' removed (backup: $backupPath)"
            return $true
        }
        catch {
            Write-Error "[FileLock] Failed to remove stale lock '$Name': $_"
            return $false
        }
    }

    return $false
}

<#
.SYNOPSIS
    Releases all locks held by this process.

.DESCRIPTION
    Utility function to clean up all locks tracked by this PowerShell session.
    Should be called during cleanup/shutdown.

.PARAMETER ProjectRoot
    The project root directory. Defaults to current directory.

.OUTPUTS
    System.Object[]. Array of released lock names.

.EXAMPLE
    Release-AllLocks
#>
function Release-AllLocks {
    [CmdletBinding()]
    [OutputType([array])]
    param(
        [string]$ProjectRoot = "."
    )

    $released = @()
    $locksToRelease = @($script:AcquiredLocks.Keys)

    foreach ($name in $locksToRelease) {
        if (Unlock-File -Name $name -ProjectRoot $ProjectRoot) {
            $released += $name
        }
    }

    Write-Verbose "[FileLock] Released $($released.Count) lock(s): $($released -join ', ')"
    return $released
}

<#
.SYNOPSIS
    Lists all existing locks in the project.

.DESCRIPTION
    Returns information about all lock files in the locks directory,
    including stale status.

.PARAMETER ProjectRoot
    The project root directory. Defaults to current directory.

.PARAMETER IncludeStale
    Include stale locks in the results.

.OUTPUTS
    System.Object[]. Array of lock information objects.

.EXAMPLE
    Get-AllLocks | Where-Object { -not $_.IsStale }
#>
function Get-AllLocks {
    [CmdletBinding()]
    [OutputType([array])]
    param(
        [string]$ProjectRoot = ".",
        
        [switch]$IncludeStale
    )

    $lockDir = Get-LockDirectory -ProjectRoot $ProjectRoot
    $locks = @()

    foreach ($name in $script:ValidLockNames) {
        $lockInfo = Get-LockInfo -Name $name -ProjectRoot $ProjectRoot
        if ($lockInfo) {
            if ($IncludeStale -or -not $lockInfo.IsStale) {
                $locks += $lockInfo
            }
        }
    }

    return $locks
}

<#
.SYNOPSIS
    Updates the timestamp of a lock file (heartbeat mechanism).

.DESCRIPTION
    Updates the timestamp in a lock file to prevent it from being considered stale.
    This should be called periodically by long-running operations.

.PARAMETER Name
    The lock name to update.

.PARAMETER ProjectRoot
    The project root directory. Defaults to current directory.

.OUTPUTS
    System.Boolean. True if heartbeat was successful.

.EXAMPLE
    # In a long-running operation
    while ($running) {
        Send-LockHeartbeat -Name "sync"
        Start-Sleep -Seconds 30
    }
#>
function Send-LockHeartbeat {
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Name,
        
        [string]$ProjectRoot = "."
    )

    # Validate lock name
    if (-not (Test-LockName -Name $Name)) {
        Write-Warning "[FileLock] Invalid lock name: $Name"
        return $false
    }

    # Check if we hold this lock
    if (-not $script:AcquiredLocks.ContainsKey($Name)) {
        Write-Warning "[FileLock] Cannot send heartbeat for lock '$Name' - not held by this process"
        return $false
    }

    try {
        $lockPath = Get-LockFilePath -Name $Name -ProjectRoot $ProjectRoot
        
        if (-not (Test-Path -LiteralPath $lockPath)) {
            Write-Warning "[FileLock] Lock file for '$Name' no longer exists"
            return $false
        }

        # Read, update timestamp, and write back
        $content = Get-Content -LiteralPath $lockPath -Raw -ErrorAction Stop | 
            ConvertFrom-Json | ConvertTo-Hashtable
        
        $content.timestamp = [DateTime]::UtcNow.ToString("yyyy-MM-ddTHH:mm:ssZ")
        $content.lastHeartbeat = [DateTime]::UtcNow.ToString("yyyy-MM-ddTHH:mm:ssZ")
        
        $tempPath = "$lockPath.heartbeat.$PID.tmp"
        $json = $content | ConvertTo-Json -Depth 5
        [System.IO.File]::WriteAllText($tempPath, $json, [System.Text.Encoding]::UTF8)
        
        # Atomic replace
        [System.IO.File]::Replace($tempPath, $lockPath, "$lockPath.bak")
        Remove-Item -LiteralPath "$lockPath.bak" -Force -ErrorAction SilentlyContinue
        
        Write-Verbose "[FileLock] Heartbeat sent for lock '$Name'"
        return $true
    }
    catch {
        Write-Warning "[FileLock] Failed to send heartbeat for lock '$Name': $_"
        return $false
    }
}

# Export all public functions (only works when loaded as module)
if ($MyInvocation.MyCommand.Path -match '\.psm1$') {
    Export-ModuleMember -Function @(
        'Lock-File'
        'Unlock-File'
        'Test-FileLock'
        'Test-StaleLock'
        'Get-LockInfo'
        'Get-LockFilePath'
        'Remove-StaleLock'
        'Release-AllLocks'
        'Get-AllLocks'
        'Get-LockDirectory'
        'Send-LockHeartbeat'
    )
}
