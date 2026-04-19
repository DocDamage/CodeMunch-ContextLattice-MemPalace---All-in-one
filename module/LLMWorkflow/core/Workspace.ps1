#requires -Version 5.1
Set-StrictMode -Version Latest

<#
.SYNOPSIS
    Workspace and Visibility Boundary System - Workspace Management
.DESCRIPTION
    Provides workspace context management for the LLM Workflow platform.
    All queries, annotations, pack selections, and exports execute inside
    an explicit workspace context with private/public separation.
.NOTES
    File: Workspace.ps1
    Version: 1.0.0
    Compatible with: PowerShell 5.1+
#>

# Global workspace state (script scope)
$script:CurrentWorkspace = $null
$script:WorkspaceStoragePath = Join-Path $HOME '.llm-workflow/workspaces'

#region Private Helper Functions

function Initialize-WorkspaceStorage {
    <#
    .SYNOPSIS
        Initializes the workspace storage directory structure.
    #>
    [CmdletBinding()]
    param()
    
    if (-not (Test-Path -LiteralPath $script:WorkspaceStoragePath)) {
        New-Item -ItemType Directory -Path $script:WorkspaceStoragePath -Force | Out-Null
        Write-Verbose "Created workspace storage at: $script:WorkspaceStoragePath"
    }
    
    # Create default personal workspace if none exists
    $defaultWorkspacePath = Join-Path $script:WorkspaceStoragePath 'personal-default.json'
    if (-not (Test-Path -LiteralPath $defaultWorkspacePath)) {
        $defaultWorkspace = @{
            schemaVersion = 1
            workspaceId = 'personal-default'
            type = 'personal'
            displayName = 'Personal Default'
            packsEnabled = @()
            visibilityRules = @{}
            createdUtc = (Get-Date -Format 'yyyy-MM-ddTHH:mm:ssZ')
            modifiedUtc = (Get-Date -Format 'yyyy-MM-ddTHH:mm:ssZ')
        }
        $defaultWorkspace | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $defaultWorkspacePath -Encoding UTF8
        Write-Verbose 'Created default personal workspace'
    }
}

function Get-WorkspaceFilePath {
    <#
    .SYNOPSIS
        Gets the file path for a workspace by ID.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory = $true)]
        [string]$WorkspaceId
    )
    
    return Join-Path $script:WorkspaceStoragePath "$WorkspaceId.json"
}

function Test-WorkspaceIdValid {
    <#
    .SYNOPSIS
        Validates workspace ID format.
    #>
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [Parameter(Mandatory = $true)]
        [string]$WorkspaceId
    )
    
    # Workspace IDs: lowercase alphanumeric, hyphens, underscores
    # Must start with letter, 3-50 characters
    if ($WorkspaceId -notmatch '^[a-z][a-z0-9_-]{2,49}$') {
        return $false
    }
    
    # Reserved words check
    $reserved = @('null', 'undefined', 'default', 'system', 'admin', 'root')
    if ($WorkspaceId -in $reserved) {
        return $false
    }
    
    return $true
}

function Write-WorkspaceAccessLog {
    <#
    .SYNOPSIS
        Logs workspace access for audit purposes.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Operation,
        
        [Parameter(Mandatory = $true)]
        [string]$WorkspaceId,
        
        [string]$Details = ''
    )
    
    $logEntry = [pscustomobject]@{
        timestamp = (Get-Date -Format 'yyyy-MM-ddTHH:mm:ss.fffZ')
        operation = $Operation
        workspaceId = $WorkspaceId
        details = $Details
        user = $env:USERNAME
    }
    
    $logPath = Join-Path $script:WorkspaceStoragePath 'access.log'
    $logEntry | ConvertTo-Json -Compress | Add-Content -LiteralPath $logPath -Encoding UTF8 -ErrorAction SilentlyContinue
}

#endregion

#region Public Functions

function Get-CurrentWorkspace {
    <#
    .SYNOPSIS
        Gets or initializes the current workspace context.
    .DESCRIPTION
        Returns the currently active workspace. If no workspace is set,
        initializes and returns the default personal workspace.
    .PARAMETER ForceReload
        Force reload from disk even if workspace is cached in memory.
    .EXAMPLE
        $workspace = Get-CurrentWorkspace
        Gets the current workspace context.
    .OUTPUTS
        System.Management.Automation.PSCustomObject
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [switch]$ForceReload
    )
    
    Initialize-WorkspaceStorage
    
    # Return cached workspace if available and not forcing reload
    if ($script:CurrentWorkspace -and -not $ForceReload) {
        return $script:CurrentWorkspace
    }
    
    # Check for environment variable override
    $envWorkspaceId = [Environment]::GetEnvironmentVariable('LLM_WORKFLOW_CURRENT_WORKSPACE')
    if ($envWorkspaceId) {
        $workspacePath = Get-WorkspaceFilePath -WorkspaceId $envWorkspaceId
        if (Test-Path -LiteralPath $workspacePath) {
            try {
                $workspace = Get-Content -LiteralPath $workspacePath -Raw | ConvertFrom-Json
                $script:CurrentWorkspace = $workspace
                Write-WorkspaceAccessLog -Operation 'get_from_env' -WorkspaceId $envWorkspaceId
                return $workspace
            }
            catch {
                Write-Warning "Failed to load workspace from environment: $envWorkspaceId"
            }
        }
    }
    
    # Load default workspace
    $defaultPath = Get-WorkspaceFilePath -WorkspaceId 'personal-default'
    if (Test-Path -LiteralPath $defaultPath) {
        $workspace = Get-Content -LiteralPath $defaultPath -Raw | ConvertFrom-Json
        $script:CurrentWorkspace = $workspace
        Write-WorkspaceAccessLog -Operation 'get_default' -WorkspaceId 'personal-default'
        return $workspace
    }
    
    throw 'No workspace available. Workspace storage may be corrupted.'
}

function New-Workspace {
    <#
    .SYNOPSIS
        Creates a new workspace.
    .DESCRIPTION
        Creates a new workspace with the specified ID, type, and configuration.
        Automatically switches to the new workspace upon creation.
    .PARAMETER WorkspaceId
        Unique identifier for the workspace (lowercase alphanumeric with hyphens/underscores).
    .PARAMETER Type
        Type of workspace: personal, project, team, or readonly.
    .PARAMETER DisplayName
        Human-readable name for the workspace.
    .PARAMETER PacksEnabled
        Array of pack IDs enabled in this workspace.
    .PARAMETER VisibilityRules
        Hashtable of pack-specific visibility rules.
    .PARAMETER SwitchToWorkspace
        Automatically switch to the new workspace after creation.
    .EXAMPLE
        New-Workspace -WorkspaceId 'project-my-rpg' -Type 'project' -DisplayName 'My RPG Project'
        Creates a new project workspace.
    .OUTPUTS
        System.Management.Automation.PSCustomObject
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory = $true)]
        [string]$WorkspaceId,
        
        [Parameter(Mandatory = $true)]
        [ValidateSet('personal', 'project', 'team', 'readonly')]
        [string]$Type,
        
        [string]$DisplayName = '',
        
        [string[]]$PacksEnabled = @(),
        
        [hashtable]$VisibilityRules = @{},
        
        [switch]$SwitchToWorkspace
    )
    
    Initialize-WorkspaceStorage
    
    # Validate workspace ID
    if (-not (Test-WorkspaceIdValid -WorkspaceId $WorkspaceId)) {
        throw "Invalid workspace ID: '$WorkspaceId'. Must be 3-50 lowercase alphanumeric characters starting with a letter."
    }
    
    # Check for existing workspace
    $workspacePath = Get-WorkspaceFilePath -WorkspaceId $WorkspaceId
    if (Test-Path -LiteralPath $workspacePath) {
        throw "Workspace already exists: $WorkspaceId"
    }
    
    # Create display name if not provided
    if ([string]::IsNullOrWhiteSpace($DisplayName)) {
        $DisplayName = $WorkspaceId -replace '[-_]', ' '
        $DisplayName = (Get-Culture).TextInfo.ToTitleCase($DisplayName)
    }
    
    # Build workspace object
    $workspace = @{
        schemaVersion = 1
        workspaceId = $WorkspaceId
        type = $Type
        displayName = $DisplayName
        packsEnabled = $PacksEnabled
        visibilityRules = $VisibilityRules
        createdUtc = (Get-Date -Format 'yyyy-MM-ddTHH:mm:ssZ')
        modifiedUtc = (Get-Date -Format 'yyyy-MM-ddTHH:mm:ssZ')
    }
    
    # Save workspace
    $workspace | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $workspacePath -Encoding UTF8
    
    Write-WorkspaceAccessLog -Operation 'create' -WorkspaceId $WorkspaceId -Details "Type=$Type"
    
    # Switch to new workspace if requested
    if ($SwitchToWorkspace) {
        Switch-Workspace -WorkspaceId $WorkspaceId | Out-Null
    }
    
    return [pscustomobject]$workspace
}

function Switch-Workspace {
    <#
    .SYNOPSIS
        Changes the active workspace.
    .DESCRIPTION
        Switches to the specified workspace and updates the current context.
        Sets the LLM_WORKFLOW_CURRENT_WORKSPACE environment variable.
    .PARAMETER WorkspaceId
        ID of the workspace to switch to.
    .PARAMETER Persist
        Persist the workspace selection across sessions (sets user environment variable).
    .EXAMPLE
        Switch-Workspace -WorkspaceId 'project-my-rpg'
        Switches to the specified project workspace.
    .OUTPUTS
        System.Management.Automation.PSCustomObject
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory = $true)]
        [string]$WorkspaceId,
        
        [switch]$Persist
    )
    
    Initialize-WorkspaceStorage
    
    # Load workspace
    $workspacePath = Get-WorkspaceFilePath -WorkspaceId $WorkspaceId
    if (-not (Test-Path -LiteralPath $workspacePath)) {
        throw "Workspace not found: $WorkspaceId"
    }
    
    try {
        $workspace = Get-Content -LiteralPath $workspacePath -Raw | ConvertFrom-Json
    }
    catch {
        throw "Failed to load workspace '$WorkspaceId': $_"
    }
    
    # Update in-memory cache
    $script:CurrentWorkspace = $workspace
    
    # Set environment variable for current process
    [Environment]::SetEnvironmentVariable('LLM_WORKFLOW_CURRENT_WORKSPACE', $WorkspaceId, 'Process')
    
    # Persist if requested
    if ($Persist) {
        [Environment]::SetEnvironmentVariable('LLM_WORKFLOW_CURRENT_WORKSPACE', $WorkspaceId, 'User')
    }
    
    # Update modified timestamp
    $workspace.modifiedUtc = (Get-Date -Format 'yyyy-MM-ddTHH:mm:ssZ')
    $workspace | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $workspacePath -Encoding UTF8
    
    Write-WorkspaceAccessLog -Operation 'switch' -WorkspaceId $WorkspaceId -Details "Persist=$Persist"
    
    return $workspace
}

function Get-WorkspacePacks {
    <#
    .SYNOPSIS
        Returns packs enabled in the current or specified workspace.
    .DESCRIPTION
        Retrieves the list of pack IDs that are enabled for the workspace,
        optionally filtered by visibility level.
    .PARAMETER WorkspaceId
        ID of the workspace to query. Uses current workspace if not specified.
    .PARAMETER VisibilityFilter
        Filter packs by visibility level.
    .EXAMPLE
        Get-WorkspacePacks
        Returns all packs enabled in the current workspace.
    .EXAMPLE
        Get-WorkspacePacks -VisibilityFilter 'private'
        Returns only private packs in the current workspace.
    .OUTPUTS
        System.String[]
    #>
    [CmdletBinding()]
    [OutputType([string[]])]
    param(
        [string]$WorkspaceId = '',
        
        [ValidateSet('private', 'local-team', 'shared', 'public-reference', '')]
        [string]$VisibilityFilter = ''
    )
    
    # Get workspace
    if ([string]::IsNullOrWhiteSpace($WorkspaceId)) {
        $workspace = Get-CurrentWorkspace
    }
    else {
        $workspacePath = Get-WorkspaceFilePath -WorkspaceId $WorkspaceId
        if (-not (Test-Path -LiteralPath $workspacePath)) {
            throw "Workspace not found: $WorkspaceId"
        }
        $workspace = Get-Content -LiteralPath $workspacePath -Raw | ConvertFrom-Json
    }
    
    $packs = $workspace.packsEnabled
    
    # Apply visibility filter if specified
    if ($VisibilityFilter -and $workspace.visibilityRules) {
        $filteredPacks = @()
        foreach ($pack in $packs) {
            $packVisibility = 'shared'  # default
            if ($workspace.visibilityRules -and $workspace.visibilityRules.$pack) {
                $packVisibility = $workspace.visibilityRules.$pack
            }
            if ($packVisibility -eq $VisibilityFilter) {
                $filteredPacks += $pack
            }
        }
        $packs = $filteredPacks
    }
    
    Write-Verbose "Retrieved $($packs.Count) packs for workspace $($workspace.workspaceId)"
    return $packs
}

function Test-WorkspaceContext {
    <#
    .SYNOPSIS
        Validates workspace context is properly configured.
    .DESCRIPTION
        Performs validation checks on the current or specified workspace
        to ensure it meets requirements for operations.
    .PARAMETER WorkspaceId
        ID of the workspace to validate. Uses current workspace if not specified.
    .PARAMETER RequiredPacks
        Array of pack IDs that must be enabled in the workspace.
    .PARAMETER RequireProjectType
        Require workspace to be a project-type workspace.
    .EXAMPLE
        Test-WorkspaceContext
        Validates the current workspace context.
    .EXAMPLE
        Test-WorkspaceContext -RequiredPacks @('rpgmaker_core_api')
        Validates workspace has required pack enabled.
    .OUTPUTS
        System.Management.Automation.PSCustomObject
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [string]$WorkspaceId = '',
        
        [string[]]$RequiredPacks = @(),
        
        [switch]$RequireProjectType
    )
    
    $result = @{
        Valid = $true
        WorkspaceId = ''
        Errors = @()
        Warnings = @()
        Checks = @{}
    }
    
    # Get workspace
    try {
        if ([string]::IsNullOrWhiteSpace($WorkspaceId)) {
            $workspace = Get-CurrentWorkspace
        }
        else {
            $workspacePath = Get-WorkspaceFilePath -WorkspaceId $WorkspaceId
            if (-not (Test-Path -LiteralPath $workspacePath)) {
                throw "Workspace not found: $WorkspaceId"
            }
            $workspace = Get-Content -LiteralPath $workspacePath -Raw | ConvertFrom-Json
        }
        $result.WorkspaceId = $workspace.workspaceId
    }
    catch {
        $result.Valid = $false
        $result.Errors += "Failed to load workspace: $_"
        return [pscustomobject]$result
    }
    
    # Validate schema version
    if ($workspace.schemaVersion -ne 1) {
        $result.Warnings += "Unexpected schema version: $($workspace.schemaVersion)"
    }
    $result.Checks['SchemaVersion'] = $true
    
    # Validate required fields
    $requiredFields = @('workspaceId', 'type', 'packsEnabled')
    foreach ($field in $requiredFields) {
        if (-not $workspace.$field) {
            $result.Valid = $false
            $result.Errors += "Missing required field: $field"
            $result.Checks[$field] = $false
        }
        else {
            $result.Checks[$field] = $true
        }
    }
    
    # Validate type
    $validTypes = @('personal', 'project', 'team', 'readonly')
    if ($workspace.type -notin $validTypes) {
        $result.Valid = $false
        $result.Errors += "Invalid workspace type: $($workspace.type)"
        $result.Checks['ValidType'] = $false
    }
    else {
        $result.Checks['ValidType'] = $true
    }
    
    # Check project type requirement
    if ($RequireProjectType -and $workspace.type -ne 'project') {
        $result.Valid = $false
        $result.Errors += "Workspace must be type 'project', found: $($workspace.type)"
        $result.Checks['ProjectType'] = $false
    }
    else {
        $result.Checks['ProjectType'] = $true
    }
    
    # Check required packs
    $enabledPacks = $workspace.packsEnabled
    foreach ($requiredPack in $RequiredPacks) {
        if ($enabledPacks -contains $requiredPack) {
            $result.Checks["Pack_$requiredPack"] = $true
        }
        else {
            $result.Valid = $false
            $result.Errors += "Required pack not enabled: $requiredPack"
            $result.Checks["Pack_$requiredPack"] = $false
        }
    }
    
    Write-Verbose "Workspace validation: $($result.Valid) for $($result.WorkspaceId)"
    return [pscustomobject]$result
}

function Get-WorkspaceList {
    <#
    .SYNOPSIS
        Lists all available workspaces.
    .DESCRIPTION
        Returns a list of all workspaces in the storage directory.
    .PARAMETER IncludeDetails
        Include full workspace details in output.
    .EXAMPLE
        Get-WorkspaceList
        Returns list of workspace IDs and names.
    .OUTPUTS
        System.Management.Automation.PSCustomObject[]
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject[]])]
    param(
        [switch]$IncludeDetails
    )
    
    Initialize-WorkspaceStorage
    
    $workspaceFiles = Get-ChildItem -Path $script:WorkspaceStoragePath -Filter '*.json' -ErrorAction SilentlyContinue |
        Where-Object { $_.Name -ne 'access.log' }
    
    $workspaces = @()
    foreach ($file in $workspaceFiles) {
        try {
            $workspace = Get-Content -LiteralPath $file.FullName -Raw | ConvertFrom-Json
            if ($IncludeDetails) {
                $workspaces += $workspace
            }
            else {
                $workspaces += [pscustomobject]@{
                    WorkspaceId = $workspace.workspaceId
                    Type = $workspace.type
                    DisplayName = $workspace.displayName
                    CreatedUtc = $workspace.createdUtc
                    ModifiedUtc = $workspace.modifiedUtc
                }
            }
        }
        catch {
            Write-Warning "Failed to load workspace from $($file.Name): $_"
        }
    }
    
    return $workspaces
}

function Remove-Workspace {
    <#
    .SYNOPSIS
        Removes a workspace.
    .DESCRIPTION
        Deletes a workspace configuration. Cannot delete the default personal workspace.
    .PARAMETER WorkspaceId
        ID of the workspace to remove.
    .PARAMETER Force
        Force removal without confirmation.
    .EXAMPLE
        Remove-Workspace -WorkspaceId 'old-project'
        Removes the specified workspace.
    #>
    [CmdletBinding(SupportsShouldProcess = $true)]
    param(
        [Parameter(Mandatory = $true)]
        [string]$WorkspaceId,
        
        [switch]$Force
    )
    
    # Protect default workspace
    if ($WorkspaceId -eq 'personal-default') {
        throw "Cannot remove the default personal workspace."
    }
    
    $workspacePath = Get-WorkspaceFilePath -WorkspaceId $WorkspaceId
    if (-not (Test-Path -LiteralPath $workspacePath)) {
        throw "Workspace not found: $WorkspaceId"
    }
    
    if ($Force -or $PSCmdlet.ShouldProcess($WorkspaceId, 'Remove workspace')) {
        Remove-Item -LiteralPath $workspacePath -Force
        Write-WorkspaceAccessLog -Operation 'remove' -WorkspaceId $WorkspaceId
        
        # Clear current workspace if it was the removed one
        if ($script:CurrentWorkspace -and $script:CurrentWorkspace.workspaceId -eq $WorkspaceId) {
            $script:CurrentWorkspace = $null
            [Environment]::SetEnvironmentVariable('LLM_WORKFLOW_CURRENT_WORKSPACE', $null, 'Process')
        }
        
        Write-Verbose "Removed workspace: $WorkspaceId"
    }
}

#endregion

# Initialize storage on module load
Initialize-WorkspaceStorage
