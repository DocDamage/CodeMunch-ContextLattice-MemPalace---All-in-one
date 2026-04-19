<#
.SYNOPSIS
    Source Registry management for LLM Workflow platform.

.DESCRIPTION
    Functions for managing source registries per Section 9 of the canonical architecture.
    Handles source registration, trust tiers, family tracking, and retirement.

.NOTES
    Author: LLM Workflow Platform
    Version: 0.4.0
    Date: 2026-04-12
#>

# Valid trust tiers per Section 9.2
$script:ValidTrustTiers = @(
    'High',
    'Medium-High',
    'Medium',
    'Low',
    'Quarantined'
)

# Valid authority roles per pack specifications
$script:ValidAuthorityRoles = @(
    # RPG Maker MZ roles (Section 22.4.1)
    'core-runtime',
    'private-project',
    'exemplar-pattern',
    'tooling-analyzer',
    'reverse-format',
    'llm-workflow',
    'multilingual-summary-source',
    'bundled-collection',
    # Godot Engine roles (Section 25.4.1)
    'core-engine',
    'language-binding',
    'mcp-integration',
    'visual-system',
    'physics-extension',
    'deployment-tooling',
    'starter-template',
    'curated-index',
    # Blender Engine roles (Section 26.4)
    'core-blender',
    'ai-agent-control',
    'synth-proc',
    'gis-context',
    'pipeline-tool',
    'format-converter',
    # Cross-domain roles
    'educational-reference',
    'math-reference',
    'notebook-tooling',
    'reverse-api-tooling',
    'voice-generation',
    'agent-simulation',
    'engine-reference',
    'frontend-framework',
    'ui-component-library',
    'creative-generation',
    'legacy-web-framework'
)

# Valid source states
$script:ValidSourceStates = @(
    'active',
    'deprecated',
    'retired',
    'quarantined',
    'removed'
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
    Creates a new source registry entry.

.DESCRIPTION
    Creates a source registry entry per Section 9.1 of the canonical architecture.

.PARAMETER SourceId
    Unique identifier for the source.

.PARAMETER RepoUrl
    Repository URL.

.PARAMETER SelectedRef
    Git reference (branch, tag, or commit hash).

.PARAMETER ParseMode
    Parser mode for extraction.

.PARAMETER TrustTier
    Trust tier (High, Medium-High, Medium, Low, Quarantined).

.PARAMETER AuthorityRole
    Authority role for retrieval routing.

.PARAMETER EngineTarget
    Target engine/version metadata.

.PARAMETER PackId
    Parent pack ID.

.PARAMETER Priority
    Priority tier (P0, P1, P2, P3, P4, P5).
#>
function New-SourceRegistryEntry {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$SourceId,

        [Parameter(Mandatory)]
        [ValidatePattern('^https?://')]
        [string]$RepoUrl,

        [Parameter()]
        [string]$SelectedRef = 'main',

        [Parameter()]
        [string]$ParseMode = 'default',

        [Parameter()]
        [ValidateSet('High', 'Medium-High', 'Medium', 'Low', 'Quarantined')]
        [string]$TrustTier = 'Medium',

        [Parameter()]
        [string]$AuthorityRole = 'exemplar-pattern',

        [Parameter()]
        [string]$EngineTarget,

        [Parameter()]
        [string]$EngineMinVersion,

        [Parameter()]
        [string]$EngineMaxVersion,

        [Parameter()]
        [string]$PackId,

        [Parameter()]
        [ValidateSet('P0', 'P1', 'P2', 'P3', 'P4', 'P5')]
        [string]$Priority = 'P2',

        [Parameter()]
        [ValidateSet('active', 'deprecated', 'retired', 'quarantined', 'removed')]
        [string]$State = 'active',

        [Parameter()]
        [string]$License,

        [Parameter()]
        [string]$OverlapScore,

        [Parameter()]
        [string]$RefreshCadence = '30-day',

        [Parameter()]
        [string[]]$Collections = @(),

        [Parameter()]
        [hashtable]$RiskNotes = @{},

        [Parameter()]
        [string]$RunId
    )

    begin {
        if (-not $RunId) {
            $RunId = & "$PSScriptRoot/../core/RunId.ps1" -Command New-RunId
        }
    }

    process {
        $entry = @{
            schemaVersion = 1
            sourceId = $SourceId
            repoUrl = $RepoUrl
            selectedRef = $SelectedRef
            parseMode = $ParseMode
            trustTier = $TrustTier
            authorityRole = $AuthorityRole
            priority = $Priority
            packId = $PackId
            license = $License
            overlapScore = $OverlapScore
            parserSuccessRate = $null
            refreshCadence = $RefreshCadence
            lastReviewedUtc = [DateTime]::UtcNow.ToString("o")
            state = $State
            collections = $Collections
            riskNotes = $RiskNotes
            contributionNotes = @()
            createdUtc = [DateTime]::UtcNow.ToString("o")
            updatedUtc = [DateTime]::UtcNow.ToString("o")
            createdByRunId = $RunId
        }

        if ($EngineTarget) { $entry.engineTarget = $EngineTarget }
        if ($EngineMinVersion) { $entry.engineMinVersion = $EngineMinVersion }
        if ($EngineMaxVersion) { $entry.engineMaxVersion = $EngineMaxVersion }

        return $entry
    }
}

<#
.SYNOPSIS
    Creates a source family registry entry for tracking forks/mirrors.

.DESCRIPTION
    Tracks source family relationships per Section 9.3.

.PARAMETER FamilyId
    Unique family identifier.

.PARAMETER CanonicalSource
    The canonical/original source.

.PARAMETER FamilyType
    Type of relationship (fork, mirror, rename, author-family, duplicate, wrapper).

.PARAMETER Members
    Array of related source IDs.
#>
function New-SourceFamilyEntry {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$FamilyId,

        [Parameter(Mandatory)]
        [string]$CanonicalSource,

        [Parameter()]
        [ValidateSet('fork', 'mirror', 'rename', 'author-family', 'duplicate', 'wrapper')]
        [string]$FamilyType = 'fork',

        [Parameter()]
        [string[]]$Members = @(),

        [Parameter()]
        [string]$Notes
    )

    process {
        $memberList = if ($Members -and $Members.Count -gt 0) {
            @($Members)
        }
        else {
            @($CanonicalSource)
        }

        return @{
            schemaVersion = 1
            familyId = $FamilyId
            canonicalSource = $CanonicalSource
            familyType = $FamilyType
            members = $memberList
            notes = $Notes
            createdUtc = [DateTime]::UtcNow.ToString("o")
            updatedUtc = [DateTime]::UtcNow.ToString("o")
        }
    }
}

<#
.SYNOPSIS
    Validates a source registry entry.

.DESCRIPTION
    Validates source entry fields and constraints.

.PARAMETER Entry
    The source entry to validate.
#>
function Test-SourceRegistryEntry {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [hashtable]$Entry
    )

    process {
        $errors = @()

        # Check required fields
        if (-not $Entry.sourceId) { $errors += "Missing required field: sourceId" }
        if (-not $Entry.repoUrl) { $errors += "Missing required field: repoUrl" }

        # Validate URL format
        if ($Entry.repoUrl -and $Entry.repoUrl -notmatch '^https?://') {
            $errors += "Invalid repoUrl: must be HTTP(S) URL"
        }

        # Validate trust tier
        if ($Entry.trustTier -and $Entry.trustTier -notin $script:ValidTrustTiers) {
            $errors += "Invalid trustTier: must be one of $($script:ValidTrustTiers -join ', ')"
        }

        # Validate state
        if ($Entry.state -and $Entry.state -notin $script:ValidSourceStates) {
            $errors += "Invalid state: must be one of $($script:ValidSourceStates -join ', ')"
        }

        return @{
            isValid = $errors.Count -eq 0
            errors = $errors
        }
    }
}

<#
.SYNOPSIS
    Saves a source registry to disk.

.DESCRIPTION
    Saves the source registry as JSON.

.PARAMETER PackId
    The pack ID.

.PARAMETER Sources
    Hashtable of source entries keyed by source ID.

.PARAMETER Path
    Optional direct path.
#>
function Save-SourceRegistry {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$PackId,

        [Parameter(Mandatory)]
        [hashtable]$Sources,

        [Parameter()]
        [string]$Path
    )

    process {
        if (-not $Path) {
            $Path = "packs/registries/$PackId.sources.json"
        }

        # Ensure directory exists
        $dir = Split-Path -Parent $Path
        if (-not (Test-Path $dir)) {
            New-Item -ItemType Directory -Path $dir -Force | Out-Null
        }

        $registry = @{
            schemaVersion = 1
            packId = $PackId
            sources = $Sources
            updatedUtc = [DateTime]::UtcNow.ToString("o")
        }

        $registry | ConvertTo-Json -Depth 10 | Out-File -FilePath $Path -Encoding UTF8
        Write-Verbose "Source registry saved to $Path"
        return $Path
    }
}

<#
.SYNOPSIS
    Loads a source registry from disk.

.DESCRIPTION
    Loads the source registry for a pack.

.PARAMETER PackId
    The pack ID.

.PARAMETER Path
    Optional direct path.
#>
function Get-SourceRegistry {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$PackId,

        [Parameter()]
        [string]$Path
    )

    process {
        if (-not $Path) {
            $Path = "packs/registries/$PackId.sources.json"
        }

        if (-not (Test-Path $Path)) {
            return @{
                schemaVersion = 1
                packId = $PackId
                sources = @{}
                updatedUtc = [DateTime]::UtcNow.ToString("o")
            }
        }

        $content = ConvertFrom-LLMJsonToHashtable -Json (Get-Content $Path -Raw)
        return $content
    }
}

<#
.SYNOPSIS
    Transitions a source to a new state.

.DESCRIPTION
    Handles source retirement, deprecation, and quarantine per Section 9.4.

.PARAMETER Entry
    The source entry.

.PARAMETER NewState
    Target state (active, deprecated, retired, quarantined, removed).

.PARAMETER Reason
    Reason for the transition.
#>
function Set-SourceState {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [hashtable]$Entry,

        [Parameter(Mandatory)]
        [ValidateSet('active', 'deprecated', 'retired', 'quarantined', 'removed')]
        [string]$NewState,

        [Parameter()]
        [string]$Reason
    )

    process {
        $oldState = $Entry.state
        $Entry.state = $NewState
        $Entry.updatedUtc = [DateTime]::UtcNow.ToString("o")

        if (-not $Entry.stateHistory) {
            $Entry.stateHistory = @()
        }

        $Entry.stateHistory += @{
            fromState = $oldState
            toState = $NewState
            timestamp = [DateTime]::UtcNow.ToString("o")
            reason = $Reason
        }

        Write-Verbose "Source $($Entry.sourceId) transitioned from $oldState to $NewState"
        return $Entry
    }
}

<#
.SYNOPSIS
    Quarantines a source for safety concerns.

.DESCRIPTION
    Quarantines a source per Section 9.5 for issues like:
    - Malformed parser input
    - Suspicious binary content
    - Weak provenance
    - Severe extraction failure
    - Boundary-policy violation

.PARAMETER Entry
    The source entry.

.PARAMETER Reason
    Quarantine reason.

.PARAMETER ReviewDate
    Optional review date.
#>
function Suspend-SourceQuarantine {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [hashtable]$Entry,

        [Parameter(Mandatory)]
        [string]$Reason,

        [Parameter()]
        [string]$ReviewDate
    )

    process {
        $Entry = Set-SourceState -Entry $Entry -NewState 'quarantined' -Reason $Reason
        $Entry.quarantineReason = $Reason
        $Entry.quarantineDate = [DateTime]::UtcNow.ToString("o")
        if ($ReviewDate) {
            $Entry.quarantineReviewDate = $ReviewDate
        }
        return $Entry
    }
}

<#
.SYNOPSIS
    Gets sources by priority tier.

.DESCRIPTION
    Returns sources filtered by priority (P0-P5).

.PARAMETER Registry
    The source registry.

.PARAMETER Priority
    Priority tier(s) to filter by.
#>
function Get-SourceByPriority {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [hashtable]$Registry,

        [Parameter(Mandatory)]
        [ValidateSet('P0', 'P1', 'P2', 'P3', 'P4', 'P5')]
        [string[]]$Priority
    )

    process {
        $sources = $Registry.sources
        if (-not $sources) { return @() }

        $result = $sources.GetEnumerator() | Where-Object {
            $_.Value.priority -in $Priority -and $_.Value.state -eq 'active'
        } | ForEach-Object {
            [PSCustomObject]$_.Value
        }

        $sorted = @($result | Sort-Object priority)
        Write-Output -NoEnumerate $sorted
    }
}

<#
.SYNOPSIS
    Gets sources by authority role.

.DESCRIPTION
    Returns sources filtered by authority role for retrieval routing.

.PARAMETER Registry
    The source registry.

.PARAMETER AuthorityRole
    Authority role to filter by.
#>
function Get-SourceByAuthorityRole {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [hashtable]$Registry,

        [Parameter(Mandatory)]
        [string]$AuthorityRole
    )

    process {
        $sources = $Registry.sources
        if (-not $sources) { return @() }

        $result = $sources.GetEnumerator() | Where-Object {
            $_.Value.authorityRole -eq $AuthorityRole -and $_.Value.state -eq 'active'
        } | ForEach-Object {
            [PSCustomObject]$_.Value
        }

        $items = @($result)
        Write-Output -NoEnumerate $items
    }
}

<#
.SYNOPSIS
    Gets the effective priority for retrieval routing.

.DESCRIPTION
    Returns sources ordered by effective priority considering:
    - Priority tier (P0 highest)
    - Trust tier
    - Active state only

.PARAMETER Registry
    The source registry.

.PARAMETER Collection
    Optional collection filter.
#>
function Get-RetrievalPrioritySources {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [hashtable]$Registry,

        [Parameter()]
        [string]$Collection
    )

    process {
        $sources = $Registry.sources
        if (-not $sources) { return @() }

        $active = $sources.GetEnumerator() | Where-Object {
            $_.Value.state -eq 'active'
        }

        if ($Collection) {
            $active = $active | Where-Object {
                $_.Value.collections -contains $Collection
            }
        }

        # Sort by priority (P0 first), then trust tier
        $priorityOrder = @('P0', 'P1', 'P2', 'P3', 'P4', 'P5')
        $trustOrder = @('High', 'Medium-High', 'Medium', 'Low')

        $ranked = $active | ForEach-Object {
            $source = [PSCustomObject]$_.Value
            [PSCustomObject]@{
                Source = $source
                PriorityRank = $priorityOrder.IndexOf($source.priority)
                TrustRank = $trustOrder.IndexOf($source.trustTier)
            }
        } | Sort-Object PriorityRank, TrustRank | ForEach-Object {
            $_.Source
        }

        $result = @($ranked)
        Write-Output -NoEnumerate $result
    }
}

<#
.SYNOPSIS
    Exports source registry summary.

.DESCRIPTION
    Creates a summary of the source registry for reporting.

.PARAMETER Registry
    The source registry.
#>
function Export-SourceRegistrySummary {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [hashtable]$Registry
    )

    process {
        $sources = $Registry.sources
        if (-not $sources) { $sources = @{} }

        $byPriority = @{}
        $byState = @{}
        $byTrust = @{}

        foreach ($source in $sources.Values) {
            # Count by priority
            if (-not $byPriority[$source.priority]) { $byPriority[$source.priority] = 0 }
            $byPriority[$source.priority]++

            # Count by state
            if (-not $byState[$source.state]) { $byState[$source.state] = 0 }
            $byState[$source.state]++

            # Count by trust tier
            if (-not $byTrust[$source.trustTier]) { $byTrust[$source.trustTier] = 0 }
            $byTrust[$source.trustTier]++
        }

        return [PSCustomObject]@{
            PackId = $Registry.packId
            TotalSources = $sources.Count
            ActiveSources = ($sources.Values | Where-Object { $_.state -eq 'active' }).Count
            ByPriority = $byPriority
            ByState = $byState
            ByTrustTier = $byTrust
            Updated = $Registry.updatedUtc
        }
    }
}

# Export-ModuleMember handled by LLMWorkflow.psm1
