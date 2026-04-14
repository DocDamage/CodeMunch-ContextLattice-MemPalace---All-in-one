# LLM Workflow Toolkit - Windows Container Entrypoint
# Handles initialization and runs llmup or custom commands

param(
    [Parameter(Position = 0)]
    [string]$Command = "llmup"
)

$ErrorActionPreference = "Stop"

# Configuration
$script:WorkflowRoot = "C:\llm-workflow"
$script:ModulePath = "C:\Users\ContainerAdministrator\Documents\PowerShell\Modules\LLMWorkflow"
$script:PalacePath = if ($env:MEMPALACE_PALACE_PATH) { $env:MEMPALACE_PALACE_PATH } else { "C:\mempalace" }

# Logging functions
function Write-Info {
    param([string]$Message)
    Write-Host "[llm-workflow] $Message" -ForegroundColor Cyan
}

function Write-Success {
    param([string]$Message)
    Write-Host "[llm-workflow] $Message" -ForegroundColor Green
}

function Write-Warn {
    param([string]$Message)
    Write-Host "[llm-workflow] $Message" -ForegroundColor Yellow
}

function Write-Error {
    param([string]$Message)
    Write-Host "[llm-workflow] $Message" -ForegroundColor Red
}

# Check if running in container
function Test-ContainerEnvironment {
    $inContainer = $false
    
    # Check for common container indicators
    if (Test-Path -Path "C:\.dockerenv") { $inContainer = $true }
    if ($env:CONTAINER -eq "true") { $inContainer = $true }
    if ($env:KUBERNETES_SERVICE_HOST) { $inContainer = $true }
    
    if ($inContainer) {
        Write-Info "Running in container environment"
    }
    
    return $inContainer
}

# Initialize workspace directory
function Initialize-Workspace {
    param([string]$Workspace = "C:\workspace")
    
    Write-Info "Initializing workspace: $Workspace"
    
    if (-not (Test-Path -Path $Workspace)) {
        Write-Warn "Creating workspace directory: $Workspace"
        New-Item -ItemType Directory -Path $Workspace -Force | Out-Null
    }
    
    # Create necessary subdirectories
    New-Item -ItemType Directory -Path "$Workspace\.memorybridge" -Force | Out-Null
    New-Item -ItemType Directory -Path "$Workspace\.contextlattice" -Force | Out-Null
    
    Write-Success "Workspace initialized"
}

# Initialize MemPalace data directory
function Initialize-MemPalace {
    Write-Info "Initializing MemPalace at: $script:PalacePath"
    
    if (-not (Test-Path -Path $script:PalacePath)) {
        New-Item -ItemType Directory -Path $script:PalacePath -Force | Out-Null
    }
    
    Write-Success "MemPalace initialized"
}

# Verify Python dependencies
function Test-PythonDependencies {
    Write-Info "Verifying Python dependencies..."
    
    # Check chromadb
    try {
        $result = python -c "import chromadb; print('OK')" 2>$null
        if ($result -eq "OK") {
            Write-Success "ChromaDB is available"
        } else {
            throw "ChromaDB import failed"
        }
    } catch {
        Write-Error "ChromaDB is not installed"
        return $false
    }
    
    # Check codemunch-pro
    $cmd = Get-Command codemunch-pro -ErrorAction SilentlyContinue
    if ($cmd) {
        Write-Success "codemunch-pro is available"
    } else {
        Write-Warn "codemunch-pro not found, installing..."
        python -m pip install codemunch-pro
        if ($LASTEXITCODE -ne 0) {
            Write-Error "Failed to install codemunch-pro"
            return $false
        }
    }
    
    return $true
}

# Verify PowerShell module
function Test-PowerShellModule {
    Write-Info "Verifying PowerShell module..."
    
    try {
        Import-Module LLMWorkflow -Force -ErrorAction Stop
        Write-Success "PowerShell module verified"
        return $true
    } catch {
        Write-Error "Failed to load LLMWorkflow module: $_"
        return $false
    }
}

# Load environment from mounted files
function Import-EnvironmentFiles {
    param([string]$Workspace = "C:\workspace")
    
    # Load .env from workspace if exists
    $envFile = Join-Path $Workspace ".env"
    if (Test-Path -Path $envFile) {
        Write-Info "Loading environment from $envFile"
        # Parse and set environment variables
        Get-Content $envFile | ForEach-Object {
            $line = $_.Trim()
            if ($line -and -not $line.StartsWith("#")) {
                if ($line -match "^(?:export\s+)?([A-Za-z_][A-Za-z0-9_]*)\s*=\s*(.*)$") {
                    $name = $matches[1]
                    $value = $matches[2].Trim('"', "'")
                    [Environment]::SetEnvironmentVariable($name, $value, "Process")
                }
            }
        }
    }
    
    # Load orchestrator.env if exists
    $orchEnvFile = Join-Path $Workspace ".contextlattice\orchestrator.env"
    if (Test-Path -Path $orchEnvFile) {
        Write-Info "Loading environment from $orchEnvFile"
        Get-Content $orchEnvFile | ForEach-Object {
            $line = $_.Trim()
            if ($line -and -not $line.StartsWith("#")) {
                if ($line -match "^(?:export\s+)?([A-Za-z_][A-Za-z0-9_]*)\s*=\s*(.*)$") {
                    $name = $matches[1]
                    $value = $matches[2].Trim('"', "'")
                    [Environment]::SetEnvironmentVariable($name, $value, "Process")
                }
            }
        }
    }
}

# Display help
function Show-Help {
    @"
LLM Workflow Toolkit - Windows Container Usage

Commands:
  llmup, up              Run llmup workflow bootstrap (default)
  llmcheck, check        Run setup validation
  llmver, version        Show version information
  llmdown, uninstall     Uninstall workflow
  llmupdate, update      Update workflow module
  doctor                 Run diagnostics
  shell, cmd             Start Command Prompt
  pwsh, powershell       Start PowerShell
  help                   Show this help message

Environment Variables:
  OPENAI_API_KEY         OpenAI API key
  ANTHROPIC_API_KEY      Anthropic/Claude API key
  KIMI_API_KEY           Moonshot/Kimi API key
  GEMINI_API_KEY         Google Gemini API key
  GLM_API_KEY            Zhipu GLM API key
  CONTEXTLATTICE_ORCHESTRATOR_URL    ContextLattice URL
  CONTEXTLATTICE_ORCHESTRATOR_API_KEY  ContextLattice API key
  MEMPALACE_PALACE_PATH  MemPalace data directory

Examples:
  # Run llmup
  docker run -v ${PWD}:C:\workspace llm-workflow

  # Interactive PowerShell
  docker run -it -v ${PWD}:C:\workspace llm-workflow pwsh
"@
}

# Main execution
Write-Info "LLM Workflow Toolkit Container v0.9.6 (Windows)"

# Initialize
Test-ContainerEnvironment
Initialize-Workspace "C:\workspace"
Initialize-MemPalace
Import-EnvironmentFiles "C:\workspace"

# Verify dependencies
if (-not (Test-PythonDependencies)) { exit 1 }
if (-not (Test-PowerShellModule)) { exit 1 }

# Handle command
switch ($Command.ToLower()) {
    { $_ -in @("llmup", "up", "") } {
        Write-Info "Running llmup..."
        Set-Location "C:\workspace"
        & pwsh -NoProfile -Command "llmup"
    }
    { $_ -in @("llmcheck", "check") } {
        Write-Info "Running llmcheck..."
        Set-Location "C:\workspace"
        & pwsh -NoProfile -Command "llmcheck"
    }
    { $_ -in @("llmver", "version") } {
        & pwsh -NoProfile -Command "llmver"
    }
    { $_ -in @("llmdown", "uninstall") } {
        Write-Info "Running llmdown..."
        & pwsh -NoProfile -Command "llmdown"
    }
    { $_ -in @("llmupdate", "update") } {
        Write-Info "Running llmupdate..."
        & pwsh -NoProfile -Command "llmupdate"
    }
    "doctor" {
        Write-Info "Running diagnostics..."
        Set-Location "C:\workspace"
        & pwsh -NoProfile -Command "Test-LLMWorkflowSetup -CheckConnectivity"
    }
    { $_ -in @("shell", "cmd") } {
        Write-Info "Starting Command Prompt..."
        & cmd.exe
    }
    { $_ -in @("pwsh", "powershell") } {
        Write-Info "Starting PowerShell..."
        & pwsh.exe
    }
    { $_ -in @("help", "--help", "-h") } {
        Show-Help
    }
    default {
        # Pass through to PowerShell
        Write-Info "Executing: $Command"
        & pwsh -NoProfile -Command $Command
    }
}

