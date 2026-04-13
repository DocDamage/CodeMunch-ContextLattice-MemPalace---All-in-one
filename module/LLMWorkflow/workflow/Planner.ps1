#requires -Version 5.1
<#
.SYNOPSIS
    Planner/Executor Preview System for LLM Workflow platform.

.DESCRIPTION
    Provides plan-based execution with dry-run support, resume capability,
    policy gate integration, and rollback on failure.
    
    Implements the dry-run invariant from Part 1 Section 3.8:
    "Dry-run invariant: All mutation paths must support --dry-run that prints
    the plan but does not execute."

.NOTES
    File: Planner.ps1
    Version: 0.4.0
    Author: LLM Workflow Team

.EXAMPLE
    # Create and execute a plan
    $plan = New-ExecutionPlan -Operation "pack-build" -Targets @("rpgmaker-mz")
    Add-PlanStep -Plan $plan -Description "Validate pack manifest" -SafetyLevel "ReadOnly"
    Show-ExecutionPlan -Plan $plan
    Invoke-ExecutionPlan -Plan $plan

.EXAMPLE
    # Dry-run mode (preview only)
    Invoke-ExecutionPlan -Plan $plan -DryRun

.EXAMPLE
    # Resume interrupted plan
    $plan = Import-PlanManifest -Path "plans/plan-20260412T...json"
    Invoke-ExecutionPlan -Plan $plan -Resume
#>

Set-StrictMode -Version Latest

#===============================================================================
# Configuration and Constants
#===============================================================================

$script:CurrentSchemaVersion = 1
$script:DefaultPlansDirectory = ".llm-workflow/plans"
$script:ExecutionMode = $null

# Safety levels aligned with Policy.ps1
enum PlanSafetyLevel {
    ReadOnly
    Mutating
    Destructive
    Networked
}

# Plan execution states
enum PlanState {
    Created
    Preview
    Running
    Paused
    Completed
    Failed
    RolledBack
}

# Exit codes per IMPROVEMENT_PROPOSALS.md section 4.4
$script:ExitCodes = @{
    Success = 0
    GeneralFailure = 1
    InvalidArguments = 2
    DependencyMissing = 3
    RemoteUnavailable = 4
    AuthFailure = 5
    PartialSuccess = 6
    LockUnavailable = 7
    MigrationRequired = 8
    PolicyBlocked = 9
    BudgetBlocked = 10
    PermissionDeniedByMode = 11
    UserCancelled = 12
    PlanValidationFailed = 13
    RollbackFailed = 14
}

#===============================================================================
# Core Plan Functions
#===============================================================================

function New-ExecutionPlan {
    <#
    .SYNOPSIS
        Creates a new execution plan for operations.

    .DESCRIPTION
        Initializes a plan object with all required metadata including
        plan ID generation, operation type, targets, and risk assessment.
        The plan starts in 'Created' state and must be executed with
        Invoke-ExecutionPlan.

    .PARAMETER Operation
        The operation type (e.g., "sync", "build", "extract", "pack-build", "restore").

    .PARAMETER Targets
        Array of target packs or sources to operate on.

    .PARAMETER RunId
        Optional run ID. If not provided, uses current run ID or generates new one.

    .PARAMETER ProjectRoot
        The project root directory. Defaults to current directory.

    .PARAMETER EstimatedDuration
        Estimated total duration as a TimeSpan or string (e.g., "00:05:00").

    .PARAMETER Description
        Optional description of the plan's purpose.

    .PARAMETER Metadata
        Additional metadata as a hashtable.

    .OUTPUTS
        System.Collections.Hashtable. The plan object with all metadata.

    .EXAMPLE
        $plan = New-ExecutionPlan -Operation "pack-build" -Targets @("rpgmaker-mz")
        
        Creates a new plan for building the rpgmaker-mz pack.

    .EXAMPLE
        $plan = New-ExecutionPlan `
            -Operation "sync" `
            -Targets @("source1", "source2") `
            -EstimatedDuration "00:10:00" `
            -Description "Sync sources with remote"
    #>
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Operation,

        [Parameter()]
        [string[]]$Targets = @(),

        [Parameter()]
        [string]$RunId = "",

        [Parameter()]
        [string]$ProjectRoot = ".",

        [Parameter()]
        [object]$EstimatedDuration = $null,

        [Parameter()]
        [string]$Description = "",

        [Parameter()]
        [hashtable]$Metadata = @{}
    )

    # Get or generate run ID
    if ([string]::IsNullOrWhiteSpace($RunId)) {
        try {
            # Try to get from RunId.ps1 module
            $runIdCmd = Get-Command Get-CurrentRunId -ErrorAction SilentlyContinue
            if ($runIdCmd) {
                $RunId = & $runIdCmd
            }
            else {
                $RunId = New-PlanRunId
            }
        }
        catch {
            $RunId = New-PlanRunId
        }
    }

    # Generate plan ID
    $timestamp = [DateTime]::UtcNow.ToString("yyyyMMddTHHmmssZ")
    $planId = "plan-$timestamp-$([Guid]::NewGuid().ToString('N').Substring(0, 8))"

    # Convert estimated duration
    $estimatedDurationStr = $null
    if ($EstimatedDuration) {
        if ($EstimatedDuration -is [TimeSpan]) {
            $estimatedDurationStr = $EstimatedDuration.ToString()
        }
        else {
            $estimatedDurationStr = [string]$EstimatedDuration
        }
    }

    # Assess initial risk level based on operation
    $riskLevel = Get-InitialRiskLevel -Operation $Operation

    # Create plan object
    $plan = [ordered]@{
        schemaVersion = $script:CurrentSchemaVersion
        planId = $planId
        runId = $RunId
        operation = $Operation
        description = $Description
        targets = $Targets
        estimatedDuration = $estimatedDurationStr
        riskLevel = $riskLevel.ToString()
        state = [PlanState]::Created.ToString()
        createdUtc = [DateTime]::UtcNow.ToString("yyyy-MM-ddTHH:mm:ssZ")
        startedUtc = $null
        completedUtc = $null
        projectRoot = if ($ProjectRoot -and (Test-Path -Path $ProjectRoot -ErrorAction SilentlyContinue)) { 
            (Resolve-Path -Path $ProjectRoot).Path 
        } else { 
            $ProjectRoot 
        }
        steps = [System.Collections.Generic.List[hashtable]]::new()
        currentStep = 0
        createdByRunId = $RunId
        metadata = $Metadata
        executionResults = @{
            success = $false
            exitCode = $null
            errors = @()
            warnings = @()
        }
        rollbackLog = [System.Collections.Generic.List[hashtable]]::new()
    }

    Write-Verbose "[Planner] Created plan '$planId' for operation '$Operation' with $($Targets.Count) target(s)"
    return $plan
}

function Add-PlanStep {
    <#
    .SYNOPSIS
        Adds a step to an execution plan.

    .DESCRIPTION
        Adds a detailed step to the plan with information about the action,
        safety level, estimated duration, rollback action, and validation.
        Steps are executed in order and can be rolled back individually.

    .PARAMETER Plan
        The plan object to add the step to.

    .PARAMETER Description
        Human-readable description of what the step does.

    .PARAMETER SafetyLevel
        The safety level: ReadOnly, Mutating, Destructive, or Networked.

    .PARAMETER EstimatedSeconds
        Estimated duration in seconds.

    .PARAMETER RollbackAction
        ScriptBlock or command to execute for rollback.

    .PARAMETER ValidationCommand
        ScriptBlock or command to validate step success.

    .PARAMETER Action
        ScriptBlock to execute for this step (stored for reference).

    .PARAMETER Parameters
        Parameters to pass to the action/rollback.

    .PARAMETER RequiresLock
        Array of lock names required before executing this step.

    .PARAMETER ConfirmRequired
        Whether this step requires user confirmation.

    .OUTPUTS
        System.Collections.Hashtable. The added step object.

    .EXAMPLE
        Add-PlanStep -Plan $plan `
            -Description "Lock pack for modification" `
            -SafetyLevel "Mutating" `
            -EstimatedSeconds 5 `
            -RollbackAction { Unlock-File -Name "pack" } `
            -RequiresLock @("pack")
    #>
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [Parameter(Mandatory = $true)]
        [hashtable]$Plan,

        [Parameter(Mandatory = $true)]
        [string]$Description,

        [Parameter()]
        [PlanSafetyLevel]$SafetyLevel = [PlanSafetyLevel]::ReadOnly,

        [Parameter()]
        [int]$EstimatedSeconds = 0,

        [Parameter()]
        [object]$RollbackAction = $null,

        [Parameter()]
        [object]$ValidationCommand = $null,

        [Parameter()]
        [scriptblock]$Action = $null,

        [Parameter()]
        [hashtable]$Parameters = @{},

        [Parameter()]
        [string[]]$RequiresLock = @(),

        [Parameter()]
        [switch]$ConfirmRequired
    )

    $stepNumber = $Plan.steps.Count + 1

    # Update overall plan risk if this step is more risky
    $currentRisk = [PlanSafetyLevel]::Parse([PlanSafetyLevel], $Plan.riskLevel)
    if ($SafetyLevel -gt $currentRisk) {
        $Plan.riskLevel = $SafetyLevel.ToString()
    }

    # Convert rollback action to string if it's a scriptblock
    $rollbackStr = $null
    if ($RollbackAction -is [scriptblock]) {
        $rollbackStr = $RollbackAction.ToString()
    }
    elseif ($RollbackAction -ne $null) {
        $rollbackStr = [string]$RollbackAction
    }

    # Convert validation command to string if needed
    $validationStr = $null
    if ($ValidationCommand -is [scriptblock]) {
        $validationStr = $ValidationCommand.ToString()
    }
    elseif ($ValidationCommand -ne $null) {
        $validationStr = [string]$ValidationCommand
    }

    # Convert action to string if needed
    $actionStr = $null
    if ($Action -is [scriptblock]) {
        $actionStr = $Action.ToString()
    }
    elseif ($Action -ne $null) {
        $actionStr = [string]$Action
    }

    $step = [ordered]@{
        stepNumber = $stepNumber
        description = $Description
        safetyLevel = $SafetyLevel.ToString()
        estimatedSeconds = $EstimatedSeconds
        rollbackAction = $rollbackStr
        validationCommand = $validationStr
        action = $actionStr
        parameters = $Parameters
        requiresLock = $RequiresLock
        confirmRequired = $ConfirmRequired.IsPresent
        status = "pending"
        startedUtc = $null
        completedUtc = $null
        durationMs = $null
        error = $null
        output = $null
    }

    $Plan.steps.Add($step)

    # Update estimated duration
    $currentTotal = 0
    if ($Plan.estimatedDuration -and [TimeSpan]::TryParse($Plan.estimatedDuration, [ref]$null)) {
        $currentTotal = ([TimeSpan]$Plan.estimatedDuration).TotalSeconds
    }
    $currentTotal += $EstimatedSeconds
    $Plan.estimatedDuration = [TimeSpan]::FromSeconds($currentTotal).ToString()

    Write-Verbose "[Planner] Added step $stepNumber to plan '$($Plan.planId)': $Description"
    return $step
}

function Show-ExecutionPlan {
    <#
    .SYNOPSIS
        Displays an execution plan in human-readable format.

    .DESCRIPTION
        Shows a formatted summary of the plan including statistics,
        step-by-step breakdown, risk warnings, and estimated total time.
        Useful for previewing what will happen before execution.

    .PARAMETER Plan
        The plan object to display.

    .PARAMETER Format
        Output format: "Text" (default) or "Json".

    .PARAMETER IncludeSteps
        Whether to include detailed step information. Default is true.

    .OUTPUTS
        System.String or PSCustomObject depending on format.

    .EXAMPLE
        Show-ExecutionPlan -Plan $plan
        
        Displays the plan in formatted text.

    .EXAMPLE
        Show-ExecutionPlan -Plan $plan -Format Json | ConvertFrom-Json
        
        Returns the plan as JSON.
    #>
    [CmdletBinding()]
    [OutputType([object])]
    param(
        [Parameter(Mandatory = $true)]
        [hashtable]$Plan,

        [Parameter()]
        [ValidateSet("Text", "Json", "Object")]
        [string]$Format = "Text",

        [Parameter()]
        [switch]$IncludeSteps = $true
    )

    switch ($Format) {
        "Json" {
            return $Plan | ConvertTo-Json -Depth 10
        }
        "Object" {
            return [pscustomobject]$Plan
        }
        default {
            return Format-PlanText -Plan $Plan -IncludeSteps:$IncludeSteps
        }
    }
}

function Invoke-ExecutionPlan {
    <#
    .SYNOPSIS
        Executes an execution plan with full safety and tracking.

    .DESCRIPTION
        Executes the plan step-by-step with:
        - Policy gate checks before execution
        - Journal entries for each step (before/after checkpoints)
        - Lock acquisition for mutating steps
        - Automatic rollback on failure
        - Resume support for interrupted plans
        
        Implements the dry-run invariant: with -DryRun, prints the plan
        but does not execute any mutating steps.

    .PARAMETER Plan
        The plan object to execute.

    .PARAMETER DryRun
        If specified, only shows what would be done without executing.

    .PARAMETER Resume
        If specified, attempts to resume from last completed step.

    .PARAMETER ExecutionMode
        The execution mode for policy checks (interactive, ci, watch, etc.).

    .PARAMETER Policy
        Optional policy object. If not provided, loads from file.

    .PARAMETER AutoConfirm
        If specified, bypasses confirmation prompts (use with caution).

    .PARAMETER StopOnWarning
        If specified, treats warnings as errors.

    .OUTPUTS
        System.Collections.Hashtable. The execution result with success status,
        exit code, and step results.

    .EXAMPLE
        $result = Invoke-ExecutionPlan -Plan $plan
        if (-not $result.success) { exit $result.exitCode }

    .EXAMPLE
        Invoke-ExecutionPlan -Plan $plan -DryRun
        
        Preview mode - shows what would happen without executing.

    .EXAMPLE
        Invoke-ExecutionPlan -Plan $plan -Resume
        
        Resume a previously interrupted plan.
    #>
    [CmdletBinding(SupportsShouldProcess = $true)]
    [OutputType([hashtable])]
    param(
        [Parameter(Mandatory = $true)]
        [hashtable]$Plan,

        [Parameter()]
        [switch]$DryRun,

        [Parameter()]
        [switch]$Resume,

        [Parameter()]
        [string]$ExecutionMode = "",

        [Parameter()]
        [object]$Policy = $null,

        [Parameter()]
        [switch]$AutoConfirm,

        [Parameter()]
        [switch]$StopOnWarning
    )

    # Validate plan
    if (-not (Test-PlanValid -Plan $Plan)) {
        return @{
            success = $false
            exitCode = $script:ExitCodes.PlanValidationFailed
            error = "Plan validation failed"
            stepResults = @()
        }
    }

    # Dry-run mode: just show and return
    if ($DryRun) {
        Write-Host "`n========================================" -ForegroundColor Cyan
        Write-Host "DRY-RUN MODE (Preview Only)" -ForegroundColor Cyan
        Write-Host "========================================" -ForegroundColor Cyan
        Write-Host (Show-ExecutionPlan -Plan $plan)
        Write-Host "`n[Dry-Run] No changes were made." -ForegroundColor Green
        return @{
            success = $true
            exitCode = $script:ExitCodes.Success
            dryRun = $true
            message = "Plan preview completed without execution"
        }
    }

    # Check policy permission before execution (Invariant 3.6)
    $mode = if ($ExecutionMode) { $ExecutionMode } else { Get-PlanExecutionMode }
    
    try {
        $policyCmd = Get-Command Assert-PolicyPermission -ErrorAction SilentlyContinue
        if ($policyCmd) {
            $safetyLevels = $Plan.steps | ForEach-Object { 
                [PlanSafetyLevel]::Parse([PlanSafetyLevel], $_.safetyLevel) 
            } | Select-Object -Unique
            
            & $policyCmd -Command $Plan.operation -Mode $mode -SafetyLevels $safetyLevels
        }
    }
    catch {
        Write-Error "Policy blocked execution: $_"
        return @{
            success = $false
            exitCode = $script:ExitCodes.PolicyBlocked
            error = $_.Exception.Message
        }
    }

    # Initialize execution
    $Plan.state = [PlanState]::Running.ToString()
    $Plan.startedUtc = [DateTime]::UtcNow.ToString("yyyy-MM-ddTHH:mm:ssZ")
    
    # Determine starting step for resume
    $startStep = 0
    if ($Resume) {
        $startStep = Get-ResumeStep -Plan $Plan
        if ($startStep -gt 0) {
            Write-Host "Resuming plan from step $($startStep + 1)" -ForegroundColor Yellow
        }
    }

    $acquiredLocks = @{}
    $stepResults = [System.Collections.Generic.List[hashtable]]::new()
    $overallSuccess = $true

    try {
        for ($i = $startStep; $i -lt $Plan.steps.Count; $i++) {
            $step = $Plan.steps[$i]
            $Plan.currentStep = $i + 1

            # Check for user cancellation
            if ([Console]::KeyAvailable) {
                $key = [Console]::ReadKey($true)
                if ($key.Key -eq [ConsoleKey]::Q -and $key.Modifiers -eq [ConsoleModifiers]::Control) {
                    throw "Execution cancelled by user (Ctrl+Q)"
                }
            }

            # Execute the step
            $result = Invoke-PlanStep `
                -Plan $Plan `
                -Step $step `
                -AcquiredLocks $acquiredLocks `
                -AutoConfirm:$AutoConfirm `
                -ExecutionMode $mode

            $stepResults.Add($result)

            if (-not $result.success) {
                $overallSuccess = $false
                
                if ($result.canContinue) {
                    Write-Warning "Step $($step.stepNumber) failed but marked as continuable"
                }
                else {
                    # Initiate rollback
                    Write-Host "`nStep failed. Initiating rollback..." -ForegroundColor Red
                    $rollbackResult = Invoke-PlanRollback `
                        -Plan $Plan `
                        -FailedStep $i `
                        -AcquiredLocks $acquiredLocks
                    
                    $Plan.executionResults.errors += $result.error
                    $Plan.state = [PlanState]::RolledBack.ToString()
                    $Plan.executionResults.exitCode = $script:ExitCodes.GeneralFailure
                    
                    return @{
                        success = $false
                        exitCode = $script:ExitCodes.GeneralFailure
                        error = $result.error
                        failedStep = $step.stepNumber
                        stepResults = $stepResults.ToArray()
                        rollbackResult = $rollbackResult
                    }
                }
            }

            # Check for warnings
            if ($result.warnings -and $result.warnings.Count -gt 0) {
                $Plan.executionResults.warnings += $result.warnings
                if ($StopOnWarning) {
                    throw "Warning treated as error (StopOnWarning enabled)"
                }
            }
        }

        # Mark plan as completed
        $Plan.state = [PlanState]::Completed.ToString()
        $Plan.completedUtc = [DateTime]::UtcNow.ToString("yyyy-MM-ddTHH:mm:ssZ")
        $Plan.executionResults.success = $overallSuccess
        $Plan.executionResults.exitCode = if ($overallSuccess) { $script:ExitCodes.Success } else { $script:ExitCodes.PartialSuccess }

        # Release all locks
        foreach ($lockName in $acquiredLocks.Keys) {
            try {
                $unlockCmd = Get-Command Unlock-File -ErrorAction SilentlyContinue
                if ($unlockCmd) {
                    & $unlockCmd -Name $lockName -ProjectRoot $Plan.projectRoot
                }
            }
            catch {
                Write-Warning "Failed to release lock '$lockName': $_"
            }
        }

        Write-Host "`nPlan execution completed successfully!" -ForegroundColor Green
        
        return @{
            success = $overallSuccess
            exitCode = $Plan.executionResults.exitCode
            stepResults = $stepResults.ToArray()
            plan = $Plan
        }
    }
    catch {
        $errorMsg = $_.Exception.Message
        Write-Error "Plan execution failed: $errorMsg"
        
        $Plan.executionResults.errors += $errorMsg
        $Plan.state = [PlanState]::Failed.ToString()
        $Plan.executionResults.exitCode = $script:ExitCodes.GeneralFailure

        # Attempt rollback
        try {
            Invoke-PlanRollback -Plan $Plan -FailedStep ($Plan.currentStep - 1) -AcquiredLocks $acquiredLocks
        }
        catch {
            Write-Error "Rollback also failed: $_"
        }

        return @{
            success = $false
            exitCode = $script:ExitCodes.GeneralFailure
            error = $errorMsg
            stepResults = $stepResults.ToArray()
        }
    }
}

function Export-PlanManifest {
    <#
    .SYNOPSIS
        Saves a plan to disk for replay or resume.

    .DESCRIPTION
        Exports the plan to a JSON file with schema versioning.
        The plan can be re-imported with Import-PlanManifest for
        replay, resume, or analysis.

    .PARAMETER Plan
        The plan object to export.

    .PARAMETER Path
        The file path to save to. If not provided, uses default
        plans directory with plan ID as filename.

    .PARAMETER ProjectRoot
        The project root directory. Defaults to plan's project root.

    .PARAMETER IncludeResults
        Whether to include execution results in the export.

    .OUTPUTS
        System.String. The path to the exported file.

    .EXAMPLE
        Export-PlanManifest -Plan $plan -Path "plans/backup.json"
        
        Exports the plan to a specific file.

    .EXAMPLE
        Export-PlanManifest -Plan $plan
        
        Exports to default location (.llm-workflow/plans/{planId}.json).
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory = $true)]
        [hashtable]$Plan,

        [Parameter()]
        [string]$Path = "",

        [Parameter()]
        [string]$ProjectRoot = "",

        [Parameter()]
        [switch]$IncludeResults
    )

    # Determine project root
    $root = if ($ProjectRoot) { $ProjectRoot } else { $Plan.projectRoot }
    if (-not $root) { $root = "." }

    # Determine export path
    if ([string]::IsNullOrWhiteSpace($Path)) {
        $plansDir = Join-Path $root $script:DefaultPlansDirectory
        $Path = Join-Path $plansDir "$($Plan.planId).json"
    }

    # Ensure directory exists
    $dir = Split-Path -Parent $Path
    if (-not (Test-Path -LiteralPath $dir)) {
        New-Item -ItemType Directory -Path $dir -Force | Out-Null
    }

    # Prepare export object
    $export = [ordered]@{
        schemaVersion = $script:CurrentSchemaVersion
        exportedUtc = [DateTime]::UtcNow.ToString("yyyy-MM-ddTHH:mm:ssZ")
        plan = $Plan
    }

    if (-not $IncludeResults) {
        # Remove execution results for clean export
        $export.plan = Copy-PlanForExport -Plan $Plan
    }

    # Use atomic write if available
    $json = $export | ConvertTo-Json -Depth 10
    
    try {
        $atomicCmd = Get-Command Write-AtomicFile -ErrorAction SilentlyContinue
        if ($atomicCmd) {
            & $atomicCmd -Path $Path -Content $json -Format Text | Out-Null
        }
        else {
            # Fallback to standard write
            $json | Out-File -FilePath $Path -Encoding UTF8 -Force
        }
    }
    catch {
        throw "Failed to export plan manifest: $_"
    }

    Write-Verbose "[Planner] Exported plan to: $Path"
    return $Path
}

function Import-PlanManifest {
    <#
    .SYNOPSIS
        Loads a plan from disk for replay or resume.

    .DESCRIPTION
        Imports a plan manifest from a JSON file. Validates schema version
        and returns the plan object ready for execution with -Resume.

    .PARAMETER Path
        The file path to load from.

    .PARAMETER ValidateSchema
        Whether to validate the schema version. Default is true.

    .PARAMETER ForResume
        If specified, validates that the plan can be resumed.

    .OUTPUTS
        System.Collections.Hashtable. The loaded plan object.

    .EXAMPLE
        $plan = Import-PlanManifest -Path "plans/plan-20260412T....json"
        Invoke-ExecutionPlan -Plan $plan -Resume
    #>
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path,

        [Parameter()]
        [switch]$ValidateSchema = $true,

        [Parameter()]
        [switch]$ForResume
    )

    if (-not (Test-Path -LiteralPath $Path)) {
        throw "Plan manifest not found: $Path"
    }

    try {
        $content = Get-Content -LiteralPath $Path -Raw -ErrorAction Stop
        $manifest = $content | ConvertFrom-Json -AsHashtable
    }
    catch {
        throw "Failed to parse plan manifest: $_"
    }

    # Validate schema version
    if ($ValidateSchema) {
        $schemaVersion = $manifest.schemaVersion
        if (-not $schemaVersion) {
            Write-Warning "Manifest missing schemaVersion, assuming version 1"
            $schemaVersion = 1
        }
        
        if ($schemaVersion -gt $script:CurrentSchemaVersion) {
            throw "Manifest schema version $schemaVersion is newer than supported version $($script:CurrentSchemaVersion)"
        }
    }

    # Extract plan
    $plan = $manifest.plan
    if (-not $plan) {
        throw "Manifest does not contain a plan object"
    }

    # Convert steps to list if needed
    if ($plan.steps -is [array]) {
        $plan.steps = [System.Collections.Generic.List[hashtable]]$plan.steps
    }
    if (-not $plan.steps) {
        $plan.steps = [System.Collections.Generic.List[hashtable]]::new()
    }

    # Validate for resume
    if ($ForResume) {
        $state = $plan.state
        if ($state -eq [PlanState]::Completed.ToString() -or $state -eq [PlanState]::RolledBack.ToString()) {
            Write-Warning "Plan is in '$state' state and may not be resumable"
        }
        
        if ($plan.currentStep -ge $plan.steps.Count) {
            throw "Plan already completed all steps"
        }
    }

    Write-Verbose "[Planner] Imported plan '$($plan.planId)' from: $Path"
    return $plan
}

#===============================================================================
# Helper Functions
#===============================================================================

function New-PlanRunId {
    <#
    .SYNOPSIS
        Generates a new run ID for planning.
    #>
    $timestamp = [DateTime]::UtcNow.ToString("yyyyMMddTHHmmssZ")
    $random = -join ((1..4) | ForEach-Object { '{0:x}' -f (Get-Random -Maximum 16) })
    return "$timestamp-$random"
}

function Get-InitialRiskLevel {
    <#
    .SYNOPSIS
        Determines initial risk level based on operation type.
    #>
    param([string]$Operation)

    switch -Regex ($Operation.ToLower()) {
        "^(delete|remove|prune|clean|destroy)$" { return [PlanSafetyLevel]::Destructive }
        "^(sync|build|write|update|modify)$" { return [PlanSafetyLevel]::Mutating }
        "^(restore|migrate|switch-provider)$" { return [PlanSafetyLevel]::Destructive }
        default { return [PlanSafetyLevel]::ReadOnly }
    }
}

function Get-PlanExecutionMode {
    <#
    .SYNOPSIS
        Detects the current execution mode.
    #>
    # Check for CI environment variables
    $ciVars = @('CI', 'GITHUB_ACTIONS', 'GITLAB_CI', 'JENKINS_HOME', 'TF_BUILD', 'BUILD_BUILDID')
    foreach ($var in $ciVars) {
        if (-not [string]::IsNullOrWhiteSpace([Environment]::GetEnvironmentVariable($var))) {
            return 'ci'
        }
    }
    return 'interactive'
}

function Test-PlanValid {
    <#
    .SYNOPSIS
        Validates a plan object structure.
    #>
    param([hashtable]$Plan)

    if (-not $Plan) {
        Write-Error "Plan is null"
        return $false
    }

    $required = @('planId', 'operation', 'steps')
    foreach ($field in $required) {
        if (-not $Plan.ContainsKey($field)) {
            Write-Error "Plan missing required field: $field"
            return $false
        }
    }

    if ($Plan.steps.Count -eq 0) {
        Write-Warning "Plan has no steps"
    }

    return $true
}

function Format-PlanText {
    <#
    .SYNOPSIS
        Formats a plan as human-readable text.
    #>
    param(
        [hashtable]$Plan,
        [switch]$IncludeSteps
    )

    $lines = @()
    $lines += ""
    $lines += "=" * 60
    $lines += "EXECUTION PLAN: $($Plan.operation)"
    $lines += "=" * 60
    $lines += "Plan ID:    $($Plan.planId)"
    $lines += "Run ID:     $($Plan.runId)"
    if ($Plan.description) {
        $lines += "Description: $($Plan.description)"
    }
    $lines += "Targets:    $($Plan.targets -join ', ')"
    $lines += "Risk Level: $($Plan.riskLevel)"
    $lines += "State:      $($Plan.state)"
    $lines += "Duration:   $($Plan.estimatedDuration)"
    $lines += "Steps:      $($Plan.steps.Count)"
    $lines += ""

    # Risk warning
    if ($Plan.riskLevel -eq [PlanSafetyLevel]::Destructive.ToString()) {
        $lines += "! WARNING: This plan contains DESTRUCTIVE operations !" 
        $lines += ""
    }
    elseif ($Plan.riskLevel -eq [PlanSafetyLevel]::Mutating.ToString()) {
        $lines += "* Note: This plan will make changes to files/systems *"
        $lines += ""
    }

    if ($IncludeSteps -and $Plan.steps.Count -gt 0) {
        $lines += "STEP-BY-STEP BREAKDOWN:"
        $lines += "-" * 60
        
        foreach ($step in $Plan.steps) {
            $riskSymbol = switch ($step.safetyLevel) {
                'Destructive' { '[!]' }
                'Mutating' { '[*]' }
                'Networked' { '[~]' }
                default { '[ ]' }
            }
            
            $duration = if ($step.estimatedSeconds -gt 0) { " (~$($step.estimatedSeconds)s)" } else { "" }
            $status = if ($step.status -ne 'pending') { " [$($step.status)]" } else { "" }
            
            $lines += "  $($step.stepNumber). $riskSymbol $($step.description)$duration$status"
            
            if ($step.requiresLock -and $step.requiresLock.Count -gt 0) {
                $lines += "     Lock: $($step.requiresLock -join ', ')"
            }
            if ($step.confirmRequired) {
                $lines += "     !! Requires confirmation !!"
            }
        }
        $lines += ""
    }

    $lines += "=" * 60
    
    return $lines -join "`n"
}

function Get-ResumeStep {
    <#
    .SYNOPSIS
        Determines which step to resume from.
    #>
    param([hashtable]$Plan)

    # Find the last completed step
    $lastCompleted = -1
    for ($i = 0; $i -lt $Plan.steps.Count; $i++) {
        if ($Plan.steps[$i].status -eq 'completed') {
            $lastCompleted = $i
        }
        elseif ($Plan.steps[$i].status -eq 'failed') {
            return $i  # Resume from failed step
        }
    }

    return $lastCompleted + 1
}

function Invoke-PlanStep {
    <#
    .SYNOPSIS
        Executes a single plan step with full safety.
    #>
    [CmdletBinding()]
    param(
        [hashtable]$Plan,
        [hashtable]$Step,
        [hashtable]$AcquiredLocks,
        [switch]$AutoConfirm,
        [string]$ExecutionMode
    )

    $stepNum = $Step.stepNumber
    $description = $Step.description
    
    Write-Host "`n[$stepNum/$($Plan.steps.Count)] $description" -ForegroundColor Cyan

    # Check if we should process this step
    if ($Step.status -eq 'completed') {
        Write-Verbose "Step $stepNum already completed, skipping"
        return @{ success = $true; skipped = $true }
    }

    # Handle confirmation requirement
    if ($Step.confirmRequired -and -not $AutoConfirm) {
        $confirm = Read-Host "Confirm step $stepNum? [y/N]"
        if ($confirm -notmatch '^[Yy]') {
            return @{ 
                success = $false 
                error = "Step $stepNum cancelled by user"
                userCancelled = $true
            }
        }
    }

    # Acquire required locks
    foreach ($lockName in $Step.requiresLock) {
        if (-not $AcquiredLocks.ContainsKey($lockName)) {
            try {
                $lockCmd = Get-Command Lock-File -ErrorAction SilentlyContinue
                if ($lockCmd) {
                    $lock = & $lockCmd -Name $lockName -ProjectRoot $Plan.projectRoot -TimeoutSeconds 30
                    if ($lock) {
                        $AcquiredLocks[$lockName] = $lock
                        Write-Verbose "Acquired lock: $lockName"
                    }
                    else {
                        throw "Could not acquire lock: $lockName"
                    }
                }
            }
            catch {
                return @{
                    success = $false
                    error = "Failed to acquire lock '$lockName': $_"
                    canContinue = $false
                }
            }
        }
    }

    # Write journal entry (before)
    $journalEntry = $null
    try {
        $journalCmd = Get-Command New-JournalEntry -ErrorAction SilentlyContinue
        if ($journalCmd) {
            $journalEntry = & $journalCmd `
                -RunId $Plan.runId `
                -Step "$($Plan.operation)-step$stepNum" `
                -Status 'before' `
                -Metadata @{ description = $description; safetyLevel = $Step.safetyLevel }
        }
    }
    catch {
        Write-Warning "Failed to write journal entry: $_"
    }

    # Execute the step
    $Step.status = 'in-progress'
    $Step.startedUtc = [DateTime]::UtcNow.ToString("yyyy-MM-ddTHH:mm:ssZ")
    $startTime = [DateTime]::Now

    $result = @{
        stepNumber = $stepNum
        success = $false
        error = $null
        warnings = @()
        output = $null
        durationMs = 0
    }

    try {
        # Check WhatIf/ShouldProcess for this step
        $shouldExecute = $true
        if ($Step.safetyLevel -ne 'ReadOnly') {
            $shouldExecute = $PSCmdlet.ShouldProcess($description, "Execute")
        }

        if ($shouldExecute) {
            # Execute action if provided
            if ($Step.action) {
                $action = [scriptblock]::Create($Step.action)
                $output = & $action @($Step.parameters)
                $result.output = $output
            }

            # Run validation if provided
            if ($Step.validationCommand) {
                $validation = [scriptblock]::Create($Step.validationCommand)
                $validationResult = & $validation
                if (-not $validationResult) {
                    throw "Validation failed for step $stepNum"
                }
            }
        }

        $result.success = $true
        $Step.status = 'completed'
    }
    catch {
        $result.success = $false
        $result.error = $_.Exception.Message
        $Step.status = 'failed'
        $Step.error = $result.error
    }

    $endTime = [DateTime]::Now
    $result.durationMs = [int]($endTime - $startTime).TotalMilliseconds
    $Step.durationMs = $result.durationMs
    $Step.completedUtc = [DateTime]::UtcNow.ToString("yyyy-MM-ddTHH:mm:ssZ")

    # Write journal entry (after)
    try {
        if ($journalEntry) {
            $journalCmd = Get-Command New-JournalEntry -ErrorAction SilentlyContinue
            if ($journalCmd) {
                $status = if ($result.success) { 'after' } else { 'failed' }
                & $journalCmd `
                    -RunId $Plan.runId `
                    -Step "$($Plan.operation)-step$stepNum" `
                    -Status $status `
                    -Metadata @{ 
                        description = $description
                        success = $result.success
                        durationMs = $result.durationMs
                        error = $result.error
                    } | Out-Null
            }
        }
    }
    catch {
        Write-Warning "Failed to write journal entry: $_"
    }

    # Output result
    if ($result.success) {
        Write-Host "  [OK] Completed in $($result.durationMs)ms" -ForegroundColor Green
    }
    else {
        Write-Host "  [FAIL] $($result.error)" -ForegroundColor Red
    }

    return $result
}

function Invoke-PlanRollback {
    <#
    .SYNOPSIS
        Rolls back completed steps when a step fails.
    #>
    [CmdletBinding()]
    param(
        [hashtable]$Plan,
        [int]$FailedStep,
        [hashtable]$AcquiredLocks
    )

    Write-Host "`nRolling back $($FailedStep) completed step(s)..." -ForegroundColor Yellow

    $rollbackResults = [System.Collections.Generic.List[hashtable]]::new()
    $success = $true

    # Roll back in reverse order
    for ($i = $FailedStep - 1; $i -ge 0; $i--) {
        $step = $Plan.steps[$i]
        
        if ($step.rollbackAction -and $step.status -eq 'completed') {
            Write-Host "  Rolling back step $($step.stepNumber): $($step.description)" -ForegroundColor Yellow
            
            try {
                $rollback = [scriptblock]::Create($step.rollbackAction)
                & $rollback
                
                $rollbackResults.Add(@{
                    stepNumber = $step.stepNumber
                    success = $true
                })
                
                Write-Host "    [Rolled Back]" -ForegroundColor Green
            }
            catch {
                $rollbackResults.Add(@{
                    stepNumber = $step.stepNumber
                    success = $false
                    error = $_.Exception.Message
                })
                
                $success = $false
                Write-Host "    [Rollback Failed] $_" -ForegroundColor Red
            }
        }
    }

    # Release all locks
    foreach ($lockName in @($AcquiredLocks.Keys)) {
        try {
            $unlockCmd = Get-Command Unlock-File -ErrorAction SilentlyContinue
            if ($unlockCmd) {
                & $unlockCmd -Name $lockName -ProjectRoot $Plan.projectRoot
            }
            $AcquiredLocks.Remove($lockName)
        }
        catch {
            Write-Warning "Failed to release lock '$lockName' during rollback: $_"
        }
    }

    $Plan.rollbackLog.AddRange($rollbackResults)

    return @{
        success = $success
        results = $rollbackResults.ToArray()
    }
}

function Copy-PlanForExport {
    <#
    .SYNOPSIS
        Creates a clean copy of a plan without execution results.
    #>
    param([hashtable]$Plan)

    $copy = [ordered]@{}
    foreach ($key in $Plan.Keys) {
        if ($key -ne 'executionResults') {
            $copy[$key] = $Plan[$key]
        }
    }
    
    # Clear step results
    $copy.steps = $Plan.steps | ForEach-Object {
        $stepCopy = [ordered]@{}
        foreach ($stepKey in $_.Keys) {
            if (@('status', 'startedUtc', 'completedUtc', 'durationMs', 'error', 'output') -notcontains $stepKey) {
                $stepCopy[$stepKey] = $_[$stepKey]
            }
        }
        # Reset status
        $stepCopy['status'] = 'pending'
        $stepCopy
    }
    
    $copy['state'] = [PlanState]::Created.ToString()
    $copy['currentStep'] = 0
    
    return $copy
}

#===============================================================================
# Additional Utility Functions
#===============================================================================

function Get-PlanStepTemplate {
    <#
    .SYNOPSIS
        Returns predefined step templates for common operations.

    .DESCRIPTION
        Provides reusable step templates to simplify plan creation.
        Templates include standard steps like lock acquisition,
        validation, backup, etc.

    .PARAMETER TemplateName
        The name of the template to retrieve.

    .OUTPUTS
        System.Collections.Hashtable. The step template.

    .EXAMPLE
        $template = Get-PlanStepTemplate -TemplateName "LockPack"
        Add-PlanStep -Plan $plan @template -Parameters @{ PackId = "my-pack" }
    #>
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [Parameter(Mandatory = $true)]
        [ValidateSet("LockPack", "ValidateManifest", "BackupState", "AcquireLock", "ReleaseLock")]
        [string]$TemplateName
    )

    switch ($TemplateName) {
        "LockPack" {
            return @{
                Description = "Acquire lock for pack operation"
                SafetyLevel = [PlanSafetyLevel]::Mutating
                EstimatedSeconds = 5
                RequiresLock = @("pack")
                RollbackAction = { param($PackId); Unlock-File -Name "pack" }
            }
        }
        "ValidateManifest" {
            return @{
                Description = "Validate pack manifest"
                SafetyLevel = [PlanSafetyLevel]::ReadOnly
                EstimatedSeconds = 2
                ValidationCommand = { param($ManifestPath); Test-Path $ManifestPath }
            }
        }
        "BackupState" {
            return @{
                Description = "Create backup before modifications"
                SafetyLevel = [PlanSafetyLevel]::Mutating
                EstimatedSeconds = 10
                ConfirmRequired = $true
                RollbackAction = { param($BackupPath); Restore-Backup -Path $BackupPath }
            }
        }
        "AcquireLock" {
            return @{
                Description = "Acquire resource lock"
                SafetyLevel = [PlanSafetyLevel]::Mutating
                EstimatedSeconds = 5
                RollbackAction = { param($LockName); Unlock-File -Name $LockName }
            }
        }
        "ReleaseLock" {
            return @{
                Description = "Release resource lock"
                SafetyLevel = [PlanSafetyLevel]::Mutating
                EstimatedSeconds = 1
            }
        }
        default {
            throw "Unknown template: $TemplateName"
        }
    }
}

function Get-PlanSummary {
    <#
    .SYNOPSIS
        Returns a summary of a plan's current state.

    .DESCRIPTION
        Provides statistics about step completion, timing, and success rates.

    .PARAMETER Plan
        The plan object to summarize.

    .OUTPUTS
        System.Management.Automation.PSCustomObject. Summary statistics.
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory = $true)]
        [hashtable]$Plan
    )

    $completedSteps = ($Plan.steps | Where-Object { $_.status -eq 'completed' }).Count
    $failedSteps = ($Plan.steps | Where-Object { $_.status -eq 'failed' }).Count
    $pendingSteps = ($Plan.steps | Where-Object { $_.status -eq 'pending' }).Count
    
    $totalDuration = 0
    foreach ($step in $Plan.steps) {
        if ($step.durationMs) {
            $totalDuration += $step.durationMs
        }
    }

    return [pscustomobject]@{
        PlanId = $Plan.planId
        Operation = $Plan.operation
        State = $Plan.state
        TotalSteps = $Plan.steps.Count
        CompletedSteps = $completedSteps
        FailedSteps = $failedSteps
        PendingSteps = $pendingSteps
        ProgressPercent = if ($Plan.steps.Count -gt 0) { 
            [math]::Round(($completedSteps / $Plan.steps.Count) * 100, 1) 
        } else { 0 }
        TotalDurationMs = $totalDuration
        RiskLevel = $Plan.riskLevel
        CanResume = ($Plan.state -in @('Created', 'Running', 'Paused', 'Failed')) -and ($pendingSteps -gt 0)
    }
}

# Export module members handled by LLMWorkflow.psm1
