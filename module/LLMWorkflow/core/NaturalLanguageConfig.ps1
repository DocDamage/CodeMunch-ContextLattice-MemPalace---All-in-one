#requires -Version 5.1
<#
.SYNOPSIS
    Natural Language Configuration for LLM Workflow platform (Phase 7).

.DESCRIPTION
    Enables users to describe their desired configuration in natural language
    and have it translated to structured config. Supports the 5-level precedence
    system (defaults -> profile -> project -> env -> args).

.NOTES
    Version: 1.0.0
    Compatible with: PowerShell 5.1+
    Confidence threshold for auto-acceptance: 0.7
#>

Import-Module (Join-Path $script:ModulePath 'ConfigSchema.ps1') -Force -ErrorAction SilentlyContinue
Import-Module (Join-Path $script:ModulePath 'ConfigPath.ps1') -Force -ErrorAction SilentlyContinue

# Wizard State
$script:WizardState = @{
    Active = $false
    CurrentStep = 0
    Questions = @()
    Answers = @{}
    GeneratedConfig = @{}
}

# Config Patterns (expanded from MCP)
$script:ConfigPatterns = @{
    'packs' = @{}
    'schedules' = @{}
    'notifications' = @{}
}

# =============================================================================
# CONFIGURATION TEMPLATES DATABASE
# =============================================================================

$script:ConfigTemplates = @{
    'godot-development' = @{
        description = 'Godot pack with MCP support and developer profile'
        config = @{
            packs = @(
                @{
                    id = 'godot-engine'
                    profile = 'developer'
                    trustTier = 'High'
                }
            )
            execution = @{
                mode = 'interactive'
            }
            logging = @{
                level = 'debug'
                consoleOutput = $true
            }
        }
        tags = @('godot', 'gamedev', 'mcp', 'developer', 'debug')
    }
    'rpgmaker-minimal' = @{
        description = 'RPG Maker pack with minimal profile for lightweight usage'
        config = @{
            packs = @(
                @{
                    id = 'rpgmaker-mz'
                    profile = 'minimal'
                    trustTier = 'Medium'
                }
            )
            execution = @{
                mode = 'interactive'
            }
            logging = @{
                level = 'warning'
                consoleOutput = $false
            }
            memory = @{
                maxContextTokens = 4000
            }
        }
        tags = @('rpgmaker', 'minimal', 'lightweight', 'plugins')
    }
    'blender-pipeline' = @{
        description = 'Blender with Godot pipeline for art-to-engine workflow'
        config = @{
            packs = @(
                @{
                    id = 'blender-engine'
                    profile = 'standard'
                    trustTier = 'High'
                },
                @{
                    id = 'godot-engine'
                    profile = 'standard'
                    trustTier = 'High'
                }
            )
            sync = @{
                mode = 'bidirectional'
                conflictResolution = 'timestamp'
            }
            filters = @{
                includePatterns = @('*.blend', '*.tscn', '*.gltf', '*.glb')
            }
        }
        tags = @('blender', 'godot', 'pipeline', '3d', 'art')
    }
    'team-shared' = @{
        description = 'Team workspace with shared packs and collaborative settings'
        config = @{
            packs = @(
                @{
                    id = 'godot-engine'
                    profile = 'team'
                    trustTier = 'Medium-High'
                },
                @{
                    id = 'rpgmaker-mz'
                    profile = 'team'
                    trustTier = 'Medium-High'
                }
            )
            sync = @{
                mode = 'bidirectional'
                autoSync = $true
                syncInterval = 60
            }
            security = @{
                enableSecretScanning = $true
                requireApprovalFor = @('delete', 'modify', 'execute')
            }
        }
        tags = @('team', 'collaborative', 'shared', 'workspace')
    }
    'private-only' = @{
        description = 'Private project only, no external packs downloaded'
        config = @{
            packs = @()
            sync = @{
                mode = 'manual'
                autoSync = $false
            }
            security = @{
                enableSecretScanning = $true
                encryptionEnabled = $true
                allowedHosts = @()
            }
            execution = @{
                mode = 'mcp-readonly'
            }
        }
        tags = @('private', 'secure', 'offline', 'no-download')
    }
}

# =============================================================================
# INTENT PATTERNS DATABASE
# =============================================================================

$script:IntentPatterns = @{
    'pack-init' = @{
        patterns = @('set up', 'setup', 'initialize', 'init', 'create', 'start with', 'new project', 'begin with')
        confidence = 0.85
    }
    'pack-update' = @{
        patterns = @('update', 'upgrade', 'refresh', 'sync', 'pull latest', 'get new', 'refresh packs')
        confidence = 0.85
    }
    'pack-remove' = @{
        patterns = @('remove', 'delete', 'uninstall', 'stop using', 'drop', 'remove pack')
        confidence = 0.85
    }
    'mode-change' = @{
        patterns = @('switch to', 'change mode', 'set mode', 'run in', 'use mode', 'enable mode')
        confidence = 0.8
    }
    'profile-switch' = @{
        patterns = @('switch profile', 'change profile', 'use profile', 'set profile', 'profile to')
        confidence = 0.85
    }
    'trust-update' = @{
        patterns = @('set trust', 'change trust', 'trust level', 'make trusted', 'make untrusted')
        confidence = 0.8
    }
    'notification-config' = @{
        patterns = @('notify', 'alert', 'send notification', 'when', 'on failure', 'on success')
        confidence = 0.8
    }
    'provider-config' = @{
        patterns = @('use model', 'set provider', 'change model', 'use gpt', 'use claude', 'api key')
        confidence = 0.85
    }
    'filter-config' = @{
        patterns = @('include only', 'exclude', 'filter', 'ignore', 'skip', 'only code', 'only docs')
        confidence = 0.8
    }
}

# =============================================================================
# PACK NAME MAPPINGS (for fuzzy matching)
# =============================================================================

$script:PackNameMappings = @{
    'godot' = 'godot-engine'
    'godot engine' = 'godot-engine'
    'godot 4' = 'godot-engine'
    'godot4' = 'godot-engine'
    'gdscript' = 'godot-engine'
    'rpg maker' = 'rpgmaker-mz'
    'rpgmaker' = 'rpgmaker-mz'
    'rpg maker mz' = 'rpgmaker-mz'
    'rmmz' = 'rpgmaker-mz'
    'blender' = 'blender-engine'
    'blender engine' = 'blender-engine'
    'blender3d' = 'blender-engine'
}

# =============================================================================
# MODE MAPPINGS
# =============================================================================

$script:ModeMappings = @{
    'interactive' = 'interactive'
    'ci' = 'ci'
    'ci mode' = 'ci'
    'watch' = 'watch'
    'watch mode' = 'watch'
    'heal watch' = 'heal-watch'
    'heal-watch' = 'heal-watch'
    'scheduled' = 'scheduled'
    'readonly' = 'mcp-readonly'
    'read only' = 'mcp-readonly'
    'mcp readonly' = 'mcp-readonly'
    'mcp-readonly' = 'mcp-readonly'
    'mutating' = 'mcp-mutating'
    'mcp mutating' = 'mcp-mutating'
    'mcp-mutating' = 'mcp-mutating'
}

# =============================================================================
# TRUST TIER MAPPINGS
# =============================================================================

$script:TrustTierMappings = @{
    'high' = 'High'
    'trusted' = 'High'
    'full trust' = 'High'
    'medium-high' = 'Medium-High'
    'medium high' = 'Medium-High'
    'medium' = 'Medium'
    'normal' = 'Medium'
    'standard' = 'Medium'
    'low' = 'Low'
    'untrusted' = 'Low'
    'quarantined' = 'Quarantined'
    'blocked' = 'Quarantined'
}

# =============================================================================
# PROFILE MAPPINGS
# =============================================================================

$script:ProfileMappings = @{
    'developer' = 'developer'
    'dev' = 'developer'
    'development' = 'developer'
    'production' = 'production'
    'prod' = 'production'
    'minimal' = 'minimal'
    'min' = 'minimal'
    'light' = 'minimal'
    'standard' = 'standard'
    'default' = 'standard'
    'team' = 'team'
    'shared' = 'team'
}


# =============================================================================
# MAIN FUNCTIONS
# =============================================================================

<#
.SYNOPSIS
    Parses natural language text into structured configuration.

.DESCRIPTION
    Main entry point for natural language configuration. Analyzes input text
    and produces a structured configuration object following the 5-level
    precedence system.

.PARAMETER Text
    The natural language description to parse.

.PARAMETER BaseConfig
    Optional existing configuration to merge with.

.PARAMETER Interactive
    If true, starts interactive mode when confidence is low.

.PARAMETER MinConfidence
    Minimum confidence threshold (0-1) for auto-acceptance.

.OUTPUTS
    PSCustomObject with generated configuration and metadata.

.EXAMPLE
    $result = ConvertFrom-NaturalLanguageConfig -Text "set up a godot pack with mcp support and readonly mode"
    PS> $result.Config

.EXAMPLE
    $result = ConvertFrom-NaturalLanguageConfig -Text "I want to work on Godot games with AI assistance"
#>
function ConvertFrom-NaturalLanguageConfig {
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Mandatory = $true, ValueFromPipeline = $true)]
        [string]$Text,

        [Parameter(Mandatory = $false)]
        [hashtable]$BaseConfig = @{},

        [Parameter(Mandatory = $false)]
        [switch]$Interactive,

        [Parameter(Mandatory = $false)]
        [double]$MinConfidence = 0.7
    )

    process {
        Write-Verbose "Parsing natural language config: $Text"
        
        # Identify intent
        $intent = Get-ConfigIntent -Text $Text
        
        # Extract parameters
        $parameters = Get-ConfigParameters -Text $Text
        
        # Generate config based on intent and parameters
        $generatedConfig = Build-ConfigFromIntent -Intent $intent -Parameters $parameters -Text $Text
        
        # Merge with base config if provided
        if ($BaseConfig -and $BaseConfig.Count -gt 0) {
            $generatedConfig = Merge-NLConfig -Generated $generatedConfig -Base $BaseConfig
        }
        
        # Validate generated config
        $validation = Test-GeneratedConfigNL -Config $generatedConfig
        
        # Calculate overall confidence
        $confidence = Measure-NLConfigConfidence -Intent $intent -Parameters $parameters -Validation $validation
        
        # Determine if we need clarification
        $needsClarification = $confidence.Overall -lt $MinConfidence
        
        $result = [PSCustomObject]@{
            Success = $validation.IsValid -or (-not ($validation.Errors | Where-Object { $_.Severity -eq 'error' }))
            Config = $generatedConfig
            Confidence = $confidence
            Intent = $intent
            Parameters = $parameters
            Validation = $validation
            NeedsClarification = $needsClarification
            ClarificationQuestions = if ($needsClarification) { 
                Get-NLConfigClarificationQuestions -Intent $intent -Parameters $parameters -Validation $validation 
            } else { @() }
            OriginalText = $Text
            ParsedAt = (Get-Date -Format 'o')
        }
        
        return $result
    }
}

<#
.SYNOPSIS
    Determines user's intent from natural language text.

.DESCRIPTION
    Analyzes text to determine the primary configuration intent category,
    including confidence score and ambiguity detection.

.PARAMETER Text
    The natural language text to analyze.

.OUTPUTS
    PSCustomObject with intent information including Category, Action, 
    Confidence, IsAmbiguous, and PossibleIntents.

.EXAMPLE
    Get-ConfigIntent -Text "set up a godot pack with mcp support"
    Returns: @{ Category = 'pack-init'; Action = 'install'; Confidence = 0.9; IsAmbiguous = $false }

.EXAMPLE
    Get-ConfigIntent -Text "change mode to readonly"
    Returns: @{ Category = 'mode-change'; Action = 'set-mode'; Confidence = 0.85 }
#>
function Get-ConfigIntent {
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Text
    )

    $textLower = $Text.ToLower()
    $scores = @{}
    $matchedPatterns = @()
    
    # Score each intent category
    foreach ($intentKey in $script:IntentPatterns.Keys) {
        $intentDef = $script:IntentPatterns[$intentKey]
        $score = 0.0
        
        foreach ($pattern in $intentDef.patterns) {
            if ($textLower -match [regex]::Escape($pattern)) {
                $score += $intentDef.confidence
                $matchedPatterns += "$intentKey`:$pattern"
            }
        }
        
        $scores[$intentKey] = [math]::Min($score, 1.0)
    }
    
    # Find highest scoring intent
    $maxScore = 0.0
    $primaryIntent = 'unknown'
    
    foreach ($key in $scores.Keys) {
        if ($scores[$key] -gt $maxScore) {
            $maxScore = $scores[$key]
            $primaryIntent = $key
        }
    }
    
    # Check for ambiguity (multiple intents with similar scores)
    $isAmbiguous = $false
    $possibleIntents = @()
    $threshold = $maxScore * 0.8
    
    foreach ($key in $scores.Keys) {
        if ($scores[$key] -ge $threshold -and $scores[$key] -gt 0.3) {
            $possibleIntents += [PSCustomObject]@{
                Category = $key
                Confidence = $scores[$key]
            }
        }
    }
    
    if ($possibleIntents.Count -gt 1 -and ($maxScore - $possibleIntents[-1].Confidence) -lt 0.2) {
        $isAmbiguous = $true
    }
    
    # Determine specific action
    $action = 'configure'
    switch ($primaryIntent) {
        'pack-init' { $action = 'install' }
        'pack-update' { $action = 'update' }
        'pack-remove' { $action = 'remove' }
        'mode-change' { $action = 'set-mode' }
        'profile-switch' { $action = 'switch-profile' }
        'trust-update' { $action = 'set-trust' }
        'notification-config' { $action = 'configure-notifications' }
        'provider-config' { $action = 'configure-provider' }
        'filter-config' { $action = 'configure-filters' }
    }
    
    return [PSCustomObject]@{
        Category = $primaryIntent
        Action = $action
        Confidence = [math]::Round($maxScore, 3)
        IsAmbiguous = $isAmbiguous
        PossibleIntents = $possibleIntents | Sort-Object -Property Confidence -Descending
        AllScores = $scores
        MatchedPatterns = $matchedPatterns
    }
}

<#
.SYNOPSIS
    Creates configuration from common templates.

.DESCRIPTION
    Generates a complete configuration from predefined templates such as
    'godot-development', 'rpgmaker-minimal', 'blender-pipeline', etc.

.PARAMETER TemplateName
    The name of the template to use.

.PARAMETER Customizations
    Optional hashtable of customizations to apply to the template.

.PARAMETER Validate
    If true, validates the generated configuration against schema.

.OUTPUTS
    PSCustomObject with the generated configuration and metadata.

.EXAMPLE
    New-ConfigFromTemplate -TemplateName 'godot-development'

.EXAMPLE
    New-ConfigFromTemplate -TemplateName 'team-shared' -Customizations @{ 'logging.level' = 'debug' }

.EXAMPLE
    New-ConfigFromTemplate -TemplateName 'private-only' -Validate
#>
function New-ConfigFromTemplate {
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Mandatory = $true)]
        [ValidateSet('godot-development', 'rpgmaker-minimal', 'blender-pipeline', 'team-shared', 'private-only')]
        [string]$TemplateName,

        [Parameter(Mandatory = $false)]
        [hashtable]$Customizations = @{},

        [Parameter(Mandatory = $false)]
        [switch]$Validate
    )

    if (-not $script:ConfigTemplates.ContainsKey($TemplateName)) {
        throw "Unknown template: $TemplateName"
    }

    $template = $script:ConfigTemplates[$TemplateName]
    $config = $template.config.Clone()
    
    # Apply customizations
    foreach ($key in $Customizations.Keys) {
        Set-NestedConfigValue -Config $config -Path $key -Value $Customizations[$key]
    }
    
    # Validate if requested
    $validation = $null
    if ($Validate) {
        $validation = Test-GeneratedConfigNL -Config $config
    }
    
    return [PSCustomObject]@{
        TemplateName = $TemplateName
        Description = $template.description
        Config = $config
        Tags = $template.tags
        Validation = $validation
        GeneratedAt = (Get-Date -Format 'o')
    }
}


<#
.SYNOPSIS
    Generates natural language description from configuration.

.DESCRIPTION
    Creates a human-readable summary of the current configuration,
    highlighting important settings and suggesting improvements.

.PARAMETER Config
    The configuration hashtable to describe.

.PARAMETER Format
    Output format: 'summary', 'detailed', or 'technical'.

.PARAMETER HighlightChanges
    If true, highlights settings that differ from defaults.

.OUTPUTS
    String containing the natural language description.

.EXAMPLE
    ConvertTo-NaturalLanguageConfig -Config $myConfig

.EXAMPLE
    Get-EffectiveConfig | ConvertTo-NaturalLanguageConfig -Format detailed -HighlightChanges
#>
function ConvertTo-NaturalLanguageConfig {
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory = $true, ValueFromPipeline = $true)]
        [hashtable]$Config,

        [Parameter(Mandatory = $false)]
        [ValidateSet('summary', 'detailed', 'technical')]
        [string]$Format = 'summary',

        [Parameter(Mandatory = $false)]
        [switch]$HighlightChanges
    )

    process {
        $parts = @()
        
        # Get defaults for comparison if highlighting changes
        $defaults = $null
        if ($HighlightChanges) {
            $defaults = Get-DefaultConfig
        }
        
        # Describe packs
        if ($Config.packs -and $Config.packs.Count -gt 0) {
            $packDescriptions = @()
            foreach ($pack in $Config.packs) {
                $packId = if ($pack.id) { $pack.id } else { $pack }
                $profile = $pack.profile
                $trust = $pack.trustTier
                
                $desc = "'$packId'"
                if ($profile) { $desc += " with $profile profile" }
                if ($trust) { $desc += " ($trust trust)" }
                
                $packDescriptions += $desc
            }
            $parts += "This configuration includes the following packs: $($packDescriptions -join ', ')."
        }
        elseif ($Config.ContainsKey('packs') -and $Config.packs.Count -eq 0) {
            $parts += "This is a private-only configuration with no external packs."
        }
        
        # Describe execution mode
        if ($Config.execution -and $Config.execution.mode) {
            $modeDesc = switch ($Config.execution.mode) {
                'interactive' { 'interactive mode for manual use' }
                'ci' { 'CI mode for automated builds' }
                'watch' { 'watch mode for continuous monitoring' }
                'heal-watch' { 'heal-watch mode for self-healing operations' }
                'scheduled' { 'scheduled execution mode' }
                'mcp-readonly' { 'MCP readonly mode for safe operations' }
                'mcp-mutating' { 'MCP mutating mode for full control' }
                default { "$($Config.execution.mode) mode" }
            }
            $parts += "It runs in $modeDesc."
        }
        
        # Describe provider settings
        if ($Config.provider) {
            if ($Config.provider.model) {
                $parts += "Using the '$($Config.provider.model)' model"
                if ($Config.provider.type) {
                    $parts[-1] += " via $($Config.provider.type)"
                }
                $parts[-1] += "."
            }
            if ($null -ne $Config.provider.temperature) {
                $tempDesc = if ($Config.provider.temperature -gt 0.7) { 'creative' } else { 'focused' }
                $parts += "Temperature is set to $($Config.provider.temperature) for $tempDesc responses."
            }
        }
        
        # Describe sync settings
        if ($Config.sync -and $Config.sync.mode) {
            $syncDesc = switch ($Config.sync.mode) {
                'bidirectional' { 'bidirectional synchronization' }
                'upload-only' { 'upload-only synchronization' }
                'download-only' { 'download-only synchronization' }
                'manual' { 'manual synchronization only' }
                default { "$($Config.sync.mode) sync" }
            }
            $autoDesc = if ($Config.sync.autoSync -eq $true) { 'automatic' } else { 'manual' }
            $parts += "Sync is configured for $syncDesc in $autoDesc mode."
        }
        
        # Describe logging
        if ($Config.logging -and $Config.logging.level) {
            $consoleDesc = if ($Config.logging.consoleOutput -eq $true) { 'with console output' } else { 'without console output' }
            $parts += "Logging level is set to '$($Config.logging.level)' $consoleDesc."
        }
        
        # Describe security settings
        if ($Config.security) {
            if ($Config.security.encryptionEnabled -eq $true) {
                $parts += "Data encryption is enabled."
            }
            if ($Config.security.enableSecretScanning -eq $true) {
                $parts += "Secret scanning is active for security."
            }
        }
        
        # Format output
        switch ($Format) {
            'summary' {
                return $parts -join ' '
            }
            'detailed' {
                $result = "Configuration Summary:`n"
                $result += "=" * 50 + "`n"
                foreach ($part in $parts) {
                    $result += "  - $part`n"
                }
                
                # Add recommendations
                $recommendations = Get-ConfigSuggestion -Config $Config -AsObjects
                if ($recommendations.Count -gt 0) {
                    $result += "`nRecommendations:`n"
                    foreach ($rec in $recommendations | Select-Object -First 3) {
                        $result += "  [!] $($rec.Message)`n"
                    }
                }
                return $result
            }
            'technical' {
                return ($Config | ConvertTo-Json -Depth 5)
            }
        }
    }
}

<#
.SYNOPSIS
    Suggests configuration improvements.

.DESCRIPTION
    Analyzes current configuration and identifies missing recommended settings,
    providing natural language suggestions for improvements.

.PARAMETER Config
    The configuration to analyze. Uses effective config if not provided.

.PARAMETER MinSeverity
    Minimum severity level to include: 'info', 'warning', or 'critical'.

.PARAMETER AsObjects
    If true, returns suggestion objects instead of strings.

.OUTPUTS
    Array of suggestion strings or objects depending on AsObjects parameter.

.EXAMPLE
    Get-ConfigSuggestion

.EXAMPLE
    Get-ConfigSuggestion -Config $myConfig -MinSeverity warning

.EXAMPLE
    $suggestions = Get-ConfigSuggestion -AsObjects
#>
function Get-ConfigSuggestion {
    [CmdletBinding()]
    [OutputType([array])]
    param(
        [Parameter(Mandatory = $false)]
        [hashtable]$Config = $null,

        [Parameter(Mandatory = $false)]
        [ValidateSet('info', 'warning', 'critical')]
        [string]$MinSeverity = 'info',

        [Parameter(Mandatory = $false)]
        [switch]$AsObjects
    )

    # Get config if not provided
    if (-not $Config) {
        $Config = Get-EffectiveConfig -NoCache
    }
    
    $suggestions = @()
    $defaults = Get-DefaultConfig
    
    # Check for API key
    if (-not $Config.provider -or -not $Config.provider.apiKey) {
        $suggestions += [PSCustomObject]@{
            Severity = 'critical'
            Category = 'provider'
            Setting = 'apiKey'
            Message = "No API key configured. Set LLMWF_PROVIDER_APIKEY environment variable or add to profile config."
            Recommendation = "export LLMWF_PROVIDER_APIKEY='your-api-key'"
        }
    }
    
    # Check for packs when not in private mode
    if ((-not $Config.packs -or $Config.packs.Count -eq 0) -and 
        ($Config.execution.mode -ne 'mcp-readonly' -and $Config.execution.mode -ne 'private-only')) {
        $suggestions += [PSCustomObject]@{
            Severity = 'warning'
            Category = 'packs'
            Setting = 'packs'
            Message = "No packs configured. Consider adding engine packs for better context."
            Recommendation = "Use 'New-ConfigFromTemplate -TemplateName godot-development' to get started."
        }
    }
    
    # Check security settings
    if ($Config.security) {
        if ($Config.security.encryptionEnabled -ne $true -and $Config.packs -and $Config.packs.Count -gt 0) {
            $suggestions += [PSCustomObject]@{
                Severity = 'warning'
                Category = 'security'
                Setting = 'encryptionEnabled'
                Message = "Data encryption is disabled. Consider enabling for sensitive projects."
                Recommendation = "Set security.encryptionEnabled to true in your config."
            }
        }
        
        if ($Config.security.enableSecretScanning -ne $true) {
            $suggestions += [PSCustomObject]@{
                Severity = 'warning'
                Category = 'security'
                Setting = 'enableSecretScanning'
                Message = "Secret scanning is disabled. Enable to prevent accidental credential exposure."
                Recommendation = "Set security.enableSecretScanning to true."
            }
        }
    }
    
    # Check logging settings
    if ($Config.logging) {
        if ($Config.logging.level -eq 'debug' -and $Config.execution.mode -eq 'production') {
            $suggestions += [PSCustomObject]@{
                Severity = 'warning'
                Category = 'logging'
                Setting = 'level'
                Message = "Debug logging enabled in production mode may impact performance."
                Recommendation = "Consider setting logging.level to 'info' or 'warning' for production."
            }
        }
    }
    
    # Check sync settings
    if ($Config.sync -and $Config.sync.autoSync -eq $true) {
        if ($Config.sync.syncInterval -lt 60) {
            $suggestions += [PSCustomObject]@{
                Severity = 'info'
                Category = 'sync'
                Setting = 'syncInterval'
                Message = "Auto-sync interval is very frequent ($($Config.sync.syncInterval)s). This may increase API usage."
                Recommendation = "Consider increasing sync.syncInterval to 300 (5 minutes) or more."
            }
        }
    }
    
    # Check memory settings
    if ($Config.memory) {
        if ($Config.memory.maxContextTokens -gt 16000) {
            $suggestions += [PSCustomObject]@{
                Severity = 'info'
                Category = 'memory'
                Setting = 'maxContextTokens'
                Message = "High context token limit ($($Config.memory.maxContextTokens)) may increase costs."
                Recommendation = "Verify this setting matches your actual needs."
            }
        }
    }
    
    # Check execution settings
    if ($Config.execution) {
        if ($Config.execution.mode -eq 'mcp-mutating' -and (-not $Config.security -or $Config.security.requireApprovalFor -notcontains 'modify')) {
            $suggestions += [PSCustomObject]@{
                Severity = 'critical'
                Category = 'security'
                Setting = 'requireApprovalFor'
                Message = "Mutating MCP mode without approval requirements is potentially dangerous."
                Recommendation = "Add 'modify' to security.requireApprovalFor array."
            }
        }
    }
    
    # Filter by severity
    $severityOrder = @{ 'critical' = 3; 'warning' = 2; 'info' = 1 }
    $minLevel = $severityOrder[$MinSeverity]
    $suggestions = $suggestions | Where-Object { $severityOrder[$_.Severity] -ge $minLevel }
    
    if ($AsObjects) {
        return $suggestions
    }
    else {
        return $suggestions | ForEach-Object { "[$($_.Severity.ToUpper())] $($_.Message)`n    -> $($_.Recommendation)" }
    }
}

<#
.SYNOPSIS
    Tests if a natural language input is valid configuration text.

.DESCRIPTION
    Validates natural language input and returns confidence score,
    identifies unknown terms, and suggests corrections.

.PARAMETER Text
    The natural language text to test.

.PARAMETER SuggestCorrections
    If true, includes suggested corrections for unknown terms.

.PARAMETER ReturnDetails
    If true, returns detailed result object instead of boolean.

.OUTPUTS
    Boolean or PSCustomObject depending on ReturnDetails parameter.

.EXAMPLE
    Test-ConfigNaturalLanguage -Text "set up godot pack"
    True

.EXAMPLE
    Test-ConfigNaturalLanguage -Text "xyz unknown term" -ReturnDetails
    Returns detailed analysis with unknown terms and suggestions
#>
function Test-ConfigNaturalLanguage {
    [CmdletBinding()]
    [OutputType([object])]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Text,

        [Parameter(Mandatory = $false)]
        [switch]$SuggestCorrections,

        [Parameter(Mandatory = $false)]
        [switch]$ReturnDetails
    )

    $textLower = $Text.ToLower()
    $words = $textLower -split '\s+' | Where-Object { $_.Length -gt 2 }
    
    $knownTerms = @()
    $unknownTerms = @()
    $suggestions = @()
    
    # Build vocabulary of known terms
    $vocabulary = @()
    $vocabulary += $script:IntentPatterns.Values.patterns | ForEach-Object { $_ }
    $vocabulary += $script:PackNameMappings.Keys
    $vocabulary += $script:ModeMappings.Keys
    $vocabulary += $script:TrustTierMappings.Keys
    $vocabulary += $script:ProfileMappings.Keys
    $vocabulary += @('pack', 'config', 'set', 'get', 'enable', 'disable', 'with', 'and', 'for', 'the', 'use')
    
    foreach ($word in $words) {
        $isKnown = $false
        foreach ($term in $vocabulary) {
            if ($word -eq $term -or $term -match $word -or $word -match $term) {
                $isKnown = $true
                $knownTerms += $word
                break
            }
        }
        if (-not $isKnown) {
            $unknownTerms += $word
        }
    }
    
    # Calculate confidence
    $totalWords = $words.Count
    $knownCount = $knownTerms.Count
    $confidence = if ($totalWords -gt 0) { $knownCount / $totalWords } else { 0 }
    
    # Generate suggestions for unknown terms if requested
    if ($SuggestCorrections -and $unknownTerms.Count -gt 0) {
        foreach ($unknown in $unknownTerms) {
            $bestMatch = Find-BestFuzzyMatch -Input $unknown -Candidates $vocabulary -Threshold 0.6
            if ($bestMatch) {
                $suggestions += [PSCustomObject]@{
                    Unknown = $unknown
                    Suggested = $bestMatch.Match
                    Confidence = $bestMatch.Score
                }
            }
        }
    }
    
    # Get intent to include in results
    $intent = Get-ConfigIntent -Text $Text
    
    $result = [PSCustomObject]@{
        IsValid = ($confidence -gt 0.5 -and $intent.Confidence -gt 0.5)
        Confidence = [math]::Round($confidence, 3)
        IntentConfidence = $intent.Confidence
        KnownTerms = $knownTerms
        UnknownTerms = $unknownTerms
        UnknownTermCount = $unknownTerms.Count
        Suggestions = $suggestions
        DetectedIntent = $intent.Category
        IsAmbiguous = $intent.IsAmbiguous
    }
    
    if ($ReturnDetails) {
        return $result
    }
    else {
        return $result.IsValid
    }
}


# =============================================================================
# HELPER FUNCTIONS
# =============================================================================

<#
.SYNOPSIS
    Extracts configuration parameters from natural language text.

.DESCRIPTION
    Identifies and extracts specific configuration values from text,
    including pack names, modes, profiles, trust tiers, and other settings.

.PARAMETER Text
    The natural language text to analyze.

.OUTPUTS
    Hashtable of extracted parameters.
#>
function Get-ConfigParameters {
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Text
    )

    $textLower = $Text.ToLower()
    $params = @{}
    
    # Extract pack names with fuzzy matching
    foreach ($mapping in $script:PackNameMappings.GetEnumerator()) {
        if ($textLower -match [regex]::Escape($mapping.Key)) {
            $params.PackId = $mapping.Value
            $params.PackConfidence = 0.95
            break
        }
    }
    
    # Extract execution mode
    foreach ($mapping in $script:ModeMappings.GetEnumerator()) {
        if ($textLower -match [regex]::Escape($mapping.Key)) {
            $params.ExecutionMode = $mapping.Value
            $params.ModeConfidence = 0.9
            break
        }
    }
    
    # Extract trust tier
    foreach ($mapping in $script:TrustTierMappings.GetEnumerator()) {
        if ($textLower -match [regex]::Escape($mapping.Key)) {
            $params.TrustTier = $mapping.Value
            $params.TrustConfidence = 0.9
            break
        }
    }
    
    # Extract profile
    foreach ($mapping in $script:ProfileMappings.GetEnumerator()) {
        if ($textLower -match [regex]::Escape($mapping.Key)) {
            $params.Profile = $mapping.Value
            $params.ProfileConfidence = 0.9
            break
        }
    }
    
    # Extract MCP-related settings
    if ($textLower -match 'mcp') {
        $params.MCPEnabled = $true
    }
    if ($textLower -match 'readonly|read.only|read-only') {
        $params.ReadOnlyMode = $true
    }
    
    # Extract provider settings
    if ($textLower -match 'openai|gpt') {
        $params.ProviderType = 'openai'
    }
    elseif ($textLower -match 'claude|anthropic') {
        $params.ProviderType = 'anthropic'
    }
    elseif ($textLower -match 'azure') {
        $params.ProviderType = 'azure-openai'
    }
    elseif ($textLower -match 'local') {
        $params.ProviderType = 'local'
    }
    
    # Extract model
    if ($textLower -match 'gpt-4o|gpt4o') {
        $params.Model = 'gpt-4o'
    }
    elseif ($textLower -match 'gpt-4|gpt4') {
        $params.Model = 'gpt-4'
    }
    elseif ($textLower -match 'gpt-3|gpt3') {
        $params.Model = 'gpt-3.5-turbo'
    }
    elseif ($textLower -match 'claude 3|claude3') {
        $params.Model = 'claude-3-opus-20240229'
    }
    
    # Extract temperature
    if ($textLower -match 'temperature\s+(?:of\s+)?(\d+\.?\d*)') {
        $params.Temperature = [double]$matches[1]
    }
    elseif ($textLower -match 'high\s+temperature|creative|more creative') {
        $params.Temperature = 0.9
    }
    elseif ($textLower -match 'low\s+temperature|focused|more focused') {
        $params.Temperature = 0.2
    }
    elseif ($textLower -match 'balanced\s+temperature') {
        $params.Temperature = 0.7
    }
    
    # Extract sync settings
    if ($textLower -match 'bidirectional|bidirectional\s+sync') {
        $params.SyncMode = 'bidirectional'
    }
    elseif ($textLower -match 'upload\s+only') {
        $params.SyncMode = 'upload-only'
    }
    elseif ($textLower -match 'download\s+only') {
        $params.SyncMode = 'download-only'
    }
    elseif ($textLower -match 'manual\s+sync|no\s+auto\s+sync') {
        $params.SyncMode = 'manual'
        $params.AutoSync = $false
    }
    
    # Extract logging level
    if ($textLower -match 'debug\s+logging|log\s+debug') {
        $params.LogLevel = 'debug'
    }
    elseif ($textLower -match 'verbose\s+logging|log\s+verbose') {
        $params.LogLevel = 'info'
    }
    elseif ($textLower -match 'warning\s+only|log\s+warnings') {
        $params.LogLevel = 'warning'
    }
    elseif ($textLower -match 'quiet|silent|no\s+logs') {
        $params.LogLevel = 'error'
        $params.ConsoleOutput = $false
    }
    
    # Extract security settings
    if ($textLower -match 'encrypt|encryption') {
        $params.EncryptionEnabled = $true
    }
    if ($textLower -match 'secret\s+scan|scan\s+secrets') {
        $params.SecretScanning = $true
    }
    if ($textLower -match 'private|no\s+download|do not download') {
        $params.PrivateOnly = $true
    }
    
    return $params
}

<#
.SYNOPSIS
    Builds configuration from intent and parameters.

.DESCRIPTION
    Internal function that constructs the final configuration hashtable
    based on the detected intent and extracted parameters.

.PARAMETER Intent
    The detected intent object.

.PARAMETER Parameters
    The extracted parameters hashtable.

.PARAMETER Text
    The original natural language text.

.OUTPUTS
    Hashtable containing the built configuration.
#>
function Build-ConfigFromIntent {
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [Parameter(Mandatory = $true)]
        [PSCustomObject]$Intent,

        [Parameter(Mandatory = $true)]
        [hashtable]$Parameters,

        [Parameter(Mandatory = $true)]
        [string]$Text
    )

    $config = @{}
    
    switch ($Intent.Category) {
        'pack-init' {
            $config = Build-PackInitConfig -Parameters $Parameters
        }
        'pack-update' {
            $config = Build-PackUpdateConfig -Parameters $Parameters
        }
        'pack-remove' {
            $config = Build-PackRemoveConfig -Parameters $Parameters
        }
        'mode-change' {
            $config = Build-ModeChangeConfig -Parameters $Parameters
        }
        'profile-switch' {
            $config = Build-ProfileSwitchConfig -Parameters $Parameters
        }
        'trust-update' {
            $config = Build-TrustUpdateConfig -Parameters $Parameters
        }
        'provider-config' {
            $config = Build-ProviderConfig -Parameters $Parameters
        }
        'notification-config' {
            $config = Build-NotificationConfig -Parameters $Parameters -Text $Text
        }
        'filter-config' {
            $config = Build-FilterConfig -Parameters $Parameters -Text $Text
        }
        default {
            $config = Build-GenericConfig -Parameters $Parameters
        }
    }
    
    # Add metadata
    $config['_source'] = 'natural-language'
    $config['_parsedAt'] = (Get-Date -Format 'o')
    
    return $config
}

# Config builder helper functions
function Build-PackInitConfig {
    param([hashtable]$Parameters)
    $config = @{
        packs = @()
    }
    
    if ($Parameters.PackId) {
        $packConfig = @{
            id = $Parameters.PackId
        }
        if ($Parameters.Profile) { $packConfig.profile = $Parameters.Profile }
        if ($Parameters.TrustTier) { $packConfig.trustTier = $Parameters.TrustTier }
        $config.packs += $packConfig
    }
    
    if ($Parameters.ExecutionMode) {
        $config.execution = @{ mode = $Parameters.ExecutionMode }
    }
    
    if ($Parameters.ProviderType -or $Parameters.Model) {
        $config.provider = @{}
        if ($Parameters.ProviderType) { $config.provider.type = $Parameters.ProviderType }
        if ($Parameters.Model) { $config.provider.model = $Parameters.Model }
        if ($Parameters.Temperature) { $config.provider.temperature = $Parameters.Temperature }
    }
    
    if ($Parameters.SyncMode) {
        $config.sync = @{ mode = $Parameters.SyncMode }
        if ($Parameters.AutoSync -ne $null) { $config.sync.autoSync = $Parameters.AutoSync }
    }
    
    return $config
}

function Build-PackUpdateConfig {
    param([hashtable]$Parameters)
    return @{
        action = 'update-packs'
        packFilter = if ($Parameters.PackId) { $Parameters.PackId } else { '*' }
        sync = @{ autoSync = $true }
    }
}

function Build-PackRemoveConfig {
    param([hashtable]$Parameters)
    return @{
        action = 'remove-packs'
        packsToRemove = if ($Parameters.PackId) { @($Parameters.PackId) } else { @() }
    }
}

function Build-ModeChangeConfig {
    param([hashtable]$Parameters)
    $config = @{}
    
    if ($Parameters.ExecutionMode) {
        $config.execution = @{ mode = $Parameters.ExecutionMode }
    }
    elseif ($Parameters.ReadOnlyMode) {
        $config.execution = @{ mode = 'mcp-readonly' }
    }
    
    return $config
}

function Build-ProfileSwitchConfig {
    param([hashtable]$Parameters)
    $config = @{}
    
    if ($Parameters.Profile) {
        $config.profileName = $Parameters.Profile
        switch ($Parameters.Profile) {
            'developer' {
                $config.logging = @{ level = 'debug'; consoleOutput = $true }
            }
            'production' {
                $config.logging = @{ level = 'warning'; consoleOutput = $false }
                $config.execution = @{ mode = 'ci' }
            }
            'minimal' {
                $config.logging = @{ level = 'error'; consoleOutput = $false }
                $config.memory = @{ maxContextTokens = 4000 }
            }
        }
    }
    
    return $config
}

function Build-TrustUpdateConfig {
    param([hashtable]$Parameters)
    $config = @{
        action = 'update-trust'
    }
    
    if ($Parameters.PackId) {
        $config.targetPack = $Parameters.PackId
    }
    if ($Parameters.TrustTier) {
        $config.trustTier = $Parameters.TrustTier
    }
    
    return $config
}

function Build-ProviderConfig {
    param([hashtable]$Parameters)
    $config = @{
        provider = @{}
    }
    
    if ($Parameters.ProviderType) { $config.provider.type = $Parameters.ProviderType }
    if ($Parameters.Model) { $config.provider.model = $Parameters.Model }
    if ($Parameters.Temperature) { $config.provider.temperature = $Parameters.Temperature }
    
    return $config
}

function Build-NotificationConfig {
    param([hashtable]$Parameters, [string]$Text)
    $textLower = $Text.ToLower()
    $config = @{
        notifications = @()
    }
    
    $notification = @{
        enabled = $true
    }
    
    if ($textLower -match 'slack') {
        $notification.type = 'webhook'
        $notification.provider = 'slack'
        $notification.url = '${SLACK_WEBHOOK_URL}'
    }
    elseif ($textLower -match 'discord') {
        $notification.type = 'webhook'
        $notification.provider = 'discord'
        $notification.url = '${DISCORD_WEBHOOK_URL}'
    }
    elseif ($textLower -match 'email') {
        $notification.type = 'email'
        $notification.recipient = '${NOTIFICATION_EMAIL}'
    }
    else {
        $notification.type = 'webhook'
    }
    
    if ($textLower -match 'on\s+failure|when.*fail|if.*error') {
        $notification.event = 'execution.failed'
    }
    elseif ($textLower -match 'on\s+success|when.*complete|when.*done') {
        $notification.event = 'execution.completed'
    }
    elseif ($textLower -match 'health|degraded') {
        $notification.event = 'health.degraded'
    }
    else {
        $notification.event = 'execution.completed'
    }
    
    $config.notifications += $notification
    return $config
}

function Build-FilterConfig {
    param([hashtable]$Parameters, [string]$Text)
    $textLower = $Text.ToLower()
    $config = @{
        filters = @{
            includePatterns = @()
            excludePatterns = @()
        }
    }
    
    if ($textLower -match 'include\s+(.+)') {
        $includePart = $matches[1]
        $patterns = [regex]::Matches($includePart, '[\*\w\/]+\.\w+|\*\.\w+')
        foreach ($pattern in $patterns) {
            $config.filters.includePatterns += $pattern.Value
        }
    }
    
    if ($textLower -match 'exclude\s+(.+)|ignore\s+(.+)') {
        $excludePart = if ($matches[1]) { $matches[1] } else { $matches[2] }
        $patterns = [regex]::Matches($excludePart, '[\*\w\/]+\.\w+|\*\.\w+')
        foreach ($pattern in $patterns) {
            $config.filters.excludePatterns += $pattern.Value
        }
    }
    
    if ($textLower -match 'code|source') {
        $config.filters.useCase = 'code-extraction'
    }
    elseif ($textLower -match 'doc') {
        $config.filters.useCase = 'documentation-only'
    }
    elseif ($textLower -match 'test') {
        $config.filters.useCase = 'tests-only'
    }
    
    return $config
}

function Build-GenericConfig {
    param([hashtable]$Parameters)
    $config = @{}
    
    if ($Parameters.PackId) {
        $config.packs = @(@{ id = $Parameters.PackId })
        if ($Parameters.Profile) { $config.packs[0].profile = $Parameters.Profile }
        if ($Parameters.TrustTier) { $config.packs[0].trustTier = $Parameters.TrustTier }
    }
    
    if ($Parameters.ExecutionMode) {
        $config.execution = @{ mode = $Parameters.ExecutionMode }
    }
    
    if ($Parameters.ProviderType -or $Parameters.Model -or $Parameters.Temperature) {
        $config.provider = @{}
        if ($Parameters.ProviderType) { $config.provider.type = $Parameters.ProviderType }
        if ($Parameters.Model) { $config.provider.model = $Parameters.Model }
        if ($Parameters.Temperature) { $config.provider.temperature = $Parameters.Temperature }
    }
    
    if ($Parameters.LogLevel -or $Parameters.ConsoleOutput -ne $null) {
        $config.logging = @{}
        if ($Parameters.LogLevel) { $config.logging.level = $Parameters.LogLevel }
        if ($Parameters.ConsoleOutput -ne $null) { $config.logging.consoleOutput = $Parameters.ConsoleOutput }
    }
    
    if ($Parameters.SyncMode -or $Parameters.AutoSync -ne $null) {
        $config.sync = @{}
        if ($Parameters.SyncMode) { $config.sync.mode = $Parameters.SyncMode }
        if ($Parameters.AutoSync -ne $null) { $config.sync.autoSync = $Parameters.AutoSync }
    }
    
    if ($Parameters.EncryptionEnabled -or $Parameters.SecretScanning -ne $null) {
        $config.security = @{}
        if ($Parameters.EncryptionEnabled) { $config.security.encryptionEnabled = $true }
        if ($Parameters.SecretScanning) { $config.security.enableSecretScanning = $true }
    }
    
    if ($Parameters.PrivateOnly) {
        $config.sync = @{ mode = 'manual'; autoSync = $false }
        $config.security = @{ enableSecretScanning = $true; encryptionEnabled = $true }
    }
    
    return $config
}


<#
.SYNOPSIS
    Merges generated config with base config.

.DESCRIPTION
    Internal helper to merge generated configuration with existing base config.
#>
function Merge-NLConfig {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [hashtable]$Generated,

        [Parameter(Mandatory = $true)]
        [hashtable]$Base
    )

    $result = $Base.Clone()
    
    foreach ($key in $Generated.Keys) {
        if ($key.StartsWith('_')) { continue }
        
        $genValue = $Generated[$key]
        
        if ($result.ContainsKey($key) -and $result[$key] -is [hashtable] -and $genValue -is [hashtable]) {
            $result[$key] = Merge-NLConfig -Generated $genValue -Base $result[$key]
        }
        else {
            $result[$key] = $genValue
        }
    }
    
    return $result
}

<#
.SYNOPSIS
    Validates generated configuration.

.DESCRIPTION
    Internal helper to validate generated configuration structure and values.
#>
function Test-GeneratedConfigNL {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [hashtable]$Config
    )

    $errors = @()
    $warnings = @()
    
    # Remove metadata keys for validation
    $cleanConfig = @{}
    foreach ($key in $Config.Keys) {
        if (-not $key.StartsWith('_')) {
            $cleanConfig[$key] = $Config[$key]
        }
    }
    
    # Check for empty non-metadata config
    if ($cleanConfig.Count -eq 0) {
        $warnings += [PSCustomObject]@{
            Path = ''
            Message = 'Configuration contains no settings'
            Severity = 'warning'
        }
    }
    
    # Validate execution mode if present
    if ($cleanConfig.execution -and $cleanConfig.execution.mode) {
        $validModes = Get-ValidExecutionModes
        if ($validModes -notcontains $cleanConfig.execution.mode) {
            $errors += [PSCustomObject]@{
                Path = 'execution.mode'
                Message = "Invalid execution mode: '$($cleanConfig.execution.mode)'. Valid modes: $($validModes -join ', ')"
                Severity = 'error'
            }
        }
    }
    
    # Validate provider settings if present
    if ($cleanConfig.provider) {
        $validProviders = @('openai', 'azure-openai', 'anthropic', 'local', 'custom')
        if ($cleanConfig.provider.type -and $validProviders -notcontains $cleanConfig.provider.type) {
            $errors += [PSCustomObject]@{
                Path = 'provider.type'
                Message = "Invalid provider type: '$($cleanConfig.provider.type)'. Valid types: $($validProviders -join ', ')"
                Severity = 'error'
            }
        }
        
        if ($null -ne $cleanConfig.provider.temperature) {
            if ($cleanConfig.provider.temperature -lt 0 -or $cleanConfig.provider.temperature -gt 2) {
                $errors += [PSCustomObject]@{
                    Path = 'provider.temperature'
                    Message = "Temperature must be between 0 and 2, got: $($cleanConfig.provider.temperature)"
                    Severity = 'error'
                }
            }
        }
    }
    
    # Validate sync mode if present
    if ($cleanConfig.sync -and $cleanConfig.sync.mode) {
        $validSyncModes = @('bidirectional', 'upload-only', 'download-only', 'manual')
        if ($validSyncModes -notcontains $cleanConfig.sync.mode) {
            $errors += [PSCustomObject]@{
                Path = 'sync.mode'
                Message = "Invalid sync mode: '$($cleanConfig.sync.mode)'. Valid modes: $($validSyncModes -join ', ')"
                Severity = 'error'
            }
        }
    }
    
    # Validate logging level if present
    if ($cleanConfig.logging -and $cleanConfig.logging.level) {
        $validLevels = @('debug', 'info', 'warning', 'error', 'critical')
        if ($validLevels -notcontains $cleanConfig.logging.level) {
            $errors += [PSCustomObject]@{
                Path = 'logging.level'
                Message = "Invalid log level: '$($cleanConfig.logging.level)'. Valid levels: $($validLevels -join ', ')"
                Severity = 'error'
            }
        }
    }
    
    # Validate trust tier if present
    if ($cleanConfig.trustTier) {
        $validTiers = @('High', 'Medium-High', 'Medium', 'Low', 'Quarantined')
        if ($validTiers -notcontains $cleanConfig.trustTier) {
            $warnings += [PSCustomObject]@{
                Path = 'trustTier'
                Message = "Unusual trust tier value: '$($cleanConfig.trustTier)'. Standard tiers: $($validTiers -join ', ')"
                Severity = 'warning'
            }
        }
    }
    
    # Validate pack IDs if present
    if ($cleanConfig.packs) {
        $validPacks = @('godot-engine', 'rpgmaker-mz', 'blender-engine')
        foreach ($pack in $cleanConfig.packs) {
            $packId = if ($pack -is [hashtable]) { $pack.id } else { $pack }
            if ($packId -and $validPacks -notcontains $packId) {
                $warnings += [PSCustomObject]@{
                    Path = 'packs'
                    Message = "Unknown pack ID: '$packId'. Known packs: $($validPacks -join ', ')"
                    Severity = 'warning'
                }
            }
        }
    }
    
    $isValid = -not ($errors | Where-Object { $_.Severity -eq 'error' })
    
    return [PSCustomObject]@{
        IsValid = $isValid
        Errors = $errors
        Warnings = $warnings
        ErrorCount = ($errors | Where-Object { $_.Severity -eq 'error' }).Count
        WarningCount = $warnings.Count
        ValidatedAt = (Get-Date -Format 'o')
    }
}

<#
.SYNOPSIS
    Calculates confidence score for configuration.

.DESCRIPTION
    Internal helper to compute overall confidence based on intent,
    parameters, and validation results.
#>
function Measure-NLConfigConfidence {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $false)]
        [PSCustomObject]$Intent,

        [Parameter(Mandatory = $false)]
        [hashtable]$Parameters,

        [Parameter(Mandatory = $false)]
        [PSCustomObject]$Validation
    )

    $scores = @{}
    
    # Intent confidence
    if ($Intent) {
        $scores.Intent = $Intent.Confidence
    }
    else {
        $scores.Intent = 0.0
    }
    
    # Parameter extraction confidence
    if ($Parameters -and $Parameters.Count -gt 0) {
        $paramScores = @()
        foreach ($key in @('PackConfidence', 'ModeConfidence', 'TrustConfidence', 'ProfileConfidence')) {
            if ($Parameters.ContainsKey($key)) {
                $paramScores += $Parameters[$key]
            }
        }
        if ($paramScores.Count -gt 0) {
            $scores.Parameters = ($paramScores | Measure-Object -Average).Average
        }
        else {
            $expectedParams = 3
            $scores.Parameters = [math]::Min($Parameters.Count / $expectedParams, 1.0) * 0.8
        }
    }
    else {
        $scores.Parameters = 0.0
    }
    
    # Validation confidence
    if ($Validation) {
        $errorPenalty = $Validation.ErrorCount * 0.25
        $warningPenalty = $Validation.WarningCount * 0.05
        $scores.Validation = [math]::Max(0.0, 1.0 - $errorPenalty - $warningPenalty)
    }
    else {
        $scores.Validation = 0.5
    }
    
    # Calculate weighted overall
    $weights = @{
        Intent = 0.35
        Parameters = 0.40
        Validation = 0.25
    }
    
    $overall = 0.0
    foreach ($key in $scores.Keys) {
        if ($weights.ContainsKey($key)) {
            $overall += $scores[$key] * $weights[$key]
        }
    }
    
    $scores.Overall = [math]::Round($overall, 3)
    
    return [PSCustomObject]$scores
}

<#
.SYNOPSIS
    Gets clarification questions for low-confidence configurations.

.DESCRIPTION
    Internal helper to generate questions when configuration
    could not be determined with high confidence.
#>
function Get-NLConfigClarificationQuestions {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $false)]
        [PSCustomObject]$Intent,

        [Parameter(Mandatory = $false)]
        [hashtable]$Parameters,

        [Parameter(Mandatory = $false)]
        [PSCustomObject]$Validation
    )

    $questions = @()
    
    # Check for ambiguous intent
    if ($Intent -and $Intent.IsAmbiguous) {
        $intentOptions = ($Intent.PossibleIntents | Select-Object -First 3 | ForEach-Object { $_.Category }) -join ', '
        $questions += [PSCustomObject]@{
            id = 'clarifyIntent'
            question = "Your request could mean several things ($intentOptions). Which did you mean?"
            type = 'choice'
            options = $Intent.PossibleIntents | Select-Object -First 3 | ForEach-Object { $_.Category }
            required = $true
        }
    }
    
    # Check for missing pack
    if ((-not $Parameters.PackId) -and ($Intent.Category -match 'pack' -or $Intent.Category -eq 'unknown')) {
        $questions += [PSCustomObject]@{
            id = 'packId'
            question = 'Which pack would you like to configure?'
            type = 'choice'
            options = @('godot-engine', 'rpgmaker-mz', 'blender-engine')
            required = $true
        }
    }
    
    # Check for missing execution mode in mode-change intent
    if ($Intent.Category -eq 'mode-change' -and -not $Parameters.ExecutionMode) {
        $questions += [PSCustomObject]@{
            id = 'executionMode'
            question = 'Which execution mode would you like to use?'
            type = 'choice'
            options = @('interactive', 'ci', 'watch', 'heal-watch', 'mcp-readonly', 'mcp-mutating')
            required = $true
        }
    }
    
    # Check for missing profile in profile-switch intent
    if ($Intent.Category -eq 'profile-switch' -and -not $Parameters.Profile) {
        $questions += [PSCustomObject]@{
            id = 'profile'
            question = 'Which profile would you like to switch to?'
            type = 'choice'
            options = @('developer', 'production', 'minimal', 'standard', 'team')
            required = $true
        }
    }
    
    # Check for missing trust tier
    if ($Intent.Category -eq 'trust-update' -and -not $Parameters.TrustTier) {
        $questions += [PSCustomObject]@{
            id = 'trustTier'
            question = 'What trust level should be applied?'
            type = 'choice'
            options = @('High', 'Medium-High', 'Medium', 'Low', 'Quarantined')
            defaultValue = 'Medium'
            required = $false
        }
    }
    
    # Add questions based on validation errors
    if ($Validation -and $Validation.Errors) {
        foreach ($error in $Validation.Errors) {
            if ($error.Path -eq 'execution.mode' -and $error.Message -match 'Invalid execution mode') {
                $questions += [PSCustomObject]@{
                    id = 'correctMode'
                    question = "The specified execution mode is invalid. Which mode would you like to use?"
                    type = 'choice'
                    options = @(Get-ValidExecutionModes)
                    required = $true
                }
            }
            elseif ($error.Path -eq 'provider.type' -and $error.Message -match 'Invalid provider type') {
                $questions += [PSCustomObject]@{
                    id = 'correctProvider'
                    question = "The specified provider type is invalid. Which provider would you like to use?"
                    type = 'choice'
                    options = @('openai', 'azure-openai', 'anthropic', 'local', 'custom')
                    required = $true
                }
            }
        }
    }
    
    return $questions
}

<#
.SYNOPSIS
    Sets a nested configuration value using dot notation.

.DESCRIPTION
    Internal helper to set values at nested paths like 'logging.level'.
#>
function Set-NestedConfigValue {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [hashtable]$Config,

        [Parameter(Mandatory = $true)]
        [string]$Path,

        [Parameter(Mandatory = $true)]
        $Value
    )

    $keys = $Path -split '\.'
    $current = $Config
    
    for ($i = 0; $i -lt $keys.Count - 1; $i++) {
        $key = $keys[$i]
        if (-not $current.ContainsKey($key)) {
            $current[$key] = @{}
        }
        $current = $current[$key]
    }
    
    $current[$keys[-1]] = $Value
}

<#
.SYNOPSIS
    Finds the best fuzzy match for an input string.

.DESCRIPTION
    Internal helper for fuzzy string matching to suggest corrections
    for unknown or misspelled terms.

.PARAMETER Input
    The input string to match.

.PARAMETER Candidates
    Array of candidate strings to match against.

.PARAMETER Threshold
    Minimum similarity score (0-1) to consider a match.

.OUTPUTS
    PSCustomObject with Match and Score, or null if no good match.
#>
function Find-BestFuzzyMatch {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Input,

        [Parameter(Mandatory = $true)]
        [string[]]$Candidates,

        [Parameter(Mandatory = $false)]
        [double]$Threshold = 0.6
    )

    $bestMatch = $null
    $bestScore = 0.0
    
    $inputLower = $Input.ToLower()
    
    foreach ($candidate in $Candidates) {
        $candidateLower = $candidate.ToLower()
        
        $score = Measure-StringSimilarity -String1 $inputLower -String2 $candidateLower
        
        if ($score -gt $bestScore -and $score -ge $Threshold) {
            $bestScore = $score
            $bestMatch = $candidate
        }
    }
    
    if ($bestMatch) {
        return [PSCustomObject]@{
            Match = $bestMatch
            Score = [math]::Round($bestScore, 3)
        }
    }
    
    return $null
}

<#
.SYNOPSIS
    Measures similarity between two strings.

.DESCRIPTION
    Internal helper that calculates a similarity score between 0 and 1
    using a simplified Levenshtein distance algorithm.
#>
function Measure-StringSimilarity {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$String1,

        [Parameter(Mandatory = $true)]
        [string]$String2
    )

    # Exact match
    if ($String1 -eq $String2) { return 1.0 }
    
    # Contains match
    if ($String1.Contains($String2) -or $String2.Contains($String1)) { return 0.9 }
    
    # Calculate Levenshtein distance
    $len1 = $String1.Length
    $len2 = $String2.Length
    
    if ($len1 -eq 0) { return 0.0 }
    if ($len2 -eq 0) { return 0.0 }
    
    # Create distance matrix
    $distances = @()
    for ($i = 0; $i -le $len1; $i++) {
        $row = @()
        for ($j = 0; $j -le $len2; $j++) {
            $row += 0
        }
        $distances += ,$row
    }
    
    for ($i = 0; $i -le $len1; $i++) { $distances[$i][0] = $i }
    for ($j = 0; $j -le $len2; $j++) { $distances[0][$j] = $j }
    
    for ($i = 1; $i -le $len1; $i++) {
        for ($j = 1; $j -le $len2; $j++) {
            $cost = if ($String1[$i - 1] -eq $String2[$j - 1]) { 0 } else { 1 }
            $distances[$i][$j] = [math]::Min(
                [math]::Min($distances[$i - 1][$j] + 1, $distances[$i][$j - 1] + 1),
                $distances[$i - 1][$j - 1] + $cost
            )
        }
    }
    
    $maxLen = [math]::Max($len1, $len2)
    $similarity = 1.0 - ($distances[$len1][$len2] / $maxLen)
    
    return $similarity
}

<#
.SYNOPSIS
    Starts an interactive configuration wizard.
#>
function Start-InteractiveConfig {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $false)]
        [PSCustomObject]$InitialResult = $null
    )

    $script:WizardState.Active = $true
    $script:WizardState.CurrentStep = 0
    $script:WizardState.Answers = @{}
    
    if ($InitialResult) {
        $script:WizardState.GeneratedConfig = $InitialResult.Config
        $script:WizardState.Questions = Get-NLConfigClarificationQuestions -Intent $InitialResult.Intent -Parameters $InitialResult.Parameters -Validation $InitialResult.Validation
    }

    Write-Host "`n=== LLM Workflow Configuration Wizard ===" -ForegroundColor Cyan
    # (Implementation would continue with interactive Read-Host loop)
    
    return $script:WizardState.GeneratedConfig
}

# =============================================================================
# EXPORT MODULE MEMBERS
# =============================================================================

try {
    Export-ModuleMember -Function @(
        'ConvertFrom-NaturalLanguageConfig',
        'Get-ConfigIntent',
        'New-ConfigFromTemplate',
        'ConvertTo-NaturalLanguageConfig',
        'Get-ConfigSuggestion',
        'Test-ConfigNaturalLanguage',
        'Start-InteractiveConfig'
    )
}
catch {
    Write-Verbose "NaturalLanguageConfig Export-ModuleMember skipped"
}
