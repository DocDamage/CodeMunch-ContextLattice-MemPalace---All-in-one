#Requires -Version 5.1
<#
.SYNOPSIS
    Godot Inventory System extractor for LLM Workflow Extraction Pipeline.

.DESCRIPTION
    Extracts structured inventory system data from Godot GDScript files and resource files.
    Parses item definitions, inventory configurations, crafting recipes, equipment slots,
    and hotbar systems from:
    - expressobits/inventory-system
    - bitbrain/pandora (RPG data framework with inventory)
    - Custom Godot inventory implementations
    
    Supports .gd (GDScript), .tres (resources), .tscn (scenes), and .json files.
    
    This parser implements Section 25.6 of the canonical architecture for the
    Godot Engine pack's structured extraction pipeline.

.REQUIRED FUNCTIONS
    - Export-InventorySystem: Extract inventory system configuration
    - Export-ItemDefinitions: Extract item schemas/types
    - Export-CraftingRecipes: Extract crafting relationships
    - Export-EquipmentSlots: Extract equipment system
    - Get-InventoryMetrics: Calculate inventory system metrics
    - Convert-ToInventoryGraph: Convert to graph representation

.PARAMETER Path
    Path to the GDScript file (.gd), resource file (.tres), scene file (.tscn), or JSON file to parse.

.PARAMETER Content
    File content string (alternative to Path).

.PARAMETER Format
    Format of the inventory file (auto, inventory_system, pandora, json, gdscript).

.OUTPUTS
    JSON with item definitions, inventory configurations, crafting recipes,
    equipment slots, and provenance metadata (source file, extraction timestamp, parser version).

.NOTES
    File Name      : GodotInventoryExtractor.ps1
    Author         : LLM Workflow Team
    Version        : 2.0.0
    Prerequisite   : PowerShell 5.1+
    Copyright      : (c) 2026 LLM Workflow Project
    License        : MIT
    Engine Support : Godot 4.x (with Godot 3.x compatibility)
    Pack           : godot-engine
#>

Set-StrictMode -Version Latest

# ============================================================================
# Module Constants and Version
# ============================================================================

$script:ParserVersion = '2.0.0'
$script:ParserName = 'GodotInventoryExtractor'

# Supported file formats
$script:SupportedFormats = @('auto', 'inventory_system', 'pandora', 'json', 'gdscript', 'tres')

# Regex Patterns for Inventory Parsing
$script:InventoryPatterns = @{
    # Item definition patterns
    ItemResource = 'extends\s+(?:Item|InventoryItem|BaseItem|ItemResource|ItemDefinition)'
    ItemClassName = 'class_name\s+(\w+)'
    ItemExport = '@export\s+var\s+(item_id|id|item_name|name|description|icon|stack_size|max_stack|weight|value|rarity|category|type)'
    ItemId = '(?:item_id|id)\s*[=:]\s*["'']([^"'']+)["'']'
    ItemName = '(?:item_name|name)\s*[=:]\s*["'']([^"'']+)["'']'
    ItemDescription = '(?:description)\s*[=:]\s*["'']([^"'']+)["'']'
    ItemIcon = '(?:icon)\s*[=:]\s*(?:preload|load)\s*\(\s*["'']([^"'']+)["'']\s*\)'
    ItemStackSize = '(?:stack_size|max_stack|max_stack_size)\s*[=:]\s*(\d+)'
    ItemWeight = '(?:weight)\s*[=:]\s*([\d.]+)'
    ItemValue = '(?:value|gold_value|price)\s*[=:]\s*(\d+)'
    ItemRarity = '(?:rarity)\s*[=:]\s*["''](\w+)["'']'
    ItemCategory = '(?:category|type|item_type)\s*[=:]\s*["''](\w+)["'']'
    ItemProperties = '@export\s+var\s+(\w+)\s*:\s*(\w+)'
    
    # Inventory system patterns (expressobits/inventory-system)
    InventoryBase = 'extends\s+(?:Inventory|BaseInventory|InventorySystem|ItemInventory)'
    InventoryGrid = 'extends\s+(?:InventoryGrid|GridInventory|SlotInventory)'
    InventorySlot = '@export\s+var\s+slots?|@export\s+var\s+grid'
    InventorySize = '(?:size|width|height|slot_count)\s*[=:]\s*(\d+)'
    InventoryGridSize = 'Vector2i?\s*\(\s*(\d+)\s*,\s*(\d+)\s*\)'
    
    # Crafting patterns
    CraftingRecipe = 'extends\s+(?:Recipe|CraftingRecipe|RecipeResource|CraftingData)'
    RecipeIngredients = '(?:ingredients|required_items|inputs?)'
    RecipeResults = '(?:results?|output|crafted_item|product)'
    RecipeCraftingTime = '(?:crafting_time|craft_time|duration)\s*[=:]\s*([\d.]+)'
    RecipeStation = '(?:crafting_station|station|workbench|required_station)'
    
    # Equipment slot patterns
    EquipmentSlot = 'extends\s+(?:EquipmentSlot|Slot|ItemSlot|GearSlot)'
    EquipmentSystem = 'extends\s+(?:Equipment|EquipmentSystem|GearSystem|GearManager)'
    SlotType = '(?:slot_type|equipment_type|gear_type)\s*[=:]\s*["''](\w+)["'']'
    SlotName = '@export\s+var\s+slot_name|slot_id'
    
    # Hotbar patterns
    HotbarBase = 'extends\s+(?:Hotbar|QuickSlot|ActionBar|HotbarSystem)'
    HotbarSlot = '(?:hotbar_slots?|quick_slots?|action_slots?)\s*[=:]'
    HotbarSize = '(?:hotbar_size|slot_count)\s*[=:]\s*(\d+)'
    
    # Pandora patterns (RPG data framework)
    PandoraItem = 'extends\s+PandoraEntity|@icon\s*\([^)]*\)\s*class_name'
    PandoraProperty = '@export\s+var\s+.*:\s*PandoraProperty'
    PandoraCategory = 'PandoraCategory|pandora_category'
    
    # Resource loading patterns
    ResourceScript = 'class_name\s+(\w+).*extends\s+Resource'
    PreloadItem = 'preload\s*\(\s*["'']([^"'']*item[^"'']*)["'']\s*\)'
    LoadItem = 'load\s*\(\s*["'']([^"'']*item[^"'']*)["'']\s*\)'
    
    # Signal patterns
    ItemAddedSignal = 'signal\s+item_added|item_picked_up|inventory_changed'
    ItemRemovedSignal = 'signal\s+item_removed|item_dropped|item_consumed'
    CraftingSignal = 'signal\s+recipe_completed|crafting_finished|item_crafted'
    EquipmentSignal = 'signal\s+equipment_changed|slot_equipped|item_equipped'
    
    # JSON patterns
    JsonItemId = '"id"\s*:\s*"([^"]+)"'
    JsonItemName = '"name"\s*:\s*"([^"]+)"'
    JsonItemType = '"type"|"category"\s*:\s*"([^"]+)"'
    JsonRecipeInput = '"ingredients"|"inputs"\s*:\s*\['
    JsonRecipeOutput = '"result"|"output"\s*:\s*\{'
    
    # Scene file patterns
    InventoryNode = 'type="Inventory"|type="ItemContainer"'
    ItemInstance = 'type="ItemInstance"|type="InventoryItem"'
    SlotNode = 'type="Slot"|type="ItemSlot"|type="InventorySlot"'
    ResourcePath = 'path="res://([^"]+)"'
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
    Detects the inventory file format from content.
.DESCRIPTION
    Analyzes the content to determine the inventory file format.
.PARAMETER Content
    The file content to analyze.
.PARAMETER Extension
    The file extension.
.OUTPUTS
    System.String. The detected format.
#>
function Get-InventoryFormat {
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
        '.json' { 
            # Check content for inventory JSON
            if ($Content -match '"items"' -or $Content -match '"inventory"' -or $Content -match '"recipes"') {
                return 'json'
            }
            return 'json'
        }
        '.tres' { return 'tres' }
        '.tscn' { return 'gdscript' }
        '.gd' { return 'gdscript' }
    }
    
    # Check content patterns
    if ($Content -match 'extends\s+InventoryGrid|extends\s+BaseInventory') {
        return 'inventory_system'
    }
    if ($Content -match 'extends\s+PandoraEntity|PandoraProperty|PandoraCategory') {
        return 'pandora'
    }
    if ($Content -match '"item_definitions"|"crafting_recipes"') {
        return 'json'
    }
    
    return 'gdscript'
}

<#
.SYNOPSIS
    Gets file metadata for extraction context.
.DESCRIPTION
    Collects file information including size, line count, and modification time.
.PARAMETER Path
    Path to the file.
.OUTPUTS
    System.Collections.Hashtable. File metadata object.
#>
function Get-FileMetadata {
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path
    )
    
    try {
        $fileInfo = Get-Item -LiteralPath $Path
        $content = Get-Content -LiteralPath $Path -Raw -ErrorAction SilentlyContinue
        $lineCount = if ($content) { @($content -split "`r?`n").Count } else { 0 }
        
        return @{
            fileSize = $fileInfo.Length
            lineCount = $lineCount
            lastModified = $fileInfo.LastWriteTimeUtc.ToString("o")
            extension = $fileInfo.Extension
        }
    }
    catch {
        return @{
            fileSize = 0
            lineCount = 0
            lastModified = $null
            extension = [System.IO.Path]::GetExtension($Path)
        }
    }
}

<#
.SYNOPSIS
    Parses item properties from GDScript content.
.DESCRIPTION
    Extracts item property definitions from a GDScript class.
.PARAMETER Content
    The GDScript class content.
.PARAMETER StartLine
    The line number where the class starts.
.OUTPUTS
    System.Collections.Hashtable. Item properties.
#>
function Get-ItemProperties {
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Content,
        
        [Parameter()]
        [int]$StartLine = 0
    )
    
    $properties = @{
        itemId = $null
        itemName = $null
        description = $null
        icon = $null
        stackSize = 1
        maxStack = 1
        weight = 0.0
        value = 0
        rarity = 'common'
        category = 'misc'
        customProperties = @()
    }
    
    $lines = $Content -split "`r?`n"
    
    foreach ($line in $lines) {
        # Item ID
        if ($line -match $script:InventoryPatterns.ItemId) {
            $properties.itemId = $matches[1]
        }
        # Item Name
        elseif ($line -match $script:InventoryPatterns.ItemName) {
            $properties.itemName = $matches[1]
        }
        # Description
        elseif ($line -match $script:InventoryPatterns.ItemDescription) {
            $properties.description = $matches[1]
        }
        # Icon
        elseif ($line -match $script:InventoryPatterns.ItemIcon) {
            $properties.icon = $matches[1]
        }
        # Stack Size
        elseif ($line -match $script:InventoryPatterns.ItemStackSize) {
            $properties.stackSize = [int]$matches[1]
            $properties.maxStack = [int]$matches[1]
        }
        # Weight
        elseif ($line -match $script:InventoryPatterns.ItemWeight) {
            $properties.weight = [float]$matches[1]
        }
        # Value
        elseif ($line -match $script:InventoryPatterns.ItemValue) {
            $properties.value = [int]$matches[1]
        }
        # Rarity
        elseif ($line -match $script:InventoryPatterns.ItemRarity) {
            $properties.rarity = $matches[1].ToLower()
        }
        # Category
        elseif ($line -match $script:InventoryPatterns.ItemCategory) {
            $properties.category = $matches[1].ToLower()
        }
        # Custom @export properties
        elseif ($line -match $script:InventoryPatterns.ItemProperties) {
            $propName = $matches[1]
            $propType = $matches[2]
            
            # Skip standard properties
            if ($propName -notin @('item_id', 'id', 'item_name', 'name', 'description', 'icon', 'stack_size', 'max_stack', 'weight', 'value', 'rarity', 'category')) {
                $properties.customProperties += @{
                    name = $propName
                    type = $propType
                    line = $line.Trim()
                }
            }
        }
    }
    
    # If itemId is not set but class_name exists, use that
    if (-not $properties.itemId -and $Content -match $script:InventoryPatterns.ItemClassName) {
        $properties.itemId = $matches[1].ToLower()
    }
    
    # If itemName is not set but itemId exists, use itemId as fallback
    if (-not $properties.itemName -and $properties.itemId) {
        $properties.itemName = $properties.itemId -replace '_', ' ' -replace '-', ' '
        $properties.itemName = (Get-Culture).TextInfo.ToTitleCase($properties.itemName)
    }
    
    return $properties
}

<#
.SYNOPSIS
    Parses JSON inventory data.
.DESCRIPTION
    Extracts inventory data from JSON format.
.PARAMETER Content
    The JSON content.
.OUTPUTS
    System.Collections.Hashtable. Parsed inventory data.
#>
function Get-JsonInventoryData {
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Content
    )
    
    try {
        $json = $Content | ConvertFrom-Json -Depth 10
        
        $result = @{
            items = @()
            recipes = @()
            inventory = $null
        }
        
        # Extract items
        if ($json.items) {
            foreach ($item in $json.items) {
                $result.items += @{
                    id = $item.id
                    name = $item.name
                    description = $item.description
                    icon = $item.icon
                    stackSize = $item.stack_size -or $item.max_stack -or 1
                    weight = $item.weight -or 0
                    value = $item.value -or 0
                    rarity = $item.rarity -or 'common'
                    category = $item.category -or $item.type -or 'misc'
                    properties = $item.properties
                }
            }
        }
        
        # Extract recipes
        if ($json.recipes) {
            foreach ($recipe in $json.recipes) {
                $result.recipes += @{
                    id = $recipe.id
                    name = $recipe.name
                    ingredients = $recipe.ingredients -or $recipe.inputs
                    results = $recipe.results -or $recipe.output
                    craftingTime = $recipe.crafting_time -or $recipe.duration -or 0
                    station = $recipe.station -or $recipe.crafting_station
                }
            }
        }
        
        return $result
    }
    catch {
        Write-Warning "[$script:ParserName] Failed to parse JSON inventory data: $_"
        return @{
            items = @()
            recipes = @()
            inventory = $null
        }
    }
}

# ============================================================================
# Public API Functions - Required by Canonical Document Section 25.6
# ============================================================================

<#
.SYNOPSIS
    Extracts inventory system configuration from Godot files.

.DESCRIPTION
    Parses GDScript files (.gd), resource files (.tres), scene files (.tscn), or
    JSON files to identify inventory system configurations including grid sizes,
    slot counts, inventory types, and associated signals.
    Supports expressobits/inventory-system and custom implementations.

.PARAMETER Path
    Path to the inventory system file.

.PARAMETER Content
    File content string (alternative to Path).

.PARAMETER Format
    Format of the inventory file (auto, inventory_system, pandora, json, gdscript).

.OUTPUTS
    System.Collections.Hashtable. Object containing:
    - inventory: Inventory system configuration object
    - slots: Array of slot configurations
    - signals: Array of inventory-related signals
    - metadata: Provenance metadata
    - statistics: Extraction statistics

.EXAMPLE
    $inventory = Export-InventorySystem -Path "res://inventory/player_inventory.gd"
    
    $inventory = Export-InventorySystem -Content $jsonContent -Format "json"
#>
function Export-InventorySystem {
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [Parameter(Mandatory = $true, ParameterSetName = 'Path')]
        [string]$Path,
        
        [Parameter(Mandatory = $true, ParameterSetName = 'Content')]
        [string]$Content,
        
        [Parameter()]
        [ValidateSet('auto', 'inventory_system', 'pandora', 'json', 'gdscript', 'tres')]
        [string]$Format = 'auto'
    )
    
    try {
        # Load content
        $sourceFile = 'inline'
        if ($PSCmdlet.ParameterSetName -eq 'Path') {
            if (-not (Test-Path -LiteralPath $Path)) {
                return @{
                    inventory = $null
                    slots = @()
                    signals = @()
                    metadata = New-ProvenanceMetadata -SourceFile $Path -Success $false -Errors @("File not found: $Path")
                    statistics = @{ slotCount = 0; hasGrid = $false }
                }
            }
            $sourceFile = Resolve-Path -Path $Path | Select-Object -ExpandProperty Path
            $Content = Get-Content -LiteralPath $Path -Raw -Encoding UTF8
            
            # Auto-detect format from extension
            if ($Format -eq 'auto') {
                $ext = [System.IO.Path]::GetExtension($Path).ToLower()
                $Format = Get-InventoryFormat -Content $Content -Extension $ext
            }
        }
        else {
            if ($Format -eq 'auto') {
                $Format = Get-InventoryFormat -Content $Content
            }
        }
        
        if ([string]::IsNullOrWhiteSpace($Content)) {
            return @{
                inventory = $null
                slots = @()
                signals = @()
                metadata = New-ProvenanceMetadata -SourceFile $sourceFile -Success $false -Errors @("Content is empty")
                statistics = @{ slotCount = 0; hasGrid = $false }
            }
        }
        
        $inventory = @{
            type = 'unknown'
            className = ''
            gridSize = $null
            slotCount = 0
            hasWeightLimit = $false
            weightLimit = 0
            acceptsCategories = @()
        }
        
        $slots = @()
        $signals = @()
        $lines = $Content -split "`r?`n"
        $lineNumber = 0
        
        foreach ($line in $lines) {
            $lineNumber++
            $trimmed = $line.Trim()
            
            # Detect inventory type
            if ($line -match $script:InventoryPatterns.InventoryGrid) {
                $inventory.type = 'grid'
                if ($line -match 'class_name\s+(\w+)') {
                    $inventory.className = $matches[1]
                }
            }
            elseif ($line -match $script:InventoryPatterns.InventoryBase) {
                $inventory.type = 'standard'
                if ($line -match 'class_name\s+(\w+)') {
                    $inventory.className = $matches[1]
                }
            }
            
            # Detect grid size
            if ($line -match $script:InventoryPatterns.InventoryGridSize) {
                $width = [int]$matches[1]
                $height = [int]$matches[2]
                $inventory.gridSize = @{
                    width = $width
                    height = $height
                }
                $inventory.slotCount = $width * $height
            }
            
            # Detect slot count
            if ($line -match $script:InventoryPatterns.InventorySize) {
                $inventory.slotCount = [int]$matches[1]
            }
            
            # Detect inventory slots
            if ($line -match $script:InventoryPatterns.InventorySlot) {
                if ($line -match ':\s*Array\[?(\w*)\]?') {
                    $slots += @{
                        type = $matches[1] -or 'Slot'
                        lineNumber = $lineNumber
                    }
                }
            }
            
            # Detect signals
            if ($line -match $script:InventoryPatterns.ItemAddedSignal) {
                $signals += @{
                    name = 'item_added'
                    type = 'inventory'
                    lineNumber = $lineNumber
                }
            }
            if ($line -match $script:InventoryPatterns.ItemRemovedSignal) {
                $signals += @{
                    name = 'item_removed'
                    type = 'inventory'
                    lineNumber = $lineNumber
                }
            }
        }
        
        # Handle JSON format
        if ($Format -eq 'json') {
            $jsonData = Get-JsonInventoryData -Content $Content
            if ($jsonData.inventory) {
                $inventory.type = $jsonData.inventory.type -or 'standard'
                $inventory.slotCount = $jsonData.inventory.slots -or $jsonData.inventory.size -or 0
                if ($jsonData.inventory.grid) {
                    $inventory.gridSize = $jsonData.inventory.grid
                    $inventory.type = 'grid'
                }
            }
        }
        
        Write-Verbose "[$script:ParserName] Extracted inventory system: type=$($inventory.type), slots=$($inventory.slotCount)"
        
        return @{
            inventory = $inventory
            slots = $slots
            signals = $signals
            format = $Format
            metadata = New-ProvenanceMetadata -SourceFile $sourceFile -Success $true
            statistics = @{
                slotCount = $inventory.slotCount
                hasGrid = ($inventory.gridSize -ne $null)
                signalCount = $signals.Count
                type = $inventory.type
            }
        }
    }
    catch {
        Write-Error "[$script:ParserName] Failed to extract inventory system: $_"
        return @{
            inventory = $null
            slots = @()
            signals = @()
            metadata = New-ProvenanceMetadata -SourceFile $sourceFile -Success $false -Errors @($_.ToString())
            statistics = @{ slotCount = 0; hasGrid = $false }
        }
    }
}

<#
.SYNOPSIS
    Extracts item definitions from Godot files.

.DESCRIPTION
    Parses GDScript files, resource files, or JSON files to extract item definitions
    including item IDs, names, descriptions, icons, stack sizes, weights, values,
    rarities, categories, and custom properties.
    Supports expressobits/inventory-system Item resources and pandora entities.

.PARAMETER Path
    Path to the item definition file.

.PARAMETER Content
    File content string (alternative to Path).

.PARAMETER Format
    Format of the file (auto, inventory_system, pandora, json, gdscript).

.OUTPUTS
    System.Collections.Hashtable. Object containing:
    - items: Array of item definition objects
    - categories: Array of unique item categories
    - rarities: Array of unique rarity levels
    - metadata: Provenance metadata
    - statistics: Extraction statistics

.EXAMPLE
    $items = Export-ItemDefinitions -Path "res://items/resources/"
    
    $items = Export-ItemDefinitions -Content $itemScript -Format "gdscript"
#>
function Export-ItemDefinitions {
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [Parameter(Mandatory = $true, ParameterSetName = 'Path')]
        [string]$Path,
        
        [Parameter(Mandatory = $true, ParameterSetName = 'Content')]
        [string]$Content,
        
        [Parameter()]
        [ValidateSet('auto', 'inventory_system', 'pandora', 'json', 'gdscript', 'tres')]
        [string]$Format = 'auto'
    )
    
    try {
        # Load content
        $sourceFile = 'inline'
        $allContent = $Content
        
        if ($PSCmdlet.ParameterSetName -eq 'Path') {
            if (-not (Test-Path -LiteralPath $Path)) {
                return @{
                    items = @()
                    categories = @()
                    rarities = @()
                    metadata = New-ProvenanceMetadata -SourceFile $Path -Success $false -Errors @("File not found: $Path")
                    statistics = @{ itemCount = 0; categoryCount = 0 }
                }
            }
            
            # If path is a directory, process all .gd files
            $fileItem = Get-Item -LiteralPath $Path
            if ($fileItem.PSIsContainer) {
                $allFiles = Get-ChildItem -Path $Path -Filter "*.gd" -Recurse
                $allContent = ($allFiles | ForEach-Object { Get-Content -LiteralPath $_.FullName -Raw }) -join "`n# FILE: `n"
            }
            else {
                $sourceFile = Resolve-Path -Path $Path | Select-Object -ExpandProperty Path
                $allContent = Get-Content -LiteralPath $Path -Raw -Encoding UTF8
            }
            
            # Auto-detect format from extension
            if ($Format -eq 'auto') {
                $ext = [System.IO.Path]::GetExtension($Path).ToLower()
                $Format = Get-InventoryFormat -Content $allContent -Extension $ext
            }
        }
        else {
            if ($Format -eq 'auto') {
                $Format = Get-InventoryFormat -Content $Content
            }
        }
        
        if ([string]::IsNullOrWhiteSpace($allContent)) {
            return @{
                items = @()
                categories = @()
                rarities = @()
                metadata = New-ProvenanceMetadata -SourceFile $sourceFile -Success $false -Errors @("Content is empty")
                statistics = @{ itemCount = 0; categoryCount = 0 }
            }
        }
        
        $items = @()
        $categories = @{}
        $rarities = @{}
        
        # Handle JSON format
        if ($Format -eq 'json') {
            $jsonData = Get-JsonInventoryData -Content $allContent
            $items = $jsonData.items
            foreach ($item in $items) {
                if ($item.category) { $categories[$item.category] = $true }
                if ($item.rarity) { $rarities[$item.rarity] = $true }
            }
        }
        else {
            # Parse GDScript for item definitions
            $lines = $allContent -split "`r?`n"
            $lineNumber = 0
            $currentItem = $null
            $itemContent = ''
            
            foreach ($line in $lines) {
                $lineNumber++
                
                # Check for new item class definition
                if ($line -match $script:InventoryPatterns.ItemResource) {
                    # Save previous item if exists
                    if ($currentItem -and $itemContent) {
                        $props = Get-ItemProperties -Content $itemContent
                        $currentItem.properties = $props
                        $currentItem.itemId = $props.itemId
                        $currentItem.itemName = $props.itemName
                        $currentItem.description = $props.description
                        $currentItem.icon = $props.icon
                        $currentItem.stackSize = $props.stackSize
                        $currentItem.weight = $props.weight
                        $currentItem.value = $props.value
                        $currentItem.rarity = $props.rarity
                        $currentItem.category = $props.category
                        $currentItem.customProperties = $props.customProperties
                        
                        $items += $currentItem
                        if ($props.category) { $categories[$props.category] = $true }
                        if ($props.rarity) { $rarities[$props.rarity] = $true }
                    }
                    
                    # Start new item
                    $className = ''
                    if ($line -match 'class_name\s+(\w+)') {
                        $className = $matches[1]
                    }
                    
                    $extends = ''
                    if ($line -match 'extends\s+(\w+)') {
                        $extends = $matches[1]
                    }
                    
                    $currentItem = @{
                        id = [System.Guid]::NewGuid().ToString()
                        className = $className
                        extends = $extends
                        lineNumber = $lineNumber
                        itemId = $null
                        itemName = $null
                        description = $null
                        icon = $null
                        stackSize = 1
                        weight = 0.0
                        value = 0
                        rarity = 'common'
                        category = 'misc'
                        customProperties = @()
                    }
                    $itemContent = $line + "`n"
                }
                elseif ($currentItem) {
                    $itemContent += $line + "`n"
                    
                    # Check for end of class
                    if ($line -match '^class\s' -or $lineNumber -eq $lines.Count) {
                        $props = Get-ItemProperties -Content $itemContent
                        $currentItem.properties = $props
                        $currentItem.itemId = $props.itemId
                        $currentItem.itemName = $props.itemName
                        $currentItem.description = $props.description
                        $currentItem.icon = $props.icon
                        $currentItem.stackSize = $props.stackSize
                        $currentItem.weight = $props.weight
                        $currentItem.value = $props.value
                        $currentItem.rarity = $props.rarity
                        $currentItem.category = $props.category
                        $currentItem.customProperties = $props.customProperties
                        
                        $items += $currentItem
                        if ($props.category) { $categories[$props.category] = $true }
                        if ($props.rarity) { $rarities[$props.rarity] = $true }
                        $currentItem = $null
                        $itemContent = ''
                    }
                }
            }
            
            # Handle last item
            if ($currentItem -and $itemContent) {
                $props = Get-ItemProperties -Content $itemContent
                $currentItem.properties = $props
                $currentItem.itemId = $props.itemId
                $currentItem.itemName = $props.itemName
                $currentItem.description = $props.description
                $currentItem.icon = $props.icon
                $currentItem.stackSize = $props.stackSize
                $currentItem.weight = $props.weight
                $currentItem.value = $props.value
                $currentItem.rarity = $props.rarity
                $currentItem.category = $props.category
                $currentItem.customProperties = $props.customProperties
                
                $items += $currentItem
                if ($props.category) { $categories[$props.category] = $true }
                if ($props.rarity) { $rarities[$props.rarity] = $true }
            }
        }
        
        Write-Verbose "[$script:ParserName] Extracted $($items.Count) item definitions"
        
        return @{
            items = $items
            categories = @($categories.Keys | Sort-Object)
            rarities = @($rarities.Keys | Sort-Object)
            format = $Format
            metadata = New-ProvenanceMetadata -SourceFile $sourceFile -Success $true
            statistics = @{
                itemCount = $items.Count
                categoryCount = $categories.Count
                rarityCount = $rarities.Count
                avgStackSize = if ($items.Count -gt 0) { [math]::Round(($items | Measure-Object -Property stackSize -Average).Average, 2) } else { 0 }
                totalValue = ($items | Measure-Object -Property value -Sum).Sum
            }
        }
    }
    catch {
        Write-Error "[$script:ParserName] Failed to extract item definitions: $_"
        return @{
            items = @()
            categories = @()
            rarities = @()
            metadata = New-ProvenanceMetadata -SourceFile $sourceFile -Success $false -Errors @($_.ToString())
            statistics = @{ itemCount = 0; categoryCount = 0 }
        }
    }
}

<#
.SYNOPSIS
    Extracts crafting recipe definitions from Godot files.

.DESCRIPTION
    Parses GDScript files, resource files, or JSON files to extract crafting recipes
    including ingredient requirements, crafting results, crafting time, and required stations.

.PARAMETER Path
    Path to the crafting recipe file or directory.

.PARAMETER Content
    File content string (alternative to Path).

.PARAMETER Format
    Format of the file (auto, json, gdscript, tres).

.OUTPUTS
    System.Collections.Hashtable. Object containing:
    - recipes: Array of crafting recipe objects
    - stations: Array of unique crafting stations
    - ingredientCounts: Dictionary of ingredient usage counts
    - metadata: Provenance metadata
    - statistics: Extraction statistics

.EXAMPLE
    $recipes = Export-CraftingRecipes -Path "res://crafting/recipes/"
    
    $recipes = Export-CraftingRecipes -Content $recipeData -Format "json"
#>
function Export-CraftingRecipes {
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [Parameter(Mandatory = $true, ParameterSetName = 'Path')]
        [string]$Path,
        
        [Parameter(Mandatory = $true, ParameterSetName = 'Content')]
        [string]$Content,
        
        [Parameter()]
        [ValidateSet('auto', 'json', 'gdscript', 'tres')]
        [string]$Format = 'auto'
    )
    
    try {
        # Load content
        $sourceFile = 'inline'
        $allContent = $Content
        
        if ($PSCmdlet.ParameterSetName -eq 'Path') {
            if (-not (Test-Path -LiteralPath $Path)) {
                return @{
                    recipes = @()
                    stations = @()
                    ingredientCounts = @{}
                    metadata = New-ProvenanceMetadata -SourceFile $Path -Success $false -Errors @("File not found: $Path")
                    statistics = @{ recipeCount = 0; stationCount = 0 }
                }
            }
            
            # If path is a directory, process all files
            $fileItem = Get-Item -LiteralPath $Path
            if ($fileItem.PSIsContainer) {
                $allFiles = Get-ChildItem -Path $Path -Filter "*.gd" -Recurse
                $gdFiles = @($allFiles) + @(Get-ChildItem -Path $Path -Filter "*.json" -Recurse)
                $allContent = ($gdFiles | ForEach-Object { Get-Content -LiteralPath $_.FullName -Raw }) -join "`n# FILE: `n"
            }
            else {
                $sourceFile = Resolve-Path -Path $Path | Select-Object -ExpandProperty Path
                $allContent = Get-Content -LiteralPath $Path -Raw -Encoding UTF8
            }
            
            # Auto-detect format from extension
            if ($Format -eq 'auto') {
                $ext = [System.IO.Path]::GetExtension($Path).ToLower()
                $Format = Get-InventoryFormat -Content $allContent -Extension $ext
            }
        }
        else {
            if ($Format -eq 'auto') {
                $Format = Get-InventoryFormat -Content $Content
            }
        }
        
        $recipes = @()
        $stations = @{}
        $ingredientCounts = @{}
        
        # Handle JSON format
        if ($Format -eq 'json') {
            $jsonData = Get-JsonInventoryData -Content $allContent
            foreach ($recipe in $jsonData.recipes) {
                $recipeObj = @{
                    id = $recipe.id -or [System.Guid]::NewGuid().ToString()
                    name = $recipe.name
                    ingredients = @()
                    results = @()
                    craftingTime = $recipe.craftingTime -or 0
                    station = $recipe.station
                }
                
                # Process ingredients
                if ($recipe.ingredients) {
                    foreach ($ing in $recipe.ingredients) {
                        $ingredient = @{
                            itemId = if ($ing.item_id) { $ing.item_id } else { $ing.id }
                            count = $ing.count -or $ing.amount -or 1
                        }
                        $recipeObj.ingredients += $ingredient
                        
                        # Track ingredient usage
                        $ingId = $ingredient.itemId
                        if (-not $ingredientCounts.ContainsKey($ingId)) {
                            $ingredientCounts[$ingId] = 0
                        }
                        $ingredientCounts[$ingId]++
                    }
                }
                
                # Process results
                if ($recipe.results) {
                    foreach ($res in $recipe.results) {
                        $result = @{
                            itemId = if ($res.item_id) { $res.item_id } else { $res.id }
                            count = $res.count -or $res.amount -or 1
                        }
                        $recipeObj.results += $result
                    }
                }
                
                $recipes += $recipeObj
                if ($recipeObj.station) { $stations[$recipeObj.station] = $true }
            }
        }
        else {
            # Parse GDScript for recipe definitions
            $lines = $allContent -split "`r?`n"
            $lineNumber = 0
            $currentRecipe = $null
            
            foreach ($line in $lines) {
                $lineNumber++
                
                # Check for recipe class definition
                if ($line -match $script:InventoryPatterns.CraftingRecipe) {
                    $className = ''
                    if ($line -match 'class_name\s+(\w+)') {
                        $className = $matches[1]
                    }
                    
                    $currentRecipe = @{
                        id = [System.Guid]::NewGuid().ToString()
                        name = $className
                        className = $className
                        lineNumber = $lineNumber
                        ingredients = @()
                        results = @()
                        craftingTime = 0
                        station = $null
                    }
                }
                
                if ($currentRecipe) {
                    # Extract crafting time
                    if ($line -match $script:InventoryPatterns.RecipeCraftingTime) {
                        $currentRecipe.craftingTime = [float]$matches[1]
                    }
                    
                    # Extract required station
                    if ($line -match $script:InventoryPatterns.RecipeStation) {
                        if ($line -match '["'']([^"'']+)["'']') {
                            $currentRecipe.station = $matches[1]
                            $stations[$currentRecipe.station] = $true
                        }
                    }
                    
                    # Extract ingredients (array or dictionary patterns)
                    if ($line -match $script:InventoryPatterns.RecipeIngredients) {
                        # Look for ingredient definitions in subsequent lines
                        $inIngredients = $true
                    }
                    
                    # Detect end of class
                    if ($line -match '^class\s' -or $lineNumber -eq $lines.Count) {
                        if ($currentRecipe.ingredients.Count -gt 0 -or $currentRecipe.results.Count -gt 0) {
                            $recipes += $currentRecipe
                        }
                        $currentRecipe = $null
                    }
                }
            }
        }
        
        Write-Verbose "[$script:ParserName] Extracted $($recipes.Count) crafting recipes"
        
        return @{
            recipes = $recipes
            stations = @($stations.Keys | Sort-Object)
            ingredientCounts = $ingredientCounts
            format = $Format
            metadata = New-ProvenanceMetadata -SourceFile $sourceFile -Success $true
            statistics = @{
                recipeCount = $recipes.Count
                stationCount = $stations.Count
                avgCraftingTime = if ($recipes.Count -gt 0) { [math]::Round(($recipes | Measure-Object -Property craftingTime -Average).Average, 2) } else { 0 }
                avgIngredients = if ($recipes.Count -gt 0) { [math]::Round(($recipes | ForEach-Object { $_.ingredients.Count } | Measure-Object -Average).Average, 2) } else { 0 }
            }
        }
    }
    catch {
        Write-Error "[$script:ParserName] Failed to extract crafting recipes: $_"
        return @{
            recipes = @()
            stations = @()
            ingredientCounts = @{}
            metadata = New-ProvenanceMetadata -SourceFile $sourceFile -Success $false -Errors @($_.ToString())
            statistics = @{ recipeCount = 0; stationCount = 0 }
        }
    }
}

<#
.SYNOPSIS
    Extracts equipment slot definitions from Godot files.

.DESCRIPTION
    Parses GDScript files, resource files, or JSON files to extract equipment slot
    definitions including slot types, allowed item categories, and slot restrictions.

.PARAMETER Path
    Path to the equipment system file or directory.

.PARAMETER Content
    File content string (alternative to Path).

.PARAMETER Format
    Format of the file (auto, json, gdscript, tres).

.OUTPUTS
    System.Collections.Hashtable. Object containing:
    - slots: Array of equipment slot objects
    - slotTypes: Array of unique slot types
    - equipmentSystem: Equipment system configuration
    - metadata: Provenance metadata
    - statistics: Extraction statistics

.EXAMPLE
    $equipment = Export-EquipmentSlots -Path "res://equipment/equipment_system.gd"
    
    $equipment = Export-EquipmentSlots -Content $equipmentData -Format "json"
#>
function Export-EquipmentSlots {
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [Parameter(Mandatory = $true, ParameterSetName = 'Path')]
        [string]$Path,
        
        [Parameter(Mandatory = $true, ParameterSetName = 'Content')]
        [string]$Content,
        
        [Parameter()]
        [ValidateSet('auto', 'json', 'gdscript', 'tres')]
        [string]$Format = 'auto'
    )
    
    try {
        # Load content
        $sourceFile = 'inline'
        if ($PSCmdlet.ParameterSetName -eq 'Path') {
            if (-not (Test-Path -LiteralPath $Path)) {
                return @{
                    slots = @()
                    slotTypes = @()
                    equipmentSystem = $null
                    metadata = New-ProvenanceMetadata -SourceFile $Path -Success $false -Errors @("File not found: $Path")
                    statistics = @{ slotCount = 0; typeCount = 0 }
                }
            }
            $sourceFile = Resolve-Path -Path $Path | Select-Object -ExpandProperty Path
            $Content = Get-Content -LiteralPath $Path -Raw -Encoding UTF8
            
            # Auto-detect format from extension
            if ($Format -eq 'auto') {
                $ext = [System.IO.Path]::GetExtension($Path).ToLower()
                $Format = Get-InventoryFormat -Content $Content -Extension $ext
            }
        }
        else {
            if ($Format -eq 'auto') {
                $Format = Get-InventoryFormat -Content $Content
            }
        }
        
        $slots = @()
        $slotTypes = @{}
        $equipmentSystem = @{
            className = ''
            signals = @()
        }
        
        $lines = $Content -split "`r?`n"
        $lineNumber = 0
        $currentSlot = $null
        
        foreach ($line in $lines) {
            $lineNumber++
            
            # Detect equipment system
            if ($line -match $script:InventoryPatterns.EquipmentSystem) {
                if ($line -match 'class_name\s+(\w+)') {
                    $equipmentSystem.className = $matches[1]
                }
            }
            
            # Detect equipment signals
            if ($line -match $script:InventoryPatterns.EquipmentSignal) {
                $equipmentSystem.signals += @{
                    name = 'equipment_changed'
                    lineNumber = $lineNumber
                }
            }
            
            # Detect slot definition
            if ($line -match $script:InventoryPatterns.EquipmentSlot) {
                $className = ''
                if ($line -match 'class_name\s+(\w+)') {
                    $className = $matches[1]
                }
                
                $currentSlot = @{
                    id = [System.Guid]::NewGuid().ToString()
                    className = $className
                    slotType = ''
                    slotName = ''
                    allowedCategories = @()
                    lineNumber = $lineNumber
                }
            }
            
            if ($currentSlot) {
                # Extract slot type
                if ($line -match $script:InventoryPatterns.SlotType) {
                    $currentSlot.slotType = $matches[1]
                    $slotTypes[$currentSlot.slotType] = $true
                }
                
                # Extract slot name
                if ($line -match $script:InventoryPatterns.SlotName) {
                    if ($line -match '["'']([^"'']+)["'']') {
                        $currentSlot.slotName = $matches[1]
                    }
                }
                
                # Detect end of class
                if ($line -match '^class\s' -or $lineNumber -eq $lines.Count) {
                    if ($currentSlot.slotType -or $currentSlot.slotName) {
                        $slots += $currentSlot
                    }
                    $currentSlot = $null
                }
            }
        }
        
        # Handle last slot
        if ($currentSlot -and ($currentSlot.slotType -or $currentSlot.slotName)) {
            $slots += $currentSlot
        }
        
        Write-Verbose "[$script:ParserName] Extracted $($slots.Count) equipment slots"
        
        return @{
            slots = $slots
            slotTypes = @($slotTypes.Keys | Sort-Object)
            equipmentSystem = $equipmentSystem
            format = $Format
            metadata = New-ProvenanceMetadata -SourceFile $sourceFile -Success $true
            statistics = @{
                slotCount = $slots.Count
                typeCount = $slotTypes.Count
                signalCount = $equipmentSystem.signals.Count
            }
        }
    }
    catch {
        Write-Error "[$script:ParserName] Failed to extract equipment slots: $_"
        return @{
            slots = @()
            slotTypes = @()
            equipmentSystem = $null
            metadata = New-ProvenanceMetadata -SourceFile $sourceFile -Success $false -Errors @($_.ToString())
            statistics = @{ slotCount = 0; typeCount = 0 }
        }
    }
}

<#
.SYNOPSIS
    Calculates inventory system metrics.

.DESCRIPTION
    Analyzes extracted inventory data (items, recipes, equipment slots) and calculates
    comprehensive metrics for quality assessment and complexity analysis.

.PARAMETER InventoryData
    Hashtable containing extracted inventory data from Export-InventorySystem,
    Export-ItemDefinitions, Export-CraftingRecipes, or Export-EquipmentSlots.

.PARAMETER Path
    Path to the Godot file to analyze directly.

.PARAMETER MetricTypes
    Array of metric categories to calculate: 'complexity', 'balance', 'economy', 'all'.

.OUTPUTS
    System.Collections.Hashtable. Metrics including:
    - complexity: System complexity scores
    - balance: Item/recipe balance indicators
    - economy: Economic metrics (values, crafting costs)
    - coverage: Inventory system coverage

.EXAMPLE
    $items = Export-ItemDefinitions -Path "res://items/"
    $metrics = Get-InventoryMetrics -InventoryData $items
    
    $metrics = Get-InventoryMetrics -Path "res://inventory_system.gd" -MetricTypes @('complexity', 'economy')
#>
function Get-InventoryMetrics {
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [Parameter(ParameterSetName = 'Data')]
        [hashtable]$InventoryData,
        
        [Parameter(Mandatory = $true, ParameterSetName = 'Path')]
        [string]$Path,
        
        [Parameter()]
        [ValidateSet('complexity', 'balance', 'economy', 'coverage', 'all')]
        [string[]]$MetricTypes = @('all')
    )
    
    try {
        $sourceFile = 'inline'
        
        # If path provided, extract data first
        if ($PSCmdlet.ParameterSetName -eq 'Path') {
            Write-Verbose "[$script:ParserName] Extracting inventory data from: $Path"
            $sourceFile = $Path
            
            # Extract all inventory data
            $inventorySystem = Export-InventorySystem -Path $Path
            $itemDefinitions = Export-ItemDefinitions -Path $Path
            $craftingRecipes = Export-CraftingRecipes -Path $Path
            $equipmentSlots = Export-EquipmentSlots -Path $Path
            
            $InventoryData = @{
                inventorySystem = $inventorySystem
                itemDefinitions = $itemDefinitions
                craftingRecipes = $craftingRecipes
                equipmentSlots = $equipmentSlots
            }
        }
        elseif ($InventoryData -and $InventoryData.metadata) {
            $sourceFile = $InventoryData.metadata.sourceFile
        }
        
        if (-not $InventoryData) {
            Write-Warning "[$script:ParserName] No inventory data provided"
            return $null
        }
        
        $metrics = @{
            sourceFile = $sourceFile
            metricTypes = $MetricTypes
            timestamp = [DateTime]::UtcNow.ToString("o")
            complexity = @{}
            balance = @{}
            economy = @{}
            coverage = @{}
            overall = @{}
        }
        
        $items = $InventoryData.itemDefinitions.items
        $recipes = $InventoryData.craftingRecipes.recipes
        $slots = $InventoryData.equipmentSlots.slots
        $inventory = $InventoryData.inventorySystem.inventory
        
        # Calculate complexity metrics
        if ('all' -in $MetricTypes -or 'complexity' -in $MetricTypes) {
            $metrics.complexity = @{
                itemCount = $items.Count
                recipeCount = $recipes.Count
                slotCount = $slots.Count
                categoryCount = if ($InventoryData.itemDefinitions.categories) { $InventoryData.itemDefinitions.categories.Count } else { 0 }
                rarityCount = if ($InventoryData.itemDefinitions.rarities) { $InventoryData.itemDefinitions.rarities.Count } else { 0 }
                
                # Inventory complexity
                inventorySlotCount = if ($inventory) { $inventory.slotCount } else { 0 }
                hasGridSystem = if ($inventory) { $inventory.gridSize -ne $null } else { $false }
                
                # Recipe complexity
                avgIngredients = if ($recipes.Count -gt 0) { 
                    [math]::Round(($recipes | ForEach-Object { $_.ingredients.Count } | Measure-Object -Average).Average, 2) 
                } else { 0 }
                maxIngredients = if ($recipes.Count -gt 0) { 
                    ($recipes | ForEach-Object { $_.ingredients.Count } | Measure-Object -Maximum).Maximum 
                } else { 0 }
                
                # Overall complexity score
                complexityScore = 0
            }
            
            # Calculate complexity score
            $complexityScore = 0
            $complexityScore += $items.Count * 0.5
            $complexityScore += $recipes.Count * 2
            $complexityScore += $metrics.complexity.categoryCount
            $complexityScore += $metrics.complexity.rarityCount * 0.5
            $metrics.complexity.complexityScore = [math]::Round($complexityScore, 2)
        }
        
        # Calculate balance metrics
        if ('all' -in $MetricTypes -or 'balance' -in $MetricTypes) {
            if ($items.Count -gt 0) {
                $valueStats = $items | Measure-Object -Property value -Average -Minimum -Maximum
                $weightStats = $items | Where-Object { $_.weight -gt 0 } | Measure-Object -Property weight -Average -Minimum -Maximum
                $stackStats = $items | Measure-Object -Property stackSize -Average -Minimum -Maximum
                
                $metrics.balance = @{
                    valueRange = @{
                        min = $valueStats.Minimum
                        max = $valueStats.Maximum
                        average = [math]::Round($valueStats.Average, 2)
                        variance = if ($items.Count -gt 1) { 
                            [math]::Round(($items | ForEach-Object { [math]::Pow($_.value - $valueStats.Average, 2) } | Measure-Object -Average).Average, 2)
                        } else { 0 }
                    }
                    weightRange = @{
                        min = $weightStats.Minimum
                        max = $weightStats.Maximum
                        average = [math]::Round($weightStats.Average, 2)
                    }
                    stackSizeRange = @{
                        min = $stackStats.Minimum
                        max = $stackStats.Maximum
                        average = [math]::Round($stackStats.Average, 2)
                    }
                    
                    # Category distribution
                    categoryDistribution = @{}
                    foreach ($item in $items) {
                        $cat = $item.category -or 'uncategorized'
                        if (-not $metrics.balance.categoryDistribution.ContainsKey($cat)) {
                            $metrics.balance.categoryDistribution[$cat] = 0
                        }
                        $metrics.balance.categoryDistribution[$cat]++
                    }
                    
                    # Rarity distribution
                    rarityDistribution = @{}
                    foreach ($item in $items) {
                        $rarity = $item.rarity -or 'common'
                        if (-not $metrics.balance.rarityDistribution.ContainsKey($rarity)) {
                            $metrics.balance.rarityDistribution[$rarity] = 0
                        }
                        $metrics.balance.rarityDistribution[$rarity]++
                    }
                }
            }
            else {
                $metrics.balance = @{
                    valueRange = @{}
                    weightRange = @{}
                    categoryDistribution = @{}
                    rarityDistribution = @{}
                }
            }
        }
        
        # Calculate economy metrics
        if ('all' -in $MetricTypes -or 'economy' -in $MetricTypes) {
            $metrics.economy = @{
                totalItemValue = ($items | Measure-Object -Property value -Sum).Sum
                avgItemValue = if ($items.Count -gt 0) { [math]::Round(($items | Measure-Object -Property value -Average).Average, 2) } else { 0 }
                
                # Recipe profitability
                recipeProfitability = @()
                totalCraftingTime = 0
            }
            
            # Calculate recipe profitability if we have both recipes and items
            if ($recipes.Count -gt 0 -and $items.Count -gt 0) {
                $itemValueLookup = @{}
                foreach ($item in $items) {
                    if ($item.itemId) {
                        $itemValueLookup[$item.itemId] = $item.value
                    }
                }
                
                foreach ($recipe in $recipes) {
                    $inputValue = 0
                    foreach ($ing in $recipe.ingredients) {
                        $ingValue = $itemValueLookup[$ing.itemId] -or 0
                        $inputValue += $ingValue * $ing.count
                    }
                    
                    $outputValue = 0
                    foreach ($res in $recipe.results) {
                        $resValue = $itemValueLookup[$res.itemId] -or 0
                        $outputValue += $resValue * $res.count
                    }
                    
                    $profit = $outputValue - $inputValue
                    $metrics.economy.recipeProfitability += @{
                        recipeId = $recipe.id
                        inputValue = $inputValue
                        outputValue = $outputValue
                        profit = $profit
                        profitMargin = if ($inputValue -gt 0) { [math]::Round($profit / $inputValue, 2) } else { 0 }
                    }
                    
                    $totalCraftingTime += $recipe.craftingTime
                }
                
                $metrics.economy.totalCraftingTime = $totalCraftingTime
                $metrics.economy.avgCraftingTime = if ($recipes.Count -gt 0) { [math]::Round($totalCraftingTime / $recipes.Count, 2) } else { 0 }
            }
        }
        
        # Calculate coverage metrics
        if ('all' -in $MetricTypes -or 'coverage' -in $MetricTypes) {
            $metrics.coverage = @{
                hasInventorySystem = $InventoryData.inventorySystem.inventory -ne $null
                hasItemDefinitions = $items.Count -gt 0
                hasCraftingSystem = $recipes.Count -gt 0
                hasEquipmentSystem = $slots.Count -gt 0
                
                # Item property coverage
                propertyCoverage = @{
                    hasIcons = ($items | Where-Object { $_.icon }).Count
                    hasDescriptions = ($items | Where-Object { $_.description }).Count
                    hasWeights = ($items | Where-Object { $_.weight -gt 0 }).Count
                    hasValues = ($items | Where-Object { $_.value -gt 0 }).Count
                    hasCategories = ($items | Where-Object { $_.category -and $_.category -ne 'misc' }).Count
                    hasRarities = ($items | Where-Object { $_.rarity -and $_.rarity -ne 'common' }).Count
                }
                
                # Calculate coverage percentages
                totalItems = [math]::Max($items.Count, 1)
                propertyCoveragePercentages = @{
                    icons = [math]::Round(($metrics.coverage.propertyCoverage.hasIcons / $totalItems) * 100, 2)
                    descriptions = [math]::Round(($metrics.coverage.propertyCoverage.hasDescriptions / $totalItems) * 100, 2)
                    weights = [math]::Round(($metrics.coverage.propertyCoverage.hasWeights / $totalItems) * 100, 2)
                    values = [math]::Round(($metrics.coverage.propertyCoverage.hasValues / $totalItems) * 100, 2)
                    categories = [math]::Round(($metrics.coverage.propertyCoverage.hasCategories / $totalItems) * 100, 2)
                    rarities = [math]::Round(($metrics.coverage.propertyCoverage.hasRarities / $totalItems) * 100, 2)
                }
                
                $metrics.coverage.propertyCoveragePercentages = $propertyCoveragePercentages
                $metrics.coverage.overallCoverage = [math]::Round((
                    $propertyCoveragePercentages.icons + 
                    $propertyCoveragePercentages.descriptions + 
                    $propertyCoveragePercentages.weights + 
                    $propertyCoveragePercentages.values + 
                    $propertyCoveragePercentages.categories + 
                    $propertyCoveragePercentages.rarities
                ) / 6, 2)
            }
        }
        
        # Overall score
        $metrics.overall = @{
            systemCompleteness = 0
            dataQuality = 0
            overallScore = 0
        }
        
        # Calculate completeness (0-100)
        $completeness = 0
        if ($metrics.coverage.hasInventorySystem) { $completeness += 25 }
        if ($metrics.coverage.hasItemDefinitions) { $completeness += 25 }
        if ($metrics.coverage.hasCraftingSystem) { $completeness += 25 }
        if ($metrics.coverage.hasEquipmentSystem) { $completeness += 25 }
        $metrics.overall.systemCompleteness = $completeness
        
        # Calculate data quality (0-100)
        if ($metrics.coverage.overallCoverage) {
            $metrics.overall.dataQuality = $metrics.coverage.overallCoverage
        }
        
        # Overall score
        $metrics.overall.overallScore = [math]::Round(($completeness + $metrics.overall.dataQuality) / 2, 2)
        
        return $metrics
    }
    catch {
        Write-Error "[$script:ParserName] Failed to calculate inventory metrics: $_"
        return @{
            sourceFile = $sourceFile
            error = $_.ToString()
            timestamp = [DateTime]::UtcNow.ToString("o")
        }
    }
}

<#
.SYNOPSIS
    Converts inventory data to a graph representation.

.DESCRIPTION
    Transforms extracted inventory data (items, recipes, equipment) into a graph structure
    suitable for visualization and analysis. Creates nodes for items, recipes, and slots,
    with edges representing relationships (ingredients, results, equipment compatibility).

.PARAMETER InventoryData
    Hashtable containing extracted inventory data from Export-ItemDefinitions,
    Export-CraftingRecipes, and Export-EquipmentSlots.

.PARAMETER IncludeRecipeGraph
    Include crafting recipe relationships in the graph.

.PARAMETER IncludeEquipmentGraph
    Include equipment slot relationships in the graph.

.PARAMETER OutputPath
    Optional path to write the exported JSON graph file.

.OUTPUTS
    System.Collections.Hashtable. Graph representation containing:
    - nodes: Array of graph nodes (items, recipes, slots)
    - edges: Array of graph edges (relationships)
    - nodeTypes: Count by node type
    - edgeTypes: Count by edge type
    - metadata: Provenance metadata

.EXAMPLE
    $items = Export-ItemDefinitions -Path "res://items/"
    $recipes = Export-CraftingRecipes -Path "res://crafting/"
    $graph = Convert-ToInventoryGraph -InventoryData @{ items = $items; recipes = $recipes }
    
    Convert-ToInventoryGraph -InventoryData $data -OutputPath "./exports/inventory_graph.json"
#>
function Convert-ToInventoryGraph {
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [Parameter(Mandatory = $true)]
        [hashtable]$InventoryData,
        
        [Parameter()]
        [switch]$IncludeRecipeGraph = $true,
        
        [Parameter()]
        [switch]$IncludeEquipmentGraph = $true,
        
        [Parameter()]
        [string]$OutputPath
    )
    
    try {
        $nodes = @()
        $edges = @()
        $nodeIdMap = @{}
        
        # Add item nodes
        if ($InventoryData.items -and $InventoryData.items.items) {
            foreach ($item in $InventoryData.items.items) {
                $nodeId = "item_$($item.itemId -or $item.id)"
                $nodeIdMap[$item.itemId -or $item.id] = $nodeId
                
                $nodes += @{
                    id = $nodeId
                    type = 'item'
                    label = $item.itemName -or $item.name -or $item.itemId
                    properties = @{
                        itemId = $item.itemId -or $item.id
                        category = $item.category
                        rarity = $item.rarity
                        value = $item.value
                        weight = $item.weight
                        stackSize = $item.stackSize
                    }
                }
            }
        }
        
        # Add recipe nodes and edges
        if ($IncludeRecipeGraph -and $InventoryData.recipes -and $InventoryData.recipes.recipes) {
            foreach ($recipe in $InventoryData.recipes.recipes) {
                $recipeNodeId = "recipe_$($recipe.id)"
                
                $nodes += @{
                    id = $recipeNodeId
                    type = 'recipe'
                    label = $recipe.name -or "Recipe $($recipe.id)"
                    properties = @{
                        craftingTime = $recipe.craftingTime
                        station = $recipe.station
                        ingredientCount = $recipe.ingredients.Count
                        resultCount = $recipe.results.Count
                    }
                }
                
                # Add ingredient edges (item -> recipe)
                foreach ($ing in $recipe.ingredients) {
                    $itemNodeId = $nodeIdMap[$ing.itemId]
                    if ($itemNodeId) {
                        $edges += @{
                            source = $itemNodeId
                            target = $recipeNodeId
                            type = 'ingredient'
                            weight = $ing.count
                            label = "$($ing.count)x"
                        }
                    }
                }
                
                # Add result edges (recipe -> item)
                foreach ($res in $recipe.results) {
                    $itemNodeId = $nodeIdMap[$res.itemId]
                    if ($itemNodeId) {
                        $edges += @{
                            source = $recipeNodeId
                            target = $itemNodeId
                            type = 'result'
                            weight = $res.count
                            label = "$($res.count)x"
                        }
                    }
                }
            }
        }
        
        # Add equipment slot nodes
        if ($IncludeEquipmentGraph -and $InventoryData.slots -and $InventoryData.slots.slots) {
            foreach ($slot in $InventoryData.slots.slots) {
                $slotNodeId = "slot_$($slot.id)"
                
                $nodes += @{
                    id = $slotNodeId
                    type = 'slot'
                    label = $slot.slotName -or $slot.slotType -or $slot.className
                    properties = @{
                        slotType = $slot.slotType
                        allowedCategories = $slot.allowedCategories
                    }
                }
                
                # Add edges to compatible items
                if ($slot.allowedCategories) {
                    foreach ($item in $InventoryData.items.items) {
                        if ($item.category -in $slot.allowedCategories) {
                            $itemNodeId = $nodeIdMap[$item.itemId -or $item.id]
                            if ($itemNodeId) {
                                $edges += @{
                                    source = $itemNodeId
                                    target = $slotNodeId
                                    type = 'equipable'
                                    weight = 1
                                }
                            }
                        }
                    }
                }
            }
        }
        
        # Calculate node and edge type counts
        $nodeTypes = @{}
        foreach ($node in $nodes) {
            if (-not $nodeTypes.ContainsKey($node.type)) {
                $nodeTypes[$node.type] = 0
            }
            $nodeTypes[$node.type]++
        }
        
        $edgeTypes = @{}
        foreach ($edge in $edges) {
            if (-not $edgeTypes.ContainsKey($edge.type)) {
                $edgeTypes[$edge.type] = 0
            }
            $edgeTypes[$edge.type]++
        }
        
        $graph = @{
            nodes = $nodes
            edges = $edges
            nodeTypes = $nodeTypes
            edgeTypes = $edgeTypes
            metadata = @{
                nodeCount = $nodes.Count
                edgeCount = $edges.Count
                timestamp = [DateTime]::UtcNow.ToString("o")
                parserName = $script:ParserName
                parserVersion = $script:ParserVersion
            }
        }
        
        # Write to file if output path specified
        if ($OutputPath) {
            $graph | ConvertTo-Json -Depth 10 | Out-File -FilePath $OutputPath -Encoding UTF8
            Write-Verbose "[$script:ParserName] Inventory graph exported to: $OutputPath"
        }
        
        return $graph
    }
    catch {
        Write-Error "[$script:ParserName] Failed to convert to inventory graph: $_"
        return @{
            nodes = @()
            edges = @()
            error = $_.ToString()
            metadata = @{
                timestamp = [DateTime]::UtcNow.ToString("o")
                parserName = $script:ParserName
                parserVersion = $script:ParserVersion
            }
        }
    }
}

# ============================================================================
# Legacy/Compatibility Functions
# ============================================================================

<#
.SYNOPSIS
    Main entry point for parsing inventory from Godot files.

.DESCRIPTION
    Parses a Godot file and returns complete structured extraction
    of inventory system patterns including items, recipes, equipment, and configurations.

.PARAMETER Path
    Path to the Godot file.

.PARAMETER Content
    Godot content string (alternative to Path).

.OUTPUTS
    System.Collections.Hashtable. Complete inventory extraction.

.EXAMPLE
    $result = Invoke-InventoryExtract -Path "res://inventory/player_inventory.gd"
#>
function Invoke-InventoryExtract {
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [Parameter(Mandatory = $true, ParameterSetName = 'Path')]
        [string]$Path,
        
        [Parameter(Mandatory = $true, ParameterSetName = 'Content')]
        [string]$Content
    )
    
    try {
        # Load content
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
            $Content = Get-Content -LiteralPath $Path -Raw -Encoding UTF8
        }
        
        if ([string]::IsNullOrWhiteSpace($Content)) {
            return @{
                filePath = $sourceFile
                success = $false
                error = "Content is empty"
            }
        }
        
        # Get file metadata
        $fileMetadata = @{}
        if ($PSCmdlet.ParameterSetName -eq 'Path') {
            $fileMetadata = Get-FileMetadata -Path $Path
        }
        
        # Extract all inventory patterns using the canonical functions
        $inventorySystem = Export-InventorySystem -Content $Content
        $itemDefinitions = Export-ItemDefinitions -Content $Content
        $craftingRecipes = Export-CraftingRecipes -Content $Content
        $equipmentSlots = Export-EquipmentSlots -Content $Content
        
        # Determine primary inventory pattern
        $primaryPattern = 'none'
        if ($itemDefinitions.items.Count -gt 0) {
            $primaryPattern = 'item_definitions'
        }
        elseif ($inventorySystem.inventory -and $inventorySystem.inventory.type -ne 'unknown') {
            $primaryPattern = 'inventory_system'
        }
        elseif ($craftingRecipes.recipes.Count -gt 0) {
            $primaryPattern = 'crafting_system'
        }
        elseif ($equipmentSlots.slots.Count -gt 0) {
            $primaryPattern = 'equipment_system'
        }
        
        $result = @{
            filePath = $sourceFile
            fileType = if ($fileMetadata.extension) { $fileMetadata.extension.TrimStart('.') } else { 'unknown' }
            fileMetadata = $fileMetadata
            primaryPattern = $primaryPattern
            inventorySystem = $inventorySystem
            itemDefinitions = $itemDefinitions
            craftingRecipes = $craftingRecipes
            equipmentSlots = $equipmentSlots
            statistics = @{
                itemCount = $itemDefinitions.statistics.itemCount
                recipeCount = $craftingRecipes.statistics.recipeCount
                slotCount = $equipmentSlots.statistics.slotCount
                categoryCount = $itemDefinitions.statistics.categoryCount
                inventorySlotCount = $inventorySystem.statistics.slotCount
            }
            metadata = New-ProvenanceMetadata -SourceFile $sourceFile -Success $true
        }
        
        Write-Verbose "[$script:ParserName] Extraction complete: primary pattern is $primaryPattern"
        
        return $result
    }
    catch {
        Write-Error "[$script:ParserName] Failed to extract inventory: $_"
        return @{
            filePath = $sourceFile
            success = $false
            error = $_.ToString()
            metadata = New-ProvenanceMetadata -SourceFile $sourceFile -Success $false -Errors @($_.ToString())
        }
    }
}

<#
.SYNOPSIS
    Extracts hotbar configuration from Godot files.
    
    DEPRECATED: Use Export-InventorySystem instead.

.DESCRIPTION
    Legacy function for compatibility. Delegates to Export-InventorySystem.
#>
function Get-HotbarConfiguration {
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [Parameter(Mandatory = $true, ParameterSetName = 'Path')]
        [string]$Path,
        
        [Parameter(Mandatory = $true, ParameterSetName = 'Content')]
        [string]$Content
    )
    
    $result = if ($PSCmdlet.ParameterSetName -eq 'Path') {
        Export-InventorySystem -Path $Path
    }
    else {
        Export-InventorySystem -Content $Content
    }
    
    return @{
        hotbarSize = $result.inventory.slotCount
        slots = $result.slots
        signals = $result.signals
    }
}

<#
.SYNOPSIS
    Exports a complete inventory system package.

.DESCRIPTION
    Extracts and exports the complete inventory system including items, recipes,
    equipment slots, and inventory configuration to a single structured output.

.PARAMETER ProjectPath
    Path to the Godot project root or inventory directory.

.PARAMETER OutputPath
    Optional path to write the exported JSON file.

.PARAMETER IncludeGraph
    Include graph representation in the export.

.OUTPUTS
    System.Collections.Hashtable. Complete inventory system export.

.EXAMPLE
    $package = Export-InventoryPackage -ProjectPath "res://inventory/"
    
    Export-InventoryPackage -ProjectPath "./my_project" -OutputPath "./exports/inventory.json" -IncludeGraph
#>
function Export-InventoryPackage {
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [Parameter(Mandatory = $true)]
        [string]$ProjectPath,
        
        [Parameter()]
        [string]$OutputPath,
        
        [Parameter()]
        [switch]$IncludeGraph
    )
    
    try {
        Write-Verbose "[$script:ParserName] Exporting inventory package from: $ProjectPath"
        
        if (-not (Test-Path -LiteralPath $ProjectPath)) {
            return @{
                success = $false
                error = "Project path not found: $ProjectPath"
                metadata = New-ProvenanceMetadata -SourceFile $ProjectPath -Success $false -Errors @("Path not found")
            }
        }
        
        # Determine if this is a file or directory
        $pathItem = Get-Item -LiteralPath $ProjectPath
        $isDirectory = $pathItem.PSIsContainer
        
        # Extract all data
        $itemData = Export-ItemDefinitions -Path $ProjectPath
        $recipeData = Export-CraftingRecipes -Path $ProjectPath
        $equipmentData = Export-EquipmentSlots -Path $ProjectPath
        
        $inventoryData = $null
        if (-not $isDirectory) {
            $inventoryData = Export-InventorySystem -Path $ProjectPath
        }
        
        # Calculate metrics
        $metrics = Get-InventoryMetrics -InventoryData @{
            itemDefinitions = $itemData
            craftingRecipes = $recipeData
            equipmentSlots = $equipmentData
            inventorySystem = $inventoryData
        }
        
        # Build package
        $package = @{
            packageId = [System.Guid]::NewGuid().ToString()
            exportVersion = $script:ParserVersion
            exportTimestamp = [DateTime]::UtcNow.ToString("o")
            sourcePath = $ProjectPath
            items = $itemData.items
            categories = $itemData.categories
            rarities = $itemData.rarities
            recipes = $recipeData.recipes
            stations = $recipeData.stations
            equipmentSlots = $equipmentData.slots
            slotTypes = $equipmentData.slotTypes
            inventory = if ($inventoryData) { $inventoryData.inventory } else { $null }
            metrics = $metrics
            statistics = @{
                totalItems = $itemData.statistics.itemCount
                totalRecipes = $recipeData.statistics.recipeCount
                totalEquipmentSlots = $equipmentData.statistics.slotCount
                totalCategories = $itemData.statistics.categoryCount
                overallCoverage = $metrics.overall.overallScore
            }
            metadata = New-ProvenanceMetadata -SourceFile $ProjectPath -Success $true
        }
        
        # Include graph if requested
        if ($IncludeGraph) {
            $package.graph = Convert-ToInventoryGraph -InventoryData @{
                items = $itemData
                recipes = $recipeData
                slots = $equipmentData
            } -IncludeRecipeGraph -IncludeEquipmentGraph
        }
        
        # Write to file if output path specified
        if ($OutputPath) {
            $package | ConvertTo-Json -Depth 10 | Out-File -FilePath $OutputPath -Encoding UTF8
            Write-Verbose "[$script:ParserName] Inventory package exported to: $OutputPath"
        }
        
        return $package
    }
    catch {
        Write-Error "[$script:ParserName] Failed to export inventory package: $_"
        return @{
            success = $false
            error = $_.ToString()
            metadata = New-ProvenanceMetadata -SourceFile $ProjectPath -Success $false -Errors @($_.ToString())
        }
    }
}

# Export module functions
Export-ModuleMember -Function @(
    'Export-InventorySystem'
    'Export-ItemDefinitions'
    'Export-CraftingRecipes'
    'Export-EquipmentSlots'
    'Get-InventoryMetrics'
    'Convert-ToInventoryGraph'
    'Invoke-InventoryExtract'
    'Export-InventoryPackage'
    'Get-HotbarConfiguration'
)
