# LLM Workflow Self-Healing Functions
# Provides automatic diagnosis and repair capabilities for common issues

Set-StrictMode -Version Latest

#===============================================================================
# Configuration and Constants
#===============================================================================

$script:HealHistoryPath = Join-Path $HOME ".llm-workflow\heal-history.jsonl"
$script:HealLogPath = Join-Path $HOME ".llm-workflow\heal-log.txt"
$script:MaxHistoryEntries = 1000

# Issue categories
enum IssueCategory {
    CRITICAL
    WARNING
    INFO
}

# Issue types that can be detected and repaired
enum IssueType {
    MissingEnvFile
    InvalidPythonPath
    MissingChromaDB
    MissingPalaceDirectory
    CorruptedSyncState
    TemplateDrift
    MissingContextLatticeApiKey
    MissingContextLatticeUrl
    InvalidProviderConfig
    MissingCodeMunch
    MissingBridgeConfig
    CorruptedBridgeConfig
    PythonModuleMissing
    EnvFileIncomplete
}

#===============================================================================
# Helper Functions
#===============================================================================

function Write-HealSuppressedException {
    <#
    .SYNOPSIS
        Emits verbose diagnostics for intentionally suppressed exceptions.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [string]$Context,

        [Parameter(Mandatory=$true)]
        [System.Management.Automation.ErrorRecord]$ErrorRecord
    )

    Write-Verbose "[LLMWorkflow.HealFunctions] $($Context): $($ErrorRecord.Exception.Message)"
}

function Resolve-HealLiteralPath {
    <#
    .SYNOPSIS
        Resolves a literal path to an absolute path, returning $null on known non-fatal misses.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory=$true)]
        [string]$LiteralPath,

        [string]$Context = 'Path resolution'
    )

    try {
        return (Resolve-Path -LiteralPath $LiteralPath -ErrorAction Stop | Select-Object -ExpandProperty Path -First 1)
    } catch [System.Management.Automation.ItemNotFoundException] {
        return $null
    } catch {
        Write-HealSuppressedException -Context "$Context for '$LiteralPath'" -ErrorRecord $_
        return $null
    }
}

function Get-HealCommandPath {
    <#
    .SYNOPSIS
        Resolves an executable command name to a source path.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory=$true)]
        [string]$CommandName,

        [string]$Context = 'Command resolution'
    )

    try {
        $command = Get-Command -Name $CommandName -ErrorAction Stop | Select-Object -First 1
        if ($null -eq $command) {
            return $null
        }
        return [string]$command.Source
    } catch [System.Management.Automation.CommandNotFoundException] {
        return $null
    } catch {
        Write-HealSuppressedException -Context "$Context for '$CommandName'" -ErrorRecord $_
        return $null
    }
}

function Get-HealChildItems {
    <#
    .SYNOPSIS
        Safely enumerates child items for wildcard and direct paths.
    #>
    [CmdletBinding()]
    [OutputType([object[]])]
    param(
        [Parameter(Mandatory=$true)]
        [string]$Path,

        [ValidateSet('Any', 'File', 'Directory')]
        [string]$ItemType = 'Any',

        [string]$Context = 'Child item enumeration'
    )

    $params = @{
        Path = $Path
        ErrorAction = 'Stop'
    }
    switch ($ItemType) {
        'File' { $params['File'] = $true }
        'Directory' { $params['Directory'] = $true }
    }

    try {
        return @(Get-ChildItem @params)
    } catch [System.Management.Automation.ItemNotFoundException] {
        return @()
    } catch {
        Write-HealSuppressedException -Context "$Context for '$Path'" -ErrorRecord $_
        return @()
    }
}

function Get-HealFileLines {
    <#
    .SYNOPSIS
        Safely reads file lines, returning an empty array if unavailable.
    #>
    [CmdletBinding()]
    [OutputType([string[]])]
    param(
        [Parameter(Mandatory=$true)]
        [string]$Path,

        [string]$Context = 'File read'
    )

    try {
        if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
            return @()
        }
        return @(Get-Content -Path $Path -ErrorAction Stop)
    } catch [System.Management.Automation.ItemNotFoundException] {
        return @()
    } catch {
        Write-HealSuppressedException -Context "$Context for '$Path'" -ErrorRecord $_
        return @()
    }
}

function Get-HealWorkflowVersion {
    <#
    .SYNOPSIS
        Gets the workflow version used in heal-history entries with a safe fallback.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param()

    try {
        $versionCommand = Get-Command -Name 'Get-LLMWorkflowVersion' -ErrorAction Stop
        if ($null -eq $versionCommand) {
            return 'unknown'
        }

        $versionInfo = Get-LLMWorkflowVersion
        if ($null -ne $versionInfo -and $versionInfo.PSObject.Properties.Name -contains 'manifestVersion') {
            $manifestVersion = [string]$versionInfo.manifestVersion
            if (-not [string]::IsNullOrWhiteSpace($manifestVersion)) {
                return $manifestVersion
            }
        }
    } catch [System.Management.Automation.CommandNotFoundException] {
        return 'unknown'
    } catch {
        Write-HealSuppressedException -Context 'Workflow version lookup' -ErrorRecord $_
    }

    return 'unknown'
}

function Initialize-HealHistoryStore {
    <#
    .SYNOPSIS
        Ensures the heal history directory and files exist.
    #>
    [CmdletBinding()]
    param()
    
    $storeDir = Split-Path -Parent $script:HealHistoryPath
    if (-not (Test-Path -LiteralPath $storeDir)) {
        New-Item -ItemType Directory -Path $storeDir -Force | Out-Null
    }
}

function Write-HealHistoryEntry {
    <#
    .SYNOPSIS
        Writes a heal operation entry to the history log.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [string]$Operation,
        
        [Parameter(Mandatory=$true)]
        [string]$IssueType,
        
        [Parameter(Mandatory=$true)]
        [string]$Status,
        
        [string]$Details = "",
        [string]$ProjectRoot = ".",
        [switch]$WhatIf
    )
    
    Initialize-HealHistoryStore
    
    $resolvedProjectRoot = Resolve-HealLiteralPath -LiteralPath $ProjectRoot -Context 'Heal history project-root resolution'

    $entry = [ordered]@{
        timestamp = [DateTime]::UtcNow.ToString("o")
        operation = $Operation
        issueType = $IssueType
        status = $Status
        details = $Details
        projectRoot = if ([string]::IsNullOrWhiteSpace($resolvedProjectRoot)) { $ProjectRoot } else { $resolvedProjectRoot }
        whatIf = $WhatIf.IsPresent
        version = Get-HealWorkflowVersion
    }
    
    $jsonLine = ($entry | ConvertTo-Json -Compress)
    Add-Content -Path $script:HealHistoryPath -Value $jsonLine -Encoding UTF8
    
    # Trim history if too large
    $lines = @(Get-HealFileLines -Path $script:HealHistoryPath -Context 'Heal history trim read')
    if (@($lines).Count -gt $script:MaxHistoryEntries) {
        $lines | Select-Object -Last $script:MaxHistoryEntries | Set-Content -Path $script:HealHistoryPath -Encoding UTF8
    }
}

function Write-HealLog {
    <#
    .SYNOPSIS
        Writes a message to the heal log file.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [string]$Message,
        
        [ValidateSet("INFO", "WARN", "ERROR", "SUCCESS")]
        [string]$Level = "INFO"
    )
    
    Initialize-HealHistoryStore
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $logLine = "[$timestamp] [$Level] $Message"
    Add-Content -Path $script:HealLogPath -Value $logLine -Encoding UTF8
}

function Get-DefaultEnvTemplate {
    <#
    .SYNOPSIS
        Returns the default .env file template content.
    #>
    @"
# LLM Workflow Environment Configuration
# Generated by llmheal on $(Get-Date -Format "yyyy-MM-dd HH:mm:ss")

# =============================================================================
# ContextLattice Configuration
# =============================================================================
CONTEXTLATTICE_ORCHESTRATOR_URL=http://127.0.0.1:8075
CONTEXTLATTICE_ORCHESTRATOR_API_KEY=your-api-key-here

# =============================================================================
# LLM Provider API Keys (at least one required)
# =============================================================================
# OpenAI
# OPENAI_API_KEY=sk-your-key-here

# Anthropic Claude
# ANTHROPIC_API_KEY=sk-ant-your-key-here

# Kimi (Moonshot)
# KIMI_API_KEY=your-kimi-key-here

# Google Gemini
# GEMINI_API_KEY=your-gemini-key-here

# GLM (Zhipu)
# GLM_API_KEY=your-glm-key-here
# GLM_BASE_URL=https://open.bigmodel.cn/api/paas/v4

# Ollama (local)
# OLLAMA_BASE_URL=http://localhost:11434/v1

# =============================================================================
# Optional Configuration
# =============================================================================
# CONTEXTLATTICE_PROJECT_NAME=my-project
# MEMPALACE_PALACE_PATH=~/.mempalace/palace
"@
}

function Get-DefaultBridgeConfig {
    <#
    .SYNOPSIS
        Returns the default bridge.config.json content.
    #>
    @"
{
  "`$schema": "./bridge.config.schema.json",
  "version": "2.0",
  "orchestratorUrl": "http://127.0.0.1:8075",
  "apiKeyEnvVar": "CONTEXTLATTICE_ORCHESTRATOR_API_KEY",
  "defaultProjectName": "my-project",
  "palaces": [
    {
      "path": "~/.mempalace/palace",
      "collectionName": "mempalace_drawers",
      "topicPrefix": "mempalace",
      "wingProjectMap": {
        "default_wing": "my-project"
      }
    }
  ],
  "syncOptions": {
    "batchSize": 250,
    "workers": 4,
    "strict": false
  }
}
"@
}

function Test-IsPythonAvailable {
    <#
    .SYNOPSIS
        Tests if Python is available and returns details.
    #>
    [CmdletBinding()]
    param()
    
    $pythonCmds = @("python", "python3", "py")
    $foundPython = $null
    
    foreach ($cmd in $pythonCmds) {
        $foundPath = Get-HealCommandPath -CommandName $cmd -Context 'Python command availability probe'
        if (-not [string]::IsNullOrWhiteSpace($foundPath)) {
            try {
                $version = & $cmd --version 2>&1
                if ($LASTEXITCODE -eq 0) {
                    $foundPython = @{
                        Command = $cmd
                        Path = $foundPath
                        Version = $version
                    }
                    break
                }
            } catch {
                continue
            }
        }
    }
    
    return $foundPython
}

function Find-PythonInstallation {
    <#
    .SYNOPSIS
        Searches for Python installations in common locations.
    #>
    [CmdletBinding()]
    param()
    
    $possiblePaths = @()
    
    # Common Windows Python locations
    if ($IsWindows -or ($PSVersionTable.PSVersion.Major -lt 6)) {
        # Search common install roots via environment variables and wildcards
        $searchRoots = @(
            (Join-Path $env:ProgramFiles 'Python*'),
            (Join-Path ${env:ProgramFiles(x86)} 'Python*'),
            'C:\Python*'
        ) | Where-Object { -not [string]::IsNullOrWhiteSpace($_) }

        foreach ($rootPattern in $searchRoots) {
            $roots = Get-HealChildItems -Path $rootPattern -ItemType Directory -Context 'Python root directory scan'
            foreach ($pythonRoot in $roots) {
                $versions = Get-HealChildItems -Path $pythonRoot.FullName -ItemType Directory -Context 'Python version directory scan' |
                    Where-Object { $_.Name -match '^\d+' } |
                    Sort-Object Name -Descending
                foreach ($ver in $versions) {
                    $pythonExe = Join-Path $ver.FullName 'python.exe'
                    if (Test-Path $pythonExe) {
                        $possiblePaths += $pythonExe
                    }
                }
                # Also check root-level python.exe
                $rootPython = Join-Path $pythonRoot.FullName 'python.exe'
                if (Test-Path $rootPython) {
                    $possiblePaths += $rootPython
                }
            }
        }
        
        # Microsoft Store Python
        $storePath = "$env:LOCALAPPDATA\Microsoft\WindowsApps\python.exe"
        if (Test-Path $storePath) {
            $possiblePaths += $storePath
        }
        
        # Py launcher (use WINDIR/SystemRoot instead of hardcoded C:\Windows)
        $windowsDir = if ($env:SystemRoot) { $env:SystemRoot } elseif ($env:WINDIR) { $env:WINDIR } else { 'C:\Windows' }
        $pyPath = Join-Path $windowsDir 'py.exe'
        if (Test-Path $pyPath) {
            $possiblePaths += $pyPath
        }
    } else {
        # Linux/Mac common locations using wildcards for portability
        $unixSearchPaths = @('/usr/bin/python*', '/usr/local/bin/python*', '/opt/python*/bin/python*', "$HOME/.local/bin/python*")
        foreach ($pattern in $unixSearchPaths) {
            $matches = Get-HealChildItems -Path $pattern -ItemType File -Context 'Unix python path scan'
            foreach ($match in $matches) {
                $possiblePaths += $match.FullName
            }
        }
    }
    
    # Test each found Python
    $validPythons = @()
    foreach ($path in $possiblePaths) {
        try {
            $version = & $path --version 2>&1
            if ($LASTEXITCODE -eq 0) {
                $validPythons += @{
                    Path = $path
                    Version = $version
                }
            }
        } catch {
            continue
        }
    }
    
    return $validPythons
}

function Test-PythonModule {
    <#
    .SYNOPSIS
        Tests if a specific Python module is available.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [string]$ModuleName,
        
        [string]$PythonCommand = "python"
    )
    
    try {
        $probe = "import importlib.util; print(bool(importlib.util.find_spec(r'$ModuleName')))"
        $result = & $PythonCommand -c $probe 2>&1
        return ($result -eq "True")
    } catch {
        return $false
    }
}

function Read-SecureInput {
    <#
    .SYNOPSIS
        Reads user input with masking (for API keys).
    #>
    [CmdletBinding()]
    param(
        [string]$Prompt = "Enter value: "
    )
    
    Write-Host $Prompt -NoNewline
    $secure = Read-Host -AsSecureString
    $BSTR = [System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($secure)
    $plain = [System.Runtime.InteropServices.Marshal]::PtrToStringAuto($BSTR)
    [System.Runtime.InteropServices.Marshal]::ZeroFreeBSTR($BSTR)
    return $plain
}

function Invoke-WhatIfMessage {
    <#
    .SYNOPSIS
        Displays a WhatIf message and returns whether to proceed.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [string]$Message,
        
        [switch]$Force
    )
    
    if ($Force) {
        return $true
    }
    
    Write-Host "[WHATIF] Would perform: $Message" -ForegroundColor Cyan
    return $false
}

#===============================================================================
# Issue Detection Functions (Test-LLMWorkflowIssue)
#===============================================================================

function Test-LLMWorkflowIssue {
    <#
    .SYNOPSIS
        Detects specific issues in the LLM Workflow environment.
    .DESCRIPTION
        Tests for a specific issue type and returns detailed information about the problem.
    .PARAMETER IssueType
        The type of issue to test for.
    .PARAMETER ProjectRoot
        Path to the project root.
    .EXAMPLE
        Test-LLMWorkflowIssue -IssueType MissingEnvFile
        Tests if the .env file is missing.
    #>
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [Parameter(Mandatory=$true)]
        [IssueType]$IssueType,
        
        [string]$ProjectRoot = "."
    )
    
    $projectPath = Resolve-HealLiteralPath -LiteralPath $ProjectRoot -Context 'Issue detection project-root resolution'
    if (-not $projectPath) {
        return @{
            Detected = $true
            Category = [IssueCategory]::CRITICAL
            Message = "Project root does not exist: $ProjectRoot"
            Details = @{}
            CanFix = $false
        }
    }
    
    switch ($IssueType) {
        "MissingEnvFile" {
            $envPath = Join-Path $projectPath ".env"
            $exists = Test-Path -LiteralPath $envPath
            return @{
                Detected = -not $exists
                Category = [IssueCategory]::WARNING
                Message = if ($exists) { ".env file exists" } else { "Missing .env file" }
                Details = @{ Path = $envPath }
                CanFix = $true
                FixDescription = "Create .env file from template"
            }
        }
        
        "InvalidPythonPath" {
            $python = Test-IsPythonAvailable
            $detected = $null -eq $python
            return @{
                Detected = $detected
                Category = [IssueCategory]::CRITICAL
                Message = if ($detected) { "Python not found on PATH" } else { "Python available: $($python.Path)" }
                Details = $python
                CanFix = $detected
                FixDescription = "Search for and configure Python installation"
            }
        }
        
        "MissingChromaDB" {
            $python = Test-IsPythonAvailable
            if (-not $python) {
                return @{
                    Detected = $false
                    Category = [IssueCategory]::INFO
                    Message = "Cannot check ChromaDB - Python not available"
                    Details = @{}
                    CanFix = $false
                }
            }
            $hasChroma = Test-PythonModule -ModuleName "chromadb" -PythonCommand $python.Command
            return @{
                Detected = -not $hasChroma
                Category = [IssueCategory]::WARNING
                Message = if ($hasChroma) { "ChromaDB module available" } else { "ChromaDB module not installed" }
                Details = @{ PythonCommand = $python.Command }
                CanFix = (-not $hasChroma)
                FixDescription = "Install ChromaDB via pip"
            }
        }
        
        "MissingPalaceDirectory" {
            $palacePath = Join-Path $HOME ".mempalace\palace"
            $envPath = [Environment]::GetEnvironmentVariable("MEMPALACE_PALACE_PATH")
            if ($envPath) {
                $palacePath = $envPath
            }
            $expandedPath = $palacePath.Replace("~", $HOME)
            $exists = Test-Path -LiteralPath $expandedPath
            return @{
                Detected = -not $exists
                Category = [IssueCategory]::WARNING
                Message = if ($exists) { "Palace directory exists" } else { "Missing palace directory: $palacePath" }
                Details = @{ Path = $palacePath; ExpandedPath = $expandedPath }
                CanFix = (-not $exists)
                FixDescription = "Create palace directory with default collection"
            }
        }
        
        "CorruptedSyncState" {
            $statePath = Join-Path $projectPath ".memorybridge\sync-state.json"
            if (-not (Test-Path -LiteralPath $statePath)) {
                return @{
                    Detected = $false
                    Category = [IssueCategory]::INFO
                    Message = "No sync state file exists (will be created on first sync)"
                    Details = @{ Path = $statePath }
                    CanFix = $false
                }
            }
            try {
                $content = Get-Content -LiteralPath $statePath -Raw -ErrorAction Stop
                $null = $content | ConvertFrom-Json -ErrorAction Stop
                return @{
                    Detected = $false
                    Category = [IssueCategory]::INFO
                    Message = "Sync state file is valid"
                    Details = @{ Path = $statePath }
                    CanFix = $false
                }
            } catch {
                return @{
                    Detected = $true
                    Category = [IssueCategory]::WARNING
                    Message = "Corrupted sync-state.json detected"
                    Details = @{ Path = $statePath; Error = $_.Exception.Message }
                    CanFix = $true
                    FixDescription = "Backup and recreate sync state"
                }
            }
        }
        
        "TemplateDrift" {
            $toolkitSource = Join-Path $PSScriptRoot "templates\tools"
            if (-not (Test-Path -LiteralPath $toolkitSource)) {
                return @{
                    Detected = $false
                    Category = [IssueCategory]::INFO
                    Message = "Cannot check template drift - template source not found"
                    Details = @{}
                    CanFix = $false
                }
            }
            
            $tools = @("codemunch", "contextlattice", "memorybridge")
            $drifted = @()
            foreach ($tool in $tools) {
                $sourceDir = Join-Path $toolkitSource $tool
                $projectDir = Join-Path (Join-Path $projectPath "tools") $tool
                if ((Test-Path -LiteralPath $sourceDir) -and -not (Test-Path -LiteralPath $projectDir)) {
                    $drifted += $tool
                }
            }
            return @{
                Detected = $drifted.Count -gt 0
                Category = [IssueCategory]::INFO
                Message = if ($drifted.Count -gt 0) { "Template drift detected for: $($drifted -join ', ')" } else { "All templates synchronized" }
                Details = @{ DriftedTools = $drifted }
                CanFix = $drifted.Count -gt 0
                FixDescription = "Re-sync templates from module"
            }
        }
        
        "MissingContextLatticeApiKey" {
            $key = [Environment]::GetEnvironmentVariable("CONTEXTLATTICE_ORCHESTRATOR_API_KEY")
            $envFile = Join-Path $projectPath ".env"
            $hasKeyInEnv = $false
            if (Test-Path -LiteralPath $envFile) {
                $envContent = Get-Content -LiteralPath $envFile -Raw
                $hasKeyInEnv = $envContent -match "CONTEXTLATTICE_ORCHESTRATOR_API_KEY\s*="
            }
            $detected = [string]::IsNullOrWhiteSpace($key) -and -not $hasKeyInEnv
            return @{
                Detected = $detected
                Category = [IssueCategory]::CRITICAL
                Message = if ($detected) { "ContextLattice API key not configured" } else { "ContextLattice API key is set" }
                Details = @{ 
                    InEnvironment = -not [string]::IsNullOrWhiteSpace($key)
                    InEnvFile = $hasKeyInEnv
                }
                CanFix = $detected
                FixDescription = "Prompt for API key with masking"
            }
        }
        
        "MissingContextLatticeUrl" {
            $url = [Environment]::GetEnvironmentVariable("CONTEXTLATTICE_ORCHESTRATOR_URL")
            $detected = [string]::IsNullOrWhiteSpace($url)
            return @{
                Detected = $detected
                Category = [IssueCategory]::WARNING
                Message = if ($detected) { "ContextLattice URL not configured (will use default)" } else { "ContextLattice URL: $url" }
                Details = @{ CurrentValue = $url }
                CanFix = $detected
                FixDescription = "Set default ContextLattice URL"
            }
        }
        
        "MissingBridgeConfig" {
            $configPath = Join-Path $projectPath ".memorybridge\bridge.config.json"
            $exists = Test-Path -LiteralPath $configPath
            return @{
                Detected = -not $exists
                Category = [IssueCategory]::WARNING
                Message = if ($exists) { "Bridge config exists" } else { "Missing bridge.config.json" }
                Details = @{ Path = $configPath }
                CanFix = (-not $exists)
                FixDescription = "Create default bridge.config.json"
            }
        }
        
        "CorruptedBridgeConfig" {
            $configPath = Join-Path $projectPath ".memorybridge\bridge.config.json"
            if (-not (Test-Path -LiteralPath $configPath)) {
                return @{
                    Detected = $false
                    Category = [IssueCategory]::INFO
                    Message = "No bridge config to validate"
                    Details = @{}
                    CanFix = $false
                }
            }
            try {
                $content = Get-Content -LiteralPath $configPath -Raw
                $null = $content | ConvertFrom-Json -ErrorAction Stop
                return @{
                    Detected = $false
                    Category = [IssueCategory]::INFO
                    Message = "Bridge config is valid JSON"
                    Details = @{ Path = $configPath }
                    CanFix = $false
                }
            } catch {
                return @{
                    Detected = $true
                    Category = [IssueCategory]::CRITICAL
                    Message = "Bridge config is corrupted (invalid JSON)"
                    Details = @{ Path = $configPath; Error = $_.Exception.Message }
                    CanFix = $true
                    FixDescription = "Backup and recreate bridge config"
                }
            }
        }
        
        default {
            return @{
                Detected = $false
                Category = [IssueCategory]::INFO
                Message = "Unknown issue type: $IssueType"
                Details = @{}
                CanFix = $false
            }
        }
    }
}

#===============================================================================
# Issue Repair Functions (Repair-LLMWorkflowIssue)
#===============================================================================

function Repair-LLMWorkflowIssue {
    <#
    .SYNOPSIS
        Repairs a specific issue in the LLM Workflow environment.
    .DESCRIPTION
        Attempts to fix a detected issue automatically. Returns repair result details.
    .PARAMETER IssueType
        The type of issue to repair.
    .PARAMETER ProjectRoot
        Path to the project root.
    .PARAMETER WhatIf
        Show what would be done without making changes.
    .PARAMETER Force
        Auto-apply fixes without prompting.
    .PARAMETER Interactive
        Show prompts for user input when needed.
    .EXAMPLE
        Repair-LLMWorkflowIssue -IssueType MissingEnvFile -Force
        Creates a .env file from template without prompting.
    #>
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [Parameter(Mandatory=$true)]
        [IssueType]$IssueType,
        
        [string]$ProjectRoot = ".",
        [switch]$WhatIf,
        [switch]$Force,
        [switch]$Interactive
    )
    
    $projectPath = Resolve-HealLiteralPath -LiteralPath $ProjectRoot -Context 'Issue repair project-root resolution'
    if (-not $projectPath) {
        return @{
            Success = $false
            IssueType = $IssueType
            Message = "Project root does not exist: $ProjectRoot"
            Changes = @()
        }
    }
    
    $changes = @()
    $success = $false
    $message = ""
    
    try {
        switch ($IssueType) {
            "MissingEnvFile" {
                $envPath = Join-Path $projectPath ".env"
                $template = Get-DefaultEnvTemplate
                
                if ($WhatIf) {
                    $changes += "Would create .env file at: $envPath"
                    $success = $true
                    $message = "Would create .env file (WhatIf mode)"
                } else {
                    $template | Out-File -FilePath $envPath -Encoding UTF8
                    $changes += "Created .env file at: $envPath"
                    Write-HealLog -Message "Created .env file: $envPath" -Level "SUCCESS"
                    $success = $true
                    $message = "Created .env file from template"
                    
                    Write-HealHistoryEntry -Operation "Repair" -IssueType $IssueType -Status "Success" `
                        -Details "Created $envPath" -ProjectRoot $ProjectRoot -WhatIf:$WhatIf
                }
                break
            }
            
            "InvalidPythonPath" {
                if ($WhatIf) {
                    $changes += "Would search for Python installations"
                    $success = $true
                    $message = "Would search for and configure Python (WhatIf mode)"
                } else {
                    $foundPythons = Find-PythonInstallation
                    if ($foundPythons.Count -eq 0) {
                        $success = $false
                        $message = "No Python installation found on system"
                        $changes += "Searched common Python locations - none found"
                    } elseif ($foundPythons.Count -eq 1 -or $Force) {
                        $selected = $foundPythons[0]
                        $changes += "Found Python: $($selected.Path) ($($selected.Version))"
                        
                        # Add to PATH for current session
                        $pythonDir = Split-Path -Parent $selected.Path
                        $env:PATH = "$pythonDir;$env:PATH"
                        $changes += "Added Python directory to PATH for current session"
                        
                        # Suggest permanent addition
                        if ($Interactive -and -not $Force) {
                            Write-Host "Found Python at: $($selected.Path)" -ForegroundColor Green
                            Write-Host "Added to current session PATH." -ForegroundColor Yellow
                            Write-Host "To add permanently, run:" -ForegroundColor Yellow
                            Write-Host "  [Environment]::SetEnvironmentVariable('PATH', '`$env:PATH;$pythonDir', 'User')" -ForegroundColor Cyan
                        }
                        
                        $success = $true
                        $message = "Configured Python: $($selected.Path)"
                        Write-HealLog -Message "Configured Python: $($selected.Path)" -Level "SUCCESS"
                    } else {
                        if ($Interactive) {
                            Write-Host "Multiple Python installations found:" -ForegroundColor Cyan
                            for ($i = 0; $i -lt $foundPythons.Count; $i++) {
                                Write-Host "  [$i] $($foundPythons[$i].Path) - $($foundPythons[$i].Version)" -ForegroundColor White
                            }
                            $choice = Read-Host "Select Python to use (0-$($foundPythons.Count - 1))"
                            if ($choice -match '^\d+$' -and [int]$choice -lt $foundPythons.Count) {
                                $selected = $foundPythons[[int]$choice]
                                $pythonDir = Split-Path -Parent $selected.Path
                                $env:PATH = "$pythonDir;$env:PATH"
                                $changes += "Selected and configured: $($selected.Path)"
                                $success = $true
                                $message = "Configured Python: $($selected.Path)"
                            } else {
                                $success = $false
                                $message = "Invalid selection"
                            }
                        } else {
                            # Auto-select first one
                            $selected = $foundPythons[0]
                            $pythonDir = Split-Path -Parent $selected.Path
                            $env:PATH = "$pythonDir;$env:PATH"
                            $changes += "Auto-selected: $($selected.Path)"
                            $success = $true
                            $message = "Configured Python: $($selected.Path)"
                        }
                    }
                    
                    Write-HealHistoryEntry -Operation "Repair" -IssueType $IssueType -Status $(if ($success) { "Success" } else { "Failed" }) `
                        -Details ($changes -join "; ") -ProjectRoot $ProjectRoot -WhatIf:$WhatIf
                }
                break
            }
            
            "MissingChromaDB" {
                if ($WhatIf) {
                    $changes += "Would run: python -m pip install chromadb"
                    $success = $true
                    $message = "Would install ChromaDB (WhatIf mode)"
                } else {
                    $python = Test-IsPythonAvailable
                    if (-not $python) {
                        $success = $false
                        $message = "Cannot install ChromaDB - Python not available"
                    } else {
                        Write-Host "Installing ChromaDB..." -ForegroundColor Cyan
                        try {
                            $output = & $python.Command -m pip install chromadb 2>&1
                            $exitCode = $LASTEXITCODE
                            
                            if ($exitCode -eq 0) {
                                $changes += "Installed ChromaDB via pip"
                                $success = $true
                                $message = "ChromaDB installed successfully"
                                Write-HealLog -Message "Installed ChromaDB" -Level "SUCCESS"
                            } else {
                                $changes += "pip install failed with exit code $exitCode"
                                $success = $false
                                $message = "Failed to install ChromaDB"
                            }
                        } catch {
                            $changes += "Exception during install: $($_.Exception.Message)"
                            $success = $false
                            $message = "Failed to install ChromaDB: $($_.Exception.Message)"
                        }
                    }
                    
                    Write-HealHistoryEntry -Operation "Repair" -IssueType $IssueType -Status $(if ($success) { "Success" } else { "Failed" }) `
                        -Details ($changes -join "; ") -ProjectRoot $ProjectRoot -WhatIf:$WhatIf
                }
                break
            }
            
            "MissingPalaceDirectory" {
                if ($WhatIf) {
                    $changes += "Would create palace directory at ~/.mempalace/palace"
                    $changes += "Would create default collection 'mempalace_drawers'"
                    $success = $true
                    $message = "Would create palace directory and collection (WhatIf mode)"
                } else {
                    $palacePath = Join-Path $HOME ".mempalace\palace"
                    $envPath = [Environment]::GetEnvironmentVariable("MEMPALACE_PALACE_PATH")
                    if ($envPath) {
                        $palacePath = $envPath.Replace("~", $HOME)
                    }
                    
                    try {
                        New-Item -ItemType Directory -Path $palacePath -Force | Out-Null
                        $changes += "Created palace directory: $palacePath"
                        
                        # Create default collection using Python
                        $python = Test-IsPythonAvailable
                        if ($python) {
                            $script = @"
import chromadb
client = chromadb.PersistentClient(path=r'$palacePath')
try:
    collection = client.create_collection('mempalace_drawers')
    print('CREATED')
except Exception as e:
    if 'already exists' in str(e):
        print('EXISTS')
    else:
        print('ERROR:', str(e))
"@
                            $result = & $python.Command -c $script 2>&1
                            if ($result -contains "CREATED") {
                                $changes += "Created default collection: mempalcace_drawers"
                            } elseif ($result -contains "EXISTS") {
                                $changes += "Collection already exists"
                            }
                        }
                        
                        $success = $true
                        $message = "Created palace directory with default collection"
                        Write-HealLog -Message "Created palace directory: $palacePath" -Level "SUCCESS"
                    } catch {
                        $success = $false
                        $message = "Failed to create palace directory: $($_.Exception.Message)"
                        $changes += "Error: $($_.Exception.Message)"
                    }
                    
                    Write-HealHistoryEntry -Operation "Repair" -IssueType $IssueType -Status $(if ($success) { "Success" } else { "Failed" }) `
                        -Details ($changes -join "; ") -ProjectRoot $ProjectRoot -WhatIf:$WhatIf
                }
                break
            }
            
            "CorruptedSyncState" {
                $statePath = Join-Path $projectPath ".memorybridge\sync-state.json"
                if ($WhatIf) {
                    $changes += "Would backup corrupted sync-state.json"
                    $changes += "Would create new empty sync-state.json"
                    $success = $true
                    $message = "Would repair sync state (WhatIf mode)"
                } else {
                    try {
                        if (Test-Path -LiteralPath $statePath) {
                            $backupPath = "$statePath.backup.$(Get-Date -Format 'yyyyMMdd_HHmmss')"
                            Copy-Item -LiteralPath $statePath -Destination $backupPath
                            $changes += "Backed up corrupted state to: $backupPath"
                        }
                        
                        $defaultState = @{
                            version = "1.0"
                            lastSync = $null
                            drawers = @{}
                        }
                        $defaultState | ConvertTo-Json -Depth 10 | Out-File -FilePath $statePath -Encoding UTF8
                        $changes += "Created new sync-state.json"
                        
                        $success = $true
                        $message = "Repaired sync state (backup created)"
                        Write-HealLog -Message "Repaired sync state: $statePath" -Level "SUCCESS"
                    } catch {
                        $success = $false
                        $message = "Failed to repair sync state: $($_.Exception.Message)"
                        $changes += "Error: $($_.Exception.Message)"
                    }
                    
                    Write-HealHistoryEntry -Operation "Repair" -IssueType $IssueType -Status $(if ($success) { "Success" } else { "Failed" }) `
                        -Details ($changes -join "; ") -ProjectRoot $ProjectRoot -WhatIf:$WhatIf
                }
                break
            }
            
            "TemplateDrift" {
                if ($WhatIf) {
                    $changes += "Would re-sync tool templates from module"
                    $success = $true
                    $message = "Would re-sync templates (WhatIf mode)"
                } else {
                    try {
                        $toolkitSource = Join-Path $PSScriptRoot "templates\tools"
                        $toolsTarget = Join-Path $projectPath "tools"
                        
                        $tools = @("codemunch", "contextlattice", "memorybridge")
                        foreach ($tool in $tools) {
                            $sourceDir = Join-Path $toolkitSource $tool
                            $targetDir = Join-Path $toolsTarget $tool
                            
                            if ((Test-Path -LiteralPath $sourceDir) -and -not (Test-Path -LiteralPath $targetDir)) {
                                Copy-Item -Path $sourceDir -Destination $targetDir -Recurse -Force
                                $changes += "Synced $tool template"
                            }
                        }
                        
                        $success = $true
                        $message = "Re-synced templates from module"
                        Write-HealLog -Message "Re-synced templates" -Level "SUCCESS"
                    } catch {
                        $success = $false
                        $message = "Failed to re-sync templates: $($_.Exception.Message)"
                        $changes += "Error: $($_.Exception.Message)"
                    }
                    
                    Write-HealHistoryEntry -Operation "Repair" -IssueType $IssueType -Status $(if ($success) { "Success" } else { "Failed" }) `
                        -Details ($changes -join "; ") -ProjectRoot $ProjectRoot -WhatIf:$WhatIf
                }
                break
            }
            
            "MissingContextLatticeApiKey" {
                if ($WhatIf) {
                    $changes += "Would prompt for ContextLattice API key"
                    $changes += "Would add key to .env file"
                    $success = $true
                    $message = "Would configure ContextLattice API key (WhatIf mode)"
                } else {
                    $envPath = Join-Path $projectPath ".env"
                    
                    if ($Interactive -or $Force) {
                        if ($Interactive) {
                            Write-Host "ContextLattice API Key Configuration" -ForegroundColor Cyan
                            Write-Host "You can obtain an API key from your ContextLattice orchestrator." -ForegroundColor Gray
                            $apiKey = Read-SecureInput -Prompt "Enter your ContextLattice API key: "
                        } else {
                            # In Force mode without interactive, use environment key if set; otherwise use placeholder.
                            $apiKey = [Environment]::GetEnvironmentVariable("CONTEXTLATTICE_ORCHESTRATOR_API_KEY")
                            if ([string]::IsNullOrWhiteSpace($apiKey)) {
                                $apiKey = "your-api-key-here"
                            }
                        }
                        
                        $allowPlaceholder = ($Force -and -not $Interactive -and $apiKey -eq "your-api-key-here")
                        if (-not [string]::IsNullOrWhiteSpace($apiKey) -and ($apiKey -ne "your-api-key-here" -or $allowPlaceholder)) {
                            # Add to current session
                            if ($apiKey -ne "your-api-key-here") {
                                $env:CONTEXTLATTICE_ORCHESTRATOR_API_KEY = $apiKey
                                $changes += "Set API key in current session"
                            } else {
                                $changes += "Configured placeholder API key for non-interactive force mode"
                            }
                            
                            # Add to .env file
                            if (Test-Path -LiteralPath $envPath) {
                                $envContent = Get-Content -LiteralPath $envPath -Raw
                                if ($envContent -match "CONTEXTLATTICE_ORCHESTRATOR_API_KEY\s*=") {
                                    # Replace existing
                                    $envContent = $envContent -replace "CONTEXTLATTICE_ORCHESTRATOR_API_KEY\s*=.*", "CONTEXTLATTICE_ORCHESTRATOR_API_KEY=$apiKey"
                                } else {
                                    # Add new
                                    $envContent += "`nCONTEXTLATTICE_ORCHESTRATOR_API_KEY=$apiKey`n"
                                }
                                $envContent | Out-File -FilePath $envPath -Encoding UTF8
                                $changes += "Updated API key in .env file"
                            } else {
                                # Create new .env with just the key
                                "CONTEXTLATTICE_ORCHESTRATOR_API_KEY=$apiKey`n" | Out-File -FilePath $envPath -Encoding UTF8
                                $changes += "Created .env file with API key"
                            }
                            
                            $success = $true
                            $message = if ($apiKey -eq "your-api-key-here") {
                                "Configured placeholder ContextLattice API key in .env (manual update required)"
                            } else {
                                "Configured ContextLattice API key"
                            }
                            Write-HealLog -Message $message -Level "SUCCESS"
                        } else {
                            $success = $false
                            $message = "No API key provided"
                            $changes += "User did not provide an API key"
                        }
                    } else {
                        $success = $false
                        $message = "Cannot configure API key in non-interactive mode without -Force"
                    }
                    
                    Write-HealHistoryEntry -Operation "Repair" -IssueType $IssueType -Status $(if ($success) { "Success" } else { "Failed" }) `
                        -Details ($changes -join "; ") -ProjectRoot $ProjectRoot -WhatIf:$WhatIf
                }
                break
            }
            
            "MissingContextLatticeUrl" {
                if ($WhatIf) {
                    $changes += "Would set default ContextLattice URL: http://127.0.0.1:8075"
                    $success = $true
                    $message = "Would set default URL (WhatIf mode)"
                } else {
                    $defaultUrl = "http://127.0.0.1:8075"
                    $env:CONTEXTLATTICE_ORCHESTRATOR_URL = $defaultUrl
                    $changes += "Set default URL in current session: $defaultUrl"
                    
                    # Also add to .env
                    $envPath = Join-Path $projectPath ".env"
                    if (Test-Path -LiteralPath $envPath) {
                        $envContent = Get-Content -LiteralPath $envPath -Raw
                        if ($envContent -notmatch "CONTEXTLATTICE_ORCHESTRATOR_URL\s*=") {
                            $envContent += "`nCONTEXTLATTICE_ORCHESTRATOR_URL=$defaultUrl`n"
                            $envContent | Out-File -FilePath $envPath -Encoding UTF8
                            $changes += "Added URL to .env file"
                        }
                    }
                    
                    $success = $true
                    $message = "Set default ContextLattice URL"
                    Write-HealLog -Message "Set default ContextLattice URL" -Level "SUCCESS"
                    
                    Write-HealHistoryEntry -Operation "Repair" -IssueType $IssueType -Status "Success" `
                        -Details ($changes -join "; ") -ProjectRoot $ProjectRoot -WhatIf:$WhatIf
                }
                break
            }
            
            "MissingBridgeConfig" {
                if ($WhatIf) {
                    $changes += "Would create default bridge.config.json"
                    $success = $true
                    $message = "Would create bridge config (WhatIf mode)"
                } else {
                    try {
                        $bridgeDir = Join-Path $projectPath ".memorybridge"
                        $configPath = Join-Path $bridgeDir "bridge.config.json"
                        
                        if (-not (Test-Path -LiteralPath $bridgeDir)) {
                            New-Item -ItemType Directory -Path $bridgeDir -Force | Out-Null
                            $changes += "Created .memorybridge directory"
                        }
                        
                        $defaultConfig = Get-DefaultBridgeConfig
                        $defaultConfig | Out-File -FilePath $configPath -Encoding UTF8
                        $changes += "Created bridge.config.json"
                        
                        $success = $true
                        $message = "Created default bridge configuration"
                        Write-HealLog -Message "Created bridge config: $configPath" -Level "SUCCESS"
                    } catch {
                        $success = $false
                        $message = "Failed to create bridge config: $($_.Exception.Message)"
                        $changes += "Error: $($_.Exception.Message)"
                    }
                    
                    Write-HealHistoryEntry -Operation "Repair" -IssueType $IssueType -Status $(if ($success) { "Success" } else { "Failed" }) `
                        -Details ($changes -join "; ") -ProjectRoot $ProjectRoot -WhatIf:$WhatIf
                }
                break
            }
            
            "CorruptedBridgeConfig" {
                $configPath = Join-Path $projectPath ".memorybridge\bridge.config.json"
                if ($WhatIf) {
                    $changes += "Would backup corrupted bridge.config.json"
                    $changes += "Would recreate bridge.config.json with defaults"
                    $success = $true
                    $message = "Would repair bridge config (WhatIf mode)"
                } else {
                    try {
                        if (Test-Path -LiteralPath $configPath) {
                            $backupPath = "$configPath.backup.$(Get-Date -Format 'yyyyMMdd_HHmmss')"
                            Copy-Item -LiteralPath $configPath -Destination $backupPath
                            $changes += "Backed up corrupted config to: $backupPath"
                        }
                        
                        $defaultConfig = Get-DefaultBridgeConfig
                        $defaultConfig | Out-File -FilePath $configPath -Encoding UTF8
                        $changes += "Recreated bridge.config.json"
                        
                        $success = $true
                        $message = "Repaired bridge configuration (backup created)"
                        Write-HealLog -Message "Repaired bridge config: $configPath" -Level "SUCCESS"
                    } catch {
                        $success = $false
                        $message = "Failed to repair bridge config: $($_.Exception.Message)"
                        $changes += "Error: $($_.Exception.Message)"
                    }
                    
                    Write-HealHistoryEntry -Operation "Repair" -IssueType $IssueType -Status $(if ($success) { "Success" } else { "Failed" }) `
                        -Details ($changes -join "; ") -ProjectRoot $ProjectRoot -WhatIf:$WhatIf
                }
                break
            }
            
            default {
                $success = $false
                $message = "Unknown issue type: $IssueType"
                $changes += "No repair action defined for this issue type"
            }
        }
    } catch {
        $success = $false
        $message = "Exception during repair: $($_.Exception.Message)"
        $changes += "Error: $($_.Exception.Message)"
        Write-HealLog -Message "Exception repairing $IssueType`: $($_.Exception.Message)" -Level "ERROR"
    }
    
    return @{
        Success = $success
        IssueType = $IssueType
        Message = $message
        Changes = $changes
    }
}

#===============================================================================
# History Functions
#===============================================================================

function Get-LLMWorkflowRepairHistory {
    <#
    .SYNOPSIS
        Retrieves the history of repair operations.
    .DESCRIPTION
        Shows past fixes applied by llmheal, including timestamps, issue types, and outcomes.
    .PARAMETER Count
        Number of recent entries to show (default: 50).
    .PARAMETER Since
        Only show entries since this date/time.
    .PARAMETER IssueType
        Filter by specific issue type.
    .PARAMETER ProjectRoot
        Filter by project root path.
    .EXAMPLE
        Get-LLMWorkflowRepairHistory
        Shows the last 50 repair operations.
    .EXAMPLE
        Get-LLMWorkflowRepairHistory -Count 10 -Since (Get-Date).AddDays(-7)
        Shows the last 10 repairs from the past week.
    #>
    [CmdletBinding()]
    [OutputType([array])]
    param(
        [int]$Count = 50,
        [DateTime]$Since = [DateTime]::MinValue,
        [IssueType[]]$IssueType = @(),
        [string]$ProjectRoot = ""
    )
    
    if (-not (Test-Path -LiteralPath $script:HealHistoryPath)) {
        Write-Verbose "No repair history found at: $script:HealHistoryPath"
        return @()
    }
    
    $entries = Get-Content -Path $script:HealHistoryPath | ForEach-Object {
        try {
            $_ | ConvertFrom-Json
        } catch {
            $null
        }
    } | Where-Object { $_ -ne $null }
    
    # Apply filters
    if ($Since -ne [DateTime]::MinValue) {
        $entries = $entries | Where-Object { 
            $entryTime = [DateTime]::Parse($_.timestamp)
            $entryTime -ge $Since
        }
    }
    
    if ($IssueType.Count -gt 0) {
        $typeNames = $IssueType | ForEach-Object { $_.ToString() }
        $entries = $entries | Where-Object { $typeNames -contains $_.issueType }
    }
    
    if (-not [string]::IsNullOrWhiteSpace($ProjectRoot)) {
        $resolvedRoot = Resolve-HealLiteralPath -LiteralPath $ProjectRoot -Context 'Repair-history project-root resolution'
        if ($resolvedRoot) {
            $entries = $entries | Where-Object { $_.projectRoot -eq $resolvedRoot }
        }
    }
    
    # Sort by timestamp (newest first) and take requested count
    $entries = $entries | Sort-Object { [DateTime]::Parse($_.timestamp) } -Descending | Select-Object -First $Count
    
    return $entries
}

function Clear-LLMWorkflowRepairHistory {
    <#
    .SYNOPSIS
        Clears the repair history log.
    .DESCRIPTION
        Removes all repair history entries. Use with caution.
    .PARAMETER Confirm
        Confirm the deletion.
    .EXAMPLE
        Clear-LLMWorkflowRepairHistory -Confirm
        Clears all repair history after confirmation.
    #>
    [CmdletBinding()]
    param(
        [switch]$Confirm
    )
    
    if (-not $Confirm) {
        Write-Warning "Use -Confirm to clear repair history. This action cannot be undone."
        return
    }
    
    if (Test-Path -LiteralPath $script:HealHistoryPath) {
        Remove-Item -LiteralPath $script:HealHistoryPath -Force
        Write-Host "Repair history cleared." -ForegroundColor Green
    } else {
        Write-Host "No repair history to clear." -ForegroundColor Yellow
    }
}

function Export-LLMWorkflowRepairHistory {
    <#
    .SYNOPSIS
        Exports repair history to a file.
    .DESCRIPTION
        Exports the repair history to JSON or CSV format.
    .PARAMETER OutputPath
        Path to the output file.
    .PARAMETER Format
        Output format: json or csv.
    .EXAMPLE
        Export-LLMWorkflowRepairHistory -OutputPath "repairs.json"
        Exports history to JSON file.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [string]$OutputPath,
        
        [ValidateSet("json", "csv")]
        [string]$Format = "json"
    )
    
    $entries = Get-LLMWorkflowRepairHistory -Count 10000
    
    switch ($Format) {
        "json" {
            $entries | ConvertTo-Json -Depth 5 | Out-File -FilePath $OutputPath -Encoding UTF8
        }
        "csv" {
            $entries | ForEach-Object {
                [pscustomobject]@{
                    Timestamp = $_.timestamp
                    Operation = $_.operation
                    IssueType = $_.issueType
                    Status = $_.status
                    Details = $_.details
                    ProjectRoot = $_.projectRoot
                    WhatIf = $_.whatIf
                    Version = $_.version
                }
            } | Export-Csv -Path $OutputPath -NoTypeInformation -Encoding UTF8
        }
    }
    
    Write-Host "Exported $($entries.Count) entries to: $OutputPath" -ForegroundColor Green
}

#===============================================================================
# Main Heal Function
#===============================================================================

function Invoke-LLMWorkflowHeal {
    <#
    .SYNOPSIS
        Diagnoses and fixes common LLM Workflow issues automatically.
    .DESCRIPTION
        Performs comprehensive diagnosis of the LLM Workflow environment and 
        offers to automatically fix detected issues. Supports WhatIf mode for
        previewing changes and Force mode for unattended operation.
    .PARAMETER ProjectRoot
        Path to the project root (default: current directory).
    .PARAMETER WhatIf
        Show what would be fixed without making changes.
    .PARAMETER Force
        Auto-apply all fixes without prompting.
    .PARAMETER Interactive
        Show interactive prompts for user input.
    .PARAMETER IncludeInfo
        Include INFO-level issues in diagnosis.
    .PARAMETER OnlyCritical
        Only check and fix CRITICAL issues.
    .PARAMETER IssueTypes
        Specific issue types to check (default: all).
    .EXAMPLE
        Invoke-LLMWorkflowHeal
        Interactive diagnosis with prompts for each fix.
    .EXAMPLE
        llmheal -WhatIf
        Preview what would be fixed without making changes.
    .EXAMPLE
        llmheal -Force
        Auto-apply all fixes without prompting.
    .EXAMPLE
        llmheal -OnlyCritical -Force
        Fix only critical issues automatically.
    .ALIAS
        llmheal
    #>
    [CmdletBinding()]
    param(
        [string]$ProjectRoot = ".",
        [switch]$WhatIf,
        [switch]$Force,
        [switch]$Interactive = $true,
        [switch]$IncludeInfo,
        [switch]$OnlyCritical,
        [IssueType[]]$IssueTypes = @()
    )

    if ($Force) {
        # Force mode is intended for unattended execution; disable interactive prompts.
        $Interactive = $false
    }
    
    # Initialize
    Initialize-HealHistoryStore
    Write-HealLog -Message "Starting heal operation on: $ProjectRoot (WhatIf=$WhatIf, Force=$Force)" -Level "INFO"
    
    $startTime = Get-Date
    $projectPath = Resolve-HealLiteralPath -LiteralPath $ProjectRoot -Context 'Heal invocation project-root resolution'
    
    if (-not $projectPath) {
        Write-Error "Project root does not exist: $ProjectRoot"
        return
    }
    
    Write-Host "`n========================================" -ForegroundColor Cyan
    Write-Host "   LLM Workflow Self-Healing" -ForegroundColor Cyan
    Write-Host "========================================`n" -ForegroundColor Cyan
    
    Write-Host "Project: $projectPath" -ForegroundColor Gray
    Write-Host "Mode: $(if ($WhatIf) { 'WhatIf (preview only)' } elseif ($Force) { 'Force (auto-apply)' } else { 'Interactive' })" -ForegroundColor Gray
    Write-Host ""
    
    # Determine which issues to check
    $allIssueTypes = @(
        [IssueType]::MissingEnvFile,
        [IssueType]::InvalidPythonPath,
        [IssueType]::MissingChromaDB,
        [IssueType]::MissingPalaceDirectory,
        [IssueType]::CorruptedSyncState,
        [IssueType]::TemplateDrift,
        [IssueType]::MissingContextLatticeApiKey,
        [IssueType]::MissingContextLatticeUrl,
        [IssueType]::MissingBridgeConfig,
        [IssueType]::CorruptedBridgeConfig
    )
    
    if ($IssueTypes.Count -gt 0) {
        $issuesToCheck = $IssueTypes
    } else {
        $issuesToCheck = $allIssueTypes
    }
    
    # Phase 1: Diagnosis
    Write-Host "Phase 1: Diagnosis" -ForegroundColor Yellow
    Write-Host "------------------" -ForegroundColor Yellow
    
    $detectedIssues = @()
    foreach ($issueType in $issuesToCheck) {
        Write-Host "  Checking $($issueType.ToString())... " -NoNewline -ForegroundColor Gray
        $result = Test-LLMWorkflowIssue -IssueType $issueType -ProjectRoot $ProjectRoot
        
        if ($result.Detected) {
            $color = switch ($result.Category) {
                ([IssueCategory]::CRITICAL) { "Red" }
                ([IssueCategory]::WARNING) { "Yellow" }
                ([IssueCategory]::INFO) { "Cyan" }
            }
            $prefix = switch ($result.Category) {
                ([IssueCategory]::CRITICAL) { "[CRITICAL]" }
                ([IssueCategory]::WARNING) { "[WARNING]" }
                ([IssueCategory]::INFO) { "[INFO]" }
            }
            
            if ($result.Category -eq [IssueCategory]::INFO -and -not $IncludeInfo) {
                Write-Host "OK (info skipped)" -ForegroundColor Green
                continue
            }
            
            if ($OnlyCritical -and $result.Category -ne [IssueCategory]::CRITICAL) {
                Write-Host "OK (non-critical skipped)" -ForegroundColor Green
                continue
            }
            
            Write-Host "$prefix $($result.Message)" -ForegroundColor $color
            
            $detectedIssues += [pscustomobject]@{
                IssueType = $issueType
                Category = $result.Category
                Message = $result.Message
                Details = $result.Details
                CanFix = $result.CanFix
                FixDescription = $result.FixDescription
            }
        } else {
            Write-Host "OK" -ForegroundColor Green
        }
    }
    
    Write-Host ""
    
    # Summary of diagnosis
    $criticalCount = @($detectedIssues | Where-Object { $_.Category -eq [IssueCategory]::CRITICAL }).Count
    $warningCount = @($detectedIssues | Where-Object { $_.Category -eq [IssueCategory]::WARNING }).Count
    $infoCount = @($detectedIssues | Where-Object { $_.Category -eq [IssueCategory]::INFO }).Count
    $fixableCount = @($detectedIssues | Where-Object { $_.CanFix }).Count
    
    Write-Host "Diagnosis Summary:" -ForegroundColor Yellow
    Write-Host "  Critical issues: $criticalCount" -ForegroundColor $(if ($criticalCount -gt 0) { "Red" } else { "Green" })
    Write-Host "  Warnings: $warningCount" -ForegroundColor $(if ($warningCount -gt 0) { "Yellow" } else { "Green" })
    Write-Host "  Info: $infoCount" -ForegroundColor Cyan
    Write-Host "  Auto-fixable: $fixableCount" -ForegroundColor $(if ($fixableCount -gt 0) { "Cyan" } else { "Gray" })
    Write-Host ""
    
    if ($detectedIssues.Count -eq 0) {
        Write-Host "No issues detected! Your LLM Workflow environment looks healthy." -ForegroundColor Green
        Write-Host ""
        return [pscustomobject]@{
            Success = $true
            IssuesFound = 0
            IssuesFixed = 0
            Duration = (Get-Date) - $startTime
            Details = @()
        }
    }
    
    # Phase 2: Repair
    Write-Host "Phase 2: Repair" -ForegroundColor Yellow
    Write-Host "---------------" -ForegroundColor Yellow
    Write-Host ""
    
    $repairResults = @()
    $fixedCount = 0
    $failedCount = 0
    $skippedCount = 0
    
    foreach ($issue in $detectedIssues) {
        if (-not $issue.CanFix) {
            Write-Host "[$($issue.Category)] $($issue.IssueType): Cannot auto-fix" -ForegroundColor Gray
            $skippedCount++
            continue
        }
        
        $shouldFix = $Force
        
        if (-not $Force -and $Interactive -and -not $WhatIf) {
            Write-Host ""
            Write-Host "Issue: $($issue.IssueType)" -ForegroundColor $(if ($issue.Category -eq [IssueCategory]::CRITICAL) { "Red" } else { "Yellow" })
            Write-Host "Description: $($issue.Message)" -ForegroundColor Gray
            Write-Host "Proposed fix: $($issue.FixDescription)" -ForegroundColor Cyan
            $response = Read-Host "Apply fix? [Y/n]"
            $shouldFix = ($response -eq "" -or $response -match "^[Yy]")
        }
        
        if ($WhatIf) {
            Write-Host "[WHATIF] Would fix: $($issue.IssueType) - $($issue.FixDescription)" -ForegroundColor Cyan
            $repairResults += [pscustomobject]@{
                IssueType = $issue.IssueType
                Category = $issue.Category
                Status = "WouldFix"
                Message = $issue.FixDescription
                Changes = @()
            }
        } elseif ($shouldFix) {
            Write-Host "  Fixing $($issue.IssueType)... " -NoNewline -ForegroundColor Gray
            
            $repairResult = Repair-LLMWorkflowIssue `
                -IssueType $issue.IssueType `
                -ProjectRoot $ProjectRoot `
                -WhatIf:$WhatIf `
                -Force:$Force `
                -Interactive:$Interactive
            
            if ($repairResult.Success) {
                Write-Host "FIXED" -ForegroundColor Green
                $fixedCount++
            } else {
                Write-Host "FAILED" -ForegroundColor Red
                Write-Host "    $($repairResult.Message)" -ForegroundColor Red
                $failedCount++
            }
            
            $repairResults += [pscustomobject]@{
                IssueType = $issue.IssueType
                Category = $issue.Category
                Status = $(if ($repairResult.Success) { "Fixed" } else { "Failed" })
                Message = $repairResult.Message
                Changes = $repairResult.Changes
            }
        } else {
            Write-Host "  Skipped: $($issue.IssueType)" -ForegroundColor Gray
            $skippedCount++
            $repairResults += [pscustomobject]@{
                IssueType = $issue.IssueType
                Category = $issue.Category
                Status = "Skipped"
                Message = "User declined"
                Changes = @()
            }
        }
    }
    
    Write-Host ""
    Write-Host "========================================" -ForegroundColor Cyan
    Write-Host "   Repair Summary" -ForegroundColor Cyan
    Write-Host "========================================" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "Total issues found: $($detectedIssues.Count)" -ForegroundColor White
    Write-Host "  Fixed: $fixedCount" -ForegroundColor Green
    Write-Host "  Failed: $failedCount" -ForegroundColor $(if ($failedCount -gt 0) { "Red" } else { "Green" })
    Write-Host "  Skipped: $skippedCount" -ForegroundColor Gray
    Write-Host ""
    
    $duration = (Get-Date) - $startTime
    Write-Host "Duration: $($duration.ToString('mm\:ss'))" -ForegroundColor Gray
    Write-Host ""
    
    # Log completion
    Write-HealLog -Message "Heal operation completed. Found: $($detectedIssues.Count), Fixed: $fixedCount, Failed: $failedCount" -Level $(if ($failedCount -eq 0) { "SUCCESS" } else { "WARN" })
    
    # Return result object
    return [pscustomobject]@{
        Success = ($failedCount -eq 0)
        IssuesFound = $detectedIssues.Count
        IssuesFixed = $fixedCount
        IssuesFailed = $failedCount
        IssuesSkipped = $skippedCount
        Duration = $duration
        Details = $repairResults
    }
}

#===============================================================================
# Export Module Members
#===============================================================================

if ($ExecutionContext.SessionState.Module) {
    Export-ModuleMember -Function @(
        'Invoke-LLMWorkflowHeal',
        'Test-LLMWorkflowIssue',
        'Repair-LLMWorkflowIssue',
        'Get-LLMWorkflowRepairHistory',
        'Clear-LLMWorkflowRepairHistory',
        'Export-LLMWorkflowRepairHistory'
    )
}
