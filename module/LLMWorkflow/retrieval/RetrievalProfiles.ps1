#requires -Version 5.1
<#
.SYNOPSIS
    Retrieval Profiles module for LLM Workflow Platform - Phase 5 Implementation.

.DESCRIPTION
    Implements Section 14.2 Retrieval Profiles for the LLM Workflow platform.
    Provides 7 built-in retrieval profiles with specific configurations for
    different query types and use cases.
    
    Built-in Profiles:
    - api-lookup: For API reference questions
    - plugin-pattern: For plugin development patterns
    - conflict-diagnosis: For diagnosing plugin conflicts
    - codegen: For code generation tasks
    - private-project-first: Prioritize private project content
    - tooling-workflow: For tooling and workflow questions
    - reverse-format: For reverse engineering questions

.NOTES
    File: RetrievalProfiles.ps1
    Version: 1.0.0
    Author: LLM Workflow Team
    Phase: 5 - Retrieval and Answer Integrity
    Compatible with: PowerShell 5.1+

.EXAMPLE
    # Get a specific profile configuration
    $profile = Get-RetrievalProfileConfig -ProfileName "api-lookup"

.EXAMPLE
    # List all available profiles
    $profiles = Get-AllRetrievalProfiles

.EXAMPLE
    # Check if a profile exists
    if (Test-RetrievalProfileExists -ProfileName "codegen") { ... }

.EXAMPLE
    # Get pack preferences for a profile
    $packPrefs = Get-ProfilePackPreferences -ProfileName "plugin-pattern" -AvailablePacks $packs

.EXAMPLE
    # Get allowed evidence types for a profile
    $evidenceTypes = Get-ProfileEvidenceTypes -ProfileName "conflict-diagnosis"

.EXAMPLE
    # Create a custom profile
    $customProfile = New-CustomRetrievalProfile -ProfileName "my-custom" -Config @{ ... }
#>

Set-StrictMode -Version Latest

#===============================================================================
# Module Constants and Configuration
#===============================================================================

$script:ModuleVersion = '1.0.0'
$script:SchemaVersion = 1

# Valid trust tiers
$script:ValidTrustTiers = @(
    'none',
    'low',
    'medium',
    'medium-high',
    'high'
)

# Valid evidence types
$script:ValidEvidenceTypes = @(
    'code-example',
    'api-reference',
    'tutorial',
    'explanation',
    'configuration',
    'schema-definition',
    'dependency-info',
    'version-compatibility',
    'compatibility-data',
    'best-practice',
    'troubleshooting'
)

# Pack type categories
$script:PackTypeCategories = @{
    core_api = @('core_api', 'official-api', 'api-reference', 'runtime-api')
    plugin_patterns = @('plugin_patterns', 'plugin-examples', 'plugin-templates')
    conflict_signatures = @('conflict_signatures', 'compatibility-data', 'known-issues')
    method_touches = @('method_touches', 'method-trace', 'hook-analysis')
    private_project = @('private_project', 'project-specific', 'local-context')
    tooling = @('tooling', 'workflow-tools', 'dev-tools', 'build-tools')
    reverse_format = @('reverse_format', 'decompilation', 'binary-analysis')
    exemplar = @('exemplar', 'reference-implementation', 'best-practice')
    community = @('community', 'third-party', 'contrib')
}

#===============================================================================
# Built-in Profile Definitions (Section 14.2)
#===============================================================================

$script:BuiltInProfiles = @{
    #---------------------------------------------------------------------------
    # 1. api-lookup: For API reference questions
    #---------------------------------------------------------------------------
    'api-lookup' = @{
        name = 'api-lookup'
        description = 'For API reference questions - prioritizes official API documentation and core runtime references'
        packPreferences = @(
            'core_api',
            'official-api',
            'api-reference',
            'runtime-api',
            'language-binding',
            'schema-definition'
        )
        evidenceTypes = @(
            'api-reference',
            'schema-definition',
            'code-example'
        )
        minTrustTier = 'high'
        requireMultipleSources = $false
        crossPackEnabled = $true
        privateProjectFirst = $false
        config = @{
            prioritizeOfficial = $true
            includeDeprecated = $false
            includeExperimental = $false
            maxCommunitySources = 0
            requireAuthorityRole = @('core-runtime', 'core-engine', 'core-blender', 'language-binding')
        }
        metadata = @{
            version = 1
            category = 'reference'
            useCases = @('API documentation lookup', 'Method signature queries', 'Schema validation')
        }
    }

    #---------------------------------------------------------------------------
    # 2. plugin-pattern: For plugin development patterns
    #---------------------------------------------------------------------------
    'plugin-pattern' = @{
        name = 'plugin-pattern'
        description = 'For plugin development patterns - prioritizes plugin patterns, examples, and community contributions'
        packPreferences = @(
            'plugin_patterns',
            'plugin-examples',
            'plugin-templates',
            'exemplar',
            'reference-implementation',
            'community',
            'third-party'
        )
        evidenceTypes = @(
            'code-example',
            'configuration',
            'tutorial',
            'best-practice'
        )
        minTrustTier = 'medium'
        requireMultipleSources = $true
        crossPackEnabled = $true
        privateProjectFirst = $false
        config = @{
            prioritizeOfficial = $true
            includeCommunityExamples = $true
            maxCommunitySources = 5
            requireAuthorityRole = @('exemplar-pattern', 'core-runtime', 'language-binding')
            patternCategories = @('hooks', 'overrides', 'extensions', 'middleware')
        }
        metadata = @{
            version = 1
            category = 'development'
            useCases = @('Plugin architecture', 'Hook patterns', 'Extension development')
        }
    }

    #---------------------------------------------------------------------------
    # 3. conflict-diagnosis: For diagnosing plugin conflicts
    #---------------------------------------------------------------------------
    'conflict-diagnosis' = @{
        name = 'conflict-diagnosis'
        description = 'For diagnosing plugin conflicts - prioritizes conflict signatures and method touch analysis'
        packPreferences = @(
            'conflict_signatures',
            'compatibility-data',
            'known-issues',
            'method_touches',
            'method-trace',
            'hook-analysis',
            'dependency-info'
        )
        evidenceTypes = @(
            'dependency-info',
            'compatibility-data',
            'troubleshooting',
            'configuration'
        )
        minTrustTier = 'medium-high'
        requireMultipleSources = $true
        crossPackEnabled = $true
        privateProjectFirst = $false
        config = @{
            prioritizeOfficial = $true
            crossSourceComparison = $true
            includeKnownIssues = $true
            maxCommunitySources = 3
            requireAuthorityRole = @('tooling-analyzer', 'compatibility-data')
            analysisDepth = 'deep'
        }
        metadata = @{
            version = 1
            category = 'diagnostics'
            useCases = @('Plugin conflict detection', 'Compatibility analysis', 'Method collision detection')
        }
    }

    #---------------------------------------------------------------------------
    # 4. codegen: For code generation tasks
    #---------------------------------------------------------------------------
    'codegen' = @{
        name = 'codegen'
        description = 'For code generation tasks - prioritizes exemplar patterns and working code samples'
        packPreferences = @(
            'exemplar',
            'reference-implementation',
            'best-practice',
            'plugin-examples',
            'core_api',
            'official-api',
            'code-templates'
        )
        evidenceTypes = @(
            'code-example',
            'configuration',
            'schema-definition'
        )
        minTrustTier = 'medium-high'
        requireMultipleSources = $true
        crossPackEnabled = $true
        privateProjectFirst = $false
        config = @{
            prioritizeOfficial = $true
            multipleSourceAggregation = $true
            requireWorkingExamples = $true
            maxCommunitySources = 2
            requireAuthorityRole = @('exemplar-pattern', 'core-runtime', 'core-engine')
            minRelevanceScore = 0.8
        }
        metadata = @{
            version = 1
            category = 'generation'
            useCases = @('Code generation', 'Template instantiation', 'Pattern application')
        }
    }

    #---------------------------------------------------------------------------
    # 5. private-project-first: Prioritize private project content
    #---------------------------------------------------------------------------
    'private-project-first' = @{
        name = 'private-project-first'
        description = 'Prioritizes private project content with fallback to public sources - labels fallbacks explicitly'
        packPreferences = @(
            'private_project',
            'project-specific',
            'local-context',
            'user-defined',
            'exemplar',
            'reference-implementation',
            'core_api'
        )
        evidenceTypes = @(
            'code-example',
            'configuration',
            'api-reference',
            'tutorial',
            'explanation'
        )
        minTrustTier = 'low'
        requireMultipleSources = $false
        crossPackEnabled = $true
        privateProjectFirst = $true
        config = @{
            prioritizeOfficial = $false
            privateProjectPriority = $true
            labelFallbacksExplicitly = $true
            fallbackToPublic = $true
            maxCommunitySources = 3
            requireAuthorityRole = @()
            fallbackLabelFormat = '[PUBLIC FALLBACK] {content}'
        }
        metadata = @{
            version = 1
            category = 'project-local'
            useCases = @('Project-specific queries', 'Local codebase context', 'Custom implementation help')
        }
    }

    #---------------------------------------------------------------------------
    # 6. tooling-workflow: For tooling and workflow questions
    #---------------------------------------------------------------------------
    'tooling-workflow' = @{
        name = 'tooling-workflow'
        description = 'For tooling and workflow questions - prioritizes tooling collections and CI/CD configurations'
        packPreferences = @(
            'tooling',
            'workflow-tools',
            'dev-tools',
            'build-tools',
            'ci-cd',
            'deployment-tooling',
            'mcp-integration'
        )
        evidenceTypes = @(
            'configuration',
            'tutorial',
            'code-example',
            'best-practice'
        )
        minTrustTier = 'medium'
        requireMultipleSources = $false
        crossPackEnabled = $true
        privateProjectFirst = $false
        config = @{
            prioritizeOfficial = $true
            includeConfigurationExamples = $true
            maxCommunitySources = 4
            requireAuthorityRole = @('deployment-tooling', 'mcp-integration', 'llm-workflow', 'tooling-analyzer')
            toolCategories = @('build', 'test', 'deploy', 'lint', 'format')
        }
        metadata = @{
            version = 1
            category = 'tooling'
            useCases = @('CI/CD setup', 'Build configuration', 'Development workflows', 'Tool integration')
        }
    }

    #---------------------------------------------------------------------------
    # 7. reverse-format: For reverse engineering questions
    #---------------------------------------------------------------------------
    'reverse-format' = @{
        name = 'reverse-format'
        description = 'For reverse engineering questions - prioritizes reverse format sources with special handling for decompilation'
        packPreferences = @(
            'reverse_format',
            'decompilation',
            'binary-analysis',
            'format-specifications',
            'file-format',
            'protocol-docs'
        )
        evidenceTypes = @(
            'schema-definition',
            'explanation',
            'api-reference',
            'code-example'
        )
        minTrustTier = 'medium'
        requireMultipleSources = $true
        crossPackEnabled = $true
        privateProjectFirst = $false
        config = @{
            prioritizeOfficial = $true
            specialHandlingDecompilation = $true
            includeFormatSpecs = $true
            maxCommunitySources = 5
            requireAuthorityRole = @('reverse-format', 'format-specification')
            warnOnLegalIssues = $true
            decompilationTopics = @('binary-format', 'protocol', 'file-structure', 'memory-layout')
        }
        metadata = @{
            version = 1
            category = 'reverse-engineering'
            useCases = @('Format analysis', 'Protocol reverse engineering', 'Binary inspection', 'File structure analysis')
        }
    }
}

# Custom profiles storage (in-memory, can be persisted)
$script:CustomProfiles = @{}

#===============================================================================
# Core Profile Functions
#===============================================================================

function Get-RetrievalProfileConfig {
    <#
    .SYNOPSIS
        Gets the configuration for a specific retrieval profile.

    .DESCRIPTION
        Retrieves the complete configuration for a named retrieval profile.
        Checks built-in profiles first, then custom profiles.
        Returns a deep copy to prevent external modification of internal state.

    .PARAMETER ProfileName
        The name of the retrieval profile to retrieve.

    .OUTPUTS
        System.Collections.Hashtable. The profile configuration, or $null if not found.

    .EXAMPLE
        $profile = Get-RetrievalProfileConfig -ProfileName "api-lookup"
        PS> $profile.name
        api-lookup
        PS> $profile.minTrustTier
        high

    .EXAMPLE
        $profile = Get-RetrievalProfileConfig -ProfileName "nonexistent"
        PS> $profile -eq $null
        True
    #>
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [Parameter(Mandatory = $true)]
        [string]$ProfileName
    )

    # Normalize profile name
    $normalizedName = $ProfileName.ToLower().Trim()

    # Check built-in profiles first
    if ($script:BuiltInProfiles.ContainsKey($normalizedName)) {
        $profile = $script:BuiltInProfiles[$normalizedName]
        Write-Verbose "[RetrievalProfiles] Found built-in profile: $normalizedName"
        return (Copy-ProfileConfig -Profile $profile)
    }

    # Check custom profiles
    if ($script:CustomProfiles.ContainsKey($normalizedName)) {
        $profile = $script:CustomProfiles[$normalizedName]
        Write-Verbose "[RetrievalProfiles] Found custom profile: $normalizedName"
        return (Copy-ProfileConfig -Profile $profile)
    }

    Write-Verbose "[RetrievalProfiles] Profile not found: $normalizedName"
    return $null
}

function Get-AllRetrievalProfiles {
    <#
    .SYNOPSIS
        Gets all available retrieval profiles.

    .DESCRIPTION
        Returns a list of all retrieval profiles including both built-in and custom profiles.
        Each profile entry includes basic metadata (name, description, category).
        For full configuration, use Get-RetrievalProfileConfig.

    .OUTPUTS
        System.Collections.Hashtable[]. Array of profile summary objects.

    .EXAMPLE
        $profiles = Get-AllRetrievalProfiles
        PS> $profiles.Count
        7

    .EXAMPLE
        $profiles = Get-AllRetrievalProfiles
        PS> $profiles | Where-Object { $_.category -eq 'development' }
        Name            Description
        ----            -----------
        plugin-pattern  For plugin development patterns...
    #>
    [CmdletBinding()]
    [OutputType([array])]
    param()

    $allProfiles = [System.Collections.Generic.List[hashtable]]::new()

    # Add built-in profiles
    foreach ($profileName in $script:BuiltInProfiles.Keys | Sort-Object) {
        $profile = $script:BuiltInProfiles[$profileName]
        $allProfiles.Add(@{
            name = $profile.name
            description = $profile.description
            category = $profile.metadata.category
            isBuiltIn = $true
            version = $profile.metadata.version
        })
    }

    # Add custom profiles
    foreach ($profileName in $script:CustomProfiles.Keys | Sort-Object) {
        $profile = $script:CustomProfiles[$profileName]
        $allProfiles.Add(@{
            name = $profile.name
            description = $profile.description
            category = $profile.metadata.category
            isBuiltIn = $false
            version = $profile.metadata.version
            createdAt = $profile.metadata.createdAt
        })
    }

    Write-Verbose "[RetrievalProfiles] Retrieved $($allProfiles.Count) profiles ($($script:BuiltInProfiles.Count) built-in, $($script:CustomProfiles.Count) custom)"
    return $allProfiles.ToArray()
}

function Test-RetrievalProfileExists {
    <#
    .SYNOPSIS
        Tests whether a retrieval profile exists.

    .DESCRIPTION
        Checks if a retrieval profile with the given name exists.
        Returns $true if the profile exists (built-in or custom), $false otherwise.

    .PARAMETER ProfileName
        The name of the retrieval profile to check.

    .OUTPUTS
        System.Boolean. True if the profile exists, false otherwise.

    .EXAMPLE
        if (Test-RetrievalProfileExists -ProfileName "api-lookup") { ... }

    .EXAMPLE
        Test-RetrievalProfileExists -ProfileName "nonexistent"
        False
    #>
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [Parameter(Mandatory = $true)]
        [string]$ProfileName
    )

    $normalizedName = $ProfileName.ToLower().Trim()
    $exists = $script:BuiltInProfiles.ContainsKey($normalizedName) -or 
              $script:CustomProfiles.ContainsKey($normalizedName)

    Write-Verbose "[RetrievalProfiles] Profile '$normalizedName' exists: $exists"
    return $exists
}

function Get-ProfilePackPreferences {
    <#
    .SYNOPSIS
        Gets ordered pack preferences for a retrieval profile.

    .DESCRIPTION
        Returns an ordered list of pack types to prefer when using the specified
        retrieval profile. The order indicates priority (first = highest priority).
        Can optionally filter against available packs.

    .PARAMETER ProfileName
        The name of the retrieval profile.

    .PARAMETER AvailablePacks
        Optional array of available pack IDs to filter against. If provided,
        only preferences matching available packs are returned.

    .OUTPUTS
        System.String[]. Ordered array of preferred pack types/pack IDs.

    .EXAMPLE
        $prefs = Get-ProfilePackPreferences -ProfileName "api-lookup"
        PS> $prefs[0]
        core_api

    .EXAMPLE
        $available = @("core_api", "community-plugins", "tooling")
        $prefs = Get-ProfilePackPreferences -ProfileName "plugin-pattern" -AvailablePacks $available
        # Returns only preferences that match available packs
    #>
    [CmdletBinding()]
    [OutputType([array])]
    param(
        [Parameter(Mandatory = $true)]
        [string]$ProfileName,

        [Parameter()]
        [array]$AvailablePacks = @()
    )

    $profile = Get-RetrievalProfileConfig -ProfileName $ProfileName
    if (-not $profile) {
        Write-Warning "[RetrievalProfiles] Profile not found: $ProfileName"
        return @()
    }

    $preferences = $profile.packPreferences

    # Filter against available packs if provided
    if ($AvailablePacks -and ($AvailablePacks | Measure-Object).Count -gt 0) {
        $filtered = New-Object System.Collections.Generic.List[string]
        $availableLower = $AvailablePacks | ForEach-Object { $_.ToString().ToLower() }

        foreach ($pref in $preferences) {
            # Check for exact match
            if ($availableLower -contains $pref.ToLower()) {
                $filtered.Add($pref)
                continue
            }

            # Check for category match (e.g., 'core_api' matches 'core_api_runtime')
            foreach ($available in $availableLower) {
                if ($available -like "$pref*" -or $pref -like "$available*") {
                    $filtered.Add($pref)
                    break
                }
            }
        }

        Write-Verbose "[RetrievalProfiles] Filtered preferences from $($preferences.Length) to $($filtered.Count) based on available packs"
        return ,$filtered.ToArray()
    }

    # Ensure we always return an array (even single item)
    return ,$preferences
}

function Get-ProfileEvidenceTypes {
    <#
    .SYNOPSIS
        Gets allowed evidence types for a retrieval profile.

    .DESCRIPTION
        Returns the list of evidence types that are allowed/appropriate
        for the specified retrieval profile.

    .PARAMETER ProfileName
        The name of the retrieval profile.

    .OUTPUTS
        System.String[]. Array of allowed evidence type strings.

    .EXAMPLE
        $types = Get-ProfileEvidenceTypes -ProfileName "codegen"
        PS> $types
        code-example
        configuration
        schema-definition
    #>
    [CmdletBinding()]
    [OutputType([array])]
    param(
        [Parameter(Mandatory = $true)]
        [string]$ProfileName
    )

    $profile = Get-RetrievalProfileConfig -ProfileName $ProfileName
    if (-not $profile) {
        Write-Warning "[RetrievalProfiles] Profile not found: $ProfileName"
        return @()
    }

    return $profile.evidenceTypes
}

function New-CustomRetrievalProfile {
    <#
    .SYNOPSIS
        Creates a new custom retrieval profile.

    .DESCRIPTION
        Creates and registers a new custom retrieval profile with the specified configuration.
        The profile is stored in memory and can be used immediately.
        
        Required configuration keys:
        - description: Human-readable description
        - packPreferences: Array of pack type priorities
        - evidenceTypes: Array of allowed evidence types
        
        Optional configuration keys:
        - minTrustTier: Minimum trust level (default: 'medium')
        - requireMultipleSources: Boolean (default: $false)
        - crossPackEnabled: Boolean (default: $true)
        - privateProjectFirst: Boolean (default: $false)
        - config: Hashtable of profile-specific settings

    .PARAMETER ProfileName
        The unique name for the new profile.

    .PARAMETER Config
        Hashtable containing the profile configuration.

    .PARAMETER Force
        If specified, overwrites an existing custom profile with the same name.
        Cannot overwrite built-in profiles.

    .OUTPUTS
        System.Collections.Hashtable. The created profile configuration.

    .EXAMPLE
        $config = @{
            description = 'Custom profile for UI development'
            packPreferences = @('ui-patterns', 'component-library')
            evidenceTypes = @('code-example', 'configuration')
        }
        $profile = New-CustomRetrievalProfile -ProfileName "ui-dev" -Config $config

    .EXAMPLE
        # With additional options
        $config = @{
            description = 'Strict security profile'
            packPreferences = @('security-best-practices', 'audited-patterns')
            evidenceTypes = @('code-example', 'explanation')
            minTrustTier = 'high'
            requireMultipleSources = $true
            config = @{ auditMode = $true }
        }
        $profile = New-CustomRetrievalProfile -ProfileName "secure-dev" -Config $config
    #>
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [Parameter(Mandatory = $true)]
        [string]$ProfileName,

        [Parameter(Mandatory = $true)]
        [hashtable]$Config,

        [Parameter()]
        [switch]$Force
    )

    $normalizedName = $ProfileName.ToLower().Trim()

    # Validate profile name
    if ([string]::IsNullOrWhiteSpace($normalizedName)) {
        throw "Profile name cannot be empty"
    }

    # Check for built-in profile collision
    if ($script:BuiltInProfiles.ContainsKey($normalizedName)) {
        throw "Cannot create custom profile '$normalizedName': name conflicts with built-in profile"
    }

    # Check for existing custom profile
    if ($script:CustomProfiles.ContainsKey($normalizedName) -and -not $Force) {
        throw "Custom profile '$normalizedName' already exists. Use -Force to overwrite."
    }

    # Validate required configuration
    if (-not $Config.ContainsKey('description') -or [string]::IsNullOrWhiteSpace($Config['description'])) {
        throw "Profile configuration must include a 'description' field"
    }

    if (-not $Config.ContainsKey('packPreferences') -or $Config['packPreferences'].Count -eq 0) {
        throw "Profile configuration must include a non-empty 'packPreferences' array"
    }

    if (-not $Config.ContainsKey('evidenceTypes') -or $Config['evidenceTypes'].Count -eq 0) {
        throw "Profile configuration must include a non-empty 'evidenceTypes' array"
    }

    # Validate evidence types
    foreach ($evType in $Config['evidenceTypes']) {
        if ($script:ValidEvidenceTypes -notcontains $evType) {
            Write-Warning "Unknown evidence type: $evType"
        }
    }

    # Validate trust tier if provided
    $minTrustTier = if ($Config.ContainsKey('minTrustTier')) { $Config['minTrustTier'] } else { 'medium' }
    if ($script:ValidTrustTiers -notcontains $minTrustTier) {
        throw "Invalid minTrustTier '$minTrustTier'. Valid values: $($script:ValidTrustTiers -join ', ')"
    }

    # Build the profile
    $profile = [ordered]@{
        name = $normalizedName
        description = $Config['description']
        packPreferences = $Config['packPreferences']
        evidenceTypes = $Config['evidenceTypes']
        minTrustTier = $minTrustTier
        requireMultipleSources = if ($Config.ContainsKey('requireMultipleSources')) { $Config['requireMultipleSources'] } else { $false }
        crossPackEnabled = if ($Config.ContainsKey('crossPackEnabled')) { $Config['crossPackEnabled'] } else { $true }
        privateProjectFirst = if ($Config.ContainsKey('privateProjectFirst')) { $Config['privateProjectFirst'] } else { $false }
        config = if ($Config.ContainsKey('config')) { $Config['config'] } else { @{} }
        metadata = @{
            version = 1
            category = if ($Config.ContainsKey('category')) { $Config['category'] } else { 'custom' }
            useCases = if ($Config.ContainsKey('useCases')) { $Config['useCases'] } else { @() }
            createdAt = [DateTime]::UtcNow.ToString("yyyy-MM-ddTHH:mm:ssZ")
            createdBy = [Environment]::UserName
        }
    }

    # Store the profile
    $script:CustomProfiles[$normalizedName] = $profile

    Write-Verbose "[RetrievalProfiles] Created custom profile: $normalizedName"
    return (Copy-ProfileConfig -Profile $profile)
}

#===============================================================================
# Additional Utility Functions
#===============================================================================

function Get-ProfileMinTrustTier {
    <#
    .SYNOPSIS
        Gets the minimum trust tier for a retrieval profile.

    .DESCRIPTION
        Returns the minimum trust tier required for evidence to be
        considered when using the specified retrieval profile.

    .PARAMETER ProfileName
        The name of the retrieval profile.

    .OUTPUTS
        System.String. The minimum trust tier (e.g., 'high', 'medium').
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory = $true)]
        [string]$ProfileName
    )

    $profile = Get-RetrievalProfileConfig -ProfileName $ProfileName
    if (-not $profile) {
        Write-Warning "[RetrievalProfiles] Profile not found: $ProfileName"
        return 'medium'  # Default fallback
    }

    return $profile.minTrustTier
}

function Test-ProfileRequiresMultipleSources {
    <#
    .SYNOPSIS
        Tests if a profile requires multiple sources.

    .DESCRIPTION
        Returns $true if the profile requires evidence from multiple
        sources for high-confidence answers.

    .PARAMETER ProfileName
        The name of the retrieval profile.

    .OUTPUTS
        System.Boolean. True if multiple sources are required.
    #>
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [Parameter(Mandatory = $true)]
        [string]$ProfileName
    )

    $profile = Get-RetrievalProfileConfig -ProfileName $ProfileName
    if (-not $profile) {
        return $false  # Default fallback
    }

    return $profile.requireMultipleSources
}

function Get-ProfileCategories {
    <#
    .SYNOPSIS
        Gets all profile categories.

    .DESCRIPTION
        Returns a list of all categories used by retrieval profiles,
        including the count of profiles in each category.

    .OUTPUTS
        System.Collections.Hashtable[]. Array of category objects with name and count.
    #>
    [CmdletBinding()]
    [OutputType([array])]
    param()

    $categories = @{}

    # Count built-in profiles by category
    foreach ($profile in $script:BuiltInProfiles.Values) {
        $cat = $profile.metadata.category
        if (-not $categories.ContainsKey($cat)) {
            $categories[$cat] = @{ name = $cat; count = 0; profiles = [System.Collections.Generic.List[string]]::new() }
        }
        $categories[$cat].count++
        $categories[$cat].profiles.Add($profile.name)
    }

    # Count custom profiles by category
    foreach ($profile in $script:CustomProfiles.Values) {
        $cat = $profile.metadata.category
        if (-not $categories.ContainsKey($cat)) {
            $categories[$cat] = @{ name = $cat; count = 0; profiles = [System.Collections.Generic.List[string]]::new() }
        }
        $categories[$cat].count++
        $categories[$cat].profiles.Add($profile.name)
    }

    return $categories.Values | Sort-Object -Property name
}

function Remove-CustomRetrievalProfile {
    <#
    .SYNOPSIS
        Removes a custom retrieval profile.

    .DESCRIPTION
        Removes a custom retrieval profile by name. Built-in profiles
        cannot be removed using this function.

    .PARAMETER ProfileName
        The name of the custom profile to remove.

    .OUTPUTS
        System.Boolean. True if the profile was removed, false if it didn't exist.
    #>
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [Parameter(Mandatory = $true)]
        [string]$ProfileName
    )

    $normalizedName = $ProfileName.ToLower().Trim()

    # Cannot remove built-in profiles
    if ($script:BuiltInProfiles.ContainsKey($normalizedName)) {
        throw "Cannot remove built-in profile: $normalizedName"
    }

    if ($script:CustomProfiles.ContainsKey($normalizedName)) {
        $script:CustomProfiles.Remove($normalizedName)
        Write-Verbose "[RetrievalProfiles] Removed custom profile: $normalizedName"
        return $true
    }

    return $false
}

function Export-RetrievalProfiles {
    <#
    .SYNOPSIS
        Exports all retrieval profiles to JSON.

    .DESCRIPTION
        Exports all retrieval profiles (built-in and custom) to a JSON file
        for backup or sharing purposes.

    .PARAMETER Path
        The file path to export to.

    .PARAMETER IncludeBuiltIn
        If specified, includes built-in profiles in the export.
        Default is to export only custom profiles.

    .OUTPUTS
        System.String. The path to the exported file.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path,

        [Parameter()]
        [switch]$IncludeBuiltIn
    )

    $export = [ordered]@{
        schemaVersion = $script:SchemaVersion
        exportedAt = [DateTime]::UtcNow.ToString("yyyy-MM-ddTHH:mm:ssZ")
        exportedBy = [Environment]::UserName
        profiles = [ordered]@{}
    }

    if ($IncludeBuiltIn) {
        foreach ($name in $script:BuiltInProfiles.Keys | Sort-Object) {
            $export.profiles[$name] = $script:BuiltInProfiles[$name]
        }
    }

    foreach ($name in $script:CustomProfiles.Keys | Sort-Object) {
        $export.profiles[$name] = $script:CustomProfiles[$name]
    }

    $json = $export | ConvertTo-Json -Depth 10
    $json | Out-File -FilePath $Path -Encoding UTF8 -Force

    Write-Verbose "[RetrievalProfiles] Exported profiles to: $Path"
    return $Path
}

function Import-RetrievalProfiles {
    <#
    .SYNOPSIS
        Imports retrieval profiles from JSON.

    .DESCRIPTION
        Imports custom retrieval profiles from a JSON file.
        By default, does not overwrite existing profiles.

    .PARAMETER Path
        The file path to import from.

    .PARAMETER Force
        If specified, overwrites existing custom profiles.

    .OUTPUTS
        System.Int32. The number of profiles imported.
    #>
    [CmdletBinding()]
    [OutputType([int])]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path,

        [Parameter()]
        [switch]$Force
    )

    if (-not (Test-Path -LiteralPath $Path)) {
        throw "Import file not found: $Path"
    }

    $content = Get-Content -LiteralPath $Path -Raw
    $import = Convert-PSObjectToHashtable -InputObject ($content | ConvertFrom-Json)

    if (-not $import.ContainsKey('profiles')) {
        throw "Invalid import file: missing 'profiles' key"
    }

    $imported = 0
    foreach ($name in $import.profiles.Keys) {
        $profileData = $import.profiles[$name]

        # Skip built-in profiles on import (they're already defined)
        if ($script:BuiltInProfiles.ContainsKey($name.ToLower())) {
            Write-Verbose "[RetrievalProfiles] Skipping built-in profile on import: $name"
            continue
        }

        try {
            $config = @{
                description = $profileData.description
                packPreferences = $profileData.packPreferences
                evidenceTypes = $profileData.evidenceTypes
            }

            # Add optional fields if present
            if ($profileData.ContainsKey('minTrustTier')) { $config['minTrustTier'] = $profileData.minTrustTier }
            if ($profileData.ContainsKey('requireMultipleSources')) { $config['requireMultipleSources'] = $profileData.requireMultipleSources }
            if ($profileData.ContainsKey('crossPackEnabled')) { $config['crossPackEnabled'] = $profileData.crossPackEnabled }
            if ($profileData.ContainsKey('privateProjectFirst')) { $config['privateProjectFirst'] = $profileData.privateProjectFirst }
            if ($profileData.ContainsKey('config')) { $config['config'] = $profileData.config }
            if ($profileData.metadata.ContainsKey('category')) { $config['category'] = $profileData.metadata.category }
            if ($profileData.metadata.ContainsKey('useCases')) { $config['useCases'] = $profileData.metadata.useCases }

            New-CustomRetrievalProfile -ProfileName $name -Config $config -Force:$Force | Out-Null
            $imported++
        }
        catch {
            Write-Warning "[RetrievalProfiles] Failed to import profile '$name': $_"
        }
    }

    Write-Verbose "[RetrievalProfiles] Imported $imported profiles from: $Path"
    return $imported
}

#===============================================================================
# Helper Functions
#===============================================================================

function Copy-ProfileConfig {
    <#
    .SYNOPSIS
        Creates a deep copy of a profile configuration.

    .DESCRIPTION
        Internal helper function that creates a deep copy of a profile
        hashtable to prevent external modification of internal state.
        Compatible with PowerShell 5.1 (does not use -AsHashtable).
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [hashtable]$Profile
    )

    # Use JSON round-trip for deep copy, then convert to hashtable
    $json = $Profile | ConvertTo-Json -Depth 10
    $psObject = $json | ConvertFrom-Json
    return (Convert-PSObjectToHashtable -InputObject $psObject)
}

function Convert-PSObjectToHashtable {
    <#
    .SYNOPSIS
        Converts a PSCustomObject to a hashtable recursively.

    .DESCRIPTION
        Helper function for PowerShell 5.1 compatibility.
        Converts PSCustomObject (from ConvertFrom-Json) to hashtable.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [object]$InputObject
    )

    if ($InputObject -eq $null) {
        return $null
    }

    # Handle arrays
    if ($InputObject -is [array]) {
        $result = @()
        foreach ($item in $InputObject) {
            $result += (Convert-PSObjectToHashtable -InputObject $item)
        }
        return $result
    }

    # Handle PSCustomObject (from JSON)
    if ($InputObject -is [System.Management.Automation.PSCustomObject]) {
        $result = @{}
        foreach ($property in $InputObject.PSObject.Properties) {
            $value = $property.Value
            if ($value -is [System.Management.Automation.PSCustomObject] -or $value -is [array]) {
                $value = Convert-PSObjectToHashtable -InputObject $value
            }
            $result[$property.Name] = $value
        }
        return $result
    }

    # Return primitive types as-is
    return $InputObject
}

#===============================================================================
# Module Export (Commented for dot-source compatibility)
# When loaded via Import-Module, all functions are exported by default.
# When dot-sourced, all functions are available in the global scope.
#===============================================================================

# Note: Functions are intentionally not exported via Export-ModuleMember
# to maintain compatibility with both dot-sourcing and Import-Module patterns.
# All public functions defined above are available for use.
