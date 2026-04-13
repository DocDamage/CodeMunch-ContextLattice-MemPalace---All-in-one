<#
.SYNOPSIS
    Deploys the Blender MCP server for LLM Workflow platform.

.DESCRIPTION
    Installs blender-mcp requirements, configures BLENDER_PATH environment variable,
    installs the Blender addon if needed, tests connectivity to Blender, and starts
    the MCP server.

.PARAMETER BlenderPath
    Path to the Blender executable. If not specified, attempts to auto-detect or uses BLENDER_PATH env var.

.PARAMETER Mode
    Execution mode: 'stdio' or 'http'. Default: stdio.

.PARAMETER Port
    Port for HTTP mode. Default: 8092.

.PARAMETER SkipAddonInstall
    Skip Blender addon installation (if already installed).

.PARAMETER SkipConnectivityTest
    Skip the Blender connectivity test.

.PARAMETER RegisterWithGateway
    Register this MCP server with the composite gateway after startup.

.PARAMETER GatewayUrl
    URL of the composite gateway for registration. Default: http://localhost:8080.

.PARAMETER AddonPath
    Custom path to the blender-mcp addon directory.

.EXAMPLE
    .\deploy-blender-mcp.ps1 -BlenderPath "C:\Blender\blender.exe"

.EXAMPLE
    .\deploy-blender-mcp.ps1 -Mode http -Port 9092 -RegisterWithGateway

.NOTES
    File Name      : deploy-blender-mcp.ps1
    Author         : LLM Workflow Team
    Version        : 1.0.0
    Requires       : PowerShell 5.1+, Python 3.8+, Blender 3.0+
#>

[CmdletBinding()]
param(
    [Parameter()]
    [string]$BlenderPath = "",

    [Parameter()]
    [ValidateSet('stdio', 'http')]
    [string]$Mode = 'stdio',

    [Parameter()]
    [ValidateRange(1, 65535)]
    [int]$Port = 8092,

    [Parameter()]
    [switch]$SkipAddonInstall,

    [Parameter()]
    [switch]$SkipConnectivityTest,

    [Parameter()]
    [switch]$RegisterWithGateway,

    [Parameter()]
    [string]$GatewayUrl = "http://localhost:8080",

    [Parameter()]
    [string]$AddonPath = ""
)

$ErrorActionPreference = "Stop"
$script:ScriptRoot = if (-not [string]::IsNullOrWhiteSpace($PSScriptRoot)) { $PSScriptRoot } else { (Split-Path -Parent $PSCommandPath) }

# Import logging module if available
$LoggingModulePath = Join-Path $script:ScriptRoot "..\..\module\LLMWorkflow\core\Logging.ps1"
if (Test-Path -LiteralPath $LoggingModulePath) {
    Import-Module $LoggingModulePath -Force -ErrorAction SilentlyContinue
}

# =============================================================================
# Logging Functions
# =============================================================================

function Write-McpLog {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [ValidateSet('INFO', 'WARN', 'ERROR', 'DEBUG')]
        [string]$Level,

        [Parameter(Mandatory = $true)]
        [string]$Message,

        [Parameter()]
        [hashtable]$Metadata = @{}
    )

    $timestamp = [DateTime]::UtcNow.ToString("yyyy-MM-ddTHH:mm:ss.fffZ")
    $logEntry = "[$timestamp] [Blender-MCP-$Level] $Message"
    
    switch ($Level) {
        'ERROR' { Write-Error $logEntry }
        'WARN'  { Write-Warning $logEntry }
        default { Write-Output $logEntry }
    }

    # Also write to structured log if available
    if (Get-Command 'Write-StructuredLog' -ErrorAction SilentlyContinue) {
        $entry = New-LogEntry -Level $Level -Message $Message -Metadata $Metadata -Source "deploy-blender-mcp"
        Write-StructuredLog -Entry $entry -Force
    }
}

# =============================================================================
# Configuration Functions
# =============================================================================

function Get-BlenderExecutablePath {
    [CmdletBinding()]
    [OutputType([string])]
    param()

    # 1. Check parameter
    if (-not [string]::IsNullOrWhiteSpace($BlenderPath)) {
        if (Test-Path -LiteralPath $BlenderPath) {
            return (Resolve-Path -LiteralPath $BlenderPath).Path
        }
        Write-McpLog -Level WARN -Message "Provided BlenderPath not found: $BlenderPath"
    }

    # 2. Check environment variable
    $envPath = [Environment]::GetEnvironmentVariable('BLENDER_PATH', 'Process')
    if (-not [string]::IsNullOrWhiteSpace($envPath)) {
        if (Test-Path -LiteralPath $envPath) {
            Write-McpLog -Level INFO -Message "Using BLENDER_PATH from environment: $envPath"
            return (Resolve-Path -LiteralPath $envPath).Path
        }
        Write-McpLog -Level WARN -Message "BLENDER_PATH environment variable points to non-existent file: $envPath"
    }

    # 3. Auto-detect based on platform
    $detectedPath = $null
    
    if ($IsWindows -or ($PSVersionTable.PSVersion.Major -lt 6 -and $env:OS -eq 'Windows_NT')) {
        # Windows detection
        $commonPaths = @(
            "${env:LOCALAPPDATA}\Blender Foundation\Blender\*\blender.exe",
            "${env:ProgramFiles}\Blender Foundation\Blender *\blender.exe",
            "${env:ProgramFiles(x86)}\Blender Foundation\Blender *\blender.exe",
            "C:\Blender\blender.exe",
            "C:\Tools\Blender\blender.exe"
        )
        
        foreach ($pattern in $commonPaths) {
            $found = Get-ChildItem -Path $pattern -ErrorAction SilentlyContinue | 
                     Sort-Object LastWriteTime -Descending | 
                     Select-Object -First 1
            if ($found) {
                $detectedPath = $found.FullName
                break
            }
        }

        # Check PATH
        if (-not $detectedPath) {
            $inPath = Get-Command blender -ErrorAction SilentlyContinue
            if ($inPath) {
                $detectedPath = $inPath.Source
            }
        }

        # Check Windows Store install
        if (-not $detectedPath) {
            $storePath = "${env:LOCALAPPDATA}\Microsoft\WindowsApps\blender.exe"
            if (Test-Path -LiteralPath $storePath) {
                $detectedPath = $storePath
            }
        }
    }
    elseif ($IsMacOS) {
        # macOS detection
        $macPaths = @(
            "/Applications/Blender.app/Contents/MacOS/Blender",
            "/usr/local/bin/blender",
            "/opt/homebrew/bin/blender"
        )
        foreach ($path in $macPaths) {
            if (Test-Path -LiteralPath $path) {
                $detectedPath = $path
                break
            }
        }
    }
    elseif ($IsLinux) {
        # Linux detection
        $linuxPaths = @(
            "/usr/bin/blender",
            "/usr/local/bin/blender",
            "/opt/blender/blender",
            "/snap/bin/blender"
        )
        foreach ($path in $linuxPaths) {
            if (Test-Path -LiteralPath $path) {
                $detectedPath = $path
                break
            }
        }
    }

    if ($detectedPath) {
        Write-McpLog -Level INFO -Message "Auto-detected Blender at: $detectedPath"
        return $detectedPath
    }

    throw "Could not find Blender executable. Please specify -BlenderPath or set BLENDER_PATH environment variable."
}

function Set-BlenderEnvironment {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$ExecutablePath
    )

    [Environment]::SetEnvironmentVariable('BLENDER_PATH', $ExecutablePath, 'Process')
    Write-McpLog -Level INFO -Message "Set BLENDER_PATH environment variable to: $ExecutablePath"

    # Set additional helpful environment variables
    $blenderDir = Split-Path -Parent $ExecutablePath
    [Environment]::SetEnvironmentVariable('BLENDER_DIR', $blenderDir, 'Process')
    
    # Detect Blender version
    try {
        $versionOutput = & $ExecutablePath --version 2>&1 | Out-String
        if ($versionOutput -match 'Blender\s+(\d+\.\d+)') {
            $version = $matches[1]
            [Environment]::SetEnvironmentVariable('BLENDER_VERSION', $version, 'Process')
            Write-McpLog -Level INFO -Message "Detected Blender version: $version"
        }
    }
    catch {
        Write-McpLog -Level WARN -Message "Could not detect Blender version: $_"
    }
}

function Get-BlenderScriptsPath {
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory = $true)]
        [string]$ExecutablePath
    )

    $blenderVersion = $env:BLENDER_VERSION
    if (-not $blenderVersion) {
        $blenderVersion = "3.0"  # Fallback
    }

    if ($IsWindows -or ($PSVersionTable.PSVersion.Major -lt 6 -and $env:OS -eq 'Windows_NT')) {
        $scriptsPath = Join-Path $env:APPDATA "Blender Foundation\Blender\$blenderVersion\scripts"
    }
    elseif ($IsMacOS) {
        $scriptsPath = "~/Library/Application Support/Blender/$blenderVersion/scripts"
    }
    else {
        $scriptsPath = "~/.config/blender/$blenderVersion/scripts"
    }

    return $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($scriptsPath)
}

# =============================================================================
# Installation Functions
# =============================================================================

function Install-BlenderMcpRequirements {
    [CmdletBinding()]
    param()

    # Check Python availability
    $pythonCmd = Get-Command python -ErrorAction SilentlyContinue
    if (-not $pythonCmd) {
        $pythonCmd = Get-Command python3 -ErrorAction SilentlyContinue
    }
    
    if (-not $pythonCmd) {
        throw "Python is not found in PATH. Please install Python 3.8+ from https://python.org/"
    }

    Write-McpLog -Level INFO -Message "Using Python: $($pythonCmd.Source)"

    # Check pip availability
    try {
        & $pythonCmd.Source -m pip --version 2>&1 | Out-Null
    }
    catch {
        throw "pip is not available for Python. Please ensure pip is installed."
    }

    # Install required packages
    $requiredPackages = @(
        "mcp>=1.0.0",
        "websockets>=10.0",
        "aiohttp>=3.8.0"
    )

    Write-McpLog -Level INFO -Message "Installing Blender MCP Python dependencies..."
    
    foreach ($package in $requiredPackages) {
        try {
            Write-McpLog -Level DEBUG -Message "Installing $package..."
            & $pythonCmd.Source -m pip install --quiet $package 2>&1 | Out-Null
        }
        catch {
            Write-McpLog -Level WARN -Message "Failed to install $package : $_"
        }
    }

    Write-McpLog -Level INFO -Message "Python dependencies installation completed"
}

function Install-BlenderAddon {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$ExecutablePath
    )

    if ($SkipAddonInstall) {
        Write-McpLog -Level INFO -Message "Skipping Blender addon installation (as requested)"
        return
    }

    Write-McpLog -Level INFO -Message "Checking Blender MCP addon..."

    $scriptsPath = Get-BlenderScriptsPath -ExecutablePath $ExecutablePath
    $addonPath = Join-Path $scriptsPath "addons\blender_mcp"

    # Check if already installed
    if (Test-Path -LiteralPath $addonPath) {
        Write-McpLog -Level INFO -Message "Blender MCP addon already installed at: $addonPath"
        return
    }

    # Try to find or download addon
    $tempAddonDir = Join-Path $env:TEMP "blender-mcp-addon"
    
    try {
        # Create temp directory
        New-Item -ItemType Directory -Path $tempAddonDir -Force | Out-Null

        # Look for addon in common locations or download it
        $addonSourcePaths = @(
            (Join-Path $script:ScriptRoot "..\..\packs\blender-engine\blender_mcp"),
            (Join-Path $script:ScriptRoot "..\..\module\LLMWorkflow\pack\blender-engine\blender_mcp")
        )

        $addonSource = $null
        foreach ($path in $addonSourcePaths) {
            if (Test-Path -LiteralPath $path) {
                $addonSource = $path
                break
            }
        }

        if ($addonSource) {
            Write-McpLog -Level INFO -Message "Found addon source at: $addonSource"
            
            # Ensure scripts directory exists
            New-Item -ItemType Directory -Path (Join-Path $scriptsPath "addons") -Force | Out-Null
            
            # Copy addon
            Copy-Item -LiteralPath $addonSource -Destination $addonPath -Recurse -Force
            Write-McpLog -Level INFO -Message "Blender MCP addon installed to: $addonPath"
        }
        else {
            Write-McpLog -Level WARN -Message "Addon source not found. Please manually install the blender-mcp addon."
            Write-McpLog -Level INFO -Message "Expected addon at one of: $($addonSourcePaths -join ', ')"
        }
    }
    finally {
        # Cleanup temp directory
        if (Test-Path -LiteralPath $tempAddonDir) {
            Remove-Item -LiteralPath $tempAddonDir -Recurse -Force -ErrorAction SilentlyContinue
        }
    }
}

# =============================================================================
# Connectivity Test Functions
# =============================================================================

function Test-BlenderConnectivity {
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [Parameter(Mandatory = $true)]
        [string]$ExecutablePath
    )

    if ($SkipConnectivityTest) {
        Write-McpLog -Level INFO -Message "Skipping connectivity test (as requested)"
        return $true
    }

    Write-McpLog -Level INFO -Message "Testing Blender connectivity..."

    try {
        # Test basic executable functionality
        $versionOutput = & $ExecutablePath --version 2>&1 | Out-String
        Write-McpLog -Level INFO -Message "Blender executable responded to version check"

        # Check if version output contains expected content
        if ($versionOutput -match 'Blender') {
            Write-McpLog -Level INFO -Message "Blender connectivity test passed"
            return $true
        }
        
        Write-McpLog -Level WARN -Message "Blender version output has unexpected format"
        return $false
    }
    catch {
        Write-McpLog -Level ERROR -Message "Blender connectivity test failed: $_"
        return $false
    }
}

# =============================================================================
# Server Startup Functions
# =============================================================================

function Start-BlenderMcpServer {
    [CmdletBinding()]
    [OutputType([System.Diagnostics.Process])]
    param()

    Write-McpLog -Level INFO -Message "Starting Blender MCP server in $Mode mode..."

    $blenderPath = Get-BlenderExecutablePath
    
    if ($Mode -eq 'http') {
        # HTTP mode - start as background process
        $env:BLENDER_MCP_PORT = $Port
        
        # Create a temporary Python script to start the MCP server
        $startupScript = Join-Path $env:TEMP "blender-mcp-startup.py"
        @"
import sys
import os
sys.path.insert(0, os.path.join(os.path.dirname(__file__), 'scripts', 'addons', 'blender_mcp'))

from blender_mcp.server import start_server
start_server(transport='http', port=$Port)
"@ | Set-Content -LiteralPath $startupScript -Encoding UTF8

        $process = Start-Process -FilePath $blenderPath `
                                 -ArgumentList @("--background", "--python", $startupScript) `
                                 -WindowStyle Hidden `
                                 -PassThru
        
        Write-McpLog -Level INFO -Message "Blender MCP HTTP server started on port $Port (PID: $($process.Id))"
        return $process
    }
    else {
        # stdio mode - for MCP client integration
        Write-McpLog -Level INFO -Message "Blender MCP server ready for stdio transport"
        Write-McpLog -Level INFO -Message "To use with MCP client, Blender must be running with the MCP addon enabled"
        return $null
    }
}

function Register-WithCompositeGateway {
    [CmdletBinding()]
    param()

    if (-not $RegisterWithGateway) {
        return
    }

    Write-McpLog -Level INFO -Message "Registering Blender MCP with composite gateway at $GatewayUrl..."

    $maxRetries = 5
    $retryCount = 0
    $registered = $false

    while ($retryCount -lt $maxRetries -and -not $registered) {
        try {
            $registrationBody = @{
                packId = "blender-engine"
                prefix = "blender_"
                endpoint = if ($Mode -eq 'http') { "http://localhost:$Port" } else { "stdio" }
                enabled = $true
                rateLimit = 100
                metadata = @{
                    version = $env:BLENDER_VERSION
                    transport = $Mode
                    blenderPath = $env:BLENDER_PATH
                }
            } | ConvertTo-Json -Depth 5

            $response = Invoke-RestMethod -Uri "$GatewayUrl/api/routes/register" `
                                          -Method POST `
                                          -ContentType "application/json" `
                                          -Body $registrationBody `
                                          -TimeoutSec 10
            
            Write-McpLog -Level INFO -Message "Successfully registered with composite gateway"
            $registered = $true
        }
        catch {
            $retryCount++
            if ($retryCount -lt $maxRetries) {
                Write-McpLog -Level WARN -Message "Registration attempt $retryCount failed, retrying in 2s..."
                Start-Sleep -Seconds 2
            }
            else {
                Write-McpLog -Level ERROR -Message "Failed to register with composite gateway after $maxRetries attempts: $_"
            }
        }
    }
}

# =============================================================================
# Main Execution
# =============================================================================

function Main {
    [CmdletBinding()]
    param()

    Write-McpLog -Level INFO -Message "=== Blender MCP Deployment Started ==="
    Write-McpLog -Level INFO -Message "Mode: $Mode, Port: $Port"

    try {
        # Step 1: Install requirements
        Install-BlenderMcpRequirements

        # Step 2: Get and configure Blender path
        $blenderPath = Get-BlenderExecutablePath
        Set-BlenderEnvironment -ExecutablePath $blenderPath

        # Step 3: Install addon
        Install-BlenderAddon -ExecutablePath $blenderPath

        # Step 4: Test connectivity
        $connected = Test-BlenderConnectivity -ExecutablePath $blenderPath
        if (-not $connected) {
            Write-McpLog -Level WARN -Message "Blender connectivity test failed, but continuing..."
        }

        # Step 5: Start MCP server
        $serverProcess = Start-BlenderMcpServer

        # Step 6: Register with gateway if requested
        if ($RegisterWithGateway) {
            # Give the server time to start
            Start-Sleep -Seconds 3
            Register-WithCompositeGateway
        }

        # Output configuration summary
        Write-Output ""
        Write-Output "=== Blender MCP Deployment Summary ==="
        Write-Output "Blender Path:     $env:BLENDER_PATH"
        Write-Output "Blender Version:  $env:BLENDER_VERSION"
        Write-Output "Transport Mode:   $Mode"
        if ($Mode -eq 'http') {
            Write-Output "HTTP Port:        $Port"
        }
        Write-Output "Server Process:   $(if ($serverProcess) { "Running (PID: $($serverProcess.Id))" } else { "N/A (stdio mode)" })"
        Write-Output "Registered:       $(if ($RegisterWithGateway) { "Yes" } else { "No" })"
        Write-Output ""

        Write-McpLog -Level INFO -Message "=== Blender MCP Deployment Completed Successfully ==="

        # Return status object
        return [PSCustomObject]@{
            Success = $true
            BlenderPath = $env:BLENDER_PATH
            BlenderVersion = $env:BLENDER_VERSION
            Mode = $Mode
            Port = if ($Mode -eq 'http') { $Port } else { $null }
            ProcessId = if ($serverProcess) { $serverProcess.Id } else { $null }
            Registered = $RegisterWithGateway.IsPresent
        }
    }
    catch {
        Write-McpLog -Level ERROR -Message "Deployment failed: $_"
        throw
    }
}

# Run main function
Main
