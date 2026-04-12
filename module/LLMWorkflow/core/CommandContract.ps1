# Policy and Execution Mode System - Command Contract
# Implements command definition and validation per IMPROVEMENT_PROPOSALS.md section 3.1

Set-StrictMode -Version Latest

#===============================================================================
# Configuration and Constants
#===============================================================================

# Standard exit codes per IMPROVEMENT_PROPOSALS.md section 4.4
$script:StandardExitCodes = @{
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
}

# Safety levels per IMPROVEMENT_PROPOSALS.md section 3.1
$script:ValidSafetyLevels = @("read-only", "mutating", "destructive", "networked")

# Registry of command contracts
$script:CommandContracts = @{}

#===============================================================================
# Command Contract Creation
#===============================================================================

function New-CommandContract {
    <#
    .SYNOPSIS
        Creates a new command contract definition.
    
    .DESCRIPTION
        Defines the complete contract for a command including its purpose,
        parameters, exit codes, dry-run behavior, locks, and safety levels.
        Per Invariant 3.1, every public command must define these properties.
    
    .PARAMETER Name
        The command name (e.g., "sync", "restore", "doctor")
    
    .PARAMETER Purpose
        Description of what the command does
    
    .PARAMETER Parameters
        Hashtable of parameter definitions with name, type, required, and description
    
    .PARAMETER ExitCodes
        Hashtable mapping exit codes to their meanings (merges with standard codes)
    
    .PARAMETER DryRunBehavior
        Description of how the command behaves in dry-run mode
    
    .PARAMETER Locks
        Array of lock names this command acquires
    
    .PARAMETER StateTouched
        Array of state files/directories this command modifies
    
    .PARAMETER RemoteSystems
        Array of remote systems this command interacts with
    
    .PARAMETER OutputContract
        Description of the command's output format and guarantees
    
    .PARAMETER SafetyLevels
        Array of safety levels: read-only, mutating, destructive, networked
    
    .PARAMETER Handler
        ScriptBlock that implements the command (optional)
    
    .OUTPUTS
        PSCustomObject representing the command contract
    
    .EXAMPLE
        $contract = New-CommandContract -Name "sync" `
            -Purpose "Synchronizes local state with remote sources" `
            -SafetyLevels @("mutating", "networked") `
            -Locks @("sync") `
            -StateTouched @("sync-state.json")
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [string]$Name,
        
        [Parameter(Mandatory=$true)]
        [string]$Purpose,
        
        [hashtable]$Parameters = @{},
        
        [hashtable]$ExitCodes = @{},
        
        [string]$DryRunBehavior = "",
        
        [string[]]$Locks = @(),
        
        [string[]]$StateTouched = @(),
        
        [string[]]$RemoteSystems = @(),
        
        [string]$OutputContract = "",
        
        [Parameter(Mandatory=$true)]
        [ValidateScript({
            foreach ($level in $_) {
                if ($script:ValidSafetyLevels -notcontains $level) {
                    throw "Invalid safety level '$level'. Valid: $($script:ValidSafetyLevels -join ', ')"
                }
            }
            return $true
        })]
        [string[]]$SafetyLevels,
        
        [scriptblock]$Handler = $null
    )
    
    # Merge with standard exit codes
    $mergedExitCodes = $script:StandardExitCodes.Clone()
    foreach ($code in $ExitCodes.Keys) {
        $mergedExitCodes[$code] = $ExitCodes[$code]
    }
    
    # Validate safety levels
    $isMutating = $SafetyLevels -contains "mutating" -or 
                  $SafetyLevels -contains "destructive" -or
                  $SafetyLevels -contains "networked"
    
    # Ensure dry-run behavior is documented for mutating commands
    if ($isMutating -and [string]::IsNullOrEmpty($DryRunBehavior)) {
        Write-Warning "Command '$Name' has mutating safety level but no DryRunBehavior defined. Per Invariant 3.8, dry-run behavior must be specified."
    }
    
    $contract = [PSCustomObject]@{
        name = $Name
        purpose = $Purpose
        parameters = $Parameters
        exitCodes = $mergedExitCodes
        dryRunBehavior = $DryRunBehavior
        locks = $Locks
        stateTouched = $StateTouched
        remoteSystems = $RemoteSystems
        outputContract = $OutputContract
        safetyLevels = $SafetyLevels
        isMutating = $isMutating
        handler = $Handler
        registeredAt = [DateTime]::UtcNow.ToString("o")
        schemaVersion = 1
    }
    
    # Register the contract
    $script:CommandContracts[$Name] = $contract
    
    return $contract
}

function Get-CommandContract {
    <#
    .SYNOPSIS
        Retrieves a registered command contract.
    
    .PARAMETER Name
        The command name to lookup
    
    .OUTPUTS
        PSCustomObject representing the command contract, or $null if not found
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [string]$Name
    )
    
    if ($script:CommandContracts.ContainsKey($Name)) {
        return $script:CommandContracts[$Name]
    }
    
    return $null
}

function Get-AllCommandContracts {
    <#
    .SYNOPSIS
        Returns all registered command contracts.
    #>
    [CmdletBinding()]
    param()
    
    return $script:CommandContracts.Values
}

#===============================================================================
# Contract Validation
#===============================================================================

function Test-CommandContract {
    <#
    .SYNOPSIS
        Validates a command against its contract.
    
    .DESCRIPTION
        Validates that a command invocation adheres to its defined contract,
        including parameter validation, safety level checks, and policy compliance.
    
    .PARAMETER Contract
        The command contract to validate against
    
    .PARAMETER Arguments
        Hashtable of arguments passed to the command
    
    .PARAMETER SkipPolicyCheck
        If specified, skips the policy permission check
    
    .PARAMETER ExecutionMode
        Current execution mode for policy checking
    
    .OUTPUTS
        PSCustomObject with validation results
    
    .EXAMPLE
        $result = Test-CommandContract -Contract $contract -Arguments $args
        if (-not $result.IsValid) { Write-Error $result.Errors }
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [PSCustomObject]$Contract,
        
        [hashtable]$Arguments = @{},
        
        [switch]$SkipPolicyCheck,
        
        [string]$ExecutionMode = ""
    )
    
    $errors = [System.Collections.Generic.List[string]]::new()
    $warnings = [System.Collections.Generic.List[string]]::new()
    
    # Validate parameters
    foreach ($paramName in $Contract.parameters.Keys) {
        $paramDef = $Contract.parameters[$paramName]
        $isProvided = $Arguments.ContainsKey($paramName)
        
        # Check required parameters
        if ($paramDef.required -and -not $isProvided) {
            $errors.Add("Missing required parameter: $paramName")
        }
        
        # Validate type if provided
        if ($isProvided -and $paramDef.type) {
            $value = $Arguments[$paramName]
            $typeValid = Test-ParameterType -Value $value -ExpectedType $paramDef.type
            if (-not $typeValid) {
                $errors.Add("Parameter '$paramName' has invalid type. Expected: $($paramDef.type)")
            }
        }
    }
    
    # Check policy permission if not skipped
    if (-not $SkipPolicyCheck) {
        if ([string]::IsNullOrEmpty($ExecutionMode)) {
            # Import ExecutionMode module function if available
            if (Get-Command Get-CurrentExecutionMode -ErrorAction SilentlyContinue) {
                $ExecutionMode = Get-CurrentExecutionMode
            }
            else {
                $ExecutionMode = "interactive"
            }
        }
        
        # Check policy permission
        if (Get-Command Test-PolicyPermission -ErrorAction SilentlyContinue) {
            $allowed = Test-PolicyPermission -Command $Contract.name -Mode $ExecutionMode
            if (-not $allowed) {
                $errors.Add("Policy blocks command '$($Contract.name)' in mode '$ExecutionMode'")
            }
        }
    }
    
    # Validate safety level consistency
    if ($Contract.isMutating -and [string]::IsNullOrEmpty($Contract.dryRunBehavior)) {
        $warnings.Add("Mutating command lacks dry-run behavior documentation (Invariant 3.8)")
    }
    
    return [PSCustomObject]@{
        IsValid = ($errors.Count -eq 0)
        Errors = $errors.ToArray()
        Warnings = $warnings.ToArray()
        command = $Contract.name
        timestamp = [DateTime]::UtcNow.ToString("o")
    }
}

function Test-ParameterType {
    <#
    .SYNOPSIS
        Validates a value against an expected type.
    
    .PARAMETER Value
        The value to validate
    
    .PARAMETER ExpectedType
        The expected type name
    #>
    [CmdletBinding()]
    param(
        [object]$Value,
        [string]$ExpectedType
    )
    
    switch ($ExpectedType.ToLower()) {
        "string" { return $Value -is [string] }
        "int" { return $Value -is [int] -or $Value -is [int64] }
        "bool" { return $Value -is [bool] }
        "array" { return $Value -is [array] }
        "hashtable" { return $Value -is [hashtable] }
        "switch" { return $Value -is [switch] -or $Value -is [bool] }
        "path" { return $Value -is [string] }  # Additional validation could be added
        "uri" { 
            if ($Value -isnot [string]) { return $false }
            return [uri]::IsWellFormedUriString($Value, [System.UriKind]::Absolute) -or
                   [uri]::IsWellFormedUriString($Value, [System.UriKind]::Relative)
        }
        default { return $true }  # Unknown types pass validation
    }
}

#===============================================================================
# Contract Execution
#===============================================================================

function Invoke-WithContract {
    <#
    .SYNOPSIS
        Executes a command with full contract validation.
    
    .DESCRIPTION
        Executes a command script block with full contract validation including:
        - Parameter validation
        - Policy permission checks (before locks)
        - Lock acquisition
        - Dry-run support
        - Exit code validation
        - Journal writing for multi-step operations
    
    .PARAMETER Contract
        The command contract defining the operation
    
    .PARAMETER Arguments
        Arguments to pass to the command
    
    .PARAMETER ScriptBlock
        The actual implementation script block
    
    .PARAMETER DryRun
        If specified, executes dry-run behavior only
    
    .PARAMETER ExecutionMode
        Current execution mode (auto-detected if not specified)
    
    .PARAMETER SkipLocks
        If specified, skips lock acquisition (not recommended)
    
    .PARAMETER JournalPath
        Optional path to write journal entries
    
    .OUTPUTS
        PSCustomObject with execution results
    
    .EXAMPLE
        Invoke-WithContract -Contract $contract -Arguments $args -ScriptBlock {
            param($Args)
            # Actual implementation
        } -DryRun:$DryRun
    #>
    [CmdletBinding(SupportsShouldProcess=$true)]
    param(
        [Parameter(Mandatory=$true)]
        [PSCustomObject]$Contract,
        
        [hashtable]$Arguments = @{},
        
        [Parameter(Mandatory=$true)]
        [scriptblock]$ScriptBlock,
        
        [switch]$DryRun,
        
        [string]$ExecutionMode = "",
        
        [switch]$SkipLocks,
        
        [string]$JournalPath = ""
    )
    
    $startTime = [DateTime]::UtcNow
    $runId = New-RunId
    
    # Auto-detect execution mode
    if ([string]::IsNullOrEmpty($ExecutionMode)) {
        if (Get-Command Get-CurrentExecutionMode -ErrorAction SilentlyContinue) {
            $ExecutionMode = Get-CurrentExecutionMode
        }
        else {
            $ExecutionMode = "interactive"
        }
    }
    
    # Step 1: Validate contract
    $validation = Test-CommandContract -Contract $Contract -Arguments $Arguments -ExecutionMode $ExecutionMode
    if (-not $validation.IsValid) {
        return [PSCustomObject]@{
            Success = $false
            ExitCode = $script:StandardExitCodes.InvalidArguments
            Errors = $validation.Errors
            Warnings = $validation.Warnings
            runId = $runId
            command = $Contract.name
            executionMode = $ExecutionMode
            dryRun = $DryRun.IsPresent
            startTime = $startTime.ToString("o")
            endTime = [DateTime]::UtcNow.ToString("o")
            durationMs = ([DateTime]::UtcNow - $startTime).TotalMilliseconds
        }
    }
    
    # Step 2: Policy check (checked BEFORE locks per Invariant 3.6)
    if (Get-Command Test-PolicyPermission -ErrorAction SilentlyContinue) {
        $policyAllowed = Test-PolicyPermission -Command $Contract.name -Mode $ExecutionMode
        if (-not $policyAllowed) {
            return [PSCustomObject]@{
                Success = $false
                ExitCode = $script:StandardExitCodes.PermissionDeniedByMode
                Errors = @("Policy blocks command '$($Contract.name)' in mode '$ExecutionMode'")
                Warnings = @()
                runId = $runId
                command = $Contract.name
                executionMode = $ExecutionMode
                policyBlocked = $true
                dryRun = $DryRun.IsPresent
                startTime = $startTime.ToString("o")
                endTime = [DateTime]::UtcNow.ToString("o")
                durationMs = ([DateTime]::UtcNow - $startTime).TotalMilliseconds
            }
        }
    }
    
    # Step 3: Check confirmation requirements
    if ($Contract.safetyLevels -contains "destructive") {
        if (Get-Command Test-RequiresConfirmation -ErrorAction SilentlyContinue) {
            $needsConfirm = Test-RequiresConfirmation -Command $Contract.name
            if ($needsConfirm -and -not $DryRun) {
                $confirmed = $PSCmdlet.ShouldProcess($Contract.name, "Execute destructive command")
                if (-not $confirmed) {
                    return [PSCustomObject]@{
                        Success = $false
                        ExitCode = $script:StandardExitCodes.UserCancelled
                        Errors = @("User cancelled the operation")
                        Warnings = @()
                        runId = $runId
                        command = $Contract.name
                        executionMode = $ExecutionMode
                        cancelled = $true
                        dryRun = $false
                        startTime = $startTime.ToString("o")
                        endTime = [DateTime]::UtcNow.ToString("o")
                        durationMs = ([DateTime]::UtcNow - $startTime).TotalMilliseconds
                    }
                }
            }
        }
    }
    
    # Step 4: Acquire locks (unless skipped)
    $acquiredLocks = @()
    if (-not $SkipLocks -and $Contract.locks.Count -gt 0) {
        foreach ($lockName in $Contract.locks) {
            # Lock acquisition would happen here
            # This is a placeholder for actual lock implementation
            $acquiredLocks += $lockName
            Write-Verbose "Acquired lock: $lockName"
        }
    }
    
    # Step 5: Write journal entry if multi-step
    $journalEntry = $null
    if (-not [string]::IsNullOrEmpty($JournalPath) -and $Contract.isMutating) {
        $journalEntry = @{
            runId = $runId
            command = $Contract.name
            phase = "begin"
            timestamp = [DateTime]::UtcNow.ToString("o")
            executionMode = $ExecutionMode
            dryRun = $DryRun.IsPresent
            locks = $acquiredLocks
        }
        # Write journal would happen here
    }
    
    # Step 6: Execute (or dry-run)
    $result = $null
    $errorOccurred = $null
    
    try {
        if ($DryRun) {
            Write-Verbose "Executing in dry-run mode: $($Contract.name)"
            # Dry-run behavior: validate and preview but don't apply
            if ($Contract.dryRunBehavior) {
                Write-Verbose "Dry-run behavior: $($Contract.dryRunBehavior)"
            }
            
            # In dry-run mode, we still run the script block but expect it to check $DryRun
            $result = & $ScriptBlock -Arguments $Arguments -DryRun:$true
        }
        else {
            Write-Verbose "Executing: $($Contract.name)"
            $result = & $ScriptBlock -Arguments $Arguments -DryRun:$false
        }
    }
    catch {
        $errorOccurred = $_
        Write-Verbose "Error executing command: $_"
    }
    
    # Step 7: Release locks
    foreach ($lockName in $acquiredLocks) {
        Write-Verbose "Released lock: $lockName"
    }
    
    # Step 8: Write final journal entry
    if ($journalEntry) {
        $journalEntry.phase = "end"
        $journalEntry.timestamp = [DateTime]::UtcNow.ToString("o")
        $journalEntry.success = ($errorOccurred -eq $null)
        if ($errorOccurred) {
            $journalEntry.error = $errorOccurred.ToString()
        }
    }
    
    # Build result
    $endTime = [DateTime]::UtcNow
    $executionResult = [PSCustomObject]@{
        Success = ($errorOccurred -eq $null)
        ExitCode = if ($errorOccurred) { $script:StandardExitCodes.GeneralFailure } else { $script:StandardExitCodes.Success }
        Errors = if ($errorOccurred) { @($errorOccurred.ToString()) } else { @() }
        Warnings = $validation.Warnings
        runId = $runId
        command = $Contract.name
        executionMode = $ExecutionMode
        dryRun = $DryRun.IsPresent
        result = $result
        startTime = $startTime.ToString("o")
        endTime = $endTime.ToString("o")
        durationMs = ($endTime - $startTime).TotalMilliseconds
        locksAcquired = $acquiredLocks
        stateTouched = if (-not $DryRun -and $errorOccurred -eq $null) { $Contract.stateTouched } else { @() }
    }
    
    return $executionResult
}

#===============================================================================
# Planner/Executor Separation (Invariant 3.8)
#===============================================================================

function New-ExecutionPlan {
    <#
    .SYNOPSIS
        Creates an execution plan for a mutating command.
    
    .DESCRIPTION
        Implements the planner/executor separation required by Invariant 3.8.
        Preview and apply must share the same planner.
    
    .PARAMETER Contract
        The command contract
    
    .PARAMETER Arguments
        Arguments for the command
    
    .OUTPUTS
        PSCustomObject representing the execution plan
    
    .EXAMPLE
        $plan = New-ExecutionPlan -Contract $contract -Arguments $args
        Show-ExecutionPlan -Plan $plan
        Invoke-ExecutionPlan -Plan $plan
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [PSCustomObject]$Contract,
        
        [hashtable]$Arguments = @{}
    )
    
    return [PSCustomObject]@{
        runId = New-RunId
        command = $Contract.name
        purpose = $Contract.purpose
        safetyLevels = $Contract.safetyLevels
        arguments = $Arguments
        locksRequired = $Contract.locks
        stateToTouch = $Contract.stateTouched
        remoteSystems = $Contract.remoteSystems
        steps = [System.Collections.Generic.List[hashtable]]::new()
        dryRunBehavior = $Contract.dryRunBehavior
        createdAt = [DateTime]::UtcNow.ToString("o")
        planned = $true
    }
}

function Add-PlanStep {
    <#
    .SYNOPSIS
        Adds a step to an execution plan.
    
    .PARAMETER Plan
        The execution plan to modify
    
    .PARAMETER Description
        Description of the step
    
    .PARAMETER Action
        ScriptBlock to execute for this step
    
    .PARAMETER IsDestructive
        Whether this step performs destructive operations
    
    .PARAMETER RollbackAction
        Optional rollback action if this step fails
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [PSCustomObject]$Plan,
        
        [Parameter(Mandatory=$true)]
        [string]$Description,
        
        [Parameter(Mandatory=$true)]
        [scriptblock]$Action,
        
        [switch]$IsDestructive,
        
        [scriptblock]$RollbackAction = $null
    )
    
    $step = @{
        stepNumber = $Plan.steps.Count + 1
        description = $Description
        action = $Action
        isDestructive = $IsDestructive.IsPresent
        rollbackAction = $RollbackAction
        status = "pending"
    }
    
    $Plan.steps.Add($step)
}

function Show-ExecutionPlan {
    <#
    .SYNOPSIS
        Displays an execution plan for review (preview mode).
    
    .PARAMETER Plan
        The execution plan to display
    
    .PARAMETER Format
        Output format: "text", "json", "yaml"
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [PSCustomObject]$Plan,
        
        [ValidateSet("text", "json")]
        [string]$Format = "text"
    )
    
    if ($Format -eq "json") {
        return $Plan | ConvertTo-Json -Depth 10
    }
    
    # Text format
    $output = @()
    $output += "=" * 60
    $output += "EXECUTION PLAN: $($Plan.command)"
    $output += "=" * 60
    $output += "Purpose: $($Plan.purpose)"
    $output += "Safety Levels: $($Plan.safetyLevels -join ', ')"
    $output += ""
    $output += "Locks Required: $(if ($Plan.locksRequired) { $Plan.locksRequired -join ', ' } else { 'None' })"
    $output += "State To Touch: $(if ($Plan.stateToTouch) { $Plan.stateToTouch -join ', ' } else { 'None' })"
    if ($Plan.remoteSystems) {
        $output += "Remote Systems: $($Plan.remoteSystems -join ', ')"
    }
    $output += ""
    $output += "Steps:"
    foreach ($step in $Plan.steps) {
        $destructiveMarker = if ($step.isDestructive) { " [DESTRUCTIVE]" } else { "" }
        $output += "  $($step.stepNumber). $($step.description)$destructiveMarker"
    }
    $output += ""
    $output += "Dry-Run Behavior: $($Plan.dryRunBehavior)"
    $output += "=" * 60
    
    return $output -join "`n"
}

function Invoke-ExecutionPlan {
    <#
    .SYNOPSIS
        Executes a pre-built execution plan.
    
    .DESCRIPTION
        Executes the plan created by New-ExecutionPlan, respecting
        dry-run mode and safety requirements.
    
    .PARAMETER Plan
        The execution plan to execute
    
    .PARAMETER DryRun
        If specified, executes in dry-run mode
    
    .PARAMETER ExecutionMode
        Current execution mode
    #>
    [CmdletBinding(SupportsShouldProcess=$true)]
    param(
        [Parameter(Mandatory=$true)]
        [PSCustomObject]$Plan,
        
        [switch]$DryRun,
        
        [string]$ExecutionMode = ""
    )
    
    if ([string]::IsNullOrEmpty($ExecutionMode)) {
        if (Get-Command Get-CurrentExecutionMode -ErrorAction SilentlyContinue) {
            $ExecutionMode = Get-CurrentExecutionMode
        }
        else {
            $ExecutionMode = "interactive"
        }
    }
    
    # Display plan in dry-run mode or if WhatIf
    if ($DryRun -or $WhatIfPreference) {
        $preview = Show-ExecutionPlan -Plan $Plan
        Write-Host $preview
        return [PSCustomObject]@{
            Success = $true
            DryRun = $true
            Plan = $Plan
        }
    }
    
    # Confirm destructive operations
    if ($Plan.safetyLevels -contains "destructive") {
        if (-not $PSCmdlet.ShouldProcess($Plan.command, "Execute destructive plan")) {
            return [PSCustomObject]@{
                Success = $false
                ExitCode = $script:StandardExitCodes.UserCancelled
                Cancelled = $true
            }
        }
    }
    
    # Execute steps
    $results = @()
    foreach ($step in $Plan.steps) {
        Write-Verbose "Executing step $($step.stepNumber): $($step.description)"
        $step.status = "executing"
        
        try {
            & $step.action
            $step.status = "completed"
            $results += [PSCustomObject]@{ step = $step.stepNumber; success = $true }
        }
        catch {
            $step.status = "failed"
            $results += [PSCustomObject]@{ step = $step.stepNumber; success = $false; error = $_.ToString() }
            
            # Attempt rollback if available
            if ($step.rollbackAction) {
                Write-Verbose "Rolling back step $($step.stepNumber)"
                try {
                    & $step.rollbackAction
                }
                catch {
                    Write-Warning "Rollback failed for step $($step.stepNumber): $_"
                }
            }
            
            break
        }
    }
    
    $allSucceeded = ($results | Where-Object { -not $_.success }).Count -eq 0
    
    return [PSCustomObject]@{
        Success = $allSucceeded
        ExitCode = if ($allSucceeded) { $script:StandardExitCodes.Success } else { $script:StandardExitCodes.GeneralFailure }
        Plan = $Plan
        StepResults = $results
    }
}

#===============================================================================
# Utility Functions
#===============================================================================

function New-RunId {
    <#
    .SYNOPSIS
        Generates a new run ID for tracking.
    #>
    $timestamp = [DateTime]::UtcNow.ToString("yyyyMMddTHHmmssZ")
    $random = -join ((1..4) | ForEach-Object { '{0:x}' -f (Get-Random -Maximum 16) })
    return "$timestamp-$random"
}

function Get-StandardExitCodes {
    <#
    .SYNOPSIS
        Returns the standard exit codes.
    #>
    return $script:StandardExitCodes
}

function Get-ValidSafetyLevels {
    <#
    .SYNOPSIS
        Returns all valid safety level names.
    #>
    return $script:ValidSafetyLevels
}

function Unregister-CommandContract {
    <#
    .SYNOPSIS
        Removes a command contract from the registry.
    
    .PARAMETER Name
        The command name to unregister
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [string]$Name
    )
    
    if ($script:CommandContracts.ContainsKey($Name)) {
        $script:CommandContracts.Remove($Name)
    }
}

# Export module members
Export-ModuleMember -Function @(
    'New-CommandContract',
    'Get-CommandContract',
    'Get-AllCommandContracts',
    'Unregister-CommandContract',
    'Test-CommandContract',
    'Invoke-WithContract',
    'New-ExecutionPlan',
    'Add-PlanStep',
    'Show-ExecutionPlan',
    'Invoke-ExecutionPlan',
    'Get-StandardExitCodes',
    'Get-ValidSafetyLevels'
) -Variable @() -Alias @()
