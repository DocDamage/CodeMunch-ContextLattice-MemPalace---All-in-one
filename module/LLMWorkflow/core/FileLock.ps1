#requires -Version 5.1
<#
.SYNOPSIS
    File Locking and Concurrency Control for LLM Workflow platform.

.DESCRIPTION
    Provides cross-platform file locking with stale lock detection and safe reclamation.
    Implements the state safety invariant requirements from IMPROVEMENT_PROPOSALS.md section 6.4.

.NOTES
    File: FileLock.ps1
    Version: 1.0.0
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
$script:LockSchemaVersion = 1
$script:ValidLockNames = @('sync', 'heal', 'index', 'ingest', 'pack')

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
        }
        catch {
            throw "Failed to create lock directory: $lockDir. Error: $_"
        }
    }

    return $lockDir
}

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
    Generates a new Run ID for lock identification.

.DESCRIPTION
    Creates a unique run identifier in the format: YYYYMMDDTHHMMSSZ-XXXX
    where XXXX is a random 4-character hex string.

.OUTPUTS
    System.String. The generated Run ID.
#>
function New-RunId {
    [CmdletBinding()]
    [OutputType([string])]
    param()

    $timestamp = [DateTime]::UtcNow.ToString("yyyyMMddTHHmmssZ")
    $randomHex = (Get-Random -Minimum 0 -Maximum 65535).ToString("x4")
    return "$timestamp-$randomHex"
}

<#
.SYNOPSIS
    Detects the current execution mode.

.DESCRIPTION
    Determines if the script is running interactively, in a CI environment,
    or as a background task.

.OUTPUTS
    System.String. One of: interactive, ci, background, scheduled
#>
function Get-ExecutionMode {
    [CmdletBinding()]
    [OutputType([string])]
    param()

    # Check for CI environment variables
    $ciVars = @('CI', 'GITHUB_ACTIONS', 'GITLAB_CI', 'JENKINS_HOME', 'TF_BUILD', 'BUILD_BUILDID')
    foreach ($var in $ciVars) {
        if (-not [string]::IsNullOrWhiteSpace([Environment]::GetEnvironmentVariable($var))) {
            return 'ci'
        }
    }

    # Check if running in a scheduled task or service
    if ($Host.Name -eq 'ServerRemoteHost' -or 
        [Environment]::GetCommandLineArgs() -contains '-NonInteractive') {
        return 'background'
    }

    # Check if running interactively
    if ([Environment]::UserInteractive) {
        return 'interactive'
    }

    return 'background'
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
        
        [int]$TimeoutSeconds = 30,
        
        [string]$ProjectRoot = ".",
        
        [string]$RunId = "",
        
        [switch]$Force
    )

    $lockPath = Get-LockFilePath -Name $Name -ProjectRoot $ProjectRoot
    $startTime = [DateTime]::Now
    $acquired = $false
    $lockContent = $null
    $myRunId = if ([string]::IsNullOrWhiteSpace($RunId)) { New-RunId } else { $RunId }

    Write-Verbose "Attempting to acquire lock '$Name' (RunId: $myRunId)"

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
                        ConvertFrom-Json -AsHashtable
                    
                    # Check if this is our own lock
                    if ($existingContent.pid -eq $PID -and $existingContent.host -eq [Environment]::MachineName.ToLowerInvariant()) {
                        if ($Force) {
                            Write-Verbose "Reusing existing lock held by this process"
                            $acquired = $true
                            $lockContent = $existingContent
                            break
                        }
                    }

                    # Check for stale lock
                    if (Test-StaleLock -Name $Name -ProjectRoot $ProjectRoot) {
                        Write-Verbose "Found stale lock, reclaiming"
                        Remove-StaleLock -Name $Name -ProjectRoot $ProjectRoot -Force
                    }
                    else {
                        # Lock is held by another active process
                        if ($TimeoutSeconds -eq 0) {
                            Write-Verbose "Lock held by another process, not waiting"
                            return $null
                        }

                        $elapsed = ([DateTime]::Now - $startTime).TotalSeconds
                        if ($elapsed -ge $TimeoutSeconds) {
                            throw "Timeout waiting for lock '$Name'. Lock held by PID $($existingContent.pid) on $($existingContent.host) since $($existingContent.timestamp)"
                        }

                        Write-Verbose "Lock held by PID $($existingContent.pid), waiting... ($([int]$elapsed)s elapsed)"
                        Start-Sleep -Milliseconds 100
                        continue
                    }
                }
                catch {
                    # Corrupt lock file, try to remove it
                    Write-Warning "Corrupt lock file detected, attempting to remove: $_"
                    try {
                        Remove-Item -LiteralPath $lockPath -Force -ErrorAction Stop
                    }
                    catch {
                        throw "Failed to remove corrupt lock file: $_"
                    }
                }
            }

            # Attempt to create the lock file atomically
            $lockContent = New-LockContent -RunId $myRunId
            $tempLockPath = "$lockPath.$PID.tmp"
            
            # Write to temp file first
            $lockJson = $lockContent | ConvertTo-Json -Depth 5
            [System.IO.File]::WriteAllText($tempLockPath, $lockJson, [System.Text.Encoding]::UTF8)

            # Use .NET for atomic move on Windows, fallback to PowerShell for cross-platform
            try {
                [System.IO.File]::Move($tempLockPath, $lockPath, $false)
                $acquired = $true
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

                Start-Sleep -Milliseconds 50
            }
        }
        catch {
            if ($_.Exception -is [System.IO.IOException] -and $_.Exception.Message -like "*Cannot create a file*") {
                # Lock contention, retry
                $elapsed = ([DateTime]::Now - $startTime).TotalSeconds
                if ($TimeoutSeconds -eq 0 -or $elapsed -ge $TimeoutSeconds) {
                    throw "Timeout waiting for lock '$Name'"
                }
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

        Write-Verbose "Lock '$Name' acquired successfully (RunId: $myRunId)"
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

    $lockPath = Get-LockFilePath -Name $Name -ProjectRoot $ProjectRoot

    Write-Verbose "Releasing lock '$Name'"

    # Check if we track this lock
    if (-not $script:AcquiredLocks.ContainsKey($Name) -and -not $Force) {
        if (Test-Path -LiteralPath $lockPath) {
            Write-Warning "Lock '$Name' was not tracked as held by this process. Use -Force to release anyway."
        }
        return $false
    }

    try {
        if (Test-Path -LiteralPath $lockPath) {
            # Verify it's our lock before removing
            try {
                $existingContent = Get-Content -LiteralPath $lockPath -Raw -ErrorAction Stop | 
                    ConvertFrom-Json -AsHashtable
                
                if ($existingContent.pid -ne $PID -and -not $Force) {
                    throw "Lock '$Name' is held by a different process (PID: $($existingContent.pid)). Use -Force to override."
                }
            }
            catch [System.Management.Automation.PSInvalidOperationException] {
                # JSON parsing failed, file might be corrupt
                Write-Warning "Lock file appears corrupt, forcing removal"
            }

            Remove-Item -LiteralPath $lockPath -Force -ErrorAction Stop
        }

        # Remove from tracking
        $script:AcquiredLocks.Remove($Name)

        Write-Verbose "Lock '$Name' released successfully"
        return $true
    }
    catch {
        Write-Error "Failed to release lock '$Name': $_"
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
        
        [int]$MaxLockAgeMinutes = 60
    )

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
            ConvertFrom-Json -AsHashtable
    }
    catch {
        # Corrupt lock file is considered stale
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
                return $true
            }
        }
        catch {
            # Invalid timestamp, consider stale
            return $true
        }
        return $false
    }

    # Check if the process is still running
    try {
        $process = Get-Process -Id $lockContent.pid -ErrorAction Stop
        # Process exists, check if it's a PowerShell process
        if ($process.ProcessName -notmatch 'powershell|pwsh') {
            # PID reused by non-PowerShell process, lock is stale
            return $true
        }
        return $false
    }
    catch [System.Management.Automation.ProcessCommandException] {
        # Process not found, lock is stale
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
            ConvertFrom-Json -AsHashtable

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
        Write-Warning "Failed to read lock file: $_"
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

    try {
        $lockPath = Get-LockFilePath -Name $Name -ProjectRoot $ProjectRoot
    }
    catch {
        Write-Warning "Invalid lock name: $Name"
        return $false
    }

    if (-not (Test-Path -LiteralPath $lockPath)) {
        Write-Verbose "Lock '$Name' does not exist"
        return $true  # Already gone
    }

    # Check if stale
    if (-not (Test-StaleLock -Name $Name -ProjectRoot $ProjectRoot)) {
        Write-Verbose "Lock '$Name' is not stale"
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
            
            Write-Verbose "Stale lock '$Name' removed (backup: $backupPath)"
            return $true
        }
        catch {
            Write-Error "Failed to remove stale lock '$Name': $_"
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

    Write-Verbose "Released $($released.Count) lock(s): $($released -join ', ')"
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

# Export all public functions
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
)
