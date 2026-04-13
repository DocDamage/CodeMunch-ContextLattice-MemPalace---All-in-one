#requires -Version 5.1
<#
.SYNOPSIS
    Natural Language Configuration Generation for LLM Workflow platform.

.DESCRIPTION
    Enables users to configure the platform using natural language descriptions
    that get translated into formal configuration. Part of Phase 7 MCP capabilities.

.NOTES
    Version: 1.0.0
    Compatible with: PowerShell 5.1+
    Confidence threshold for auto-acceptance: 0.7
#>

# Module-level configuration patterns database
$script:ConfigPatterns = @{
    # Pack-related patterns
    packs = @{
        'track' = @{ intent = 'pack.install'; confidence = 0.9 }
        'install' = @{ intent = 'pack.install'; confidence = 0.9 }
        'use' = @{ intent = 'pack.install'; confidence = 0.8 }
        'include' = @{ intent = 'pack.install'; confidence = 0.8 }
        'add' = @{ intent = 'pack.install'; confidence = 0.8 }
        'godot' = @{ intent = 'pack.godot'; confidence = 0.95; packId = 'godot-engine' }
        'rpg maker' = @{ intent = 'pack.rpgmaker'; confidence = 0.95; packId = 'rpgmaker-mz' }
        'blender' = @{ intent = 'pack.blender'; confidence = 0.95; packId = 'blender-engine' }
        'high trust' = @{ intent = 'trust.high'; confidence = 0.9; trustTier = 'High' }
        'medium trust' = @{ intent = 'trust.medium'; confidence = 0.9; trustTier = 'Medium' }
        'low trust' = @{ intent = 'trust.low'; confidence = 0.9; trustTier = 'Low' }
        'developer profile' = @{ intent = 'profile.developer'; confidence = 0.9; profile = 'developer' }
        'production profile' = @{ intent = 'profile.production'; confidence = 0.9; profile = 'production' }
        'minimal profile' = @{ intent = 'profile.minimal'; confidence = 0.9; profile = 'minimal' }
    }
    
    # Schedule-related patterns
    schedules = @{
        'every day' = @{ cron = '0 0 * * *'; confidence = 0.9 }
        'daily' = @{ cron = '0 0 * * *'; confidence = 0.9 }
        'every hour' = @{ cron = '0 * * * *'; confidence = 0.9 }
        'hourly' = @{ cron = '0 * * * *'; confidence = 0.9 }
        'every minute' = @{ cron = '* * * * *'; confidence = 0.9 }
        'every week' = @{ cron = '0 0 * * 0'; confidence = 0.9 }
        'weekly' = @{ cron = '0 0 * * 0'; confidence = 0.9 }
        'every month' = @{ cron = '0 0 1 * *'; confidence = 0.9 }
        'monthly' = @{ cron = '0 0 1 * *'; confidence = 0.9 }
        'sync' = @{ intent = 'schedule.sync'; confidence = 0.8 }
        'at' = @{ intent = 'schedule.time'; confidence = 0.85 }
        'am' = @{ intent = 'schedule.am'; confidence = 0.9 }
        'pm' = @{ intent = 'schedule.pm'; confidence = 0.9 }
    }
    
    # Notification patterns
    notifications = @{
        'notify' = @{ intent = 'notification.add'; confidence = 0.9 }
        'alert' = @{ intent = 'notification.add'; confidence = 0.9 }
        'slack' = @{ intent = 'notification.slack'; confidence = 0.95; type = 'webhook'; urlPattern = '${SLACK_WEBHOOK_URL}' }
        'discord' = @{ intent = 'notification.discord'; confidence = 0.95; type = 'webhook'; urlPattern = '${DISCORD_WEBHOOK_URL}' }
        'email' = @{ intent = 'notification.email'; confidence = 0.9; type = 'email' }
        'webhook' = @{ intent = 'notification.webhook'; confidence = 0.9; type = 'webhook' }
        'health drops' = @{ event = 'health.degraded'; confidence = 0.9 }
        'on failure' = @{ event = 'execution.failed'; confidence = 0.9 }
        'on success' = @{ event = 'execution.completed'; confidence = 0.9 }
        'when complete' = @{ event = 'execution.completed'; confidence = 0.9 }
    }
    
    # Filter patterns
    filters = @{
        'include' = @{ intent = 'filter.include'; confidence = 0.9 }
        'exclude' = @{ intent = 'filter.exclude'; confidence = 0.9 }
        'only' = @{ intent = 'filter.only'; confidence = 0.85 }
        'ignore' = @{ intent = 'filter.exclude'; confidence = 0.9 }
        'skip' = @{ intent = 'filter.exclude'; confidence = 0.9 }
        'code files' = @{ intent = 'filter.code'; confidence = 0.9; useCase = 'code-extraction' }
        'documentation' = @{ intent = 'filter.docs'; confidence = 0.9; useCase = 'documentation-only' }
        'tests' = @{ intent = 'filter.tests'; confidence = 0.9; useCase = 'tests-only' }
    }
    
    # Provider patterns
    providers = @{
        'openai' = @{ provider = 'openai'; confidence = 0.95 }
        'gpt-4' = @{ model = 'gpt-4'; confidence = 0.95 }
        'gpt-3' = @{ model = 'gpt-3.5-turbo'; confidence = 0.95 }
        'claude' = @{ provider = 'anthropic'; model = 'claude-3-opus-20240229'; confidence = 0.95 }
        'anthropic' = @{ provider = 'anthropic'; confidence = 0.95 }
        'local' = @{ provider = 'local'; confidence = 0.9 }
        'azure' = @{ provider = 'azure-openai'; confidence = 0.95 }
    }
    
    # Execution mode patterns
    executionModes = @{
        'interactive' = @{ mode = 'interactive'; confidence = 0.95 }
        'ci mode' = @{ mode = 'ci'; confidence = 0.95 }
        'watch' = @{ mode = 'watch'; confidence = 0.95 }
        'heal watch' = @{ mode = 'heal-watch'; confidence = 0.95 }
        'scheduled' = @{ mode = 'scheduled'; confidence = 0.9 }
    }
}

# Interactive wizard state
$script:WizardState = @{
    Active = $false
    CurrentStep = 0
    Questions = @()
    Answers = @{}
    Context = @{}
    GeneratedConfig = @{}
}

# Config examples database
$script:ConfigExamples = @(
    @{
        description = "I want to track the Godot engine with high trust and include Rust bindings"
        config = @{
            packId = "godot-engine"
            installProfile = "developer"
            trustOverrides = @{
                "godot-rust/gdext" = "high"
            }
            collections = @("godot_core_api", "godot_language_bindings")
        }
        tags = @('godot', 'rust', 'bindings', 'high-trust')
    }
    @{
        description = "Sync every day at 2am and notify on Slack when health drops"
        config = @{
            schedule = "0 2 * * *"
            notifications = @(
                @{
                    event = "health.degraded"
                    type = "webhook"
                    url = '${SLACK_WEBHOOK_URL}'
                }
            )
        }
        tags = @('schedule', 'sync', 'slack', 'health', 'notification')
    }
    @{
        description = "Use OpenAI GPT-4 with high temperature for creative tasks"
        config = @{
            provider = @{
                type = "openai"
                model = "gpt-4"
                temperature = 0.9
            }
        }
        tags = @('openai', 'gpt-4', 'creative', 'temperature')
    }
    @{
        description = "Run in CI mode with no notifications and strict validation"
        config = @{
            execution = @{
                mode = "ci"
                strict = $true
            }
            notifications = @{
                enabled = $false
            }
        }
        tags = @('ci', 'strict', 'no-notifications')
    }
    @{
        description = "Track RPG Maker MZ with medium trust and include all plugins"
        config = @{
            packId = "rpgmaker-mz"
            installProfile = "standard"
            trustTier = "Medium"
            includePatterns = @("js/plugins/**")
        }
        tags = @('rpgmaker', 'plugins', 'medium-trust')
    }
)

<#
.SYNOPSIS
    Parses natural language text into configuration.

.DESCRIPTION
    Main entry point for natural language configuration generation.
    Analyzes input text and produces a structured configuration hashtable.

.PARAMETER Text
    The natural language description to parse.

.PARAMETER BaseConfig
    Optional existing configuration to merge with/override.

.PARAMETER Interactive
    If true, starts interactive mode when confidence is low.

.PARAMETER MinConfidence
    Minimum confidence threshold (0-1) for auto-acceptance.

.OUTPUTS
    PSCustomObject with generated configuration and metadata.

.EXAMPLE
    $result = ConvertFrom-NaturalLanguageConfig -Text "I want to track Godot with high trust"
    PS> $result.Config
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
        
        # Extract entities
        $entities = Get-ConfigEntities -Text $Text
        
        # Generate config based on intent
        $generatedConfig = New-ConfigFromDescription -Text $Text -Intent $intent -Entities $entities
        
        # Merge with base config if provided
        if ($BaseConfig -and $BaseConfig.Count -gt 0) {
            $generatedConfig = Merge-GeneratedConfig -Generated $generatedConfig -Base $BaseConfig
        }
        
        # Validate generated config
        $validation = Test-GeneratedConfig -Config $generatedConfig
        
        # Calculate overall confidence
        $confidence = Measure-ConfigConfidence -Intent $intent -Entities $entities -Validation $validation
        
        # Determine if we need clarification
        $needsClarification = $confidence.Overall -lt $MinConfidence
        
        $result = [PSCustomObject]@{
            Success = $validation.IsValid -or (-not $validation.Errors.Any{ $_.Severity -eq 'error' })
            Config = $generatedConfig
            Confidence = $confidence
            Intent = $intent
            Entities = $entities
            Validation = $validation
            NeedsClarification = $needsClarification
            ClarificationQuestions = if ($needsClarification) { 
                Get-ConfigClarificationQuestions -Intent $intent -Entities $entities -Validation $validation 
            } else { @() }
        }
        
        # Start interactive mode if needed and requested
        if ($needsClarification -and $Interactive) {
            Start-InteractiveConfig -InitialResult $result | Out-Null
        }
        
        return $result
    }
}

<#
.SYNOPSIS
    Identifies the configuration intent from natural language text.

.DESCRIPTION
    Analyzes text to determine the primary configuration intent category.

.PARAMETER Text
    The natural language text to analyze.

.OUTPUTS
    PSCustomObject with intent information.

.EXAMPLE
    Get-ConfigIntent -Text "I want to track Godot"
    Returns: @{ Category = 'pack'; Action = 'install'; Confidence = 0.9 }
#>
function Get-ConfigIntent {
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Text
    )

    $textLower = $Text.ToLower()
    $scores = @{
        pack = 0.0
        schedule = 0.0
        notification = 0.0
        filter = 0.0
        provider = 0.0
        execution = 0.0
    }
    
    $detectedPatterns = @()
    
    # Check pack-related patterns
    foreach ($pattern in $script:ConfigPatterns.packs.Keys) {
        if ($textLower -match $pattern) {
            $scores.pack += $script:ConfigPatterns.packs[$pattern].confidence
            $detectedPatterns += "pack:$pattern"
        }
    }
    
    # Check schedule-related patterns
    foreach ($pattern in $script:ConfigPatterns.schedules.Keys) {
        if ($textLower -match $pattern) {
            $scores.schedule += $script:ConfigPatterns.schedules[$pattern].confidence
            $detectedPatterns += "schedule:$pattern"
        }
    }
    
    # Check notification-related patterns
    foreach ($pattern in $script:ConfigPatterns.notifications.Keys) {
        if ($textLower -match $pattern) {
            $scores.notification += $script:ConfigPatterns.notifications[$pattern].confidence
            $detectedPatterns += "notification:$pattern"
        }
    }
    
    # Check filter-related patterns
    foreach ($pattern in $script:ConfigPatterns.filters.Keys) {
        if ($textLower -match $pattern) {
            $scores.filter += $script:ConfigPatterns.filters[$pattern].confidence
            $detectedPatterns += "filter:$pattern"
        }
    }
    
    # Check provider-related patterns
    foreach ($pattern in $script:ConfigPatterns.providers.Keys) {
        if ($textLower -match $pattern) {
            $scores.provider += $script:ConfigPatterns.providers[$pattern].confidence
            $detectedPatterns += "provider:$pattern"
        }
    }
    
    # Check execution mode patterns
    foreach ($pattern in $script:ConfigPatterns.executionModes.Keys) {
        if ($textLower -match $pattern) {
            $scores.execution += $script:ConfigPatterns.executionModes[$pattern].confidence
            $detectedPatterns += "execution:$pattern"
        }
    }
    
    # Determine primary intent
    $maxScore = ($scores.Values | Measure-Object -Maximum).Maximum
    $primaryCategory = $scores.GetEnumerator() | 
        Where-Object { $_.Value -eq $maxScore } | 
        Select-Object -First 1 -ExpandProperty Key
    
    # Determine specific action
    $action = 'configure'
    switch ($primaryCategory) {
        'pack' { $action = if ($textLower -match 'track|install|use|add') { 'install' } else { 'configure' } }
        'schedule' { $action = 'set-schedule' }
        'notification' { $action = 'add-notification' }
        'filter' { $action = 'set-filter' }
        'provider' { $action = 'set-provider' }
        'execution' { $action = 'set-mode' }
    }
    
    return [PSCustomObject]@{
        Category = $primaryCategory
        Action = $action
        Confidence = [math]::Min($maxScore, 1.0)
        AllScores = $scores
        Patterns = $detectedPatterns
    }
}

<#
.SYNOPSIS
    Extracts configuration entities from natural language text.

.DESCRIPTION
    Identifies and extracts specific configuration values from text.

.PARAMETER Text
    The natural language text to analyze.

.OUTPUTS
    Hashtable of extracted entities.

.EXAMPLE
    Get-ConfigEntities -Text "track Godot with high trust"
    Returns: @{ packId = 'godot-engine'; trustTier = 'High' }
#>
function Get-ConfigEntities {
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Text
    )

    $textLower = $Text.ToLower()
    $entities = @{}
    
    # Extract pack entities
    if ($textLower -match 'godot') {
        $entities.packId = 'godot-engine'
        $entities.packConfidence = 0.95
    }
    elseif ($textLower -match 'rpg\s*maker') {
        $entities.packId = 'rpgmaker-mz'
        $entities.packConfidence = 0.95
    }
    elseif ($textLower -match 'blender') {
        $entities.packId = 'blender-engine'
        $entities.packConfidence = 0.95
    }
    
    # Extract trust tier
    if ($textLower -match 'high\s+trust|trust.*high') {
        $entities.trustTier = 'High'
        $entities.trustConfidence = 0.9
    }
    elseif ($textLower -match 'medium\s+trust|trust.*medium') {
        $entities.trustTier = 'Medium'
        $entities.trustConfidence = 0.9
    }
    elseif ($textLower -match 'low\s+trust|trust.*low') {
        $entities.trustTier = 'Low'
        $entities.trustConfidence = 0.9
    }
    
    # Extract profile
    if ($textLower -match 'developer|dev\s+profile') {
        $entities.installProfile = 'developer'
    }
    elseif ($textLower -match 'production|prod\s+profile') {
        $entities.installProfile = 'production'
    }
    elseif ($textLower -match 'minimal|min\s+profile') {
        $entities.installProfile = 'minimal'
    }
    elseif ($textLower -match 'standard\s+profile') {
        $entities.installProfile = 'standard'
    }
    
    # Extract provider
    foreach ($pattern in $script:ConfigPatterns.providers.Keys) {
        if ($textLower -match $pattern) {
            $providerInfo = $script:ConfigPatterns.providers[$pattern]
            if ($providerInfo.provider) {
                $entities.providerType = $providerInfo.provider
            }
            if ($providerInfo.model) {
                $entities.model = $providerInfo.model
            }
            break
        }
    }
    
    # Extract temperature
    if ($textLower -match 'temperature\s+(?:of\s+)?(\d+\.?\d*)') {
        $entities.temperature = [double]$matches[1]
    }
    elseif ($textLower -match 'high\s+temperature|creative') {
        $entities.temperature = 0.9
    }
    elseif ($textLower -match 'low\s+temperature|focused') {
        $entities.temperature = 0.2
    }
    
    # Extract execution mode
    foreach ($pattern in $script:ConfigPatterns.executionModes.Keys) {
        if ($textLower -match $pattern) {
            $entities.executionMode = $script:ConfigPatterns.executionModes[$pattern].mode
            break
        }
    }
    
    # Extract schedule time
    $scheduleMatch = $textLower | Select-String -Pattern '(\d{1,2}):?(\d{2})?\s*(am|pm)?'
    if ($scheduleMatch) {
        $hour = [int]$scheduleMatch.Matches[0].Groups[1].Value
        $minute = if ($scheduleMatch.Matches[0].Groups[2].Success) { 
            [int]$scheduleMatch.Matches[0].Groups[2].Value 
        } else { 0 }
        $ampm = $scheduleMatch.Matches[0].Groups[3].Value
        
        if ($ampm -eq 'pm' -and $hour -lt 12) { $hour += 12 }
        if ($ampm -eq 'am' -and $hour -eq 12) { $hour = 0 }
        
        $entities.scheduleHour = $hour
        $entities.scheduleMinute = $minute
    }
    
    # Extract notification target
    foreach ($pattern in @('slack', 'discord', 'email', 'webhook')) {
        if ($textLower -match $pattern) {
            $entities.notificationType = $pattern
            break
        }
    }
    
    # Extract notification event
    if ($textLower -match 'health') {
        $entities.notificationEvent = 'health.degraded'
    }
    elseif ($textLower -match 'fail|error') {
        $entities.notificationEvent = 'execution.failed'
    }
    elseif ($textLower -match 'complete|success') {
        $entities.notificationEvent = 'execution.completed'
    }
    
    # Extract filter patterns
    if ($textLower -match 'code\s+files|source\s+files') {
        $entities.filterUseCase = 'code-extraction'
    }
    elseif ($textLower -match 'documentation|docs') {
        $entities.filterUseCase = 'documentation-only'
    }
    elseif ($textLower -match 'tests?') {
        $entities.filterUseCase = 'tests-only'
    }
    
    # Extract extensions
    $extensionMatches = [regex]::Matches($textLower, '\*(\.\w+)')
    if ($extensionMatches.Count -gt 0) {
        $entities.extensions = @($extensionMatches | ForEach-Object { $_.Groups[1].Value } | Select-Object -Unique)
    }
    
    return $entities
}

<#
.SYNOPSIS
    Tests if text appears to be configuration-related.

.DESCRIPTION
    Quick check to determine if natural language text is likely
    attempting to configure the platform.

.PARAMETER Text
    The text to test.

.PARAMETER Threshold
    Minimum confidence to consider text as config-related.

.OUTPUTS
    Boolean indicating if text is config-related.

.EXAMPLE
    Test-ConfigIntent -Text "I want to configure Godot"
    True
#>
function Test-ConfigIntent {
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Text,

        [Parameter(Mandatory = $false)]
        [double]$Threshold = 0.5
    )

    $intent = Get-ConfigIntent -Text $Text
    return $intent.Confidence -ge $Threshold
}

<#
.SYNOPSIS
    Generates configuration from description and parsed data.

.DESCRIPTION
    Internal function that builds configuration hashtable from
    parsed intent and entities.

.PARAMETER Text
    Original natural language text.

.PARAMETER Intent
    Parsed intent object from Get-ConfigIntent.

.PARAMETER Entities
    Extracted entities from Get-ConfigEntities.

.OUTPUTS
    Hashtable containing generated configuration.

.EXAMPLE
    New-ConfigFromDescription -Text "track Godot" -Intent $intent -Entities $entities
#>
function New-ConfigFromDescription {
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Text,

        [Parameter(Mandatory = $false)]
        [PSCustomObject]$Intent = $null,

        [Parameter(Mandatory = $false)]
        [hashtable]$Entities = @{}
    )

    if (-not $Intent) {
        $Intent = Get-ConfigIntent -Text $Text
    }
    if (-not $Entities -or $Entities.Count -eq 0) {
        $Entities = Get-ConfigEntities -Text $Text
    }
    
    $config = @{}
    
    switch ($Intent.Category) {
        'pack' {
            $config = New-PackConfigFromDescription -Text $Text -Entities $Entities
        }
        'schedule' {
            $config = New-ScheduleFromDescription -Text $Text -Entities $Entities
        }
        'notification' {
            $config.notifications = @(New-NotificationFromEntities -Entities $Entities)
        }
        'filter' {
            $config = New-FilterFromDescription -Text $Text -Entities $Entities
        }
        'provider' {
            $config.provider = @{}
            if ($Entities.providerType) {
                $config.provider.type = $Entities.providerType
            }
            if ($Entities.model) {
                $config.provider.model = $Entities.model
            }
            if ($Entities.ContainsKey('temperature')) {
                $config.provider.temperature = $Entities.temperature
            }
        }
        'execution' {
            $config.execution = @{}
            if ($Entities.executionMode) {
                $config.execution.mode = $Entities.executionMode
            }
        }
        default {
            # Generic configuration attempt
            if ($Entities.packId) {
                $config = New-PackConfigFromDescription -Text $Text -Entities $Entities
            }
        }
    }
    
    # Add metadata
    $config._generatedFrom = $Text
    $config._generatedAt = (Get-Date -Format 'o')
    
    return $config
}

<#
.SYNOPSIS
    Generates pack-specific configuration.

.DESCRIPTION
    Creates configuration for pack installation and management.

.PARAMETER Text
    Natural language description.

.PARAMETER Entities
    Extracted entities.

.OUTPUTS
    Hashtable with pack configuration.

.EXAMPLE
    New-PackConfigFromDescription -Text "track Godot with high trust" -Entities $entities
#>
function New-PackConfigFromDescription {
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Text,

        [Parameter(Mandatory = $false)]
        [hashtable]$Entities = @{}
    )

    $config = @{}
    
    if ($Entities.packId) {
        $config.packId = $Entities.packId
    }
    
    if ($Entities.installProfile) {
        $config.installProfile = $Entities.installProfile
    }
    
    if ($Entities.trustTier) {
        $config.trustTier = $Entities.trustTier
        
        # If we have trust overrides from text parsing
        $textLower = $Text.ToLower()
        if ($textLower -match 'rust') {
            $config.trustOverrides = @{
                "godot-rust/gdext" = $Entities.trustTier.ToLower()
            }
        }
    }
    
    # Determine collections based on pack
    if ($config.packId -eq 'godot-engine') {
        $config.collections = @("godot_core_api")
        if ($Text -match 'rust|bindings|language') {
            $config.collections += "godot_language_bindings"
        }
    }
    elseif ($config.packId -eq 'rpgmaker-mz') {
        $config.collections = @("rpgmaker_core", "rpgmaker_plugins")
    }
    elseif ($config.packId -eq 'blender-engine') {
        $config.collections = @("blender_python_api", "blender_geometry_nodes")
    }
    
    return $config
}

<#
.SYNOPSIS
    Generates filter configuration from natural language.

.DESCRIPTION
    Creates include/exclude filter configuration based on description.

.PARAMETER Text
    Natural language description.

.PARAMETER Entities
    Extracted entities.

.OUTPUTS
    Hashtable with filter configuration.

.EXAMPLE
    New-FilterFromDescription -Text "include only code files" -Entities $entities
#>
function New-FilterFromDescription {
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Text,

        [Parameter(Mandatory = $false)]
        [hashtable]$Entities = @{}
    )

    $config = @{
        filters = @{
            includePatterns = @()
            excludePatterns = @()
        }
    }
    
    $textLower = $Text.ToLower()
    
    # Set use case based on entities or text
    if ($Entities.filterUseCase) {
        $config.filters.useCase = $Entities.filterUseCase
    }
    elseif ($textLower -match 'code|source') {
        $config.filters.useCase = 'code-extraction'
    }
    elseif ($textLower -match 'documentation|docs') {
        $config.filters.useCase = 'documentation-only'
    }
    elseif ($textLower -match 'tests?') {
        $config.filters.useCase = 'tests-only'
    }
    
    # Add extension filters
    if ($Entities.extensions) {
        $config.filters.includeExtensions = $Entities.extensions
    }
    
    # Parse include patterns
    if ($textLower -match 'include\s+(.+)') {
        $includePart = $matches[1]
        # Extract file patterns
        $patterns = [regex]::Matches($includePart, '[\*\w\/]+\.\w+')
        foreach ($pattern in $patterns) {
            $config.filters.includePatterns += $pattern.Value
        }
    }
    
    # Parse exclude patterns  
    if ($textLower -match 'exclude\s+(.+)|ignore\s+(.+)') {
        $excludePart = if ($matches[1]) { $matches[1] } else { $matches[2] }
        $patterns = [regex]::Matches($excludePart, '[\*\w\/]+\.\w+')
        foreach ($pattern in $patterns) {
            $config.filters.excludePatterns += $pattern.Value
        }
    }
    
    return $config
}

<#
.SYNOPSIS
    Parses schedule expressions from natural language.

.DESCRIPTION
    Converts natural language time descriptions to cron expressions.

.PARAMETER Text
    Natural language description.

.PARAMETER Entities
    Extracted entities.

.OUTPUTS
    Hashtable with schedule configuration.

.EXAMPLE
    New-ScheduleFromDescription -Text "every day at 2am" -Entities $entities
    Returns: @{ schedule = "0 2 * * *" }
#>
function New-ScheduleFromDescription {
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Text,

        [Parameter(Mandatory = $false)]
        [hashtable]$Entities = @{}
    )

    $config = @{}
    $textLower = $Text.ToLower()
    
    # Check for common schedule patterns
    if ($textLower -match 'every\s+day|daily') {
        if ($Entities.scheduleHour -ne $null) {
            $config.schedule = "0 $($Entities.scheduleHour) * * *"
        }
        else {
            $config.schedule = "0 0 * * *"
        }
    }
    elseif ($textLower -match 'every\s+hour|hourly') {
        $config.schedule = "0 * * * *"
    }
    elseif ($textLower -match 'every\s+minute') {
        $config.schedule = "* * * * *"
    }
    elseif ($textLower -match 'every\s+week|weekly') {
        if ($Entities.scheduleHour -ne $null) {
            $config.schedule = "0 $($Entities.scheduleHour) * * 0"
        }
        else {
            $config.schedule = "0 0 * * 0"
        }
    }
    elseif ($textLower -match 'every\s+month|monthly') {
        if ($Entities.scheduleHour -ne $null) {
            $config.schedule = "0 $($Entities.scheduleHour) 1 * *"
        }
        else {
            $config.schedule = "0 0 1 * *"
        }
    }
    elseif ($Entities.scheduleHour -ne $null) {
        # Just a time specified
        $config.schedule = "0 $($Entities.scheduleHour) * * *"
    }
    
    # Check for sync keyword
    if ($textLower -match 'sync|synchronize') {
        $config.syncEnabled = $true
    }
    
    return $config
}

<#
.SYNOPSIS
    Creates notification configuration from entities.

.DESCRIPTION
    Internal helper to build notification objects.

.PARAMETER Entities
    Extracted entities.

.OUTPUTS
    Hashtable with notification configuration.
#>
function New-NotificationFromEntities {
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [Parameter(Mandatory = $true)]
        [hashtable]$Entities
    )

    $notification = @{
        enabled = $true
    }
    
    if ($Entities.notificationType) {
        $notification.type = $Entities.notificationType
        
        # Set URL pattern based on type
        switch ($Entities.notificationType) {
            'slack' { $notification.url = '${SLACK_WEBHOOK_URL}' }
            'discord' { $notification.url = '${DISCORD_WEBHOOK_URL}' }
            'email' { 
                $notification.type = 'email'
                $notification.recipient = '${NOTIFICATION_EMAIL}'
            }
        }
    }
    
    if ($Entities.notificationEvent) {
        $notification.event = $Entities.notificationEvent
    }
    else {
        $notification.event = 'execution.completed'
    }
    
    return $notification
}

<#
.SYNOPSIS
    Validates generated configuration.

.DESCRIPTION
    Checks if generated configuration is valid and complete.

.PARAMETER Config
    The configuration to validate.

.PARAMETER Schema
    Optional schema to validate against.

.OUTPUTS
    PSCustomObject with validation results.

.EXAMPLE
    Test-GeneratedConfig -Config $myConfig
#>
function Test-GeneratedConfig {
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Mandatory = $true)]
        [hashtable]$Config,

        [Parameter(Mandatory = $false)]
        [hashtable]$Schema = $null
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
    
    # Check for empty config
    if ($cleanConfig.Count -eq 0) {
        $errors += [PSCustomObject]@{
            Path = ''
            Message = 'Configuration is empty'
            Severity = 'error'
        }
    }
    
    # Validate pack configuration
    if ($cleanConfig.ContainsKey('packId')) {
        $validPacks = @('godot-engine', 'rpgmaker-mz', 'blender-engine', 'generic')
        if ($cleanConfig.packId -notin $validPacks) {
            $warnings += [PSCustomObject]@{
                Path = 'packId'
                Message = "Unknown packId '$($cleanConfig.packId)'. Valid values: $($validPacks -join ', ')"
                Severity = 'warning'
            }
        }
    }
    
    # Validate schedule format
    if ($cleanConfig.ContainsKey('schedule')) {
        $cronPattern = '^([0-9*,/-]+)\s+([0-9*,/-]+)\s+([0-9*,/-]+)\s+([0-9*,/-]+)\s+([0-9*,/-]+)$'
        if (-not ($cleanConfig.schedule -match $cronPattern)) {
            $errors += [PSCustomObject]@{
                Path = 'schedule'
                Message = "Invalid cron expression: '$($cleanConfig.schedule)'"
                Severity = 'error'
            }
        }
    }
    
    # Validate trust tier
    if ($cleanConfig.ContainsKey('trustTier')) {
        $validTiers = @('High', 'Medium-High', 'Medium', 'Low', 'Quarantined')
        if ($cleanConfig.trustTier -notin $validTiers) {
            $warnings += [PSCustomObject]@{
                Path = 'trustTier'
                Message = "Unusual trust tier value: '$($cleanConfig.trustTier)'"
                Severity = 'warning'
            }
        }
    }
    
    # Check for required fields based on intent
    if ($cleanConfig.ContainsKey('notifications') -and $cleanConfig.notifications.Count -gt 0) {
        foreach ($i in 0..($cleanConfig.notifications.Count - 1)) {
            $notif = $cleanConfig.notifications[$i]
            if (-not $notif.type) {
                $errors += [PSCustomObject]@{
                    Path = "notifications[$i].type"
                    Message = 'Notification type is required'
                    Severity = 'error'
                }
            }
            if (-not $notif.event) {
                $warnings += [PSCustomObject]@{
                    Path = "notifications[$i].event"
                    Message = 'Notification event not specified, defaulting to execution.completed'
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
    }
}

<#
.SYNOPSIS
    Gets clarification questions for low-confidence configurations.

.DESCRIPTION
    Generates questions to ask the user when configuration
    could not be determined with high confidence.

.PARAMETER Intent
    Parsed intent.

.PARAMETER Entities
    Extracted entities.

.PARAMETER Validation
    Validation results.

.OUTPUTS
    Array of question objects.

.EXAMPLE
    Get-ConfigClarificationQuestions -Intent $intent -Entities $entities -Validation $validation
#>
function Get-ConfigClarificationQuestions {
    [CmdletBinding()]
    [OutputType([array])]
    param(
        [Parameter(Mandatory = $false)]
        [PSCustomObject]$Intent = $null,

        [Parameter(Mandatory = $false)]
        [hashtable]$Entities = @{},

        [Parameter(Mandatory = $false)]
        [PSCustomObject]$Validation = $null
    )

    $questions = @()
    
    # Check for missing pack
    if (-not $Entities.packId -and $Intent.Category -eq 'pack') {
        $questions += [PSCustomObject]@{
            id = 'packId'
            question = 'Which pack would you like to configure?'
            type = 'choice'
            options = @('godot-engine', 'rpgmaker-mz', 'blender-engine', 'generic')
            required = $true
        }
    }
    
    # Check for missing trust tier
    if (-not $Entities.trustTier -and $Entities.packId) {
        $questions += [PSCustomObject]@{
            id = 'trustTier'
            question = 'What trust level should be applied?'
            type = 'choice'
            options = @('High', 'Medium-High', 'Medium', 'Low', 'Quarantined')
            defaultValue = 'Medium'
            required = $false
        }
    }
    
    # Check for missing schedule details
    if ($Intent.Category -eq 'schedule' -and ($null -eq $Entities.scheduleHour)) {
        $questions += [PSCustomObject]@{
            id = 'scheduleTime'
            question = 'What time should the schedule run? (e.g., 2:00 AM)'
            type = 'time'
            required = $true
        }
    }
    
    # Check for missing notification type
    if ($Intent.Category -eq 'notification' -and -not $Entities.notificationType) {
        $questions += [PSCustomObject]@{
            id = 'notificationType'
            question = 'How would you like to be notified?'
            type = 'choice'
            options = @('slack', 'discord', 'email', 'webhook')
            required = $true
        }
    }
    
    # Check for missing provider
    if ($Intent.Category -eq 'provider' -and -not $Entities.providerType) {
        $questions += [PSCustomObject]@{
            id = 'providerType'
            question = 'Which LLM provider would you like to use?'
            type = 'choice'
            options = @('openai', 'azure-openai', 'anthropic', 'local')
            required = $true
        }
    }
    
    # Add questions based on validation errors
    if ($Validation -and $Validation.Errors) {
        foreach ($error in $Validation.Errors) {
            if ($error.Path -eq 'schedule') {
                $questions += [PSCustomObject]@{
                    id = 'scheduleCorrection'
                    question = "The schedule format appears invalid. Please specify when (e.g., 'daily at 2am', 'every hour')"
                    type = 'text'
                    required = $true
                }
            }
        }
    }
    
    return $questions
}

<#
.SYNOPSIS
    Calculates confidence score for configuration generation.

.DESCRIPTION
    Computes overall confidence based on intent clarity,
    entity extraction quality, and validation results.

.PARAMETER Intent
    Parsed intent.

.PARAMETER Entities
    Extracted entities.

.PARAMETER Validation
    Validation results.

.OUTPUTS
    PSCustomObject with confidence scores.

.EXAMPLE
    Measure-ConfigConfidence -Intent $intent -Entities $entities -Validation $validation
#>
function Measure-ConfigConfidence {
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Mandatory = $false)]
        [PSCustomObject]$Intent = $null,

        [Parameter(Mandatory = $false)]
        [hashtable]$Entities = @{},

        [Parameter(Mandatory = $false)]
        [PSCustomObject]$Validation = $null
    )

    $scores = @{}
    
    # Intent confidence
    if ($Intent) {
        $scores.Intent = $Intent.Confidence
    }
    else {
        $scores.Intent = 0.0
    }
    
    # Entity extraction confidence
    $entityScores = @()
    foreach ($key in $Entities.Keys) {
        if ($key -like '*Confidence') {
            $entityScores += $Entities[$key]
        }
    }
    if ($entityScores.Count -gt 0) {
        $scores.Entities = ($entityScores | Measure-Object -Average).Average
    }
    else {
        # Estimate based on entity count vs expected
        $scores.Entities = [math]::Min($Entities.Count * 0.2, 1.0)
    }
    
    # Validation confidence
    if ($Validation) {
        $errorPenalty = $Validation.ErrorCount * 0.2
        $warningPenalty = $Validation.WarningCount * 0.05
        $scores.Validation = [math]::Max(0.0, 1.0 - $errorPenalty - $warningPenalty)
    }
    else {
        $scores.Validation = 0.5
    }
    
    # Calculate overall
    $weights = @{
        Intent = 0.4
        Entities = 0.35
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
    Gets alternative interpretations of the configuration intent.

.DESCRIPTION
    Provides alternative possible meanings when confidence is low.

.PARAMETER Text
    Original natural language text.

.PARAMETER Intent
    Primary parsed intent.

.PARAMETER MaxAlternatives
    Maximum number of alternatives to return.

.OUTPUTS
    Array of alternative interpretation objects.

.EXAMPLE
    Get-ConfigAlternatives -Text "configure Godot" -Intent $intent
#>
function Get-ConfigAlternatives {
    [CmdletBinding()]
    [OutputType([array])]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Text,

        [Parameter(Mandatory = $false)]
        [PSCustomObject]$Intent = $null,

        [Parameter(Mandatory = $false)]
        [int]$MaxAlternatives = 3
    )

    $alternatives = @()
    $textLower = $Text.ToLower()
    
    # If intent is unclear, suggest other categories
    if (-not $Intent -or $Intent.Confidence -lt 0.6) {
        if ($textLower -match 'godot|rpg|blender') {
            $alternatives += [PSCustomObject]@{
                Category = 'pack'
                Description = 'Configure a game engine pack'
                Confidence = 0.7
            }
        }
        if ($textLower -match 'notify|alert|slack|email') {
            $alternatives += [PSCustomObject]@{
                Category = 'notification'
                Description = 'Set up notifications'
                Confidence = 0.75
            }
        }
        if ($textLower -match 'schedule|daily|hourly|sync') {
            $alternatives += [PSCustomObject]@{
                Category = 'schedule'
                Description = 'Configure synchronization schedule'
                Confidence = 0.7
            }
        }
        if ($textLower -match 'gpt|claude|openai|model') {
            $alternatives += [PSCustomObject]@{
                Category = 'provider'
                Description = 'Configure LLM provider settings'
                Confidence = 0.8
            }
        }
    }
    
    # Add specific alternatives based on text
    if ($textLower -match 'godot') {
        $alternatives += [PSCustomObject]@{
            Category = 'pack'
            Variant = 'godot-rust'
            Description = 'Configure Godot with Rust bindings support'
            Confidence = 0.6
            ConfigOverride = @{
                trustOverrides = @{
                    'godot-rust/gdext' = 'high'
                }
                collections = @('godot_core_api', 'godot_language_bindings')
            }
        }
    }
    
    return $alternatives | Sort-Object -Property Confidence -Descending | Select-Object -First $MaxAlternatives
}

<#
.SYNOPSIS
    Gets matching example configurations.

.DESCRIPTION
    Finds example configurations that match the given description.

.PARAMETER Description
    Natural language description to match.

.PARAMETER Tags
    Optional tags to filter by.

.PARAMETER MaxExamples
    Maximum number of examples to return.

.OUTPUTS
    Array of matching example configurations.

.EXAMPLE
    Get-ConfigExample -Description "track Godot with high trust"
#>
function Get-ConfigExample {
    [CmdletBinding()]
    [OutputType([array])]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Description,

        [Parameter(Mandatory = $false)]
        [string[]]$Tags = @(),

        [Parameter(Mandatory = $false)]
        [int]$MaxExamples = 3
    )

    $descLower = $Description.ToLower()
    $scoredExamples = @()
    
    foreach ($example in $script:ConfigExamples) {
        $score = 0.0
        
        # Match against example description
        $exampleDescLower = $example.description.ToLower()
        $descWords = $descLower -split '\s+' | Where-Object { $_.Length -gt 3 }
        foreach ($word in $descWords) {
            if ($exampleDescLower -match $word) {
                $score += 0.1
            }
        }
        
        # Match against tags
        foreach ($tag in $Tags) {
            $tagLower = $tag.ToLower()
            if ($example.tags -contains $tagLower) {
                $score += 0.2
            }
        }
        
        # Check for pack match
        if ($example.config.packId -and $descLower -match $example.config.packId) {
            $score += 0.3
        }
        
        if ($score -gt 0) {
            $scoredExamples += [PSCustomObject]@{
                Example = $example
                Score = [math]::Min($score, 1.0)
            }
        }
    }
    
    return $scoredExamples | 
        Sort-Object -Property Score -Descending | 
        Select-Object -First $MaxExamples | 
        ForEach-Object { $_.Example }
}

<#
.SYNOPSIS
    Creates a configuration template from description.

.DESCRIPTION
    Generates a reusable configuration template.

.PARAMETER Description
    Natural language description.

.PARAMETER Name
    Template name.

.PARAMETER Parameters
    Template parameters.

.OUTPUTS
    Hashtable containing the template.

.EXAMPLE
    New-ConfigTemplate -Description "track {pack} with {trust} trust" -Name "pack-with-trust"
#>
function New-ConfigTemplate {
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Description,

        [Parameter(Mandatory = $true)]
        [string]$Name,

        [Parameter(Mandatory = $false)]
        [hashtable]$Parameters = @{},

        [Parameter(Mandatory = $false)]
        [hashtable]$DefaultValues = @{}
    )

    # Parse description for parameter placeholders
    $placeholderPattern = '\{(\w+)\}'
    $matches = [regex]::Matches($Description, $placeholderPattern)
    $templateParams = @()
    
    foreach ($match in $matches) {
        $paramName = $match.Groups[1].Value
        if ($templateParams -notcontains $paramName) {
            $templateParams += $paramName
        }
    }
    
    # Generate base config from description
    $baseConfig = New-ConfigFromDescription -Text $Description
    
    # Create template
    $template = @{
        name = $Name
        description = $Description
        baseConfig = $baseConfig
        parameters = $templateParams
        parameterDefinitions = @{}
        defaults = $DefaultValues
        createdAt = (Get-Date -Format 'o')
    }
    
    # Add parameter definitions
    foreach ($param in $templateParams) {
        $template.parameterDefinitions[$param] = @{
            required = -not $DefaultValues.ContainsKey($param)
            defaultValue = if ($DefaultValues.ContainsKey($param)) { $DefaultValues[$param] } else { $null }
        }
    }
    
    return $template
}

<#
.SYNOPSIS
    Expands a template with provided values.

.DESCRIPTION
    Fills in template parameters with actual values.

.PARAMETER Template
    The template to expand.

.PARAMETER Values
    Parameter values.

.OUTPUTS
    Hashtable with expanded configuration.

.EXAMPLE
    Expand-ConfigTemplate -Template $template -Values @{ pack = 'godot-engine'; trust = 'high' }
#>
function Expand-ConfigTemplate {
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [Parameter(Mandatory = $true)]
        [hashtable]$Template,

        [Parameter(Mandatory = $true)]
        [hashtable]$Values
    )

    $config = $Template.baseConfig.Clone()
    
    # Merge with defaults
    $allValues = $Template.defaults.Clone()
    foreach ($key in $Values.Keys) {
        $allValues[$key] = $Values[$key]
    }
    
    # Replace placeholders in description to understand intent
    $description = $Template.description
    foreach ($param in $Template.parameters) {
        if ($allValues.ContainsKey($param)) {
            $description = $description -replace "\{$param\}", $allValues[$param]
        }
    }
    
    # Re-parse with actual values
    $parsedConfig = New-ConfigFromDescription -Text $description
    
    # Merge parsed config with template base
    foreach ($key in $parsedConfig.Keys) {
        if (-not $key.StartsWith('_')) {
            $config[$key] = $parsedConfig[$key]
        }
    }
    
    return $config
}

<#
.SYNOPSIS
    Registers a new configuration pattern.

.DESCRIPTION
    Adds a new pattern to the configuration patterns database.

.PARAMETER Category
    Pattern category (packs, schedules, notifications, etc.).

.PARAMETER Pattern
    Pattern string to match.

.PARAMETER Intent
    Intent identifier.

.PARAMETER Metadata
    Additional metadata for the pattern.

.EXAMPLE
    Register-ConfigPattern -Category 'packs' -Pattern 'unity' -Intent 'pack.unity' -Metadata @{ packId = 'unity-engine' }
#>
function Register-ConfigPattern {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [ValidateSet('packs', 'schedules', 'notifications', 'filters', 'providers', 'executionModes')]
        [string]$Category,

        [Parameter(Mandatory = $true)]
        [string]$Pattern,

        [Parameter(Mandatory = $true)]
        [string]$Intent,

        [Parameter(Mandatory = $false)]
        [hashtable]$Metadata = @{},

        [Parameter(Mandatory = $false)]
        [double]$Confidence = 0.8
    )

    $patternData = @{
        intent = $Intent
        confidence = $Confidence
    }
    
    # Add metadata
    foreach ($key in $Metadata.Keys) {
        $patternData[$key] = $Metadata[$key]
    }
    
    # Register pattern
    $script:ConfigPatterns[$Category][$Pattern.ToLower()] = $patternData
    
    Write-Verbose "Registered pattern '$Pattern' in category '$Category' with intent '$Intent'"
}

<#
.SYNOPSIS
    Starts an interactive configuration wizard.

.DESCRIPTION
    Guides the user through configuration via interactive prompts.

.PARAMETER InitialResult
    Optional initial parsing result to start from.

.PARAMETER Context
    Optional context information.

.OUTPUTS
    PSCustomObject with final configuration.

.EXAMPLE
    Start-InteractiveConfig
#>
function Start-InteractiveConfig {
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Mandatory = $false)]
        [PSCustomObject]$InitialResult = $null,

        [Parameter(Mandatory = $false)]
        [hashtable]$Context = @{}
    )

    # Initialize wizard state
    $script:WizardState.Active = $true
    $script:WizardState.CurrentStep = 0
    $script:WizardState.Answers = @{}
    $script:WizardState.Context = $Context
    
    if ($InitialResult) {
        $script:WizardState.GeneratedConfig = $InitialResult.Config
        $script:WizardState.Questions = $InitialResult.ClarificationQuestions
    }
    else {
        $script:WizardState.GeneratedConfig = @{}
        $script:WizardState.Questions = @()
    }
    
    Write-Host "`n=== LLM Workflow Configuration Wizard ===" -ForegroundColor Cyan
    Write-Host "Answer the following questions to complete your configuration.`n" -ForegroundColor Gray
    
    # Process questions
    while ($script:WizardState.CurrentStep -lt $script:WizardState.Questions.Count) {
        $question = Get-NextConfigQuestion
        if (-not $question) { break }
        
        Write-Host "`nQuestion $($script:WizardState.CurrentStep + 1) of $($script:WizardState.Questions.Count):" -ForegroundColor Yellow
        
        # Display question
        Write-Host $question.question -ForegroundColor White
        
        if ($question.type -eq 'choice' -and $question.options) {
            for ($i = 0; $i -lt $question.options.Count; $i++) {
                Write-Host "  [$i] $($question.options[$i])" -ForegroundColor Gray
            }
        }
        
        if ($question.defaultValue) {
            Write-Host "  [Default: $($question.defaultValue)]" -ForegroundColor DarkGray
        }
        
        # Get answer (in a real implementation, this would read from user input)
        # For programmatic use, we'll use the default or skip
        $answer = $question.defaultValue
        
        Submit-ConfigAnswer -QuestionId $question.id -Answer $answer | Out-Null
    }
    
    return Complete-InteractiveConfig
}

<#
.SYNOPSIS
    Gets the next question in the wizard.

.DESCRIPTION
    Returns the next question for the interactive wizard.

.OUTPUTS
    Question object or null if wizard complete.

.EXAMPLE
    $question = Get-NextConfigQuestion
#>
function Get-NextConfigQuestion {
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param()

    if (-not $script:WizardState.Active) {
        return $null
    }
    
    if ($script:WizardState.CurrentStep -ge $script:WizardState.Questions.Count) {
        return $null
    }
    
    return $script:WizardState.Questions[$script:WizardState.CurrentStep]
}

<#
.SYNOPSIS
    Submits an answer and advances the wizard.

.DESCRIPTION
    Processes a user answer and moves to the next question.

.PARAMETER QuestionId
    ID of the question being answered.

.PARAMETER Answer
    The user's answer.

.OUTPUTS
    PSCustomObject with next step information.

.EXAMPLE
    Submit-ConfigAnswer -QuestionId 'packId' -Answer 'godot-engine'
#>
function Submit-ConfigAnswer {
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Mandatory = $true)]
        [string]$QuestionId,

        [Parameter(Mandatory = $true)]
        [object]$Answer
    )

    if (-not $script:WizardState.Active) {
        throw "Wizard is not active. Call Start-InteractiveConfig first."
    }
    
    # Store answer
    $script:WizardState.Answers[$QuestionId] = $Answer
    
    # Update generated config based on question type
    switch ($QuestionId) {
        'packId' { $script:WizardState.GeneratedConfig.packId = $Answer }
        'trustTier' { $script:WizardState.GeneratedConfig.trustTier = $Answer }
        'scheduleTime' { 
            # Parse time string and update schedule
            $scheduleConfig = New-ScheduleFromDescription -Text "daily at $Answer"
            $script:WizardState.GeneratedConfig.schedule = $scheduleConfig.schedule
        }
        'notificationType' {
            if (-not $script:WizardState.GeneratedConfig.notifications) {
                $script:WizardState.GeneratedConfig.notifications = @()
            }
            $script:WizardState.GeneratedConfig.notifications += @{
                type = $Answer
                event = 'execution.completed'
            }
        }
        'providerType' {
            if (-not $script:WizardState.GeneratedConfig.provider) {
                $script:WizardState.GeneratedConfig.provider = @{}
            }
            $script:WizardState.GeneratedConfig.provider.type = $Answer
        }
    }
    
    # Advance step
    $script:WizardState.CurrentStep++
    
    $nextQuestion = Get-NextConfigQuestion
    
    return [PSCustomObject]@{
        Success = $true
        NextQuestion = $nextQuestion
        IsComplete = ($null -eq $nextQuestion)
        Progress = "$($script:WizardState.CurrentStep) / $($script:WizardState.Questions.Count)"
    }
}

<#
.SYNOPSIS
    Completes the interactive configuration wizard.

.DESCRIPTION
    Finalizes the wizard and returns the completed configuration.

.PARAMETER SaveToFile
    Optional path to save the configuration.

.OUTPUTS
    PSCustomObject with final configuration.

.EXAMPLE
    $config = Complete-InteractiveConfig
#>
function Complete-InteractiveConfig {
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Mandatory = $false)]
        [string]$SaveToFile = $null
    )

    if (-not $script:WizardState.Active) {
        throw "Wizard is not active."
    }
    
    # Finalize config
    $config = $script:WizardState.GeneratedConfig.Clone()
    
    # Remove internal keys
    $keysToRemove = $config.Keys | Where-Object { $_.StartsWith('_') }
    foreach ($key in $keysToRemove) {
        $config.Remove($key)
    }
    
    # Add completion metadata
    $config._completedViaWizard = $true
    $config._completedAt = (Get-Date -Format 'o')
    
    # Save if requested
    if ($SaveToFile) {
        $config | ConvertTo-Json -Depth 10 | Out-File -FilePath $SaveToFile -Encoding UTF8
        Write-Verbose "Configuration saved to: $SaveToFile"
    }
    
    # Reset wizard state
    $script:WizardState.Active = $false
    $script:WizardState.CurrentStep = 0
    $script:WizardState.Questions = @()
    
    # Generate explanation
    $explanation = Get-ConfigExplanation -Config $config
    
    return [PSCustomObject]@{
        Success = $true
        Config = $config
        Answers = $script:WizardState.Answers
        Explanation = $explanation
    }
}

<#
.SYNOPSIS
    Converts configuration to natural language explanation.

.DESCRIPTION
    Generates human-readable explanation of configuration.

.PARAMETER Config
    Configuration to explain.

.OUTPUTS
    String with natural language explanation.

.EXAMPLE
    ConvertTo-NaturalLanguageConfig -Config $myConfig
#>
function ConvertTo-NaturalLanguageConfig {
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory = $true, ValueFromPipeline = $true)]
        [hashtable]$Config
    )

    process {
        return Get-ConfigExplanation -Config $Config
    }
}

<#
.SYNOPSIS
    Gets human-readable explanation of configuration.

.DESCRIPTION
    Generates a detailed explanation of what a configuration does.

.PARAMETER Config
    Configuration to explain.

.PARAMETER Format
    Output format: 'text', 'bullet', or 'structured'.

.OUTPUTS
    String or structured explanation.

.EXAMPLE
    Get-ConfigExplanation -Config $myConfig
#>
function Get-ConfigExplanation {
    [CmdletBinding()]
    [OutputType([object])]
    param(
        [Parameter(Mandatory = $true)]
        [hashtable]$Config,

        [Parameter(Mandatory = $false)]
        [ValidateSet('text', 'bullet', 'structured')]
        [string]$Format = 'text'
    )

    $explanations = @()
    
    # Explain pack configuration
    if ($Config.packId) {
        $packName = $Config.packId
        $profileText = if ($Config.installProfile) { " using the '$($Config.installProfile)' profile" } else { '' }
        $trustText = if ($Config.trustTier) { " with $($Config.trustTier) trust settings" } else { '' }
        $explanations += "Tracks the '$packName' pack$profileText$trustText."
        
        if ($Config.trustOverrides) {
            $overrideCount = $Config.trustOverrides.Count
            $explanations += "  - Applies custom trust overrides for $overrideCount specific sources."
        }
        
        if ($Config.collections) {
            $collectionList = $Config.collections -join ', '
            $explanations += "  - Includes collections: $collectionList."
        }
    }
    
    # Explain schedule
    if ($Config.schedule) {
        $scheduleDesc = Convert-CronToDescription -CronExpression $Config.schedule
        $explanations += "Runs on a schedule: $scheduleDesc."
    }
    
    # Explain notifications
    if ($Config.notifications) {
        if ($Config.notifications -is [array]) {
            foreach ($notif in $Config.notifications) {
                if ($notif.enabled -ne $false) {
                    $type = $notif.type
                    $event = $notif.event -replace '\.', ' '
                    $explanations += "Sends $type notifications when $event."
                }
            }
        }
        elseif ($Config.notifications.enabled -eq $false) {
            $explanations += "Notifications are disabled."
        }
    }
    
    # Explain provider
    if ($Config.provider) {
        $providerParts = @()
        if ($Config.provider.type) {
            $providerParts += "uses the '$($Config.provider.type)' provider"
        }
        if ($Config.provider.model) {
            $providerParts += "model '$($Config.provider.model)'"
        }
        if ($null -ne $Config.provider.temperature) {
            $tempDesc = if ($Config.provider.temperature -gt 0.7) { 'creative' } else { 'focused' }
            $providerParts += "with $tempDesc temperature ($($Config.provider.temperature))"
        }
        if ($providerParts.Count -gt 0) {
            $explanations += "Configuration $($providerParts -join ', ')."
        }
    }
    
    # Explain execution mode
    if ($Config.execution -and $Config.execution.mode) {
        $explanations += "Runs in '$($Config.execution.mode)' execution mode."
    }
    
    # Explain filters
    if ($Config.filters) {
        if ($Config.filters.useCase) {
            $explanations += "Filter preset: $($Config.filters.useCase)."
        }
        if ($Config.filters.includeExtensions) {
            $extList = $Config.filters.includeExtensions -join ', '
            $explanations += "  - Includes file types: $extList"
        }
    }
    
    switch ($Format) {
        'text' {
            return $explanations -join ' '
        }
        'bullet' {
            return ($explanations | ForEach-Object { "- $_" }) -join "`n"
        }
        'structured' {
            return [PSCustomObject]@{
                Explanations = $explanations
                Summary = $explanations -join ' '
                Config = $Config
            }
        }
        default {
            return $explanations -join ' '
        }
    }
}

<#
.SYNOPSIS
    Converts cron expression to human-readable description.

.DESCRIPTION
    Internal helper to convert cron to natural language.

.PARAMETER CronExpression
    Cron expression to convert.

.OUTPUTS
    String description.
#>
function Convert-CronToDescription {
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory = $true)]
        [string]$CronExpression
    )

    $parts = $CronExpression -split '\s+'
    if ($parts.Count -ne 5) {
        return "custom schedule ($CronExpression)"
    }
    
    $minute = $parts[0]
    $hour = $parts[1]
    $day = $parts[2]
    $month = $parts[3]
    $weekday = $parts[4]
    
    # Common patterns
    if ($minute -eq '0' -and $hour -eq '0' -and $day -eq '*' -and $month -eq '*' -and $weekday -eq '*') {
        return "daily at midnight"
    }
    if ($minute -eq '0' -and $hour -eq '*' -and $day -eq '*' -and $month -eq '*' -and $weekday -eq '*') {
        return "every hour"
    }
    if ($minute -eq '*' -and $hour -eq '*' -and $day -eq '*' -and $month -eq '*' -and $weekday -eq '*') {
        return "every minute"
    }
    if ($minute -eq '0' -and $hour -eq '0' -and $day -eq '*' -and $month -eq '*' -and $weekday -eq '0') {
        return "weekly on Sunday at midnight"
    }
    if ($minute -eq '0' -and $hour -eq '0' -and $day -eq '1' -and $month -eq '*' -and $weekday -eq '*') {
        return "monthly on the 1st at midnight"
    }
    
    # Specific time
    if ($day -eq '*' -and $month -eq '*' -and $weekday -eq '*') {
        $hourStr = if ($hour -eq '0') { '12 AM' } elseif ([int]$hour -lt 12) { "$hour AM" } elseif ($hour -eq '12') { '12 PM' } else { "$([int]$hour - 12) PM" }
        $minuteStr = if ($minute -eq '0') { '' } else { ":$minute" }
        return "daily at $hourStr$minuteStr"
    }
    
    return "custom schedule: $CronExpression"
}

<#
.SYNOPSIS
    Merges generated config with base configuration.

.DESCRIPTION
    Internal helper to merge configurations.

.PARAMETER Generated
    Generated configuration.

.PARAMETER Base
    Base configuration to merge into.

.OUTPUTS
    Merged configuration hashtable.
#>
function Merge-GeneratedConfig {
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [Parameter(Mandatory = $true)]
        [hashtable]$Generated,

        [Parameter(Mandatory = $true)]
        [hashtable]$Base
    )

    $merged = $Base.Clone()
    
    foreach ($key in $Generated.Keys) {
        if ($key.StartsWith('_')) { continue }
        
        if ($merged.ContainsKey($key) -and $merged[$key] -is [hashtable] -and $Generated[$key] -is [hashtable]) {
            # Deep merge nested hashtables
            $merged[$key] = Merge-GeneratedConfig -Generated $Generated[$key] -Base $merged[$key]
        }
        else {
            $merged[$key] = $Generated[$key]
        }
    }
    
    return $merged
}

# Export all public functions
Export-ModuleMember -Function @(
    # Intent Parsing
    'ConvertFrom-NaturalLanguageConfig',
    'Get-ConfigIntent',
    'Get-ConfigEntities',
    'Test-ConfigIntent',
    
    # Config Generation
    'New-ConfigFromDescription',
    'New-PackConfigFromDescription',
    'New-FilterFromDescription',
    'New-ScheduleFromDescription',
    
    # Validation & Clarification
    'Test-GeneratedConfig',
    'Get-ConfigClarificationQuestions',
    'Measure-ConfigConfidence',
    'Get-ConfigAlternatives',
    
    # Examples & Templates
    'Get-ConfigExample',
    'New-ConfigTemplate',
    'Expand-ConfigTemplate',
    'Register-ConfigPattern',
    
    # Interactive Generation
    'Start-InteractiveConfig',
    'Get-NextConfigQuestion',
    'Submit-ConfigAnswer',
    'Complete-InteractiveConfig',
    
    # Explanation
    'ConvertTo-NaturalLanguageConfig',
    'Get-ConfigExplanation'
)
