#requires -Version 5.1
<#
.SYNOPSIS
    Blender Python addon parser for the LLM Workflow Phase 4 Structured Extraction Pipeline.

.DESCRIPTION
    Parses Blender Python scripts and extracts:
    - Addon registration metadata (bl_info)
    - Operator class registrations (bpy.types.Operator)
    - Panel class registrations (bpy.types.Panel)
    - Property declarations (bpy.props.*)
    - bpy.ops operator call patterns
    - Menu registrations
    - Keymap registrations
    - Geometry Nodes node groups and types
    - Import statements for dependency tracking
    
    This parser implements Section 26.6.2 of the canonical architecture
    for the Blender pack's structured extraction pipeline.

.NOTES
    File Name      : BlenderPythonParser.ps1
    Author         : LLM Workflow Team
    Version        : 1.0.0
    Prerequisite   : PowerShell 5.1+
    Copyright      : (c) 2026 LLM Workflow Project
    License        : MIT
    Engine Support : Blender 2.8+, Blender 3.x, Blender 4.x
#>

Set-StrictMode -Version Latest

# ============================================================================
# Script-level Constants
# ============================================================================

# Default values for bl_info fields
$script:DefaultBlInfo = @{
    name = ""
    author = ""
    version = @(0, 0, 0)
    blender = @(2, 80, 0)
    description = ""
    category = ""
    location = ""
    warning = ""
    wiki_url = ""
    tracker_url = ""
    support = "COMMUNITY"
}

# Known bpy modules for dependency tracking
$script:KnownBpyModules = @('bpy', 'bmesh', 'mathutils', 'blf', 'gpu', 'aud', 'ffmpg')

# Standard library modules to exclude from dependencies
$script:StdLibModules = @('os', 'sys', 'json', 'math', 'random', 'datetime', 'collections', 'itertools', 'functools', 're', 'typing', 'pathlib', 'inspect', 'textwrap', 'hashlib', 'base64', 'io', 'string')

# Quote characters
$script:SingleQuote = "'"
$script:DoubleQuote = '"'

# ============================================================================
# Main Parser Function
# ============================================================================

function Invoke-BlenderPythonParse {
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [Parameter(Mandatory = $true, ParameterSetName = 'Path')]
        [Alias('FilePath')]
        [string]$Path,
        
        [Parameter(Mandatory = $true, ParameterSetName = 'Content')]
        [string]$Content,
        
        [Parameter()]
        [string]$BlenderVersion = '4.x'
    )
    
    begin {
        Write-Verbose "[BlenderPythonParser] Starting parse operation"
        $correlationId = [System.Guid]::NewGuid().ToString("N").Substring(0, 8)
        Write-Verbose "[BlenderPythonParser] Correlation ID: $correlationId"
    }
    
    process {
        try {
            $sourceFile = ""
            if ($PSCmdlet.ParameterSetName -eq 'Path') {
                Write-Verbose "[BlenderPythonParser] Loading file: $Path"
                
                if (-not (Test-Path -LiteralPath $Path)) {
                    throw "File not found: $Path"
                }
                
                $sourceFile = Resolve-Path -Path $Path | Select-Object -ExpandProperty Path
                $fileContent = Get-Content -LiteralPath $sourceFile -Raw -Encoding UTF8
            }
            else {
                $fileContent = $Content
                $sourceFile = "<inline>"
            }
            
            if ([string]::IsNullOrWhiteSpace($fileContent)) {
                throw "Content is empty"
            }
            
            Write-Verbose "[BlenderPythonParser] Parsing content ($($fileContent.Length) chars)"
            
            # Extract all components
            $addonInfo = Get-BlenderAddonInfo -Content $fileContent
            $operators = Get-BlenderOperators -Content $fileContent
            $panels = Get-BlenderPanels -Content $fileContent
            $menus = Get-BlenderMenus -Content $fileContent
            $properties = Get-BlenderProperties -Content $fileContent
            $operatorCalls = Get-BlenderOperatorCalls -Content $fileContent
            $nodeGroups = Get-BlenderNodeGroups -Content $fileContent
            $imports = Get-BlenderImports -Content $fileContent
            $dependencies = Get-BlenderDependencies -Content $fileContent -Imports $imports
            $versionCompat = Test-BlenderVersionCompatibility -Content $fileContent -TargetVersion $BlenderVersion
            
            $manifest = @{
                addonInfo = $addonInfo
                operators = $operators
                panels = $panels
                menus = $menus
                operatorCalls = $operatorCalls
                imports = $imports
                dependencies = $dependencies
                geometryNodes = @{ nodeGroups = $nodeGroups }
                sourceFile = $sourceFile
                parsedAt = [DateTime]::UtcNow.ToString("o")
                compatibility = $versionCompat
            }
            
            Write-Verbose "[BlenderPythonParser] Parse complete: $($operators.Count) operators, $($panels.Count) panels"
            
            return $manifest
        }
        catch {
            Write-Error "[BlenderPythonParser] Failed to parse: $_"
            throw
        }
    }
}

# ============================================================================
# Public API Functions
# ============================================================================

function Get-BlenderAddonInfo {
    [CmdletBinding(DefaultParameterSetName = 'Content')]
    [OutputType([hashtable])]
    param(
        [Parameter(ParameterSetName = 'Path', Mandatory = $true)]
        [string]$Path,
        
        [Parameter(ParameterSetName = 'Content', Mandatory = $true, ValueFromPipeline = $true)]
        [string]$Content
    )
    
    process {
        try {
            if ($PSCmdlet.ParameterSetName -eq 'Path') {
                $Content = Get-Content -LiteralPath $Path -Raw -Encoding UTF8
            }
            
            $result = @{
                name = ""
                author = ""
                version = @(0, 0, 0)
                blender = @(2, 80, 0)
                location = ""
                description = ""
                category = ""
                support = "COMMUNITY"
            }
            
            # Match bl_info dictionary
            $match = [regex]::Match($Content, '(?s)bl_info\s*=\s*\{([^}]+(?:\{[^}]*\}[^}]*)*)\}')
            if (-not $match.Success) {
                Write-Verbose "[Get-BlenderAddonInfo] No bl_info dictionary found"
                return $result
            }
            
            $dictContent = $match.Groups[1].Value
            
            # Parse string values - double quotes
            $dqPattern = '"([^"]+)"\s*:\s*"([^"]*)"'
            [regex]::Matches($dictContent, $dqPattern) | ForEach-Object {
                $key = $_.Groups[1].Value.Trim()
                $value = $_.Groups[2].Value
                if ($result.ContainsKey($key)) { $result[$key] = $value }
            }
            
            # Parse string values - single quotes
            $sqPattern = "'([^']+)'\s*:\s*'([^']*)'"
            [regex]::Matches($dictContent, $sqPattern) | ForEach-Object {
                $key = $_.Groups[1].Value.Trim()
                $value = $_.Groups[2].Value
                if ($result.ContainsKey($key)) { $result[$key] = $value }
            }
            
            # Parse version tuples
            $vMatch = [regex]::Match($dictContent, '"version"\s*:\s*\((\d+)\s*,\s*(\d+)(?:\s*,\s*(\d+))?\)')
            if ($vMatch.Success) {
                $version = @([int]$vMatch.Groups[1].Value, [int]$vMatch.Groups[2].Value)
                if ($vMatch.Groups[3].Success) { $version += [int]$vMatch.Groups[3].Value }
                $result['version'] = $version
            }
            
            # Parse blender version tuple
            $bMatch = [regex]::Match($dictContent, '"blender"\s*:\s*\((\d+)\s*,\s*(\d+)(?:\s*,\s*(\d+))?\)')
            if ($bMatch.Success) {
                $blenderVer = @([int]$bMatch.Groups[1].Value, [int]$bMatch.Groups[2].Value)
                if ($bMatch.Groups[3].Success) { $blenderVer += [int]$bMatch.Groups[3].Value }
                $result['blender'] = $blenderVer
            }
            
            return $result
        }
        catch {
            Write-Warning "[Get-BlenderAddonInfo] Failed to parse bl_info: $_"
            return $script:DefaultBlInfo.Clone()
        }
    }
}

function Get-BlenderOperators {
    [CmdletBinding(DefaultParameterSetName = 'Content')]
    [OutputType([array])]
    param(
        [Parameter(ParameterSetName = 'Path', Mandatory = $true)]
        [string]$Path,
        
        [Parameter(ParameterSetName = 'Content', Mandatory = $true, ValueFromPipeline = $true)]
        [string]$Content
    )
    
    process {
        try {
            if ($PSCmdlet.ParameterSetName -eq 'Path') {
                $Content = Get-Content -LiteralPath $Path -Raw -Encoding UTF8
            }
            
            $operators = New-Object System.Collections.ArrayList
            
            # Match operator class definitions
            $classMatches = [regex]::Matches($Content, 'class\s+(\w+)\s*\(\s*bpy\.types\.Operator\s*\)')
            Write-Verbose "[Get-BlenderOperators] Found $($classMatches.Count) operator classes"
            
            foreach ($classMatch in $classMatches) {
                $className = $classMatch.Groups[1].Value
                $classBlock = Get-ClassBlock -Content $Content -ClassName $className
                
                if ($classBlock) {
                    $operator = Parse-OperatorClass -ClassName $className -ClassBlock $classBlock
                    [void]$operators.Add($operator)
                }
            }
            
            return ,$operators.ToArray()
        }
        catch {
            Write-Warning "[Get-BlenderOperators] Failed to extract operators: $_"
            return @()
        }
    }
}

function Get-BlenderPanels {
    [CmdletBinding(DefaultParameterSetName = 'Content')]
    [OutputType([array])]
    param(
        [Parameter(ParameterSetName = 'Path', Mandatory = $true)]
        [string]$Path,
        
        [Parameter(ParameterSetName = 'Content', Mandatory = $true, ValueFromPipeline = $true)]
        [string]$Content
    )
    
    process {
        try {
            if ($PSCmdlet.ParameterSetName -eq 'Path') {
                $Content = Get-Content -LiteralPath $Path -Raw -Encoding UTF8
            }
            
            $panels = New-Object System.Collections.ArrayList
            
            $classMatches = [regex]::Matches($Content, 'class\s+(\w+)\s*\(\s*bpy\.types\.Panel\s*\)')
            Write-Verbose "[Get-BlenderPanels] Found $($classMatches.Count) panel classes"
            
            foreach ($classMatch in $classMatches) {
                $className = $classMatch.Groups[1].Value
                $classBlock = Get-ClassBlock -Content $Content -ClassName $className
                
                if ($classBlock) {
                    $panel = Parse-PanelClass -ClassName $className -ClassBlock $classBlock
                    [void]$panels.Add($panel)
                }
            }
            
            return ,$panels.ToArray()
        }
        catch {
            Write-Warning "[Get-BlenderPanels] Failed to extract panels: $_"
            return @()
        }
    }
}

function Get-BlenderMenus {
    [CmdletBinding(DefaultParameterSetName = 'Content')]
    [OutputType([array])]
    param(
        [Parameter(ParameterSetName = 'Path', Mandatory = $true)]
        [string]$Path,
        
        [Parameter(ParameterSetName = 'Content', Mandatory = $true, ValueFromPipeline = $true)]
        [string]$Content
    )
    
    process {
        try {
            if ($PSCmdlet.ParameterSetName -eq 'Path') {
                $Content = Get-Content -LiteralPath $Path -Raw -Encoding UTF8
            }
            
            $menus = New-Object System.Collections.ArrayList
            
            $classMatches = [regex]::Matches($Content, 'class\s+(\w+)\s*\(\s*bpy\.types\.Menu\s*\)')
            Write-Verbose "[Get-BlenderMenus] Found $($classMatches.Count) menu classes"
            
            foreach ($classMatch in $classMatches) {
                $className = $classMatch.Groups[1].Value
                $classBlock = Get-ClassBlock -Content $Content -ClassName $className
                
                if ($classBlock) {
                    $menu = @{
                        bl_idname = $className
                        bl_label = ""
                    }
                    
                    # Extract bl_idname - avoid character class issues
                    $idMatch = [regex]::Match($classBlock, 'bl_idname\s*=\s*["' + $script:SingleQuote + '](.+)["' + $script:SingleQuote + ']')
                    if ($idMatch.Success) { $menu.bl_idname = $idMatch.Groups[1].Value }
                    
                    # Extract bl_label
                    $labelMatch = [regex]::Match($classBlock, 'bl_label\s*=\s*["' + $script:SingleQuote + '](.+)["' + $script:SingleQuote + ']')
                    if ($labelMatch.Success) { 
                        $menu.bl_label = $labelMatch.Groups[1].Value 
                    }
                    else {
                        $menu.bl_label = ConvertTo-Label -ClassName $className
                    }
                    
                    [void]$menus.Add($menu)
                }
            }
            
            return ,$menus.ToArray()
        }
        catch {
            Write-Warning "[Get-BlenderMenus] Failed to extract menus: $_"
            return @()
        }
    }
}

function Get-BlenderProperties {
    [CmdletBinding(DefaultParameterSetName = 'Content')]
    [OutputType([array])]
    param(
        [Parameter(ParameterSetName = 'Path', Mandatory = $true)]
        [string]$Path,
        
        [Parameter(ParameterSetName = 'Content', Mandatory = $true, ValueFromPipeline = $true)]
        [string]$Content,
        
        [Parameter()]
        [ValidateSet("global", "class")]
        [string]$Scope = "global",
        
        [Parameter()]
        [string]$ClassBlock = ""
    )
    
    process {
        try {
            if ($PSCmdlet.ParameterSetName -eq 'Path') {
                $Content = Get-Content -LiteralPath $Path -Raw -Encoding UTF8
            }
            
            $properties = New-Object System.Collections.ArrayList
            $targetContent = if ($ClassBlock) { $ClassBlock } else { $Content }
            
            if ([string]::IsNullOrWhiteSpace($targetContent)) {
                return @()
            }
            
            # Pattern for property declarations with bpy.props
            $propMatches = [regex]::Matches($targetContent, '(?m)^\s+(\w+)\s*:\s*(?:bpy\.props\.)?(\w+Property)\s*\(')
            
            foreach ($match in $propMatches) {
                $propName = $match.Groups[1].Value
                $propType = $match.Groups[2].Value
                
                # Extract property arguments
                $startIdx = $match.Index + $match.Length - 1
                $parenCount = 1
                $argContent = ""
                $idx = $startIdx + 1
                $chars = $targetContent.ToCharArray()
                
                while ($idx -lt $chars.Length -and $parenCount -gt 0) {
                    $char = $chars[$idx]
                    if ($char -eq '(') { $parenCount++ }
                    elseif ($char -eq ')') {
                        $parenCount--
                        if ($parenCount -eq 0) { break }
                    }
                    $argContent += $char
                    $idx++
                }
                
                $arguments = Parse-PropertyArguments -ArgumentString $argContent
                
                $prop = @{
                    name = $propName
                    type = $propType
                    subtype = if ($arguments.ContainsKey('subtype')) { $arguments['subtype'] } else { $null }
                    default = if ($arguments.ContainsKey('default')) { ConvertTo-TypedValue -Value $arguments['default'] -PropertyType $propType } else { $null }
                    min = if ($arguments.ContainsKey('min')) { [double]$arguments['min'] } else { $null }
                    max = if ($arguments.ContainsKey('max')) { [double]$arguments['max'] } else { $null }
                    description = if ($arguments.ContainsKey('description')) { $arguments['description'] } else { "" }
                }
                
                [void]$properties.Add($prop)
            }
            
            return ,$properties.ToArray()
        }
        catch {
            Write-Warning "[Get-BlenderProperties] Failed to extract properties: $_"
            return @()
        }
    }
}

function Get-BlenderOperatorCalls {
    [CmdletBinding(DefaultParameterSetName = 'Content')]
    [OutputType([array])]
    param(
        [Parameter(ParameterSetName = 'Path', Mandatory = $true)]
        [string]$Path,
        
        [Parameter(ParameterSetName = 'Content', Mandatory = $true, ValueFromPipeline = $true)]
        [string]$Content
    )
    
    process {
        try {
            if ($PSCmdlet.ParameterSetName -eq 'Path') {
                $Content = Get-Content -LiteralPath $Path -Raw -Encoding UTF8
            }
            
            $calls = New-Object System.Collections.ArrayList
            
            # Find operator calls with parameters
            $matches = [regex]::Matches($Content, 'bpy\.ops\.(\w+)\.(\w+)\s*\(([^)]*)\)')
            
            foreach ($match in $matches) {
                $category = $match.Groups[1].Value
                $opName = $match.Groups[2].Value
                $params = $match.Groups[3].Value
                
                $call = @{
                    operator = "$category.$opName"
                    context = "bpy.context"
                    parameters = Parse-OperatorParameters -ParameterString $params
                }
                
                [void]$calls.Add($call)
            }
            
            # Also find simple operator calls without parameters
            $simpleMatches = [regex]::Matches($Content, 'bpy\.ops\.(\w+)\.(\w+)(?:\s*\(|\s)')
            foreach ($match in $simpleMatches) {
                $category = $match.Groups[1].Value
                $opName = $match.Groups[2].Value
                $fullOpName = "$category.$opName"
                
                # Check if not already added
                $existing = $calls | Where-Object { $_.operator -eq $fullOpName }
                if (-not $existing) {
                    $call = @{
                        operator = $fullOpName
                        context = "bpy.context"
                        parameters = @{}
                    }
                    [void]$calls.Add($call)
                }
            }
            
            return ,$calls.ToArray()
        }
        catch {
            Write-Warning "[Get-BlenderOperatorCalls] Failed to extract operator calls: $_"
            return @()
        }
    }
}

function Get-BlenderNodeGroups {
    [CmdletBinding(DefaultParameterSetName = 'Content')]
    [OutputType([array])]
    param(
        [Parameter(ParameterSetName = 'Path', Mandatory = $true)]
        [string]$Path,
        
        [Parameter(ParameterSetName = 'Content', Mandatory = $true, ValueFromPipeline = $true)]
        [string]$Content
    )
    
    process {
        try {
            if ($PSCmdlet.ParameterSetName -eq 'Path') {
                $Content = Get-Content -LiteralPath $Path -Raw -Encoding UTF8
            }
            
            $nodeGroups = New-Object System.Collections.ArrayList
            
            # Find node group creation
            $ngMatches = [regex]::Matches($Content, 'bpy\.data\.node_groups\.new\s*\(\s*name\s*=\s*["' + $script:SingleQuote + ']([^"' + $script:SingleQuote + ']+)["' + $script:SingleQuote + ']\s*,\s*type\s*=\s*["' + $script:SingleQuote + ']([^"' + $script:SingleQuote + ']+)["' + $script:SingleQuote + ']\s*\)')
            
            foreach ($match in $ngMatches) {
                $ngName = $match.Groups[1].Value
                $ngType = $match.Groups[2].Value
                
                $nodeGroup = @{
                    name = $ngName
                    type = $ngType
                    nodes = @()
                    links = @()
                }
                
                # Extract nodes
                $nodeNewPattern = '\.nodes\.new\s*\(\s*["' + $script:SingleQuote + ']([^"' + $script:SingleQuote + ']+)["' + $script:SingleQuote + ']\s*\)'
                $nodeMatches = [regex]::Matches($Content, $nodeNewPattern)
                $nodeId = 0
                foreach ($nodeMatch in $nodeMatches) {
                    $nodeId++
                    $nodeType = $nodeMatch.Groups[1].Value
                    $nodeGroup.nodes += @{
                        id = "Node_{0:D3}" -f $nodeId
                        type = $nodeType
                        name = $nodeType
                    }
                }
                
                # Extract links
                $linkNewPattern = '\.links\.new\s*\(\s*(\w+)\.outputs?\[(?:\d+|"[^"]+")\]\s*,\s*(\w+)\.inputs?\[(?:\d+|"[^"]+")\]\s*\)'
                $linkMatches = [regex]::Matches($Content, $linkNewPattern)
                $linkId = 0
                foreach ($linkMatch in $linkMatches) {
                    $linkId++
                    $fromNode = $linkMatch.Groups[1].Value
                    $toNode = $linkMatch.Groups[2].Value
                    $nodeGroup.links += @{
                        id = "Link_{0:D3}" -f $linkId
                        fromNode = $fromNode
                        toNode = $toNode
                    }
                }
                
                [void]$nodeGroups.Add($nodeGroup)
            }
            
            return ,$nodeGroups.ToArray()
        }
        catch {
            Write-Warning "[Get-BlenderNodeGroups] Failed to extract node groups: $_"
            return @()
        }
    }
}

function Get-BlenderImports {
    [CmdletBinding(DefaultParameterSetName = 'Content')]
    [OutputType([array])]
    param(
        [Parameter(ParameterSetName = 'Path', Mandatory = $true)]
        [string]$Path,
        
        [Parameter(ParameterSetName = 'Content', Mandatory = $true, ValueFromPipeline = $true)]
        [string]$Content
    )
    
    process {
        try {
            if ($PSCmdlet.ParameterSetName -eq 'Path') {
                $Content = Get-Content -LiteralPath $Path -Raw -Encoding UTF8
            }
            
            $imports = New-Object System.Collections.ArrayList
            
            # Standard imports: import bpy, mathutils
            $stdMatches = [regex]::Matches($Content, '(?m)^import\s+(\w+(?:\s*,\s*\w+)*)')
            foreach ($match in $stdMatches) {
                $modules = $match.Groups[1].Value -split '\s*,\s*'
                foreach ($mod in $modules) {
                    [void]$imports.Add($mod.Trim())
                }
            }
            
            # From imports: from bpy import context
            $fromMatches = [regex]::Matches($Content, '(?m)^from\s+([\w.]+)\s+import\s+([^\n]+)')
            foreach ($match in $fromMatches) {
                $module = $match.Groups[1].Value
                if (-not $imports.Contains($module)) {
                    [void]$imports.Add($module)
                }
            }
            
            return ,($imports | Select-Object -Unique)
        }
        catch {
            Write-Warning "[Get-BlenderImports] Failed to extract imports: $_"
            return @()
        }
    }
}

function Get-BlenderDependencies {
    [CmdletBinding(DefaultParameterSetName = 'Content')]
    [OutputType([array])]
    param(
        [Parameter(ParameterSetName = 'Path', Mandatory = $true)]
        [string]$Path,
        
        [Parameter(ParameterSetName = 'Content', Mandatory = $true, ValueFromPipeline = $true)]
        [string]$Content,
        
        [Parameter()]
        [array]$Imports = @()
    )
    
    process {
        try {
            if ($PSCmdlet.ParameterSetName -eq 'Path') {
                $Content = Get-Content -LiteralPath $Path -Raw -Encoding UTF8
            }
            
            if ($Imports.Count -eq 0) {
                $Imports = Get-BlenderImports -Content $Content
            }
            
            $dependencies = New-Object System.Collections.ArrayList
            
            foreach ($imp in $Imports) {
                $baseModule = $imp -split '\.' | Select-Object -First 1
                
                # Skip Blender modules and standard library
                if ($script:KnownBpyModules -contains $baseModule) { continue }
                if ($script:StdLibModules -contains $baseModule) { continue }
                if ($baseModule -eq 'bpy') { continue }
                
                [void]$dependencies.Add($baseModule)
            }
            
            return ,($dependencies | Select-Object -Unique)
        }
        catch {
            Write-Warning "[Get-BlenderDependencies] Failed to extract dependencies: $_"
            return @()
        }
    }
}

function Test-BlenderVersionCompatibility {
    [CmdletBinding(DefaultParameterSetName = 'Content')]
    [OutputType([hashtable])]
    param(
        [Parameter(ParameterSetName = 'Path', Mandatory = $true)]
        [string]$Path,
        
        [Parameter(ParameterSetName = 'Content', Mandatory = $true, ValueFromPipeline = $true)]
        [string]$Content,
        
        [Parameter()]
        [string]$TargetVersion = '4.x'
    )
    
    process {
        try {
            if ($PSCmdlet.ParameterSetName -eq 'Path') {
                $Content = Get-Content -LiteralPath $Path -Raw -Encoding UTF8
            }
            
            $blInfo = Get-BlenderAddonInfo -Content $Content
            $requiredVersion = $blInfo.blender
            
            # Parse target version
            $targetParts = $TargetVersion -split '\.'
            $targetMajor = if ($targetParts[0] -match '^\d+$') { [int]$targetParts[0] } else { 4 }
            $targetMinor = if ($targetParts.Count -gt 1 -and $targetParts[1] -match '^\d+$') { [int]$targetParts[1] } else { 0 }
            
            # Compare versions
            $compatible = $true
            $message = "Compatible"
            
            if ($requiredVersion.Count -ge 2) {
                $reqMajor = $requiredVersion[0]
                $reqMinor = $requiredVersion[1]
                
                if ($reqMajor -gt $targetMajor) {
                    $compatible = $false
                    $message = "Requires Blender $reqMajor.$reqMinor or higher"
                }
                elseif ($reqMajor -eq $targetMajor -and $reqMinor -gt $targetMinor) {
                    $compatible = $false
                    $message = "Requires Blender $reqMajor.$reqMinor or higher"
                }
            }
            
            return @{
                isCompatible = $compatible
                message = $message
                requiredVersion = $requiredVersion
                targetVersion = @($targetMajor, $targetMinor, 0)
            }
        }
        catch {
            Write-Warning "[Test-BlenderVersionCompatibility] Failed to check compatibility: $_"
            return @{
                isCompatible = $false
                message = "Error checking compatibility: $_"
                requiredVersion = @(0, 0, 0)
                targetVersion = @(0, 0, 0)
            }
        }
    }
}

# ============================================================================
# Helper Functions
# ============================================================================

function Get-ClassBlock {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Content,
        
        [Parameter(Mandatory = $true)]
        [string]$ClassName
    )
    
    try {
        $escapedName = [regex]::Escape($ClassName)
        
        # Find class definition
        $classDefMatch = [regex]::Match($Content, "(?m)^class\s+" + $escapedName + "\s*\([^)]*\):\s*$")
        
        if (-not $classDefMatch.Success) {
            return $null
        }
        
        $startPos = $classDefMatch.Index + $classDefMatch.Length
        $lines = $Content.Substring($startPos).Split("`n")
        $classLines = New-Object System.Collections.ArrayList
        
        foreach ($line in $lines) {
            if ($line.Trim() -eq "") {
                [void]$classLines.Add($line)
                continue
            }
            
            # Check indentation
            $indent = $line.Length - $line.TrimStart().Length
            
            # If we hit a line that's not indented, check if it's a new class or function
            if ($indent -lt 4 -and $line.Trim() -ne "") {
                $trimmed = $line.Trim()
                if ($trimmed -match '^class\s+' -or $trimmed -match '^def\s+register' -or $trimmed -match '^def\s+unregister') {
                    break
                }
            }
            
            [void]$classLines.Add($line)
        }
        
        return ($classLines -join "`n")
    }
    catch {
        Write-Verbose "[Get-ClassBlock] Failed to extract class block for $ClassName`: $_"
        return $null
    }
}

function Parse-OperatorClass {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$ClassName,
        
        [Parameter(Mandatory = $true)]
        [string]$ClassBlock
    )
    
    $operator = @{
        bl_idname = ""
        bl_label = ""
        bl_description = ""
        bl_options = @{}
        properties = @()
        executeMethod = ""
    }
    
    # Build regex pattern for quoted values
    $q = "[" + $script:SingleQuote + $script:DoubleQuote + "]"
    
    # Extract bl_idname
    $idMatch = [regex]::Match($ClassBlock, 'bl_idname\s*=\s*' + $q + '(.+)' + $q)
    if ($idMatch.Success) {
        $operator.bl_idname = $idMatch.Groups[1].Value
    }
    else {
        $operator.bl_idname = ConvertTo-OperatorId -ClassName $ClassName
    }
    
    # Extract bl_label
    $labelMatch = [regex]::Match($ClassBlock, 'bl_label\s*=\s*' + $q + '(.+)' + $q)
    if ($labelMatch.Success) {
        $operator.bl_label = $labelMatch.Groups[1].Value
    }
    else {
        $operator.bl_label = ConvertTo-Label -ClassName $ClassName
    }
    
    # Extract bl_description
    $descMatch = [regex]::Match($ClassBlock, 'bl_description\s*=\s*' + $q + '(.+)' + $q)
    if ($descMatch.Success) {
        $operator.bl_description = $descMatch.Groups[1].Value
    }
    
    # Extract bl_options as hashtable
    $optsMatch = [regex]::Match($ClassBlock, 'bl_options\s*=\s*\{([^}]+)\}')
    if ($optsMatch.Success) {
        $optsText = $optsMatch.Groups[1].Value
        $options = @{}
        
        # Match quoted strings
        $optMatches = [regex]::Matches($optsText, $q + '(.+)' + $q)
        foreach ($optMatch in $optMatches) {
            $optName = $optMatch.Groups[1].Value
            $options[$optName] = $true
        }
        
        $operator.bl_options = $options
    }
    
    # Extract properties
    $operator.properties = Get-BlenderProperties -Content $ClassBlock -Scope "class" -ClassBlock $ClassBlock
    
    # Extract execute method body
    $operator.executeMethod = Get-MethodBody -ClassBlock $ClassBlock -MethodName "execute"
    
    return $operator
}

function Parse-PanelClass {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$ClassName,
        
        [Parameter(Mandatory = $true)]
        [string]$ClassBlock
    )
    
    $panel = @{
        bl_idname = $ClassName
        bl_label = ""
        bl_space_type = ""
        bl_region_type = ""
        bl_category = ""
        drawMethod = ""
    }
    
    # Build regex pattern for quoted values
    $q = "[" + $script:SingleQuote + $script:DoubleQuote + "]"
    
    # Extract bl_idname
    $idMatch = [regex]::Match($ClassBlock, 'bl_idname\s*=\s*' + $q + '(.+)' + $q)
    if ($idMatch.Success) {
        $panel.bl_idname = $idMatch.Groups[1].Value
    }
    
    # Extract bl_label
    $labelMatch = [regex]::Match($ClassBlock, 'bl_label\s*=\s*' + $q + '(.+)' + $q)
    if ($labelMatch.Success) {
        $panel.bl_label = $labelMatch.Groups[1].Value
    }
    else {
        $panel.bl_label = ConvertTo-Label -ClassName $ClassName
    }
    
    # Extract bl_space_type
    $spaceMatch = [regex]::Match($ClassBlock, 'bl_space_type\s*=\s*' + $q + '(.+)' + $q)
    if ($spaceMatch.Success) {
        $panel.bl_space_type = $spaceMatch.Groups[1].Value
    }
    
    # Extract bl_region_type
    $regionMatch = [regex]::Match($ClassBlock, 'bl_region_type\s*=\s*' + $q + '(.+)' + $q)
    if ($regionMatch.Success) {
        $panel.bl_region_type = $regionMatch.Groups[1].Value
    }
    
    # Extract bl_category
    $catMatch = [regex]::Match($ClassBlock, 'bl_category\s*=\s*' + $q + '(.+)' + $q)
    if ($catMatch.Success) {
        $panel.bl_category = $catMatch.Groups[1].Value
    }
    
    # Extract draw method body
    $panel.drawMethod = Get-MethodBody -ClassBlock $ClassBlock -MethodName "draw"
    
    return $panel
}

function Get-MethodBody {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$ClassBlock,
        
        [Parameter(Mandatory = $true)]
        [string]$MethodName
    )
    
    $methodPattern = "(?m)^(\s+)def\s+" + [regex]::Escape($MethodName) + "\s*\([^)]*\):"
    $methodMatch = [regex]::Match($ClassBlock, $methodPattern)
    
    if (-not $methodMatch.Success) {
        return ""
    }
    
    $baseIndent = $methodMatch.Groups[1].Value.Length
    $startPos = $methodMatch.Index + $methodMatch.Length
    $remainingContent = $ClassBlock.Substring($startPos)
    $lines = $remainingContent.Split("`n")
    $methodLines = New-Object System.Collections.ArrayList
    
    # Skip docstring line if present
    $firstLine = $true
    
    foreach ($line in $lines) {
        if ($firstLine -and $line.Trim() -match '^["'']') {
            $firstLine = $false
            continue
        }
        
        if ($line.Trim() -eq "") {
            [void]$methodLines.Add($line)
            continue
        }
        
        $indent = $line.Length - $line.TrimStart().Length
        
        if ($indent -le $baseIndent) {
            break
        }
        
        [void]$methodLines.Add($line)
    }
    
    return ($methodLines -join "`n").Trim()
}

function Parse-PropertyArguments {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$ArgumentString
    )
    
    $args = @{}
    
    try {
        $patterns = @{
            name = '(?i)name\s*=\s*["' + $script:SingleQuote + ']([^"' + $script:SingleQuote + ']*)["' + $script:SingleQuote + ']'
            description = '(?i)description\s*=\s*["' + $script:SingleQuote + ']([^"' + $script:SingleQuote + ']*)["' + $script:SingleQuote + ']'
            default = '(?i)default\s*=\s*([^,)]+)'
            min = '(?i)min\s*=\s*(-?[\d\.]+)'
            max = '(?i)max\s*=\s*(-?[\d\.]+)'
            subtype = '(?i)subtype\s*=\s*["' + $script:SingleQuote + ']([^"' + $script:SingleQuote + ']*)["' + $script:SingleQuote + ']'
        }
        
        foreach ($key in $patterns.Keys) {
            $pattern = $patterns[$key]
            $match = [regex]::Match($ArgumentString, $pattern)
            if ($match.Success) {
                $args[$key] = $match.Groups[1].Value.Trim()
            }
        }
    }
    catch {
        Write-Verbose "[Parse-PropertyArguments] Failed to parse arguments: $_"
    }
    
    return $args
}

function Parse-OperatorParameters {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$ParameterString
    )
    
    $params = @{}
    
    try {
        $paramMatches = [regex]::Matches($ParameterString, '(\w+)\s*=\s*([^,]+)')
        foreach ($match in $paramMatches) {
            $key = $match.Groups[1].Value.Trim()
            $value = $match.Groups[2].Value.Trim()
            $params[$key] = ConvertTo-TypedValue -Value $value -PropertyType "StringProperty"
        }
    }
    catch {
        Write-Verbose "[Parse-OperatorParameters] Failed to parse parameters: $_"
    }
    
    return $params
}

function ConvertTo-TypedValue {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Value,
        
        [Parameter(Mandatory = $true)]
        [string]$PropertyType
    )
    
    $trimmed = $Value.Trim()
    
    # Handle boolean
    if ($trimmed -match '^(?i)true$') { return $true }
    if ($trimmed -match '^(?i)false$') { return $false }
    
    # Handle None/null
    if ($trimmed -match '^(?i)none$') { return $null }
    
    # Handle integers
    if ($trimmed -match '^-?\d+$' -and $PropertyType -match 'Int') {
        return [int]$trimmed
    }
    
    # Handle floats
    if ($trimmed -match '^-?\d+\.\d+$' -and $PropertyType -match 'Float') {
        return [double]$trimmed
    }
    
    # Handle quoted strings
    if ($trimmed -match '^["'']') {
        return $trimmed -replace '^["'']|["'']$'
    }
    
    # Default to string
    return $trimmed
}

function ConvertTo-OperatorId {
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory = $true)]
        [string]$ClassName
    )
    
    # Convert class name like MY_OT_operator_name to my.operator_name
    if ($ClassName -match '^([A-Z]+)_OT_(.+)$') {
        $prefix = $matches[1].ToLower()
        $name = $matches[2].ToLower() -replace '_', '_'
        return "$prefix.$name"
    }
    
    return $ClassName.ToLower()
}

function ConvertTo-Label {
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory = $true)]
        [string]$ClassName
    )
    
    # Remove prefix like MY_OT_, MY_PT_, etc.
    $name = $ClassName -replace '^[A-Z]+_[A-Z]+_', ''
    
    # Convert snake_case to Title Case
    $parts = $name -split '_'
    $label = ($parts | ForEach-Object { 
        if ($_.Length -gt 0) {
            $_.Substring(0,1).ToUpper() + $_.Substring(1).ToLower()
        }
    }) -join ' '
    
    return $label
}

# ============================================================================
# Legacy/Compatibility Functions
# ============================================================================

function ConvertFrom-BlenderPython {
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [Parameter(Mandatory = $true, ParameterSetName = "Path")]
        [string]$Path,
        
        [Parameter(Mandatory = $true, ParameterSetName = "Content")]
        [string]$Content,
        
        [Parameter()]
        [string]$BlenderVersion = "4.x",
        
        [Parameter()]
        [switch]$IncludeSource
    )
    
    process {
        $result = Invoke-BlenderPythonParse @PSBoundParameters
        
        if ($result) {
            $result['blInfo'] = $result.addonInfo
            $result['globalProperties'] = $result.properties
            $result['propertyGroups'] = @()
            $result['preferences'] = $null
            $result['keymaps'] = @()
            $result['summary'] = @{
                totalClasses = $result.operators.Count + $result.panels.Count + $result.menus.Count
                totalOperators = $result.operators.Count
                totalPanels = $result.panels.Count
                totalMenus = $result.menus.Count
                hasPreferences = $false
                hasKeymaps = $false
                totalProperties = if ($result.properties) { $result.properties.Count } else { 0 }
            }
        }
        
        return $result
    }
}

function Get-BlInfo {
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Content
    )
    
    return Get-BlenderAddonInfo -Content $Content
}

function New-BlenderAddonManifest {
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [Parameter()]
        [string]$FileName = "",
        
        [Parameter()]
        [string]$BlenderVersion = "4.x",
        
        [Parameter()]
        [hashtable]$BlInfo = $null,
        
        [Parameter()]
        [array]$Operators = @(),
        
        [Parameter()]
        [array]$Panels = @(),
        
        [Parameter()]
        [array]$Menus = @(),
        
        [Parameter()]
        [array]$PropertyGroups = @(),
        
        [Parameter()]
        [hashtable]$Preferences = $null,
        
        [Parameter()]
        [array]$Keymaps = @(),
        
        [Parameter()]
        [array]$GlobalProperties = @()
    )
    
    $manifest = @{
        fileType = "blender_addon"
        blenderVersion = $BlenderVersion
        fileName = $FileName
        parsedAt = [DateTime]::UtcNow.ToString("yyyy-MM-ddTHH:mm:ssZ", [System.Globalization.CultureInfo]::InvariantCulture)
        addonInfo = if ($BlInfo) { $BlInfo } else { $script:DefaultBlInfo.Clone() }
        blInfo = if ($BlInfo) { $BlInfo } else { @{} }
        operators = $Operators
        panels = $Panels
        menus = $Menus
        propertyGroups = $PropertyGroups
        preferences = $Preferences
        keymaps = $Keymaps
        globalProperties = $GlobalProperties
        properties = $GlobalProperties
        geometryNodes = @{ nodeGroups = @() }
        operatorCalls = @()
        imports = @()
        dependencies = @()
        sourceFile = $FileName
        compatibility = @{
            isCompatible = $true
            message = "Unknown"
            requiredVersion = @(0, 0, 0)
            targetVersion = @(0, 0, 0)
        }
        summary = @{
            totalClasses = $Operators.Count + $Panels.Count + $Menus.Count + $(if ($PropertyGroups) { $PropertyGroups.Count } else { 0 }) + $(if ($Preferences) { 1 } else { 0 })
            totalOperators = $Operators.Count
            totalPanels = $Panels.Count
            totalMenus = $Menus.Count
            totalPropertyGroups = if ($PropertyGroups) { $PropertyGroups.Count } else { 0 }
            hasPreferences = ($Preferences -ne $null)
            hasKeymaps = ($Keymaps.Count -gt 0)
            totalProperties = $GlobalProperties.Count
        }
    }
    
    return $manifest
}

# ============================================================================
# Module Exports
# ============================================================================

if ($MyInvocation.InvocationName -ne ".") { Export-ModuleMember -Function @(
    # Main API (Canonical Document Section 26.6.2)
    'Invoke-BlenderPythonParse'
    'Get-BlenderAddonInfo'
    'Get-BlenderOperators'
    'Get-BlenderPanels'
    'Get-BlenderProperties'
    'Get-BlenderOperatorCalls'
    'Get-BlenderNodeGroups'
    'Get-BlenderMenus'
    'Get-BlenderImports'
    'Get-BlenderDependencies'
    'Test-BlenderVersionCompatibility'
    
    # Legacy/Compatibility
    'ConvertFrom-BlenderPython'
    'Get-BlInfo'
    'New-BlenderAddonManifest'
)

}

