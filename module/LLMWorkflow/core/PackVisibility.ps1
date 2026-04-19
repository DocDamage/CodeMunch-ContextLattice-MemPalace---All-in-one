#requires -Version 5.1
Set-StrictMode -Version Latest

<#
.SYNOPSIS
    Workspace and Visibility Boundary System - Pack-Level Visibility
.DESCRIPTION
    Provides pack-level visibility controls including visibility configuration,
    access testing, retrieval priority management, and answer context validation.
.NOTES
    File: PackVisibility.ps1
    Version: 1.0.0
    Compatible with: PowerShell 5.1+
#>

#region Private Helper Functions

function Test-AnswerContextAllowed {
    <#
    .SYNOPSIS
        Tests if answer context is allowed for pack usage.
    #>
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [Parameter(Mandatory = $true)]
        [string]$AllowedContext,
        
        [Parameter(Mandatory = $true)]
        [string]$CurrentContext,
        
        [string]$PackContext = ''
    )
    
    switch ($AllowedContext) {
        'local-only' {
            return ($CurrentContext -eq $PackContext)
        }
        'same-project' {
            return ($CurrentContext -eq $PackContext -or $CurrentContext.StartsWith($PackContext))
        }
        'same-pack' {
            return ($CurrentContext -eq $PackContext)
        }
        'any' {
            return $true
        }
        default {
            return $false
        }
    }
}

function Get-PackTypePriority {
    <#
    .SYNOPSIS
        Gets priority score for pack type (higher = search first).
    #>
    [CmdletBinding()]
    [OutputType([int])]
    param(
        [Parameter(Mandatory = $true)]
        [string]$PackId
    )
    
    # Private project packs get highest priority
    if ($PackId -match '_private_|-private-') {
        return 100
    }
    
    # Team packs
    if ($PackId -match '_team_|-team-') {
        return 80
    }
    
    # Domain-specific packs
    if ($PackId -match 'rpgmaker|unity|unreal|godot') {
        return 60
    }
    
    # Core/reference packs
    if ($PackId -match '_core_|_reference_|_api_') {
        return 40
    }
    
    # General packs
    return 20
}

function Write-PackAccessLog {
    <#
    .SYNOPSIS
        Logs pack access decisions for audit.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$PackId,
        
        [Parameter(Mandatory = $true)]
        [string]$Operation,
        
        [bool]$Allowed,
        
        [string]$Reason = ''
    )
    
    $logEntry = [pscustomobject]@{
        timestamp = (Get-Date -Format 'yyyy-MM-ddTHH:mm:ss.fffZ')
        packId = $PackId
        operation = $Operation
        allowed = $Allowed
        reason = $Reason
        user = $env:USERNAME
    }
    
    $logDir = Join-Path $HOME '.llm-workflow/logs'
    if (-not (Test-Path -LiteralPath $logDir)) {
        New-Item -ItemType Directory -Path $logDir -Force | Out-Null
    }
    
    $logPath = Join-Path $logDir 'pack-access.log'
    $logEntry | ConvertTo-Json -Compress | Add-Content -LiteralPath $logPath -Encoding UTF8 -ErrorAction SilentlyContinue
}

#endregion

#region Public Functions

function New-PackVisibilityConfig {
    <#
    .SYNOPSIS
        Creates a new pack visibility configuration.
    .DESCRIPTION
        Generates a visibility configuration object for a pack with
        appropriate defaults based on pack naming conventions.
    .PARAMETER PackId
        The unique identifier for the pack.
    .PARAMETER Visibility
        The visibility level: private, local-team, shared, or public-reference.
    .PARAMETER Exportable
        Whether the pack content can be exported.
    .PARAMETER Federatable
        Whether the pack can be federated to other systems.
    .PARAMETER AllowedAnswerContexts
        Array of allowed answer contexts: local-only, same-project, same-pack, any.
    .PARAMETER CustomRules
        Hashtable of custom visibility rules.
    .PARAMETER ProjectId
        Project ID for project-specific packs.
    .EXAMPLE
        New-PackVisibilityConfig -PackId 'rpgmaker_private_project' -Visibility 'private'
        Creates a private pack visibility configuration.
    .OUTPUTS
        System.Management.Automation.PSCustomObject
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory = $true)]
        [string]$PackId,
        
        [ValidateSet('private', 'local-team', 'shared', 'public-reference')]
        [string]$Visibility = 'shared',
        
        [bool]$Exportable = $true,
        
        [bool]$Federatable = $false,
        
        [string[]]$AllowedAnswerContexts = @('any'),
        
        [hashtable]$CustomRules = @{},
        
        [string]$ProjectId = ''
    )
    
    # Auto-detect visibility from pack name if using defaults
    if ($PSBoundParameters.ContainsKey('Visibility') -eq $false) {
        if ($PackId -match '_private_|-private-') {
            $Visibility = 'private'
            $Exportable = $false
            $Federatable = $false
            $AllowedAnswerContexts = @('local-only')
        }
        elseif ($PackId -match '_team_|-team-') {
            $Visibility = 'local-team'
            $Exportable = $true
            $Federatable = $false
            $AllowedAnswerContexts = @('same-project', 'local-only')
        }
        elseif ($PackId -match '_public_|-public-|reference|core') {
            $Visibility = 'public-reference'
            $Exportable = $true
            $Federatable = $true
            $AllowedAnswerContexts = @('any')
        }
    }
    
    $config = [pscustomobject]@{
        PackId = $PackId
        Visibility = $Visibility
        Exportable = $Exportable
        Federatable = $Federatable
        AllowedAnswerContexts = $AllowedAnswerContexts
        CustomRules = $CustomRules
        ProjectId = $ProjectId
        CreatedUtc = (Get-Date -Format 'yyyy-MM-ddTHH:mm:ssZ')
        Version = 1
    }
    
    return $config
}

function Test-PackAccess {
    <#
    .SYNOPSIS
        Tests if a pack is accessible in the current context.
    .DESCRIPTION
        Evaluates whether a pack can be accessed based on workspace
        context, visibility rules, and operation type.
    .PARAMETER PackId
        The pack identifier to test.
    .PARAMETER WorkspaceContext
        The current workspace context.
    .PARAMETER Operation
        The operation being performed: read, write, export, federate.
    .PARAMETER ProjectContext
        The project context for project-specific access checks.
    .EXAMPLE
        Test-PackAccess -PackId 'rpgmaker_private_project' -WorkspaceContext $workspace -Operation 'read'
        Tests if the pack is accessible for reading.
    .OUTPUTS
        System.Management.Automation.PSCustomObject
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory = $true)]
        [string]$PackId,
        
        [Parameter(Mandatory = $true)]
        [pscustomobject]$WorkspaceContext,
        
        [ValidateSet('read', 'write', 'export', 'federate', 'admin')]
        [string]$Operation = 'read',
        
        [string]$ProjectContext = ''
    )
    
    $result = @{
        Allowed = $false
        Reason = ''
        VisibilityLevel = 'unknown'
        RequiresAudit = $false
        FallbackAllowed = $false
    }
    
    # Check if pack is enabled in workspace
    $enabledPacks = $WorkspaceContext.packsEnabled
    if ($enabledPacks -and ($enabledPacks -notcontains $PackId)) {
        # Check for wildcards
        $packEnabled = $false
        foreach ($enabledPattern in $enabledPacks) {
            if ($PackId -like $enabledPattern) {
                $packEnabled = $true
                break
            }
        }
        
        if (-not $packEnabled) {
            $result.Reason = "Pack '$PackId' is not enabled in workspace '$($WorkspaceContext.workspaceId)'"
            Write-PackAccessLog -PackId $PackId -Operation $Operation -Allowed $false -Reason $result.Reason
            return [pscustomobject]$result
        }
    }
    
    # Get pack visibility settings
    $packVisibility = Get-PackVisibility -PackId $PackId -WorkspaceContext $WorkspaceContext
    $result.VisibilityLevel = $packVisibility.Visibility
    
    # Evaluate based on operation
    switch ($Operation) {
        'read' {
            # Read is generally allowed if pack is enabled
            $result.Allowed = $true
            $result.RequiresAudit = ($packVisibility.Visibility -eq 'private')
        }
        
        'write' {
            # Write depends on workspace type
            if ($packVisibility.Visibility -eq 'private') {
                $result.Allowed = ($WorkspaceContext.type -in @('project', 'personal'))
                $result.Reason = if (-not $result.Allowed) { 'Private packs only writable in project/personal workspaces' } else { '' }
                $result.RequiresAudit = $true
            }
            elseif ($packVisibility.Visibility -eq 'local-team') {
                $result.Allowed = ($WorkspaceContext.type -in @('team', 'project'))
                $result.Reason = if (-not $result.Allowed) { 'Team packs only writable in team/project workspaces' } else { '' }
                $result.RequiresAudit = $true
            }
            else {
                $result.Allowed = $false
                $result.Reason = 'Public/reference packs are read-only'
            }
        }
        
        'export' {
            $exportCheck = Test-VisibilityRule -Operation 'export' -Visibility $packVisibility.Visibility -WorkspaceContext $WorkspaceContext
            $result.Allowed = $exportCheck.Allowed
            $result.Reason = $exportCheck.Reason
            $result.RequiresAudit = $exportCheck.AuditRequired
        }
        
        'federate' {
            $federateCheck = Test-VisibilityRule -Operation 'federate' -Visibility $packVisibility.Visibility -WorkspaceContext $WorkspaceContext
            $result.Allowed = $federateCheck.Allowed
            $result.Reason = $federateCheck.Reason
            $result.RequiresAudit = $federateCheck.AuditRequired
        }
        
        'admin' {
            # Admin operations require explicit workspace ownership
            $result.Allowed = ($WorkspaceContext.type -in @('project', 'team')) -and 
                            ($packVisibility.Visibility -ne 'public-reference')
            $result.Reason = if (-not $result.Allowed) { 'Admin operations restricted' } else { '' }
            $result.RequiresAudit = $true
        }
    }
    
    # Determine if fallback to public packs is allowed
    $result.FallbackAllowed = ($packVisibility.Visibility -eq 'private') -and 
                             ($Operation -eq 'read')
    
    Write-PackAccessLog -PackId $PackId -Operation $Operation -Allowed $result.Allowed -Reason $result.Reason
    
    return [pscustomobject]$result
}

function Get-RetrievalPriority {
    <#
    .SYNOPSIS
        Returns retrieval priority order for packs based on query and workspace.
    .DESCRIPTION
        Implements the private-project precedence rule: private project packs
        are searched first, then falling back to public/domain packs if needed.
    .PARAMETER Query
        The search query (used for relevance scoring).
    .PARAMETER WorkspaceContext
        The current workspace context.
    .PARAMETER Operation
        The operation type (affects visibility filtering).
    .PARAMETER IncludeDisabled
        Include disabled packs in the priority list.
    .PARAMETER MaxPacks
        Maximum number of packs to return.
    .EXAMPLE
        Get-RetrievalPriority -Query 'character movement' -WorkspaceContext $workspace
        Returns ordered list of packs to search.
    .OUTPUTS
        System.Management.Automation.PSCustomObject[]
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject[]])]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Query,
        
        [Parameter(Mandatory = $true)]
        [pscustomobject]$WorkspaceContext,
        
        [ValidateSet('read', 'export', 'federate')]
        [string]$Operation = 'read',
        
        [switch]$IncludeDisabled,
        
        [int]$MaxPacks = 0
    )
    
    $allPacks = $WorkspaceContext.packsEnabled
    if (-not $allPacks -or $allPacks.Count -eq 0) {
        Write-Warning 'No packs enabled in workspace'
        return @()
    }
    
    $scoredPacks = @()
    
    foreach ($packId in $allPacks) {
        # Get pack visibility
        $packVisibility = Get-PackVisibility -PackId $packId -WorkspaceContext $WorkspaceContext
        
        # Skip packs that don't allow this operation
        $accessCheck = Test-PackAccess -PackId $packId -WorkspaceContext $WorkspaceContext -Operation $Operation
        if (-not $accessCheck.Allowed -and -not $accessCheck.FallbackAllowed) {
            continue
        }
        
        # Calculate priority score
        $basePriority = Get-PackTypePriority -PackId $packId
        
        # Boost private project packs (highest priority)
        if ($packVisibility.Visibility -eq 'private') {
            $basePriority += 50
        }
        
        # Boost team packs for team workspaces
        if ($packVisibility.Visibility -eq 'local-team' -and $WorkspaceContext.type -eq 'team') {
            $basePriority += 30
        }
        
        # Simple keyword relevance boost
        $relevance = 0
        $queryWords = $Query.ToLower().Split(' ', [System.StringSplitOptions]::RemoveEmptyEntries)
        $packWords = $packId.ToLower().Replace('_', ' ').Replace('-', ' ').Split(' ')
        
        foreach ($word in $queryWords) {
            if ($packWords -contains $word) {
                $relevance += 10
            }
        }
        
        $scoredPacks += [pscustomobject]@{
            PackId = $packId
            Priority = $basePriority + $relevance
            Visibility = $packVisibility.Visibility
            AccessAllowed = $accessCheck.Allowed
            FallbackAllowed = $accessCheck.FallbackAllowed
            IsPrivate = ($packVisibility.Visibility -eq 'private')
            ScoreBreakdown = @{
                BasePriority = $basePriority
                Relevance = $relevance
                Total = $basePriority + $relevance
            }
        }
    }
    
    # Sort by priority (descending), private packs first
    $sortedPacks = $scoredPacks | Sort-Object -Property @{ 
        Expression = { $_.IsPrivate }; Descending = $true 
    }, @{ 
        Expression = { $_.Priority }; Descending = $true 
    }
    
    # Apply limit if specified
    if ($MaxPacks -gt 0) {
        $sortedPacks = $sortedPacks | Select-Object -First $MaxPacks
    }
    
    Write-Verbose "Retrieval priority for '$Query': $($sortedPacks.Count) packs"
    
    return $sortedPacks
}

function Test-CanAnswerFromPack {
    <#
    .SYNOPSIS
        Tests if an answer can use content from a specific pack.
    .DESCRIPTION
        Validates whether content from a pack can be used in an answer
        based on answer context rules and workspace boundaries.
    .PARAMETER PackId
        The pack containing the potential answer content.
    .PARAMETER WorkspaceContext
        The current workspace context.
    .PARAMETER AnswerContext
        The context where the answer will be used.
    .PARAMETER QueryContext
        The context of the original query.
    .EXAMPLE
        Test-CanAnswerFromPack -PackId 'rpgmaker_private_project' -WorkspaceContext $workspace -AnswerContext 'local-only'
        Tests if answer can use content from private project pack.
    .OUTPUTS
        System.Management.Automation.PSCustomObject
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory = $true)]
        [string]$PackId,
        
        [Parameter(Mandatory = $true)]
        [pscustomobject]$WorkspaceContext,
        
        [string]$AnswerContext = 'any',
        
        [string]$QueryContext = ''
    )
    
    $result = @{
        Allowed = $false
        Reason = ''
        ExplicitFallback = $false
        WarningRequired = $false
    }
    
    # Get pack visibility
    $packVisibility = Get-PackVisibility -PackId $PackId -WorkspaceContext $WorkspaceContext
    
    # Check if answer context is allowed
    $allowedContexts = $packVisibility.AllowedAnswerContexts
    
    if ($AnswerContext -in $allowedContexts -or 'any' -in $allowedContexts) {
        $result.Allowed = $true
    }
    elseif ($AnswerContext -eq 'local-only' -and 'same-project' -in $allowedContexts) {
        # local-only is more restrictive than same-project
        if ($QueryContext -eq $WorkspaceContext.workspaceId) {
            $result.Allowed = $true
        }
        else {
            $result.Reason = "Pack '$PackId' requires local-only context"
        }
    }
    else {
        $result.Reason = "Pack '$PackId' does not allow answers in '$AnswerContext' context. Allowed: $($allowedContexts -join ', ')"
    }
    
    # Special handling for private packs
    if ($packVisibility.Visibility -eq 'private') {
        if ($WorkspaceContext.type -ne 'project') {
            $result.Allowed = $false
            $result.Reason = "Private pack '$PackId' only accessible in project workspaces"
        }
        else {
            # Private project content - mark for explicit fallback label if needed
            $result.ExplicitFallback = $true
            $result.WarningRequired = $true
        }
    }
    
    # Check if using fallback
    if (-not $result.Allowed) {
        # Check if fallback to public packs is allowed
        $accessCheck = Test-PackAccess -PackId $PackId -WorkspaceContext $WorkspaceContext -Operation 'read'
        if ($accessCheck.FallbackAllowed) {
            $result.ExplicitFallback = $true
            $result.Reason += ' (fallback to public packs will be labeled)'
        }
    }
    
    Write-PackAccessLog -PackId $PackId -Operation 'can_answer' -Allowed $result.Allowed -Reason $result.Reason
    
    return [pscustomobject]$result
}

function Get-PackAnswerLabel {
    <#
    .SYNOPSIS
        Generates appropriate attribution label for pack content in answers.
    .DESCRIPTION
        Creates labels indicating the source pack and whether content
        is from private project sources or public fallback.
    .PARAMETER PackId
        The pack being cited.
    .PARAMETER WorkspaceContext
        The current workspace context.
    .PARAMETER IsFallback
        Whether this is fallback content.
    .PARAMETER IncludeVisibility
        Include visibility level in label.
    .EXAMPLE
        Get-PackAnswerLabel -PackId 'rpgmaker_private_project' -WorkspaceContext $workspace
        Returns attribution label for answer.
    .OUTPUTS
        System.String
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory = $true)]
        [string]$PackId,
        
        [Parameter(Mandatory = $true)]
        [pscustomobject]$WorkspaceContext,
        
        [switch]$IsFallback,
        
        [switch]$IncludeVisibility
    )
    
    $packVisibility = Get-PackVisibility -PackId $PackId -WorkspaceContext $WorkspaceContext
    
    $labels = @()
    
    # Add source indicator
    $labels += "[Source: $PackId]"
    
    # Add visibility if requested
    if ($IncludeVisibility) {
        $labels += "[Visibility: $($packVisibility.Visibility)]"
    }
    
    # Add fallback warning
    if ($IsFallback) {
        $labels += '[FALLBACK: Using public/domain packs - private project search was insufficient]'
    }
    
    # Add private content warning
    if ($packVisibility.Visibility -eq 'private') {
        $labels += '[PRIVATE PROJECT CONTENT]'
    }
    
    return ($labels -join ' ')
}

function Select-PacksForQuery {
    <#
    .SYNOPSIS
        Selects appropriate packs for a query with visibility filtering.
    .DESCRIPTION
        Implements the full pack selection algorithm including private-project
        precedence, access validation, and fallback handling.
    .PARAMETER Query
        The user query.
    .PARAMETER WorkspaceContext
        The current workspace context.
    .PARAMETER ProjectContext
        The project context for determining private pack relevance.
    .PARAMETER MaxPacks
        Maximum packs to include in selection.
    .PARAMETER RequirePrivateFirst
        Require private project packs to be searched first.
    .EXAMPLE
        Select-PacksForQuery -Query 'character controller' -WorkspaceContext $workspace
        Returns selected packs with search order and attribution info.
    .OUTPUTS
        System.Management.Automation.PSCustomObject
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Query,
        
        [Parameter(Mandatory = $true)]
        [pscustomobject]$WorkspaceContext,
        
        [string]$ProjectContext = '',
        
        [int]$MaxPacks = 5,
        
        [switch]$RequirePrivateFirst
    )
    
    $result = @{
        Query = $Query
        SelectedPacks = @()
        PrivatePacks = @()
        PublicPacks = @()
        FallbackRequired = $false
        AttributionLabels = @{}
    }
    
    # Get priority-ordered packs
    $priorityPacks = Get-RetrievalPriority -Query $Query -WorkspaceContext $WorkspaceContext -MaxPacks ($MaxPacks * 2)
    
    if ($priorityPacks.Count -eq 0) {
        Write-Warning 'No accessible packs found for query'
        return [pscustomobject]$result
    }
    
    # Separate private and public packs
    $privatePacks = $priorityPacks | Where-Object { $_.IsPrivate -and $_.AccessAllowed }
    $publicPacks = $priorityPacks | Where-Object { -not $_.IsPrivate -and $_.AccessAllowed }
    
    $result.PrivatePacks = @($privatePacks | Select-Object -ExpandProperty PackId)
    $result.PublicPacks = @($publicPacks | Select-Object -ExpandProperty PackId)
    
    # Build selected packs list with precedence rules
    $selected = @()
    
    # 1. Private project packs first (if query is clearly project-related)
    if ($RequirePrivateFirst -or ($ProjectContext -and $result.PrivatePacks.Count -gt 0)) {
        foreach ($pack in $privatePacks | Select-Object -First $MaxPacks) {
            $selected += $pack.PackId
            $result.AttributionLabels[$pack.PackId] = Get-PackAnswerLabel -PackId $pack.PackId -WorkspaceContext $WorkspaceContext
        }
    }
    
    # 2. Fill remaining slots with public packs
    $remainingSlots = $MaxPacks - @($selected).Count
    $publicPackList = @($publicPacks)
    if ($remainingSlots -gt 0 -and $publicPackList.Count -gt 0) {
        foreach ($pack in $publicPacks | Select-Object -First $remainingSlots) {
            if ($selected -notcontains $pack.PackId) {
                $selected += $pack.PackId
                $isFallback = ($result.PrivatePacks.Count -gt 0 -and -not $RequirePrivateFirst)
                $result.AttributionLabels[$pack.PackId] = Get-PackAnswerLabel -PackId $pack.PackId -WorkspaceContext $WorkspaceContext -IsFallback:$isFallback
            }
        }
    }
    
    # 3. If no private packs found but they're expected, mark fallback
    $privatePackList = @($result.PrivatePacks)
    $publicPackList = @($result.PublicPacks)
    if ($RequirePrivateFirst -and $privatePackList.Count -eq 0 -and $publicPackList.Count -gt 0) {
        $result.FallbackRequired = $true
        # Update labels to indicate fallback
        foreach ($packId in $selected) {
            $result.AttributionLabels[$packId] = Get-PackAnswerLabel -PackId $packId -WorkspaceContext $WorkspaceContext -IsFallback
        }
    }
    
    $result.SelectedPacks = $selected
    
    Write-Verbose "Selected $($selected.Count) packs for query: $($selected -join ', ')"
    
    return [pscustomobject]$result
}

#endregion

# Ensure the visibility functions are available
$visibilityPath = Join-Path $PSScriptRoot 'Visibility.ps1'
if (Test-Path -LiteralPath $visibilityPath) {
    . $visibilityPath
}
