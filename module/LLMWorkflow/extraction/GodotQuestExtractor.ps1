#Requires -Version 5.1
<#
.SYNOPSIS
    Godot Quest System extractor for LLM Workflow Extraction Pipeline.

.DESCRIPTION
    Extracts structured quest data from Godot quest systems.
    Supports multiple quest frameworks including:
    - shomykohai/quest-system (Quest Resource-based)
    - bitbrain/pandora (entity component-based quest data)
    - Custom quest implementations (Resource, JSON, GDScript)
    
    Extracts quest resources, objectives, prerequisites, rewards, and state machines from:
    - .tres files (Quest resources)
    - .gd files (Quest scripts)
    - .json files (Quest data exports)
    - .cfg files (Quest configuration)
    
    This parser implements Section 25.7 of the canonical architecture for the
    Godot Engine pack's structured extraction pipeline.

.REQUIRED FUNCTIONS
    - Export-QuestSystem: Extract quest system configuration
    - Export-QuestDefinitions: Extract quest data
    - Export-QuestObjectives: Extract objectives/tasks
    - Get-QuestGraph: Build quest dependency graph
    - Export-QuestRewards: Extract reward definitions
    - Get-QuestMetrics: Calculate quest system metrics

.PARAMETER Path
    Path to the quest file to parse.

.PARAMETER Content
    File content string (alternative to Path).

.PARAMETER Format
    Format of the quest file (auto, quest_system, pandora, json, gdscript).

.OUTPUTS
    JSON with quest definitions, objective hierarchies, prerequisite graphs,
    reward mappings, and provenance metadata (source file, extraction timestamp, parser version).

.NOTES
    File Name      : GodotQuestExtractor.ps1
    Author         : LLM Workflow Team
    Version        : 2.0.0
    Prerequisite   : PowerShell 5.1+
    Copyright      : (c) 2026 LLM Workflow Project
    License        : MIT
    Pack           : godot-engine
#>

Set-StrictMode -Version Latest

# ============================================================================
# Module Constants and Version
# ============================================================================

$script:ParserVersion = '2.0.0'
$script:ParserName = 'GodotQuestExtractor'

# Supported file formats
$script:SupportedFormats = @('auto', 'quest_system', 'pandora', 'json', 'gdscript', 'tres')

# Quest states
$script:QuestStates = @('available', 'active', 'completed', 'failed', 'locked', 'turned_in')

# Objective types
$script:ObjectiveTypes = @('kill', 'collect', 'interact', 'escort', 'reach', 'craft', 'talk', 'use', 'custom')

# Regex Patterns for Quest Parsing
$script:QuestPatterns = @{
    # Quest Resource patterns (.tres files)
    QuestResource = '\[resource\]|\[ext_resource.*?path=".*?quest'
    QuestId = '(?:quest_id|id)\s*=\s*["\'](?<id>[^"\']+)["\']'
    QuestTitle = '(?:title|quest_name|name)\s*=\s*["\'](?<title>[^"\']+)["\']'
    QuestDescription = '(?:description|desc|quest_description)\s*=\s*["\'](?<desc>[^"\']*?)["\']'
    QuestStatus = '(?:status|state|quest_status)\s*=\s*(?<status>\w+)'
    QuestCategory = '(?:category|quest_category|type)\s*=\s*["\'](?<cat>[^"\']+)["\']'
    QuestLevel = '(?:level|required_level|min_level)\s*=\s*(?<level>\d+)'
    QuestGiver = '(?:quest_giver|giver|source_npc|npc)\s*=\s*["\'](?<giver>[^"\']+)["\']'
    QuestReceiver = '(?:turn_in|receiver|target_npc)\s*=\s*["\'](?<receiver>[^"\']+)["\']'
    QuestIsMain = '(?:is_main_quest|main_story|is_story)\s*=\s*(?<main>true|false)'
    QuestIsRepeatable = '(?:is_repeatable|repeatable|can_repeat)\s*=\s*(?<rep>true|false)'
    QuestIsHidden = '(?:is_hidden|hidden|secret)\s*=\s*(?<hidden>true|false)'
    QuestTimeLimit = '(?:time_limit|timeout|duration)\s*=\s*(?<time>[\d.]+)'
    QuestExperience = '(?:xp|exp|experience|reward_xp)\s*=\s*(?<xp>\d+)'
    QuestNextQuest = '(?:next_quest|leads_to|unlocks)\s*=\s*["\'](?<next>[^"\']+)["\']'
    
    # Objective patterns
    ObjectiveId = '(?:objective_id|objective_name|task_id)\s*=\s*["\'](?<id>[^"\']+)["\']'
    ObjectiveDescription = '(?:objective_description|task_desc|objective_text)\s*=\s*["\'](?<desc>[^"\']*?)["\']'
    ObjectiveType = '(?:objective_type|task_type)\s*=\s*["\'](?<type>\w+)["\']'
    ObjectiveTarget = '(?:target|target_id|target_entity)\s*=\s*["\'](?<target>[^"\']+)["\']'
    ObjectiveCount = '(?:count|amount|required|target_count)\s*=\s*(?<count>\d+)'
    ObjectiveProgress = '(?:progress|current|completed_count)\s*=\s*(?<prog>\d+)'
    ObjectiveOptional = '(?:is_optional|optional)\s*=\s*(?<opt>true|false)'
    ObjectiveOrder = '(?:order|sequence|priority)\s*=\s*(?<order>\d+)'
    ObjectiveLocation = '(?:location|area|zone|map)\s*=\s*["\'](?<loc>[^"\']+)["\']'
    
    # Prerequisite patterns
    PrerequisiteQuest = '(?:prerequisite|requires_quest|required_quest|prereq)\s*=\s*["\'](?<prereq>[^"\']+)["\']'
    PrerequisiteLevel = '(?:prereq_level|required_level)\s*=\s*(?<level>\d+)'
    PrerequisiteItem = '(?:requires_item|required_item)\s*=\s*["\'](?<item>[^"\']+)["\']'
    PrerequisiteFlag = '(?:requires_flag|condition|prereq_condition)\s*=\s*["\'](?<flag>[^"\']+)["\']'
    PrerequisiteList = '(?:prerequisites|requirements)\s*=\s*\[(?<list>[^\]]*)\]'
    
    # Reward patterns
    RewardItemId = '(?:reward_item|item_reward|give_item)\s*=\s*["\'](?<item>[^"\']+)["\']'
    RewardItemCount = '(?:reward_count|item_count|amount)\s*=\s*(?<count>\d+)'
    RewardGold = '(?:reward_gold|gold|money|currency)\s*=\s*(?<gold>\d+)'
    RewardExperience = '(?:reward_xp|xp_reward|experience)\s*=\s*(?<xp>\d+)'
    RewardSkill = '(?:reward_skill|unlock_skill|learn)\s*=\s*["\'](?<skill>[^"\']+)["\']'
    RewardUnlock = '(?:unlock|unlock_quest|unlocks_area)\s*=\s*["\'](?<unlock>[^"\']+)["\']'
    RewardReputation = '(?:reputation|rep|standing)\s*=\s*(?<rep>-?\d+)'
    RewardFaction = '(?:faction|reputation_faction)\s*=\s*["\'](?<fac>[^"\']+)["\']'
    
    # shomykohai/quest-system specific
    QuestSystemResource = 'class_name\s+Quest|extends\s+Quest'
    QuestArray = '@export\s+var\s+quests\s*:\s*Array\[Quest\]'
    ObjectiveArray = '@export\s+var\s+objectives\s*:\s*Array\[Objective\]'
    QuestStepNode = '\[node\s+name="QuestStep"'
    
    # bitbrain/pandora specific
    PandoraEntity = 'class\s+PandoraEntity|pandora_entity'
    PandoraCategory = '\[category\s+name="(?<cat>[^"]+)"'
    PandoraProperty = '\[property\s+name="(?<prop>[^"]+)".*?value="(?<val>[^"]*)"'
    PandoraQuestComponent = 'QuestComponent|quest_component'
    
    # GDScript quest patterns
    QuestClass = 'class\s+\w+Quest|class_name\s+\w*Quest'
    QuestStateEnum = 'enum\s+QuestState|enum\s+State'
    QuestSignal = 'signal\s+quest_(?<signal>\w+)'
    QuestExport = '@export\s+var\s+quest_(?<field>\w+)'
    
    # JSON quest patterns
    JsonQuestArray = '"quests"\s*:\s*\['
    JsonQuestId = '"quest_id"\s*:\s*"(?<id>[^"]+)"'
    JsonObjectiveArray = '"objectives"\s*:\s*\['
    JsonRewardArray = '"rewards"\s*:\s*\['
    JsonPrerequisiteArray = '"prerequisites"\s*:\s*\['
    
    # State machine patterns
    StateAvailable = 'STATE_AVAILABLE|STATE_NOT_STARTED'
    StateActive = 'STATE_ACTIVE|STATE_IN_PROGRESS'
    StateCompleted = 'STATE_COMPLETED|STATE_DONE'
    StateFailed = 'STATE_FAILED|STATE_ABORTED'
    StateTransition = 'change_state|set_state|transition_to'
}

# ============================================================================
# Private Helper Functions
# ============================================================================

<#
.SYNOPSIS
    Creates provenance metadata for extraction results.
.DESCRIPTION
    Generates standardized metadata including source file, extraction timestamp,
    and parser version for tracking extraction provenance.
.PARAMETER SourceFile
    Path to the source file being parsed.
.PARAMETER Success
    Whether the extraction was successful.
.PARAMETER Errors
    Array of error messages.
.OUTPUTS
    System.Collections.Hashtable. Provenance metadata object.
#>
function New-ProvenanceMetadata {
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [Parameter(Mandatory = $true)]
        [string]$SourceFile,
        
        [Parameter()]
        [bool]$Success = $true,
        
        [Parameter()]
        [array]$Errors = @()
    )
    
    return @{
        sourceFile = $SourceFile
        extractionTimestamp = [DateTime]::UtcNow.ToString("o")
        parserName = $script:ParserName
        parserVersion = $script:ParserVersion
        success = $Success
        errors = $Errors
    }
}

<#
.SYNOPSIS
    Detects the quest format from file content.
.DESCRIPTION
    Analyzes the content to determine the quest file format.
.PARAMETER Content
    The file content to analyze.
.PARAMETER Extension
    The file extension.
.OUTPUTS
    System.String. The detected format.
#>
function Get-QuestFormat {
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Content,
        
        [Parameter()]
        [string]$Extension = ''
    )
    
    # Check extension first
    switch ($Extension.ToLower()) {
        '.tres' { return 'quest_system' }
        '.quest' { return 'quest_system' }
        '.json' { return 'json' }
        '.gd' { return 'gdscript' }
        '.cfg' { return 'quest_system' }
    }
    
    # Check content patterns for shomykohai/quest-system
    if ($Content -match $script:QuestPatterns.QuestSystemResource -or
        $Content -match 'class_name\s+Quest\s' -or
        $Content -match 'extends\s+QuestResource') {
        return 'quest_system'
    }
    
    # Check content patterns for bitbrain/pandora
    if ($Content -match $script:QuestPatterns.PandoraEntity -or
        $Content -match 'pandora_category' -or
        $Content -match '\[pandora_entity\]') {
        return 'pandora'
    }
    
    # Check for JSON quest format
    if ($Content -match '"quests"\s*:' -or 
        ($Content -match '"quest_id"' -and $Content -match '"objectives"')) {
        return 'json'
    }
    
    # Check for GDScript quest class
    if ($Content -match $script:QuestPatterns.QuestClass -or
        $Content -match '@export\s+var\s+quest_') {
        return 'gdscript'
    }
    
    # Default to quest_system for .tres-like content
    if ($Content -match '\[gd_resource\]' -or $Content -match '\[resource\]') {
        return 'quest_system'
    }
    
    return 'quest_system'
}

<#
.SYNOPSIS
    Parses prerequisite list from a string.
.DESCRIPTION
    Extracts prerequisite quest IDs from a comma-separated list or array notation.
.PARAMETER PrereqString
    The prerequisite string to parse.
.OUTPUTS
    System.Array. Array of prerequisite quest IDs.
#>
function Get-PrerequisiteList {
    [CmdletBinding()]
    [OutputType([array])]
    param(
        [Parameter(Mandatory = $true)]
        [string]$PrereqString
    )
    
    $prereqs = @()
    
    # Handle array notation ["quest1", "quest2"]
    if ($PrereqString -match '^\s*\[.*\]\s*$') {
        $items = $PrereqString -replace '^\s*\[\s*' -replace '\s*\]\s*$'
        $items = $items -split '\s*,\s*'
        foreach ($item in $items) {
            $cleanItem = $item -replace '^["\']' -replace '["\']$' -replace '\s+', ''
            if ($cleanItem) {
                $prereqs += $cleanItem
            }
        }
    }
    else {
        # Single prerequisite
        $prereqs += $PrereqString.Trim() -replace '^["\']' -replace '["\']$'
    }
    
    return $prereqs | Where-Object { $_ }
}

<#
.SYNOPSIS
    Extracts objectives from quest content.
.DESCRIPTION
    Parses quest content and extracts objective definitions.
.PARAMETER Content
    The quest content to parse.
.PARAMETER Format
    The quest format.
.OUTPUTS
    System.Array. Array of objective objects.
#>
function Get-QuestObjectivesFromContent {
    [CmdletBinding()]
    [OutputType([array])]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Content,
        
        [Parameter()]
        [string]$Format = 'quest_system'
    )
    
    $objectives = @()
    
    switch ($Format) {
        'quest_system' {
            # Look for objective sections in .tres format
            $objectiveSections = [regex]::Matches($Content, '(?s)(sub_resource\s*\(\s*type="Objective".*?\)|\[objective\].*?)(?=sub_resource|\[objective\]|\z)')
            
            foreach ($section in $objectiveSections) {
                $objContent = $section.Value
                $objective = @{
                    objective_id = ''
                    description = ''
                    type = 'custom'
                    target = ''
                    required_count = 1
                    current_progress = 0
                    is_optional = $false
                    order = 0
                    location = ''
                }
                
                # Extract objective ID
                if ($objContent -match $script:QuestPatterns.ObjectiveId) {
                    $objective.objective_id = $matches['id']
                }
                
                # Extract description
                if ($objContent -match $script:QuestPatterns.ObjectiveDescription) {
                    $objective.description = $matches['desc']
                }
                
                # Extract type
                if ($objContent -match $script:QuestPatterns.ObjectiveType) {
                    $objective.type = $matches['type'].ToLower()
                }
                
                # Extract target
                if ($objContent -match $script:QuestPatterns.ObjectiveTarget) {
                    $objective.target = $matches['target']
                }
                
                # Extract count
                if ($objContent -match $script:QuestPatterns.ObjectiveCount) {
                    $objective.required_count = [int]$matches['count']
                }
                
                # Extract progress
                if ($objContent -match $script:QuestPatterns.ObjectiveProgress) {
                    $objective.current_progress = [int]$matches['prog']
                }
                
                # Extract optional flag
                if ($objContent -match $script:QuestPatterns.ObjectiveOptional) {
                    $objective.is_optional = $matches['opt'] -eq 'true'
                }
                
                # Extract order
                if ($objContent -match $script:QuestPatterns.ObjectiveOrder) {
                    $objective.order = [int]$matches['order']
                }
                
                # Extract location
                if ($objContent -match $script:QuestPatterns.ObjectiveLocation) {
                    $objective.location = $matches['loc']
                }
                
                if ($objective.objective_id -or $objective.description) {
                    $objectives += $objective
                }
            }
        }
        
        'pandora' {
            # Parse pandora entity properties for objectives
            $propertyMatches = [regex]::Matches($Content, '\[property\s+name="(?<name>[^"]+)".*?value="(?<val>[^"]*)"')
            
            $currentObjective = $null
            foreach ($match in $propertyMatches) {
                $propName = $match.Groups['name'].Value
                $propValue = $match.Groups['val'].Value
                
                if ($propName -match 'objective_?(\d+)_?id' -or $propName -match 'task_?(\d+)') {
                    if ($currentObjective) {
                        $objectives += $currentObjective
                    }
                    $currentObjective = @{
                        objective_id = $propValue
                        description = ''
                        type = 'custom'
                        target = ''
                        required_count = 1
                        current_progress = 0
                        is_optional = $false
                        order = if ($matches[1]) { [int]$matches[1] } else { 0 }
                        location = ''
                    }
                }
                elseif ($currentObjective) {
                    switch -Regex ($propName) {
                        'desc|description' { $currentObjective.description = $propValue }
                        'type' { $currentObjective.type = $propValue.ToLower() }
                        'target' { $currentObjective.target = $propValue }
                        'count|amount|required' { $currentObjective.required_count = [int]$propValue }
                        'optional' { $currentObjective.is_optional = $propValue -eq 'true' }
                    }
                }
            }
            
            if ($currentObjective) {
                $objectives += $currentObjective
            }
        }
        
        'json' {
            try {
                $json = $Content | ConvertFrom-Json
                if ($json.objectives) {
                    foreach ($obj in $json.objectives) {
                        $objectives += @{
                            objective_id = $obj.id -or $obj.objective_id -or "objective_$($objectives.Count + 1)"
                            description = $obj.description -or $obj.desc -or $obj.text -or ''
                            type = ($obj.type -or 'custom').ToLower()
                            target = $obj.target -or $obj.target_id -or ''
                            required_count = $obj.count -or $obj.required -or $obj.amount -or 1
                            current_progress = $obj.progress -or $obj.current -or 0
                            is_optional = $obj.optional -or $obj.is_optional -or $false
                            order = $obj.order -or $obj.sequence -or 0
                            location = $obj.location -or $obj.area -or ''
                        }
                    }
                }
            }
            catch {
                Write-Verbose "Failed to parse JSON objectives: $_"
            }
        }
        
        'gdscript' {
            # Parse GDScript objective arrays or dictionaries
            $lines = $Content -split "`r?`n"
            $inObjectiveBlock = $false
            $braceDepth = 0
            $currentObjective = $null
            
            foreach ($line in $lines) {
                if ($line -match '@export\s+var\s+objectives' -or 
                    $line -match 'var\s+objectives\s*=' -or
                    $line -match 'objectives\s*=\s*\[') {
                    $inObjectiveBlock = $true
                    $braceDepth = 0
                }
                
                if ($inObjectiveBlock) {
                    $braceDepth += (($line -creplace '[^{\[]').Length) - (($line -creplace '[^}\]]').Length)
                    
                    # Parse objective entry
                    if ($line -match '"id"\s*:\s*"([^"]+)"') {
                        if ($currentObjective) {
                            $objectives += $currentObjective
                        }
                        $currentObjective = @{
                            objective_id = $matches[1]
                            description = ''
                            type = 'custom'
                            target = ''
                            required_count = 1
                            current_progress = 0
                            is_optional = $false
                            order = 0
                            location = ''
                        }
                    }
                    
                    if ($currentObjective) {
                        if ($line -match '"desc"\s*:\s*"([^"]*)"') {
                            $currentObjective.description = $matches[1]
                        }
                        if ($line -match '"type"\s*:\s*"(\w+)"') {
                            $currentObjective.type = $matches[1].ToLower()
                        }
                        if ($line -match '"target"\s*:\s*"([^"]+)"') {
                            $currentObjective.target = $matches[1]
                        }
                        if ($line -match '"count"\s*:\s*(\d+)') {
                            $currentObjective.required_count = [int]$matches[1]
                        }
                    }
                    
                    if ($braceDepth -le 0 -and ($line -match '\]' -or $line -match '\}')) {
                        $inObjectiveBlock = $false
                        if ($currentObjective) {
                            $objectives += $currentObjective
                            $currentObjective = $null
                        }
                    }
                }
            }
            
            if ($currentObjective) {
                $objectives += $currentObjective
            }
        }
    }
    
    return $objectives
}

<#
.SYNOPSIS
    Extracts rewards from quest content.
.DESCRIPTION
    Parses quest content and extracts reward definitions.
.PARAMETER Content
    The quest content to parse.
.PARAMETER Format
    The quest format.
.OUTPUTS
    System.Array. Array of reward objects.
#>
function Get-QuestRewardsFromContent {
    [CmdletBinding()]
    [OutputType([array])]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Content,
        
        [Parameter()]
        [string]$Format = 'quest_system'
    )
    
    $rewards = @{
        items = @()
        experience = 0
        gold = 0
        skills = @()
        unlocks = @()
        reputation = @()
    }
    
    switch ($Format) {
        'quest_system' {
            # Extract experience
            if ($Content -match $script:QuestPatterns.RewardExperience) {
                $rewards.experience = [int]$matches['xp']
            }
            
            # Extract gold
            if ($Content -match $script:QuestPatterns.RewardGold) {
                $rewards.gold = [int]$matches['gold']
            }
            
            # Extract item rewards
            $itemMatches = [regex]::Matches($Content, '(?s)reward_item.*?item_id\s*=\s*["\']([^"\']+)["\']')
            foreach ($match in $itemMatches) {
                $item = @{
                    item_id = $match.Groups[1].Value
                    count = 1
                }
                
                # Look for count in surrounding context
                $context = $Content.Substring([Math]::Max(0, $match.Index - 100), [Math]::Min(200, $Content.Length - $match.Index))
                if ($context -match $script:QuestPatterns.RewardItemCount) {
                    $item.count = [int]$matches['count']
                }
                
                $rewards.items += $item
            }
            
            # Also check for simple item_reward patterns
            if ($Content -match $script:QuestPatterns.RewardItemId) {
                $existingItem = $rewards.items | Where-Object { $_.item_id -eq $matches['item'] }
                if (-not $existingItem) {
                    $rewards.items += @{
                        item_id = $matches['item']
                        count = 1
                    }
                }
            }
            
            # Extract skill unlocks
            $skillMatches = [regex]::Matches($Content, $script:QuestPatterns.RewardSkill)
            foreach ($match in $skillMatches) {
                $rewards.skills += $matches['skill']
            }
            
            # Extract quest/area unlocks
            $unlockMatches = [regex]::Matches($Content, $script:QuestPatterns.RewardUnlock)
            foreach ($match in $unlockMatches) {
                $rewards.unlocks += @{
                    type = 'quest'
                    id = $matches['unlock']
                }
            }
            
            # Extract reputation
            if ($Content -match $script:QuestPatterns.RewardReputation) {
                $repEntry = @{
                    amount = [int]$matches['rep']
                    faction = 'default'
                }
                if ($Content -match $script:QuestPatterns.RewardFaction) {
                    $repEntry.faction = $matches['fac']
                }
                $rewards.reputation += $repEntry
            }
        }
        
        'pandora' {
            $propertyMatches = [regex]::Matches($Content, '\[property\s+name="(?<name>[^"]+)".*?value="(?<val>[^"]*)"')
            
            foreach ($match in $propertyMatches) {
                $propName = $match.Groups['name'].Value
                $propValue = $match.Groups['val'].Value
                
                switch -Regex ($propName) {
                    'reward_xp|experience|xp' { $rewards.experience = [int]$propValue }
                    'reward_gold|gold|money' { $rewards.gold = [int]$propValue }
                    'reward_item' { $rewards.items += @{ item_id = $propValue; count = 1 } }
                    'unlock_skill|skill_reward' { $rewards.skills += $propValue }
                    'unlock_quest|unlocks' { $rewards.unlocks += @{ type = 'quest'; id = $propValue } }
                }
            }
        }
        
        'json' {
            try {
                $json = $Content | ConvertFrom-Json
                if ($json.rewards) {
                    $rewards.experience = $json.rewards.experience -or $json.rewards.xp -or 0
                    $rewards.gold = $json.rewards.gold -or $json.rewards.money -or $json.rewards.currency -or 0
                    
                    if ($json.rewards.items) {
                        foreach ($item in $json.rewards.items) {
                            $rewards.items += @{
                                item_id = $item.id -or $item.item_id -or ''
                                count = $item.count -or $item.amount -or 1
                            }
                        }
                    }
                    
                    if ($json.rewards.skills) {
                        $rewards.skills = $json.rewards.skills
                    }
                    
                    if ($json.rewards.unlocks) {
                        foreach ($unlock in $json.rewards.unlocks) {
                            $rewards.unlocks += @{
                                type = $unlock.type -or 'quest'
                                id = $unlock.id -or $unlock.quest_id -or ''
                            }
                        }
                    }
                }
            }
            catch {
                Write-Verbose "Failed to parse JSON rewards: $_"
            }
        }
        
        'gdscript' {
            # Check for export variables
            if ($Content -match 'reward_xp\s*=\s*(\d+)') {
                $rewards.experience = [int]$matches[1]
            }
            if ($Content -match 'reward_gold\s*=\s*(\d+)') {
                $rewards.gold = [int]$matches[1]
            }
            
            # Parse reward arrays
            if ($Content -match 'reward_items\s*=\s*\[(.*?)\]') {
                $itemsStr = $matches[1]
                $itemMatches = [regex]::Matches($itemsStr, '"([^"]+)"')
                foreach ($match in $itemMatches) {
                    $rewards.items += @{ item_id = $match.Groups[1].Value; count = 1 }
                }
            }
        }
    }
    
    return $rewards
}

<#
.SYNOPSIS
    Extracts prerequisites from quest content.
.DESCRIPTION
    Parses quest content and extracts prerequisite definitions.
.PARAMETER Content
    The quest content to parse.
.PARAMETER Format
    The quest format.
.OUTPUTS
    System.Array. Array of prerequisite objects.
#>
function Get-QuestPrerequisitesFromContent {
    [CmdletBinding()]
    [OutputType([array])]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Content,
        
        [Parameter()]
        [string]$Format = 'quest_system'
    )
    
    $prerequisites = @()
    
    switch ($Format) {
        'quest_system' {
            # Extract prerequisite quests
            $prereqMatches = [regex]::Matches($Content, $script:QuestPatterns.PrerequisiteQuest)
            foreach ($match in $prereqMatches) {
                $prerequisites += @{
                    type = 'quest'
                    id = $matches['prereq']
                    status = 'completed'  # Default assumption
                }
            }
            
            # Extract from prerequisite list
            if ($Content -match $script:QuestPatterns.PrerequisiteList) {
                $listItems = Get-PrerequisiteList -PrereqString $matches['list']
                foreach ($item in $listItems) {
                    $existing = $prerequisites | Where-Object { $_.type -eq 'quest' -and $_.id -eq $item }
                    if (-not $existing) {
                        $prerequisites += @{
                            type = 'quest'
                            id = $item
                            status = 'completed'
                        }
                    }
                }
            }
            
            # Extract level requirement
            if ($Content -match $script:QuestPatterns.PrerequisiteLevel) {
                $prerequisites += @{
                    type = 'level'
                    required_level = [int]$matches['level']
                }
            }
            
            # Extract item requirement
            if ($Content -match $script:QuestPatterns.PrerequisiteItem) {
                $prerequisites += @{
                    type = 'item'
                    item_id = $matches['item']
                }
            }
            
            # Extract flag/condition requirement
            if ($Content -match $script:QuestPatterns.PrerequisiteFlag) {
                $prerequisites += @{
                    type = 'flag'
                    flag = $matches['flag']
                }
            }
        }
        
        'pandora' {
            $propertyMatches = [regex]::Matches($Content, '\[property\s+name="(?<name>[^"]+)".*?value="(?<val>[^"]*)"')
            
            foreach ($match in $propertyMatches) {
                $propName = $match.Groups['name'].Value
                $propValue = $match.Groups['val'].Value
                
                switch -Regex ($propName) {
                    'prerequisite|requires_quest' {
                        $prerequisites += @{
                            type = 'quest'
                            id = $propValue
                            status = 'completed'
                        }
                    }
                    'required_level|min_level' {
                        $prerequisites += @{
                            type = 'level'
                            required_level = [int]$propValue
                        }
                    }
                    'required_item' {
                        $prerequisites += @{
                            type = 'item'
                            item_id = $propValue
                        }
                    }
                }
            }
        }
        
        'json' {
            try {
                $json = $Content | ConvertFrom-Json
                if ($json.prerequisites) {
                    foreach ($prereq in $json.prerequisites) {
                        $type = $prereq.type -or 'quest'
                        $prereqObj = @{
                            type = $type
                        }
                        
                        switch ($type) {
                            'quest' { $prereqObj.id = $prereq.id -or $prereq.quest_id -or ''; $prereqObj.status = $prereq.status -or 'completed' }
                            'level' { $prereqObj.required_level = $prereq.level -or $prereq.required_level -or 1 }
                            'item' { $prereqObj.item_id = $prereq.item -or $prereq.item_id -or '' }
                            'flag' { $prereqObj.flag = $prereq.flag -or $prereq.condition -or '' }
                        }
                        
                        $prerequisites += $prereqObj
                    }
                }
            }
            catch {
                Write-Verbose "Failed to parse JSON prerequisites: $_"
            }
        }
        
        'gdscript' {
            # Parse GDScript prerequisite arrays
            if ($Content -match 'prerequisite_quests\s*=\s*\[(.*?)\]') {
                $questsStr = $matches[1]
                $questMatches = [regex]::Matches($questsStr, '"([^"]+)"')
                foreach ($match in $questMatches) {
                    $prerequisites += @{
                        type = 'quest'
                        id = $match.Groups[1].Value
                        status = 'completed'
                    }
                }
            }
            
            if ($Content -match 'required_level\s*=\s*(\d+)') {
                $prerequisites += @{
                    type = 'level'
                    required_level = [int]$matches[1]
                }
            }
        }
    }
    
    return $prerequisites
}


# ============================================================================
# Public API Functions - Required by Canonical Document Section 25.7
# ============================================================================

<#
.SYNOPSIS
    Extracts quest system configuration.

.DESCRIPTION
    Parses quest system configuration files and extracts system-level settings
    including quest categories, state definitions, global settings, and
    quest registry information.

.PARAMETER Path
    Path to the quest system configuration file.

.PARAMETER Content
    File content string (alternative to Path).

.PARAMETER Format
    Format of the quest file (auto, quest_system, pandora, json, gdscript).

.OUTPUTS
    System.Collections.Hashtable. Object containing:
    - systemConfig: Quest system configuration
    - questRegistry: Quest registry information
    - stateDefinitions: Quest state definitions
    - categories: Quest categories
    - metadata: Provenance metadata
    - statistics: Extraction statistics

.EXAMPLE
    $system = Export-QuestSystem -Path "res://quests/quest_system.tres"
    
    $system = Export-QuestSystem -Content $configContent -Format "json"
#>
function Export-QuestSystem {
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [Parameter(Mandatory = $true, ParameterSetName = 'Path')]
        [string]$Path,
        
        [Parameter(Mandatory = $true, ParameterSetName = 'Content')]
        [string]$Content,
        
        [Parameter()]
        [ValidateSet('auto', 'quest_system', 'pandora', 'json', 'gdscript', 'tres')]
        [string]$Format = 'auto'
    )
    
    try {
        # Load content
        $sourceFile = 'inline'
        if ($PSCmdlet.ParameterSetName -eq 'Path') {
            if (-not (Test-Path -LiteralPath $Path)) {
                return @{
                    systemConfig = @{}
                    questRegistry = @()
                    stateDefinitions = @()
                    categories = @()
                    metadata = New-ProvenanceMetadata -SourceFile $Path -Success $false -Errors @("File not found: $Path")
                    statistics = @{ questCount = 0; categoryCount = 0 }
                }
            }
            $sourceFile = Resolve-Path -Path $Path | Select-Object -ExpandProperty Path
            $Content = Get-Content -LiteralPath $Path -Raw -Encoding UTF8
            
            # Auto-detect format from extension
            if ($Format -eq 'auto') {
                $ext = [System.IO.Path]::GetExtension($Path).ToLower()
                $Format = Get-QuestFormat -Content $Content -Extension $ext
            }
        }
        else {
            if ($Format -eq 'auto') {
                $Format = Get-QuestFormat -Content $Content
            }
        }
        
        if ([string]::IsNullOrWhiteSpace($Content)) {
            return @{
                systemConfig = @{}
                questRegistry = @()
                stateDefinitions = @()
                categories = @()
                metadata = New-ProvenanceMetadata -SourceFile $sourceFile -Success $false -Errors @("Content is empty")
                statistics = @{ questCount = 0; categoryCount = 0 }
            }
        }
        
        $systemConfig = @{}
        $questRegistry = @()
        $stateDefinitions = @()
        $categories = @()
        
        switch ($Format) {
            'quest_system' {
                # Parse .tres resource file for system configuration
                
                # Extract state definitions
                if ($Content -match $script:QuestPatterns.QuestStateEnum) {
                    $stateDefinitions = @('available', 'active', 'completed', 'failed', 'locked')
                }
                else {
                    # Default states based on content analysis
                    $statesFound = @()
                    foreach ($state in $script:QuestStates) {
                        if ($Content -match "STATE_$($state.ToUpper())" -or $Content -match "Status.$state") {
                            $statesFound += $state
                        }
                    }
                    if ($statesFound.Count -eq 0) {
                        $stateDefinitions = $script:QuestStates
                    }
                    else {
                        $stateDefinitions = $statesFound
                    }
                }
                
                # Extract quest categories
                $categoryMatches = [regex]::Matches($Content, $script:QuestPatterns.QuestCategory)
                foreach ($match in $categoryMatches) {
                    $catName = $match.Groups['cat'].Value
                    if ($catName -notin $categories) {
                        $categories += $catName
                    }
                }
                
                # Look for quest registry
                $questMatches = [regex]::Matches($Content, 'path="res://.*?/(?<file>[^/]+)\.tres"')
                foreach ($match in $questMatches) {
                    $questRegistry += @{
                        file = $match.Groups['file'].Value
                        path = $match.Groups[0].Value -replace 'path="' -replace '"$'
                    }
                }
            }
            
            'pandora' {
                # Parse pandora category structure
                $categoryMatches = [regex]::Matches($Content, $script:QuestPatterns.PandoraCategory)
                foreach ($match in $categoryMatches) {
                    $categories += $match.Groups['cat'].Value
                }
                
                $stateDefinitions = @('available', 'active', 'completed', 'failed')
            }
            
            'json' {
                try {
                    $json = $Content | ConvertFrom-Json
                    
                    if ($json.quest_system) {
                        $systemConfig = $json.quest_system
                    }
                    
                    if ($json.categories) {
                        $categories = $json.categories
                    }
                    
                    if ($json.states) {
                        $stateDefinitions = $json.states
                    }
                    elseif ($json.quest_states) {
                        $stateDefinitions = $json.quest_states
                    }
                    else {
                        $stateDefinitions = $script:QuestStates
                    }
                    
                    if ($json.quests) {
                        foreach ($quest in $json.quests) {
                            $questRegistry += @{
                                id = $quest.quest_id -or $quest.id -or ''
                                title = $quest.title -or ''
                            }
                        }
                    }
                }
                catch {
                    Write-Verbose "Failed to parse JSON system config: $_"
                    $stateDefinitions = $script:QuestStates
                }
            }
            
            'gdscript' {
                # Parse GDScript quest manager
                $stateDefinitions = @()
                foreach ($state in $script:QuestStates) {
                    if ($Content -match "STATE_$($state.ToUpper())") {
                        $stateDefinitions += $state
                    }
                }
                if ($stateDefinitions.Count -eq 0) {
                    $stateDefinitions = $script:QuestStates
                }
                
                # Check for quest array export
                if ($Content -match $script:QuestPatterns.QuestArray) {
                    $systemConfig.hasQuestArray = $true
                }
            }
        }
        
        # Ensure we have default state definitions
        if ($stateDefinitions.Count -eq 0) {
            $stateDefinitions = $script:QuestStates
        }
        
        return @{
            systemConfig = $systemConfig
            questRegistry = $questRegistry
            stateDefinitions = $stateDefinitions
            categories = $categories
            format = $Format
            metadata = New-ProvenanceMetadata -SourceFile $sourceFile -Success $true
            statistics = @{
                questCount = $questRegistry.Count
                categoryCount = $categories.Count
                stateCount = $stateDefinitions.Count
            }
        }
    }
    catch {
        Write-Error "[$script:ParserName] Failed to export quest system: $_"
        return @{
            systemConfig = @{}
            questRegistry = @()
            stateDefinitions = @()
            categories = @()
            metadata = New-ProvenanceMetadata -SourceFile $sourceFile -Success $false -Errors @($_.ToString())
            statistics = @{ questCount = 0; categoryCount = 0 }
        }
    }
}

<#
.SYNOPSIS
    Extracts quest definitions.

.DESCRIPTION
    Parses quest resource files and extracts quest data including
    quest ID, title, description, status, and metadata.

.PARAMETER Path
    Path to the quest resource file.

.PARAMETER Content
    File content string (alternative to Path).

.PARAMETER Format
    Format of the quest file (auto, quest_system, pandora, json, gdscript).

.OUTPUTS
    System.Collections.Hashtable. Object containing:
    - quests: Array of quest definition objects
    - questMap: Dictionary of quests by ID
    - metadata: Provenance metadata
    - statistics: Extraction statistics

.EXAMPLE
    $quests = Export-QuestDefinitions -Path "res://quests/main_quest.tres"
    
    $quests = Export-QuestDefinitions -Content $questContent -Format "json"
#>
function Export-QuestDefinitions {
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [Parameter(Mandatory = $true, ParameterSetName = 'Path')]
        [string]$Path,
        
        [Parameter(Mandatory = $true, ParameterSetName = 'Content')]
        [string]$Content,
        
        [Parameter()]
        [ValidateSet('auto', 'quest_system', 'pandora', 'json', 'gdscript', 'tres')]
        [string]$Format = 'auto'
    )
    
    try {
        # Load content
        $sourceFile = 'inline'
        if ($PSCmdlet.ParameterSetName -eq 'Path') {
            if (-not (Test-Path -LiteralPath $Path)) {
                return @{
                    quests = @()
                    questMap = @{}
                    metadata = New-ProvenanceMetadata -SourceFile $Path -Success $false -Errors @("File not found: $Path")
                    statistics = @{ questCount = 0; mainQuests = 0; sideQuests = 0 }
                }
            }
            $sourceFile = Resolve-Path -Path $Path | Select-Object -ExpandProperty Path
            $Content = Get-Content -LiteralPath $Path -Raw -Encoding UTF8
            
            if ($Format -eq 'auto') {
                $ext = [System.IO.Path]::GetExtension($Path).ToLower()
                $Format = Get-QuestFormat -Content $Content -Extension $ext
            }
        }
        else {
            if ($Format -eq 'auto') {
                $Format = Get-QuestFormat -Content $Content
            }
        }
        
        if ([string]::IsNullOrWhiteSpace($Content)) {
            return @{
                quests = @()
                questMap = @{}
                metadata = New-ProvenanceMetadata -SourceFile $sourceFile -Success $false -Errors @("Content is empty")
                statistics = @{ questCount = 0; mainQuests = 0; sideQuests = 0 }
            }
        }
        
        $quests = @()
        $questMap = @{}
        
        switch ($Format) {
            'quest_system' {
                # Parse single .tres quest resource
                $quest = @{
                    quest_id = ''
                    title = ''
                    description = ''
                    status = 'available'
                    category = ''
                    required_level = 0
                    quest_giver = ''
                    turn_in_npc = ''
                    is_main_quest = $false
                    is_repeatable = $false
                    is_hidden = $false
                    time_limit = $null
                    next_quest = ''
                }
                
                # Extract quest ID
                if ($Content -match $script:QuestPatterns.QuestId) {
                    $quest.quest_id = $matches['id']
                }
                
                # Extract title
                if ($Content -match $script:QuestPatterns.QuestTitle) {
                    $quest.title = $matches['title']
                }
                
                # Extract description
                if ($Content -match $script:QuestPatterns.QuestDescription) {
                    $quest.description = $matches['desc']
                }
                
                # Extract status
                if ($Content -match $script:QuestPatterns.QuestStatus) {
                    $quest.status = $matches['status'].ToLower()
                }
                
                # Extract category
                if ($Content -match $script:QuestPatterns.QuestCategory) {
                    $quest.category = $matches['cat']
                }
                
                # Extract level requirement
                if ($Content -match $script:QuestPatterns.QuestLevel) {
                    $quest.required_level = [int]$matches['level']
                }
                
                # Extract quest giver
                if ($Content -match $script:QuestPatterns.QuestGiver) {
                    $quest.quest_giver = $matches['giver']
                }
                
                # Extract turn-in NPC
                if ($Content -match $script:QuestPatterns.QuestReceiver) {
                    $quest.turn_in_npc = $matches['receiver']
                }
                
                # Extract main quest flag
                if ($Content -match $script:QuestPatterns.QuestIsMain) {
                    $quest.is_main_quest = $matches['main'] -eq 'true'
                }
                
                # Extract repeatable flag
                if ($Content -match $script:QuestPatterns.QuestIsRepeatable) {
                    $quest.is_repeatable = $matches['rep'] -eq 'true'
                }
                
                # Extract hidden flag
                if ($Content -match $script:QuestPatterns.QuestIsHidden) {
                    $quest.is_hidden = $matches['hidden'] -eq 'true'
                }
                
                # Extract time limit
                if ($Content -match $script:QuestPatterns.QuestTimeLimit) {
                    $quest.time_limit = [double]$matches['time']
                }
                
                # Extract next quest
                if ($Content -match $script:QuestPatterns.QuestNextQuest) {
                    $quest.next_quest = $matches['next']
                }
                
                # Generate quest_id from filename if not found
                if ([string]::IsNullOrEmpty($quest.quest_id) -and $sourceFile -ne 'inline') {
                    $fileName = [System.IO.Path]::GetFileNameWithoutExtension($sourceFile)
                    $quest.quest_id = $fileName
                }
                
                # Generate title from ID if not found
                if ([string]::IsNullOrEmpty($quest.title)) {
                    $quest.title = ($quest.quest_id -replace '_', ' ' -replace '-', ' ').ToUpper()
                }
                
                if ($quest.quest_id) {
                    $quests += $quest
                    $questMap[$quest.quest_id] = $quest
                }
                
                # Check for multiple quests in file (embedded resources)
                $embeddedQuests = [regex]::Matches($Content, '\[sub_resource\s+type="Quest".*?\]')
                foreach ($embMatch in $embeddedQuests) {
                    $embSection = $Content.Substring($embMatch.Index, [Math]::Min(500, $Content.Length - $embMatch.Index))
                    $embQuest = @{
                        quest_id = ''
                        title = ''
                        description = ''
                        status = 'available'
                        category = ''
                        required_level = 0
                        quest_giver = ''
                        turn_in_npc = ''
                        is_main_quest = $false
                        is_repeatable = $false
                        is_hidden = $false
                        time_limit = $null
                        next_quest = ''
                    }
                    
                    if ($embSection -match $script:QuestPatterns.QuestId) {
                        $embQuest.quest_id = $matches['id']
                    }
                    if ($embSection -match $script:QuestPatterns.QuestTitle) {
                        $embQuest.title = $matches['title']
                    }
                    if ($embSection -match $script:QuestPatterns.QuestDescription) {
                        $embQuest.description = $matches['desc']
                    }
                    
                    if ($embQuest.quest_id -and -not $questMap.ContainsKey($embQuest.quest_id)) {
                        $quests += $embQuest
                        $questMap[$embQuest.quest_id] = $embQuest
                    }
                }
            }
            
            'pandora' {
                # Parse pandora entity as quest
                $quest = @{
                    quest_id = ''
                    title = ''
                    description = ''
                    status = 'available'
                    category = ''
                    required_level = 0
                    quest_giver = ''
                    turn_in_npc = ''
                    is_main_quest = $false
                    is_repeatable = $false
                    is_hidden = $false
                    time_limit = $null
                    next_quest = ''
                }
                
                # Extract from pandora properties
                $propertyMatches = [regex]::Matches($Content, '\[property\s+name="(?<name>[^"]+)".*?value="(?<val>[^"]*)"')
                
                foreach ($match in $propertyMatches) {
                    $propName = $match.Groups['name'].Value
                    $propValue = $match.Groups['val'].Value
                    
                    switch -Regex ($propName) {
                        'id|quest_id' { $quest.quest_id = $propValue }
                        'name|title|quest_name' { $quest.title = $propValue }
                        'desc|description' { $quest.description = $propValue }
                        'status|state' { $quest.status = $propValue.ToLower() }
                        'category|type' { $quest.category = $propValue }
                        'level|required_level|min_level' { $quest.required_level = [int]$propValue }
                        'giver|quest_giver|npc' { $quest.quest_giver = $propValue }
                        'receiver|turn_in' { $quest.turn_in_npc = $propValue }
                        'main|is_main|story' { $quest.is_main_quest = $propValue -eq 'true' }
                        'repeatable|can_repeat' { $quest.is_repeatable = $propValue -eq 'true' }
                        'hidden|is_hidden|secret' { $quest.is_hidden = $propValue -eq 'true' }
                    }
                }
                
                if ($quest.quest_id) {
                    $quests += $quest
                    $questMap[$quest.quest_id] = $quest
                }
            }
            
            'json' {
                try {
                    $json = $Content | ConvertFrom-Json
                    
                    $questArray = if ($json.quests) { $json.quests } else { @($json) }
                    
                    foreach ($q in $questArray) {
                        $quest = @{
                            quest_id = $q.quest_id -or $q.id -or ''
                            title = $q.title -or $q.name -or ''
                            description = $q.description -or $q.desc -or ''
                            status = ($q.status -or $q.state -or 'available').ToLower()
                            category = $q.category -or $q.type -or ''
                            required_level = $q.required_level -or $q.level -or $q.min_level -or 0
                            quest_giver = $q.quest_giver -or $q.giver -or $q.source_npc -or ''
                            turn_in_npc = $q.turn_in -or $q.receiver -or $q.target_npc -or ''
                            is_main_quest = $q.is_main_quest -or $q.main_story -or $q.is_story -or $false
                            is_repeatable = $q.is_repeatable -or $q.repeatable -or $q.can_repeat -or $false
                            is_hidden = $q.is_hidden -or $q.hidden -or $q.secret -or $false
                            time_limit = $q.time_limit -or $q.timeout -or $q.duration -or $null
                            next_quest = $q.next_quest -or $q.leads_to -or $q.unlocks -or ''
                        }
                        
                        if ($quest.quest_id) {
                            $quests += $quest
                            $questMap[$quest.quest_id] = $quest
                        }
                    }
                }
                catch {
                    Write-Verbose "Failed to parse JSON quest definitions: $_"
                }
            }
            
            'gdscript' {
                # Parse GDScript quest class
                $quest = @{
                    quest_id = ''
                    title = ''
                    description = ''
                    status = 'available'
                    category = ''
                    required_level = 0
                    quest_giver = ''
                    turn_in_npc = ''
                    is_main_quest = $false
                    is_repeatable = $false
                    is_hidden = $false
                    time_limit = $null
                    next_quest = ''
                }
                
                # Extract from export variables
                if ($Content -match 'quest_id\s*=\s*["\']([^"\']+)["\']') {
                    $quest.quest_id = $matches[1]
                }
                if ($Content -match 'quest_name\s*=\s*["\']([^"\']+)["\']') {
                    $quest.title = $matches[1]
                }
                if ($Content -match 'description\s*=\s*["\']([^"\']*?)["\']') {
                    $quest.description = $matches[1]
                }
                if ($Content -match 'required_level\s*=\s*(\d+)') {
                    $quest.required_level = [int]$matches[1]
                }
                
                # Generate ID from class_name if needed
                if ([string]::IsNullOrEmpty($quest.quest_id)) {
                    if ($Content -match 'class_name\s+(\w+)') {
                        $quest.quest_id = $matches[1]
                    }
                    elseif ($Content -match 'class\s+(\w+)Quest') {
                        $quest.quest_id = $matches[1]
                    }
                }
                
                if ($quest.quest_id) {
                    $quests += $quest
                    $questMap[$quest.quest_id] = $quest
                }
            }
        }
        
        $mainQuests = ($quests | Where-Object { $_.is_main_quest }).Count
        $sideQuests = ($quests | Where-Object { -not $_.is_main_quest }).Count
        
        return @{
            quests = $quests
            questMap = $questMap
            format = $Format
            metadata = New-ProvenanceMetadata -SourceFile $sourceFile -Success $true
            statistics = @{
                questCount = $quests.Count
                mainQuests = $mainQuests
                sideQuests = $sideQuests
                repeatableQuests = ($quests | Where-Object { $_.is_repeatable }).Count
                hiddenQuests = ($quests | Where-Object { $_.is_hidden }).Count
            }
        }
    }
    catch {
        Write-Error "[$script:ParserName] Failed to export quest definitions: $_"
        return @{
            quests = @()
            questMap = @{}
            metadata = New-ProvenanceMetadata -SourceFile $sourceFile -Success $false -Errors @($_.ToString())
            statistics = @{ questCount = 0; mainQuests = 0; sideQuests = 0 }
        }
    }
}

<#
.SYNOPSIS
    Extracts quest objectives/tasks.

.DESCRIPTION
    Parses quest files and extracts objective definitions including
    objective ID, type, target, progress tracking, and completion criteria.

.PARAMETER Path
    Path to the quest file.

.PARAMETER Content
    File content string (alternative to Path).

.PARAMETER QuestId
    Specific quest ID to extract objectives for (optional).

.PARAMETER Format
    Format of the quest file (auto, quest_system, pandora, json, gdscript).

.OUTPUTS
    System.Collections.Hashtable. Object containing:
    - objectives: Array of objective objects
    - objectiveMap: Dictionary of objectives by ID
    - questObjectives: Objectives grouped by quest ID
    - metadata: Provenance metadata
    - statistics: Extraction statistics

.EXAMPLE
    $objectives = Export-QuestObjectives -Path "res://quests/main_quest.tres"
    
    $objectives = Export-QuestObjectives -Content $questContent -Format "json"
#>
function Export-QuestObjectives {
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [Parameter(Mandatory = $true, ParameterSetName = 'Path')]
        [string]$Path,
        
        [Parameter(Mandatory = $true, ParameterSetName = 'Content')]
        [string]$Content,
        
        [Parameter()]
        [string]$QuestId = '',
        
        [Parameter()]
        [ValidateSet('auto', 'quest_system', 'pandora', 'json', 'gdscript', 'tres')]
        [string]$Format = 'auto'
    )
    
    try {
        # Load content
        $sourceFile = 'inline'
        if ($PSCmdlet.ParameterSetName -eq 'Path') {
            if (-not (Test-Path -LiteralPath $Path)) {
                return @{
                    objectives = @()
                    objectiveMap = @{}
                    questObjectives = @{}
                    metadata = New-ProvenanceMetadata -SourceFile $Path -Success $false -Errors @("File not found: $Path")
                    statistics = @{ objectiveCount = 0; optionalCount = 0 }
                }
            }
            $sourceFile = Resolve-Path -Path $Path | Select-Object -ExpandProperty Path
            $Content = Get-Content -LiteralPath $Path -Raw -Encoding UTF8
            
            if ($Format -eq 'auto') {
                $ext = [System.IO.Path]::GetExtension($Path).ToLower()
                $Format = Get-QuestFormat -Content $Content -Extension $ext
            }
        }
        else {
            if ($Format -eq 'auto') {
                $Format = Get-QuestFormat -Content $Content
            }
        }
        
        if ([string]::IsNullOrWhiteSpace($Content)) {
            return @{
                objectives = @()
                objectiveMap = @{}
                questObjectives = @{}
                metadata = New-ProvenanceMetadata -SourceFile $sourceFile -Success $false -Errors @("Content is empty")
                statistics = @{ objectiveCount = 0; optionalCount = 0 }
            }
        }
        
        # Get quest definitions first to determine quest ID
        $questDefs = Export-QuestDefinitions -Content $Content -Format $Format
        $currentQuestId = $QuestId
        
        if ([string]::IsNullOrEmpty($currentQuestId) -and $questDefs.quests.Count -gt 0) {
            $currentQuestId = $questDefs.quests[0].quest_id
        }
        
        # Extract objectives using helper function
        $objectives = Get-QuestObjectivesFromContent -Content $Content -Format $Format
        
        # Associate objectives with quest ID
        foreach ($obj in $objectives) {
            $obj.quest_id = $currentQuestId
        }
        
        # Build objective map
        $objectiveMap = @{}
        $questObjectives = @{}
        
        if ($currentQuestId) {
            $questObjectives[$currentQuestId] = @()
        }
        
        foreach ($obj in $objectives) {
            $objId = $obj.objective_id
            if ([string]::IsNullOrEmpty($objId)) {
                $objId = "objective_$($objectives.IndexOf($obj) + 1)"
                $obj.objective_id = $objId
            }
            
            $objectiveMap[$objId] = $obj
            
            $qid = $obj.quest_id
            if ($qid) {
                if (-not $questObjectives.ContainsKey($qid)) {
                    $questObjectives[$qid] = @()
                }
                $questObjectives[$qid] += $obj
            }
        }
        
        $optionalCount = ($objectives | Where-Object { $_.is_optional }).Count
        $byType = @{}
        foreach ($obj in $objectives) {
            $type = $obj.type
            if (-not $byType.ContainsKey($type)) {
                $byType[$type] = 0
            }
            $byType[$type]++
        }
        
        return @{
            objectives = $objectives
            objectiveMap = $objectiveMap
            questObjectives = $questObjectives
            format = $Format
            metadata = New-ProvenanceMetadata -SourceFile $sourceFile -Success $true
            statistics = @{
                objectiveCount = $objectives.Count
                optionalCount = $optionalCount
                requiredCount = $objectives.Count - $optionalCount
                objectivesByType = $byType
                averageObjectivesPerQuest = if ($questObjectives.Count -gt 0) { $objectives.Count / $questObjectives.Count } else { 0 }
            }
        }
    }
    catch {
        Write-Error "[$script:ParserName] Failed to export quest objectives: $_"
        return @{
            objectives = @()
            objectiveMap = @{}
            questObjectives = @{}
            metadata = New-ProvenanceMetadata -SourceFile $sourceFile -Success $false -Errors @($_.ToString())
            statistics = @{ objectiveCount = 0; optionalCount = 0 }
        }
    }
}


<#
.SYNOPSIS
    Builds quest dependency graph.

.DESCRIPTION
    Parses quest definitions and constructs a dependency graph showing
    quest prerequisites, unlock chains, and quest relationships.

.PARAMETER Path
    Path to the quest file or directory.

.PARAMETER Content
    File content string (alternative to Path).

.PARAMETER QuestDefinitions
    Pre-extracted quest definitions (optional).

.PARAMETER Format
    Format of the quest file (auto, quest_system, pandora, json, gdscript).

.OUTPUTS
    System.Collections.Hashtable. Object containing:
    - nodes: Array of quest nodes
    - edges: Array of dependency edges
    - adjacencyList: Adjacency list representation
    - chains: Quest chains/sequences
    - metadata: Provenance metadata
    - statistics: Graph statistics

.EXAMPLE
    $graph = Get-QuestGraph -Path "res://quests/"
    
    $graph = Get-QuestGraph -QuestDefinitions $questDefs
#>
function Get-QuestGraph {
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [Parameter(Mandatory = $true, ParameterSetName = 'Path')]
        [string]$Path,
        
        [Parameter(Mandatory = $true, ParameterSetName = 'Content')]
        [string]$Content,
        
        [Parameter(Mandatory = $true, ParameterSetName = 'Definitions')]
        [hashtable]$QuestDefinitions,
        
        [Parameter()]
        [ValidateSet('auto', 'quest_system', 'pandora', 'json', 'gdscript', 'tres')]
        [string]$Format = 'auto'
    )
    
    try {
        $sourceFile = 'inline'
        $quests = @()
        $questMap = @{}
        $allPrerequisites = @()
        
        switch ($PSCmdlet.ParameterSetName) {
            'Path' {
                if (Test-Path -LiteralPath $Path -PathType Container) {
                    # Process directory of quest files
                    $questFiles = Get-ChildItem -Path $Path -Recurse -Include @('*.tres', '*.quest', '*.gd', '*.json')
                    foreach ($file in $questFiles) {
                        $defs = Export-QuestDefinitions -Path $file.FullName
                        foreach ($q in $defs.quests) {
                            $quests += $q
                            $questMap[$q.quest_id] = $q
                        }
                        $prereqs = Get-QuestPrerequisitesFromContent -Content (Get-Content $file.FullName -Raw) -Format $defs.format
                        foreach ($p in $prereqs) {
                            $p.targetQuest = $q.quest_id
                            $allPrerequisites += $p
                        }
                    }
                    $sourceFile = $Path
                }
                else {
                    $defs = Export-QuestDefinitions -Path $Path
                    $quests = $defs.quests
                    $questMap = $defs.questMap
                    $fileContent = Get-Content -LiteralPath $Path -Raw
                    if ($Format -eq 'auto') {
                        $Format = Get-QuestFormat -Content $fileContent -Extension ([System.IO.Path]::GetExtension($Path))
                    }
                    $allPrerequisites = Get-QuestPrerequisitesFromContent -Content $fileContent -Format $Format
                    foreach ($p in $allPrerequisites) {
                        if ($quests.Count -eq 1) {
                            $p.targetQuest = $quests[0].quest_id
                        }
                    }
                    $sourceFile = $Path
                }
            }
            'Content' {
                $defs = Export-QuestDefinitions -Content $Content -Format $Format
                $quests = $defs.quests
                $questMap = $defs.questMap
                $allPrerequisites = Get-QuestPrerequisitesFromContent -Content $Content -Format $Format
                foreach ($p in $allPrerequisites) {
                    if ($quests.Count -eq 1) {
                        $p.targetQuest = $quests[0].quest_id
                    }
                }
            }
            'Definitions' {
                $quests = $QuestDefinitions.quests
                $questMap = $QuestDefinitions.questMap
                $sourceFile = $QuestDefinitions.metadata.sourceFile
            }
        }
        
        # Build graph nodes
        $nodes = @()
        foreach ($quest in $quests) {
            $node = @{
                id = $quest.quest_id
                label = $quest.title
                type = if ($quest.is_main_quest) { 'main' } else { 'side' }
                status = $quest.status
                level = $quest.required_level
                category = $quest.category
                is_repeatable = $quest.is_repeatable
                is_hidden = $quest.is_hidden
            }
            $nodes += $node
        }
        
        # Build graph edges from prerequisites and next_quest chains
        $edges = @()
        $adjacencyList = @{}
        
        # Initialize adjacency list
        foreach ($quest in $quests) {
            $adjacencyList[$quest.quest_id] = @{
                prerequisites = @()
                unlocks = @()
            }
        }
        
        # Add edges from prerequisites
        foreach ($prereq in $allPrerequisites) {
            if ($prereq.type -eq 'quest' -and $prereq.targetQuest) {
                $edge = @{
                    from = $prereq.id
                    to = $prereq.targetQuest
                    type = 'prerequisite'
                    requiredStatus = $prereq.status
                }
                $edges += $edge
                
                if ($adjacencyList.ContainsKey($prereq.id)) {
                    $adjacencyList[$prereq.id].unlocks += $prereq.targetQuest
                }
                if ($adjacencyList.ContainsKey($prereq.targetQuest)) {
                    $adjacencyList[$prereq.targetQuest].prerequisites += $prereq.id
                }
            }
        }
        
        # Add edges from next_quest chains
        foreach ($quest in $quests) {
            if (-not [string]::IsNullOrEmpty($quest.next_quest)) {
                $edge = @{
                    from = $quest.quest_id
                    to = $quest.next_quest
                    type = 'sequence'
                }
                $edges += $edge
                
                if ($adjacencyList.ContainsKey($quest.quest_id)) {
                    $adjacencyList[$quest.quest_id].unlocks += $quest.next_quest
                }
                if ($adjacencyList.ContainsKey($quest.next_quest)) {
                    $adjacencyList[$quest.next_quest].prerequisites += $quest.quest_id
                }
            }
        }
        
        # Find quest chains (linear sequences)
        $chains = @()
        $visited = @{}
        
        foreach ($quest in $quests) {
            if ($visited.ContainsKey($quest.quest_id)) {
                continue
            }
            
            # Check if this quest has no prerequisites (chain start) or is a chain link
            $isStart = ($adjacencyList[$quest.quest_id].prerequisites.Count -eq 0) -or
                       ($edges | Where-Object { $_.to -eq $quest.quest_id -and $_.type -eq 'sequence' }).Count -eq 0
            
            if ($isStart) {
                $chain = @{
                    id = "chain_$($quest.quest_id)"
                    startQuest = $quest.quest_id
                    quests = @($quest.quest_id)
                    length = 1
                }
                
                $current = $quest.quest_id
                $maxDepth = 50  # Prevent infinite loops
                $depth = 0
                
                while ($depth -lt $maxDepth) {
                    # Find next quest in sequence
                    $nextEdge = $edges | Where-Object { $_.from -eq $current -and $_.type -eq 'sequence' } | Select-Object -First 1
                    
                    if ($nextEdge) {
                        $current = $nextEdge.to
                        $chain.quests += $current
                        $chain.length++
                        $visited[$current] = $true
                    }
                    else {
                        break
                    }
                    $depth++
                }
                
                if ($chain.length -gt 1) {
                    $chains += $chain
                }
            }
        }
        
        # Calculate graph statistics
        $questIds = $quests | ForEach-Object { $_.quest_id }
        $danglingRefs = $edges | Where-Object { $questIds -notcontains $_.to } | ForEach-Object { $_.to } | Select-Object -Unique
        
        return @{
            nodes = $nodes
            edges = $edges
            adjacencyList = $adjacencyList
            chains = $chains
            format = $Format
            metadata = New-ProvenanceMetadata -SourceFile $sourceFile -Success $true
            statistics = @{
                nodeCount = $nodes.Count
                edgeCount = $edges.Count
                chainCount = $chains.Count
                avgPrerequisites = if ($nodes.Count -gt 0) { ($adjacencyList.Values | ForEach-Object { $_.prerequisites.Count } | Measure-Object -Average).Average } else { 0 }
                avgUnlocks = if ($nodes.Count -gt 0) { ($adjacencyList.Values | ForEach-Object { $_.unlocks.Count } | Measure-Object -Average).Average } else { 0 }
                danglingReferences = $danglingRefs
                hasCircularDeps = $false  # Would need deeper analysis
            }
        }
    }
    catch {
        Write-Error "[$script:ParserName] Failed to build quest graph: $_"
        return @{
            nodes = @()
            edges = @()
            adjacencyList = @{}
            chains = @()
            metadata = New-ProvenanceMetadata -SourceFile $sourceFile -Success $false -Errors @($_.ToString())
            statistics = @{ nodeCount = 0; edgeCount = 0 }
        }
    }
}

<#
.SYNOPSIS
    Extracts reward definitions.

.DESCRIPTION
    Parses quest files and extracts reward data including items,
    experience, gold, skill unlocks, and other rewards.

.PARAMETER Path
    Path to the quest file.

.PARAMETER Content
    File content string (alternative to Path).

.PARAMETER QuestDefinitions
    Pre-extracted quest definitions (optional).

.PARAMETER Format
    Format of the quest file (auto, quest_system, pandora, json, gdscript).

.OUTPUTS
    System.Collections.Hashtable. Object containing:
    - rewards: Array of reward objects
    - rewardsByQuest: Rewards grouped by quest ID
    - rewardSummary: Summary of all rewards
    - metadata: Provenance metadata
    - statistics: Reward statistics

.EXAMPLE
    $rewards = Export-QuestRewards -Path "res://quests/main_quest.tres"
    
    $rewards = Export-QuestRewards -QuestDefinitions $questDefs
#>
function Export-QuestRewards {
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [Parameter(Mandatory = $true, ParameterSetName = 'Path')]
        [string]$Path,
        
        [Parameter(Mandatory = $true, ParameterSetName = 'Content')]
        [string]$Content,
        
        [Parameter(Mandatory = $true, ParameterSetName = 'Definitions')]
        [hashtable]$QuestDefinitions,
        
        [Parameter()]
        [ValidateSet('auto', 'quest_system', 'pandora', 'json', 'gdscript', 'tres')]
        [string]$Format = 'auto'
    )
    
    try {
        $sourceFile = 'inline'
        $quests = @()
        $questRewards = @{}
        
        switch ($PSCmdlet.ParameterSetName) {
            'Path' {
                if (Test-Path -LiteralPath $Path -PathType Container) {
                    # Process directory
                    $questFiles = Get-ChildItem -Path $Path -Recurse -Include @('*.tres', '*.quest', '*.gd', '*.json')
                    foreach ($file in $questFiles) {
                        $defs = Export-QuestDefinitions -Path $file.FullName
                        $fileContent = Get-Content $file.FullName -Raw
                        $fileFormat = Get-QuestFormat -Content $fileContent -Extension $file.Extension
                        $rewards = Get-QuestRewardsFromContent -Content $fileContent -Format $fileFormat
                        
                        foreach ($q in $defs.quests) {
                            $quests += $q
                            $questRewards[$q.quest_id] = $rewards
                        }
                    }
                    $sourceFile = $Path
                }
                else {
                    $defs = Export-QuestDefinitions -Path $Path
                    $quests = $defs.quests
                    $fileContent = Get-Content -LiteralPath $Path -Raw
                    if ($Format -eq 'auto') {
                        $Format = Get-QuestFormat -Content $fileContent -Extension ([System.IO.Path]::GetExtension($Path))
                    }
                    $rewards = Get-QuestRewardsFromContent -Content $fileContent -Format $Format
                    foreach ($q in $quests) {
                        $questRewards[$q.quest_id] = $rewards
                    }
                    $sourceFile = $Path
                }
            }
            'Content' {
                $defs = Export-QuestDefinitions -Content $Content -Format $Format
                $quests = $defs.quests
                $rewards = Get-QuestRewardsFromContent -Content $Content -Format $Format
                foreach ($q in $quests) {
                    $questRewards[$q.quest_id] = $rewards
                }
            }
            'Definitions' {
                $quests = $QuestDefinitions.quests
                $sourceFile = $QuestDefinitions.metadata.sourceFile
            }
        }
        
        # Build reward summary
        $allRewards = @()
        $rewardsByQuest = @{}
        $totalXP = 0
        $totalGold = 0
        $allItems = @{}
        $allSkills = @()
        $allUnlocks = @()
        
        foreach ($quest in $quests) {
            $qid = $quest.quest_id
            $rewards = $questRewards[$qid]
            
            if (-not $rewards) {
                continue
            }
            
            $rewardsByQuest[$qid] = $rewards
            
            # Aggregate totals
            $totalXP += $rewards.experience
            $totalGold += $rewards.gold
            
            foreach ($item in $rewards.items) {
                $itemId = $item.item_id
                if (-not $allItems.ContainsKey($itemId)) {
                    $allItems[$itemId] = 0
                }
                $allItems[$itemId] += $item.count
            }
            
            $allSkills += $rewards.skills
            $allUnlocks += $rewards.unlocks
            
            # Add to all rewards list
            $allRewards += @{
                quest_id = $qid
                quest_title = $quest.title
                experience = $rewards.experience
                gold = $rewards.gold
                items = $rewards.items
                skills = $rewards.skills
                unlocks = $rewards.unlocks
                reputation = $rewards.reputation
            }
        }
        
        $rewardSummary = @{
            totalExperience = $totalXP
            totalGold = $totalGold
            uniqueItems = $allItems.Keys.Count
            itemTotals = $allItems
            uniqueSkills = ($allSkills | Select-Object -Unique).Count
            skills = $allSkills | Select-Object -Unique
            unlockCount = $allUnlocks.Count
        }
        
        # Calculate reward distribution
        $questsWithXP = ($quests | Where-Object { $questRewards[$_.quest_id] -and $questRewards[$_.quest_id].experience -gt 0 }).Count
        $questsWithGold = ($quests | Where-Object { $questRewards[$_.quest_id] -and $questRewards[$_.quest_id].gold -gt 0 }).Count
        $questsWithItems = ($quests | Where-Object { $questRewards[$_.quest_id] -and $questRewards[$_.quest_id].items.Count -gt 0 }).Count
        
        return @{
            rewards = $allRewards
            rewardsByQuest = $rewardsByQuest
            rewardSummary = $rewardSummary
            format = $Format
            metadata = New-ProvenanceMetadata -SourceFile $sourceFile -Success $true
            statistics = @{
                totalQuests = $quests.Count
                questsWithRewards = ($quests | Where-Object { $questRewards[$_.quest_id] -and 
                    ($questRewards[$_.quest_id].experience -gt 0 -or 
                     $questRewards[$_.quest_id].gold -gt 0 -or 
                     $questRewards[$_.quest_id].items.Count -gt 0) }).Count
                questsWithXP = $questsWithXP
                questsWithGold = $questsWithGold
                questsWithItems = $questsWithItems
                averageXPPerQuest = if ($quests.Count -gt 0) { $totalXP / $quests.Count } else { 0 }
                averageGoldPerQuest = if ($quests.Count -gt 0) { $totalGold / $quests.Count } else { 0 }
            }
        }
    }
    catch {
        Write-Error "[$script:ParserName] Failed to export quest rewards: $_"
        return @{
            rewards = @()
            rewardsByQuest = @{}
            rewardSummary = @{}
            metadata = New-ProvenanceMetadata -SourceFile $sourceFile -Success $false -Errors @($_.ToString())
            statistics = @{ totalQuests = 0 }
        }
    }
}

<#
.SYNOPSIS
    Calculates quest system metrics.

.DESCRIPTION
    Analyzes quest system data and calculates comprehensive metrics
    including quest distribution, complexity, balance, and coverage.

.PARAMETER Path
    Path to the quest directory or file.

.PARAMETER QuestDefinitions
    Pre-extracted quest definitions.

.PARAMETER QuestGraph
    Pre-built quest graph.

.PARAMETER QuestRewards
    Pre-extracted quest rewards.

.OUTPUTS
    System.Collections.Hashtable. Object containing:
    - overview: High-level system overview
    - distribution: Quest distribution metrics
    - complexity: Complexity metrics
    - balance: Balance metrics
    - coverage: Content coverage metrics
    - recommendations: Optimization recommendations
    - metadata: Provenance metadata

.EXAMPLE
    $metrics = Get-QuestMetrics -Path "res://quests/"
    
    $metrics = Get-QuestMetrics -QuestDefinitions $questDefs -QuestGraph $graph -QuestRewards $rewards
#>
function Get-QuestMetrics {
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [Parameter(Mandatory = $true, ParameterSetName = 'Path')]
        [string]$Path,
        
        [Parameter(Mandatory = $true, ParameterSetName = 'Definitions')]
        [hashtable]$QuestDefinitions,
        
        [Parameter()]
        [hashtable]$QuestGraph = $null,
        
        [Parameter()]
        [hashtable]$QuestRewards = $null
    )
    
    try {
        $sourceFile = 'inline'
        
        # Get quest definitions if not provided
        if ($PSCmdlet.ParameterSetName -eq 'Path') {
            if (Test-Path -LiteralPath $Path -PathType Container) {
                $allQuests = @()
                $questFiles = Get-ChildItem -Path $Path -Recurse -Include @('*.tres', '*.quest', '*.gd', '*.json')
                foreach ($file in $questFiles) {
                    $defs = Export-QuestDefinitions -Path $file.FullName
                    $allQuests += $defs.quests
                }
                $QuestDefinitions = @{
                    quests = $allQuests
                    questMap = @{}
                }
                foreach ($q in $allQuests) {
                    $QuestDefinitions.questMap[$q.quest_id] = $q
                }
                $sourceFile = $Path
            }
            else {
                $QuestDefinitions = Export-QuestDefinitions -Path $Path
                $sourceFile = $Path
            }
        }
        else {
            $sourceFile = $QuestDefinitions.metadata.sourceFile
        }
        
        $quests = $QuestDefinitions.quests
        
        if ($quests.Count -eq 0) {
            return @{
                overview = @{}
                distribution = @{}
                complexity = @{}
                balance = @{}
                coverage = @{}
                recommendations = @()
                metadata = New-ProvenanceMetadata -SourceFile $sourceFile -Success $false -Errors @("No quests found")
            }
        }
        
        # Get graph if not provided
        if (-not $QuestGraph) {
            $QuestGraph = Get-QuestGraph -QuestDefinitions $QuestDefinitions
        }
        
        # Get rewards if not provided
        if (-not $QuestRewards) {
            $QuestRewards = Export-QuestRewards -QuestDefinitions $QuestDefinitions
        }
        
        # Overview metrics
        $overview = @{
            totalQuests = $quests.Count
            mainQuests = ($quests | Where-Object { $_.is_main_quest }).Count
            sideQuests = ($quests | Where-Object { -not $_.is_main_quest }).Count
            repeatableQuests = ($quests | Where-Object { $_.is_repeatable }).Count
            hiddenQuests = ($quests | Where-Object { $_.is_hidden }).Count
            totalChains = $QuestGraph.chains.Count
            totalDependencies = $QuestGraph.edges.Count
        }
        
        # Distribution metrics
        $byCategory = @{}
        $byStatus = @{}
        $byLevel = @{}
        
        foreach ($quest in $quests) {
            # Category distribution
            $cat = if ($quest.category) { $quest.category } else { 'uncategorized' }
            if (-not $byCategory.ContainsKey($cat)) {
                $byCategory[$cat] = 0
            }
            $byCategory[$cat]++
            
            # Status distribution
            $status = if ($quest.status) { $quest.status } else { 'available' }
            if (-not $byStatus.ContainsKey($status)) {
                $byStatus[$status] = 0
            }
            $byStatus[$status]++
            
            # Level distribution (bucket by 5-level ranges)
            $level = $quest.required_level
            $levelBucket = [Math]::Floor($level / 5) * 5
            $levelRange = "$levelBucket-$($levelBucket + 4)"
            if (-not $byLevel.ContainsKey($levelRange)) {
                $byLevel[$levelRange] = 0
            }
            $byLevel[$levelRange]++
        }
        
        $distribution = @{
            byCategory = $byCategory
            byStatus = $byStatus
            byLevelRange = $byLevel
            categoryDiversity = $byCategory.Keys.Count
        }
        
        # Complexity metrics
        $avgChainLength = if ($QuestGraph.chains.Count -gt 0) { 
            ($QuestGraph.chains | ForEach-Object { $_.length } | Measure-Object -Average).Average 
        } else { 0 }
        
        $maxChainLength = if ($QuestGraph.chains.Count -gt 0) {
            ($QuestGraph.chains | ForEach-Object { $_.length } | Measure-Object -Maximum).Maximum
        } else { 0 }
        
        $questsWithPrereqs = ($QuestGraph.adjacencyList.Values | Where-Object { $_.prerequisites.Count -gt 0 }).Count
        $questsWithUnlocks = ($QuestGraph.adjacencyList.Values | Where-Object { $_.unlocks.Count -gt 0 }).Count
        
        $complexity = @{
            averageChainLength = [Math]::Round($avgChainLength, 2)
            maxChainLength = $maxChainLength
            questsWithPrerequisites = $questsWithPrereqs
            questsWithUnlocks = $questsWithUnlocks
            averagePrerequisitesPerQuest = [Math]::Round($QuestGraph.statistics.avgPrerequisites, 2)
            averageUnlocksPerQuest = [Math]::Round($QuestGraph.statistics.avgUnlocks, 2)
            dependencyComplexity = if ($overview.totalQuests -gt 0) { 
                [Math]::Round($overview.totalDependencies / $overview.totalQuests, 2) 
            } else { 0 }
        }
        
        # Balance metrics
        $totalXP = $QuestRewards.rewardSummary.totalExperience
        $totalGold = $QuestRewards.rewardSummary.totalGold
        
        $xpPerQuest = if ($overview.totalQuests -gt 0) { $totalXP / $overview.totalQuests } else { 0 }
        $goldPerQuest = if ($overview.totalQuests -gt 0) { $totalGold / $overview.totalQuests } else { 0 }
        
        # Calculate reward variance
        $xpValues = $QuestRewards.rewards | ForEach-Object { $_.experience }
        $xpVariance = if ($xpValues.Count -gt 1) {
            $avg = ($xpValues | Measure-Object -Average).Average
            $sumSqDiff = ($xpValues | ForEach-Object { [Math]::Pow($_ - $avg, 2) } | Measure-Object -Sum).Sum
            [Math]::Round($sumSqDiff / $xpValues.Count, 2)
        } else { 0 }
        
        $balance = @{
            totalExperience = $totalXP
            totalGold = $totalGold
            experiencePerQuest = [Math]::Round($xpPerQuest, 2)
            goldPerQuest = [Math]::Round($goldPerQuest, 2)
            experienceVariance = $xpVariance
            mainToSideRatio = if ($overview.sideQuests -gt 0) { 
                [Math]::Round($overview.mainQuests / $overview.sideQuests, 2) 
            } else { 0 }
        }
        
        # Coverage metrics
        $levelRange = 1..50  # Assume max level 50
        $coveredLevels = @()
        foreach ($quest in $quests) {
            $level = $quest.required_level
            if ($level -and $level -gt 0) {
                $coveredLevels += $level
            }
        }
        
        $coverage = @{
            levelCoverageCount = ($coveredLevels | Select-Object -Unique).Count
            minRequiredLevel = ($quests | ForEach-Object { $_.required_level } | Measure-Object -Minimum).Minimum
            maxRequiredLevel = ($quests | ForEach-Object { $_.required_level } | Measure-Object -Maximum).Maximum
            hasContentForLowLevels = ($coveredLevels | Where-Object { $_ -le 10 }).Count -gt 0
            hasContentForMidLevels = ($coveredLevels | Where-Object { $_ -gt 10 -and $_ -le 30 }).Count -gt 0
            hasContentForHighLevels = ($coveredLevels | Where-Object { $_ -gt 30 }).Count -gt 0
        }
        
        # Recommendations
        $recommendations = @()
        
        if ($overview.sideQuests -eq 0 -and $overview.mainQuests -gt 0) {
            $recommendations += "Consider adding side quests to supplement the main story"
        }
        
        if ($overview.repeatableQuests -eq 0) {
            $recommendations += "Consider adding repeatable quests for endgame content"
        }
        
        if ($QuestGraph.statistics.danglingReferences.Count -gt 0) {
            $recommendations += "Found $($QuestGraph.statistics.danglingReferences.Count) dangling quest references: $($QuestGraph.statistics.danglingReferences -join ', ')"
        }
        
        if ($balance.experienceVariance -gt 10000) {
            $recommendations += "High variance in XP rewards detected; consider rebalancing quest rewards"
        }
        
        if ($coverage.levelCoverageCount -lt 10) {
            $recommendations += "Limited level range coverage; consider quests for more level ranges"
        }
        
        if ($complexity.averagePrerequisitesPerQuest -gt 3) {
            $recommendations += "High prerequisite density detected; consider simplifying quest dependencies"
        }
        
        return @{
            overview = $overview
            distribution = $distribution
            complexity = $complexity
            balance = $balance
            coverage = $coverage
            recommendations = $recommendations
            metadata = New-ProvenanceMetadata -SourceFile $sourceFile -Success $true
        }
    }
    catch {
        Write-Error "[$script:ParserName] Failed to calculate quest metrics: $_"
        return @{
            overview = @{}
            distribution = @{}
            complexity = @{}
            balance = @{}
            coverage = @{}
            recommendations = @()
            metadata = New-ProvenanceMetadata -SourceFile $sourceFile -Success $false -Errors @($_.ToString())
        }
    }
}


# ============================================================================
# Legacy Compatibility Functions
# ============================================================================

<#
.SYNOPSIS
    Extracts quest data from quest files.
    
    DEPRECATED: Use Export-QuestDefinitions instead.
#>
function Get-QuestData {
    [CmdletBinding()]
    [OutputType([array])]
    param(
        [Parameter(Mandatory = $true, ParameterSetName = 'Path')]
        [string]$Path,
        
        [Parameter(Mandatory = $true, ParameterSetName = 'Content')]
        [string]$Content,
        
        [Parameter()]
        [ValidateSet('auto', 'quest_system', 'json', 'gdscript')]
        [string]$Format = 'auto'
    )
    
    $result = if ($PSCmdlet.ParameterSetName -eq 'Path') {
        Export-QuestDefinitions -Path $Path -Format $Format
    }
    else {
        Export-QuestDefinitions -Content $Content -Format $Format
    }
    
    return $result.quests
}

<#
.SYNOPSIS
    Extracts quest objectives from quest files.
    
    DEPRECATED: Use Export-QuestObjectives instead.
#>
function Get-QuestObjectives {
    [CmdletBinding()]
    [OutputType([array])]
    param(
        [Parameter(Mandatory = $true, ParameterSetName = 'Path')]
        [string]$Path,
        
        [Parameter(Mandatory = $true, ParameterSetName = 'Content')]
        [string]$Content,
        
        [Parameter()]
        [ValidateSet('auto', 'quest_system', 'json', 'gdscript')]
        [string]$Format = 'auto'
    )
    
    $result = if ($PSCmdlet.ParameterSetName -eq 'Path') {
        Export-QuestObjectives -Path $Path -Format $Format
    }
    else {
        Export-QuestObjectives -Content $Content -Format $Format
    }
    
    return $result.objectives
}

<#
.SYNOPSIS
    Extracts quest prerequisites from quest files.
    
    DEPRECATED: Use Get-QuestPrerequisitesFromContent or Get-QuestGraph instead.
#>
function Get-QuestPrerequisites {
    [CmdletBinding()]
    [OutputType([array])]
    param(
        [Parameter(Mandatory = $true, ParameterSetName = 'Path')]
        [string]$Path,
        
        [Parameter(Mandatory = $true, ParameterSetName = 'Content')]
        [string]$Content,
        
        [Parameter()]
        [ValidateSet('auto', 'quest_system', 'json', 'gdscript')]
        [string]$Format = 'auto'
    )
    
    $sourceFile = 'inline'
    if ($PSCmdlet.ParameterSetName -eq 'Path') {
        if (-not (Test-Path -LiteralPath $Path)) {
            return @()
        }
        $sourceFile = $Path
        $Content = Get-Content -LiteralPath $Path -Raw
        if ($Format -eq 'auto') {
            $ext = [System.IO.Path]::GetExtension($Path).ToLower()
            $Format = Get-QuestFormat -Content $Content -Extension $ext
        }
    }
    else {
        if ($Format -eq 'auto') {
            $Format = Get-QuestFormat -Content $Content
        }
    }
    
    return Get-QuestPrerequisitesFromContent -Content $Content -Format $Format
}

<#
.SYNOPSIS
    Extracts quest rewards from quest files.
    
    DEPRECATED: Use Export-QuestRewards instead.
#>
function Get-QuestRewardData {
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [Parameter(Mandatory = $true, ParameterSetName = 'Path')]
        [string]$Path,
        
        [Parameter(Mandatory = $true, ParameterSetName = 'Content')]
        [string]$Content,
        
        [Parameter()]
        [ValidateSet('auto', 'quest_system', 'json', 'gdscript')]
        [string]$Format = 'auto'
    )
    
    $sourceFile = 'inline'
    if ($PSCmdlet.ParameterSetName -eq 'Path') {
        if (-not (Test-Path -LiteralPath $Path)) {
            return @{}
        }
        $sourceFile = $Path
        $Content = Get-Content -LiteralPath $Path -Raw
        if ($Format -eq 'auto') {
            $ext = [System.IO.Path]::GetExtension($Path).ToLower()
            $Format = Get-QuestFormat -Content $Content -Extension $ext
        }
    }
    else {
        if ($Format -eq 'auto') {
            $Format = Get-QuestFormat -Content $Content
        }
    }
    
    return Get-QuestRewardsFromContent -Content $Content -Format $Format
}

<#
.SYNOPSIS
    Main entry point for parsing quest files.
    
    DEPRECATED: Use the specific Export-* and Get-* functions instead.

.DESCRIPTION
    Legacy entry point that delegates to the canonical extraction functions.
#>
function Invoke-QuestExtract {
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [Parameter(Mandatory = $true, ParameterSetName = 'Path')]
        [string]$Path,
        
        [Parameter(Mandatory = $true, ParameterSetName = 'Content')]
        [string]$Content,
        
        [Parameter()]
        [ValidateSet('auto', 'quest_system', 'json', 'gdscript')]
        [string]$Format = 'auto'
    )
    
    try {
        $sourceFile = 'inline'
        
        if ($PSCmdlet.ParameterSetName -eq 'Path') {
            if (-not (Test-Path -LiteralPath $Path)) {
                return @{
                    filePath = $Path
                    success = $false
                    error = "File not found: $Path"
                }
            }
            $sourceFile = Resolve-Path -Path $Path | Select-Object -ExpandProperty Path
            $questDefs = Export-QuestDefinitions -Path $Path -Format $Format
        }
        else {
            $questDefs = Export-QuestDefinitions -Content $Content -Format $Format
        }
        
        $objectives = Export-QuestObjectives -QuestDefinitions $questDefs
        $rewards = Export-QuestRewards -QuestDefinitions $questDefs
        $graph = Get-QuestGraph -QuestDefinitions $questDefs
        $metrics = Get-QuestMetrics -QuestDefinitions $questDefs -QuestGraph $graph -QuestRewards $rewards
        
        return @{
            filePath = $sourceFile
            fileType = $questDefs.format
            quests = $questDefs.quests
            questMap = $questDefs.questMap
            objectives = $objectives.objectives
            questObjectives = $objectives.questObjectives
            rewards = $rewards.rewards
            rewardSummary = $rewards.rewardSummary
            graph = @{
                nodes = $graph.nodes
                edges = $graph.edges
                chains = $graph.chains
            }
            metrics = @{
                overview = $metrics.overview
                distribution = $metrics.distribution
                complexity = $metrics.complexity
                balance = $metrics.balance
            }
            statistics = $questDefs.statistics
            metadata = $questDefs.metadata
        }
    }
    catch {
        Write-Error "[$script:ParserName] Failed to extract quest data: $_"
        return @{
            filePath = $sourceFile
            success = $false
            error = $_.ToString()
        }
    }
}

# ============================================================================
# Module Export
# ============================================================================

Export-ModuleMember -Function @(
    # Primary API (Canonical Document Section 25.7)
    'Export-QuestSystem'
    'Export-QuestDefinitions'
    'Export-QuestObjectives'
    'Get-QuestGraph'
    'Export-QuestRewards'
    'Get-QuestMetrics'
    
    # Helper functions
    'Get-QuestFormat'
    'Get-QuestObjectivesFromContent'
    'Get-QuestRewardsFromContent'
    'Get-QuestPrerequisitesFromContent'
    
    # Legacy compatibility
    'Invoke-QuestExtract'
    'Get-QuestData'
    'Get-QuestObjectives'
    'Get-QuestPrerequisites'
    'Get-QuestRewardData'
)
