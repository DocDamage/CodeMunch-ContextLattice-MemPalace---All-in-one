<#
.SYNOPSIS
    Pack Manifest management for LLM Workflow platform.

.DESCRIPTION
    Functions for creating, validating, and managing domain pack manifests.
    Implements Section 8 of the canonical architecture.

.NOTES
    Author: LLM Workflow Platform
    Version: 0.4.0
    Date: 2026-04-12
#>

# Valid pack lifecycle states per Section 8.3
$script:ValidLifecycleStates = @(
    'draft',
    'building',
    'staged',
    'validated',
    'promoted',
    'deprecated',
    'retired',
    'removed'
)

# Valid pack channels per Section 8.4
$script:ValidChannels = @(
    'draft',
    'candidate',
    'stable',
    'frozen'
)

# Valid install profiles per Section 8.5
$script:ValidInstallProfiles = @(
    'minimal',
    'core-only',
    'developer',
    'full',
    'private-first'
)

# Valid trust tiers per Section 9.2
$script:ValidTrustTiers = @(
    'High',
    'Medium-High',
    'Medium',
    'Low',
    'Quarantined'
)

if (-not (Get-Command ConvertTo-LLMHashtable -ErrorAction SilentlyContinue)) {
    function ConvertTo-LLMHashtable {
        [CmdletBinding()]
        param([Parameter(ValueFromPipeline = $true)]$InputObject)

        process {
            if ($null -eq $InputObject) { return $null }

            if ($InputObject -is [System.Collections.IDictionary]) {
                $hash = @{}
                foreach ($key in $InputObject.Keys) {
                    $hash[$key] = ConvertTo-LLMHashtable -InputObject $InputObject[$key]
                }
                return $hash
            }

            if ($InputObject -is [PSCustomObject] -or $InputObject -is [System.Management.Automation.PSCustomObject]) {
                $hash = @{}
                foreach ($prop in $InputObject.PSObject.Properties) {
                    $hash[$prop.Name] = ConvertTo-LLMHashtable -InputObject $prop.Value
                }
                return $hash
            }

            if ($InputObject -is [System.Collections.IEnumerable] -and $InputObject -isnot [string]) {
                $result = @()
                foreach ($item in $InputObject) {
                    $result += ,(ConvertTo-LLMHashtable -InputObject $item)
                }
                return $result
            }

            return $InputObject
        }
    }
}

if (-not (Get-Command ConvertFrom-LLMJsonToHashtable -ErrorAction SilentlyContinue)) {
    function ConvertFrom-LLMJsonToHashtable {
        [CmdletBinding()]
        param([Parameter(Mandatory)][string]$Json)

        $convertFromJson = Get-Command ConvertFrom-Json -ErrorAction Stop
        if ($convertFromJson.Parameters.ContainsKey('AsHashtable')) {
            return ($Json | ConvertFrom-Json -AsHashtable)
        }

        return ConvertTo-LLMHashtable -InputObject ($Json | ConvertFrom-Json)
    }
}

<#
.SYNOPSIS
    Creates a new pack manifest.

.DESCRIPTION
    Creates a pack manifest according to Section 8.2 of the canonical architecture.

.PARAMETER PackId
    Unique identifier for the pack (e.g., 'rpgmaker-mz', 'godot-engine').

.PARAMETER Domain
    Domain category (e.g., 'game-dev', '3d-graphics').

.PARAMETER Version
    Semantic version of the pack.

.PARAMETER TaxonomyVersion
    Version of the taxonomy used.

.PARAMETER DefaultCollections
    Array of default collection IDs.

.PARAMETER Status
    Lifecycle status (draft, building, staged, validated, promoted, deprecated, retired, removed).

.PARAMETER Channel
    Distribution channel (draft, candidate, stable, frozen).

.PARAMETER InstallProfiles
    Hashtable of install profiles with their member sources.

.EXAMPLE
    $manifest = New-PackManifest -PackId "rpgmaker-mz" -Domain "game-dev" -Version "1.0.0-draft"
#>
function New-PackManifest {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidatePattern('^[a-z0-9-]+$')]
        [string]$PackId,

        [Parameter(Mandatory)]
        [string]$Domain,

        [Parameter(Mandatory)]
        [ValidatePattern('^\d+\.\d+\.\d+(-\w+)?$')]
        [string]$Version,

        [Parameter()]
        [string]$TaxonomyVersion = "1",

        [Parameter()]
        [string[]]$DefaultCollections = @(),

        [Parameter()]
        [ValidateSet('draft', 'building', 'staged', 'validated', 'promoted', 'deprecated', 'retired', 'removed')]
        [string]$Status = 'draft',

        [Parameter()]
        [ValidateSet('draft', 'candidate', 'stable', 'frozen')]
        [string]$Channel = 'draft',

        [Parameter()]
        [hashtable]$InstallProfiles = @{},

        [Parameter()]
        [hashtable]$Owners = @{},

        [Parameter()]
        [string]$RunId
    )

    begin {
        if (-not $RunId) {
            $RunId = & "$PSScriptRoot/../core/RunId.ps1" -Command New-RunId
        }
    }

    process {
        $manifest = @{
            schemaVersion = 1
            packId = $PackId
            domain = $Domain
            version = $Version
            taxonomyVersion = $TaxonomyVersion
            status = $Status
            channel = $Channel
            defaultCollections = $DefaultCollections
            installProfiles = $InstallProfiles
            owners = $Owners
            createdUtc = [DateTime]::UtcNow.ToString("o")
            updatedUtc = [DateTime]::UtcNow.ToString("o")
            createdByRunId = $RunId
        }

        return $manifest
    }
}

<#
.SYNOPSIS
    Validates a pack manifest against the canonical schema.

.DESCRIPTION
    Validates that a manifest contains all required fields and valid values
    per Section 8 of the canonical architecture.

.PARAMETER Manifest
    The manifest hashtable to validate.

.EXAMPLE
    $result = Test-PackManifest -Manifest $manifest
#>
function Test-PackManifest {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [hashtable]$Manifest
    )

    process {
        $errors = @()

        # Check required fields
        $requiredFields = @('packId', 'domain', 'version', 'status', 'channel')
        foreach ($field in $requiredFields) {
            if (-not $Manifest.ContainsKey($field) -or -not $Manifest[$field]) {
                $errors += "Missing required field: $field"
            }
        }

        # Validate packId format
        if ($Manifest.ContainsKey('packId') -and $Manifest.packId -notmatch '^[a-z0-9-]+$') {
            $errors += "Invalid packId format: must be lowercase alphanumeric with hyphens only"
        }

        # Validate version format (semver)
        if ($Manifest.ContainsKey('version') -and $Manifest.version -notmatch '^\d+\.\d+\.\d+(-\w+)?$') {
            $errors += "Invalid version format: must follow semantic versioning"
        }

        # Validate lifecycle state
        if ($Manifest.ContainsKey('status') -and $Manifest.status -notin $script:ValidLifecycleStates) {
            $errors += "Invalid status: must be one of $($script:ValidLifecycleStates -join ', ')"
        }

        # Validate channel
        if ($Manifest.ContainsKey('channel') -and $Manifest.channel -notin $script:ValidChannels) {
            $errors += "Invalid channel: must be one of $($script:ValidChannels -join ', ')"
        }

        # Validate install profiles
        if ($Manifest.ContainsKey('installProfiles') -and $Manifest.installProfiles) {
            foreach ($profileName in $Manifest.installProfiles.Keys) {
                if ($profileName -notin $script:ValidInstallProfiles) {
                    $errors += "Invalid install profile name: $profileName"
                }
            }
        }

        return @{
            isValid = $errors.Count -eq 0
            errors = $errors
        }
    }
}

<#
.SYNOPSIS
    Saves a pack manifest to disk.

.DESCRIPTION
    Saves the manifest as JSON with atomic write and schema header.

.PARAMETER Manifest
    The manifest to save.

.PARAMETER Path
    The path to save to (defaults to packs/manifests/{packId}.json).

.PARAMETER Atomic
    Whether to use atomic write (default: true).
#>
function Save-PackManifest {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [hashtable]$Manifest,

        [Parameter()]
        [string]$Path,

        [Parameter()]
        [bool]$Atomic = $true
    )

    process {
        if (-not $Path) {
            $Path = "packs/manifests/$($Manifest.packId).json"
        }

        # Ensure directory exists
        $dir = Split-Path -Parent $Path
        if (-not (Test-Path $dir)) {
            New-Item -ItemType Directory -Path $dir -Force | Out-Null
        }

        # Update timestamps
        $Manifest.updatedUtc = [DateTime]::UtcNow.ToString("o")

        if ($Atomic) {
            # Use atomic write if available
            $json = $Manifest | ConvertTo-Json -Depth 10
            $tempPath = "$Path.tmp"
            $json | Out-File -FilePath $tempPath -Encoding UTF8 -NoNewline
            Move-Item -Path $tempPath -Destination $Path -Force
        }
        else {
            $Manifest | ConvertTo-Json -Depth 10 | Out-File -FilePath $Path -Encoding UTF8
        }

        Write-Verbose "Pack manifest saved to $Path"
        return $Path
    }
}

<#
.SYNOPSIS
    Loads a pack manifest from disk.

.DESCRIPTION
    Loads and validates a pack manifest.

.PARAMETER PackId
    The pack ID to load.

.PARAMETER Path
    Direct path to the manifest file.
#>
function Get-PackManifest {
    [CmdletBinding()]
    param(
        [Parameter()]
        [string]$PackId,

        [Parameter()]
        [string]$Path
    )

    process {
        if (-not $Path -and $PackId) {
            $Path = "packs/manifests/$PackId.json"
        }

        if (-not (Test-Path $Path)) {
            Write-Warning "Pack manifest not found: $Path"
            return $null
        }

        $content = ConvertFrom-LLMJsonToHashtable -Json (Get-Content $Path -Raw)
        return $content
    }
}

<#
.SYNOPSIS
    Lists all available pack manifests.

.DESCRIPTION
    Returns a list of all pack manifests in the manifests directory.

.PARAMETER Status
    Filter by lifecycle status.

.PARAMETER Domain
    Filter by domain.
#>
function Get-PackManifestList {
    [CmdletBinding()]
    param(
        [Parameter()]
        [string]$Status,

        [Parameter()]
        [string]$Domain
    )

    process {
        $manifestDir = "packs/manifests"
        if (-not (Test-Path $manifestDir)) {
            return @()
        }

        $manifests = Get-ChildItem -Path $manifestDir -Filter "*.json" | ForEach-Object {
            $content = ConvertFrom-LLMJsonToHashtable -Json (Get-Content $_.FullName -Raw)
            [PSCustomObject]@{
                PackId = $content.packId
                Domain = $content.domain
                Version = $content.version
                Status = $content.status
                Channel = $content.channel
                Path = $_.FullName
            }
        }

        if ($Status) {
            $manifests = $manifests | Where-Object { $_.Status -eq $Status }
        }

        if ($Domain) {
            $manifests = $manifests | Where-Object { $_.Domain -eq $Domain }
        }

        return $manifests
    }
}

<#
.SYNOPSIS
    Transitions a pack to a new lifecycle state.

.DESCRIPTION
    Manages pack lifecycle transitions per Section 8.3.
    Only validated builds can be promoted.

.PARAMETER Manifest
    The pack manifest.

.PARAMETER NewStatus
    The target lifecycle state.

.PARAMETER Reason
    Reason for the transition.
#>
function Set-PackLifecycleState {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [hashtable]$Manifest,

        [Parameter(Mandatory)]
        [ValidateSet('draft', 'building', 'staged', 'validated', 'promoted', 'deprecated', 'retired', 'removed')]
        [string]$NewStatus,

        [Parameter()]
        [string]$Reason
    )

    process {
        $currentStatus = $Manifest.status

        # Validate transition rules
        $invalidTransitions = @{
            'draft' = @('promoted')
            'building' = @('promoted')
            'staged' = @('promoted')
            'validated' = @()
            'promoted' = @('building', 'staged')
            'deprecated' = @('building', 'staged', 'promoted')
            'retired' = @('building', 'staged', 'promoted')
            'removed' = @('building', 'staged', 'validated', 'promoted')
        }

        if ($invalidTransitions[$currentStatus] -contains $NewStatus) {
            Write-Warning "Invalid transition from '$currentStatus' to '$NewStatus'"
            return $null
        }

        # Rule: only validated builds can be promoted
        if ($NewStatus -eq 'promoted' -and $currentStatus -ne 'validated') {
            Write-Warning "Only validated builds can be promoted. Current status: $currentStatus"
            return $null
        }

        $Manifest.status = $NewStatus
        $Manifest.updatedUtc = [DateTime]::UtcNow.ToString("o")

        if (-not $Manifest.lifecycleHistory) {
            $Manifest.lifecycleHistory = @()
        }

        $Manifest.lifecycleHistory += @{
            fromStatus = $currentStatus
            toStatus = $NewStatus
            timestamp = [DateTime]::UtcNow.ToString("o")
            reason = $Reason
        }

        Write-Verbose "Pack $($Manifest.packId) transitioned from $currentStatus to $NewStatus"
        return $Manifest
    }
}

<#
.SYNOPSIS
    Gets the default install profile for a pack.

.DESCRIPTION
    Returns the member sources for a given install profile.

.PARAMETER Manifest
    The pack manifest.

.PARAMETER ProfileName
    The install profile name (minimal, core-only, developer, full, private-first).
#>
function Get-PackInstallProfile {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [hashtable]$Manifest,

        [Parameter(Mandatory)]
        [ValidateSet('minimal', 'core-only', 'developer', 'full', 'private-first')]
        [string]$ProfileName
    )

    process {
        if (-not $Manifest.installProfiles -or -not $Manifest.installProfiles[$ProfileName]) {
            Write-Warning "Install profile '$ProfileName' not found for pack $($Manifest.packId)"
            return @()
        }

        $members = @($Manifest.installProfiles[$ProfileName])
        Write-Output -NoEnumerate $members
    }
}

<#
.SYNOPSIS
    Exports a pack summary for display.

.DESCRIPTION
    Creates a concise summary of the pack for status/health reporting.

.PARAMETER Manifest
    The pack manifest.
#>
function Export-PackSummary {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [hashtable]$Manifest
    )

    process {
        $sourceCount = 0
        if ($Manifest.sourceRegistry) {
            $sourceCount = $Manifest.sourceRegistry.Count
        }

        return [PSCustomObject]@{
            PackId = $Manifest.packId
            Domain = $Manifest.domain
            Version = $Manifest.version
            Status = $Manifest.status
            Channel = $Manifest.channel
            SourceCount = $sourceCount
            Collections = $Manifest.defaultCollections -join ', '
            Updated = $Manifest.updatedUtc
        }
    }
}

# Export-ModuleMember handled by LLMWorkflow.psm1
