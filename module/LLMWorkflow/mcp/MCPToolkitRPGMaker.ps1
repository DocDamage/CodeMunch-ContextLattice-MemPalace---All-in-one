#requires -Version 5.1
Set-StrictMode -Version Latest

#===============================================================================
# RPG Maker MZ Integration Functions
#===============================================================================

<#
.SYNOPSIS
    Gets information about an RPG Maker MZ project.
.DESCRIPTION
    Analyzes an RPG Maker MZ project directory and returns detailed information
    including game title, plugins, database files, and project structure.
.PARAMETER ProjectPath
    The path to the RPG Maker project directory.
.OUTPUTS
    System.Management.Automation.PSCustomObject with project details.
.EXAMPLE
    PS C:\> Get-MCPRPGMakerProjectInfo -ProjectPath "./MyRPGGame"
    
    Returns detailed information about the RPG Maker project.
#>
function Get-MCPRPGMakerProjectInfo {
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory = $true)]
        [ValidateScript({ Test-Path -LiteralPath $_ })]
        [string]$ProjectPath
    )
    
    try {
        $resolvedPath = Resolve-Path -LiteralPath $ProjectPath | Select-Object -ExpandProperty Path
        
        # Check for RPG Maker project indicators
        $wwwPath = Join-Path $resolvedPath 'www'
        $jsPath = Join-Path $wwwPath 'js'
        $pluginsPath = Join-Path $jsPath 'plugins'
        $dataPath = Join-Path $wwwPath 'data'
        
        # Try to find the game project file (.rmmzproject or .rpgproject)
        $projectFile = Get-ChildItem -Path $resolvedPath -Filter '*.rmmzproject' -ErrorAction SilentlyContinue | Select-Object -First 1
        if (-not $projectFile) {
            $projectFile = Get-ChildItem -Path $resolvedPath -Filter '*.rpgproject' -ErrorAction SilentlyContinue | Select-Object -First 1
        }
        
        # Check if this is a valid RPG Maker project
        $isValidProject = (Test-Path -LiteralPath $jsPath) -and (Test-Path -LiteralPath $pluginsPath)
        
        if (-not $isValidProject) {
            return [pscustomobject]@{
                success = $false
                error = "Not a valid RPG Maker MZ/MV project: www/js/plugins folder not found"
                path = $resolvedPath
            }
        }
        
        # Read System.json for game info
        $systemInfo = @{}
        $systemJsonPath = Join-Path $dataPath 'System.json'
        $systemJsonPathMV = Join-Path $dataPath 'System.json'
        
        $actualSystemPath = if (Test-Path -LiteralPath $systemJsonPath) { 
            $systemJsonPath 
        } elseif (Test-Path -LiteralPath $systemJsonPathMV) { 
            $systemJsonPathMV 
        } else { 
            $null 
        }
        
        if ($actualSystemPath -and (Test-Path -LiteralPath $actualSystemPath)) {
            try {
                $systemJson = Get-Content -LiteralPath $actualSystemPath -Raw -Encoding UTF8 | ConvertFrom-Json
                $systemInfo['gameTitle'] = $systemJson.gameTitle
                $systemInfo['currencyUnit'] = $systemJson.currencyUnit
                $systemInfo['versionId'] = $systemJson.versionId
                $systemInfo['engineVersion'] = if ($systemJson.versionId -gt 0) { 'MZ' } else { 'MV' }
            }
            catch {
                Write-Verbose "[RPGMaker] Failed to parse System.json: $_"
            }
        }
        
        # Count plugins
        $pluginFiles = @()
        if (Test-Path -LiteralPath $pluginsPath) {
            $pluginFiles = Get-ChildItem -Path $pluginsPath -Filter '*.js' -ErrorAction SilentlyContinue
        }
        
        # Read plugins.js to get active plugin list
        $activePlugins = @()
        $pluginsJsPath = Join-Path $jsPath 'plugins.js'
        if (Test-Path -LiteralPath $pluginsJsPath) {
            try {
                $pluginsContent = Get-Content -LiteralPath $pluginsJsPath -Raw -Encoding UTF8
                # Extract plugin names from the plugins array
                if ($pluginsContent -match '\$plugins\s*=\s*(\[.*?\])') {
                    $pluginsJson = $matches[1] | ConvertFrom-Json
                    $activePlugins = $pluginsJson | Where-Object { $_.status -eq $true } | ForEach-Object { $_.name }
                }
            }
            catch {
                Write-Verbose "[RPGMaker] Failed to parse plugins.js: $_"
            }
        }
        
        # Count database files
        $databaseFiles = @()
        if (Test-Path -LiteralPath $dataPath) {
            $databaseFiles = Get-ChildItem -Path $dataPath -Filter '*.json' -ErrorAction SilentlyContinue | Select-Object -ExpandProperty Name
        }
        
        # Detect engine type
        $engineType = 'Unknown'
        $hasMZIndicators = Test-Path -LiteralPath (Join-Path $jsPath 'rmmz_core.js')
        $hasMVIndicators = Test-Path -LiteralPath (Join-Path $jsPath 'rpg_core.js')
        
        if ($hasMZIndicators) {
            $engineType = 'MZ'
        } elseif ($hasMVIndicators) {
            $engineType = 'MV'
        }
        
        return [pscustomobject]@{
            success = $true
            projectName = if ($projectFile) { $projectFile.BaseName } else { Split-Path -Leaf $resolvedPath }
            projectPath = $resolvedPath
            engineType = $engineType
            gameTitle = $systemInfo['gameTitle']
            currencyUnit = $systemInfo['currencyUnit']
            versionId = $systemInfo['versionId']
            pluginCount = $pluginFiles.Count
            activePluginCount = $activePlugins.Count
            pluginsPath = $pluginsPath
            databaseFiles = $databaseFiles
            databaseFileCount = $databaseFiles.Count
            hasProjectFile = ($projectFile -ne $null)
            lastModified = (Get-Item -LiteralPath $resolvedPath).LastWriteTimeUtc.ToString('O')
        }
    }
    catch {
        Write-MCPLog -Level ERROR -Message "Failed to get RPG Maker project info: $_"
        return [pscustomobject]@{
            success = $false
            error = $_.Exception.Message
            path = $ProjectPath
        }
    }
}

<#
.SYNOPSIS
    Lists installed plugins in an RPG Maker MZ project.
.DESCRIPTION
    Returns a list of all plugins in the project's www/js/plugins folder
    with optional detailed metadata extraction.
.PARAMETER ProjectPath
    The path to the RPG Maker project directory.
.PARAMETER IncludeDetails
    If specified, includes detailed plugin metadata from parsing.
.OUTPUTS
    System.Management.Automation.PSCustomObject[] with plugin information.
.EXAMPLE
    PS C:\> Get-MCPRPGMakerPluginList -ProjectPath "./MyRPGGame" -IncludeDetails
    
    Lists all plugins with detailed metadata.
#>
function Get-MCPRPGMakerPluginList {
    [CmdletBinding()]
    [OutputType([array])]
    param(
        [Parameter(Mandatory = $true)]
        [ValidateScript({ Test-Path -LiteralPath $_ })]
        [string]$ProjectPath,
        
        [Parameter()]
        [switch]$IncludeDetails
    )
    
    try {
        $resolvedPath = Resolve-Path -LiteralPath $ProjectPath | Select-Object -ExpandProperty Path
        $pluginsPath = Join-Path $resolvedPath 'www\js\plugins'
        
        if (-not (Test-Path -LiteralPath $pluginsPath)) {
            return [pscustomobject]@{
                success = $false
                error = "Plugins folder not found: $pluginsPath"
                plugins = @()
            }
        }
        
        # Read plugins.js for active status
        $jsPath = Join-Path $resolvedPath 'www\js'
        $pluginsJsPath = Join-Path $jsPath 'plugins.js'
        $activePlugins = @{}
        if (Test-Path -LiteralPath $pluginsJsPath) {
            try {
                $pluginsContent = Get-Content -LiteralPath $pluginsJsPath -Raw -Encoding UTF8
                if ($pluginsContent -match '\$plugins\s*=\s*(\[.*?\])') {
                    $pluginsJson = $matches[1] | ConvertFrom-Json
                    foreach ($plugin in $pluginsJson) {
                        $activePlugins[$plugin.name] = @{
                            status = $plugin.status
                            parameters = $plugin.parameters
                        }
                    }
                }
            }
            catch {
                Write-Verbose "[RPGMaker] Failed to parse plugins.js: $_"
            }
        }
        
        # Get all plugin files
        $pluginFiles = Get-ChildItem -Path $pluginsPath -Filter '*.js' | Sort-Object Name
        $plugins = [System.Collections.Generic.List[object]]::new()
        
        foreach ($file in $pluginFiles) {
            $pluginName = $file.BaseName
            $pluginInfo = [ordered]@{
                name = $pluginName
                fileName = $file.Name
                filePath = $file.FullName
                fileSize = $file.Length
                lastModified = $file.LastWriteTimeUtc.ToString('O')
                isActive = $activePlugins.ContainsKey($pluginName) -and $activePlugins[$pluginName].status
            }
            
            if ($IncludeDetails) {
                # Try to parse plugin metadata
                try {
                    $content = Get-Content -LiteralPath $file.FullName -Raw -Encoding UTF8
                    
                    # Extract basic metadata from comment block
                    if ($content -match '@plugindesc\s+(.+)') {
                        $pluginInfo['description'] = $matches[1].Trim()
                    }
                    if ($content -match '@author\s+(.+)') {
                        $pluginInfo['author'] = $matches[1].Trim()
                    }
                    if ($content -match '@version\s+(.+)') {
                        $pluginInfo['version'] = $matches[1].Trim()
                    }
                    if ($content -match '@target\s+(.+)') {
                        $pluginInfo['target'] = $matches[1].Trim()
                    }
                    if ($content -match '@url\s+(.+)') {
                        $pluginInfo['url'] = $matches[1].Trim()
                    }
                    
                    # Count parameters
                    $paramMatches = [regex]::Matches($content, '@param\s+(\w+)')
                    $pluginInfo['parameterCount'] = $paramMatches.Count
                    
                    # Count commands
                    $commandMatches = [regex]::Matches($content, '@command\s+(\w+)')
                    $pluginInfo['commandCount'] = $commandMatches.Count
                    
                    # Detect dependencies
                    $depMatches = [regex]::Matches($content, '@reqPlugin\s+(.+)')
                    $pluginInfo['dependencies'] = @($depMatches | ForEach-Object { $_.Groups[1].Value.Trim() })
                    
                    # Extract help text (limited)
                    if ($content -match '@help\s+([\s\S]*?)(?=\n\s*\*\s*@|\n\s*\*/|\Z)') {
                        $helpText = $matches[1] -replace '\n\s*\*\s*', ' '
                        $pluginInfo['helpTextPreview'] = $helpText.Substring(0, [Math]::Min(200, $helpText.Length))
                    }
                }
                catch {
                    Write-Verbose "[RPGMaker] Failed to parse plugin metadata for $($file.Name): $_"
                }
            }
            
            $plugins.Add([pscustomobject]$pluginInfo)
        }
        
        return [pscustomobject]@{
            success = $true
            projectPath = $resolvedPath
            pluginsPath = $pluginsPath
            totalCount = $plugins.Count
            activeCount = ($plugins | Where-Object { $_.isActive }).Count
            plugins = $plugins.ToArray()
        }
    }
    catch {
        Write-MCPLog -Level ERROR -Message "Failed to list RPG Maker plugins: $_"
        return [pscustomobject]@{
            success = $false
            error = $_.Exception.Message
            plugins = @()
        }
    }
}

<#
.SYNOPSIS
    Analyzes a specific RPG Maker plugin file for conflicts and metadata.
.DESCRIPTION
    Parses a plugin file and optionally checks for conflicts with other
    installed plugins based on method patches and header annotations.
.PARAMETER ProjectPath
    The path to the RPG Maker project directory.
.PARAMETER PluginName
    The name of the plugin to analyze (with or without .js extension).
.PARAMETER CheckConflicts
    If specified, checks for conflicts with other plugins.
.OUTPUTS
    System.Management.Automation.PSCustomObject with analysis results.
.EXAMPLE
    PS C:\> Invoke-MCPRPGMakerAnalyzePlugin -ProjectPath "./MyRPGGame" -PluginName "MyPlugin" -CheckConflicts
    
    Analyzes the plugin and checks for conflicts.
#>
function Invoke-MCPRPGMakerAnalyzePlugin {
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory = $true)]
        [ValidateScript({ Test-Path -LiteralPath $_ })]
        [string]$ProjectPath,
        
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$PluginName,
        
        [Parameter()]
        [switch]$CheckConflicts
    )
    
    try {
        $resolvedPath = Resolve-Path -LiteralPath $ProjectPath | Select-Object -ExpandProperty Path
        $pluginsPath = Join-Path $resolvedPath 'www\js\plugins'
        
        # Normalize plugin name
        if (-not $PluginName.EndsWith('.js')) {
            $PluginName = "$PluginName.js"
        }
        
        $pluginPath = Join-Path $pluginsPath $PluginName
        
        if (-not (Test-Path -LiteralPath $pluginPath)) {
            return [pscustomobject]@{
                success = $false
                error = "Plugin not found: $PluginName"
            }
        }
        
        # Read plugin content
        $content = Get-Content -LiteralPath $pluginPath -Raw -Encoding UTF8
        
        # Extract full metadata
        $metadata = @{
            name = [System.IO.Path]::GetFileNameWithoutExtension($PluginName)
            fileSize = (Get-Item -LiteralPath $pluginPath).Length
            lineCount = ($content -split "`r?`n").Count
        }
        
        # Parse header annotations
        if ($content -match '/\*:(.+?)(?:\*/|$)') {
            $headerBlock = $matches[1]
            
            # Extract metadata annotations
            if ($headerBlock -match '@plugindesc\s+(.+)') {
                $metadata['description'] = $matches[1].Trim()
            }
            if ($headerBlock -match '@author\s+(.+)') {
                $metadata['author'] = $matches[1].Trim()
            }
            if ($headerBlock -match '@version\s+(.+)') {
                $metadata['version'] = $matches[1].Trim()
            }
            if ($headerBlock -match '@target\s+(.+)') {
                $metadata['target'] = $matches[1].Trim()
            }
            if ($headerBlock -match '@url\s+(.+)') {
                $metadata['url'] = $matches[1].Trim()
            }
            
            # Extract parameters
            $params = @()
            $paramMatches = [regex]::Matches($headerBlock, '@param\s+(\w+)[\s\S]*?(?=@param|@command|\Z)')
            foreach ($match in $paramMatches) {
                $paramBlock = $match.Value
                $paramName = ($paramBlock | Select-String -Pattern '@param\s+(\w+)').Matches.Groups[1].Value
                $paramType = 'string'
                $paramDefault = ''
                $paramDesc = ''
                
                if ($paramBlock -match '@type\s+(.+)') {
                    $paramType = $matches[1].Trim()
                }
                if ($paramBlock -match '@default\s+(.+)') {
                    $paramDefault = $matches[1].Trim()
                }
                if ($paramBlock -match '@desc\s+(.+)') {
                    $paramDesc = $matches[1].Trim()
                }
                
                $params += @{
                    name = $paramName
                    type = $paramType
                    default = $paramDefault
                    description = $paramDesc
                }
            }
            $metadata['parameters'] = $params
            
            # Extract commands
            $commands = @()
            $commandMatches = [regex]::Matches($headerBlock, '@command\s+(\w+)[\s\S]*?(?=@command|@param|\Z)')
            foreach ($match in $commandMatches) {
                $cmdBlock = $match.Value
                $cmdName = ($cmdBlock | Select-String -Pattern '@command\s+(\w+)').Matches.Groups[1].Value
                $cmdDesc = ''
                $cmdArgs = @()
                
                if ($cmdBlock -match '@desc\s+(.+)') {
                    $cmdDesc = $matches[1].Trim()
                }
                
                # Extract command arguments
                $argMatches = [regex]::Matches($cmdBlock, '@arg\s+(\w+)')
                foreach ($argMatch in $argMatches) {
                    $cmdArgs += $argMatch.Groups[1].Value
                }
                
                $commands += @{
                    name = $cmdName
                    description = $cmdDesc
                    arguments = $cmdArgs
                }
            }
            $metadata['commands'] = $commands
            
            # Extract dependencies
            $deps = @()
            $depMatches = [regex]::Matches($headerBlock, '@(?:reqPlugin|requires?)\s+(.+)')
            foreach ($match in $depMatches) {
                $deps += $match.Groups[1].Value.Trim()
            }
            $metadata['dependencies'] = $deps
            
            # Extract conflicts
            $conflicts = @()
            $conflictMatches = [regex]::Matches($headerBlock, '@conflict\s+(.+)')
            foreach ($match in $conflictMatches) {
                $conflicts += $match.Groups[1].Value.Trim()
            }
            $metadata['explicitConflicts'] = $conflicts
            
            # Extract order requirements
            $orderAfter = @()
            $orderBefore = @()
            $afterMatches = [regex]::Matches($headerBlock, '@(?:after|orderAfter)\s+(.+)')
            foreach ($match in $afterMatches) {
                $orderAfter += $match.Groups[1].Value.Trim()
            }
            $beforeMatches = [regex]::Matches($headerBlock, '@(?:before|orderBefore)\s+(.+)')
            foreach ($match in $beforeMatches) {
                $orderBefore += $match.Groups[1].Value.Trim()
            }
            $metadata['orderAfter'] = $orderAfter
            $metadata['orderBefore'] = $orderBefore
        }
        
        # Extract method patches for conflict detection
        $methodPatches = @()
        $aliasPattern = '(\w+)\.(\w+)\s*=\s*Game_(\w+)\.(\w+)'
        $overwritePattern = '(\w+)\.prototype\.(\w+)\s*=\s*function'
        
        $aliasMatches = [regex]::Matches($content, $aliasPattern)
        foreach ($match in $aliasMatches) {
            $methodPatches += @{
                type = 'alias'
                target = "$($match.Groups[1].Value).$($match.Groups[2].Value)"
                source = "Game_$($match.Groups[3].Value).$($match.Groups[4].Value)"
            }
        }
        
        $overwriteMatches = [regex]::Matches($content, $overwritePattern)
        foreach ($match in $overwriteMatches) {
            $methodPatches += @{
                type = 'overwrite'
                target = "$($match.Groups[1].Value).prototype.$($match.Groups[2].Value)"
            }
        }
        
        $metadata['methodPatches'] = $methodPatches
        
        # Check conflicts with other plugins
        $conflictAnalysis = @()
        if ($CheckConflicts) {
            $otherPlugins = Get-ChildItem -Path $pluginsPath -Filter '*.js' | Where-Object { $_.Name -ne $PluginName }
            
            foreach ($otherPlugin in $otherPlugins) {
                $otherContent = Get-Content -LiteralPath $otherPlugin.FullName -Raw -Encoding UTF8
                $otherName = $otherPlugin.BaseName
                $conflictsFound = @()
                
                # Check for explicit conflicts
                if ($metadata['explicitConflicts'] -contains $otherName) {
                    $conflictsFound += 'explicit_conflict'
                }
                
                # Check for method patch overlaps
                foreach ($patch in $methodPatches) {
                    $targetPattern = [regex]::Escape($patch.target)
                    if ($otherContent -match $targetPattern) {
                        $conflictsFound += "method_overlap:$($patch.target)"
                    }
                }
                
                if ($conflictsFound.Count -gt 0) {
                    $conflictAnalysis += @{
                        plugin = $otherName
                        conflictTypes = $conflictsFound
                    }
                }
            }
        }
        
        return [pscustomobject]@{
            success = $true
            pluginPath = $pluginPath
            metadata = $metadata
            conflictCount = $conflictAnalysis.Count
            conflicts = $conflictAnalysis
            analysisTimestamp = [DateTime]::UtcNow.ToString('O')
        }
    }
    catch {
        Write-MCPLog -Level ERROR -Message "Failed to analyze RPG Maker plugin: $_"
        return [pscustomobject]@{
            success = $false
            error = $_.Exception.Message
        }
    }
}

<#
.SYNOPSIS
    Creates a new RPG Maker MZ plugin file with proper header.
.DESCRIPTION
    Generates a new plugin file with the standard RPG Maker MZ plugin header
    format including all required annotations.
.PARAMETER ProjectPath
    The path to the RPG Maker project directory.
.PARAMETER PluginName
    The name of the new plugin.
.PARAMETER Author
    The plugin author name.
.PARAMETER Description
    The plugin description.
.PARAMETER Target
    The target engine (MZ, MV, or Both).
.OUTPUTS
    System.Management.Automation.PSCustomObject with creation result.
.EXAMPLE
    PS C:\> Invoke-MCPRPGMakerCreatePluginSkeleton -ProjectPath "./MyRPGGame" -PluginName "MyNewPlugin" -Author "Developer"
    
    Creates a new plugin skeleton file.
#>
function Invoke-MCPRPGMakerCreatePluginSkeleton {
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory = $true)]
        [ValidateScript({ Test-Path -LiteralPath $_ })]
        [string]$ProjectPath,
        
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$PluginName,
        
        [Parameter()]
        [string]$Author = '',
        
        [Parameter()]
        [string]$Description = '',
        
        [Parameter()]
        [ValidateSet('MZ', 'MV', 'Both')]
        [string]$Target = 'MZ'
    )
    
    # Check execution mode
    Assert-MCPExecutionMode -ToolName 'rpgmaker_create_plugin_skeleton' -CurrentMode $script:ServerState.ExecutionMode
    
    try {
        $resolvedPath = Resolve-Path -LiteralPath $ProjectPath | Select-Object -ExpandProperty Path
        $pluginsPath = Join-Path $resolvedPath 'www\js\plugins'
        
        if (-not (Test-Path -LiteralPath $pluginsPath)) {
            return [pscustomobject]@{
                success = $false
                error = "Plugins folder not found: $pluginsPath"
            }
        }
        
        # Normalize plugin name
        $baseName = $PluginName -replace '\.js$', ''
        $fileName = "$baseName.js"
        $pluginPath = Join-Path $pluginsPath $fileName
        
        # Check if file already exists
        if (Test-Path -LiteralPath $pluginPath) {
            return [pscustomobject]@{
                success = $false
                error = "Plugin already exists: $fileName"
            }
        }
        
        # Get current date
        $currentDate = Get-Date -Format "yyyy-MM-dd"
        
        # Build plugin header
        $authorText = if ($Author) { $Author } else { 'Your Name' }
        $descText = if ($Description) { $Description } else { "Description of $baseName" }
        
        $pluginContent = @"
//=============================================================================
// $baseName
//=============================================================================

/*:
 * @target $Target
 * @plugindesc $descText
 * @author $authorText
 * @url 
 *
 * @help
 * $baseName
 * ============================================================================
 * $descText
 *
 * ============================================================================
 * Plugin Parameters
 * ============================================================================
 *
 * @param ExampleParam
 * @text Example Parameter
 * @type string
 * @default Hello World
 * @desc An example parameter to get you started
 *
 * ============================================================================
 * Plugin Commands
 * ============================================================================
 *
 * @command ExampleCommand
 * @text Example Command
 * @desc An example plugin command
 *
 * @arg ExampleArg
 * @type string
 * @default test
 * @desc An example argument
 */

(function() {
    'use strict';

    // Plugin parameters
    const pluginName = '$baseName';
    const parameters = PluginManager.parameters(pluginName);
    const paramExample = String(parameters['ExampleParam'] || 'Hello World');

    // Plugin command registration
    PluginManager.registerCommand(pluginName, 'ExampleCommand', args => {
        const argValue = String(args.ExampleArg || 'test');
        console.log(`[\${pluginName}] ExampleCommand executed with arg: \${argValue}`);
    });

    // Your plugin code here
    const _Scene_Boot_start = Scene_Boot.prototype.start;
    Scene_Boot.prototype.start = function() {
        _Scene_Boot_start.call(this);
        console.log(`[\${pluginName}] Loaded with param: \${paramExample}`);
    };

})();
"@
        
        # Write the plugin file
        $pluginContent | Set-Content -LiteralPath $pluginPath -Encoding UTF8 -NoNewline
        
        Write-MCPLog -Level INFO -Message "Created RPG Maker plugin skeleton" -Metadata @{
            pluginName = $baseName
            pluginPath = $pluginPath
            author = $authorText
            target = $Target
        }
        
        return [pscustomobject]@{
            success = $true
            pluginName = $baseName
            pluginPath = $pluginPath
            fileName = $fileName
            author = $authorText
            target = $Target
            message = "Plugin '$baseName' created successfully at $pluginPath"
        }
    }
    catch {
        Write-MCPLog -Level ERROR -Message "Failed to create RPG Maker plugin skeleton: $_"
        return [pscustomobject]@{
            success = $false
            error = $_.Exception.Message
        }
    }
}

<#
.SYNOPSIS
    Validates notetag syntax in RPG Maker MZ database files.
.DESCRIPTION
    Parses RPG Maker database JSON files and validates notetag syntax
    in note fields, checking for common issues like unclosed tags,
    invalid characters, or malformed syntax.
.PARAMETER ProjectPath
    The path to the RPG Maker project directory.
.PARAMETER DatabaseFile
    Specific database file to validate (e.g., Actors.json, Items.json).
    If not specified, validates all database files.
.OUTPUTS
    System.Management.Automation.PSCustomObject with validation results.
.EXAMPLE
    PS C:\> Test-MCPRPGMakerNotetags -ProjectPath "./MyRPGGame" -DatabaseFile "Actors.json"
    
    Validates notetags in the Actors.json file.
#>
function Test-MCPRPGMakerNotetags {
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory = $true)]
        [ValidateScript({ Test-Path -LiteralPath $_ })]
        [string]$ProjectPath,
        
        [Parameter()]
        [string]$DatabaseFile = ''
    )
    
    try {
        $resolvedPath = Resolve-Path -LiteralPath $ProjectPath | Select-Object -ExpandProperty Path
        $dataPath = Join-Path $resolvedPath 'www\data'
        
        if (-not (Test-Path -LiteralPath $dataPath)) {
            return [pscustomobject]@{
                success = $false
                error = "Data folder not found: $dataPath"
            }
        }
        
        # Determine which files to validate
        $databaseFiles = @()
        if ($DatabaseFile) {
            $targetFile = Join-Path $dataPath $DatabaseFile
            if (Test-Path -LiteralPath $targetFile) {
                $databaseFiles += Get-Item -LiteralPath $targetFile
            } else {
                return [pscustomobject]@{
                    success = $false
                    error = "Database file not found: $DatabaseFile"
                }
            }
        } else {
            # Validate all database JSON files
            $databaseFiles = Get-ChildItem -Path $dataPath -Filter '*.json' | Where-Object { 
                $_.Name -in @('Actors.json', 'Classes.json', 'Skills.json', 'Items.json', 
                              'Weapons.json', 'Armors.json', 'Enemies.json', 'Troops.json', 
                              'States.json', 'Animations.json', 'Tilesets.json', 'CommonEvents.json',
                              'Map001.json', 'Map002.json', 'Map003.json', 'Map004.json', 'Map005.json')
            }
        }
        
        $results = [System.Collections.Generic.List[object]]::new()
        $totalErrors = 0
        $totalWarnings = 0
        
        foreach ($file in $databaseFiles) {
            $fileResults = @{
                fileName = $file.Name
                filePath = $file.FullName
                entriesChecked = 0
                errors = @()
                warnings = @()
            }
            
            try {
                $jsonContent = Get-Content -LiteralPath $file.FullName -Raw -Encoding UTF8
                $data = $jsonContent | ConvertFrom-Json
                
                # Function to check notetags in an object
                function Check-Notetags {
                    param($Obj, $EntryId)
                    $issues = @{
                        errors = @()
                        warnings = @()
                    }
                    
                    if ($Obj -is [PSCustomObject]) {
                        # Check note field
                        if ($Obj.PSObject.Properties['note']) {
                            $note = $Obj.note
                            if ($note -and $note -is [string]) {
                                # Check for unclosed XML-style tags
                                $openTags = [regex]::Matches($note, '<(\w+)[^>]*>') | Where-Object { $_.Value -notmatch '/\s*>' }
                                $closeTags = [regex]::Matches($note, '</(\w+)>')
                                
                                $openTagNames = $openTags | ForEach-Object { 
                                    if ($_ -match '<(\w+)') { $matches[1] }
                                }
                                $closeTagNames = $closeTags | ForEach-Object { 
                                    if ($_ -match '</(\w+)') { $matches[1] }
                                }
                                
                                foreach ($tagName in $openTagNames) {
                                    if ($tagName -notin $closeTagNames -and $tagName -notin @('br', 'hr', 'img', 'meta')) {
                                        $issues.warnings += "Entry $EntryId`: Unclosed tag <$tagName>"
                                    }
                                }
                                
                                # Check for malformed RPG Maker notetags
                                $notetagMatches = [regex]::Matches($note, '<(\w+)(:[^>]*)?>')
                                foreach ($match in $notetagMatches) {
                                    $tagContent = $match.Groups[2].Value
                                    # Check for unbalanced quotes in tag parameters
                                    $quoteCount = ($tagContent -split '"').Count - 1
                                    if ($quoteCount % 2 -ne 0) {
                                        $issues.errors += "Entry $EntryId`: Unbalanced quotes in notetag: $($match.Value)"
                                    }
                                }
                                
                                # Check for common typo patterns
                                if ($note -match '<\s*\w+\s*:') {
                                    # Has RPG Maker style notetags, check format
                                    $malformed = [regex]::Matches($note, '<\s*\w+\s*:[^>]+[^/>]\s*>')
                                    foreach ($match in $malformed) {
                                        if ($match.Value -notmatch '/>') {
                                            $issues.warnings += "Entry $EntryId`: Notetag may be missing closing '/>': $($match.Value)"
                                        }
                                    }
                                }
                            }
                        }
                        
                        # Recursively check nested objects (for things like effects, traits)
                        foreach ($prop in $Obj.PSObject.Properties) {
                            if ($prop.Value -is [array]) {
                                for ($i = 0; $i -lt $prop.Value.Count; $i++) {
                                    $nestedIssues = Check-Notetags -Obj $prop.Value[$i] -EntryId "$EntryId.$($prop.Name)[$i]"
                                    $issues.errors += $nestedIssues.errors
                                    $issues.warnings += $nestedIssues.warnings
                                }
                            }
                        }
                    }
                    
                    return $issues
                }
                
                # Process array entries (skip null entries at index 0)
                if ($data -is [array]) {
                    for ($i = 1; $i -lt $data.Count; $i++) {
                        if ($data[$i]) {
                            $fileResults.entriesChecked++
                            $entryIssues = Check-Notetags -Obj $data[$i] -EntryId $i
                            $fileResults.errors += $entryIssues.errors
                            $fileResults.warnings += $entryIssues.warnings
                        }
                    }
                }
            }
            catch {
                $fileResults.errors += "Failed to parse file: $_"
            }
            
            $fileResults.errorCount = $fileResults.errors.Count
            $fileResults.warningCount = $fileResults.warnings.Count
            $totalErrors += $fileResults.errorCount
            $totalWarnings += $fileResults.warningCount
            
            $results.Add([pscustomobject]$fileResults)
        }
        
        return [pscustomobject]@{
            success = $true
            projectPath = $resolvedPath
            filesChecked = $results.Count
            totalErrors = $totalErrors
            totalWarnings = $totalWarnings
            hasIssues = ($totalErrors -gt 0 -or $totalWarnings -gt 0)
            results = $results.ToArray()
            validationTimestamp = [DateTime]::UtcNow.ToString('O')
        }
    }
    catch {
        Write-MCPLog -Level ERROR -Message "Failed to validate RPG Maker notetags: $_"
        return [pscustomobject]@{
            success = $false
            error = $_.Exception.Message
        }
    }
}

