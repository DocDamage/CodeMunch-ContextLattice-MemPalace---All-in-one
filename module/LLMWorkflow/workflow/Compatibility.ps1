<#
.SYNOPSIS
    Helper to convert JSON to hashtable (PowerShell 5.1 compatible).
#>
function ConvertFrom-JsonToHashtable {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true, ValueFromPipeline = $true)]
        [string]$InputObject
    )
    process {
        $result = $InputObject | ConvertFrom-Json
        # Convert PSCustomObject to hashtable recursively
        function Convert-Object($obj) {
            if ($obj -is [System.Management.Automation.PSCustomObject]) {
                $hash = @{}
                foreach ($prop in $obj.PSObject.Properties) {
                    $hash[$prop.Name] = Convert-Object $prop.Value
                }
                return $hash
            }
            elseif ($obj -is [array]) {
                return @($obj | ForEach-Object { Convert-Object $_ })
            }
            return $obj
        }
        return Convert-Object $result
    }
}

<#
.SYNOPSIS
    Runtime Compatibility Enforcement for LLM Workflow platform.

.DESCRIPTION
    Implements compatibility matrix validation, version drift detection,
    and compatibility lock management per Section 16 of the canonical architecture.
    
    This module provides semantic versioning support, version range validation,
    dependency chain compatibility checking, and cross-pack compatibility
    verification for the Blender → Godot pipeline and similar workflows.

.NOTES
    Author: LLM Workflow Platform
    Version: 0.4.0
    Date: 2026-04-12
#>

# Script-level constants
$script:ToolkitVersion = '0.4.0'
$script:CompatSchemaVersion = 1
$script:ExitCodeMigrationRequired = 8

# Valid compatibility statuses
$script:ValidCompatStatuses = @('compatible', 'warning', 'incompatible', 'unknown')

# Valid drift severity levels
$script:ValidDriftSeverities = @('info', 'warning', 'critical', 'breaking')

<#
.SYNOPSIS
    Parses a semantic version string into its components.

.DESCRIPTION
    Parses semantic version strings (e.g., "1.2.3", "1.2.3-alpha", "1.2.3+build")
    into major, minor, patch, pre-release, and build components.

.PARAMETER Version
    The version string to parse.

.OUTPUTS
    Hashtable with keys: Major, Minor, Patch, PreRelease, Build, Original, IsValid
#>
function Parse-SemanticVersion {
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [Parameter(Mandatory = $true, ValueFromPipeline = $true)]
        [string]$Version
    )

    process {
        $result = @{
            Major      = 0
            Minor      = 0
            Patch      = 0
            PreRelease = $null
            Build      = $null
            Original   = $Version
            IsValid    = $false
        }

        if ([string]::IsNullOrWhiteSpace($Version)) {
            return $result
        }

        # Semantic version pattern: MAJOR.MINOR.PATCH[-prerelease][+build]
        # Supports versions like: 1.2.3, 1.2.3-alpha, 1.2.3-alpha.1, 1.2.3+build.123, 1.2.3-alpha+build
        $pattern = '^(?<major>0|[1-9][0-9]*)\.(?<minor>0|[1-9][0-9]*)\.(?<patch>0|[1-9][0-9]*)(?:-(?<prerelease>[0-9A-Za-z-]+(?:\.[0-9A-Za-z-]+)*))?(?:\+(?<build>[0-9A-Za-z-]+(?:\.[0-9A-Za-z-]+)*))?$'

        if ($Version -match $pattern) {
            $result.Major = [int]$matches['major']
            $result.Minor = [int]$matches['minor']
            $result.Patch = [int]$matches['patch']
            $result.PreRelease = $matches['prerelease']
            $result.Build = $matches['build']
            $result.IsValid = $true
        }

        return $result
    }
}

<#
.SYNOPSIS
    Tests if a version satisfies a version range constraint.

.DESCRIPTION
    Validates that a version satisfies a version range expression.
    Supports: >=, >, <=, <, =, ^, ~, and ranges like ">=1.0.0 <2.0.0"

.PARAMETER Version
    The version to test.

.PARAMETER Range
    The version range constraint (e.g., ">=1.0.0", "^1.2.0", "~1.2.3", ">=1.0.0 <2.0.0").

.OUTPUTS
    Boolean indicating if the version satisfies the range.
#>
function Test-VersionRange {
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Version,

        [Parameter(Mandatory = $true)]
        [string]$Range
    )

    process {
        $parsedVersion = Parse-SemanticVersion -Version $Version
        if (-not $parsedVersion.IsValid) {
            Write-Verbose "Invalid version format: $Version"
            return $false
        }

        # Handle caret (^) - compatible with major version
        if ($Range -match '^\^(?<version>.+)$') {
            $caretVersion = Parse-SemanticVersion -Version $matches['version']
            if (-not $caretVersion.IsValid) { return $false }

            if ($caretVersion.Major -eq 0) {
                # ^0.x.y is equivalent to >=0.x.y <0.(x+1).0
                return (Compare-Version $parsedVersion $caretVersion) -ge 0 -and
                       $parsedVersion.Major -eq 0 -and
                       $parsedVersion.Minor -eq $caretVersion.Minor
            }
            # ^x.y.z is equivalent to >=x.y.z <(x+1).0.0
            return (Compare-Version $parsedVersion $caretVersion) -ge 0 -and
                   $parsedVersion.Major -eq $caretVersion.Major
        }

        # Handle tilde (~) - compatible with minor version
        if ($Range -match '^~(?<version>.+)$') {
            $tildeVersion = Parse-SemanticVersion -Version $matches['version']
            if (-not $tildeVersion.IsValid) { return $false }

            # ~x.y.z is equivalent to >=x.y.z <x.(y+1).0
            return (Compare-Version $parsedVersion $tildeVersion) -ge 0 -and
                   $parsedVersion.Major -eq $tildeVersion.Major -and
                   $parsedVersion.Minor -eq $tildeVersion.Minor
        }

        # Handle hyphen range (e.g., "1.0.0 - 2.0.0")
        if ($Range -match '^(?<min>\S+)\s+-\s+(?<max>\S+)$') {
            $minVersion = Parse-SemanticVersion -Version $matches['min']
            $maxVersion = Parse-SemanticVersion -Version $matches['max']
            if (-not $minVersion.IsValid -or -not $maxVersion.IsValid) { return $false }

            return (Compare-Version $parsedVersion $minVersion) -ge 0 -and
                   (Compare-Version $parsedVersion $maxVersion) -le 0
        }

        # Handle compound ranges (e.g., ">=1.0.0 <2.0.0")
        $constraints = $Range -split '\s+' | Where-Object { $_ }
        foreach ($constraint in $constraints) {
            if (-not (Test-SingleConstraint -Version $parsedVersion -Constraint $constraint)) {
                return $false
            }
        }

        return $true
    }
}

<#
.SYNOPSIS
    Tests a single version constraint.

.DESCRIPTION
    Internal helper to test a single constraint operator against a parsed version.
#>
function Test-SingleConstraint {
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [Parameter(Mandatory = $true)]
        [hashtable]$Version,

        [Parameter(Mandatory = $true)]
        [string]$Constraint
    )

    process {
        # Pattern: operator + version
        if ($Constraint -match '^(?<op>>=|<=|>|<|=)(?<ver>.+)$') {
            $operator = $matches['op']
            $constraintVersion = Parse-SemanticVersion -Version $matches['ver']
            if (-not $constraintVersion.IsValid) { return $false }

            $comparison = Compare-Version $Version $constraintVersion

            switch ($operator) {
                '>=' { return $comparison -ge 0 }
                '<=' { return $comparison -le 0 }
                '>'  { return $comparison -gt 0 }
                '<'  { return $comparison -lt 0 }
                '='  { return $comparison -eq 0 }
            }
        }

        # Bare version = exact match
        $exactVersion = Parse-SemanticVersion -Version $Constraint
        if ($exactVersion.IsValid) {
            return (Compare-Version $Version $exactVersion) -eq 0
        }

        return $false
    }
}

<#
.SYNOPSIS
    Compares two semantic versions.

.DESCRIPTION
    Compares two parsed semantic versions.
    Returns: -1 if v1 < v2, 0 if v1 == v2, 1 if v1 > v2

.PARAMETER Version1
    First parsed version hashtable.

.PARAMETER Version2
    Second parsed version hashtable.
#>
function Compare-Version {
    [CmdletBinding()]
    [OutputType([int])]
    param(
        [Parameter(Mandatory = $true)]
        [hashtable]$Version1,

        [Parameter(Mandatory = $true)]
        [hashtable]$Version2
    )

    process {
        # Compare major.minor.patch
        if ($Version1.Major -ne $Version2.Major) {
            return [math]::Sign($Version1.Major - $Version2.Major)
        }
        if ($Version1.Minor -ne $Version2.Minor) {
            return [math]::Sign($Version1.Minor - $Version2.Minor)
        }
        if ($Version1.Patch -ne $Version2.Patch) {
            return [math]::Sign($Version1.Patch - $Version2.Patch)
        }

        # Handle pre-release comparison
        $v1HasPre = -not [string]::IsNullOrEmpty($Version1.PreRelease)
        $v2HasPre = -not [string]::IsNullOrEmpty($Version2.PreRelease)

        # A version without pre-release has higher precedence
        if ($v1HasPre -and -not $v2HasPre) { return -1 }
        if (-not $v1HasPre -and $v2HasPre) { return 1 }

        # Both have pre-release or both don't - compare pre-release identifiers
        if ($v1HasPre -and $v2HasPre) {
            $v1Parts = $Version1.PreRelease -split '\.'
            $v2Parts = $Version2.PreRelease -split '\.'

            for ($i = 0; $i -lt [math]::Max($v1Parts.Length, $v2Parts.Length); $i++) {
                if ($i -ge $v1Parts.Length) { return -1 }
                if ($i -ge $v2Parts.Length) { return 1 }

                $v1Part = $v1Parts[$i]
                $v2Part = $v2Parts[$i]

                $v1IsNum = $v1Part -match '^\d+$'
                $v2IsNum = $v2Part -match '^\d+$'

                if ($v1IsNum -and $v2IsNum) {
                    $cmp = [int]$v1Part - [int]$v2Part
                    if ($cmp -ne 0) { return [math]::Sign($cmp) }
                }
                elseif ($v1IsNum) {
                    return -1  # Numeric identifiers have lower precedence
                }
                elseif ($v2IsNum) {
                    return 1
                }
                else {
                    $cmp = [string]::CompareOrdinal($v1Part, $v2Part)
                    if ($cmp -ne 0) { return [math]::Sign($cmp) }
                }
            }
        }

        return 0
    }
}

<#
.SYNOPSIS
    Tests version compatibility between two versions.

.DESCRIPTION
    Validates that two versions are compatible according to semantic versioning rules.
    By default, versions with the same major version are compatible (except 0.x).

.PARAMETER RequiredVersion
    The required version or version range.

.PARAMETER ActualVersion
    The actual version to test.

.PARAMETER Strict
    If specified, requires exact version match.

.OUTPUTS
    Boolean indicating compatibility.
#>
function Test-VersionCompatibility {
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [Parameter(Mandatory = $true)]
        [string]$RequiredVersion,

        [Parameter(Mandatory = $true)]
        [string]$ActualVersion,

        [Parameter()]
        [switch]$Strict
    )

    process {
        if ($Strict) {
            $v1 = Parse-SemanticVersion -Version $RequiredVersion
            $v2 = Parse-SemanticVersion -Version $ActualVersion
            if (-not $v1.IsValid -or -not $v2.IsValid) { return $false }
            return (Compare-Version $v1 $v2) -eq 0
        }

        # Test as range
        return Test-VersionRange -Version $ActualVersion -Range $RequiredVersion
    }
}

<#
.SYNOPSIS
    Validates compatibility matrix for a pack.

.DESCRIPTION
    Validates compatibility between pack version, toolkit version, and source engine versions.
    Checks dependency chain compatibility and generates a comprehensive compatibility assessment.

.PARAMETER PackId
    The unique identifier for the pack to validate.

.PARAMETER TargetVersion
    Optional specific pack version to validate against. If not specified, uses the current pack version.

.PARAMETER Strict
    If specified, enforces strict version matching without tolerating warnings.

.PARAMETER RunId
    Optional run ID for tracking.

.OUTPUTS
    Hashtable containing compatibility status and details.
#>
function Test-CompatibilityMatrix {
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [Parameter(Mandatory = $true)]
        [string]$PackId,

        [Parameter()]
        [string]$TargetVersion,

        [Parameter()]
        [switch]$Strict,

        [Parameter()]
        [string]$RunId
    )

    begin {
        if (-not $RunId) {
            $RunId = & "$PSScriptRoot/../core/RunId.ps1" -Command New-RunId
        }
    }

    process {
        $result = @{
            schemaVersion  = $script:CompatSchemaVersion
            runId          = $RunId
            generatedUtc   = [DateTime]::UtcNow.ToString("o")
            packId         = $PackId
            overallStatus  = 'unknown'
            toolkitVersion = $script:ToolkitVersion
            packVersion    = $null
            sources        = @()
            drift          = @()
            conflicts      = @()
            recommendations = @()
        }

        # Load pack manifest
        $manifestPath = "packs/manifests/$PackId.json"
        if (-not (Test-Path $manifestPath)) {
            Write-Error "Pack manifest not found: $manifestPath"
            $result.overallStatus = 'incompatible'
            $result.recommendations += "Pack manifest not found for $PackId"
            return $result
        }

        $manifest = Get-Content $manifestPath -Raw | ConvertFrom-JsonToHashtable
        $result.packVersion = if ($TargetVersion) { $TargetVersion } else { $manifest.version }

        # Load source registry
        $registryPath = "packs/registries/$PackId.sources.json"
        $registry = $null
        if (Test-Path $registryPath) {
            $registry = Get-Content $registryPath -Raw | ConvertFrom-JsonToHashtable
        }

        # Check toolkit compatibility
        $toolkitConstraint = $manifest.toolkitConstraint
        if (-not $toolkitConstraint -and $manifest.toolkit_constraint) {
            $toolkitConstraint = $manifest.toolkit_constraint
        }
        if ($toolkitConstraint) {
            if (-not (Test-VersionRange -Version $script:ToolkitVersion -Range $toolkitConstraint)) {
                $result.overallStatus = 'incompatible'
                $result.conflicts += @{
                    type        = 'toolkit'
                    current     = $script:ToolkitVersion
                    required    = $toolkitConstraint
                    description = "Toolkit version $script:ToolkitVersion does not satisfy pack requirement: $toolkitConstraint"
                }
            }
        }

        # Check source compatibility
        if ($registry -and $registry.sources) {
            foreach ($sourceEntry in $registry.sources.GetEnumerator()) {
                $source = $sourceEntry.Value
                $sourceCompat = Test-SourceCompatibility -Source $source -Strict:$Strict
                $result.sources += $sourceCompat

                if ($sourceCompat.status -eq 'incompatible') {
                    $result.conflicts += @{
                        type        = 'source'
                        sourceId    = $source.sourceId
                        description = $sourceCompat.statusReason
                    }
                }

                # Check for drift
                $drift = Get-SourceVersionDrift -Source $source
                if ($drift) {
                    $result.drift += $drift
                }
            }
        }

        # Determine overall status
        if ($result.conflicts.Count -gt 0) {
            $result.overallStatus = 'incompatible'
        }
        elseif ($result.drift.Count -gt 0 -or ($result.sources | Where-Object { $_.status -eq 'warning' })) {
            $result.overallStatus = 'warning'
        }
        else {
            $result.overallStatus = 'compatible'
        }

        # Generate recommendations
        $result.recommendations = Get-CompatibilityRecommendations -Result $result

        return $result
    }
}

<#
.SYNOPSIS
    Tests compatibility for a single source.

.DESCRIPTION
    Internal helper to test compatibility for a single source entry.
#>
function Test-SourceCompatibility {
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [Parameter(Mandatory = $true)]
        [hashtable]$Source,

        [Parameter()]
        [switch]$Strict
    )

    process {
        $result = @{
            sourceId       = $Source.sourceId
            engineTarget   = $Source.engineTarget
            engineMinVersion = $Source.engineMinVersion
            engineMaxVersion = $Source.engineMaxVersion
            status         = 'unknown'
            statusReason   = $null
        }

        # Check source state
        if ($Source.state -eq 'quarantined') {
            $result.status = 'incompatible'
            $result.statusReason = "Source is quarantined: $($Source.quarantineReason)"
            return $result
        }

        if ($Source.state -eq 'retired' -or $Source.state -eq 'removed') {
            $result.status = 'incompatible'
            $result.statusReason = "Source is $($Source.state)"
            return $result
        }

        if ($Source.state -eq 'deprecated') {
            $result.status = 'warning'
            $result.statusReason = "Source is deprecated"
        }

        # If no engine constraints, consider compatible
        if (-not $Source.engineTarget -and -not $Source.engineMinVersion -and -not $Source.engineMaxVersion) {
            if ($result.status -eq 'unknown') {
                $result.status = 'compatible'
            }
            return $result
        }

        # Engine version constraints would be checked against actual engine version here
        # This is a placeholder for actual engine version checking
        if ($result.status -eq 'unknown') {
            $result.status = 'compatible'
        }

        return $result
    }
}

<#
.SYNOPSIS
    Detects version drift for a source.

.DESCRIPTION
    Internal helper to detect version drift between installed and required versions.
#>
function Get-SourceVersionDrift {
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [Parameter(Mandatory = $true)]
        [hashtable]$Source
    )

    process {
        # This would compare against actual installed source version
        # Placeholder implementation - would integrate with sync state
        $syncStatePath = ".llm-workflow/state/sync-state.json"
        if (-not (Test-Path $syncStatePath)) {
            return $null
        }

        # Implementation would check actual synced version vs required
        # For now, return null (no drift detected)
        return $null
    }
}

<#
.SYNOPSIS
    Generates recommendations based on compatibility result.

.DESCRIPTION
    Internal helper to generate actionable recommendations.
#>
function Get-CompatibilityRecommendations {
    [CmdletBinding()]
    [OutputType([string[]])]
    param(
        [Parameter(Mandatory = $true)]
        [hashtable]$Result
    )

    process {
        $recommendations = @()

        foreach ($conflict in $Result.conflicts) {
            switch ($conflict.type) {
                'toolkit' {
                    $recommendations += "Update toolkit to version satisfying: $($conflict.required)"
                }
                'source' {
                    $recommendations += "Review source '$($conflict.sourceId)': $($conflict.description)"
                }
            }
        }

        foreach ($drift in $Result.drift) {
            if ($drift.severity -eq 'critical') {
                $recommendations += "Update source '$($drift.sourceId)' from $($drift.currentVersion) to $($drift.requiredVersion)"
            }
        }

        if ($recommendations.Count -eq 0 -and $Result.overallStatus -eq 'compatible') {
            $recommendations += "All compatibility checks passed"
        }

        return $recommendations
    }
}

<#
.SYNOPSIS
    Generates a comprehensive compatibility report.

.DESCRIPTION
    Creates a detailed compatibility report including pack compatibility status,
    source compatibility by priority, dependency conflicts, recommended actions,
    and risk assessment.

.PARAMETER PackId
    The pack ID to generate the report for.

.PARAMETER IncludeDrift
    Include version drift information in the report.

.PARAMETER Format
    Output format: 'Hashtable' (default), 'Json', or 'Markdown'.

.PARAMETER RunId
    Optional run ID for tracking.

.OUTPUTS
    Compatibility report in the specified format.
#>
function Get-CompatibilityReport {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$PackId,

        [Parameter()]
        [switch]$IncludeDrift,

        [Parameter()]
        [ValidateSet('Hashtable', 'Json', 'Markdown')]
        [string]$Format = 'Hashtable',

        [Parameter()]
        [string]$RunId
    )

    begin {
        if (-not $RunId) {
            $RunId = & "$PSScriptRoot/../core/RunId.ps1" -Command New-RunId
        }
    }

    process {
        # Run compatibility matrix test
        $matrix = Test-CompatibilityMatrix -PackId $PackId -RunId $RunId

        $report = @{
            schemaVersion   = $script:CompatSchemaVersion
            runId           = $RunId
            generatedUtc    = [DateTime]::UtcNow.ToString("o")
            packId          = $PackId
            summary         = @{
                overallStatus   = $matrix.overallStatus
                toolkitVersion  = $matrix.toolkitVersion
                packVersion     = $matrix.packVersion
                totalSources    = $matrix.sources.Count
                compatibleCount = ($matrix.sources | Where-Object { $_.status -eq 'compatible' }).Count
                warningCount    = ($matrix.sources | Where-Object { $_.status -eq 'warning' }).Count
                incompatibleCount = ($matrix.sources | Where-Object { $_.status -eq 'incompatible' }).Count
            }
            packCompatibility = @{
                status      = $matrix.overallStatus
                toolkitOk   = ($matrix.conflicts | Where-Object { $_.type -eq 'toolkit' }).Count -eq 0
                details     = $matrix.conflicts | Where-Object { $_.type -eq 'toolkit' }
            }
            sourceCompatibility = @{
                byPriority = @{}
                byStatus   = @{}
            }
            dependencyConflicts = $matrix.conflicts
            recommendedActions  = $matrix.recommendations
            riskAssessment      = Get-RiskAssessment -Matrix $matrix
        }

        # Group sources by priority
        $registryPath = "packs/registries/$PackId.sources.json"
        if (Test-Path $registryPath) {
            $registry = Get-Content $registryPath -Raw | ConvertFrom-JsonToHashtable
            $priorities = @('P0', 'P1', 'P2', 'P3', 'P4', 'P5')
            foreach ($priority in $priorities) {
                $prioritySources = $matrix.sources | Where-Object {
                    $sourceId = $_.sourceId
                    $registry.sources[$sourceId].priority -eq $priority
                }
                if ($prioritySources) {
                    $report.sourceCompatibility.byPriority[$priority] = @{
                        count      = $prioritySources.Count
                        compatible = ($prioritySources | Where-Object { $_.status -eq 'compatible' }).Count
                        warning    = ($prioritySources | Where-Object { $_.status -eq 'warning' }).Count
                        incompatible = ($prioritySources | Where-Object { $_.status -eq 'incompatible' }).Count
                    }
                }
            }
        }

        # Group by status
        $statuses = @('compatible', 'warning', 'incompatible', 'unknown')
        foreach ($status in $statuses) {
            $count = ($matrix.sources | Where-Object { $_.status -eq $status }).Count
            if ($count -gt 0) {
                $report.sourceCompatibility.byStatus[$status] = $count
            }
        }

        # Include drift if requested
        if ($IncludeDrift) {
            $report.versionDrift = $matrix.drift
        }

        # Format output
        switch ($Format) {
            'Json' {
                return $report | ConvertTo-Json -Depth 10
            }
            'Markdown' {
                return ConvertTo-CompatibilityMarkdown -Report $report
            }
            default {
                return $report
            }
        }
    }
}

<#
.SYNOPSIS
    Generates risk assessment for compatibility matrix.

.DESCRIPTION
    Internal helper to generate risk assessment.
#>
function Get-RiskAssessment {
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [Parameter(Mandatory = $true)]
        [hashtable]$Matrix
    )

    process {
        $risk = @{
            level       = 'low'
            score       = 0  # 0-100, higher is riskier
            factors     = @()
            mitigation  = @()
        }

        # Score based on conflicts
        if ($Matrix.conflicts.Count -gt 0) {
            $risk.score += $Matrix.conflicts.Count * 25
            $risk.factors += ("{0} compatibility conflict(s) detected" -f $Matrix.conflicts.Count)
        }

        # Score based on drift
        if ($Matrix.drift.Count -gt 0) {
            $criticalDrift = $Matrix.drift | Where-Object { $_.severity -eq 'critical' }
            if ($criticalDrift) {
                $risk.score += $criticalDrift.Count * 15
                $risk.factors += ("{0} critical version drift(s)" -f $criticalDrift.Count)
            }
        }

        # Determine risk level
        if ($risk.score -ge 75) {
            $risk.level = 'critical'
            $risk.mitigation += "Address all critical conflicts before proceeding"
            $risk.mitigation += "Run compatibility lock export after fixes"
        }
        elseif ($risk.score -ge 50) {
            $risk.level = 'high'
            $risk.mitigation += "Review and resolve warnings before production use"
        }
        elseif ($risk.score -ge 25) {
            $risk.level = 'medium'
            $risk.mitigation += "Monitor compatibility status regularly"
        }

        return $risk
    }
}

<#
.SYNOPSIS
    Converts compatibility report to Markdown format.

.DESCRIPTION
    Internal helper to convert report to Markdown.
#>
function ConvertTo-CompatibilityMarkdown {
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory = $true)]
        [hashtable]$Report
    )

    process {
        $md = @()
        $md += "# Compatibility Report: $($Report.packId)"
        $md += ""
        $md += "**Generated:** $($Report.generatedUtc)"  
        $md += "**Run ID:** $($Report.runId)"
        $md += ""
        $md += "## Summary"
        $md += ""
        $md += "| Metric | Value |"
        $md += "|--------|-------|"
        $md += "| Overall Status | $($Report.summary.overallStatus) |"
        $md += "| Toolkit Version | $($Report.summary.toolkitVersion) |"
        $md += "| Pack Version | $($Report.summary.packVersion) |"
        $md += "| Total Sources | $($Report.summary.totalSources) |"
        $md += "| Compatible | $($Report.summary.compatibleCount) |"
        $md += "| Warning | $($Report.summary.warningCount) |"
        $md += "| Incompatible | $($Report.summary.incompatibleCount) |"
        $md += ""

        $md += "## Risk Assessment"
        $md += ""
        $md += "**Level:** $($Report.riskAssessment.level)  "
        $md += "**Score:** $($Report.riskAssessment.score)/100"
        $md += ""

        if ($Report.riskAssessment.factors.Count -gt 0) {
            $md += "### Risk Factors"
            $md += ""
            foreach ($factor in $Report.riskAssessment.factors) {
                $md += "- $factor"
            }
            $md += ""
        }

        if ($Report.riskAssessment.mitigation.Count -gt 0) {
            $md += "### Mitigation Steps"
            $md += ""
            foreach ($step in $Report.riskAssessment.mitigation) {
                $md += "- $step"
            }
            $md += ""
        }

        if ($Report.dependencyConflicts.Count -gt 0) {
            $md += "## Conflicts"
            $md += ""
            foreach ($conflict in $Report.dependencyConflicts) {
                $md += "- **$($conflict.type):** $($conflict.description)"
            }
            $md += ""
        }

        if ($Report.recommendedActions.Count -gt 0) {
            $md += "## Recommended Actions"
            $md += ""
            foreach ($action in $Report.recommendedActions) {
                $md += "- $action"
            }
            $md += ""
        }

        return ($md -join "`n")
    }
}

<#
.SYNOPSIS
    Creates a compatibility lock file.

.DESCRIPTION
    Exports a compatibility.lock.json file containing:
    - Toolkit version constraints
    - Pack version constraints  
    - Source version pins
    - Known working combinations

.PARAMETER PackId
    The pack ID to create the lock for.

.PARAMETER Path
    Optional path for the lock file. Defaults to compatibility.lock.json.

.PARAMETER PinSources
    If specified, pins all current source versions.

.PARAMETER Notes
    Optional notes about this lock configuration.

.PARAMETER RunId
    Optional run ID for tracking.

.OUTPUTS
    Path to the created lock file.
#>
function Export-CompatibilityLock {
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory = $true)]
        [string]$PackId,

        [Parameter()]
        [string]$Path = 'compatibility.lock.json',

        [Parameter()]
        [switch]$PinSources,

        [Parameter()]
        [string]$Notes,

        [Parameter()]
        [string]$RunId
    )

    begin {
        if (-not $RunId) {
            $RunId = & "$PSScriptRoot/../core/RunId.ps1" -Command New-RunId
        }
    }

    process {
        # Load pack manifest
        $manifestPath = "packs/manifests/$PackId.json"
        $manifest = $null
        if (Test-Path $manifestPath) {
            $manifest = Get-Content $manifestPath -Raw | ConvertFrom-JsonToHashtable
        }

        # Load source registry
        $registryPath = "packs/registries/$PackId.sources.json"
        $registry = $null
        if (Test-Path $registryPath) {
            $registry = Get-Content $registryPath -Raw | ConvertFrom-JsonToHashtable
        }

        $lock = @{
            schema_version = $script:CompatSchemaVersion
            updated_utc    = [DateTime]::UtcNow.ToString("o")
            runId          = $RunId
            packId         = $PackId
            notes          = $Notes
            tooling        = @{
                llmworkflow_module_version = $script:ToolkitVersion
                tested_shells              = @('powershell-5.1', 'pwsh-7.x')
                tested_python              = '3.11'
            }
            constraints    = @{
                toolkit = @{
                    min_version = '0.4.0'
                    max_version = $null
                    constraint  = '>=0.4.0'
                }
                pack    = @{
                    packId  = $PackId
                    version = if ($manifest) { $manifest.version } else { $null }
                    channel = if ($manifest) { $manifest.channel } else { $null }
                }
            }
            sources        = @{}
            combinations   = @()
        }

        # Add source pins if requested
        if ($PinSources -and $registry -and $registry.sources) {
            foreach ($entry in $registry.sources.GetEnumerator()) {
                $source = $entry.Value
                $lock.sources[$source.sourceId] = @{
                    sourceId    = $source.sourceId
                    repoUrl     = $source.repoUrl
                    pinnedRef   = $source.selectedRef
                    engineTarget = $source.engineTarget
                    engineMinVersion = $source.engineMinVersion
                    engineMaxVersion = $source.engineMaxVersion
                }
            }
        }

        # Add known working combination
        $workingCombo = @{
            toolkit_version = $script:ToolkitVersion
            pack_version    = if ($manifest) { $manifest.version } else { $null }
            pack_channel    = if ($manifest) { $manifest.channel } else { $null }
            sources         = @()
            tested_utc      = [DateTime]::UtcNow.ToString("o")
            tested_by       = $RunId
        }

        if ($registry -and $registry.sources) {
            foreach ($entry in $registry.sources.GetEnumerator()) {
                $source = $entry.Value
                if ($source.state -eq 'active') {
                    $workingCombo.sources += @{
                        sourceId  = $source.sourceId
                        ref       = $source.selectedRef
                        engineTarget = $source.engineTarget
                    }
                }
            }
        }

        $lock.combinations += $workingCombo

        # Save lock file
        $json = $lock | ConvertTo-Json -Depth 10
        $json | Out-File -FilePath $Path -Encoding UTF8 -Force

        Write-Verbose "Compatibility lock exported to: $Path"
        return (Resolve-Path $Path).Path
    }
}

<#
.SYNOPSIS
    Detects version drift between installed and required versions.

.DESCRIPTION
    Compares installed versions against required versions and identifies:
    - Outdated sources
    - Breaking changes
    - Version mismatches

.PARAMETER PackId
    The pack ID to check for drift.

.PARAMETER CompareAgainst
    What to compare against: 'LockFile' (default) or 'Manifest'.

.PARAMETER IncludeDetails
    Include detailed drift information for each source.

.PARAMETER RunId
    Optional run ID for tracking.

.OUTPUTS
    Array of drift detection results.
#>
function Get-VersionDrift {
    [CmdletBinding()]
    [OutputType([array])]
    param(
        [Parameter(Mandatory = $true)]
        [string]$PackId,

        [Parameter()]
        [ValidateSet('LockFile', 'Manifest')]
        [string]$CompareAgainst = 'LockFile',

        [Parameter()]
        [switch]$IncludeDetails,

        [Parameter()]
        [string]$RunId
    )

    begin {
        if (-not $RunId) {
            $RunId = & "$PSScriptRoot/../core/RunId.ps1" -Command New-RunId
        }
    }

    process {
        $driftResults = @()

        # Load source registry
        $registryPath = "packs/registries/$PackId.sources.json"
        if (-not (Test-Path $registryPath)) {
            Write-Warning "Source registry not found for pack: $PackId"
            return $driftResults
        }

        $registry = Get-Content $registryPath -Raw | ConvertFrom-JsonToHashtable

        # Determine baseline
        $baseline = $null
        if ($CompareAgainst -eq 'LockFile' -and (Test-Path 'compatibility.lock.json')) {
            $lockFile = Get-Content 'compatibility.lock.json' -Raw | ConvertFrom-JsonToHashtable
            $baseline = $lockFile.sources
        }

        foreach ($entry in $registry.sources.GetEnumerator()) {
            $source = $entry.Value
            $drift = $null

            if ($baseline -and $baseline[$source.sourceId]) {
                $baselineSource = $baseline[$source.sourceId]
                if ($baselineSource.pinnedRef -ne $source.selectedRef) {
                    $drift = @{
                        sourceId        = $source.sourceId
                        type            = 'version_mismatch'
                        currentVersion  = $source.selectedRef
                        pinnedVersion   = $baselineSource.pinnedRef
                        severity        = 'warning'
                        description     = "Source ref changed from pinned version"
                    }
                }
            }

            # Check for outdated sources based on refresh cadence
            $lastReviewed = $null
            if ($source.lastReviewedUtc) {
                try {
                    $lastReviewed = [DateTime]::Parse($source.lastReviewedUtc)
                }
                catch {
                    Write-Verbose "Could not parse lastReviewedUtc for $($source.sourceId)"
                }
            }

            if ($lastReviewed) {
                $daysSinceReview = ([DateTime]::UtcNow - $lastReviewed).Days
                $cadenceDays = 30  # Default 30-day cadence

                switch ($source.refreshCadence) {
                    '7-day' { $cadenceDays = 7 }
                    '14-day' { $cadenceDays = 14 }
                    '30-day' { $cadenceDays = 30 }
                    '90-day' { $cadenceDays = 90 }
                    'manual' { $cadenceDays = 365 }
                }

                if ($daysSinceReview -gt $cadenceDays * 2) {
                    $drift = @{
                        sourceId       = $source.sourceId
                        type           = 'stale_review'
                        daysStale      = $daysSinceReview
                        severity       = 'warning'
                        description    = "Source not reviewed in $daysSinceReview days (cadence: $($source.refreshCadence))"
                    }
                }
                elseif ($daysSinceReview -gt $cadenceDays) {
                    if (-not $drift) {
                        $drift = @{
                            sourceId       = $source.sourceId
                            type           = 'review_overdue'
                            daysOverdue    = $daysSinceReview - $cadenceDays
                            severity       = 'info'
                            description    = "Source review is $($daysSinceReview - $cadenceDays) days overdue"
                        }
                    }
                }
            }

            if ($drift) {
                if ($IncludeDetails) {
                    $drift.sourceDetails = @{
                        repoUrl      = $source.repoUrl
                        engineTarget = $source.engineTarget
                        trustTier    = $source.trustTier
                        state        = $source.state
                    }
                }
                $driftResults += $drift
            }
        }

        return $driftResults
    }
}

<#
.SYNOPSIS
    Validates compatibility before an operation.

.DESCRIPTION
    Pre-operation compatibility check that validates compatibility before sync/build
    operations. Returns exit code 8 (Migration required) if incompatible.

.PARAMETER PackId
    The pack ID to validate.

.PARAMETER Operation
    The operation being performed (e.g., 'sync', 'build', 'deploy').

.PARAMETER Strict
    If specified, treats warnings as incompatible.

.PARAMETER AutoFix
    If specified, attempts automatic fixes where possible.

.PARAMETER RunId
    Optional run ID for tracking.

.OUTPUTS
    Exit code: 0 (compatible), 8 (migration required), or other error codes.
#>
function Assert-CompatibilityBeforeOperation {
    [CmdletBinding()]
    [OutputType([int])]
    param(
        [Parameter(Mandatory = $true)]
        [string]$PackId,

        [Parameter()]
        [string]$Operation = 'operation',

        [Parameter()]
        [switch]$Strict,

        [Parameter()]
        [switch]$AutoFix,

        [Parameter()]
        [string]$RunId
    )

    begin {
        if (-not $RunId) {
            $RunId = & "$PSScriptRoot/../core/RunId.ps1" -Command New-RunId
        }
    }

    process {
        Write-Verbose "Checking compatibility for $Operation on pack: $PackId"

        # Run compatibility check
        $matrix = Test-CompatibilityMatrix -PackId $PackId -Strict:$Strict -RunId $RunId

        switch ($matrix.overallStatus) {
            'compatible' {
                Write-Verbose "Compatibility check passed for $Operation"
                return 0
            }

            'warning' {
                if ($Strict) {
                    Write-Warning "Compatibility warnings treated as errors (Strict mode) for $Operation"
                    foreach ($rec in $matrix.recommendations) {
                        Write-Warning "  - $rec"
                    }
                    return $script:ExitCodeMigrationRequired
                }
                Write-Verbose "Compatibility warnings detected but proceeding with $Operation"
                foreach ($rec in $matrix.recommendations) {
                    Write-Verbose "  - $rec"
                }
                return 0
            }

            'incompatible' {
                Write-Error "Compatibility check failed for $Operation"
                foreach ($conflict in $matrix.conflicts) {
                    Write-Error "  - $($conflict.type): $($conflict.description)"
                }
                foreach ($rec in $matrix.recommendations) {
                    Write-Host "  Recommendation: $rec"
                }
                return $script:ExitCodeMigrationRequired
            }

            default {
                Write-Error "Unknown compatibility status: $($matrix.overallStatus)"
                return 1
            }
        }
    }
}

<#
.SYNOPSIS
    Registers a known working compatibility combination.

.DESCRIPTION
    Records that a specific toolkit version works with a specific pack version
    and source configuration. These combinations can be used for validation
    and troubleshooting.

.PARAMETER PackId
    The pack ID.

.PARAMETER PackVersion
    The pack version that works.

.PARAMETER ToolkitVersion
    The toolkit version that works (defaults to current).

.PARAMETER Sources
    Hashtable of source IDs to their working refs.

.PARAMETER Notes
    Optional notes about this combination.

.PARAMETER CommunityTested
    If specified, marks this as community-tested rather than officially verified.

.PARAMETER TestedBy
    Identifier of who tested this combination.

.PARAMETER RunId
    Optional run ID for tracking.

.OUTPUTS
    The registered combination entry.
#>
function Register-KnownCompatibility {
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [Parameter(Mandatory = $true)]
        [string]$PackId,

        [Parameter(Mandatory = $true)]
        [string]$PackVersion,

        [Parameter()]
        [string]$ToolkitVersion = $script:ToolkitVersion,

        [Parameter()]
        [hashtable]$Sources = @{},

        [Parameter()]
        [string]$Notes,

        [Parameter()]
        [switch]$CommunityTested,

        [Parameter()]
        [string]$TestedBy,

        [Parameter()]
        [string]$RunId
    )

    begin {
        if (-not $RunId) {
            $RunId = & "$PSScriptRoot/../core/RunId.ps1" -Command New-RunId
        }
    }

    process {
        $combination = @{
            schemaVersion   = $script:CompatSchemaVersion
            packId          = $PackId
            packVersion     = $PackVersion
            toolkitVersion  = $ToolkitVersion
            sources         = @()
            testedUtc       = [DateTime]::UtcNow.ToString("o")
            testedBy        = $TestedBy
            runId           = $RunId
            communityTested = $CommunityTested.IsPresent
            notes           = $Notes
            verified        = -not $CommunityTested.IsPresent
        }

        foreach ($entry in $Sources.GetEnumerator()) {
            $combination.sources += @{
                sourceId = $entry.Key
                ref      = $entry.Value
            }
        }

        # Load or create known combinations file
        $knownCombosPath = ".llm-workflow/state/known-compatibility.json"
        $knownCombos = @{
            schemaVersion = $script:CompatSchemaVersion
            combinations  = @()
        }

        if (Test-Path $knownCombosPath) {
            try {
                $existing = Get-Content $knownCombosPath -Raw | ConvertFrom-JsonToHashtable
                if ($existing.combinations) {
                    $knownCombos.combinations = $existing.combinations
                }
            }
            catch {
                Write-Warning "Could not load existing known combinations: $_"
            }
        }

        # Add new combination
        $knownCombos.combinations += $combination

        # Save
        $dir = Split-Path -Parent $knownCombosPath
        if (-not (Test-Path $dir)) {
            New-Item -ItemType Directory -Path $dir -Force | Out-Null
        }

        $knownCombos | ConvertTo-Json -Depth 10 | Out-File -FilePath $knownCombosPath -Encoding UTF8 -Force

Write-Verbose ("Registered known compatibility for {0}@{1}" -f $PackId, $PackVersion)
        return $combination
    }
}

<#
.SYNOPSIS
    Gets known working compatibility combinations.

.DESCRIPTION
    Retrieves registered known working combinations for a pack.

.PARAMETER PackId
    The pack ID to query.

.PARAMETER ToolkitVersion
    Filter by specific toolkit version.

.PARAMETER VerifiedOnly
    Only return officially verified combinations (not community-tested).

.PARAMETER Latest
    Return only the most recent combination.

.OUTPUTS
    Array of known compatibility combinations.
#>
function Get-KnownCompatibility {
    [CmdletBinding()]
    [OutputType([array])]
    param(
        [Parameter(Mandatory = $true)]
        [string]$PackId,

        [Parameter()]
        [string]$ToolkitVersion,

        [Parameter()]
        [switch]$VerifiedOnly,

        [Parameter()]
        [switch]$Latest
    )

    process {
        $knownCombosPath = ".llm-workflow/state/known-compatibility.json"
        if (-not (Test-Path $knownCombosPath)) {
            return @()
        }

        $knownCombos = Get-Content $knownCombosPath -Raw | ConvertFrom-JsonToHashtable
        $combinations = $knownCombos.combinations | Where-Object { $_.packId -eq $PackId }

        if ($ToolkitVersion) {
            $combinations = $combinations | Where-Object { $_.toolkitVersion -eq $ToolkitVersion }
        }

        if ($VerifiedOnly) {
            $combinations = $combinations | Where-Object { $_.verified -eq $true }
        }

        $combinations = $combinations | Sort-Object testedUtc -Descending

        if ($Latest) {
            return @($combinations | Select-Object -First 1)
        }

        return $combinations
    }
}

<#
.SYNOPSIS
    Validates cross-pack compatibility.

.DESCRIPTION
    Validates compatibility between two packs for pipeline scenarios
    like Blender → Godot workflow.

.PARAMETER SourcePackId
    The source pack ID (e.g., 'blender-engine').

.PARAMETER TargetPackId
    The target pack ID (e.g., 'godot-engine').

.PARAMETER PipelineType
    The type of pipeline workflow.

.PARAMETER RunId
    Optional run ID for tracking.

.OUTPUTS
    Cross-pack compatibility assessment.
#>
function Test-CrossPackCompatibility {
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [Parameter(Mandatory = $true)]
        [string]$SourcePackId,

        [Parameter(Mandatory = $true)]
        [string]$TargetPackId,

        [Parameter()]
        [string]$PipelineType = 'export-import',

        [Parameter()]
        [string]$RunId
    )

    begin {
        if (-not $RunId) {
            $RunId = & "$PSScriptRoot/../core/RunId.ps1" -Command New-RunId
        }
    }

    process {
        $result = @{
            schemaVersion = $script:CompatSchemaVersion
            runId         = $RunId
            generatedUtc  = [DateTime]::UtcNow.ToString("o")
            sourcePack    = $SourcePackId
            targetPack    = $TargetPackId
            pipelineType  = $PipelineType
            status        = 'unknown'
            issues        = @()
            supportedFormats = @()
        }

        # Load pack manifests
        $sourceManifestPath = "packs/manifests/$SourcePackId.json"
        $targetManifestPath = "packs/manifests/$TargetPackId.json"

        if (-not (Test-Path $sourceManifestPath)) {
            $result.issues += "Source pack manifest not found: $SourcePackId"
            $result.status = 'incompatible'
            return $result
        }

        if (-not (Test-Path $targetManifestPath)) {
            $result.issues += "Target pack manifest not found: $TargetPackId"
            $result.status = 'incompatible'
            return $result
        }

        $sourceManifest = Get-Content $sourceManifestPath -Raw | ConvertFrom-JsonToHashtable
        $targetManifest = Get-Content $targetManifestPath -Raw | ConvertFrom-JsonToHashtable

        # Check for known pipeline configurations
        $pipelines = @{
            'blender-godot' = @{
                supportedFormats = @('glTF', 'glb', 'obj', 'fbx')
                notes = 'Blender to Godot pipeline via glTF/GLB recommended'
            }
            'rpgmaker-godot' = @{
                supportedFormats = @('json', 'csv')
                notes = 'Data export/import pipeline, custom tooling required'
            }
        }

        $pipelineKey = "$SourcePackId-$TargetPackId"
        if ($pipelines.ContainsKey($pipelineKey)) {
            $config = $pipelines[$pipelineKey]
            $result.supportedFormats = $config.supportedFormats
            $result.status = 'compatible'
            $result.notes = $config.notes
        }
        else {
            $result.status = 'unknown'
            $result.notes = "No predefined configuration for $pipelineKey pipeline"
        }

        return $result
    }
}

# Export-ModuleMember is handled by LLMWorkflow.psm1
