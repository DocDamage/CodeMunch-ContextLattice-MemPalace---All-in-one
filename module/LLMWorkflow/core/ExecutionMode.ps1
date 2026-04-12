# Policy and Execution Mode System - Execution Mode Management
# Manages execution modes and their capabilities per IMPROVEMENT_PROPOSALS.md section 5.3

Set-StrictMode -Version Latest

#===============================================================================
# Configuration and Constants
#===============================================================================

# Valid execution modes per IMPROVEMENT_PROPOSALS.md section 5.3
$script:ValidExecutionModes = @(
    "interactive",
    "ci",
    "watch",
    "heal-watch",
    "scheduled",
    "mcp-readonly",
    "mcp-mutating"
)

# Default mode capabilities (commands allowed in each mode)
$script:DefaultModeCapabilities = @{
    "interactive" = @{
        description = "Full interactive mode with all commands available"
        capabilities = @("*")  # All capabilities allowed
        allowDestructive = $true
        allowMutating = $true
        allowNetworked = $true
        requiresConfirmation = $true
        supportsTty = $true
        supportsPrompts = $true
    }
    "ci" = @{
        description = "Continuous Integration mode - safe for automated builds"
        capabilities = @("doctor", "status", "preview", "sync", "index", "build", "test", "validate", "explain", "search")
        allowDestructive = $false
        allowMutating = $true
        allowNetworked = $true
        requiresConfirmation = $false
        supportsTty = $false
        supportsPrompts = $false
    }
    "watch" = @{
        description = "File watcher mode - responds to filesystem changes"
        capabilities = @("sync", "index", "telemetry", "status")
        allowDestructive = $false
        allowMutating = $true
        allowNetworked = $true
        requiresConfirmation = $false
        supportsTty = $false
        supportsPrompts = $false
        autoConfirm = $true
    }
    "heal-watch" = @{
        description = "Auto-healing watcher mode - monitors and repairs"
        capabilities = @("doctor", "heal", "status", "telemetry")
        allowDestructive = $false
        allowMutating = $false
        allowNetworked = $false
        requiresConfirmation = $false
        supportsTty = $false
        supportsPrompts = $false
        autoConfirm = $true
    }
    "scheduled" = @{
        description = "Scheduled task mode - runs via cron/scheduler"
        capabilities = @("sync", "index", "telemetry", "backup", "status")
        allowDestructive = $false
        allowMutating = $true
        allowNetworked = $true
        requiresConfirmation = $false
        supportsTty = $false
        supportsPrompts = $false
        autoConfirm = $true
    }
    "mcp-readonly" = @{
        description = "Model Context Protocol read-only mode"
        capabilities = @("doctor", "status", "preview", "search", "explain", "config")
        allowDestructive = $false
        allowMutating = $false
        allowNetworked = $true
        requiresConfirmation = $false
        supportsTty = $false
        supportsPrompts = $false
        mcpRestricted = $true
    }
    "mcp-mutating" = @{
        description = "Model Context Protocol mutating mode"
        capabilities = @("doctor", "status", "preview", "search", "explain", "config", "sync", "index", "ingest", "build")
        allowDestructive = $false
        allowMutating = $true
        allowNetworked = $true
        requiresConfirmation = $false
        supportsTty = $false
        supportsPrompts = $false
        mcpRestricted = $true
    }
}

# Current execution mode (session-scoped)
$script:CurrentExecutionMode = $null

# Mode history for audit purposes
$script:ModeHistory = [System.Collections.Generic.List[hashtable]]::new()

#===============================================================================
# Execution Mode Policy Functions
#===============================================================================

function Get-ExecutionModePolicy {
    <#
    .SYNOPSIS
        Gets the policy configuration for a specific execution mode.
    
    .DESCRIPTION
        Returns the complete policy definition for an execution mode,
        including allowed capabilities, restrictions, and behavior settings.
    
    .PARAMETER Mode
        The execution mode to get policy for (e.g., "watch", "ci", "mcp-readonly")
    
    .OUTPUTS
        PSCustomObject containing the mode policy
    
    .EXAMPLE
        $policy = Get-ExecutionModePolicy -Mode "ci"
        if (-not $policy.allowDestructive) { Write-Host "Destructive ops blocked" }
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [ValidateScript({
            if ($script:ValidExecutionModes -notcontains $_) {
                throw "Invalid execution mode '$_'. Valid modes: $($script:ValidExecutionModes -join ', ')"
            }
            return $true
        })]
        [string]$Mode
    )
    
    $defaultPolicy = $script:DefaultModeCapabilities[$Mode]
    
    if (-not $defaultPolicy) {
        throw "No policy defined for execution mode '$Mode'"
    }
    
    # Convert to PSCustomObject for consistent access
    return [PSCustomObject]$defaultPolicy
}

function Test-ExecutionModeCapability {
    <#
    .SYNOPSIS
        Tests if a capability is allowed in a specific execution mode.
    
    .DESCRIPTION
        Checks whether a command or capability is permitted in the given
        execution mode. Also validates safety level restrictions.
    
    .PARAMETER Capability
        The capability or command name to test (e.g., "sync", "restore", "destructive")
    
    .PARAMETER Mode
        The execution mode to test against
    
    .PARAMETER SafetyLevel
        Optional safety level to validate
    
    .OUTPUTS
        Boolean indicating whether the capability is allowed
    
    .EXAMPLE
        if (-not (Test-ExecutionModeCapability -Capability "restore" -Mode "watch")) {
            Write-Error "Restore not allowed in watch mode"
        }
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [string]$Capability,
        
        [Parameter(Mandatory=$true)]
        [string]$Mode,
        
        [string]$SafetyLevel = ""
    )
    
    # Validate mode
    if ($script:ValidExecutionModes -notcontains $Mode) {
        Write-Warning "Unknown execution mode '$Mode'"
        return $false
    }
    
    $policy = Get-ExecutionModePolicy -Mode $Mode
    
    # Check if all capabilities are allowed (wildcard)
    if ($policy.capabilities -contains "*") {
        # Still need to check safety levels
        return Test-SafetyLevelForMode -SafetyLevel $SafetyLevel -Policy $policy
    }
    
    # Check if capability is in allowed list
    if ($policy.capabilities -notcontains $Capability) {
        Write-Verbose "Capability '$Capability' not in allowed list for mode '$Mode'"
        return $false
    }
    
    # Check safety level restrictions
    return Test-SafetyLevelForMode -SafetyLevel $SafetyLevel -Policy $policy
}

function Test-SafetyLevelForMode {
    <#
    .SYNOPSIS
        Internal function to test safety level against mode policy.
    #>
    [CmdletBinding()]
    param(
        [string]$SafetyLevel,
        [PSCustomObject]$Policy
    )
    
    if ([string]::IsNullOrEmpty($SafetyLevel)) {
        return $true
    }
    
    switch ($SafetyLevel.ToLower()) {
        "destructive" { return $Policy.allowDestructive -eq $true }
        "mutating" { return $Policy.allowMutating -eq $true }
        "networked" { return $Policy.allowNetworked -eq $true }
        "read-only" { return $true }  # Always allowed
        default { return $true }
    }
}

function Get-CurrentExecutionMode {
    <#
    .SYNOPSIS
        Gets the current execution mode for this session.
    
    .DESCRIPTION
        Returns the currently active execution mode. If no mode has been
        explicitly set, returns the default mode (interactive) or the
        mode specified by LLM_WORKFLOW_MODE environment variable.
    
    .OUTPUTS
        String representing the current execution mode
    
    .EXAMPLE
        $currentMode = Get-CurrentExecutionMode
    #>
    [CmdletBinding()]
    param()
    
    # Return explicitly set mode
    if ($script:CurrentExecutionMode) {
        return $script:CurrentExecutionMode
    }
    
    # Check environment variable
    if ($env:LLM_WORKFLOW_MODE -and $script:ValidExecutionModes -contains $env:LLM_WORKFLOW_MODE) {
        $script:CurrentExecutionMode = $env:LLM_WORKFLOW_MODE
        return $script:CurrentExecutionMode
    }
    
    # Default to interactive
    return "interactive"
}

function Switch-ExecutionMode {
    <#
    .SYNOPSIS
        Changes the current execution mode with validation.
    
    .DESCRIPTION
        Switches to a new execution mode after validating the transition
        is allowed. Records the mode change in history.
    
    .PARAMETER Mode
        The execution mode to switch to
    
    .PARAMETER Force
        Bypass validation checks (use with caution)
    
    .PARAMETER Reason
        Optional reason for the mode change (for audit log)
    
    .OUTPUTS
        PSCustomObject with mode change details
    
    .EXAMPLE
        Switch-ExecutionMode -Mode "ci" -Reason "Running in Jenkins pipeline"
    #>
    [CmdletBinding(SupportsShouldProcess=$true)]
    param(
        [Parameter(Mandatory=$true)]
        [ValidateScript({
            if ($script:ValidExecutionModes -notcontains $_) {
                throw "Invalid execution mode '$_'. Valid modes: $($script:ValidExecutionModes -join ', ')"
            }
            return $true
        })]
        [string]$Mode,
        
        [switch]$Force,
        
        [string]$Reason = ""
    )
    
    $currentMode = Get-CurrentExecutionMode
    
    # Check if already in this mode
    if ($currentMode -eq $Mode) {
        Write-Verbose "Already in execution mode '$Mode'"
        return [PSCustomObject]@{
            previousMode = $Mode
            newMode = $Mode
            changed = $false
            timestamp = [DateTime]::UtcNow.ToString("o")
        }
    }
    
    # Validate mode transition
    if (-not $Force) {
        $validation = Test-ModeTransition -FromMode $currentMode -ToMode $Mode
        if (-not $validation.IsValid) {
            throw "Invalid mode transition from '$currentMode' to '$Mode': $($validation.Reason)"
        }
    }
    
    # Confirm the change
    if ($PSCmdlet.ShouldProcess("Switching from '$currentMode' to '$Mode'", "Execution Mode")) {
        # Record in history
        $historyEntry = @{
            timestamp = [DateTime]::UtcNow.ToString("o")
            previousMode = $currentMode
            newMode = $Mode
            reason = $Reason
            forced = $Force.IsPresent
        }
        $script:ModeHistory.Add($historyEntry)
        
        # Set the new mode
        $script:CurrentExecutionMode = $Mode
        
        # Update environment variable for child processes
        $env:LLM_WORKFLOW_MODE = $Mode
        
        Write-Verbose "Switched execution mode from '$currentMode' to '$Mode'"
        
        return [PSCustomObject]@{
            previousMode = $currentMode
            newMode = $Mode
            changed = $true
            timestamp = $historyEntry.timestamp
            reason = $Reason
        }
    }
    
    return $null
}

function Test-ModeTransition {
    <#
    .SYNOPSIS
        Validates whether a mode transition is allowed.
    
    .PARAMETER FromMode
        Source execution mode
    
    .PARAMETER ToMode
        Target execution mode
    #>
    [CmdletBinding()]
    param(
        [string]$FromMode,
        [string]$ToMode
    )
    
    # Define restricted transitions
    # Some modes should not transition to others for safety
    $restrictedTransitions = @{
        "mcp-readonly" = @("interactive")  # MCP readonly can only go to interactive
        "mcp-mutating" = @("interactive", "mcp-readonly")
    }
    
    $result = @{
        IsValid = $true
        Reason = ""
    }
    
    # Check restricted transitions
    if ($restrictedTransitions.ContainsKey($FromMode)) {
        $allowedTargets = $restrictedTransitions[$FromMode]
        if ($allowedTargets -notcontains $ToMode) {
            $result.IsValid = $false
            $result.Reason = "Mode '$FromMode' can only transition to: $($allowedTargets -join ', ')"
            return $result
        }
    }
    
    # Check for downgrade from interactive when in sensitive context
    if ($FromMode -eq "interactive" -and $ToMode -ne "interactive") {
        # This is generally allowed but could have additional checks
        # e.g., verify no destructive operations are in progress
    }
    
    return $result
}

function Get-AllowedCommands {
    <#
    .SYNOPSIS
        Gets the list of commands allowed in the specified execution mode.
    
    .DESCRIPTION
        Returns the complete list of commands that are permitted in the
        given execution mode, including their safety levels.
    
    .PARAMETER Mode
        The execution mode to query
    
    .PARAMETER IncludeDetails
        If specified, returns detailed information about each command
    
    .OUTPUTS
        Array of command names or detailed objects
    
    .EXAMPLE
        $allowed = Get-AllowedCommands -Mode "watch"
        $detailed = Get-AllowedCommands -Mode "ci" -IncludeDetails
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [string]$Mode,
        
        [switch]$IncludeDetails
    )
    
    $policy = Get-ExecutionModePolicy -Mode $Mode
    
    if (-not $IncludeDetails) {
        return $policy.capabilities
    }
    
    # Return detailed information
    $commands = @()
    foreach ($capability in $policy.capabilities) {
        $safetyLevel = Get-CommandSafetyLevel -Command $capability
        $commands += [PSCustomObject]@{
            command = $capability
            safetyLevel = $safetyLevel
            allowed = $true
        }
    }
    
    return $commands
}

function Get-CommandSafetyLevel {
    <#
    .SYNOPSIS
        Returns the safety level for a command.
    
    .DESCRIPTION
        Maps commands to their safety levels based on IMPROVEMENT_PROPOSALS.md:
        - read-only: doctor, status, preview, search, explain
        - mutating: sync, index, ingest, build
        - destructive: restore, prune, delete, clean
        - networked: remote sync, provider calls
    
    .PARAMETER Command
        The command name to lookup
    
    .OUTPUTS
        String array of safety levels (commands can have multiple)
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [string]$Command
    )
    
    $safetyLevels = [System.Collections.Generic.List[string]]::new()
    
    # Read-only commands
    $readOnlyCommands = @("doctor", "status", "preview", "search", "explain", "config", "help", "version")
    if ($readOnlyCommands -contains $Command) {
        $safetyLevels.Add("read-only")
    }
    
    # Mutating commands
    $mutatingCommands = @("sync", "index", "ingest", "build", "update", "create")
    if ($mutatingCommands -contains $Command) {
        $safetyLevels.Add("mutating")
    }
    
    # Destructive commands
    $destructiveCommands = @("restore", "prune", "delete", "clean", "destroy", "reset")
    if ($destructiveCommands -contains $Command) {
        $safetyLevels.Add("destructive")
    }
    
    # Networked commands (can overlap with others)
    $networkedCommands = @("sync", "ingest", "remote-sync", "provider", "fetch", "push")
    if ($networkedCommands -contains $Command) {
        $safetyLevels.Add("networked")
    }
    
    if ($safetyLevels.Count -eq 0) {
        return @("unknown")
    }
    
    return $safetyLevels.ToArray()
}

#===============================================================================
# Mode Context and Environment Functions
#===============================================================================

function Get-ExecutionModeContext {
    <#
    .SYNOPSIS
        Gets comprehensive context about the current execution mode.
    
    .DESCRIPTION
        Returns detailed information about the current mode including
        its capabilities, restrictions, and current environment state.
    
    .OUTPUTS
        PSCustomObject with full mode context
    
    .EXAMPLE
        $context = Get-ExecutionModeContext
        if (-not $context.supportsPrompts) { Write-Host "Non-interactive" }
    #>
    [CmdletBinding()]
    param()
    
    $currentMode = Get-CurrentExecutionMode
    $policy = Get-ExecutionModePolicy -Mode $currentMode
    
    return [PSCustomObject]@{
        mode = $currentMode
        description = $policy.description
        capabilities = $policy.capabilities
        restrictions = @{
            allowDestructive = $policy.allowDestructive
            allowMutating = $policy.allowMutating
            allowNetworked = $policy.allowNetworked
            requiresConfirmation = $policy.requiresConfirmation
        }
        environment = @{
            supportsTty = $policy.supportsTty
            supportsPrompts = $policy.supportsPrompts
            isMcpRestricted = $policy.mcpRestricted -eq $true
            autoConfirm = $policy.autoConfirm -eq $true
        }
        timestamp = [DateTime]::UtcNow.ToString("o")
        modeHistory = $script:ModeHistory | Select-Object -Last 10
    }
}

function Test-IsInteractiveMode {
    <#
    .SYNOPSIS
        Tests if the current execution mode supports interactive prompts.
    
    .OUTPUTS
        Boolean indicating if prompts are supported
    #>
    [CmdletBinding()]
    param()
    
    $policy = Get-ExecutionModePolicy -Mode (Get-CurrentExecutionMode)
    return $policy.supportsPrompts -eq $true
}

function Test-IsDryRunMode {
    <#
    .SYNOPSIS
        Tests if the current execution context is in dry-run mode.
    
    .DESCRIPTION
        Checks both the explicit DryRun parameter and environment
        variables to determine if dry-run behavior should apply.
    
    .OUTPUTS
        Boolean indicating if dry-run mode is active
    #>
    [CmdletBinding()]
    param()
    
    # Check common dry-run environment variables
    if ($env:LLM_WORKFLOW_DRY_RUN -eq "true" -or 
        $env:DRY_RUN -eq "true" -or
        $env:CI_DRY_RUN -eq "true") {
        return $true
    }
    
    # Check WhatIf preference
    if ($WhatIfPreference) {
        return $true
    }
    
    return $false
}

function Get-ModeHistory {
    <#
    .SYNOPSIS
        Gets the history of execution mode changes.
    
    .PARAMETER Limit
        Maximum number of history entries to return
    
    .OUTPUTS
        Array of mode change records
    #>
    [CmdletBinding()]
    param(
        [int]$Limit = 100
    )
    
    return $script:ModeHistory | Select-Object -Last $Limit
}

function Clear-ModeHistory {
    <#
    .SYNOPSIS
        Clears the execution mode change history.
    #>
    [CmdletBinding(SupportsShouldProcess=$true)]
    param()
    
    if ($PSCmdlet.ShouldProcess("Mode history", "Clear")) {
        $script:ModeHistory.Clear()
        Write-Verbose "Mode history cleared"
    }
}

#===============================================================================
# Utility Functions
#===============================================================================

function Get-ValidExecutionModes {
    <#
    .SYNOPSIS
        Returns all valid execution mode names.
    #>
    return $script:ValidExecutionModes
}

function Test-IsValidExecutionMode {
    <#
    .SYNOPSIS
        Tests if a string is a valid execution mode.
    
    .PARAMETER Mode
        The mode name to test
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [string]$Mode
    )
    
    return $script:ValidExecutionModes -contains $Mode
}

function Get-ExecutionModeSummary {
    <#
    .SYNOPSIS
        Returns a summary of all execution modes and their key characteristics.
    #>
    [CmdletBinding()]
    param()
    
    $summary = @()
    foreach ($mode in $script:ValidExecutionModes) {
        $policy = $script:DefaultModeCapabilities[$mode]
        $summary += [PSCustomObject]@{
            mode = $mode
            description = $policy.description
            commandCount = $policy.capabilities.Count
            allowsDestructive = $policy.allowDestructive
            allowsMutating = $policy.allowMutating
            supportsPrompts = $policy.supportsPrompts
        }
    }
    
    return $summary
}

# Export module members
Export-ModuleMember -Function @(
    'Get-ExecutionModePolicy',
    'Test-ExecutionModeCapability',
    'Get-CurrentExecutionMode',
    'Switch-ExecutionMode',
    'Get-AllowedCommands',
    'Get-CommandSafetyLevel',
    'Get-ExecutionModeContext',
    'Test-IsInteractiveMode',
    'Test-IsDryRunMode',
    'Get-ModeHistory',
    'Clear-ModeHistory',
    'Get-ValidExecutionModes',
    'Test-IsValidExecutionMode',
    'Get-ExecutionModeSummary'
) -Variable @() -Alias @()
