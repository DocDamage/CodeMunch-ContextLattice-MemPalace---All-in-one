#requires -Version 5.1
<#
.SYNOPSIS
    Core journaling and checkpoint functions for LLM Workflow.
.DESCRIPTION
    Provides journaling capabilities for multi-step operations with
    before/after checkpoint entries, resume/restart support, and
    run manifest generation.
    
    Journal files are stored at:
    .llm-workflow/journals/{runId}.journal.json
    
    Run manifests are stored at:
    .llm-workflow/manifests/{runId}.run.json
.NOTES
    File Name      : Journal.ps1
    Author         : LLM Workflow Team
    Prerequisite   : PowerShell 5.1+
    Copyright      : (c) 2026 LLM Workflow Project
    License        : MIT
    
    Exit Codes Supported:
    - 0: success
    - 1: general failure
    - 6: partial success
    - 12: user-cancelled / aborted
#>

Set-StrictMode -Version Latest

# Default paths
$script:DefaultJournalDirectory = ".llm-workflow/journals"
$script:DefaultManifestDirectory = ".llm-workflow/manifests"
$script:CurrentSchemaVersion = 1

<#
.SYNOPSIS
    Creates a new run manifest for tracking a top-level operation.
.DESCRIPTION
    Creates a run manifest with all required fields including:
    - Run ID and timestamps
    - Command and arguments
    - Execution mode and policy decision
    - Git commit hash
    - Config/profile sources
    - Locks acquired
    - Artifacts written
    - Warnings and errors
    - Exit code
    - Resume/restart status
    
    The manifest is written atomically to the manifests directory.
.PARAMETER RunId
    The unique run identifier. If not provided, uses the current run ID.
.PARAMETER Command
    The command being executed (e.g., "sync", "build", "export").
.PARAMETER Args
    Array of arguments passed to the command.
.PARAMETER ExecutionMode
    The execution mode (interactive, ci, watch, scheduled, etc.).
.PARAMETER PolicyDecision
    The policy decision result (allowed, denied, etc.).
.PARAMETER ProjectRoot
    The project root directory. Defaults to current directory.
.PARAMETER ManifestDirectory
    The directory where manifests are stored.
.OUTPUTS
    System.Management.Automation.PSCustomObject representing the created manifest.
.EXAMPLE
    PS C:\> $manifest = New-RunManifest -RunId "20260411T210501Z-7f2c" -Command "sync" -Args @("--all")
    
    Creates a new run manifest for a sync operation.
#>
function New-RunManifest {
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter()]
        [string]$RunId = "",
        
        [Parameter(Mandatory = $true)]
        [string]$Command,
        
        [Parameter()]
        [string[]]$Args = @(),
        
        [Parameter()]
        [string]$ExecutionMode = "interactive",
        
        [Parameter()]
        [string]$PolicyDecision = "allowed",
        
        [Parameter()]
        [string]$ProjectRoot = ".",
        
        [Parameter()]
        [string]$ManifestDirectory = $script:DefaultManifestDirectory
    )
    
    # Get or generate run ID
    if ([string]::IsNullOrEmpty($RunId)) {
        try {
            $runIdCmd = Get-Command Get-CurrentRunId -ErrorAction SilentlyContinue
            if ($runIdCmd) {
                $RunId = & $runIdCmd
            }
            else {
                # Fallback: generate timestamp-based ID
                $timestamp = [DateTime]::UtcNow.ToString("yyyyMMddTHHmmssZ", [System.Globalization.CultureInfo]::InvariantCulture)
                $random = Get-Random -Minimum 0 -Maximum 65535
                $RunId = "$timestamp-$($random.ToString('x4'))"
            }
        }
        catch {
            $timestamp = [DateTime]::UtcNow.ToString("yyyyMMddTHHmmssZ", [System.Globalization.CultureInfo]::InvariantCulture)
            $random = Get-Random -Minimum 0 -Maximum 65535
            $RunId = "$timestamp-$($random.ToString('x4'))"
        }
    }
    
    # Get git commit hash if available
    $gitCommit = ""
    try {
        $gitCmd = Get-Command git -ErrorAction SilentlyContinue
        if ($gitCmd) {
            $gitCommit = & git rev-parse --short HEAD 2>$null
            if ($LASTEXITCODE -ne 0) {
                $gitCommit = ""
            }
        }
    }
    catch {
        $gitCommit = ""
    }
    
    # Resolve project root
    $resolvedProjectRoot = $ProjectRoot
    if (Test-Path -LiteralPath $ProjectRoot) {
        $resolvedProjectRoot = (Resolve-Path -LiteralPath $ProjectRoot).Path
    }
    
    # Build manifest
    $manifest = [ordered]@{
        schemaVersion = $script:CurrentSchemaVersion
        updatedUtc = [DateTime]::UtcNow.ToString("yyyy-MM-ddTHH:mm:ssZ", [System.Globalization.CultureInfo]::InvariantCulture)
        createdByRunId = $RunId
        runId = $RunId
        command = $Command
        args = $Args
        startedAt = [DateTime]::UtcNow.ToString("yyyy-MM-ddTHH:mm:ssZ", [System.Globalization.CultureInfo]::InvariantCulture)
        completedAt = $null
        executionMode = $ExecutionMode
        policyDecision = $PolicyDecision
        gitCommit = $gitCommit
        projectRoot = $resolvedProjectRoot
        configSources = @()
        profileSources = @()
        locksAcquired = @()
        artifactsWritten = @()
        warnings = @()
        errors = @()
        exitCode = $null
        exitStatus = "running"
        resumeStatus = @{
            canResume = $false
            lastCheckpoint = $null
            completedSteps = @()
            pendingSteps = @()
        }
        metadata = @{}
    }
    
    # Write manifest atomically
    try {
        $manifestPath = Join-Path $ManifestDirectory "$RunId.run.json"
        Write-JsonFileAtomic -Path $manifestPath -Data $manifest
        Write-Verbose "[Journal] Created run manifest: $manifestPath"
    }
    catch {
        Write-Warning "[Journal] Failed to write run manifest: $_"
    }
    
    return [pscustomobject]$manifest
}

<#
.SYNOPSIS
    Updates an existing run manifest with completion information.
.DESCRIPTION
    Updates the run manifest with final status, exit code, completion
    timestamp, and any accumulated errors or warnings.
.PARAMETER RunId
    The run ID of the manifest to update.
.PARAMETER ExitCode
    The exit code (0=success, 1=failure, 6=partial, 12=aborted).
.PARAMETER Warnings
    Array of warning messages accumulated during the run.
.PARAMETER Errors
    Array of error messages accumulated during the run.
.PARAMETER ManifestDirectory
    The directory where manifests are stored.
.PARAMETER ResumeStatus
    Resume/restart status information.
.OUTPUTS
    System.Management.Automation.PSCustomObject representing the updated manifest.
.EXAMPLE
    PS C:\> Complete-RunManifest -RunId "20260411T210501Z-7f2c" -ExitCode 0
    
    Marks the run as successfully completed.
#>
function Complete-RunManifest {
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory = $true)]
        [string]$RunId,
        
        [Parameter()]
        [ValidateSet(0, 1, 6, 12)]
        [int]$ExitCode = 0,
        
        [Parameter()]
        [string[]]$Warnings = @(),
        
        [Parameter()]
        [string[]]$Errors = @(),
        
        [Parameter()]
        [string]$ManifestDirectory = $script:DefaultManifestDirectory,
        
        [Parameter()]
        [hashtable]$ResumeStatus = @{}
    )
    
    $manifestPath = Join-Path $ManifestDirectory "$RunId.run.json"
    
    if (-not (Test-Path -LiteralPath $manifestPath)) {
        Write-Warning "[Journal] Run manifest not found: $manifestPath"
        return $null
    }
    
    try {
        $manifest = Get-Content -LiteralPath $manifestPath -Raw | ConvertFrom-Json -AsHashtable
        
        # Update fields
        $manifest['completedAt'] = [DateTime]::UtcNow.ToString("yyyy-MM-ddTHH:mm:ssZ", [System.Globalization.CultureInfo]::InvariantCulture)
        $manifest['updatedUtc'] = $manifest['completedAt']
        $manifest['exitCode'] = $ExitCode
        
        # Determine exit status
        switch ($ExitCode) {
            0 { $manifest['exitStatus'] = "success" }
            1 { $manifest['exitStatus'] = "failure" }
            6 { $manifest['exitStatus'] = "partial" }
            12 { $manifest['exitStatus'] = "aborted" }
            default { $manifest['exitStatus'] = "unknown" }
        }
        
        if ($Warnings.Count -gt 0) {
            $manifest['warnings'] = $Warnings
        }
        
        if ($Errors.Count -gt 0) {
            $manifest['errors'] = $Errors
        }
        
        if ($ResumeStatus.Count -gt 0) {
            $manifest['resumeStatus'] = $ResumeStatus
        }
        
        Write-JsonFileAtomic -Path $manifestPath -Data $manifest
        Write-Verbose "[Journal] Updated run manifest: $manifestPath"
        
        return [pscustomobject]$manifest
    }
    catch {
        Write-Warning "[Journal] Failed to update run manifest: $_"
        return $null
    }
}

<#
.SYNOPSIS
    Creates a new journal entry (checkpoint) for a multi-step operation.
.DESCRIPTION
    Writes a journal entry to track before/after state of each step
    in a multi-step operation. Supports resume/restart functionality.
    
    Journal entries include:
    - Step name and status (before/after)
    - Timestamps
    - Metadata about the step
    - State snapshot for resume capability
.PARAMETER RunId
    The run ID this journal entry belongs to.
.PARAMETER Step
    The name of the step (e.g., "ingest", "embed", "export").
.PARAMETER Status
    The checkpoint status: "before" or "after".
.PARAMETER Metadata
    Additional metadata about the step state.
.PARAMETER State
    Serializable state snapshot for resume support.
.PARAMETER JournalDirectory
    The directory where journals are stored.
.OUTPUTS
    System.Management.Automation.PSCustomObject representing the journal entry.
.EXAMPLE
    PS C:\> New-JournalEntry -RunId "20260411T210501Z-7f2c" -Step "ingest" -Status "before" -Metadata @{source="github"}
    
    Creates a "before" checkpoint for the ingest step.
#>
function New-JournalEntry {
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory = $true)]
        [string]$RunId,
        
        [Parameter(Mandatory = $true)]
        [string]$Step,
        
        [Parameter(Mandatory = $true)]
        [ValidateSet('before', 'after', 'start', 'complete', 'failed')]
        [string]$Status,
        
        [Parameter()]
        [hashtable]$Metadata = @{},
        
        [Parameter()]
        [hashtable]$State = @{},
        
        [Parameter()]
        [string]$JournalDirectory = $script:DefaultJournalDirectory
    )
    
    $entry = [ordered]@{
        schemaVersion = $script:CurrentSchemaVersion
        updatedUtc = [DateTime]::UtcNow.ToString("yyyy-MM-ddTHH:mm:ssZ", [System.Globalization.CultureInfo]::InvariantCulture)
        createdByRunId = $RunId
        runId = $RunId
        step = $Step
        status = $Status
        timestamp = [DateTime]::UtcNow.ToString("yyyy-MM-ddTHH:mm:ss.fffZ", [System.Globalization.CultureInfo]::InvariantCulture)
        sequence = 0
        metadata = $Metadata
        state = $State
        durationMs = $null
    }
    
    # Read existing journal to determine sequence number
    $journalPath = Join-Path $JournalDirectory "$RunId.journal.json"
    $existingEntries = @()
    
    if (Test-Path -LiteralPath $journalPath) {
        try {
            $existingEntries = Get-Content -LiteralPath $journalPath -Raw | ConvertFrom-Json -AsHashtable
            if ($existingEntries -isnot [array]) {
                $existingEntries = @($existingEntries)
            }
            $entry['sequence'] = $existingEntries.Count
        }
        catch {
            $existingEntries = @()
            $entry['sequence'] = 0
        }
    }
    
    # Calculate duration if this is an "after" entry and there's a matching "before"
    if ($Status -eq 'after' -and $existingEntries.Count -gt 0) {
        $beforeEntry = $existingEntries | 
            Where-Object { $_.step -eq $Step -and $_.status -eq 'before' } |
            Select-Object -Last 1
        
        if ($beforeEntry) {
            try {
                $beforeTime = [DateTime]::Parse($beforeEntry.timestamp)
                $afterTime = [DateTime]::Parse($entry['timestamp'])
                $entry['durationMs'] = [int]($afterTime - $beforeTime).TotalMilliseconds
            }
            catch {
                Write-Verbose "[Journal] Failed to calculate duration: $_"
            }
        }
    }
    
    # Append entry to journal
    $allEntries = $existingEntries + $entry
    
    try {
        Write-JsonFileAtomic -Path $journalPath -Data $allEntries
        Write-Verbose "[Journal] Wrote journal entry: $RunId/$Step/$Status"
    }
    catch {
        Write-Warning "[Journal] Failed to write journal entry: $_"
    }
    
    return [pscustomobject]$entry
}

<#
.SYNOPSIS
    Gets the journal state for resume support.
.DESCRIPTION
    Reads the journal for a given run ID and determines:
    - Whether the run can be resumed
    - Which steps are complete
    - Which steps are pending
    - The last successful checkpoint
    
    Used by --resume and --restart flags.
.PARAMETER RunId
    The run ID to get journal state for.
.PARAMETER JournalDirectory
    The directory where journals are stored.
.PARAMETER ManifestDirectory
    The directory where manifests are stored.
.OUTPUTS
    System.Management.Automation.PSCustomObject with resume state information.
.EXAMPLE
    PS C:\> $state = Get-JournalState -RunId "20260411T210501Z-7f2c"
    PS C:\> if ($state.CanResume) { Resume-FromCheckpoint $state.LastCheckpoint }
    
    Checks if a run can be resumed.
#>
function Get-JournalState {
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory = $true)]
        [string]$RunId,
        
        [Parameter()]
        [string]$JournalDirectory = $script:DefaultJournalDirectory,
        
        [Parameter()]
        [string]$ManifestDirectory = $script:DefaultManifestDirectory
    )
    
    $journalPath = Join-Path $JournalDirectory "$RunId.journal.json"
    $manifestPath = Join-Path $ManifestDirectory "$RunId.run.json"
    
    $result = [ordered]@{
        RunId = $RunId
        Exists = $false
        CanResume = $false
        CanRestart = $false
        IsComplete = $false
        LastCheckpoint = $null
        CompletedSteps = @()
        PendingSteps = @()
        FailedSteps = @()
        Entries = @()
        Manifest = $null
    }
    
    # Check if manifest exists
    if (Test-Path -LiteralPath $manifestPath) {
        try {
            $result['Manifest'] = Get-Content -LiteralPath $manifestPath -Raw | ConvertFrom-Json
            $result['Exists'] = $true
        }
        catch {
            Write-Warning "[Journal] Failed to read manifest: $_"
        }
    }
    
    # Read journal entries
    if (Test-Path -LiteralPath $journalPath) {
        try {
            $entries = Get-Content -LiteralPath $journalPath -Raw | ConvertFrom-Json -AsHashtable
            if ($entries -isnot [array]) {
                $entries = @($entries)
            }
            $result['Entries'] = $entries
            $result['Exists'] = $true
        }
        catch {
            Write-Warning "[Journal] Failed to read journal: $_"
            return [pscustomobject]$result
        }
    }
    else {
        return [pscustomobject]$result
    }
    
    # Analyze entries
    $steps = @{}
    foreach ($entry in $result['Entries']) {
        $stepName = $entry.step
        if (-not $steps.ContainsKey($stepName)) {
            $steps[$stepName] = @{
                Name = $stepName
                Before = $null
                After = $null
                Failed = $null
            }
        }
        
        switch ($entry.status) {
            'before' { $steps[$stepName].Before = $entry }
            'after' { $steps[$stepName].After = $entry }
            'failed' { $steps[$stepName].Failed = $entry }
        }
    }
    
    # Determine step states
    foreach ($stepName in $steps.Keys) {
        $step = $steps[$stepName]
        
        if ($step.Failed) {
            $result['FailedSteps'] += $stepName
            $result['PendingSteps'] += $stepName
        }
        elseif ($step.After) {
            $result['CompletedSteps'] += $stepName
        }
        elseif ($step.Before -and -not $step.After) {
            $result['PendingSteps'] += $stepName
            if ($null -eq $result['LastCheckpoint']) {
                $result['LastCheckpoint'] = $step.Before
            }
        }
    }
    
    # Determine if can resume
    if ($result['PendingSteps'].Count -gt 0 -and $result['LastCheckpoint']) {
        $result['CanResume'] = $true
    }
    
    # Determine if can restart
    if ($result['Exists']) {
        $result['CanRestart'] = $true
    }
    
    # Check if complete (has start and complete entries)
    $hasStart = $result['Entries'] | Where-Object { $_.status -eq 'start' } | Select-Object -First 1
    $hasComplete = $result['Entries'] | Where-Object { $_.status -eq 'complete' } | Select-Object -First 1
    if ($hasStart -and $hasComplete) {
        $result['IsComplete'] = $true
    }
    
    return [pscustomobject]$result
}

<#
.SYNOPSIS
    Exports a journal report for display or analysis.
.DESCRIPTION
    Generates a human-readable or machine-readable summary of
    a journal, including step timing, status, and overall progress.
.PARAMETER RunId
    The run ID to generate the report for.
.PARAMETER JournalDirectory
    The directory where journals are stored.
.PARAMETER ManifestDirectory
    The directory where manifests are stored.
.PARAMETER Format
    Output format: "text" or "json".
.OUTPUTS
    System.String or System.Management.Automation.PSCustomObject depending on format.
.EXAMPLE
    PS C:\> Export-JournalReport -RunId "20260411T210501Z-7f2c"
    
    Generates a text report of the journal.
.EXAMPLE
    PS C:\> Export-JournalReport -RunId "20260411T210501Z-7f2c" -Format json | ConvertFrom-Json
    
    Generates a JSON report.
#>
function Export-JournalReport {
    [CmdletBinding()]
    [OutputType([object])]
    param(
        [Parameter(Mandatory = $true)]
        [string]$RunId,
        
        [Parameter()]
        [string]$JournalDirectory = $script:DefaultJournalDirectory,
        
        [Parameter()]
        [string]$ManifestDirectory = $script:DefaultManifestDirectory,
        
        [Parameter()]
        [ValidateSet('text', 'json', 'object')]
        [string]$Format = 'text'
    )
    
    $state = Get-JournalState -RunId $RunId -JournalDirectory $JournalDirectory -ManifestDirectory $ManifestDirectory
    
    if (-not $state.Exists) {
        if ($Format -eq 'json') {
            return '{"error": "Journal not found"}'
        }
        elseif ($Format -eq 'object') {
            return @{ error = "Journal not found" }
        }
        else {
            return "Journal not found for run: $RunId"
        }
    }
    
    # Calculate statistics
    $stepStats = @()
    $steps = @{}
    foreach ($entry in $state.Entries) {
        $stepName = $entry.step
        if (-not $steps.ContainsKey($stepName)) {
            $steps[$stepName] = @{
                Name = $stepName
                Before = $null
                After = $null
                DurationMs = 0
            }
        }
        
        if ($entry.status -eq 'before') {
            $steps[$stepName].Before = $entry.timestamp
        }
        elseif ($entry.status -eq 'after' -and $entry.durationMs) {
            $steps[$stepName].After = $entry.timestamp
            $steps[$stepName].DurationMs = $entry.durationMs
        }
    }
    
    foreach ($stepName in $steps.Keys) {
        $step = $steps[$stepName]
        $stepStats += [pscustomobject]@{
            Step = $stepName
            Status = if ($step.After) { "Complete" } elseif ($step.Before) { "In Progress" } else { "Pending" }
            DurationMs = $step.DurationMs
            Duration = if ($step.DurationMs -gt 0) { 
                $ts = [TimeSpan]::FromMilliseconds($step.DurationMs)
                "{0:mm\:ss\.fff}" -f $ts
            } else { "N/A" }
        }
    }
    
    # Build report object
    $report = [ordered]@{
        runId = $RunId
        command = if ($state.Manifest) { $state.Manifest.command } else { "unknown" }
        startedAt = if ($state.Manifest) { $state.Manifest.startedAt } else { "unknown" }
        status = $state.Manifest.exitStatus
        exitCode = $state.Manifest.exitCode
        completedSteps = $state.CompletedSteps
        pendingSteps = $state.PendingSteps
        failedSteps = $state.FailedSteps
        canResume = $state.CanResume
        isComplete = $state.IsComplete
        stepStatistics = $stepStats
        totalSteps = ($state.CompletedSteps.Count + $state.PendingSteps.Count)
        progressPercent = if (($state.CompletedSteps.Count + $state.PendingSteps.Count) -gt 0) {
            [math]::Round(($state.CompletedSteps.Count / ($state.CompletedSteps.Count + $state.PendingSteps.Count)) * 100, 1)
        } else { 0 }
    }
    
    switch ($Format) {
        'json' {
            return $report | ConvertTo-Json -Depth 10
        }
        'object' {
            return [pscustomobject]$report
        }
        default {
            # Text format
            $lines = @()
            $lines += "=" * 60
            $lines += "Journal Report: $RunId"
            $lines += "=" * 60
            $lines += ""
            $lines += "Command:    $($report.command)"
            $lines += "Started:    $($report.startedAt)"
            $lines += "Status:     $($report.status)"
            if ($null -ne $report.exitCode) {
                $lines += "Exit Code:  $($report.exitCode)"
            }
            $lines += ""
            $lines += "Progress:   $($report.progressPercent)% ($($state.CompletedSteps.Count) of $($report.totalSteps) steps)"
            $lines += ""
            
            if ($stepStats.Count -gt 0) {
                $lines += "Step Details:"
                $lines += "-" * 40
                foreach ($stat in $stepStats | Sort-Object Step) {
                    $statusSymbol = switch ($stat.Status) {
                        'Complete' { "[x]" }
                        'In Progress' { "[~]" }
                        default { "[ ]" }
                    }
                    $lines += "  $statusSymbol $($stat.Step.PadRight(20)) $($stat.Duration.PadLeft(12))"
                }
                $lines += ""
            }
            
            if ($state.CanResume) {
                $lines += "Resume:     Available (use --resume flag)"
            }
            if ($state.CanRestart) {
                $lines += "Restart:    Available (use --restart flag)"
            }
            
            $lines += ""
            $lines += "=" * 60
            
            return $lines -join "`n"
        }
    }
}

<#
.SYNOPSIS
    Helper function to write JSON files atomically.
.DESCRIPTION
    Writes JSON data to a file using temp file + rename for atomicity.
.PARAMETER Path
    The target file path.
.PARAMETER Data
    The data to serialize to JSON.
#>
function Write-JsonFileAtomic {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path,
        
        [Parameter(Mandatory = $true)]
        [object]$Data
    )
    
    $directory = Split-Path -Parent $Path
    
    # Ensure directory exists
    if (-not (Test-Path -LiteralPath $directory)) {
        New-Item -ItemType Directory -Path $directory -Force | Out-Null
    }
    
    # Convert to JSON
    $json = $Data | ConvertTo-Json -Depth 10
    
    # Ensure ASCII-safe for cross-platform compatibility
    $bytes = [System.Text.Encoding]::UTF8.GetBytes($json)
    
    # Write to temp file
    $tempFile = [System.IO.Path]::GetTempFileName()
    
    try {
        [System.IO.File]::WriteAllBytes($tempFile, $bytes)
        
        # Atomic rename (Move with overwrite)
        [System.IO.File]::Move($tempFile, $Path, $true)
    }
    finally {
        # Cleanup temp file if it still exists
        if (Test-Path -LiteralPath $tempFile) {
            Remove-Item -LiteralPath $tempFile -Force -ErrorAction SilentlyContinue
        }
    }
}

<#
.SYNOPSIS
    Adds an artifact to the run manifest.
.DESCRIPTION
    Records an artifact that was written during the run.
.PARAMETER RunId
    The run ID.
.PARAMETER ArtifactPath
    The path to the artifact.
.PARAMETER ArtifactType
    The type of artifact (e.g., "file", "directory", "database").
.PARAMETER Checksum
    Optional checksum of the artifact.
.PARAMETER ManifestDirectory
    The directory where manifests are stored.
#>
function Add-RunArtifact {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$RunId,
        
        [Parameter(Mandatory = $true)]
        [string]$ArtifactPath,
        
        [Parameter()]
        [string]$ArtifactType = "file",
        
        [Parameter()]
        [string]$Checksum = "",
        
        [Parameter()]
        [string]$ManifestDirectory = $script:DefaultManifestDirectory
    )
    
    $manifestPath = Join-Path $ManifestDirectory "$RunId.run.json"
    
    if (-not (Test-Path -LiteralPath $manifestPath)) {
        Write-Warning "[Journal] Run manifest not found: $manifestPath"
        return
    }
    
    try {
        $manifest = Get-Content -LiteralPath $manifestPath -Raw | ConvertFrom-Json -AsHashtable
        
        $artifact = @{
            path = $ArtifactPath
            type = $ArtifactType
            timestamp = [DateTime]::UtcNow.ToString("yyyy-MM-ddTHH:mm:ssZ", [System.Globalization.CultureInfo]::InvariantCulture)
        }
        
        if ($Checksum) {
            $artifact['checksum'] = $Checksum
        }
        
        if (-not $manifest.ContainsKey('artifactsWritten')) {
            $manifest['artifactsWritten'] = @()
        }
        
        $manifest['artifactsWritten'] += $artifact
        $manifest['updatedUtc'] = [DateTime]::UtcNow.ToString("yyyy-MM-ddTHH:mm:ssZ", [System.Globalization.CultureInfo]::InvariantCulture)
        
        Write-JsonFileAtomic -Path $manifestPath -Data $manifest
        Write-Verbose "[Journal] Added artifact to manifest: $ArtifactPath"
    }
    catch {
        Write-Warning "[Journal] Failed to add artifact: $_"
    }
}

# Export functions
Export-ModuleMember -Function @(
    'New-RunManifest',
    'Complete-RunManifest',
    'New-JournalEntry',
    'Get-JournalState',
    'Export-JournalReport',
    'Add-RunArtifact'
)
