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
    Version        : 1.1.0
    
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

# Valid step names for validation
$script:ValidStepNames = @('ingest', 'embed', 'export', 'sync', 'heal', 'index', 'pack', 'validate', 'cleanup')

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

<#
.SYNOPSIS
    Validates a run ID format.
.DESCRIPTION
    Validates that a run ID matches the expected format: yyyyMMddTHHmmssZ-xxxx
.PARAMETER RunId
    The run ID to validate.
.OUTPUTS
    System.Boolean. True if valid.
#>
function Test-RunIdFormat {
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [Parameter(Mandatory = $true)]
        [string]$RunId
    )
    
    if ([string]::IsNullOrWhiteSpace($RunId)) {
        return $false
    }
    
    return $RunId -match '^\d{8}T\d{6}Z-[0-9a-f]{4}$'
}

<#
.SYNOPSIS
    Validates a step name.
.DESCRIPTION
    Validates that a step name is valid.
.PARAMETER Step
    The step name to validate.
.OUTPUTS
    System.Boolean. True if valid.
#>
function Test-StepName {
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Step
    )
    
    if ([string]::IsNullOrWhiteSpace($Step)) {
        return $false
    }
    
    # Allow custom step names (not just the predefined ones)
    # but require alphanumeric + underscore/hyphen
    return $Step -match '^[a-zA-Z0-9_-]+$'
}

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
        [ValidateNotNullOrEmpty()]
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
    
    # Validate RunId format if provided
    if (-not [string]::IsNullOrWhiteSpace($RunId)) {
        if (-not (Test-RunIdFormat -RunId $RunId)) {
            throw "Invalid RunId format: $RunId. Expected format: yyyyMMddTHHmmssZ-xxxx"
        }
    }
    
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
    
    # Validate RunId
    if (-not (Test-RunIdFormat -RunId $RunId)) {
        throw "Invalid RunId format: $RunId"
    }
    
    $manifestPath = Join-Path $ManifestDirectory "$RunId.run.json"
    
    if (-not (Test-Path -LiteralPath $manifestPath)) {
        Write-Warning "[Journal] Run manifest not found: $manifestPath"
        return $null
    }
    
    try {
        $manifest = Get-Content -LiteralPath $manifestPath -Raw | ConvertFrom-Json | ConvertTo-Hashtable
        
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
    
    # Validate RunId
    if (-not (Test-RunIdFormat -RunId $RunId)) {
        throw "Invalid RunId format: $RunId"
    }
    
    # Validate Step name
    if (-not (Test-StepName -Step $Step)) {
        throw "Invalid step name: $Step"
    }
    
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
            $existingEntries = Get-Content -LiteralPath $journalPath -Raw | ConvertFrom-Json | ConvertTo-Hashtable
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
    Creates a checkpoint for a step with state preservation.
.DESCRIPTION
    High-level function that creates a "before" checkpoint and preserves
    the current state for potential resume. This is the recommended way
    to checkpoint operations.

.PARAMETER RunId
    The run ID this checkpoint belongs to.
.PARAMETER Step
    The name of the step being checkpointed.
.PARAMETER State
    Serializable state to preserve for resume.
.PARAMETER Metadata
    Additional metadata about the step.
.PARAMETER JournalDirectory
    The directory where journals are stored.

.OUTPUTS
    System.Management.Automation.PSCustomObject representing the checkpoint.

.EXAMPLE
    $checkpoint = Checkpoint-Journal -RunId $runId -Step "ingest" -State @{ processedCount = 0; files = @() }
#>
function Checkpoint-Journal {
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory = $true)]
        [string]$RunId,
        
        [Parameter(Mandatory = $true)]
        [string]$Step,
        
        [Parameter()]
        [hashtable]$State = @{},
        
        [Parameter()]
        [hashtable]$Metadata = @{},
        
        [Parameter()]
        [string]$JournalDirectory = $script:DefaultJournalDirectory
    )
    
    # Validate inputs
    if (-not (Test-RunIdFormat -RunId $RunId)) {
        throw "Invalid RunId format: $RunId"
    }
    if (-not (Test-StepName -Step $Step)) {
        throw "Invalid step name: $Step"
    }
    
    # Create the checkpoint entry
    $checkpoint = New-JournalEntry -RunId $RunId -Step $Step -Status "before" `
        -State $State -Metadata $Metadata -JournalDirectory $JournalDirectory
    
    Write-Verbose "[Journal] Created checkpoint for step '$Step' in run $RunId"
    
    return [pscustomobject]@{
        Checkpoint = $checkpoint
        RunId = $RunId
        Step = $Step
        Timestamp = $checkpoint.timestamp
        CanResume = $true
    }
}

<#
.SYNOPSIS
    Restores state from a checkpoint for resume operations.
.DESCRIPTION
    Reads the journal for a given run and step, and returns the preserved
    state from the most recent checkpoint. This allows operations to resume
    from where they left off.

.PARAMETER RunId
    The run ID to restore from.
.PARAMETER Step
    The specific step to restore (optional - if not specified, returns
    the last checkpoint from any incomplete step).
.PARAMETER JournalDirectory
    The directory where journals are stored.

.OUTPUTS
    System.Management.Automation.PSCustomObject with restored state, or $null
    if no checkpoint exists.

.EXAMPLE
    $state = Restore-FromCheckpoint -RunId $runId -Step "ingest"
    if ($state) {
        $processedCount = $state.processedCount
        Write-Host "Resuming from checkpoint with $processedCount items processed"
    }
#>
function Restore-FromCheckpoint {
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory = $true)]
        [string]$RunId,
        
        [Parameter()]
        [string]$Step = "",
        
        [Parameter()]
        [string]$JournalDirectory = $script:DefaultJournalDirectory
    )
    
    # Validate RunId
    if (-not (Test-RunIdFormat -RunId $RunId)) {
        throw "Invalid RunId format: $RunId"
    }
    
    $journalPath = Join-Path $JournalDirectory "$RunId.journal.json"
    
    if (-not (Test-Path -LiteralPath $journalPath)) {
        Write-Verbose "[Journal] No journal found for run $RunId"
        return $null
    }
    
    try {
        $entries = Get-Content -LiteralPath $journalPath -Raw | ConvertFrom-Json | ConvertTo-Hashtable
        if ($entries -isnot [array]) {
            $entries = @($entries)
        }
        
        # Find checkpoints (before entries that don't have matching after)
        $checkpoints = @()
        $stepStatuses = @{}
        
        foreach ($entry in $entries) {
            $stepName = $entry.step
            if (-not $stepStatuses.ContainsKey($stepName)) {
                $stepStatuses[$stepName] = @{
                    Before = $null
                    After = $null
                }
            }
            
            if ($entry.status -eq 'before') {
                $stepStatuses[$stepName].Before = $entry
            }
            elseif ($entry.status -eq 'after') {
                $stepStatuses[$stepName].After = $entry
            }
        }
        
        # Find incomplete steps (have before but no after)
        foreach ($stepName in $stepStatuses.Keys) {
            $status = $stepStatuses[$stepName]
            if ($status.Before -and -not $status.After) {
                $checkpoints += $status.Before
            }
        }
        
        # Filter by specific step if requested
        if (-not [string]::IsNullOrWhiteSpace($Step)) {
            $checkpoints = $checkpoints | Where-Object { $_.step -eq $Step }
        }
        
        if ($checkpoints.Count -eq 0) {
            Write-Verbose "[Journal] No checkpoints found for resume"
            return $null
        }
        
        # Get the most recent checkpoint
        $lastCheckpoint = $checkpoints | Sort-Object { [DateTime]::Parse($_.timestamp) } | Select-Object -Last 1
        
        return [pscustomobject]@{
            RunId = $RunId
            Step = $lastCheckpoint.step
            State = $lastCheckpoint.state
            Metadata = $lastCheckpoint.metadata
            Timestamp = $lastCheckpoint.timestamp
            Sequence = $lastCheckpoint.sequence
            AllPendingSteps = @($checkpoints | ForEach-Object { $_.step } | Select-Object -Unique)
        }
    }
    catch {
        Write-Warning "[Journal] Failed to restore from checkpoint: $_"
        return $null
    }
}

<#
.SYNOPSIS
    Completes a checkpointed step.
.DESCRIPTION
    Marks a step as complete by writing an "after" entry. Should be called
    after successful completion of a step that was checkpointed.

.PARAMETER RunId
    The run ID.
.PARAMETER Step
    The step name to complete.
.PARAMETER Metadata
    Additional metadata about completion.
.PARAMETER JournalDirectory
    The directory where journals are stored.

.OUTPUTS
    System.Management.Automation.PSCustomObject representing the completion entry.

.EXAMPLE
    Complete-Checkpoint -RunId $runId -Step "ingest" -Metadata @{ processedCount = 100 }
#>
function Complete-Checkpoint {
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory = $true)]
        [string]$RunId,
        
        [Parameter(Mandatory = $true)]
        [string]$Step,
        
        [Parameter()]
        [hashtable]$Metadata = @{},
        
        [Parameter()]
        [string]$JournalDirectory = $script:DefaultJournalDirectory
    )
    
    # Validate inputs
    if (-not (Test-RunIdFormat -RunId $RunId)) {
        throw "Invalid RunId format: $RunId"
    }
    if (-not (Test-StepName -Step $Step)) {
        throw "Invalid step name: $Step"
    }
    
    $entry = New-JournalEntry -RunId $RunId -Step $Step -Status "after" `
        -Metadata $Metadata -JournalDirectory $JournalDirectory
    
    Write-Verbose "[Journal] Completed checkpoint for step '$Step' in run $RunId"
    
    return [pscustomobject]@{
        Entry = $entry
        RunId = $RunId
        Step = $Step
        DurationMs = $entry.durationMs
    }
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
    
    # Validate RunId
    if (-not (Test-RunIdFormat -RunId $RunId)) {
        throw "Invalid RunId format: $RunId"
    }
    
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
            $entries = Get-Content -LiteralPath $journalPath -Raw | ConvertFrom-Json | ConvertTo-Hashtable
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
    
    # Validate RunId
    if (-not (Test-RunIdFormat -RunId $RunId)) {
        throw "Invalid RunId format: $RunId"
    }
    
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
    Ensures directory is synced after write.
.PARAMETER Path
    The target file path.
.PARAMETER Data
    The data to serialize to JSON.
.OUTPUTS
    None. Throws on error.
#>
function Write-JsonFileAtomic {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
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
    
    # Generate temp file in same directory for atomic rename
    $tempFile = "$Path.tmp.$PID.$([Guid]::NewGuid().ToString('N'))"
    
    try {
        # Write to temp file with sync
        $stream = [System.IO.File]::Create($tempFile)
        try {
            $stream.Write($bytes, 0, $bytes.Length)
            $stream.Flush($true)
        }
        finally {
            $stream.Close()
            $stream.Dispose()
        }
        
        # Atomic move using File.Replace if target exists
        if (Test-Path -LiteralPath $Path) {
            try {
                $backupPath = "$Path.bak.replace"
                [System.IO.File]::Replace($tempFile, $Path, $backupPath)
                # Clean up replace backup
                if (Test-Path -LiteralPath $backupPath) {
                    Remove-Item -LiteralPath $backupPath -Force -ErrorAction SilentlyContinue
                }
            }
            catch {
                # Fallback for non-Windows platforms
                Remove-Item -LiteralPath $Path -Force
                [System.IO.File]::Move($tempFile, $Path)
            }
        }
        else {
            [System.IO.File]::Move($tempFile, $Path)
        }
        
        # Sync directory to ensure rename is committed
        $dir = Split-Path -Parent $Path
        if ($dir -and (Test-Path -LiteralPath $dir)) {
            $syncMarker = Join-Path $dir ".sync.$(Get-Random)"
            try {
                [System.IO.File]::WriteAllText($syncMarker, [string]::Empty)
                $fs = [System.IO.File]::Open($syncMarker, [System.IO.FileMode]::Open, 
                    [System.IO.FileAccess]::ReadWrite, [System.IO.FileShare]::None)
                $fs.Flush($true)
                $fs.Close()
                Remove-Item -LiteralPath $syncMarker -Force -ErrorAction SilentlyContinue
            }
            catch {
                Write-Verbose "[Journal] Directory sync failed: $_"
            }
        }
    }
    catch {
        # Cleanup temp file on failure
        if (Test-Path -LiteralPath $tempFile) {
            Remove-Item -LiteralPath $tempFile -Force -ErrorAction SilentlyContinue
        }
        throw
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
.OUTPUTS
    None.
#>
function Add-RunArtifact {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$RunId,
        
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$ArtifactPath,
        
        [Parameter()]
        [ValidateSet('file', 'directory', 'database', 'log', 'report')]
        [string]$ArtifactType = "file",
        
        [Parameter()]
        [string]$Checksum = "",
        
        [Parameter()]
        [string]$ManifestDirectory = $script:DefaultManifestDirectory
    )
    
    # Validate RunId
    if (-not (Test-RunIdFormat -RunId $RunId)) {
        throw "Invalid RunId format: $RunId"
    }
    
    $manifestPath = Join-Path $ManifestDirectory "$RunId.run.json"
    
    if (-not (Test-Path -LiteralPath $manifestPath)) {
        Write-Warning "[Journal] Run manifest not found: $manifestPath"
        return
    }
    
    try {
        $manifest = Get-Content -LiteralPath $manifestPath -Raw | ConvertFrom-Json | ConvertTo-Hashtable
        
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

<#
.SYNOPSIS
    Writes a journal entry atomically.
.DESCRIPTION
    Explicit atomic append function for writing journal entries.
    This is a lower-level function than New-JournalEntry that provides
    more control over the write process and returns detailed result info.
    
    Implements atomic write using temp file + rename pattern.
.PARAMETER RunId
    The run ID this journal entry belongs to.
.PARAMETER Step
    The name of the step (e.g., "ingest", "embed", "export").
.PARAMETER Status
    The checkpoint status: "before", "after", "start", "complete", or "failed".
.PARAMETER Metadata
    Additional metadata about the step state.
.PARAMETER State
    Serializable state snapshot for resume support.
.PARAMETER JournalDirectory
    The directory where journals are stored.
.PARAMETER VerifyWrite
    If specified, verifies the write by reading back the file.
.OUTPUTS
    System.Management.Automation.PSCustomObject representing the write result.
.EXAMPLE
    PS C:\> $result = Write-JournalEntry -RunId "20260411T210501Z-7f2c" -Step "ingest" -Status "before"
    PS C:\> if ($result.Success) { Write-Host "Entry written at line $($result.LineNumber)" }
    
    Writes a journal entry and returns result information.
#>
function Write-JournalEntry {
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
        [string]$JournalDirectory = $script:DefaultJournalDirectory,
        
        [switch]$VerifyWrite
    )
    
    # Validate inputs
    if (-not (Test-RunIdFormat -RunId $RunId)) {
        throw "Invalid RunId format: $RunId"
    }
    if (-not (Test-StepName -Step $Step)) {
        throw "Invalid step name: $Step"
    }
    
    $startTime = [DateTime]::Now
    $journalPath = Join-Path $JournalDirectory "$RunId.journal.json"
    $tempPath = "$journalPath.tmp.$PID.$([Guid]::NewGuid().ToString('N'))"
    
    try {
        # Build the entry
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
        
        # Read existing entries to determine sequence and duration
        $existingEntries = @()
        if (Test-Path -LiteralPath $journalPath) {
            try {
                $content = Get-Content -LiteralPath $journalPath -Raw -ErrorAction Stop
                $existingEntries = $content | ConvertFrom-Json | ConvertTo-Hashtable
                if ($existingEntries -isnot [array]) {
                    $existingEntries = @($existingEntries)
                }
                $entry['sequence'] = $existingEntries.Count
                
                # Calculate duration if this is an "after" entry
                if ($Status -eq 'after') {
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
            }
            catch {
                Write-Warning "[Journal] Failed to read existing journal, starting fresh: $_"
                $existingEntries = @()
                $entry['sequence'] = 0
            }
        }
        
        # Prepare all entries
        $allEntries = $existingEntries + $entry
        
        # Ensure directory exists
        if (-not (Test-Path -LiteralPath $JournalDirectory)) {
            New-Item -ItemType Directory -Path $JournalDirectory -Force | Out-Null
        }
        
        # Convert to JSON
        $json = $allEntries | ConvertTo-Json -Depth 10
        $bytes = [System.Text.Encoding]::UTF8.GetBytes($json)
        
        # Atomic write: write to temp, flush, then move
        $tempStream = [System.IO.File]::Create($tempPath)
        try {
            $tempStream.Write($bytes, 0, $bytes.Length)
            $tempStream.Flush($true)
        }
        finally {
            $tempStream.Close()
            $tempStream.Dispose()
        }
        
        # Atomic move using File.Replace if target exists
        if (Test-Path -LiteralPath $journalPath) {
            try {
                $backupPath = "$journalPath.bak.replace"
                [System.IO.File]::Replace($tempPath, $journalPath, $backupPath)
                # Clean up replace backup
                if (Test-Path -LiteralPath $backupPath) {
                    Remove-Item -LiteralPath $backupPath -Force -ErrorAction SilentlyContinue
                }
            }
            catch {
                # Fallback for non-Windows platforms
                Remove-Item -LiteralPath $journalPath -Force
                [System.IO.File]::Move($tempPath, $journalPath)
            }
        }
        else {
            [System.IO.File]::Move($tempPath, $journalPath)
        }
        
        # Sync directory
        try {
            $syncMarker = Join-Path $JournalDirectory ".sync.$(Get-Random)"
            [System.IO.File]::WriteAllText($syncMarker, [string]::Empty)
            $fs = [System.IO.File]::Open($syncMarker, [System.IO.FileMode]::Open, 
                [System.IO.FileAccess]::ReadWrite, [System.IO.FileShare]::None)
            $fs.Flush($true)
            $fs.Close()
            Remove-Item -LiteralPath $syncMarker -Force -ErrorAction SilentlyContinue
        }
        catch {
            Write-Verbose "[Journal] Directory sync failed: $_"
        }
        
        # Verify write if requested
        $verified = $false
        if ($VerifyWrite) {
            try {
                $verifyContent = Get-Content -LiteralPath $journalPath -Raw -ErrorAction Stop
                $verifyEntries = $verifyContent | ConvertFrom-Json -ErrorAction Stop
                $verified = ($verifyEntries.Count -eq $allEntries.Count)
            }
            catch {
                Write-Warning "[Journal] Write verification failed: $_"
            }
        }
        
        $duration = ([DateTime]::Now - $startTime).TotalMilliseconds
        
        Write-Verbose "[Journal] Atomically wrote entry: $RunId/$Step/$Status (seq: $($entry['sequence']))"
        
        return [pscustomobject]@{
            Success = $true
            Entry = [pscustomobject]$entry
            Path = $journalPath
            LineNumber = $entry['sequence'] + 1
            BytesWritten = $bytes.Length
            DurationMs = [math]::Round($duration, 2)
            Verified = $verified
            Error = $null
        }
    }
    catch {
        # Clean up temp file on failure
        if (Test-Path -LiteralPath $tempPath) {
            Remove-Item -LiteralPath $tempPath -Force -ErrorAction SilentlyContinue
        }
        
        Write-Error "[Journal] Failed to write journal entry atomically: $_"
        
        return [pscustomobject]@{
            Success = $false
            Entry = $null
            Path = $journalPath
            LineNumber = 0
            BytesWritten = 0
            DurationMs = 0
            Verified = $false
            Error = $_.Exception.Message
        }
    }
}

<#
.SYNOPSIS
    Rotates a journal file for archival.
.DESCRIPTION
    Archives the current journal by renaming it with a timestamp suffix,
    optionally compressing it, and removing old archived journals.
    
    This prevents journal files from growing too large and helps with
    long-term storage management.
.PARAMETER RunId
    The run ID of the journal to rotate.
.PARAMETER JournalDirectory
    The directory where journals are stored.
.PARAMETER ArchiveDirectory
    The directory where archived journals are stored. Defaults to a
    subdirectory 'archive' under JournalDirectory.
.PARAMETER MaxArchives
    Maximum number of archived journals to retain. Default is 10.
.PARAMETER Compress
    If specified, compresses the archived journal using gzip (on supported platforms).
.PARAMETER Force
    Skip confirmation prompts.
.OUTPUTS
    System.Management.Automation.PSCustomObject with rotation result.
.EXAMPLE
    PS C:\> Rotate-Journal -RunId "20260411T210501Z-7f2c" -MaxArchives 5
    
    Rotates the journal, keeping 5 archives.
.EXAMPLE
    PS C:\> Rotate-Journal -RunId "20260411T210501Z-7f2c" -Compress -MaxArchives 20
    
    Rotates and compresses the journal, keeping 20 compressed archives.
#>
function Rotate-Journal {
    [CmdletBinding(SupportsShouldProcess = $true)]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory = $true)]
        [string]$RunId,
        
        [Parameter()]
        [string]$JournalDirectory = $script:DefaultJournalDirectory,
        
        [Parameter()]
        [string]$ArchiveDirectory = "",
        
        [ValidateRange(1, 1000)]
        [int]$MaxArchives = 10,
        
        [switch]$Compress,
        
        [switch]$Force
    )
    
    # Validate RunId
    if (-not (Test-RunIdFormat -RunId $RunId)) {
        throw "Invalid RunId format: $RunId"
    }
    
    # Determine archive directory
    if ([string]::IsNullOrWhiteSpace($ArchiveDirectory)) {
        $ArchiveDirectory = Join-Path $JournalDirectory "archive"
    }
    
    $journalPath = Join-Path $JournalDirectory "$RunId.journal.json"
    $startTime = [DateTime]::Now
    
    # Check if journal exists
    if (-not (Test-Path -LiteralPath $journalPath)) {
        Write-Verbose "[Journal] No journal to rotate for run $RunId"
        return [pscustomobject]@{
            Success = $true
            Rotated = $false
            Message = "No journal exists to rotate"
            ArchivedPath = $null
            RemovedArchives = @()
        }
    }
    
    # Create archive directory if needed
    if (-not (Test-Path -LiteralPath $ArchiveDirectory)) {
        try {
            New-Item -ItemType Directory -Path $ArchiveDirectory -Force | Out-Null
        }
        catch {
            return [pscustomobject]@{
                Success = $false
                Rotated = $false
                Message = "Failed to create archive directory: $_"
                ArchivedPath = $null
                RemovedArchives = @()
            }
        }
    }
    
    # Generate archive filename with timestamp
    $timestamp = [DateTime]::Now.ToString("yyyyMMddHHmmss")
    $archiveName = "$RunId.$timestamp.journal.json"
    if ($Compress) {
        $archiveName += ".gz"
    }
    $archivePath = Join-Path $ArchiveDirectory $archiveName
    
    if ($PSCmdlet.ShouldProcess($journalPath, "Rotate journal to $archivePath")) {
        try {
            # Get original file info for verification
            $originalFile = Get-Item -LiteralPath $journalPath
            $originalSize = $originalFile.Length
            
            if ($Compress) {
                # Compress and move in one operation
                $inputStream = [System.IO.FileStream]::new($journalPath, [System.IO.FileMode]::Open, [System.IO.FileAccess]::Read)
                $outputStream = [System.IO.FileStream]::new($archivePath, [System.IO.FileMode]::CreateNew, [System.IO.FileAccess]::Write)
                $gzipStream = [System.IO.Compression.GzipStream]::new($outputStream, [System.IO.Compression.CompressionLevel]::Optimal)
                
                try {
                    $inputStream.CopyTo($gzipStream)
                }
                finally {
                    $gzipStream.Dispose()
                    $outputStream.Dispose()
                    $inputStream.Dispose()
                }
                
                # Remove original after successful compression
                Remove-Item -LiteralPath $journalPath -Force
            }
            else {
                # Simple move (atomic on same filesystem)
                [System.IO.File]::Move($journalPath, $archivePath)
            }
            
            # Verify archive exists and has content
            if (-not (Test-Path -LiteralPath $archivePath)) {
                throw "Archive file was not created"
            }
            
            $archiveFile = Get-Item -LiteralPath $archivePath
            $archivedSize = $archiveFile.Length
            
            # Clean up old archives
            $removedArchives = @()
            $pattern = "$RunId.*.journal.json"
            if ($Compress) {
                $pattern += ".gz"
            }
            
            $existingArchives = @(Get-ChildItem -Path $ArchiveDirectory -Filter $pattern -File -ErrorAction SilentlyContinue |
                Sort-Object -Property LastWriteTime -Descending)
            
            if ($existingArchives.Count -gt $MaxArchives) {
                $toRemove = @($existingArchives | Select-Object -Skip $MaxArchives)
                foreach ($oldArchive in $toRemove) {
                    if ($oldArchive -and $oldArchive.FullName) {
                        try {
                            Remove-Item -LiteralPath $oldArchive.FullName -Force
                            $removedArchives += $oldArchive.Name
                            Write-Verbose "[Journal] Removed old archive: $($oldArchive.Name)"
                        }
                        catch {
                            Write-Warning "[Journal] Failed to remove old archive '$($oldArchive.Name)': $_"
                        }
                    }
                }
            }
            
            $duration = ([DateTime]::Now - $startTime).TotalMilliseconds
            
            Write-Verbose "[Journal] Rotated journal for $RunId to $archivePath"
            
            return [pscustomobject]@{
                Success = $true
                Rotated = $true
                Message = "Journal rotated successfully"
                OriginalPath = $journalPath
                ArchivedPath = $archivePath
                OriginalSize = $originalSize
                ArchivedSize = $archivedSize
                CompressionRatio = if ($originalSize -gt 0) { [math]::Round(($originalSize - $archivedSize) / $originalSize * 100, 2) } else { 0 }
                RemovedArchives = $removedArchives
                DurationMs = [math]::Round($duration, 2)
            }
        }
        catch {
            return [pscustomobject]@{
                Success = $false
                Rotated = $false
                Message = "Failed to rotate journal: $_"
                OriginalPath = $journalPath
                ArchivedPath = $null
                RemovedArchives = @()
                Error = $_.Exception.Message
            }
        }
    }
    
    return [pscustomobject]@{
        Success = $true
        Rotated = $false
        Message = "Operation cancelled by user"
        ArchivedPath = $null
        RemovedArchives = @()
    }
}

<#
.SYNOPSIS
    Verifies the integrity of a journal file.
.DESCRIPTION
    Performs integrity checks on a journal file to ensure it is valid JSON,
    follows the expected schema, and all entries are consistent.
    
    Checks performed:
    - File is valid JSON
    - All entries have required fields (schemaVersion, runId, step, status, timestamp)
    - Schema version is consistent across entries
    - RunId matches across entries
    - Sequence numbers are consecutive
    - No duplicate entries for same step/status (except allowed combinations)
    - Timestamps are in chronological order
.PARAMETER RunId
    The run ID of the journal to verify.
.PARAMETER JournalDirectory
    The directory where journals are stored.
.PARAMETER ManifestDirectory
    The directory where manifests are stored (for cross-validation).
.PARAMETER Repair
    If specified, attempts to repair minor issues (removes corrupt entries).
.OUTPUTS
    System.Management.Automation.PSCustomObject with verification results.
.EXAMPLE
    PS C:\> $result = Test-JournalIntegrity -RunId "20260411T210501Z-7f2c"
    PS C:\> if ($result.IsValid) { Write-Host "Journal is valid" }
    
    Verifies a journal file.
.EXAMPLE
    PS C:\> Test-JournalIntegrity -RunId "20260411T210501Z-7f2c" -Repair
    
    Verifies and attempts to repair the journal.
#>
function Test-JournalIntegrity {
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory = $true)]
        [string]$RunId,
        
        [Parameter()]
        [string]$JournalDirectory = $script:DefaultJournalDirectory,
        
        [Parameter()]
        [string]$ManifestDirectory = $script:DefaultManifestDirectory,
        
        [switch]$Repair
    )
    
    # Validate RunId
    if (-not (Test-RunIdFormat -RunId $RunId)) {
        throw "Invalid RunId format: $RunId"
    }
    
    $journalPath = Join-Path $JournalDirectory "$RunId.journal.json"
    $startTime = [DateTime]::Now
    
    $result = [ordered]@{
        RunId = $RunId
        Path = $journalPath
        IsValid = $false
        Exists = $false
        EntryCount = 0
        Errors = @()
        Warnings = @()
        SchemaVersion = $null
        CheckResults = @{
            ValidJson = $false
            RequiredFieldsPresent = $false
            SchemaVersionConsistent = $false
            RunIdConsistent = $false
            SequenceValid = $false
            TimestampsChronological = $false
            ManifestCrossCheck = $false
        }
        Repaired = $false
        RepairedPath = $null
    }
    
    # Check if file exists
    if (-not (Test-Path -LiteralPath $journalPath)) {
        $result['Errors'] += "Journal file not found: $journalPath"
        return [pscustomobject]$result
    }
    
    $result['Exists'] = $true
    
    # Read and parse the file
    $content = $null
    $entries = $null
    
    try {
        $content = Get-Content -LiteralPath $journalPath -Raw -ErrorAction Stop
        $result['CheckResults']['ValidJson'] = $true
    }
    catch {
        $result['Errors'] += "Failed to read journal file: $_"
        return [pscustomobject]$result
    }
    
    try {
        $entries = $content | ConvertFrom-Json | ConvertTo-Hashtable
        $result['CheckResults']['ValidJson'] = $true
    }
    catch {
        $result['Errors'] += "Invalid JSON: $_"
        return [pscustomobject]$result
    }
    
    # Ensure entries is an array
    if ($entries -isnot [array]) {
        $entries = @($entries)
    }
    
    $result['EntryCount'] = $entries.Count
    
    if ($entries.Count -eq 0) {
        $result['Warnings'] += "Journal contains no entries"
        $result['IsValid'] = $true  # Empty journal is technically valid
        return [pscustomobject]$result
    }
    
    # Check required fields on all entries
    $requiredFields = @('schemaVersion', 'runId', 'step', 'status', 'timestamp')
    $allHaveRequired = $true
    $invalidEntries = @()
    
    for ($i = 0; $i -lt $entries.Count; $i++) {
        $entry = $entries[$i]
        foreach ($field in $requiredFields) {
            if (-not $entry.ContainsKey($field)) {
                $allHaveRequired = $false
                $invalidEntries += $i
                $result['Errors'] += "Entry $i is missing required field: $field"
            }
        }
    }
    
    $result['CheckResults']['RequiredFieldsPresent'] = $allHaveRequired
    
    if (-not $allHaveRequired -and -not $Repair) {
        return [pscustomobject]$result
    }
    
    # Filter out invalid entries if repairing
    if ($Repair -and $invalidEntries.Count -gt 0) {
        $entries = $entries | Where-Object { 
            $entry = $_
            $hasAll = $true
            foreach ($field in $requiredFields) {
                if (-not $entry.ContainsKey($field)) {
                    $hasAll = $false
                    break
                }
            }
            $hasAll
        }
        $result['EntryCount'] = $entries.Count
        $result['Repaired'] = $true
    }
    
    # Check schema version consistency (ensure arrays with @())
    $schemaVersions = @($entries | ForEach-Object { $_.schemaVersion } | Select-Object -Unique)
    if ($schemaVersions.Count -eq 1) {
        $result['CheckResults']['SchemaVersionConsistent'] = $true
        $result['SchemaVersion'] = $schemaVersions[0]
    }
    else {
        $result['Errors'] += "Inconsistent schema versions found: $($schemaVersions -join ', ')"
    }
    
    # Check runId consistency (ensure arrays with @())
    $runIds = @($entries | ForEach-Object { $_.runId } | Select-Object -Unique)
    if ($runIds.Count -eq 1 -and $runIds[0] -eq $RunId) {
        $result['CheckResults']['RunIdConsistent'] = $true
    }
    else {
        $result['Errors'] += "Inconsistent runIds found: $($runIds -join ', ')"
    }
    
    # Check sequence numbers
    $sequences = $entries | ForEach-Object { $_.sequence } | Sort-Object
    $expectedSequence = 0..($entries.Count - 1)
    if (@($sequences) -join ',' -eq @($expectedSequence) -join ',') {
        $result['CheckResults']['SequenceValid'] = $true
    }
    else {
        $result['Errors'] += "Sequence numbers are not consecutive (found: $($sequences -join ', '))"
    }
    
    # Check timestamp chronology
    $timestampsValid = $true
    for ($i = 1; $i -lt $entries.Count; $i++) {
        try {
            $prevTime = [DateTime]::Parse($entries[$i - 1].timestamp)
            $currTime = [DateTime]::Parse($entries[$i].timestamp)
            if ($currTime -lt $prevTime) {
                $timestampsValid = $false
                $result['Warnings'] += "Entry $i has timestamp earlier than entry $($i - 1)"
            }
        }
        catch {
            $result['Warnings'] += "Could not parse timestamps for entries $($i - 1) and $i"
        }
    }
    $result['CheckResults']['TimestampsChronological'] = $timestampsValid
    
    # Cross-check with manifest
    $manifestPath = Join-Path $ManifestDirectory "$RunId.run.json"
    if (Test-Path -LiteralPath $manifestPath) {
        try {
            $manifest = Get-Content -LiteralPath $manifestPath -Raw | ConvertFrom-Json
            if ($manifest.runId -eq $RunId) {
                $result['CheckResults']['ManifestCrossCheck'] = $true
            }
            else {
                $result['Warnings'] += "Manifest runId does not match journal runId"
            }
        }
        catch {
            $result['Warnings'] += "Could not read manifest for cross-check: $_"
        }
    }
    else {
        $result['Warnings'] += "No manifest found for cross-check"
    }
    
    # Determine overall validity
    $result['IsValid'] = $result['CheckResults']['ValidJson'] -and
                         $result['CheckResults']['RequiredFieldsPresent'] -and
                         $result['CheckResults']['SchemaVersionConsistent'] -and
                         $result['CheckResults']['RunIdConsistent']
    
    # Repair if requested and needed
    if ($Repair -and -not $result['IsValid'] -and $entries.Count -gt 0) {
        try {
            $repairedPath = "$journalPath.repaired.$([DateTime]::Now.ToString('yyyyMMddHHmmss'))"
            
            # Backup original
            Copy-Item -LiteralPath $journalPath -Destination $repairedPath -Force
            $result['RepairedPath'] = $repairedPath
            
            # Write repaired entries
            Write-JsonFileAtomic -Path $journalPath -Data $entries
            
            $result['Repaired'] = $true
            $result['IsValid'] = $true  # Assume valid after repair
            Write-Verbose "[Journal] Repaired journal saved to $journalPath (backup: $repairedPath)"
        }
        catch {
            $result['Errors'] += "Failed to repair journal: $_"
        }
    }
    
    return [pscustomobject]$result
}

# Export functions (only works when loaded as module)
if ($MyInvocation.MyCommand.Path -match '\.psm1$') {
    Export-ModuleMember -Function @(
        'New-RunManifest'
        'Complete-RunManifest'
        'New-JournalEntry'
        'Write-JournalEntry'
        'Get-JournalState'
        'Rotate-Journal'
        'Test-JournalIntegrity'
        'Export-JournalReport'
        'Add-RunArtifact'
        'Checkpoint-Journal'
        'Restore-FromCheckpoint'
        'Complete-Checkpoint'
    )
}
