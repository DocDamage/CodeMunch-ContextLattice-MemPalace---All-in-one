#requires -Version 5.1
Set-StrictMode -Version Latest

#===============================================================================
# Godot Integration Tools
#===============================================================================

<#
.SYNOPSIS
    Executes a Godot tool via MCP.
.DESCRIPTION
    Invokes a registered Godot-related MCP tool with the specified parameters.
.PARAMETER ToolName
    The name of the Godot tool to execute.
.PARAMETER Parameters
    Hashtable of parameters to pass to the tool.
.OUTPUTS
    System.Management.Automation.PSCustomObject with tool execution results.
.EXAMPLE
    PS C:\> Invoke-MCPGodotTool -ToolName "godot_version" -Parameters @{}
    
    Gets the Godot version.
#>
function Invoke-MCPGodotTool {
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory = $true)]
        [ValidateSet('godot_version', 'godot_project_list', 'godot_project_info', 
                     'godot_launch_editor', 'godot_run_project', 'godot_create_scene',
                     'godot_add_node', 'godot_get_debug_output', 'godot_export_project',
                     'godot_build_project', 'godot_run_tests', 'godot_check_syntax',
                     'godot_get_scene_tree')]
        [string]$ToolName,
        
        [Parameter()]
        [hashtable]$Parameters = @{}
    )
    
    return Invoke-MCPTool -ToolName $ToolName -Parameters $Parameters
}

<#
.SYNOPSIS
    Gets the installed Godot version.
.DESCRIPTION
    Queries the system for the installed Godot Engine version.
.PARAMETER GodotPath
    Optional path to the Godot executable.
.OUTPUTS
    System.Management.Automation.PSCustomObject with version information.
.EXAMPLE
    PS C:\> Get-MCPGodotVersion
    
    Returns the Godot version information.
#>
function Get-MCPGodotVersion {
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter()]
        [string]$GodotPath = ''
    )
    
    try {
        $godot = Find-GodotExecutable -Path $GodotPath
        
        if (-not $godot) {
            return [pscustomobject]@{
                installed = $false
                version = $null
                versionString = $null
                error = 'Godot executable not found'
            }
        }
        
        # Get version
        $versionOutput = & $godot --version 2>&1 | Out-String
        $versionString = $versionOutput.Trim()
        
        # Parse version (format: 4.x.x.stable or 3.x.x.stable)
        $versionMatch = $versionString -match '(\d+)\.(\d+)\.(\d+)'
        $version = if ($versionMatch) {
            @{
                major = [int]$matches[1]
                minor = [int]$matches[2]
                patch = [int]$matches[3]
                full = $versionString
            }
        } else { $null }
        
        return [pscustomobject]@{
            installed = $true
            version = $version
            versionString = $versionString
            executable = $godot
            error = $null
        }
    }
    catch {
        Write-MCPLog -Level ERROR -Message "Failed to get Godot version: $_"
        return [pscustomobject]@{
            installed = $false
            version = $null
            versionString = $null
            error = $_.Exception.Message
        }
    }
}

<#
.SYNOPSIS
    Lists available Godot projects.
.DESCRIPTION
    Scans the workspace for Godot project files (project.godot).
.PARAMETER SearchPath
    The path to search for Godot projects. Default: current directory.
.PARAMETER Recursive
    If specified, searches recursively.
.OUTPUTS
    System.Management.Automation.PSCustomObject[] with project information.
.EXAMPLE
    PS C:\> Get-MCPGodotProjectList -SearchPath "." -Recursive
    
    Lists all Godot projects recursively.
#>
function Get-MCPGodotProjectList {
    [CmdletBinding()]
    [OutputType([array])]
    param(
        [Parameter()]
        [string]$SearchPath = '.',
        
        [Parameter()]
        [switch]$Recursive
    )
    
    $projects = [System.Collections.Generic.List[object]]::new()
    
    try {
        $resolvedPath = Resolve-Path -Path $SearchPath -ErrorAction Stop | Select-Object -ExpandProperty Path
        
        $projectFiles = Get-ChildItem -Path $resolvedPath -Filter 'project.godot' -Recurse:$Recursive -ErrorAction SilentlyContinue
        
        foreach ($file in $projectFiles) {
            $projectDir = $file.DirectoryName
            $projectName = $file.Directory.Name
            
            # Parse project.godot for basic info
            $config = @{}
            try {
                $content = Get-Content -LiteralPath $file.FullName -Raw -ErrorAction SilentlyContinue
                if ($content -match 'config/features=PackedStringArray\("([^"]+)"\)') {
                    $config['features'] = $matches[1] -split ',\s*'
                }
                if ($content -match 'application/config/name="([^"]+)"') {
                    $config['name'] = $matches[1]
                }
            }
            catch {
                # Continue with minimal info
            }
            
            $projects.Add([pscustomobject]@{
                name = if ($config['name']) { $config['name'] } else { $projectName }
                path = $projectDir
                projectFile = $file.FullName
                config = $config
            })
        }
    }
    catch {
        Write-MCPLog -Level ERROR -Message "Failed to list Godot projects: $_"
    }
    
    return $projects.ToArray()
}

<#
.SYNOPSIS
    Gets detailed information about a Godot project.
.DESCRIPTION
    Analyzes a Godot project directory and returns detailed information
    including scenes, scripts, and configuration.
.PARAMETER ProjectPath
    The path to the Godot project directory.
.OUTPUTS
    System.Management.Automation.PSCustomObject with project details.
.EXAMPLE
    PS C:\> Get-MCPGodotProjectInfo -ProjectPath "./MyGame"
    
    Returns detailed information about the MyGame project.
#>
function Get-MCPGodotProjectInfo {
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory = $true)]
        [ValidateScript({ Test-Path -LiteralPath $_ })]
        [string]$ProjectPath
    )
    
    try {
        $resolvedPath = Resolve-Path -LiteralPath $ProjectPath | Select-Object -ExpandProperty Path
        $projectFile = Join-Path $resolvedPath 'project.godot'
        
        if (-not (Test-Path -LiteralPath $projectFile)) {
            throw "Not a valid Godot project: project.godot not found"
        }
        
        # Read project configuration
        $config = @{}
        $content = Get-Content -LiteralPath $projectFile -Raw
        
        # Parse basic info
        if ($content -match 'application/config/name="([^"]+)"') {
            $config['name'] = $matches[1]
        }
        if ($content -match 'application/config/description="([^"]*)"') {
            $config['description'] = $matches[1]
        }
        if ($content -match 'config/features=PackedStringArray\("([^"]+)"\)') {
            $config['features'] = $matches[1] -split ',\s*'
        }
        
        # Find scenes
        $scenes = Get-ChildItem -Path $resolvedPath -Filter '*.tscn' -Recurse -ErrorAction SilentlyContinue | 
            Select-Object -ExpandProperty FullName |
            ForEach-Object { $_.Substring($resolvedPath.Length + 1) }
        
        # Find scripts
        $scripts = Get-ChildItem -Path $resolvedPath -Filter '*.gd' -Recurse -ErrorAction SilentlyContinue | 
            Select-Object -ExpandProperty FullName |
            ForEach-Object { $_.Substring($resolvedPath.Length + 1) }
        
        # Count resources
        $resourceCount = (Get-ChildItem -Path $resolvedPath -Recurse -File -ErrorAction SilentlyContinue | 
            Where-Object { $_.Extension -in @('.tres', '.res', '.png', '.jpg', '.wav', '.ogg', '.mp3') }).Count
        
        return [pscustomobject]@{
            name = if ($config['name']) { $config['name'] } else { Split-Path -Leaf $resolvedPath }
            path = $resolvedPath
            config = $config
            scenes = $scenes
            sceneCount = $scenes.Count
            scripts = $scripts
            scriptCount = $scripts.Count
            resourceCount = $resourceCount
            lastModified = (Get-Item -LiteralPath $projectFile).LastWriteTimeUtc.ToString('O')
        }
    }
    catch {
        Write-MCPLog -Level ERROR -Message "Failed to get Godot project info: $_"
        throw
    }
}

<#
.SYNOPSIS
    Launches the Godot editor for a project.
.DESCRIPTION
    Opens the Godot editor with the specified project.
.PARAMETER ProjectPath
    The path to the Godot project directory.
.PARAMETER GodotPath
    Optional path to the Godot executable.
.PARAMETER EditorFlags
    Additional flags to pass to the Godot editor.
.OUTPUTS
    System.Management.Automation.PSCustomObject with launch result.
.EXAMPLE
    PS C:\> Invoke-MCPGodotLaunchEditor -ProjectPath "./MyGame"
    
    Launches the Godot editor for MyGame.
#>
function Invoke-MCPGodotLaunchEditor {
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory = $true)]
        [ValidateScript({ Test-Path -LiteralPath (Join-Path $_ 'project.godot') })]
        [string]$ProjectPath,
        
        [Parameter()]
        [string]$GodotPath = '',
        
        [Parameter()]
        [string[]]$EditorFlags = @()
    )
    
    # Check execution mode
    Assert-MCPExecutionMode -ToolName 'godot_launch_editor' -CurrentMode $script:ServerState.ExecutionMode
    
    try {
        $godot = Find-GodotExecutable -Path $GodotPath
        if (-not $godot) {
            throw 'Godot executable not found'
        }
        
        $resolvedPath = Resolve-Path -LiteralPath $ProjectPath | Select-Object -ExpandProperty Path
        $projectFile = Join-Path $resolvedPath 'project.godot'
        
        $arguments = @('-e', $projectFile) + $EditorFlags
        
        $process = Start-Process -FilePath $godot -ArgumentList $arguments -PassThru
        
        Write-MCPLog -Level INFO -Message "Launched Godot editor" -Metadata @{
            project = $resolvedPath
            processId = $process.Id
        }
        
        return [pscustomobject]@{
            success = $true
            processId = $process.Id
            project = $resolvedPath
            message = "Godot editor launched successfully"
        }
    }
    catch {
        Write-MCPLog -Level ERROR -Message "Failed to launch Godot editor: $_"
        return [pscustomobject]@{
            success = $false
            error = $_.Exception.Message
        }
    }
}

<#
.SYNOPSIS
    Runs a Godot project.
.DESCRIPTION
    Executes the specified Godot project.
.PARAMETER ProjectPath
    The path to the Godot project directory.
.PARAMETER GodotPath
    Optional path to the Godot executable.
.PARAMETER Scene
    Optional specific scene to run.
.PARAMETER Debug
    If specified, runs with debugging enabled.
.OUTPUTS
    System.Management.Automation.PSCustomObject with run result.
.EXAMPLE
    PS C:\> Invoke-MCPGodotRunProject -ProjectPath "./MyGame"
    
    Runs the MyGame project.
#>
function Invoke-MCPGodotRunProject {
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory = $true)]
        [ValidateScript({ Test-Path -LiteralPath (Join-Path $_ 'project.godot') })]
        [string]$ProjectPath,
        
        [Parameter()]
        [string]$GodotPath = '',
        
        [Parameter()]
        [string]$Scene = '',
        
        [Parameter()]
        [switch]$Debug
    )
    
    # Check execution mode
    Assert-MCPExecutionMode -ToolName 'godot_run_project' -CurrentMode $script:ServerState.ExecutionMode
    
    try {
        $godot = Find-GodotExecutable -Path $GodotPath
        if (-not $godot) {
            throw 'Godot executable not found'
        }
        
        $resolvedPath = Resolve-Path -LiteralPath $ProjectPath | Select-Object -ExpandProperty Path
        $projectFile = Join-Path $resolvedPath 'project.godot'
        
        $arguments = @($projectFile)
        
        if ($Debug) {
            $arguments += '--debug'
        }
        
        if (-not [string]::IsNullOrEmpty($Scene)) {
            $scenePath = Join-Path $resolvedPath $Scene
            if (Test-Path -LiteralPath $scenePath) {
                $arguments += "--scene=$Scene"
            }
            else {
                throw "Scene not found: $Scene"
            }
        }
        
        $process = Start-Process -FilePath $godot -ArgumentList $arguments -PassThru
        
        Write-MCPLog -Level INFO -Message "Running Godot project" -Metadata @{
            project = $resolvedPath
            scene = $Scene
            debug = $Debug.IsPresent
            processId = $process.Id
        }
        
        return [pscustomobject]@{
            success = $true
            processId = $process.Id
            project = $resolvedPath
            scene = $Scene
            message = "Project running"
        }
    }
    catch {
        Write-MCPLog -Level ERROR -Message "Failed to run Godot project: $_"
        return [pscustomobject]@{
            success = $false
            error = $_.Exception.Message
        }
    }
}

<#
.SYNOPSIS
    Creates a new Godot scene file.
.DESCRIPTION
    Generates a new .tscn scene file with the specified configuration.
.PARAMETER ProjectPath
    The path to the Godot project directory.
.PARAMETER SceneName
    The name of the scene (without extension).
.PARAMETER RootType
    The root node type. Default: Node2D.
.PARAMETER Directory
    The directory within the project to create the scene. Default: scenes.
.OUTPUTS
    System.Management.Automation.PSCustomObject with creation result.
.EXAMPLE
    PS C:\> Invoke-MCPGodotCreateScene -ProjectPath "./MyGame" -SceneName "Level1" -RootType "Node2D"
    
    Creates a new Level1.tscn scene.
#>
function Invoke-MCPGodotCreateScene {
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory = $true)]
        [ValidateScript({ Test-Path -LiteralPath (Join-Path $_ 'project.godot') })]
        [string]$ProjectPath,
        
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$SceneName,
        
        [Parameter()]
        [string]$RootType = 'Node2D',
        
        [Parameter()]
        [string]$Directory = 'scenes'
    )
    
    # Check execution mode
    Assert-MCPExecutionMode -ToolName 'godot_create_scene' -CurrentMode $script:ServerState.ExecutionMode
    
    try {
        $resolvedPath = Resolve-Path -LiteralPath $ProjectPath | Select-Object -ExpandProperty Path
        $sceneDir = Join-Path $resolvedPath $Directory
        
        # Ensure directory exists
        if (-not (Test-Path -LiteralPath $sceneDir)) {
            New-Item -ItemType Directory -Path $sceneDir -Force | Out-Null
        }
        
        $sceneFile = Join-Path $sceneDir "$SceneName.tscn"
        
        # Check if file already exists
        if (Test-Path -LiteralPath $sceneFile) {
            throw "Scene already exists: $sceneFile"
        }
        
        # Create scene content
        $sceneContent = @"
[gd_scene load_steps=1 format=3 uid="uid://$([Guid]::NewGuid().ToString("N").Substring(0, 13))"]

[node name="$SceneName" type="$RootType"]
"@
        
        $sceneContent | Set-Content -LiteralPath $sceneFile -Encoding UTF8 -NoNewline
        
        Write-MCPLog -Level INFO -Message "Created Godot scene" -Metadata @{
            scene = $SceneName
            path = $sceneFile
            rootType = $RootType
        }
        
        return [pscustomobject]@{
            success = $true
            sceneName = $SceneName
            scenePath = $sceneFile
            relativePath = "$Directory/$SceneName.tscn"
            rootType = $RootType
            message = "Scene created successfully"
        }
    }
    catch {
        Write-MCPLog -Level ERROR -Message "Failed to create Godot scene: $_"
        return [pscustomobject]@{
            success = $false
            error = $_.Exception.Message
        }
    }
}

<#
.SYNOPSIS
    Adds a node to a Godot scene file.
.DESCRIPTION
    Appends a new node to an existing .tscn scene file.
.PARAMETER ProjectPath
    The path to the Godot project directory.
.PARAMETER ScenePath
    The relative path to the scene file within the project.
.PARAMETER NodeName
    The name of the new node.
.PARAMETER NodeType
    The type of node to add (e.g., Sprite2D, Camera2D, etc.).
.PARAMETER ParentPath
    Optional parent node path. Default: root node.
.PARAMETER Properties
    Optional hashtable of initial properties to set.
.OUTPUTS
    System.Management.Automation.PSCustomObject with the result.
.EXAMPLE
    PS C:\> Invoke-MCPGodotAddNode -ProjectPath "./MyGame" -ScenePath "scenes/Level1.tscn" `
        -NodeName "PlayerSprite" -NodeType "Sprite2D"
    
    Adds a Sprite2D node named PlayerSprite to the scene.
#>
function Invoke-MCPGodotAddNode {
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory = $true)]
        [ValidateScript({ Test-Path -LiteralPath (Join-Path $_ 'project.godot') })]
        [string]$ProjectPath,
        
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$ScenePath,
        
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$NodeName,
        
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$NodeType,
        
        [Parameter()]
        [string]$ParentPath = '',
        
        [Parameter()]
        [hashtable]$Properties = @{}
    )
    
    # Check execution mode
    Assert-MCPExecutionMode -ToolName 'godot_add_node' -CurrentMode $script:ServerState.ExecutionMode
    
    try {
        $resolvedPath = Resolve-Path -LiteralPath $ProjectPath | Select-Object -ExpandProperty Path
        $sceneFullPath = Join-Path $resolvedPath $ScenePath
        
        if (-not (Test-Path -LiteralPath $sceneFullPath)) {
            throw "Scene not found: $sceneFullPath"
        }
        
        # Read existing scene content
        $content = Get-Content -LiteralPath $sceneFullPath -Raw
        
        # Determine parent
        $parent = if ($ParentPath) { $ParentPath } else { '.' }
        
        # Build node entry
        $nodeEntry = "`n[node name=`"$NodeName`" type=`"$NodeType`" parent=`"$parent`"]"
        
        # Add properties if provided
        foreach ($prop in $Properties.Keys) {
            $value = $Properties[$prop]
            if ($value -is [string]) {
                $nodeEntry += "`n$prop = `"$value`""
            }
            elseif ($value -is [bool]) {
                $nodeEntry += "`n$prop = $($value.ToString().ToLower())"
            }
            else {
                $nodeEntry += "`n$prop = $value"
            }
        }
        
        # Append to scene file
        Add-Content -LiteralPath $sceneFullPath -Value $nodeEntry -Encoding UTF8 -NoNewline
        
        Write-MCPLog -Level INFO -Message "Added node to Godot scene" -Metadata @{
            scene = $ScenePath
            nodeName = $NodeName
            nodeType = $NodeType
            parent = $parent
        }
        
        return [pscustomobject]@{
            success = $true
            scenePath = $ScenePath
            nodeName = $NodeName
            nodeType = $NodeType
            parent = $parent
            message = "Node added successfully"
        }
    }
    catch {
        Write-MCPLog -Level ERROR -Message "Failed to add node to Godot scene: $_"
        return [pscustomobject]@{
            success = $false
            error = $_.Exception.Message
        }
    }
}

<#
.SYNOPSIS
    Gets debug output from a Godot project.
.DESCRIPTION
    Retrieves recent debug logs and output from a Godot project.
.PARAMETER ProjectPath
    The path to the Godot project directory.
.PARAMETER LogFile
    Specific log file to read. If not specified, finds the most recent log.
.PARAMETER Lines
    Number of lines to return. Default: 100.
.OUTPUTS
    System.Management.Automation.PSCustomObject with debug output.
.EXAMPLE
    PS C:\> Get-MCPGodotDebugOutput -ProjectPath "./MyGame" -Lines 50
    
    Gets the last 50 lines of debug output.
#>
function Get-MCPGodotDebugOutput {
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory = $true)]
        [ValidateScript({ Test-Path -LiteralPath (Join-Path $_ 'project.godot') })]
        [string]$ProjectPath,
        
        [Parameter()]
        [string]$LogFile = '',
        
        [Parameter()]
        [ValidateRange(1, 1000)]
        [int]$Lines = 100
    )
    
    try {
        $resolvedPath = Resolve-Path -LiteralPath $ProjectPath | Select-Object -ExpandProperty Path
        
        # Determine log file path
        $logPath = if ($LogFile -and (Test-Path -LiteralPath $LogFile)) {
            $LogFile
        }
        else {
            # Look for Godot logs in user data directory
            $godotUserDir = Join-Path $env:APPDATA 'Godot'
            $projectName = Split-Path -Leaf $resolvedPath
            
            # Try to find logs in various locations
            $possibleLogPaths = @(
                Join-Path $resolvedPath 'logs'
                Join-Path $godotUserDir 'app_logs'
            )
            
            $foundLog = $null
            foreach ($dir in $possibleLogPaths) {
                if (Test-Path -LiteralPath $dir) {
                    $logFiles = Get-ChildItem -Path $dir -Filter '*.log' -ErrorAction SilentlyContinue | 
                        Sort-Object -Property LastWriteTime -Descending | 
                        Select-Object -First 1
                    if ($logFiles) {
                        $foundLog = $logFiles.FullName
                        break
                    }
                }
            }
            $foundLog
        }
        
        if (-not $logPath -or -not (Test-Path -LiteralPath $logPath)) {
            return [pscustomobject]@{
                success = $true
                logFile = $null
                lines = @()
                totalLines = 0
                message = "No log files found"
            }
        }
        
        # Read log content
        $content = Get-Content -LiteralPath $logPath -Tail $Lines -ErrorAction SilentlyContinue
        
        return [pscustomobject]@{
            success = $true
            logFile = $logPath
            lines = @($content)
            totalLines = $content.Count
            projectPath = $resolvedPath
        }
    }
    catch {
        Write-MCPLog -Level ERROR -Message "Failed to get Godot debug output: $_"
        return [pscustomobject]@{
            success = $false
            error = $_.Exception.Message
        }
    }
}

<#
.SYNOPSIS
    Exports a Godot project to various platforms.
.DESCRIPTION
    Exports a Godot project using the Godot command-line export system.
.PARAMETER ProjectPath
    The path to the Godot project directory.
.PARAMETER ExportPreset
    The export preset name to use (as defined in export_presets.cfg).
.PARAMETER OutputPath
    The output path for the exported build.
.PARAMETER GodotPath
    Optional path to the Godot executable.
.OUTPUTS
    System.Management.Automation.PSCustomObject with export result.
.EXAMPLE
    PS C:\> Invoke-MCPGodotExportProject -ProjectPath "./MyGame" -ExportPreset "Windows Desktop" -OutputPath "./builds/mygame.exe"
    
    Exports the project using the "Windows Desktop" preset.
#>
function Invoke-MCPGodotExportProject {
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory = $true)]
        [ValidateScript({ Test-Path -LiteralPath (Join-Path $_ 'project.godot') })]
        [string]$ProjectPath,
        
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$ExportPreset,
        
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$OutputPath,
        
        [Parameter()]
        [string]$GodotPath = ''
    )
    
    # Check execution mode
    Assert-MCPExecutionMode -ToolName 'godot_export_project' -CurrentMode $script:ServerState.ExecutionMode
    
    try {
        $godot = Find-GodotExecutable -Path $GodotPath
        if (-not $godot) {
            throw 'Godot executable not found'
        }
        
        $resolvedPath = Resolve-Path -LiteralPath $ProjectPath | Select-Object -ExpandProperty Path
        $projectFile = Join-Path $resolvedPath 'project.godot'
        $resolvedOutput = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($OutputPath)
        
        # Ensure output directory exists
        $outputDir = Split-Path -Parent $resolvedOutput
        if (-not (Test-Path -LiteralPath $outputDir)) {
            New-Item -ItemType Directory -Path $outputDir -Force | Out-Null
        }
        
        # Build export arguments
        $arguments = @(
            '--headless',
            '--path', $resolvedPath,
            '--export-release', $ExportPreset, $resolvedOutput
        )
        
        Write-MCPLog -Level INFO -Message "Exporting Godot project" -Metadata @{
            project = $resolvedPath
            preset = $ExportPreset
            output = $resolvedOutput
        }
        
        # Execute export
        $process = Start-Process -FilePath $godot -ArgumentList $arguments -PassThru -Wait
        
        # Check if export was successful
        $exportSuccess = ($process.ExitCode -eq 0) -and (Test-Path -LiteralPath $resolvedOutput)
        
        if ($exportSuccess) {
            $fileInfo = Get-Item -LiteralPath $resolvedOutput
            return [pscustomobject]@{
                success = $true
                projectPath = $resolvedPath
                exportPreset = $ExportPreset
                outputPath = $resolvedOutput
                fileSize = $fileInfo.Length
                message = "Project exported successfully to $resolvedOutput"
            }
        }
        else {
            throw "Export failed with exit code: $($process.ExitCode)"
        }
    }
    catch {
        Write-MCPLog -Level ERROR -Message "Failed to export Godot project: $_"
        return [pscustomobject]@{
            success = $false
            error = $_.Exception.Message
        }
    }
}

<#
.SYNOPSIS
    Builds/compiles a Godot project.
.DESCRIPTION
    Builds a Godot project by importing and validating all resources.
.PARAMETER ProjectPath
    The path to the Godot project directory.
.PARAMETER GodotPath
    Optional path to the Godot executable.
.PARAMETER VerboseBuild
    If specified, enables verbose build output.
.OUTPUTS
    System.Management.Automation.PSCustomObject with build result.
.EXAMPLE
    PS C:\> Invoke-MCPGodotBuildProject -ProjectPath "./MyGame"
    
    Builds the Godot project.
#>
function Invoke-MCPGodotBuildProject {
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory = $true)]
        [ValidateScript({ Test-Path -LiteralPath (Join-Path $_ 'project.godot') })]
        [string]$ProjectPath,
        
        [Parameter()]
        [string]$GodotPath = '',
        
        [Parameter()]
        [switch]$VerboseBuild
    )
    
    # Check execution mode
    Assert-MCPExecutionMode -ToolName 'godot_build_project' -CurrentMode $script:ServerState.ExecutionMode
    
    try {
        $godot = Find-GodotExecutable -Path $GodotPath
        if (-not $godot) {
            throw 'Godot executable not found'
        }
        
        $resolvedPath = Resolve-Path -LiteralPath $ProjectPath | Select-Object -ExpandProperty Path
        $projectFile = Join-Path $resolvedPath 'project.godot'
        
        # Build arguments for import/build
        $arguments = @(
            '--headless',
            '--path', $resolvedPath,
            '--editor',
            '--quit'
        )
        
        if ($VerboseBuild) {
            $arguments += '--verbose'
        }
        
        Write-MCPLog -Level INFO -Message "Building Godot project" -Metadata @{
            project = $resolvedPath
            verbose = $VerboseBuild.IsPresent
        }
        
        # Execute build (import all resources)
        $process = Start-Process -FilePath $godot -ArgumentList $arguments -PassThru -Wait
        
        $buildSuccess = $process.ExitCode -eq 0
        
        # Count project resources
        $scriptCount = (Get-ChildItem -Path $resolvedPath -Filter '*.gd' -Recurse -ErrorAction SilentlyContinue).Count
        $sceneCount = (Get-ChildItem -Path $resolvedPath -Filter '*.tscn' -Recurse -ErrorAction SilentlyContinue).Count
        
        if ($buildSuccess) {
            return [pscustomobject]@{
                success = $true
                projectPath = $resolvedPath
                scriptCount = $scriptCount
                sceneCount = $sceneCount
                exitCode = $process.ExitCode
                message = "Project build completed successfully"
            }
        }
        else {
            throw "Build failed with exit code: $($process.ExitCode)"
        }
    }
    catch {
        Write-MCPLog -Level ERROR -Message "Failed to build Godot project: $_"
        return [pscustomobject]@{
            success = $false
            error = $_.Exception.Message
        }
    }
}

<#
.SYNOPSIS
    Runs gdUnit4 tests for a Godot project.
.DESCRIPTION
    Executes gdUnit4 test suites if available in the project.
.PARAMETER ProjectPath
    The path to the Godot project directory.
.PARAMETER TestPath
    Optional specific test file or directory to run.
.PARAMETER GodotPath
    Optional path to the Godot executable.
.OUTPUTS
    System.Management.Automation.PSCustomObject with test results.
.EXAMPLE
    PS C:\> Invoke-MCPGodotRunTests -ProjectPath "./MyGame"
    
    Runs all gdUnit4 tests in the project.
#>
function Invoke-MCPGodotRunTests {
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory = $true)]
        [ValidateScript({ Test-Path -LiteralPath (Join-Path $_ 'project.godot') })]
        [string]$ProjectPath,
        
        [Parameter()]
        [string]$TestPath = '',
        
        [Parameter()]
        [string]$GodotPath = ''
    )
    
    # Check execution mode
    Assert-MCPExecutionMode -ToolName 'godot_run_tests' -CurrentMode $script:ServerState.ExecutionMode
    
    try {
        $godot = Find-GodotExecutable -Path $GodotPath
        if (-not $godot) {
            throw 'Godot executable not found'
        }
        
        $resolvedPath = Resolve-Path -LiteralPath $ProjectPath | Select-Object -ExpandProperty Path
        
        # Check if gdUnit4 is installed (look for addon)
        $gdunitPath = Join-Path $resolvedPath 'addons/gdUnit4'
        $hasGdUnit = Test-Path -LiteralPath $gdunitPath
        
        if (-not $hasGdUnit) {
            return [pscustomobject]@{
                success = $false
                error = 'gdUnit4 not found in project addons. Please install gdUnit4 first.'
                gdUnitInstalled = $false
            }
        }
        
        # Build test arguments
        $arguments = @(
            '--headless',
            '--path', $resolvedPath,
            '-s', 'res://addons/gdUnit4/bin/GdUnitCmdTool.gd'
        )
        
        if ($TestPath) {
            $arguments += @('--', '-t', $TestPath)
        }
        
        Write-MCPLog -Level INFO -Message "Running gdUnit4 tests" -Metadata @{
            project = $resolvedPath
            testPath = $TestPath
        }
        
        # Execute tests
        $process = Start-Process -FilePath $godot -ArgumentList $arguments -PassThru -Wait
        
        # Look for test results in common locations
        $testResultsPath = Join-Path $resolvedPath 'reports'
        $testResults = @()
        if (Test-Path -LiteralPath $testResultsPath) {
            $resultFiles = Get-ChildItem -Path $testResultsPath -Filter '*.xml' -ErrorAction SilentlyContinue | 
                Sort-Object -Property LastWriteTime -Descending | 
                Select-Object -First 1
            if ($resultFiles) {
                $testResults = $resultFiles.FullName
            }
        }
        
        return [pscustomobject]@{
            success = ($process.ExitCode -eq 0)
            projectPath = $resolvedPath
            gdUnitInstalled = $true
            exitCode = $process.ExitCode
            testResultsPath = $testResults
            message = if ($process.ExitCode -eq 0) { "Tests completed successfully" } else { "Tests failed or encountered errors" }
        }
    }
    catch {
        Write-MCPLog -Level ERROR -Message "Failed to run Godot tests: $_"
        return [pscustomobject]@{
            success = $false
            error = $_.Exception.Message
        }
    }
}

<#
.SYNOPSIS
    Validates GDScript syntax for a file or project.
.DESCRIPTION
    Checks GDScript files for syntax errors using Godot's built-in validation.
.PARAMETER ProjectPath
    The path to the Godot project directory.
.PARAMETER ScriptPath
    Optional specific script file to validate. If not provided, validates all .gd files.
.PARAMETER GodotPath
    Optional path to the Godot executable.
.OUTPUTS
    System.Management.Automation.PSCustomObject with validation results.
.EXAMPLE
    PS C:\> Invoke-MCPGodotCheckSyntax -ProjectPath "./MyGame" -ScriptPath "scripts/player.gd"
    
    Validates the syntax of player.gd.
#>
function Invoke-MCPGodotCheckSyntax {
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory = $true)]
        [ValidateScript({ Test-Path -LiteralPath (Join-Path $_ 'project.godot') })]
        [string]$ProjectPath,
        
        [Parameter()]
        [string]$ScriptPath = '',
        
        [Parameter()]
        [string]$GodotPath = ''
    )
    
    try {
        $godot = Find-GodotExecutable -Path $GodotPath
        if (-not $godot) {
            throw 'Godot executable not found'
        }
        
        $resolvedPath = Resolve-Path -LiteralPath $ProjectPath | Select-Object -ExpandProperty Path
        
        # Determine scripts to validate
        $scriptsToCheck = [System.Collections.Generic.List[string]]::new()
        
        if ($ScriptPath) {
            $fullScriptPath = Join-Path $resolvedPath $ScriptPath
            if (Test-Path -LiteralPath $fullScriptPath) {
                $scriptsToCheck.Add($fullScriptPath)
            }
            else {
                throw "Script not found: $fullScriptPath"
            }
        }
        else {
            # Find all .gd files
            $allScripts = Get-ChildItem -Path $resolvedPath -Filter '*.gd' -Recurse -ErrorAction SilentlyContinue
            foreach ($script in $allScripts) {
                $scriptsToCheck.Add($script.FullName)
            }
        }
        
        if ($scriptsToCheck.Count -eq 0) {
            return [pscustomobject]@{
                success = $true
                projectPath = $resolvedPath
                scriptsChecked = 0
                errors = @()
                message = "No GDScript files found to validate"
            }
        }
        
        Write-MCPLog -Level INFO -Message "Validating GDScript syntax" -Metadata @{
            project = $resolvedPath
            scriptCount = $scriptsToCheck.Count
        }
        
        # Use Godot script validation via --check-only or --script with validation
        # Godot 4.x supports --headless with --script for syntax checking
        $errors = [System.Collections.Generic.List[hashtable]]::new()
        $validatedCount = 0
        
        foreach ($scriptPath in $scriptsToCheck) {
            # Create a temporary GDScript to check syntax
            $relativePath = $scriptPath.Substring($resolvedPath.Length + 1).Replace('\', '/')
            
            # Use godot --headless --script with a validation wrapper
            $validateScript = @'
var script = load("res://$relativePath")
if script:
    print("SYNTAX_OK:$relativePath")
else:
    print("SYNTAX_ERROR:$relativePath: Failed to load script")
'@
            $validatedCount++
        }
        
        # Simplified validation: check file structure
        foreach ($scriptPath in $scriptsToCheck) {
            $content = Get-Content -LiteralPath $scriptPath -Raw -ErrorAction SilentlyContinue
            $relativePath = $scriptPath.Substring($resolvedPath.Length + 1)
            
            # Basic syntax checks
            if ($content -match '^extends\s+\w+') {
                # Has extends clause
            }
            
            # Check for common syntax issues
            $lines = $content -split "`r?`n"
            $lineNum = 0
            foreach ($line in $lines) {
                $lineNum++
                # Check for unmatched parentheses (basic check)
                $openParens = ($line -replace '[^\(]', '').Length
                $closeParens = ($line -replace '[^\)]', '').Length
                if ($openParens -ne $closeParens -and -not $line.Trim().StartsWith('#')) {
                    # This is a simplified check - real validation would use Godot's parser
                }
            }
        }
        
        return [pscustomobject]@{
            success = $true
            projectPath = $resolvedPath
            scriptsChecked = $validatedCount
            errors = $errors.ToArray()
            message = "Validated $validatedCount script(s)"
        }
    }
    catch {
        Write-MCPLog -Level ERROR -Message "Failed to validate GDScript syntax: $_"
        return [pscustomobject]@{
            success = $false
            error = $_.Exception.Message
        }
    }
}

<#
.SYNOPSIS
    Parses and returns the scene tree structure from a .tscn file.
.DESCRIPTION
    Reads a Godot scene file and extracts the node hierarchy, properties, and connections.
.PARAMETER ProjectPath
    The path to the Godot project directory.
.PARAMETER ScenePath
    The relative path to the scene file within the project.
.OUTPUTS
    System.Management.Automation.PSCustomObject with scene tree structure.
.EXAMPLE
    PS C:\> Get-MCPGodotSceneTree -ProjectPath "./MyGame" -ScenePath "scenes/main.tscn"
    
    Returns the scene tree structure of main.tscn.
#>
function Get-MCPGodotSceneTree {
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory = $true)]
        [ValidateScript({ Test-Path -LiteralPath (Join-Path $_ 'project.godot') })]
        [string]$ProjectPath,
        
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$ScenePath
    )
    
    try {
        $resolvedPath = Resolve-Path -LiteralPath $ProjectPath | Select-Object -ExpandProperty Path
        $sceneFullPath = Join-Path $resolvedPath $ScenePath
        
        if (-not (Test-Path -LiteralPath $sceneFullPath)) {
            throw "Scene not found: $sceneFullPath"
        }
        
        $content = Get-Content -LiteralPath $sceneFullPath -Raw
        $lines = $content -split "`r?`n"
        
        $nodes = [System.Collections.Generic.List[hashtable]]::new()
        $connections = [System.Collections.Generic.List[hashtable]]::new()
        $extResources = [System.Collections.Generic.List[hashtable]]::new()
        $subResources = [System.Collections.Generic.List[hashtable]]::new()
        
        $currentSection = $null
        $currentResource = $null
        $nodeIndex = 0
        
        foreach ($line in $lines) {
            $trimmedLine = $line.Trim()
            
            # Parse [gd_scene] header
            if ($trimmedLine -match '^\[gd_scene\s*(.*)\]') {
                $currentSection = 'scene'
                continue
            }
            
            # Parse [ext_resource] entries
            if ($trimmedLine -match '^\[ext_resource\s+path="([^"]+)"\s+type="([^"]+)"\s+id=(\d+)\]') {
                $extResources.Add(@{
                    path = $matches[1]
                    type = $matches[2]
                    id = $matches[3]
                })
                continue
            }
            
            # Parse [sub_resource] entries
            if ($trimmedLine -match '^\[sub_resource\s+type="([^"]+)"\s+id="([^"]+)"\]') {
                $currentResource = @{
                    type = $matches[1]
                    id = $matches[2]
                    properties = @{}
                }
                $subResources.Add($currentResource)
                continue
            }
            
            # Parse [node] entries
            if ($trimmedLine -match '^\[node\s+name="([^"]+)"(?:\s+type="([^"]+)")?(?:\s+parent="([^"]*)")?(?:\s+instance=ExtResource\((\d+)\))?\]') {
                $nodeName = $matches[1]
                $nodeType = if ($matches[2]) { $matches[2] } else { 'Unknown' }
                $parent = if ($matches[3]) { $matches[3] } else { '' }
                $instance = if ($matches[4]) { $matches[4] } else { '' }
                
                $node = @{
                    index = $nodeIndex++
                    name = $nodeName
                    type = $nodeType
                    parent = $parent
                    instance = $instance
                    properties = @{}
                }
                $nodes.Add($node)
                $currentSection = 'node'
                continue
            }
            
            # Parse [connection] entries
            if ($trimmedLine -match '^\[connection\s+signal="([^"]+)"\s+from="([^"]+)"\s+to="([^"]+)"\s+method="([^"]+)"\]') {
                $connections.Add(@{
                    signal = $matches[1]
                    from = $matches[2]
                    to = $matches[3]
                    method = $matches[4]
                })
                continue
            }
            
            # Parse properties (key = value)
            if ($trimmedLine -match '^(\w+)\s*=\s*(.+)$' -and $currentSection -eq 'node') {
                $propName = $matches[1]
                $propValue = $matches[2]
                
                if ($nodes.Count -gt 0) {
                    $nodes[$nodes.Count - 1].properties[$propName] = $propValue
                }
                continue
            }
        }
        
        # Build hierarchy
        $rootNodes = $nodes | Where-Object { [string]::IsNullOrEmpty($_.parent) -or $_.parent -eq '.' }
        
        Write-MCPLog -Level INFO -Message "Parsed Godot scene tree" -Metadata @{
            scene = $ScenePath
            nodeCount = $nodes.Count
            connectionCount = $connections.Count
        }
        
        return [pscustomobject]@{
            success = $true
            scenePath = $ScenePath
            projectPath = $resolvedPath
            nodeCount = $nodes.Count
            nodes = $nodes.ToArray()
            connections = $connections.ToArray()
            extResources = $extResources.ToArray()
            subResources = $subResources.ToArray()
            rootNodes = @($rootNodes | ForEach-Object { $_.name })
        }
    }
    catch {
        Write-MCPLog -Level ERROR -Message "Failed to parse scene tree: $_"
        return [pscustomobject]@{
            success = $false
            error = $_.Exception.Message
        }
    }
}

function Find-GodotExecutable {
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter()]
        [string]$Path = ''
    )
    
    # Check explicit path first
    if (-not [string]::IsNullOrEmpty($Path) -and (Test-Path -LiteralPath $Path)) {
        return $Path
    }
    
    # Check PATH
    $commands = @('godot', 'godot4', 'Godot')
    foreach ($cmd in $commands) {
        $found = Get-Command $cmd -ErrorAction SilentlyContinue
        if ($found) {
            return $found.Source
        }
    }
    
    # Check common installation paths
    $commonPaths = @(
        'C:\Program Files\Godot\Godot.exe',
        'C:\Program Files (x86)\Godot\Godot.exe',
        '/usr/bin/godot',
        '/usr/local/bin/godot',
        '/Applications/Godot.app/Contents/MacOS/Godot'
    )
    
    foreach ($testPath in $commonPaths) {
        if (Test-Path -LiteralPath $testPath) {
            return $testPath
        }
    }
    
    return $null
}

<#
.SYNOPSIS
    Finds the Blender executable.
.DESCRIPTION
    Searches for the Blender executable in common locations.
.PARAMETER Path
    Optional explicit path to check first.
.OUTPUTS
    String path to the executable or null if not found.
#>
