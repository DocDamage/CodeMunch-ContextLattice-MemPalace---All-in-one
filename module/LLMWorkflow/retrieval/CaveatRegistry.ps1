#requires -Version 5.1
<#
.SYNOPSIS
    Caveat Registry for LLM Workflow platform.

.DESCRIPTION
    Maintains known caveats and falsehoods to avoid recurring misconceptions in answers.
    Implements Section 15.5 of the canonical architecture for caveat management.

    Key capabilities:
    - Singleton registry pattern with persistent storage
    - Thread-safe operations with file locking
    - Efficient trigger-based caveat matching
    - Predefined caveats for common version boundaries and misconceptions
    - Export/Import for sharing caveat knowledge

.NOTES
    File Name      : CaveatRegistry.ps1
    Author         : LLM Workflow Team
    Prerequisite   : PowerShell 5.1+
    Copyright      : (c) 2026 LLM Workflow Project
    License        : MIT

.EXAMPLE
    # Get or initialize the caveat registry
    $registry = Get-CaveatRegistry -ProjectRoot "C:\MyProject"

.EXAMPLE
    # Register a new caveat
    Register-Caveat -CaveatId "gdscript-typed-arrays" `
        -Category "version-boundary" `
        -Subject "Godot 4.0 Typed Arrays" `
        -Message "Note: Typed arrays (Array[int]) are Godot 4.0+. In Godot 3.x, use Array without type hints." `
        -Triggers @{ keywords = @("typed array", "Array["); packs = @("godot-engine") }

.EXAMPLE
    # Find applicable caveats for a query
    $caveats = Find-ApplicableCaveats -Query "How do I use onready in Godot?" -Evidence @()

.EXAMPLE
    # Attach caveats to an answer
    $annotatedAnswer = Add-AnswerCaveats -Answer $myAnswer -Caveats $caveats
#>

Set-StrictMode -Version Latest

# Script-level variables for singleton pattern
$script:CaveatRegistryInstance = $null
$script:CaveatRegistryPath = $null
$script:CaveatRegistryLock = [System.Object]::new()
$script:CaveatSchemaVersion = 1

# Valid caveat categories per Section 15.5
$script:ValidCategories = @(
    'version-boundary',      # Godot 3 vs 4, Blender 3.x vs 4.x, etc.
    'common-misconception',  # Frequently misunderstood concepts
    'compatibility',         # Known compatibility issues
    'experimental',          # Unstable or beta features
    'deprecated',            # Outdated patterns/APIs
    'translation-only'       # Caveats about translated content
)

# Valid severity levels
$script:ValidSeverities = @('info', 'warning', 'critical')

# Predefined caveats loaded on initialization
$script:PredefinedCaveats = @{
    # Godot Engine - Version Boundaries
    'godot-3-vs-4-onready' = @{
        caveatId = 'godot-3-vs-4-onready'
        category = 'version-boundary'
        subject = '@onready vs onready'
        message = 'Note: `@onready` is Godot 4 syntax. In Godot 3, use `onready` (no @).'
        triggers = @{
            keywords = @('@onready', 'onready', 'export var', '@export')
            packs = @('godot-engine')
            patterns = @('@onready\s+\w+', 'onready\s+\w+')
        }
        severity = 'warning'
        metadata = @{
            appliesTo = @('gdscript')
            godot3Equivalent = 'onready var'
            godot4Equivalent = '@onready var'
        }
    }
    'godot-4-typed-arrays' = @{
        caveatId = 'godot-4-typed-arrays'
        category = 'version-boundary'
        subject = 'Typed Arrays (Godot 4.0+)'
        message = 'Note: Typed arrays (Array[int], Array[String]) are Godot 4.0+. In Godot 3.x, use untyped Array.'
        triggers = @{
            keywords = @('typed array', 'Array[', 'Array<int>', 'Array[String]')
            packs = @('godot-engine')
            patterns = @('Array\[\w+\]')
        }
        severity = 'warning'
        metadata = @{
            appliesTo = @('gdscript')
            sinceVersion = '4.0'
        }
    }
    'godot-signal-syntax-change' = @{
        caveatId = 'godot-signal-syntax-change'
        category = 'version-boundary'
        subject = 'Signal Syntax Changes'
        message = 'Note: Godot 4 uses `signal_name.emit()` instead of `emit_signal("signal_name")`. Connect syntax also changed.'
        triggers = @{
            keywords = @('emit_signal', 'connect(', 'signal', 'emit()')
            packs = @('godot-engine')
            patterns = @('emit_signal\s*\(', '\.emit\s*\(')
        }
        severity = 'info'
        metadata = @{
            appliesTo = @('gdscript')
            godot3Syntax = 'emit_signal("name")'
            godot4Syntax = 'name.emit()'
        }
    }
    'godot-node-path-export' = @{
        caveatId = 'godot-node-path-export'
        category = 'version-boundary'
        subject = '@export NodePath vs @export Node'
        message = 'Note: In Godot 4, use `@export var node: Node` instead of `@export var path: NodePath`. NodePath is still valid but less common.'
        triggers = @{
            keywords = @('@export', 'NodePath', 'export(NodePath)')
            packs = @('godot-engine')
            patterns = @('@export\s+.*NodePath')
        }
        severity = 'info'
        metadata = @{
            appliesTo = @('gdscript')
            sinceVersion = '4.0'
        }
    }
    
    # RPG Maker MZ
    'rpgmaker-plugin-order' = @{
        caveatId = 'rpgmaker-plugin-order'
        category = 'common-misconception'
        subject = 'Plugin Load Order'
        message = 'Warning: Plugin load order matters in RPG Maker MZ. Some plugins must be placed above/below others. Check plugin documentation for ordering requirements.'
        triggers = @{
            keywords = @('plugin order', 'load order', 'plugin conflict', 'plugins not working')
            packs = @('rpgmaker-mz', 'rpgmaker-mv')
        }
        severity = 'warning'
        metadata = @{
            appliesTo = @('javascript', 'rmmz', 'rmmv')
            commonIssue = $true
        }
    }
    'rpgmaker-alias-pattern' = @{
        caveatId = 'rpgmaker-alias-pattern'
        category = 'common-misconception'
        subject = 'Plugin Alias Pattern'
        message = 'Note: When extending RPG Maker classes, use `.alias` methods properly to preserve compatibility with other plugins. Always call the aliased method unless intentionally overriding.'
        triggers = @{
            keywords = @('alias', 'Window_Base.prototype', 'Scene_Base.prototype')
            packs = @('rpgmaker-mz', 'rpgmaker-mv')
            patterns = @('\.prototype\.\w+\s*=\s*function')
        }
        severity = 'warning'
        metadata = @{
            appliesTo = @('javascript', 'rmmz', 'rmmv')
            bestPractice = $true
        }
    }
    'rpgmaker-eval-security' = @{
        caveatId = 'rpgmaker-eval-security'
        category = 'common-misconception'
        subject = 'eval() and Game_Variables Security'
        message = 'Warning: Using eval() with game variables can be a security risk. Validate inputs and avoid executing user-provided content directly.'
        triggers = @{
            keywords = @('eval(', '$gameVariables', 'Game_Variables', 'execute code')
            packs = @('rpgmaker-mz', 'rpgmaker-mv')
        }
        severity = 'critical'
        metadata = @{
            appliesTo = @('javascript', 'rmmz', 'rmmv')
            security = $true
        }
    }
    
    # Blender
    'blender-python-api-change' = @{
        caveatId = 'blender-python-api-change'
        category = 'version-boundary'
        subject = 'Blender Python API Changes (2.7x to 2.8+)'
        message = 'Note: Blender 2.8+ has significant API changes from 2.7x. Common changes: `bpy.context.scene.objects` iteration, `mesh.from_pydata()`, and collection-based scene organization.'
        triggers = @{
            keywords = @('bpy.context', 'scene.objects', 'from_pydata', 'Blender 2.7', 'Blender 2.8')
            packs = @('blender-engine')
            patterns = @('scene\.objects\.\w+', 'from_pydata')
        }
        severity = 'warning'
        metadata = @{
            appliesTo = @('python', 'blender')
            breakingChange = $true
        }
    }
    'blender-geometry-nodes-fields' = @{
        caveatId = 'blender-geometry-nodes-fields'
        category = 'version-boundary'
        subject = 'Geometry Nodes Fields (Blender 3.0+)'
        message = 'Note: Geometry Nodes uses a "fields" system since Blender 3.0. Older tutorials using "Attribute Spreadsheet" workflows may not apply.'
        triggers = @{
            keywords = @('geometry nodes', 'fields', 'attribute', 'node group')
            packs = @('blender-engine')
        }
        severity = 'info'
        metadata = @{
            appliesTo = @('blender')
            sinceVersion = '3.0'
        }
    }
    
    # Compatibility
    'gdscript-python-confusion' = @{
        caveatId = 'gdscript-python-confusion'
        category = 'common-misconception'
        subject = 'GDScript is NOT Python'
        message = 'Note: GDScript syntax resembles Python but is a distinct language with different semantics. Godot 4 GDScript has significant differences from Python.'
        triggers = @{
            keywords = @('python', 'gdscript', 'GDScript python')
            packs = @('godot-engine')
        }
        severity = 'info'
        metadata = @{
            appliesTo = @('gdscript')
            clarification = $true
        }
    }
    'export-var-godot-4' = @{
        caveatId = 'export-var-godot-4'
        category = 'version-boundary'
        subject = 'export var vs @export'
        message = 'Note: Godot 4 uses `@export` annotation. `export var` syntax from Godot 3.x is not valid in Godot 4.'
        triggers = @{
            keywords = @('export var', '@export', 'export(int)', 'export var')
            packs = @('godot-engine')
            patterns = @('export\s*\(\s*\w+\s*\)', '^export\s+var')
            falsehoodPatterns = @('\b(use|using)\s+export\s+var\s+in\s+Godot\s*4', '\bexport\s+var\s+is\s+(valid|correct|supported)\s+in\s+Godot\s*4')
        }
        severity = 'warning'
        metadata = @{
            appliesTo = @('gdscript')
            godot3Syntax = 'export var'
            godot4Syntax = '@export var'
        }
    }
    
    # Experimental/Unstable
    'godot-csharp-limitations' = @{
        caveatId = 'godot-csharp-limitations'
        category = 'experimental'
        subject = 'C# in Godot - Platform Limitations'
        message = 'Note: C# in Godot has limitations: mobile export requires AOT compilation, certain platforms (Web without threading) may not support C#.'
        triggers = @{
            keywords = @('C#', 'csharp', 'mono', 'Godot C#', 'export android')
            packs = @('godot-engine')
        }
        severity = 'info'
        metadata = @{
            appliesTo = @('csharp', 'godot')
            platforms = @('mobile', 'web')
        }
    }
    
    # Deprecated
    'godot-kinematic-body' = @{
        caveatId = 'godot-kinematic-body'
        category = 'deprecated'
        subject = 'KinematicBody replaced by CharacterBody3D/CharacterBody2D'
        message = 'Note: KinematicBody was renamed to CharacterBody3D/CharacterBody2D in Godot 4. The API has changed significantly.'
        triggers = @{
            keywords = @('KinematicBody', 'KinematicBody2D', 'KinematicBody3D', 'move_and_slide')
            packs = @('godot-engine')
            patterns = @('KinematicBody\d*[Dd]?')
            falsehoodPatterns = @('\bKinematicBody\s+is\s+(the\s+)?(current|new|latest)\s+(class|node)\s+in\s+Godot\s*4')
        }
        severity = 'warning'
        metadata = @{
            appliesTo = @('gdscript', 'csharp')
            godot3Class = 'KinematicBody'
            godot4Class = 'CharacterBody3D'
        }
    }
    
    # Translation-only caveats
    'translation-authority-level' = @{
        caveatId = 'translation-authority-level'
        category = 'translation-only'
        subject = 'Translation Authority Level'
        message = 'Note: This answer references translated documentation which has lower authority than official English sources. Verify critical information against official documentation.'
        triggers = @{
            keywords = @('translation', 'localized docs', 'non-english')
            packs = @()
        }
        severity = 'info'
        metadata = @{
            authorityLevel = 'low'
            appliesTo = @('documentation')
        }
    }
}

<#
.SYNOPSIS
    Converts a PSCustomObject to a Hashtable recursively.

.DESCRIPTION
    Helper function to convert PSCustomObject (from ConvertFrom-Json in PowerShell 5.1)
    to a Hashtable for PowerShell 5.1 compatibility.

.PARAMETER InputObject
    The object to convert.

.OUTPUTS
    System.Collections.Hashtable
#>
function ConvertTo-Hashtable {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $false)]
        [AllowNull()]
        [object]$InputObject
    )

    if ($null -eq $InputObject) {
        return $null
    }

    # Handle hashtables (already converted)
    if ($InputObject -is [System.Collections.Hashtable]) {
        $newHash = @{}
        foreach ($key in $InputObject.Keys) {
            $newHash[$key] = ConvertTo-Hashtable -InputObject $InputObject[$key]
        }
        return $newHash
    }

    # Handle arrays/collections
    if ($InputObject -is [System.Collections.IEnumerable] -and 
        $InputObject -isnot [string]) {
        $array = @()
        foreach ($item in $InputObject) {
            $array += (ConvertTo-Hashtable -InputObject $item)
        }
        return $array
    }

    # Handle PSCustomObject
    if ($InputObject -is [PSCustomObject]) {
        $hash = @{}
        foreach ($property in $InputObject.PSObject.Properties) {
            $hash[$property.Name] = ConvertTo-Hashtable -InputObject $property.Value
        }
        return $hash
    }

    # Handle OrderedDictionary
    if ($InputObject -is [System.Collections.Specialized.OrderedDictionary]) {
        $hash = @{}
        foreach ($key in $InputObject.Keys) {
            $hash[$key] = ConvertTo-Hashtable -InputObject $InputObject[$key]
        }
        return $hash
    }

    # Return primitive types as-is
    return $InputObject
}

<#
.SYNOPSIS
    Gets the default path for the caveat registry state file.

.DESCRIPTION
    Returns the canonical path for the caveat registry JSON file.

.PARAMETER ProjectRoot
    The project root directory. Defaults to current directory.

.OUTPUTS
    System.String. The full path to the caveat registry file.
#>
function Get-CaveatRegistryPath {
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [string]$ProjectRoot = "."
    )

    $resolvedRoot = Resolve-Path -Path $ProjectRoot -ErrorAction SilentlyContinue
    if (-not $resolvedRoot) {
        $resolvedRoot = $ProjectRoot
    }

    $stateDir = Join-Path $resolvedRoot ".llm-workflow\state"
    
    if (-not (Test-Path -LiteralPath $stateDir)) {
        try {
            New-Item -ItemType Directory -Path $stateDir -Force | Out-Null
        }
        catch {
            throw "Failed to create state directory: $stateDir. Error: $_"
        }
    }

    return Join-Path $stateDir "caveat-registry.json"
}

<#
.SYNOPSIS
    Gets the caveat registry (singleton pattern).

.DESCRIPTION
    Returns the caveat registry instance, creating it if necessary.
    Loads predefined caveats on first initialization. Thread-safe.

.PARAMETER ProjectRoot
    The project root directory. Used to determine state file location.

.PARAMETER Force
    Force reload from disk, bypassing cached instance.

.OUTPUTS
    System.Collections.Hashtable. The caveat registry object.

.EXAMPLE
    $registry = Get-CaveatRegistry -ProjectRoot "C:\MyProject"

.EXAMPLE
    # Force reload
    $registry = Get-CaveatRegistry -Force
#>
function Get-CaveatRegistry {
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [string]$ProjectRoot = ".",
        
        [switch]$Force
    )

    # Check if we have a cached instance
    if (-not $Force -and $script:CaveatRegistryInstance -ne $null) {
        return $script:CaveatRegistryInstance
    }

    # Thread-safe initialization
    [System.Threading.Monitor]::Enter($script:CaveatRegistryLock)
    try {
        # Double-check after acquiring lock
        if (-not $Force -and $script:CaveatRegistryInstance -ne $null) {
            return $script:CaveatRegistryInstance
        }

        $registryPath = Get-CaveatRegistryPath -ProjectRoot $ProjectRoot
        $script:CaveatRegistryPath = $registryPath

        # Try to load existing registry
        if (Test-Path -LiteralPath $registryPath) {
            try {
                $json = [System.IO.File]::ReadAllText($registryPath, [System.Text.Encoding]::UTF8)
                if (-not [string]::IsNullOrWhiteSpace($json)) {
                    $parsed = $json | ConvertFrom-Json; $existing = ConvertTo-Hashtable -InputObject $parsed
                    if ($existing -ne $null -and $existing.ContainsKey('caveats')) {
                        $script:CaveatRegistryInstance = $existing
                        Write-Verbose "[CaveatRegistry] Loaded registry from $registryPath ($($existing.caveats.Count) caveats)"
                        return $script:CaveatRegistryInstance
                    }
                }
            }
            catch {
                Write-Warning "[CaveatRegistry] Failed to load existing registry, creating new: $_"
            }
        }

        # Create new registry with predefined caveats
        $clonedCaveats = $script:PredefinedCaveats.Clone()
        
        # Ensure all caveats have triggerCount initialized
        foreach ($caveatId in @($clonedCaveats.Keys)) {
            if (-not $clonedCaveats[$caveatId].ContainsKey('triggerCount')) {
                $clonedCaveats[$caveatId]['triggerCount'] = 0
            }
        }
        
        $script:CaveatRegistryInstance = @{
            schemaVersion = $script:CaveatSchemaVersion
            createdAt = [DateTime]::UtcNow.ToString("yyyy-MM-ddTHH:mm:ss.fffZ")
            updatedAt = [DateTime]::UtcNow.ToString("yyyy-MM-ddTHH:mm:ss.fffZ")
            caveats = $clonedCaveats
            usageStats = @{
                totalTriggers = 0
                lastTriggerAt = $null
            }
        }

        # Save initial registry
        Save-CaveatRegistryInternal

        Write-Verbose "[CaveatRegistry] Created new registry with $($script:PredefinedCaveats.Count) predefined caveats"
        return $script:CaveatRegistryInstance
    }
    finally {
        [System.Threading.Monitor]::Exit($script:CaveatRegistryLock)
    }
}

<#
.SYNOPSIS
    Internal function to save the caveat registry to disk.

.DESCRIPTION
    Saves the current caveat registry state atomically.
    Uses temp-file + rename pattern for thread safety.
#>
function Save-CaveatRegistryInternal {
    [CmdletBinding()]
    param()

    if ($null -eq $script:CaveatRegistryInstance) {
        return
    }

    if ([string]::IsNullOrEmpty($script:CaveatRegistryPath)) {
        $script:CaveatRegistryPath = Get-CaveatRegistryPath
    }

    # Update timestamp
    $script:CaveatRegistryInstance.updatedAt = [DateTime]::UtcNow.ToString("yyyy-MM-ddTHH:mm:ss.fffZ")

    # Ensure directory exists
    $dir = Split-Path -Parent $script:CaveatRegistryPath
    if (-not (Test-Path -LiteralPath $dir)) {
        New-Item -ItemType Directory -Path $dir -Force | Out-Null
    }

    # Atomic write using temp file
    $tempPath = "$script:CaveatRegistryPath.tmp.$PID.$([Guid]::NewGuid().ToString('N'))"
    try {
        $json = $script:CaveatRegistryInstance | ConvertTo-Json -Depth 20
        [System.IO.File]::WriteAllText($tempPath, $json, [System.Text.Encoding]::UTF8)
        
        # Atomic rename
        if (Test-Path -LiteralPath $script:CaveatRegistryPath) {
            Remove-Item -LiteralPath $script:CaveatRegistryPath -Force
        }
        [System.IO.File]::Move($tempPath, $script:CaveatRegistryPath)
        
        Write-Verbose "[CaveatRegistry] Saved registry to $script:CaveatRegistryPath"
    }
    catch {
        # Clean up temp file on failure
        if (Test-Path -LiteralPath $tempPath) {
            Remove-Item -LiteralPath $tempPath -Force -ErrorAction SilentlyContinue
        }
        throw "Failed to save caveat registry: $_"
    }
}

<#
.SYNOPSIS
    Registers a new caveat in the registry.

.DESCRIPTION
    Adds a new caveat to the registry with validation. Thread-safe.

.PARAMETER CaveatId
    Unique identifier for the caveat.

.PARAMETER Category
    Category of caveat: 'version-boundary', 'common-misconception', 
    'compatibility', 'experimental', 'deprecated', or 'translation-only'.

.PARAMETER Subject
    Topic or entity this caveat applies to.

.PARAMETER Message
    The caveat message to display.

.PARAMETER Triggers
    Hashtable with keywords, packs, and patterns that trigger this caveat.
    Example: @{ keywords = @('onready'); packs = @('godot-engine'); patterns = @() }

.PARAMETER Severity
    Severity level: 'info', 'warning', or 'critical'. Default is 'warning'.

.PARAMETER Metadata
    Additional metadata for the caveat.

.PARAMETER ProjectRoot
    The project root directory.

.OUTPUTS
    System.Collections.Hashtable. The registered caveat.

.EXAMPLE
    Register-Caveat -CaveatId "my-caveat" -Category "common-misconception" `
        -Subject "My Topic" -Message "Important note about this topic." `
        -Triggers @{ keywords = @('topic', 'keyword'); packs = @('my-pack') }
#>
function Register-Caveat {
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [Parameter(Mandatory = $true)]
        [string]$CaveatId,

        [Parameter(Mandatory = $true)]
        [ValidateSet('version-boundary', 'common-misconception', 'compatibility', 
                     'experimental', 'deprecated', 'translation-only')]
        [string]$Category,

        [Parameter(Mandatory = $true)]
        [string]$Subject,

        [Parameter(Mandatory = $true)]
        [string]$Message,

        [Parameter(Mandatory = $true)]
        [hashtable]$Triggers,

        [Parameter()]
        [ValidateSet('info', 'warning', 'critical')]
        [string]$Severity = 'warning',

        [Parameter()]
        [hashtable]$Metadata = @{},

        [Parameter()]
        [string]$ProjectRoot = "."
    )

    # Validate caveat ID format
    if ($CaveatId -notmatch '^[a-z0-9-]+$') {
        throw "Invalid caveat ID '$CaveatId'. Must contain only lowercase letters, numbers, and hyphens."
    }

    # Validate triggers structure
    if (-not $Triggers.ContainsKey('keywords') -and -not $Triggers.ContainsKey('patterns')) {
        Write-Warning "[CaveatRegistry] Caveat '$CaveatId' has no keywords or patterns. It will never trigger."
    }

    # Get or initialize registry
    $registry = Get-CaveatRegistry -ProjectRoot $ProjectRoot

    [System.Threading.Monitor]::Enter($script:CaveatRegistryLock)
    try {
        # Check for duplicate
        if ($registry.caveats.ContainsKey($CaveatId)) {
            Write-Warning "[CaveatRegistry] Caveat '$CaveatId' already exists. Use Update-Caveat to modify."
        }

        $caveat = @{
            caveatId = $CaveatId
            category = $Category
            subject = $Subject
            message = $Message
            triggers = $Triggers
            severity = $Severity
            metadata = $Metadata
            createdAt = [DateTime]::UtcNow.ToString("yyyy-MM-ddTHH:mm:ss.fffZ")
            updatedAt = [DateTime]::UtcNow.ToString("yyyy-MM-ddTHH:mm:ss.fffZ")
            triggerCount = 0
        }

        $registry.caveats[$CaveatId] = $caveat
        Save-CaveatRegistryInternal

        Write-Verbose "[CaveatRegistry] Registered caveat: $CaveatId"
        return $caveat
    }
    finally {
        [System.Threading.Monitor]::Exit($script:CaveatRegistryLock)
    }
}

<#
.SYNOPSIS
    Updates an existing caveat.

.DESCRIPTION
    Modifies an existing caveat in the registry.

.PARAMETER CaveatId
    The ID of the caveat to update.

.PARAMETER ProjectRoot
    The project root directory.

.PARAMETER Subject
    New subject (optional).

.PARAMETER Message
    New message (optional).

.PARAMETER Triggers
    New triggers (optional).

.PARAMETER Severity
    New severity (optional).

.PARAMETER Metadata
    New metadata (optional).

.OUTPUTS
    System.Collections.Hashtable. The updated caveat.
#>
function Update-Caveat {
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [Parameter(Mandatory = $true)]
        [string]$CaveatId,

        [Parameter()]
        [string]$ProjectRoot = ".",

        [Parameter()]
        [string]$Subject,

        [Parameter()]
        [string]$Message,

        [Parameter()]
        [hashtable]$Triggers,

        [Parameter()]
        [ValidateSet('info', 'warning', 'critical')]
        [string]$Severity,

        [Parameter()]
        [hashtable]$Metadata
    )

    $registry = Get-CaveatRegistry -ProjectRoot $ProjectRoot

    [System.Threading.Monitor]::Enter($script:CaveatRegistryLock)
    try {
        if (-not $registry.caveats.ContainsKey($CaveatId)) {
            throw "Caveat not found: $CaveatId"
        }

        $caveat = $registry.caveats[$CaveatId]

        if ($PSBoundParameters.ContainsKey('Subject')) {
            $caveat.subject = $Subject
        }
        if ($PSBoundParameters.ContainsKey('Message')) {
            $caveat.message = $Message
        }
        if ($PSBoundParameters.ContainsKey('Triggers')) {
            $caveat.triggers = $Triggers
        }
        if ($PSBoundParameters.ContainsKey('Severity')) {
            $caveat.severity = $Severity
        }
        if ($PSBoundParameters.ContainsKey('Metadata')) {
            $caveat.metadata = $Metadata
        }

        $caveat.updatedAt = [DateTime]::UtcNow.ToString("yyyy-MM-ddTHH:mm:ss.fffZ")

        Save-CaveatRegistryInternal

        Write-Verbose "[CaveatRegistry] Updated caveat: $CaveatId"
        return $caveat
    }
    finally {
        [System.Threading.Monitor]::Exit($script:CaveatRegistryLock)
    }
}

<#
.SYNOPSIS
    Removes a caveat from the registry.

.DESCRIPTION
    Deletes a caveat from the registry.

.PARAMETER CaveatId
    The ID of the caveat to remove.

.PARAMETER ProjectRoot
    The project root directory.

.OUTPUTS
    System.Boolean. True if removed, false if not found.
#>
function Remove-Caveat {
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [Parameter(Mandatory = $true)]
        [string]$CaveatId,

        [Parameter()]
        [string]$ProjectRoot = "."
    )

    $registry = Get-CaveatRegistry -ProjectRoot $ProjectRoot

    [System.Threading.Monitor]::Enter($script:CaveatRegistryLock)
    try {
        if (-not $registry.caveats.ContainsKey($CaveatId)) {
            Write-Warning "[CaveatRegistry] Caveat not found: $CaveatId"
            return $false
        }

        $registry.caveats.Remove($CaveatId)
        Save-CaveatRegistryInternal

        Write-Verbose "[CaveatRegistry] Removed caveat: $CaveatId"
        return $true
    }
    finally {
        [System.Threading.Monitor]::Exit($script:CaveatRegistryLock)
    }
}

<#
.SYNOPSIS
    Tests if text matches trigger criteria.

.DESCRIPTION
    Internal helper function to check if text matches caveat triggers.
#>
function Test-TriggerMatch {
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Text,

        [Parameter(Mandatory = $true)]
        [hashtable]$Triggers
    )

    $Text = $Text.ToLowerInvariant()
    $matchScore = 0

    # Check keywords
    if ($Triggers.ContainsKey('keywords')) {
        foreach ($keyword in $Triggers.keywords) {
            if ($Text.Contains($keyword.ToLowerInvariant())) {
                $matchScore++
            }
        }
    }

    # Check regex patterns
    if ($Triggers.ContainsKey('patterns')) {
        foreach ($pattern in $Triggers.patterns) {
            try {
                if ($Text -match $pattern) {
                    $matchScore += 2  # Patterns count more than keywords
                }
            }
            catch {
                Write-Verbose "[CaveatRegistry] Invalid pattern: $pattern"
            }
        }
    }

    return $matchScore -gt 0
}

<#
.SYNOPSIS
    Finds applicable caveats for a query or answer context.

.DESCRIPTION
    Searches the registry for caveats that apply to the given query and evidence.
    Uses trigger matching for efficient filtering.

.PARAMETER Query
    The user query text.

.PARAMETER Evidence
    Array of evidence items from retrieval.

.PARAMETER AnswerContext
    Additional context about the answer (pack IDs used, etc.).

.PARAMETER ProjectRoot
    The project root directory.

.PARAMETER MinMatchScore
    Minimum match score for a caveat to be considered applicable. Default is 1.

.OUTPUTS
    System.Array. Array of applicable caveats sorted by relevance.

.EXAMPLE
    $caveats = Find-ApplicableCaveats -Query "How do I use @onready?" -Evidence @()

.EXAMPLE
    $caveats = Find-ApplicableCaveats -Query "Plugin help" `
        -Evidence @(@{ source = 'rmmz-docs' }) `
        -AnswerContext @{ packsUsed = @('rpgmaker-mz') }
#>
function Find-ApplicableCaveats {
    [CmdletBinding()]
    [OutputType([array])]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Query,

        [Parameter()]
        [array]$Evidence = @(),

        [Parameter()]
        [hashtable]$AnswerContext = @{},

        [Parameter()]
        [string]$ProjectRoot = ".",

        [Parameter()]
        [int]$MinMatchScore = 1
    )

    $registry = Get-CaveatRegistry -ProjectRoot $ProjectRoot
    $applicable = @()

    # Build combined text from query and evidence
    $combinedText = $Query
    foreach ($ev in $Evidence) {
        if ($ev -is [hashtable]) {
            if ($ev.ContainsKey('text')) {
                $combinedText += " " + $ev.text
            }
            if ($ev.ContainsKey('content')) {
                $combinedText += " " + $ev.content
            }
        }
        elseif ($ev -is [string]) {
            $combinedText += " " + $ev
        }
    }

    $combinedText = $combinedText.ToLowerInvariant()

    # Get packs from context
    $packsUsed = @()
    if ($AnswerContext.ContainsKey('packsUsed')) {
        $packsUsed = $AnswerContext.packsUsed
    }

    foreach ($caveatEntry in $registry.caveats.GetEnumerator()) {
        $caveat = $caveatEntry.Value
        $matchScore = 0

        # Check if caveat applies to packs in use
        $packMatch = $false
        if ($caveat.triggers.ContainsKey('packs')) {
            if ($caveat.triggers.packs.Count -eq 0) {
                $packMatch = $true  # Applies to all packs
            }
            else {
                foreach ($pack in $packsUsed) {
                    if ($caveat.triggers.packs -contains $pack) {
                        $packMatch = $true
                        break
                    }
                }
            }
        }
        else {
            $packMatch = $true  # No pack restriction
        }

        # If no pack match and packs specified, skip this caveat
        if (-not $packMatch -and $caveat.triggers.packs.Count -gt 0 -and $packsUsed.Count -gt 0) {
            continue
        }

        # Check keywords
        if ($caveat.triggers.ContainsKey('keywords')) {
            foreach ($keyword in $caveat.triggers.keywords) {
                if ($combinedText.Contains($keyword.ToLowerInvariant())) {
                    $matchScore++
                }
            }
        }

        # Check patterns
        if ($caveat.triggers.ContainsKey('patterns')) {
            foreach ($pattern in $caveat.triggers.patterns) {
                try {
                    if ($combinedText -match $pattern) {
                        $matchScore += 2
                    }
                }
                catch {
                    Write-Verbose "[CaveatRegistry] Invalid pattern in caveat $($caveat.caveatId): $pattern"
                }
            }
        }

        if ($matchScore -ge $MinMatchScore) {
            $applicable += [PSCustomObject]@{
                Caveat = $caveat
                MatchScore = $matchScore
                MatchedAt = [DateTime]::UtcNow.ToString("yyyy-MM-ddTHH:mm:ss.fffZ")
            }
        }
    }

    # Sort by match score (descending) and ensure array
    $sorted = @($applicable | Sort-Object -Property MatchScore -Descending)

    # Update usage stats
    if ($sorted.Count -gt 0) {
        [System.Threading.Monitor]::Enter($script:CaveatRegistryLock)
        try {
            $registry.usageStats.totalTriggers += $sorted.Count
            $registry.usageStats.lastTriggerAt = [DateTime]::UtcNow.ToString("yyyy-MM-ddTHH:mm:ss.fffZ")
            
            # Update trigger counts for matched caveats
            foreach ($match in $sorted) {
                $match.Caveat.triggerCount++
            }
            
            Save-CaveatRegistryInternal
        }
        finally {
            [System.Threading.Monitor]::Exit($script:CaveatRegistryLock)
        }
    }

    return $sorted
}

<#
.SYNOPSIS
    Attaches caveats to an answer.

.DESCRIPTION
    Formats and appends applicable caveats to an answer string.
    Caveats are formatted based on severity.

.PARAMETER Answer
    The original answer text.

.PARAMETER Caveats
    Array of caveat objects (from Find-ApplicableCaveats).

.PARAMETER Format
    Output format: 'inline', 'section', or 'footnote'. Default is 'section'.

.OUTPUTS
    System.String. The answer with caveats attached.

.EXAMPLE
    $annotated = Add-AnswerCaveats -Answer $myAnswer -Caveats $caveats

.EXAMPLE
    $annotated = Add-AnswerCaveats -Answer $myAnswer -Caveats $caveats -Format 'footnote'
#>
function Add-AnswerCaveats {
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Answer,

        [Parameter(Mandatory = $true)]
        [array]$Caveats,

        [Parameter()]
        [ValidateSet('inline', 'section', 'footnote')]
        [string]$Format = 'section'
    )

    if ($Caveats.Count -eq 0) {
        return $Answer
    }

    switch ($Format) {
        'inline' {
            # Add caveats inline at the beginning
            $caveatNotes = $Caveats | ForEach-Object {
                $prefix = switch ($_.Caveat.severity) {
                    'critical' { '[CRITICAL]' }
                    'warning' { '[WARNING]' }
                    'info' { '[NOTE]' }
                    default { '[NOTE]' }
                }
                "$prefix $($_.Caveat.message)"
            }
            return ($caveatNotes -join "`n") + "`n`n" + $Answer
        }

        'footnote' {
            # Add caveats as footnotes
            $footnoteHeader = "`n`n---`n**Important Notes:**`n"
            $footnotes = $Caveats | ForEach-Object { 
                $marker = switch ($_.Caveat.severity) {
                    'critical' { '⚠️ CRITICAL' }
                    'warning' { '⚠️' }
                    'info' { 'ℹ️' }
                    default { 'ℹ️' }
                }
                "$marker $($_.Caveat.message)" 
            }
            return $Answer + $footnoteHeader + ($footnotes -join "`n`n")
        }

        'section' {
            # Add caveats in a dedicated section (default)
            $sectionHeader = "`n`n---`n`n### ⚠️ Important Caveats`n`n"
            $caveatItems = $Caveats | ForEach-Object {
                $severityEmoji = switch ($_.Caveat.severity) {
                    'critical' { '🔴' }
                    'warning' { '🟡' }
                    'info' { '🔵' }
                    default { '🔵' }
                }
                $category = $_.Caveat.category -replace '-', ' '
                "$severityEmoji **[$category]** $($_.Caveat.message)"
            }
            return $Answer + $sectionHeader + ($caveatItems -join "`n`n") + "`n"
        }
    }

    return $Answer
}

<#
.SYNOPSIS
    Tests if an answer contains known falsehoods.

.DESCRIPTION
    Checks answer text against falsehood patterns registered in the caveat registry.
    Returns detailed information about detected falsehoods.

.PARAMETER AnswerText
    The answer text to test.

.PARAMETER ProjectRoot
    The project root directory.

.PARAMETER IncludeCategories
    Categories to include in the check. Default is all.

.OUTPUTS
    System.Collections.Hashtable. Results with HasFalsehoods, Falsehoods, Confidence.

.EXAMPLE
    $result = Test-KnownFalsehoods -AnswerText "Use export var in Godot 4."
    if ($result.HasFalsehoods) { Write-Host "Answer contains issues!" }
#>
function Test-KnownFalsehoods {
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [Parameter(Mandatory = $true)]
        [string]$AnswerText,

        [Parameter()]
        [string]$ProjectRoot = ".",

        [Parameter()]
        [string[]]$IncludeCategories = @('version-boundary', 'deprecated', 'common-misconception')
    )

    $registry = Get-CaveatRegistry -ProjectRoot $ProjectRoot
    $detected = @()
    $confidence = 0.0

    foreach ($caveatEntry in $registry.caveats.GetEnumerator()) {
        $caveat = $caveatEntry.Value

        # Skip if category not in include list
        if ($IncludeCategories -notcontains $caveat.category) {
            continue
        }

        # Check for falsehood indicators
        $matched = $false
        $matchScore = 0

        if ($caveat.triggers.ContainsKey('falsehoodPatterns')) {
            foreach ($pattern in $caveat.triggers.falsehoodPatterns) {
                try {
                    if ($AnswerText -match $pattern) {
                        $matched = $true
                        $matchScore += 3
                    }
                }
                catch {
                    Write-Verbose "[CaveatRegistry] Invalid falsehood pattern: $pattern"
                }
            }
        }

        # Also check regular patterns
        if ($caveat.triggers.ContainsKey('patterns')) {
            foreach ($pattern in $caveat.triggers.patterns) {
                try {
                    if ($AnswerText -match $pattern) {
                        $matched = $true
                        $matchScore += 2
                    }
                }
                catch {
                    Write-Verbose "[CaveatRegistry] Invalid pattern: $pattern"
                }
            }
        }

        if ($matched) {
            $detected += [PSCustomObject]@{
                CaveatId = $caveat.caveatId
                Category = $caveat.category
                Subject = $caveat.subject
                Message = $caveat.message
                Severity = $caveat.severity
                MatchScore = $matchScore
            }
            $confidence += ($matchScore / 10.0)
        }
    }

    # Cap confidence at 1.0
    $confidence = [Math]::Min(1.0, $confidence)

    return @{
        HasFalsehoods = $detected.Count -gt 0
        FalsehoodCount = $detected.Count
        Falsehoods = $detected
        Confidence = $confidence
        CheckedAt = [DateTime]::UtcNow.ToString("yyyy-MM-ddTHH:mm:ss.fffZ")
    }
}

<#
.SYNOPSIS
    Gets caveats by category.

.DESCRIPTION
    Returns all caveats in a specific category.

.PARAMETER Category
    The category to filter by.

.PARAMETER ProjectRoot
    The project root directory.

.OUTPUTS
    System.Array. Array of caveat objects.

.EXAMPLE
    $versionCaveats = Get-CaveatsByCategory -Category "version-boundary"
#>
function Get-CaveatsByCategory {
    [CmdletBinding()]
    [OutputType([array])]
    param(
        [Parameter(Mandatory = $true)]
        [ValidateSet('version-boundary', 'common-misconception', 'compatibility', 
                     'experimental', 'deprecated', 'translation-only')]
        [string]$Category,

        [Parameter()]
        [string]$ProjectRoot = "."
    )

    $registry = Get-CaveatRegistry -ProjectRoot $ProjectRoot

    $filtered = $registry.caveats.GetEnumerator() | 
        Where-Object { $_.Value.category -eq $Category } |
        ForEach-Object { $_.Value }

    return $filtered
}

<#
.SYNOPSIS
    Gets a specific caveat by ID.

.DESCRIPTION
    Retrieves a single caveat by its ID.

.PARAMETER CaveatId
    The ID of the caveat to retrieve.

.PARAMETER ProjectRoot
    The project root directory.

.OUTPUTS
    System.Collections.Hashtable. The caveat object, or null if not found.
#>
function Get-Caveat {
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [Parameter(Mandatory = $true)]
        [string]$CaveatId,

        [Parameter()]
        [string]$ProjectRoot = "."
    )

    $registry = Get-CaveatRegistry -ProjectRoot $ProjectRoot

    if ($registry.caveats.ContainsKey($CaveatId)) {
        return $registry.caveats[$CaveatId]
    }

    return $null
}

<#
.SYNOPSIS
    Loads predefined caveats for a specific pack.

.DESCRIPTION
    Returns only the predefined caveats that apply to a specific pack.
    Does not modify the registry.

.PARAMETER PackId
    The pack ID to load caveats for.

.OUTPUTS
    System.Array. Array of applicable caveat objects.

.EXAMPLE
    $godotCaveats = Load-PackCaveats -PackId "godot-engine"
#>
function Load-PackCaveats {
    [CmdletBinding()]
    [OutputType([array])]
    param(
        [Parameter(Mandatory = $true)]
        [string]$PackId
    )

    $packCaveats = @()

    foreach ($caveatEntry in $script:PredefinedCaveats.GetEnumerator()) {
        $caveat = $caveatEntry.Value

        # Check if caveat applies to this pack
        if ($caveat.triggers.ContainsKey('packs')) {
            if ($caveat.triggers.packs.Count -eq 0 -or 
                $caveat.triggers.packs -contains $PackId) {
                $packCaveats += $caveat
            }
        }
        else {
            # No pack restriction, include it
            $packCaveats += $caveat
        }
    }

    return $packCaveats
}

<#
.SYNOPSIS
    Exports the caveat registry to a file.

.DESCRIPTION
    Exports the entire caveat registry to a JSON file for sharing
    or backup purposes.

.PARAMETER OutputPath
    The output file path.

.PARAMETER ProjectRoot
    The project root directory.

.PARAMETER Compress
    If specified, outputs compressed JSON.

.OUTPUTS
    System.Collections.Hashtable. Export result with Success, Path, CaveatCount.

.EXAMPLE
    Export-CaveatRegistry -OutputPath "caveats-backup.json"
#>
function Export-CaveatRegistry {
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [Parameter(Mandatory = $true)]
        [string]$OutputPath,

        [Parameter()]
        [string]$ProjectRoot = ".",

        [switch]$Compress
    )

    $registry = Get-CaveatRegistry -ProjectRoot $ProjectRoot

    try {
        $dir = Split-Path -Parent $OutputPath
        if (-not (Test-Path -LiteralPath $dir)) {
            New-Item -ItemType Directory -Path $dir -Force | Out-Null
        }

        $json = $registry | ConvertTo-Json -Depth 20 -Compress:$Compress
        [System.IO.File]::WriteAllText($OutputPath, $json, [System.Text.Encoding]::UTF8)

        Write-Verbose "[CaveatRegistry] Exported registry to $OutputPath"

        return @{
            Success = $true
            Path = $OutputPath
            CaveatCount = $registry.caveats.Count
            ExportedAt = [DateTime]::UtcNow.ToString("yyyy-MM-ddTHH:mm:ss.fffZ")
        }
    }
    catch {
        Write-Error "[CaveatRegistry] Failed to export registry: $_"
        return @{
            Success = $false
            Path = $OutputPath
            Error = $_.Exception.Message
        }
    }
}

<#
.SYNOPSIS
    Imports caveats from a file.

.DESCRIPTION
    Imports caveats from a JSON file into the registry.
    Can merge with existing caveats or replace them.

.PARAMETER Path
    The path to the import file.

.PARAMETER ProjectRoot
    The project root directory.

.PARAMETER MergeMode
    How to handle conflicts: 'merge' (default), 'replace', or 'skip'.

.OUTPUTS
    System.Collections.Hashtable. Import result with Success, ImportedCount, ReplacedCount.

.EXAMPLE
    Import-CaveatRegistry -Path "shared-caveats.json"

.EXAMPLE
    Import-CaveatRegistry -Path "new-caveats.json" -MergeMode replace
#>
function Import-CaveatRegistry {
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path,

        [Parameter()]
        [string]$ProjectRoot = ".",

        [Parameter()]
        [ValidateSet('merge', 'replace', 'skip')]
        [string]$MergeMode = 'merge'
    )

    if (-not (Test-Path -LiteralPath $Path)) {
        throw "Import file not found: $Path"
    }

    try {
        $json = [System.IO.File]::ReadAllText($Path, [System.Text.Encoding]::UTF8)
        $parsedImport = $json | ConvertFrom-Json; $importData = ConvertTo-Hashtable -InputObject $parsedImport

        if ($null -eq $importData -or -not $importData.ContainsKey('caveats')) {
            throw "Invalid caveat registry format: missing 'caveats' key"
        }

        $registry = Get-CaveatRegistry -ProjectRoot $ProjectRoot

        [System.Threading.Monitor]::Enter($script:CaveatRegistryLock)
        try {
            $importedCount = 0
            $replacedCount = 0
            $skippedCount = 0

            foreach ($caveatEntry in $importData.caveats.GetEnumerator()) {
                $caveatId = $caveatEntry.Key
                $caveat = $caveatEntry.Value

                if ($registry.caveats.ContainsKey($caveatId)) {
                    switch ($MergeMode) {
                        'replace' {
                            $registry.caveats[$caveatId] = $caveat
                            $replacedCount++
                        }
                        'merge' {
                            # Update only if import is newer
                            $existing = $registry.caveats[$caveatId]
                            if ($caveat.ContainsKey('updatedAt') -and 
                                $existing.ContainsKey('updatedAt')) {
                                $importTime = [DateTime]::Parse($caveat.updatedAt)
                                $existingTime = [DateTime]::Parse($existing.updatedAt)
                                if ($importTime -gt $existingTime) {
                                    $registry.caveats[$caveatId] = $caveat
                                    $replacedCount++
                                }
                                else {
                                    $skippedCount++
                                }
                            }
                            else {
                                $skippedCount++
                            }
                        }
                        'skip' {
                            $skippedCount++
                        }
                    }
                }
                else {
                    $registry.caveats[$caveatId] = $caveat
                    $importedCount++
                }
            }

            Save-CaveatRegistryInternal

            Write-Verbose "[CaveatRegistry] Imported $importedCount caveats, replaced $replacedCount, skipped $skippedCount"

            return @{
                Success = $true
                ImportedCount = $importedCount
                ReplacedCount = $replacedCount
                SkippedCount = $skippedCount
                TotalCount = $registry.caveats.Count
                ImportedAt = [DateTime]::UtcNow.ToString("yyyy-MM-ddTHH:mm:ss.fffZ")
            }
        }
        finally {
            [System.Threading.Monitor]::Exit($script:CaveatRegistryLock)
        }
    }
    catch {
        Write-Error "[CaveatRegistry] Failed to import registry: $_"
        return @{
            Success = $false
            Error = $_.Exception.Message
        }
    }
}

<#
.SYNOPSIS
    Gets registry statistics.

.DESCRIPTION
    Returns statistics about the caveat registry usage.

.PARAMETER ProjectRoot
    The project root directory.

.OUTPUTS
    System.Collections.Hashtable. Statistics object.
#>
function Get-CaveatRegistryStats {
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [Parameter()]
        [string]$ProjectRoot = "."
    )

    $registry = Get-CaveatRegistry -ProjectRoot $ProjectRoot

    $byCategory = @{}
    $bySeverity = @{}
    $topTriggered = @()

    foreach ($caveat in $registry.caveats.Values) {
        # Count by category
        if (-not $byCategory.ContainsKey($caveat.category)) {
            $byCategory[$caveat.category] = 0
        }
        $byCategory[$caveat.category]++

        # Count by severity
        if (-not $bySeverity.ContainsKey($caveat.severity)) {
            $bySeverity[$caveat.severity] = 0
        }
        $bySeverity[$caveat.severity]++
    }

    # Get top triggered caveats
    $topTriggered = @($registry.caveats.Values) | 
        Where-Object { $_.ContainsKey('triggerCount') -and $_.triggerCount -gt 0 } |
        Sort-Object -Property triggerCount -Descending |
        Select-Object -First 10 | 
        ForEach-Object { 
            [PSCustomObject]@{
                CaveatId = $_.caveatId
                Subject = $_.subject
                TriggerCount = $_.triggerCount
            }
        }

    return @{
        TotalCaveats = $registry.caveats.Count
        ByCategory = $byCategory
        BySeverity = $bySeverity
        UsageStats = $registry.usageStats
        TopTriggered = $topTriggered
        SchemaVersion = $registry.schemaVersion
        CreatedAt = $registry.createdAt
        UpdatedAt = $registry.updatedAt
        RegistryPath = $script:CaveatRegistryPath
    }
}

<#
.SYNOPSIS
    Resets the caveat registry to defaults.

.DESCRIPTION
    Clears all caveats and restores predefined defaults.
    WARNING: This will delete any custom caveats.

.PARAMETER ProjectRoot
    The project root directory.

.PARAMETER Force
    Skip confirmation prompt.

.OUTPUTS
    System.Boolean. True if reset successful.
#>
function Reset-CaveatRegistry {
    [CmdletBinding(SupportsShouldProcess = $true)]
    [OutputType([bool])]
    param(
        [Parameter()]
        [string]$ProjectRoot = ".",

        [switch]$Force
    )

    if (-not $Force -and -not $PSCmdlet.ShouldProcess("Caveat Registry", "Reset to defaults")) {
        return $false
    }

    [System.Threading.Monitor]::Enter($script:CaveatRegistryLock)
    try {
        $script:CaveatRegistryInstance = $null
        $registry = Get-CaveatRegistry -ProjectRoot $ProjectRoot -Force
        
        Write-Verbose "[CaveatRegistry] Registry reset to defaults"
        return $true
    }
    finally {
        [System.Threading.Monitor]::Exit($script:CaveatRegistryLock)
    }
}

# Export all public functions
Export-ModuleMember -Function @(
    'Get-CaveatRegistry'
    'Register-Caveat'
    'Update-Caveat'
    'Remove-Caveat'
    'Get-Caveat'
    'Find-ApplicableCaveats'
    'Add-AnswerCaveats'
    'Test-KnownFalsehoods'
    'Get-CaveatsByCategory'
    'Load-PackCaveats'
    'Export-CaveatRegistry'
    'Import-CaveatRegistry'
    'Get-CaveatRegistryStats'
    'Reset-CaveatRegistry'
)
