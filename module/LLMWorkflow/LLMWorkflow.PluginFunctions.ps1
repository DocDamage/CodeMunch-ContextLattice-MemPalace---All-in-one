# LLM Workflow Plugin Management Functions
# PowerShell 5.1+ compatible

function Get-LLMWorkflowPluginManifestPath {
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [string]$ProjectRoot = "."
    )
    $llmWorkflowDir = Join-Path (Resolve-Path -LiteralPath $ProjectRoot).Path ".llm-workflow"
    return Join-Path $llmWorkflowDir "plugins.json"
}

function Test-LLMWorkflowPluginManifest {
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [string]$ProjectRoot = "."
    )
    $manifestPath = Get-LLMWorkflowPluginManifestPath -ProjectRoot $ProjectRoot
    return Test-Path -LiteralPath $manifestPath
}

function Get-LLMWorkflowPluginManifest {
    [CmdletBinding()]
    param(
        [string]$ProjectRoot = "."
    )
    $manifestPath = Get-LLMWorkflowPluginManifestPath -ProjectRoot $ProjectRoot
    if (-not (Test-Path -LiteralPath $manifestPath)) {
        return @{
            version = "1.0"
            plugins = @()
        }
    }
    try {
        $content = Get-Content -LiteralPath $manifestPath -Raw -Encoding UTF8
        $manifest = $content | ConvertFrom-Json -ErrorAction Stop
        # Ensure plugins array exists
        if (-not $manifest.plugins) {
            $manifest.plugins = @()
        }
        return $manifest
    } catch {
        Write-Warning "Failed to parse plugin manifest: $($_.Exception.Message)"
        return @{
            version = "1.0"
            plugins = @()
        }
    }
}

function Save-LLMWorkflowPluginManifest {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [object]$Manifest,
        [string]$ProjectRoot = "."
    )
    $manifestPath = Get-LLMWorkflowPluginManifestPath -ProjectRoot $ProjectRoot
    $manifestDir = Split-Path -Parent $manifestPath
    if (-not (Test-Path -LiteralPath $manifestDir)) {
        New-Item -ItemType Directory -Path $manifestDir -Force | Out-Null
    }
    $Manifest | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $manifestPath -Encoding UTF8
}

function Get-LLMWorkflowPlugins {
    <#
    .SYNOPSIS
        Gets all registered LLM Workflow plugins.
    .DESCRIPTION
        Returns a list of plugins from the .llm-workflow/plugins.json manifest.
    .PARAMETER ProjectRoot
        Path to the project root. Defaults to current directory.
    .PARAMETER Trigger
        Filter plugins by trigger type (bootstrap, check).
    .EXAMPLE
        Get-LLMWorkflowPlugins
        Returns all registered plugins.
    .EXAMPLE
        Get-LLMWorkflowPlugins -Trigger bootstrap
        Returns only plugins that run on bootstrap.
    #>
    [CmdletBinding()]
    param(
        [string]$ProjectRoot = ".",
        [ValidateSet("bootstrap", "check", "")]
        [string]$Trigger = ""
    )
    $manifest = Get-LLMWorkflowPluginManifest -ProjectRoot $ProjectRoot
    $plugins = $manifest.plugins
    if ($Trigger) {
        $plugins = @($plugins | Where-Object { $_.runOn -contains $Trigger })
    }
    # Return as array of PSCustomObjects (use comma to prevent unrolling)
    $result = @()
    foreach ($plugin in $plugins) {
        $result += [pscustomobject]@{
            Name = $plugin.name
            Description = $plugin.description
            Version = if ($plugin.PSObject.Properties['version']) { $plugin.version } else { "" }
            Author = if ($plugin.PSObject.Properties['author']) { $plugin.author } else { "" }
            BootstrapScript = if ($plugin.PSObject.Properties['bootstrapScript']) { $plugin.bootstrapScript } else { "" }
            CheckScript = if ($plugin.PSObject.Properties['checkScript']) { $plugin.checkScript } else { "" }
            RunOn = $plugin.runOn
            Valid = Test-LLMWorkflowPlugin -Plugin $plugin -ProjectRoot $ProjectRoot
        }
    }
    return ,$result
}

function Test-LLMWorkflowPlugin {
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [Parameter(Mandatory=$true)]
        [object]$Plugin,
        [string]$ProjectRoot = "."
    )
    $projectPath = (Resolve-Path -LiteralPath $ProjectRoot).Path
    # Check required fields
    if (-not $Plugin.name -or -not $Plugin.description -or -not $Plugin.runOn) {
        return $false
    }
    # Check script paths exist if specified
    $bootstrapScript = if ($Plugin.PSObject.Properties['bootstrapScript']) { $Plugin.bootstrapScript } else { "" }
    $checkScript = if ($Plugin.PSObject.Properties['checkScript']) { $Plugin.checkScript } else { "" }
    if ($bootstrapScript) {
        $bootstrapPath = Join-Path $projectPath $bootstrapScript
        if (-not (Test-Path -LiteralPath $bootstrapPath)) {
            return $false
        }
    }
    if ($checkScript) {
        $checkPath = Join-Path $projectPath $checkScript
        if (-not (Test-Path -LiteralPath $checkPath)) {
            return $false
        }
    }
    return $true
}

function Register-LLMWorkflowPlugin {
    <#
    .SYNOPSIS
        Registers a new LLM Workflow plugin.
    .DESCRIPTION
        Adds a plugin to the .llm-workflow/plugins.json manifest.
    .PARAMETER ManifestPath
        Path to the plugin's individual manifest.json file.
    .PARAMETER ProjectRoot
        Path to the project root. Defaults to current directory.
    .PARAMETER Name
        Plugin name (if not using ManifestPath).
    .PARAMETER Description
        Plugin description (if not using ManifestPath).
    .PARAMETER BootstrapScript
        Path to bootstrap script (if not using ManifestPath).
    .PARAMETER CheckScript
        Path to check script (if not using ManifestPath).
    .PARAMETER RunOn
        Array of triggers (if not using ManifestPath).
    .EXAMPLE
        Register-LLMWorkflowPlugin -ManifestPath "tools/my-plugin/manifest.json"
        Registers a plugin from its manifest file.
    .EXAMPLE
        Register-LLMWorkflowPlugin -Name "my-plugin" -Description "My plugin" -BootstrapScript "tools/my-plugin/bootstrap.ps1" -RunOn @("bootstrap")
        Registers a plugin inline.
    #>
    [CmdletBinding()]
    param(
        [Parameter(ParameterSetName="FromManifest")]
        [string]$ManifestPath,
        [string]$ProjectRoot = ".",
        [Parameter(ParameterSetName="Inline", Mandatory=$true)]
        [string]$Name,
        [Parameter(ParameterSetName="Inline", Mandatory=$true)]
        [string]$Description,
        [Parameter(ParameterSetName="Inline")]
        [string]$Version = "",
        [Parameter(ParameterSetName="Inline")]
        [string]$Author = "",
        [Parameter(ParameterSetName="Inline")]
        [string]$BootstrapScript = "",
        [Parameter(ParameterSetName="Inline")]
        [string]$CheckScript = "",
        [Parameter(ParameterSetName="Inline", Mandatory=$true)]
        [ValidateSet("bootstrap", "check")]
        [string[]]$RunOn
    )
    $projectPath = (Resolve-Path -LiteralPath $ProjectRoot).Path
    $manifest = Get-LLMWorkflowPluginManifest -ProjectRoot $projectPath
    # Load plugin definition
    $pluginDef = $null
    if ($ManifestPath) {
        $fullManifestPath = Join-Path $projectPath $ManifestPath
        if (-not (Test-Path -LiteralPath $fullManifestPath)) {
            throw "Plugin manifest not found: $fullManifestPath"
        }
        try {
            $content = Get-Content -LiteralPath $fullManifestPath -Raw -Encoding UTF8
            $pluginDef = $content | ConvertFrom-Json -ErrorAction Stop
        } catch {
            throw "Failed to parse plugin manifest: $($_.Exception.Message)"
        }
    } else {
        $pluginDef = @{
            name = $Name
            description = $Description
            version = $Version
            author = $Author
            bootstrapScript = $BootstrapScript
            checkScript = $CheckScript
            runOn = $RunOn
        }
    }
    # Validate required fields
    if (-not $pluginDef.name) {
        throw "Plugin manifest missing required field: name"
    }
    if (-not $pluginDef.description) {
        throw "Plugin manifest missing required field: description"
    }
    if (-not $pluginDef.runOn) {
        throw "Plugin manifest missing required field: runOn"
    }
    # Remove existing plugin with same name
    $manifest.plugins = @($manifest.plugins | Where-Object { $_.name -ne $pluginDef.name })
    # Add new plugin
    $newPlugin = @{
        name = $pluginDef.name
        description = $pluginDef.description
        runOn = $pluginDef.runOn
    }
    if ($pluginDef.version) { $newPlugin.version = $pluginDef.version }
    if ($pluginDef.author) { $newPlugin.author = $pluginDef.author }
    if ($pluginDef.bootstrapScript) { $newPlugin.bootstrapScript = $pluginDef.bootstrapScript }
    if ($pluginDef.checkScript) { $newPlugin.checkScript = $pluginDef.checkScript }
    $manifest.plugins += $newPlugin
    Save-LLMWorkflowPluginManifest -Manifest $manifest -ProjectRoot $projectPath
    Write-Output "Registered plugin: $($pluginDef.name)"
}

function Unregister-LLMWorkflowPlugin {
    <#
    .SYNOPSIS
        Unregisters an LLM Workflow plugin.
    .DESCRIPTION
        Removes a plugin from the .llm-workflow/plugins.json manifest.
    .PARAMETER Name
        Name of the plugin to unregister.
    .PARAMETER ProjectRoot
        Path to the project root. Defaults to current directory.
    .EXAMPLE
        Unregister-LLMWorkflowPlugin -Name "my-plugin"
        Removes the plugin named "my-plugin".
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [string]$Name,
        [string]$ProjectRoot = "."
    )
    $projectPath = (Resolve-Path -LiteralPath $ProjectRoot).Path
    $manifest = Get-LLMWorkflowPluginManifest -ProjectRoot $projectPath
    $originalCount = $manifest.plugins.Count
    $manifest.plugins = @($manifest.plugins | Where-Object { $_.name -ne $Name })
    if ($manifest.plugins.Count -eq $originalCount) {
        Write-Warning "Plugin not found: $Name"
        return
    }
    Save-LLMWorkflowPluginManifest -Manifest $manifest -ProjectRoot $projectPath
    Write-Output "Unregistered plugin: $Name"
}

function Invoke-LLMWorkflowPlugins {
    <#
    .SYNOPSIS
        Executes LLM Workflow plugins for a given trigger.
    .DESCRIPTION
        Runs all plugins registered for the specified trigger (bootstrap or check).
    .PARAMETER Trigger
        The trigger to execute plugins for (bootstrap or check).
    .PARAMETER ProjectRoot
        Path to the project root. Defaults to current directory.
    .PARAMETER Context
        Additional context hashtable to pass to plugins.
    .PARAMETER Strict
        If set, stops on first plugin failure. Otherwise continues.
    .EXAMPLE
        Invoke-LLMWorkflowPlugins -Trigger bootstrap -ProjectRoot "."
        Runs all bootstrap plugins.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [ValidateSet("bootstrap", "check")]
        [string]$Trigger,
        [string]$ProjectRoot = ".",
        [hashtable]$Context = @{},
        [switch]$Strict
    )
    $projectPath = (Resolve-Path -LiteralPath $ProjectRoot).Path
    $plugins = Get-LLMWorkflowPlugins -ProjectRoot $projectPath -Trigger $Trigger
    if ($plugins.Count -eq 0) {
        return @{ Success = $true; Executed = 0; Failed = 0; Results = @() }
    }
    $results = @()
    $executed = 0
    $failed = 0
    foreach ($plugin in $plugins) {
        $scriptPath = $null
        switch ($Trigger) {
            "bootstrap" { $scriptPath = $plugin.BootstrapScript }
            "check" { $scriptPath = $plugin.CheckScript }
        }
        if (-not $scriptPath) {
            Write-Warning "[plugin] $($plugin.Name): No script defined for trigger '$Trigger'"
            continue
        }
        $fullScriptPath = Join-Path $projectPath $scriptPath
        if (-not (Test-Path -LiteralPath $fullScriptPath)) {
            Write-Warning "[plugin] $($plugin.Name): Script not found: $scriptPath"
            $failed++
            $results += @{
                Name = $plugin.Name
                Success = $false
                Message = "Script not found: $scriptPath"
            }
            if ($Strict) { break }
            continue
        }
        $executed++
        try {
            $global:LASTEXITCODE = 0
            & $fullScriptPath -ProjectRoot $projectPath -Context $Context 2>&1 | ForEach-Object {
                # Prefix plugin output
                if ($_ -is [System.Management.Automation.ErrorRecord]) {
                    Write-Warning "[plugin:$($plugin.Name)] $_"
                } else {
                    Write-Output "[plugin:$($plugin.Name)] $_"
                }
            }
            $exitCode = $global:LASTEXITCODE
            if ($exitCode -ne 0) {
                throw "Plugin exited with code $exitCode"
            }
            $results += @{
                Name = $plugin.Name
                Success = $true
                Message = "Completed successfully"
            }
        } catch {
            $failed++
            $results += @{
                Name = $plugin.Name
                Success = $false
                Message = $_.Exception.Message
            }
            Write-Warning "[plugin] $($plugin.Name) failed: $($_.Exception.Message)"
            if ($Strict) {
                throw "Plugin execution stopped due to -Strict flag. Failed plugin: $($plugin.Name)"
            }
        }
    }
    return @{
        Success = ($failed -eq 0)
        Executed = $executed
        Failed = $failed
        Results = $results
    }
}
