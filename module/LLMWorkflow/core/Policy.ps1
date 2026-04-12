# Policy and Execution Mode System - Policy Enforcement
# Invariant 3.6: Destructive or agent-invokable operations must pass a policy gate before execution

Set-StrictMode -Version Latest

#===============================================================================
# Configuration and Constants
#===============================================================================

$script:PolicyFileName = "policy.json"
$script:DefaultPolicyPath = Join-Path $HOME ".llm-workflow\config\$script:PolicyFileName"

# Default policy configuration when no policy file exists
$script:DefaultPolicy = @{
    schemaVersion = 1
    defaultMode = "interactive"
    rules = @{
        "mcp-readonly" = @{
            allow = @("doctor", "status", "preview", "search", "explain", "config")
            deny = @("restore", "prune", "delete", "switch-provider", "migrate", "clean")
        }
        "mcp-mutating" = @{
            allow = @("doctor", "status", "preview", "search", "explain", "config", "sync", "index", "ingest", "build")
            deny = @("restore", "prune", "delete")
        }
        "watch" = @{
            allow = @("sync", "index", "telemetry", "status")
            deny = @("migrate", "restore", "prune", "delete", "switch-provider", "clean")
        }
        "heal-watch" = @{
            allow = @("doctor", "heal", "status", "telemetry")
            deny = @("migrate", "restore", "prune", "delete", "sync", "index", "ingest")
        }
        "ci" = @{
            allow = @("doctor", "status", "preview", "sync", "index", "build", "test", "validate")
            deny = @("restore", "prune", "delete", "switch-provider", "clean", "migrate")
        }
        "scheduled" = @{
            allow = @("sync", "index", "telemetry", "backup", "status")
            deny = @("restore", "prune", "delete", "migrate", "switch-provider", "clean")
        }
        "interactive" = @{
            allow = @("*")
            deny = @()
        }
    }
    requireConfirmationFor = @("restore", "prune", "delete", "provider-rotate", "migrate", "clean")
}

# Registered actions that require confirmation (populated at runtime)
$script:RegisteredPolicyActions = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)

# Safety levels that trigger policy checks
enum SafetyLevel {
    ReadOnly
    Mutating
    Destructive
    Networked
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
}

#===============================================================================
# Policy Configuration Functions
#===============================================================================

function Get-PolicyRules {
    <#
    .SYNOPSIS
        Loads and returns the policy configuration.
    
    .DESCRIPTION
        Loads policy from the policy.json file if it exists, otherwise returns
        the built-in default policy. Performs schema version validation.
    
    .PARAMETER PolicyPath
        Optional path to a custom policy file. Defaults to ~/.llm-workflow/config/policy.json
    
    .PARAMETER MergeWithDefaults
        If specified, merges the loaded policy with defaults for missing properties.
    
    .OUTPUTS
        PSCustomObject containing the policy configuration
    
    .EXAMPLE
        $policy = Get-PolicyRules
        $policy = Get-PolicyRules -PolicyPath "./custom-policy.json"
    #>
    [CmdletBinding()]
    param(
        [string]$PolicyPath = $script:DefaultPolicyPath,
        [switch]$MergeWithDefaults
    )
    
    $policy = $null
    
    # Try to load from file if it exists
    if (Test-Path -LiteralPath $PolicyPath -PathType Leaf) {
        try {
            $content = Get-Content -LiteralPath $PolicyPath -Raw -ErrorAction Stop
            $policy = $content | ConvertFrom-Json -ErrorAction Stop
            
            # Validate schema version
            if (-not $policy.schemaVersion) {
                Write-Warning "Policy file missing schemaVersion. Using defaults."
                $policy = $null
            }
            elseif ($policy.schemaVersion -gt 1) {
                Write-Warning "Policy file has unsupported schema version $($policy.schemaVersion). Using defaults."
                $policy = $null
            }
        }
        catch {
            Write-Warning "Failed to load policy file from '$PolicyPath': $_"
            $policy = $null
        }
    }
    
    # Use defaults if loading failed or file doesn't exist
    if (-not $policy) {
        $policy = $script:DefaultPolicy | ConvertTo-Json -Depth 10 | ConvertFrom-Json
    }
    elseif ($MergeWithDefaults) {
        # Merge with defaults for any missing properties
        $policy = Merge-PolicyWithDefaults -Policy $policy
    }
    
    return $policy
}

function Merge-PolicyWithDefaults {
    <#
    .SYNOPSIS
        Merges a policy object with default values for missing properties.
    
    .PARAMETER Policy
        The policy object to merge
    #>
    [CmdletBinding()]
    param([PSCustomObject]$Policy)
    
    $defaults = $script:DefaultPolicy
    $merged = @{
        schemaVersion = $Policy.schemaVersion
        defaultMode = if ($Policy.defaultMode) { $Policy.defaultMode } else { $defaults.defaultMode }
        rules = @{}
        requireConfirmationFor = [System.Collections.Generic.List[string]]::new()
    }
    
    # Merge rules
    $defaultRules = $defaults.rules
    $policyRules = $Policy.rules
    
    if ($policyRules) {
        $policyRules.PSObject.Properties | ForEach-Object {
            $mode = $_.Name
            $rule = $_.Value
            $merged.rules[$mode] = @{
                allow = if ($rule.allow) { $rule.allow } else { @() }
                deny = if ($rule.deny) { $rule.deny } else { @() }
            }
        }
    }
    
    # Add any missing default rules
    $defaultRules.Keys | ForEach-Object {
        if (-not $merged.rules.ContainsKey($_)) {
            $merged.rules[$_] = $defaultRules[$_]
        }
    }
    
    # Merge requireConfirmationFor
    if ($Policy.requireConfirmationFor) {
        $Policy.requireConfirmationFor | ForEach-Object { $merged.requireConfirmationFor.Add($_) }
    }
    $defaults.requireConfirmationFor | ForEach-Object {
        if (-not $merged.requireConfirmationFor.Contains($_)) {
            $merged.requireConfirmationFor.Add($_)
        }
    }
    
    return [PSCustomObject]$merged
}

function Save-PolicyRules {
    <#
    .SYNOPSIS
        Saves a policy configuration to file.
    
    .PARAMETER Policy
        The policy object to save
    
    .PARAMETER PolicyPath
        Path to save the policy file
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [hashtable]$Policy,
        
        [string]$PolicyPath = $script:DefaultPolicyPath
    )
    
    # Ensure directory exists
    $dir = Split-Path -Parent $PolicyPath
    if (-not (Test-Path -LiteralPath $dir)) {
        New-Item -ItemType Directory -Path $dir -Force | Out-Null
    }
    
    # Add standard header per IMPROVEMENT_PROPOSALS.md section 4.3
    $Policy['updatedUtc'] = [DateTime]::UtcNow.ToString("o")
    if (-not $Policy.ContainsKey('createdByRunId')) {
        $Policy['createdByRunId'] = New-RunId
    }
    
    $json = $Policy | ConvertTo-Json -Depth 10
    $json | Set-Content -LiteralPath $PolicyPath -Encoding UTF8 -Force
}

function New-RunId {
    <#
    .SYNOPSIS
        Generates a new run ID for tracking.
    #>
    $timestamp = [DateTime]::UtcNow.ToString("yyyyMMddTHHmmssZ")
    $random = -join ((1..4) | ForEach-Object { '{0:x}' -f (Get-Random -Maximum 16) })
    return "$timestamp-$random"
}

#===============================================================================
# Policy Permission Functions
#===============================================================================

function Test-PolicyPermission {
    <#
    .SYNOPSIS
        Checks if a command is allowed under the current policy and execution mode.
    
    .DESCRIPTION
        Tests whether a command can be executed based on the current execution mode
        and policy rules. Policy is checked before locks and before apply (Invariant 3.6).
    
    .PARAMETER Command
        The command name to check (e.g., "sync", "restore", "doctor")
    
    .PARAMETER Mode
        The execution mode to check against (e.g., "watch", "ci", "mcp-readonly")
    
    .PARAMETER Policy
        Optional policy object. If not provided, will load from file.
    
    .PARAMETER SafetyLevels
        Optional array of safety levels for the command. Used for additional validation.
    
    .OUTPUTS
        Boolean indicating whether the operation is allowed
    
    .EXAMPLE
        if (-not (Test-PolicyPermission -Command "sync" -Mode "watch")) {
            Write-Error "Policy blocks 'sync' in watch mode"
            exit 11
        }
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [string]$Command,
        
        [Parameter(Mandatory=$true)]
        [string]$Mode,
        
        [PSCustomObject]$Policy = $null,
        
        [SafetyLevel[]]$SafetyLevels = @()
    )
    
    # Load policy if not provided
    if (-not $Policy) {
        $Policy = Get-PolicyRules
    }
    
    # Check if mode exists in rules
    if (-not $Policy.rules.$Mode) {
        Write-Verbose "Execution mode '$Mode' not found in policy rules. Using default policy."
        $Mode = $Policy.defaultMode
    }
    
    $modeRules = $Policy.rules.$Mode
    
    # Check deny list first (explicit deny takes precedence)
    if ($modeRules.deny -contains $Command -or $modeRules.deny -contains "*") {
        Write-Verbose "Command '$Command' is explicitly denied in mode '$Mode'"
        return $false
    }
    
    # Check allow list
    if ($modeRules.allow -contains "*" -or $modeRules.allow -contains $Command) {
        # Also check safety level restrictions for this mode
        return Test-SafetyLevelPermission -SafetyLevels $SafetyLevels -Mode $Mode -ModeRules $modeRules
    }
    
    Write-Verbose "Command '$Command' not in allow list for mode '$Mode'"
    return $false
}

function Test-SafetyLevelPermission {
    <#
    .SYNOPSIS
        Validates safety levels against mode-specific restrictions.
    
    .PARAMETER SafetyLevels
        Array of safety levels for the command
    
    .PARAMETER Mode
        Current execution mode
    
    .PARAMETER ModeRules
        Rules for the current mode
    #>
    [CmdletBinding()]
    param(
        [SafetyLevel[]]$SafetyLevels,
        [string]$Mode,
        [PSCustomObject]$ModeRules
    )
    
    # Define mode-specific safety restrictions
    $modeSafetyRestrictions = @{
        "mcp-readonly" = @([SafetyLevel]::ReadOnly)
        "watch" = @([SafetyLevel]::ReadOnly, [SafetyLevel]::Mutating, [SafetyLevel]::Networked)
        "ci" = @([SafetyLevel]::ReadOnly, [SafetyLevel]::Mutating, [SafetyLevel]::Networked)
    }
    
    if ($modeSafetyRestrictions.ContainsKey($Mode) -and $SafetyLevels.Count -gt 0) {
        $allowedLevels = $modeSafetyRestrictions[$Mode]
        foreach ($level in $SafetyLevels) {
            if ($allowedLevels -notcontains $level) {
                Write-Verbose "Safety level '$level' not allowed in mode '$Mode'"
                return $false
            }
        }
    }
    
    return $true
}

function Assert-PolicyPermission {
    <#
    .SYNOPSIS
        Asserts that a command is allowed under current policy, throwing if not.
    
    .DESCRIPTION
        Similar to Test-PolicyPermission but throws a terminating error if the
        command is not allowed. Returns silently if permission is granted.
    
    .PARAMETER Command
        The command name to check
    
    .PARAMETER Mode
        The execution mode
    
    .PARAMETER Policy
        Optional policy object
    
    .PARAMETER SafetyLevels
        Optional array of safety levels
    
    .EXAMPLE
        Assert-PolicyPermission -Command "restore" -Mode "watch"
        # Will throw if not allowed
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [string]$Command,
        
        [Parameter(Mandatory=$true)]
        [string]$Mode,
        
        [PSCustomObject]$Policy = $null,
        
        [SafetyLevel[]]$SafetyLevels = @()
    )
    
    $allowed = Test-PolicyPermission -Command $Command -Mode $Mode -Policy $Policy -SafetyLevels $SafetyLevels
    
    if (-not $allowed) {
        $exitCode = $script:ExitCodes.PermissionDeniedByMode
        $message = "Policy blocks command '$Command' in execution mode '$Mode' (Exit code: $exitCode)"
        throw [System.UnauthorizedAccessException]::new($message)
    }
}

#===============================================================================
# Confirmation Functions
#===============================================================================

function Test-RequiresConfirmation {
    <#
    .SYNOPSIS
        Checks if a command requires confirmation before execution.
    
    .PARAMETER Command
        The command name to check
    
    .PARAMETER Policy
        Optional policy object
    
    .OUTPUTS
        Boolean indicating whether confirmation is required
    
    .EXAMPLE
        if (Test-RequiresConfirmation -Command "restore") {
            # Prompt for confirmation
        }
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [string]$Command,
        
        [PSCustomObject]$Policy = $null
    )
    
    if (-not $Policy) {
        $Policy = Get-PolicyRules
    }
    
    # Check registered actions
    if ($script:RegisteredPolicyActions.Contains($Command)) {
        return $true
    }
    
    # Check policy configuration
    if ($Policy.requireConfirmationFor -contains $Command) {
        return $true
    }
    
    return $false
}

function Request-Confirmation {
    <#
    .SYNOPSIS
        Prompts the user for confirmation before executing a dangerous operation.
    
    .DESCRIPTION
        Displays a confirmation prompt including the operation description and
        impact assessment. Supports -Confirm common parameter pattern.
    
    .PARAMETER Operation
        Name of the operation being performed (e.g., "restore", "prune")
    
    .PARAMETER Impact
        Description of the impact this operation will have
    
    .PARAMETER Target
        Optional target of the operation (e.g., file path, resource name)
    
    .PARAMETER Confirm
        If specified, bypasses the prompt and returns $true (simulates -Confirm:$false)
    
    .PARAMETER WhatIf
        If specified, returns $false without prompting (dry-run mode)
    
    .OUTPUTS
        Boolean indicating whether the user confirmed
    
    .EXAMPLE
        $confirmed = Request-Confirmation -Operation "restore" `
            -Impact "Will overwrite local palace with backup from 2026-04-10" `
            -Target "/path/to/palace"
        if (-not $confirmed) { exit 12 }
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [string]$Operation,
        
        [Parameter(Mandatory=$true)]
        [string]$Impact,
        
        [string]$Target = "",
        
        [switch]$Confirm,
        
        [switch]$WhatIf
    )
    
    # In WhatIf mode, don't actually confirm
    if ($WhatIf) {
        Write-Verbose "[WhatIf] Would prompt for confirmation: $Operation - $Impact"
        return $true
    }
    
    # If -Confirm:$false was passed (bypass confirmation)
    if ($Confirm -and $PSCmdlet.MyInvocation.BoundParameters['Confirm'] -eq $false) {
        Write-Verbose "Confirmation bypassed via -Confirm:`$false"
        return $true
    }
    
    # Build the prompt
    Write-Host ""
    Write-Host "CONFIRMATION REQUIRED" -ForegroundColor Yellow
    Write-Host ("=" * 50) -ForegroundColor Yellow
    Write-Host "Operation: $Operation" -ForegroundColor Cyan
    if ($Target) {
        Write-Host "Target: $Target" -ForegroundColor Cyan
    }
    Write-Host "Impact: $Impact" -ForegroundColor $(if ($Impact -match "destructive|delete|overwrite|remove") { "Red" } else { "Yellow" })
    Write-Host ("=" * 50) -ForegroundColor Yellow
    
    # In non-interactive mode, fail safe
    if (-not $Host.UI.RawUI -or $env:CI -eq "true" -or -not [Environment]::UserInteractive) {
        Write-Warning "Running in non-interactive mode. Operation requires confirmation. Use -Confirm:`$false to bypass."
        return $false
    }
    
    # Prompt for confirmation
    $caption = "Are you sure you want to continue?"
    $message = "This operation cannot be undone. Type 'yes' to proceed:"
    $choices = @(
        New-Object System.Management.Automation.Host.ChoiceDescription "&Yes", "Proceed with the operation"
        New-Object System.Management.Automation.Host.ChoiceDescription "&No", "Cancel the operation"
    )
    
    $result = $Host.UI.PromptForChoice($caption, $message, $choices, 1)
    
    return ($result -eq 0)
}

function Register-PolicyAction {
    <#
    .SYNOPSIS
        Registers a command as requiring confirmation before execution.
    
    .DESCRIPTION
        Allows runtime registration of commands that should require confirmation.
        This is useful for plugins and extensions.
    
    .PARAMETER Command
        The command name to register
    
    .PARAMETER ConfirmationMessage
        Optional custom confirmation message template
    
    .EXAMPLE
        Register-PolicyAction -Command "dangerous-cleanup" -ConfirmationMessage "This will delete all temporary files"
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [string]$Command,
        
        [string]$ConfirmationMessage = ""
    )
    
    [void]$script:RegisteredPolicyActions.Add($Command)
    
    if ($ConfirmationMessage) {
        # Store custom message if needed
        # This could be expanded to use a dictionary for custom messages
        Write-Verbose "Registered action '$Command' with custom message: $ConfirmationMessage"
    }
    else {
        Write-Verbose "Registered action '$Command' as requiring confirmation"
    }
}

function Unregister-PolicyAction {
    <#
    .SYNOPSIS
        Unregisters a previously registered policy action.
    
    .PARAMETER Command
        The command name to unregister
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [string]$Command
    )
    
    [void]$script:RegisteredPolicyActions.Remove($Command)
    Write-Verbose "Unregistered action '$Command'"
}

#===============================================================================
# Utility Functions
#===============================================================================

function Get-PolicyExitCode {
    <#
    .SYNOPSIS
        Returns the exit code for policy-related failures.
    
    .PARAMETER Reason
        The reason for failure: PolicyBlocked or PermissionDeniedByMode
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [ValidateSet("PolicyBlocked", "PermissionDeniedByMode", "UserCancelled")]
        [string]$Reason
    )
    
    switch ($Reason) {
        "PolicyBlocked" { return $script:ExitCodes.PolicyBlocked }
        "PermissionDeniedByMode" { return $script:ExitCodes.PermissionDeniedByMode }
        "UserCancelled" { return $script:ExitCodes.UserCancelled }
        default { return $script:ExitCodes.GeneralFailure }
    }
}

function Get-AllSafetyLevels {
    <#
    .SYNOPSIS
        Returns all available safety levels.
    #>
    return [Enum]::GetNames([SafetyLevel])
}

# Export module members
Export-ModuleMember -Function @(
    'Get-PolicyRules',
    'Save-PolicyRules',
    'Test-PolicyPermission',
    'Assert-PolicyPermission',
    'Test-RequiresConfirmation',
    'Request-Confirmation',
    'Register-PolicyAction',
    'Unregister-PolicyAction',
    'Get-PolicyExitCode',
    'Get-AllSafetyLevels'
) -Variable @('ExitCodes') -Alias @()
