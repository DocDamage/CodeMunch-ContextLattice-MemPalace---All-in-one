<#
.SYNOPSIS
    Include/Exclude Filters for LLM Workflow platform.

.DESCRIPTION
    Functions for creating and applying include/exclude filters for source and file filtering.
    Implements Section 20 of the canonical architecture (Phase 3).

.NOTES
    Author: LLM Workflow Platform
    Version: 0.4.0
    Date: 2026-04-12
#>

# Current schema version for filter configs
$script:FilterSchemaVersion = 1

# Valid pattern types
$script:ValidPatternTypes = @('glob', 'regex', 'literal')

# Valid default behaviors
$script:ValidDefaultBehaviors = @('include', 'exclude')

# Per-pack default filter definitions
$script:PackDefaultFilters = @{
    'rpgmaker-mz' = @{
        includeExtensions = @('.js', '.json', '.md')
        excludePatterns = @(
            'node_modules/**',
            '.git/**',
            'dist/**',
            'build/**',
            '*.min.js',
            'js/libs/**',
            'audio/**',
            'img/**',
            'movies/**',
            'save/**',
            '**/Thumbs.db',
            '**/.DS_Store'
        )
        codeFilePatterns = @(
            'js/plugins/*.js',
            'js/rmmz_*.js'
        )
    }
    'godot-engine' = @{
        includeExtensions = @('.gd', '.cs', '.tscn', '.tres', '.gdshader', '.shader', '.md')
        excludePatterns = @(
            '**/.godot/**',
            '**/.import/**',
            '.git/**',
            'addons/**',
            'bin/**',
            'build/**',
            'export/**',
            '**/*.tmp',
            '**/Thumbs.db',
            '**/.DS_Store'
        )
        codeFilePatterns = @(
            '**/*.gd',
            '**/*.cs'
        )
    }
    'blender-engine' = @{
        includeExtensions = @('.py', '.md', '.json')
        excludePatterns = @(
            '__pycache__/**',
            '.git/**',
            '*.blend1',
            '*.blend2',
            'build/**',
            'dist/**',
            '**/Thumbs.db',
            '**/.DS_Store'
        )
        codeFilePatterns = @(
            '**/*.py'
        )
    }
    'generic' = @{
        includeExtensions = @('.js', '.ts', '.py', '.ps1', '.md', '.json', '.yaml', '.yml', '.toml')
        excludePatterns = @(
            'node_modules/**',
            '.git/**',
            '__pycache__/**',
            '.venv/**',
            'venv/**',
            'bin/**',
            'obj/**',
            'dist/**',
            'build/**',
            'out/**',
            '.vscode/**',
            '.idea/**',
            '*.min.js',
            '*.map',
            '**/Thumbs.db',
            '**/.DS_Store',
            '**/*.tmp',
            '**/*.log'
        )
        codeFilePatterns = @(
            '**/*.js',
            '**/*.ts',
            '**/*.py',
            '**/*.ps1'
        )
    }
}

<#
.SYNOPSIS
    Creates a new include/exclude filter object.

.DESCRIPTION
    Creates a filter object that can be used to test paths against include/exclude patterns.
    Supports glob patterns, regex patterns, and literal paths with priority-based matching.

.PARAMETER Name
    Filter configuration name for identification.

.PARAMETER PatternType
    Type of patterns used (glob, regex, literal). Default is 'glob'.

.PARAMETER DefaultBehavior
    Default behavior when no patterns match: 'include' (include all unless excluded) or 
    'exclude' (exclude all unless included). Default is 'include'.

.PARAMETER Patterns
    Array of pattern objects with properties: pattern, action, priority.

.PARAMETER Description
    Optional description of the filter configuration.

.EXAMPLE
    $filter = New-IncludeExcludeFilter -Name "my-filter" -DefaultBehavior exclude
    
.EXAMPLE
    $patterns = @(
        @{ pattern = "src/**/*.js"; action = "include"; priority = 100 },
        @{ pattern = "**/*.test.js"; action = "exclude"; priority = 50 }
    )
    $filter = New-IncludeExcludeFilter -Name "js-sources" -Patterns $patterns -DefaultBehavior exclude
#>
function New-IncludeExcludeFilter {
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Name,

        [Parameter()]
        [ValidateSet('glob', 'regex', 'literal')]
        [string]$PatternType = 'glob',

        [Parameter()]
        [ValidateSet('include', 'exclude')]
        [string]$DefaultBehavior = 'include',

        [Parameter()]
        [array]$Patterns = @(),

        [Parameter()]
        [string]$Description = ''
    )

    process {
        # Normalize and validate patterns
        $normalizedPatterns = @()
        foreach ($pat in $Patterns) {
            if ($pat -is [hashtable]) {
                $normalizedPatterns += @{
                    pattern = $pat.pattern
                    action = if ($pat.action -in @('include', 'exclude')) { $pat.action } else { 'exclude' }
                    priority = if ($pat.priority -is [int]) { $pat.priority } else { 100 }
                    description = $pat.description
                }
            }
            elseif ($pat -is [string]) {
                # Parse string pattern with optional prefix
                $action = 'include'
                $pattern = $pat
                $priority = 100

                # Check for negation prefix
                if ($pattern.StartsWith('!')) {
                    $action = 'exclude'
                    $pattern = $pattern.Substring(1)
                }
                # Check for priority suffix like [P0] or [999]
                if ($pattern -match '\[(P?\d+)\]$') {
                    $priorityVal = $matches[1]
                    if ($priorityVal.StartsWith('P')) {
                        $priorityVal = $priorityVal.Substring(1)
                    }
                    [int]$priority = $priorityVal
                    $pattern = $pattern -replace '\[P?\d+\]$', ''
                    $pattern = $pattern.TrimEnd()
                }

                $normalizedPatterns += @{
                    pattern = $pattern
                    action = $action
                    priority = $priority
                }
            }
        }

        # Sort patterns by priority (highest first)
        $normalizedPatterns = $normalizedPatterns | Sort-Object -Property priority -Descending

        return @{
            schemaVersion = $script:FilterSchemaVersion
            name = $Name
            patternType = $PatternType
            defaultBehavior = $DefaultBehavior
            patterns = @($normalizedPatterns)
            description = $Description
            createdUtc = [DateTime]::UtcNow.ToString("o")
            updatedUtc = [DateTime]::UtcNow.ToString("o")
        }
    }
}

<#
.SYNOPSIS
    Converts a glob pattern to a regex pattern.

.DESCRIPTION
    Internal helper function that converts glob patterns with ** and * wildcards
to equivalent regular expressions.

.PARAMETER GlobPattern
    The glob pattern to convert.
#>
function Convert-GlobToRegex {
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory = $true)]
        [string]$GlobPattern
    )

    process {
        $regex = $GlobPattern

        # Escape regex special characters except * and ?
        $regex = [regex]::Escape($regex)

        # Handle **/ pattern (matches zero or more directory levels)
        # This needs to be processed before single *
        $regex = $regex -replace '\\\*\\\*/', '(?:.*/)?'
        
        # Handle /** (trailing recursive)
        $regex = $regex -replace '/\\\*\\\*', '(?:/.*)?'
        
        # Handle standalone ** (anywhere)
        $regex = $regex -replace '(?<!/)\\\*\\\*(?!/)', '.*'

        # Handle * (matches anything except /)
        $regex = $regex -replace '\\\*', '[^/\\]*'

        # Handle ? (matches single character except /)
        $regex = $regex -replace '\\\?', '[^/\\]'

        # Anchor the pattern
        $regex = '^' + $regex + '$'

        return $regex
    }
}

<#
.SYNOPSIS
    Tests if a path matches a pattern.

.DESCRIPTION
    Internal helper that tests a path against a single pattern.

.PARAMETER Path
    The path to test.

.PARAMETER Pattern
    The pattern to match against.

.PARAMETER PatternType
    Type of pattern (glob, regex, literal).
#>
function Test-PathMatchesPattern {
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path,

        [Parameter(Mandatory = $true)]
        [string]$Pattern,

        [Parameter()]
        [ValidateSet('glob', 'regex', 'literal')]
        [string]$PatternType = 'glob'
    )

    process {
        # Normalize path separators
        $normalizedPath = $Path -replace '\\', '/'

        switch ($PatternType) {
            'literal' {
                return $normalizedPath -eq ($Pattern -replace '\\', '/')
            }
            'regex' {
                try {
                    return $normalizedPath -match $Pattern
                }
                catch {
                    Write-Warning "Invalid regex pattern: $Pattern"
                    return $false
                }
            }
            'glob' {
                $regexPattern = Convert-GlobToRegex -GlobPattern $Pattern
                try {
                    return $normalizedPath -match $regexPattern
                }
                catch {
                    Write-Warning "Invalid glob pattern conversion: $Pattern -> $regexPattern"
                    return $false
                }
            }
            default {
                return $false
            }
        }
    }
}

<#
.SYNOPSIS
    Tests if a path matches an include/exclude filter.

.DESCRIPTION
    Tests a path against the filter's patterns and returns true if the path
    should be included based on the filter rules and priority ordering.

.PARAMETER Path
    The file or directory path to test.

.PARAMETER Filter
    The filter object created by New-IncludeExcludeFilter.

.PARAMETER DefaultResult
    Optional default result if no patterns match (overrides filter's defaultBehavior).

.EXAMPLE
    $filter = New-IncludeExcludeFilter -Name "test" -DefaultBehavior exclude
    Test-PathAgainstFilter -Path "src/main.js" -Filter $filter
#>
function Test-PathAgainstFilter {
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [Parameter(Mandatory = $true, ValueFromPipeline = $true)]
        [string]$Path,

        [Parameter(Mandatory = $true)]
        [hashtable]$Filter,

        [Parameter()]
        [bool]$DefaultResult
    )

    begin {
        # Determine default behavior
        $defaultAction = if ($PSBoundParameters.ContainsKey('DefaultResult')) {
            if ($DefaultResult) { 'include' } else { 'exclude' }
        }
        else {
            $Filter.defaultBehavior
        }

        $result = $defaultAction
        $matchedPriority = -1
    }

    process {
        foreach ($patternDef in $Filter.patterns) {
            $pattern = $patternDef.pattern
            $action = $patternDef.action
            $priority = $patternDef.priority

            # Skip if we've already matched a higher priority pattern
            if ($priority -lt $matchedPriority) {
                continue
            }

            # Test if path matches this pattern
            if (Test-PathMatchesPattern -Path $Path -Pattern $pattern -PatternType $Filter.patternType) {
                $result = $action
                $matchedPriority = $priority

                Write-Verbose "Path '$Path' matched pattern '$pattern' (priority=$priority, action=$action)"
            }
        }

        return ($result -eq 'include')
    }
}

<#
.SYNOPSIS
    Filters a source registry using include/exclude rules.

.DESCRIPTION
    Takes a source registry and applies include/exclude patterns to filter sources.
    Supports filtering by source properties like packId, authorityRole, trustTier.

.PARAMETER Registry
    The source registry hashtable from Get-SourceRegistry.

.PARAMETER IncludePatterns
    Array of patterns for sources to include (supports wildcards).

.PARAMETER ExcludePatterns
    Array of patterns for sources to exclude (supports wildcards).

.PARAMETER Priority
    Optional priority tier(s) to filter by (P0, P1, P2, P3, P4, P5).

.PARAMETER AuthorityRole
    Optional authority role to filter by.

.PARAMETER TrustTier
    Optional trust tier(s) to filter by.

.PARAMETER PackId
    Optional pack ID to filter sources by.

.PARAMETER State
    Optional source state(s) to filter by (default: 'active').

.EXAMPLE
    $registry = Get-SourceRegistry -PackId "rpgmaker-mz"
    $sources = Get-IncludedSources -Registry $registry -Priority @("P0", "P1")

.EXAMPLE
    $registry = Get-SourceRegistry -PackId "rpgmaker-mz"
    $sources = Get-IncludedSources -Registry $registry `
        -IncludePatterns @("plugin-*") `
        -ExcludePatterns @("*test*", "*demo*")
#>
function Get-IncludedSources {
    [CmdletBinding()]
    [OutputType([array])]
    param(
        [Parameter(Mandatory = $true)]
        [hashtable]$Registry,

        [Parameter()]
        [string[]]$IncludePatterns = @(),

        [Parameter()]
        [string[]]$ExcludePatterns = @(),

        [Parameter()]
        [ValidateSet('P0', 'P1', 'P2', 'P3', 'P4', 'P5')]
        [string[]]$Priority = @(),

        [Parameter()]
        [string]$AuthorityRole = '',

        [Parameter()]
        [ValidateSet('High', 'Medium-High', 'Medium', 'Low', 'Quarantined')]
        [string[]]$TrustTier = @(),

        [Parameter()]
        [string]$PackId = '',

        [Parameter()]
        [ValidateSet('active', 'deprecated', 'retired', 'quarantined', 'removed')]
        [string[]]$State = @('active')
    )

    process {
        $sources = $Registry.sources
        if (-not $sources) { return @() }

        $filteredSources = $sources.GetEnumerator() | Where-Object {
            $source = $_.Value

            # Filter by state
            if ($State -and $source.state -notin $State) {
                return $false
            }

            # Filter by priority
            if ($Priority -and $source.priority -notin $Priority) {
                return $false
            }

            # Filter by authority role
            if ($AuthorityRole -and $source.authorityRole -ne $AuthorityRole) {
                return $false
            }

            # Filter by trust tier
            if ($TrustTier -and $source.trustTier -notin $TrustTier) {
                return $false
            }

            # Filter by pack ID
            if ($PackId -and $source.packId -ne $PackId) {
                return $false
            }

            # Apply include patterns (if any specified, must match at least one)
            if ($IncludePatterns.Count -gt 0) {
                $included = $false
                foreach ($pattern in $IncludePatterns) {
                    if ($source.sourceId -like $pattern) {
                        $included = $true
                        break
                    }
                }
                if (-not $included) {
                    return $false
                }
            }

            # Apply exclude patterns (must not match any)
            foreach ($pattern in $ExcludePatterns) {
                if ($source.sourceId -like $pattern) {
                    return $false
                }
            }

            return $true
        } | ForEach-Object {
            [PSCustomObject]$_.Value
        }

        # Use comma operator to prevent PowerShell from unwrapping single-element arrays
        return ,($filteredSources | Sort-Object priority)
    }
}

<#
.SYNOPSIS
    Filters a file list for extraction using include/exclude rules.

.DESCRIPTION
    Takes a list of file paths and applies extension filters and path filters
to return only files that should be processed.

.PARAMETER Files
    Array of file paths to filter.

.PARAMETER IncludeExtensions
    Array of file extensions to include (e.g., '.js', '.py').

.PARAMETER ExcludeExtensions
    Array of file extensions to exclude.

.PARAMETER IncludePatterns
    Array of glob/regex patterns for files to include.

.PARAMETER ExcludePatterns
    Array of glob/regex patterns for files to exclude.

.PARAMETER PatternType
    Type of patterns (glob, regex, literal). Default: 'glob'.

.PARAMETER DefaultBehavior
    Default behavior when no patterns match. Default: 'include'.

.PARAMETER Filter
    Pre-built filter object from New-IncludeExcludeFilter (alternative to individual parameters).

.EXAMPLE
    $files = Get-ChildItem -Recurse -File | Select-Object -ExpandProperty FullName
    $filtered = Get-IncludedFiles -Files $files -IncludeExtensions @('.js', '.ts')

.EXAMPLE
    $filter = New-IncludeExcludeFilter -Name "code-only" -DefaultBehavior exclude
    $files = Get-ChildItem -Recurse -File | Select-Object -ExpandProperty FullName
    $filtered = Get-IncludedFiles -Files $files -Filter $filter
#>
function Get-IncludedFiles {
    [CmdletBinding()]
    [OutputType([array])]
    param(
        [Parameter(Mandatory = $true, ValueFromPipeline = $true)]
        [string[]]$Files,

        [Parameter()]
        [string[]]$IncludeExtensions = @(),

        [Parameter()]
        [string[]]$ExcludeExtensions = @(),

        [Parameter()]
        [string[]]$IncludePatterns = @(),

        [Parameter()]
        [string[]]$ExcludePatterns = @(),

        [Parameter()]
        [ValidateSet('glob', 'regex', 'literal')]
        [string]$PatternType = 'glob',

        [Parameter()]
        [ValidateSet('include', 'exclude')]
        [string]$DefaultBehavior = 'include',

        [Parameter()]
        [hashtable]$Filter
    )

    begin {
        # Collect all files from pipeline
        $allFiles = [System.Collections.Generic.List[string]]::new()

        # Build filter object if not provided
        if (-not $Filter) {
            $patterns = @()

            # Add include patterns
            foreach ($pattern in $IncludePatterns) {
                $patterns += @{
                    pattern = $pattern
                    action = 'include'
                    priority = 100
                }
            }

            # Add exclude patterns
            foreach ($pattern in $ExcludePatterns) {
                $patterns += @{
                    pattern = $pattern
                    action = 'exclude'
                    priority = 100
                }
            }

            $Filter = New-IncludeExcludeFilter `
                -Name "temp-filter" `
                -PatternType $PatternType `
                -DefaultBehavior $DefaultBehavior `
                -Patterns $patterns
        }
    }

    process {
        foreach ($file in $Files) {
            $allFiles.Add($file)
        }
    }

    end {
        $filteredFiles = $allFiles | Where-Object {
            $filePath = $_
            $fileName = Split-Path -Leaf $filePath
            $extension = [System.IO.Path]::GetExtension($fileName).ToLower()

            # Apply extension filters first
            if ($IncludeExtensions.Count -gt 0) {
                $extIncluded = $false
                foreach ($ext in $IncludeExtensions) {
                    $extNormalized = if ($ext.StartsWith('.')) { $ext.ToLower() } else { ".$($ext.ToLower())" }
                    if ($extension -eq $extNormalized) {
                        $extIncluded = $true
                        break
                    }
                }
                if (-not $extIncluded) {
                    return $false
                }
            }

            if ($ExcludeExtensions.Count -gt 0) {
                foreach ($ext in $ExcludeExtensions) {
                    $extNormalized = if ($ext.StartsWith('.')) { $ext.ToLower() } else { ".$($ext.ToLower())" }
                    if ($extension -eq $extNormalized) {
                        return $false
                    }
                }
            }

            # Apply pattern-based filter
            return Test-PathAgainstFilter -Path $filePath -Filter $Filter
        }

        return @($filteredFiles)
    }
}

<#
.SYNOPSIS
    Exports a filter configuration to a JSON file.

.DESCRIPTION
    Saves a filter object to disk with proper formatting and comments support
    via JSONC (JSON with Comments) format for human readability.

.PARAMETER Filter
    The filter object to export.

.PARAMETER Path
    Path to save the filter configuration file.

.PARAMETER IncludeComments
    Include human-readable comments in the output (uses JSONC format).

.EXAMPLE
    $filter = New-IncludeExcludeFilter -Name "rpgmaker-filter"
    Export-FilterConfig -Filter $filter -Path "./filters/rpgmaker.json" -IncludeComments
#>
function Export-FilterConfig {
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory = $true)]
        [hashtable]$Filter,

        [Parameter(Mandatory = $true)]
        [string]$Path,

        [Parameter()]
        [switch]$IncludeComments
    )

    process {
        # Ensure directory exists
        $dir = Split-Path -Parent $Path
        if (-not (Test-Path $dir)) {
            New-Item -ItemType Directory -Path $dir -Force | Out-Null
        }

        # Update timestamp
        $Filter.updatedUtc = [DateTime]::UtcNow.ToString("o")

        if ($IncludeComments) {
            # Build JSON with comments
            $lines = [System.Collections.Generic.List[string]]::new()
            $lines.Add("// LLM Workflow Filter Configuration")
            $lines.Add("// Generated: $($Filter.updatedUtc)")
            $lines.Add("// Schema Version: $($Filter.schemaVersion)")
            $lines.Add("")

            if ($Filter.description) {
                $lines.Add("// Description: $($Filter.description)")
                $lines.Add("")
            }

            $lines.Add("{")
            $lines.Add("  // Schema version for compatibility")
            $lines.Add("  `"schemaVersion`": $($Filter.schemaVersion),")
            $lines.Add("")
            $lines.Add("  // Filter configuration name")
            $lines.Add("  `"name`": `"$($Filter.name)`",")
            $lines.Add("")
            $lines.Add("  // Pattern type: glob | regex | literal")
            $lines.Add("  `"patternType`": `"$($Filter.patternType)`",")
            $lines.Add("")
            $lines.Add("  // Default behavior when no patterns match: include | exclude")
            $lines.Add("  `"defaultBehavior`": `"$($Filter.defaultBehavior)`",")
            $lines.Add("")
            $lines.Add("  // Pattern definitions (evaluated in priority order, highest first)")
            $lines.Add("  `"patterns`": [")

            $patternCount = $Filter.patterns.Count
            for ($i = 0; $i -lt $patternCount; $i++) {
                $pat = $Filter.patterns[$i]
                $lines.Add("    {")
                $lines.Add("      // Pattern string to match against paths")
                $lines.Add("      `"pattern`": `"$($pat.pattern)`",")
                $lines.Add("      // Action when matched: include | exclude")
                $lines.Add("      `"action`": `"$($pat.action)`",")
                $lines.Add("      // Priority (higher values evaluated first)")
                $lines.Add("      `"priority`": $($pat.priority)")
                if ($pat.description) {
                    $lines.Add(",")
                    $lines.Add("      // Description of this pattern")
                    $lines.Add("      `"description`": `"$($pat.description)`"")
                }
                else {
                    $lines.Add("")
                }

                $comma = if ($i -lt $patternCount - 1) { "," } else { "" }
                $lines.Add("    }$comma")
            }

            $lines.Add("  ],")
            $lines.Add("")
            $lines.Add("  // Metadata")
            $lines.Add("  `"description`": `"$($Filter.description)`",")
            $lines.Add("  `"createdUtc`": `"$($Filter.createdUtc)`",")
            $lines.Add("  `"updatedUtc`": `"$($Filter.updatedUtc)`"")
            $lines.Add("}")

            $json = $lines -join "`r`n"
        }
        else {
            # Standard JSON without comments
            $json = $Filter | ConvertTo-Json -Depth 10
        }

        # Write with UTF8 encoding and BOM for PowerShell 5.1 compatibility
        $json | Out-File -FilePath $Path -Encoding UTF8

        Write-Verbose "Filter configuration exported to: $Path"
        return $Path
    }
}

<#
.SYNOPSIS
    Imports a filter configuration from a JSON file.

.DESCRIPTION
    Loads a filter object from disk. Supports both standard JSON and JSONC
    (JSON with Comments) format by stripping comments before parsing.

.PARAMETER Path
    Path to the filter configuration file.

.PARAMETER ValidateSchema
    Validate the loaded configuration against the expected schema.

.EXAMPLE
    $filter = Import-FilterConfig -Path "./filters/rpgmaker.json"

.EXAMPLE
    $filter = Import-FilterConfig -Path "./filters/custom.json" -ValidateSchema
#>
function Import-FilterConfig {
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path,

        [Parameter()]
        [switch]$ValidateSchema
    )

    begin {
        # Helper function to convert PSCustomObject to hashtable (for PS 5.1 compatibility)
        function ConvertTo-Hashtable {
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
                if ($InputObject -is [System.Management.Automation.PSCustomObject]) {
                    $hash = @{}
                    foreach ($prop in $InputObject.PSObject.Properties) {
                        $hash[$prop.Name] = ConvertTo-Hashtable -InputObject $prop.Value
                    }
                    return $hash
                }
                return $InputObject
            }
        }
    }

    process {
        if (-not (Test-Path -LiteralPath $Path)) {
            throw "Filter configuration file not found: $Path"
        }

        $content = Get-Content -LiteralPath $Path -Raw -Encoding UTF8

        # Remove JSONC comments (both // and /* */)
        $json = $content -replace '//.*?\r?\n', "`r`n" -replace '/\*.*?\*/', ''

        try {
            $obj = $json | ConvertFrom-Json
            $config = ConvertTo-Hashtable -InputObject $obj
        }
        catch {
            throw "Failed to parse filter configuration: $_"
        }

        if ($ValidateSchema) {
            # Validate required fields
            $requiredFields = @('schemaVersion', 'name', 'patternType', 'defaultBehavior')
            foreach ($field in $requiredFields) {
                if (-not $config.ContainsKey($field)) {
                    throw "Invalid filter configuration: missing required field '$field'"
                }
            }

            # Validate pattern type
            if ($config.patternType -notin $script:ValidPatternTypes) {
                throw "Invalid filter configuration: patternType must be one of $($script:ValidPatternTypes -join ', ')"
            }

            # Validate default behavior
            if ($config.defaultBehavior -notin $script:ValidDefaultBehaviors) {
                throw "Invalid filter configuration: defaultBehavior must be one of $($script:ValidDefaultBehaviors -join ', ')"
            }

            # Validate patterns array
            if ($config.ContainsKey('patterns')) {
                foreach ($pat in $config.patterns) {
                    if (-not $pat.ContainsKey('pattern') -or -not $pat.ContainsKey('action')) {
                        throw "Invalid filter configuration: each pattern must have 'pattern' and 'action' fields"
                    }
                    if ($pat.action -notin $script:ValidDefaultBehaviors) {
                        throw "Invalid filter configuration: pattern action must be 'include' or 'exclude'"
                    }
                }
            }
        }

        # Ensure all expected fields exist
        if (-not $config.ContainsKey('patterns')) {
            $config.patterns = @()
        }
        if (-not $config.ContainsKey('description')) {
            $config.description = ''
        }
        if (-not $config.ContainsKey('createdUtc')) {
            $config.createdUtc = [DateTime]::UtcNow.ToString("o")
        }
        if (-not $config.ContainsKey('updatedUtc')) {
            $config.updatedUtc = [DateTime]::UtcNow.ToString("o")
        }

        # Re-sort patterns by priority
        if ($config.patterns.Count -gt 0) {
            $config.patterns = @($config.patterns | Sort-Object -Property priority -Descending)
        }

        Write-Verbose "Filter configuration imported from: $Path"
        return $config
    }
}

<#
.SYNOPSIS
    Returns default filter configurations for common scenarios.

.DESCRIPTION
    Provides sensible default filters for various pack types and use cases.
    Includes pre-configured patterns for code extraction, documentation filtering, etc.

.PARAMETER PackId
    Pack ID to get defaults for (rpgmaker-mz, godot-engine, blender-engine, generic).

.PARAMETER UseCase
    Specific use case filter (code-extraction, documentation-only, tests-only, all).

.PARAMETER IncludeExtensions
    Additional extensions to include (merged with defaults).

.PARAMETER ExcludePatterns
    Additional patterns to exclude (merged with defaults).

.EXAMPLE
    $defaults = Get-DefaultFilters -PackId "rpgmaker-mz"

.EXAMPLE
    $defaults = Get-DefaultFilters -PackId "godot-engine" -UseCase "code-extraction"

.EXAMPLE
    $filter = Get-DefaultFilters -PackId "generic" -UseCase "code-extraction" -AsFilterObject
#>
function Get-DefaultFilters {
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [Parameter()]
        [ValidateSet('rpgmaker-mz', 'godot-engine', 'blender-engine', 'generic')]
        [string]$PackId = 'generic',

        [Parameter()]
        [ValidateSet('code-extraction', 'documentation-only', 'tests-only', 'all')]
        [string]$UseCase = 'code-extraction',

        [Parameter()]
        [string[]]$IncludeExtensions = @(),

        [Parameter()]
        [string[]]$ExcludePatterns = @(),

        [Parameter()]
        [switch]$AsFilterObject
    )

    process {
        $defaults = $script:PackDefaultFilters[$PackId]
        if (-not $defaults) {
            $defaults = $script:PackDefaultFilters['generic']
        }

        # Merge additional extensions
        $allExtensions = [System.Collections.Generic.List[string]]::new()
        foreach ($ext in $defaults.includeExtensions) {
            $allExtensions.Add($ext)
        }
        foreach ($ext in $IncludeExtensions) {
            if (-not $allExtensions.Contains($ext)) {
                $allExtensions.Add($ext)
            }
        }

        # Merge additional exclude patterns
        $allExcludes = [System.Collections.Generic.List[string]]::new()
        foreach ($pat in $defaults.excludePatterns) {
            $allExcludes.Add($pat)
        }
        foreach ($pat in $ExcludePatterns) {
            $allExcludes.Add($pat)
        }

        # Build patterns based on use case
        $patterns = [System.Collections.Generic.List[hashtable]]::new()

        switch ($UseCase) {
            'code-extraction' {
                # Include code files
                foreach ($pattern in $defaults.codeFilePatterns) {
                    $patterns.Add(@{
                        pattern = $pattern
                        action = 'include'
                        priority = 200
                        description = "Include code files matching: $pattern"
                    })
                }

                # Include extensions
                foreach ($ext in $allExtensions) {
                    $extPattern = if ($ext.StartsWith('.')) { "**/*$ext" } else { "**/*.$ext" }
                    $patterns.Add(@{
                        pattern = $extPattern
                        action = 'include'
                        priority = 150
                        description = "Include files with extension: $ext"
                    })
                }

                # Exclude patterns (higher priority)
                foreach ($pattern in $allExcludes) {
                    $patterns.Add(@{
                        pattern = $pattern
                        action = 'exclude'
                        priority = 500
                        description = "Exclude: $pattern"
                    })
                }

                $defaultBehavior = 'exclude'
                $description = "Code extraction filter for $PackId"
            }

            'documentation-only' {
                $patterns.Add(@{
                    pattern = '**/*.md'
                    action = 'include'
                    priority = 200
                    description = "Include markdown documentation"
                })
                $patterns.Add(@{
                    pattern = '**/README*'
                    action = 'include'
                    priority = 200
                    description = "Include README files"
                })
                $patterns.Add(@{
                    pattern = '**/LICENSE*'
                    action = 'include'
                    priority = 200
                    description = "Include license files"
                })
                $patterns.Add(@{
                    pattern = '**/docs/**'
                    action = 'include'
                    priority = 200
                    description = "Include docs directory"
                })

                # Exclude common non-doc directories
                $patterns.Add(@{
                    pattern = 'node_modules/**'
                    action = 'exclude'
                    priority = 500
                })
                $patterns.Add(@{
                    pattern = '.git/**'
                    action = 'exclude'
                    priority = 500
                })

                $defaultBehavior = 'exclude'
                $description = "Documentation-only filter for $PackId"
            }

            'tests-only' {
                $patterns.Add(@{
                    pattern = '**/test*/**'
                    action = 'include'
                    priority = 200
                })
                $patterns.Add(@{
                    pattern = '**/*.test.*'
                    action = 'include'
                    priority = 200
                })
                $patterns.Add(@{
                    pattern = '**/*.spec.*'
                    action = 'include'
                    priority = 200
                })
                $patterns.Add(@{
                    pattern = '**/tests/**'
                    action = 'include'
                    priority = 200
                })

                $defaultBehavior = 'exclude'
                $description = "Tests-only filter for $PackId"
            }

            'all' {
                $defaultBehavior = 'include'
                $description = "Include all filter for $PackId"
            }
        }

        $result = @{
            packId = $PackId
            useCase = $UseCase
            includeExtensions = @($allExtensions)
            excludePatterns = @($allExcludes)
            patterns = @($patterns)
            defaultBehavior = $defaultBehavior
            description = $description
        }

        if ($AsFilterObject) {
            return New-IncludeExcludeFilter `
                -Name "$PackId-$UseCase" `
                -PatternType 'glob' `
                -DefaultBehavior $defaultBehavior `
                -Patterns @($patterns) `
                -Description $description
        }

        return $result
    }
}

<#
.SYNOPSIS
    Adds a pattern to an existing filter.

.DESCRIPTION
    Helper function to add include/exclude patterns to a filter object.

.PARAMETER Filter
    The filter object to modify.

.PARAMETER Pattern
    The pattern string to add.

.PARAMETER Action
    Action when pattern matches: 'include' or 'exclude'.

.PARAMETER Priority
    Priority for pattern evaluation (higher = evaluated first).

.PARAMETER Description
    Optional description of the pattern.
#>
function Add-FilterPattern {
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [Parameter(Mandatory = $true)]
        [hashtable]$Filter,

        [Parameter(Mandatory = $true)]
        [string]$Pattern,

        [Parameter(Mandatory = $true)]
        [ValidateSet('include', 'exclude')]
        [string]$Action,

        [Parameter()]
        [int]$Priority = 100,

        [Parameter()]
        [string]$Description = ''
    )

    process {
        $newPattern = @{
            pattern = $Pattern
            action = $Action
            priority = $Priority
        }

        if ($Description) {
            $newPattern.description = $Description
        }

        # Add to patterns array
        $Filter.patterns += $newPattern

        # Re-sort by priority
        $Filter.patterns = @($Filter.patterns | Sort-Object -Property priority -Descending)

        # Update timestamp
        $Filter.updatedUtc = [DateTime]::UtcNow.ToString("o")

        return $Filter
    }
}

<#
.SYNOPSIS
    Removes patterns from a filter.

.DESCRIPTION
    Helper function to remove patterns from a filter object by pattern string.

.PARAMETER Filter
    The filter object to modify.

.PARAMETER Pattern
    The pattern string to remove (supports wildcards).

.PARAMETER Action
    Optional action filter (only remove patterns with this action).
#>
function Remove-FilterPattern {
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [Parameter(Mandatory = $true)]
        [hashtable]$Filter,

        [Parameter(Mandatory = $true)]
        [string]$Pattern,

        [Parameter()]
        [ValidateSet('include', 'exclude')]
        [string]$Action
    )

    process {
        $Filter.patterns = @($Filter.patterns | Where-Object {
            $match = $_.pattern -like $Pattern
            if ($Action) {
                $match = $match -and ($_.action -eq $Action)
            }
            -not $match
        })

        # Update timestamp
        $Filter.updatedUtc = [DateTime]::UtcNow.ToString("o")

        return $Filter
    }
}

# Export-ModuleMember handled by LLMWorkflow.psm1
