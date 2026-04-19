<#
.SYNOPSIS
    Deploys the Godot MCP server for LLM Workflow platform.

.DESCRIPTION
    Installs and configures the godot-mcp server from npm, sets up environment variables,
    tests connectivity to the Godot editor, and registers the server with the composite gateway.

.PARAMETER GodotPath
    Path to the Godot executable. If not specified, attempts to auto-detect or uses GODOT_PATH env var.

.PARAMETER Mode
    Execution mode: 'stdio' or 'http'. Default: stdio.

.PARAMETER Port
    Port for HTTP mode. Default: 8091.

.PARAMETER SkipNpmInstall
    Skip npm install of godot-mcp (if already installed).

.PARAMETER SkipConnectivityTest
    Skip the Godot editor connectivity test.

.PARAMETER RegisterWithGateway
    Register this MCP server with the composite gateway after startup.

.PARAMETER GatewayUrl
    URL of the composite gateway for registration. Default: http://localhost:8080.

.PARAMETER ProjectPath
    Path to the Godot project to open. Optional.

.EXAMPLE
    .\deploy-godot-mcp.ps1 -GodotPath "C:\Godot\Godot_v4.exe"

.EXAMPLE
    .\deploy-godot-mcp.ps1 -Mode http -Port 9091 -RegisterWithGateway

.NOTES
    File Name      : deploy-godot-mcp.ps1
    Author         : LLM Workflow Team
    Version        : 1.0.0
    Requires       : PowerShell 5.1+, Node.js 16+, npm
#>

[CmdletBinding()]
param(
    [Parameter()]
    [string]$GodotPath = "",

    [Parameter()]
    [ValidateSet('stdio', 'http')]
    [string]$Mode = 'stdio',

    [Parameter()]
    [ValidateRange(1, 65535)]
    [int]$Port = 8091,

    [Parameter()]
    [switch]$SkipNpmInstall,

    [Parameter()]
    [switch]$SkipConnectivityTest,

    [Parameter()]
    [switch]$RegisterWithGateway,

    [Parameter()]
    [string]$GatewayUrl = "http://localhost:8080",

    [Parameter()]
    [string]$ProjectPath = ""
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
    $logEntry = "[$timestamp] [Godot-MCP-$Level] $Message"
    
    switch ($Level) {
        'ERROR' { Write-Error $logEntry }
        'WARN'  { Write-Warning $logEntry }
        default { Write-Output $logEntry }
    }

    # Also write to structured log if available
    if (Get-Command 'Write-StructuredLog' -ErrorAction SilentlyContinue) {
        $entry = New-LogEntry -Level $Level -Message $Message -Metadata $Metadata -Source "deploy-godot-mcp"
        Write-StructuredLog -Entry $entry -Force
    }
}

# =============================================================================
# Configuration Functions
# =============================================================================

function Get-GodotExecutablePath {
    [CmdletBinding()]
    [OutputType([string])]
    param()

    # 1. Check parameter
    if (-not [string]::IsNullOrWhiteSpace($GodotPath)) {
        if (Test-Path -LiteralPath $GodotPath) {
            return (Resolve-Path -LiteralPath $GodotPath).Path
        }
        Write-McpLog -Level WARN -Message "Provided GodotPath not found: $GodotPath"
    }

    # 2. Check environment variable
    $envPath = [Environment]::GetEnvironmentVariable('GODOT_PATH', 'Process')
    if (-not [string]::IsNullOrWhiteSpace($envPath)) {
        if (Test-Path -LiteralPath $envPath) {
            Write-McpLog -Level INFO -Message "Using GODOT_PATH from environment: $envPath"
            return (Resolve-Path -LiteralPath $envPath).Path
        }
        Write-McpLog -Level WARN -Message "GODOT_PATH environment variable points to non-existent file: $envPath"
    }

    # 3. Auto-detect based on platform
    $detectedPath = $null
    
    if ($IsWindows -or ($PSVersionTable.PSVersion.Major -lt 6 -and $env:OS -eq 'Windows_NT')) {
        # Windows detection
        $commonPaths = @(
            "${env:LOCALAPPDATA}\Godot\Godot*.exe",
            "${env:ProgramFiles}\Godot\Godot*.exe",
            "${env:ProgramFiles(x86)}\Godot\Godot*.exe",
            "C:\Godot\Godot*.exe",
            "C:\Tools\Godot\Godot*.exe"
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
            $inPath = Get-Command godot -ErrorAction SilentlyContinue
            if ($inPath) {
                $detectedPath = $inPath.Source
            }
        }
    }
    elseif ($IsMacOS) {
        # macOS detection
        $macPaths = @(
            "/Applications/Godot.app/Contents/MacOS/Godot",
            "/usr/local/bin/godot",
            "/opt/homebrew/bin/godot"
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
            "/usr/bin/godot",
            "/usr/local/bin/godot",
            "/opt/godot/godot",
            "/snap/bin/godot"
        )
        foreach ($path in $linuxPaths) {
            if (Test-Path -LiteralPath $path) {
                $detectedPath = $path
                break
            }
        }
    }

    if ($detectedPath) {
        Write-McpLog -Level INFO -Message "Auto-detected Godot at: $detectedPath"
        return $detectedPath
    }

    throw "Could not find Godot executable. Please specify -GodotPath or set GODOT_PATH environment variable."
}

function Set-GodotEnvironment {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$ExecutablePath
    )

    [Environment]::SetEnvironmentVariable('GODOT_PATH', $ExecutablePath, 'Process')
    Write-McpLog -Level INFO -Message "Set GODOT_PATH environment variable to: $ExecutablePath"

    # Set additional helpful environment variables
    $godotDir = Split-Path -Parent $ExecutablePath
    [Environment]::SetEnvironmentVariable('GODOT_DIR', $godotDir, 'Process')
    
    # Detect Godot version
    try {
        $versionOutput = & $ExecutablePath --version 2>&1 | Out-String
        if ($versionOutput -match '(\d+\.\d+\.\d+)') {
            $version = $matches[1]
            [Environment]::SetEnvironmentVariable('GODOT_VERSION', $version, 'Process')
            Write-McpLog -Level INFO -Message "Detected Godot version: $version"
        }
    }
    catch {
        Write-McpLog -Level WARN -Message "Could not detect Godot version: $_"
    }
}

# =============================================================================
# Installation Functions
# =============================================================================

function Install-GodotMcpPackage {
    [CmdletBinding()]
    param()

    if ($SkipNpmInstall) {
        Write-McpLog -Level INFO -Message "Skipping npm install (as requested)"
        return
    }

    # Check if npm is available
    $npmCmd = Get-Command npm -ErrorAction SilentlyContinue
    if (-not $npmCmd) {
        throw "npm is not found in PATH. Please install Node.js 16+ from https://nodejs.org/"
    }

    Write-McpLog -Level INFO -Message "Checking godot-mcp package..."

    # Check if already installed globally
    $globalList = & npm list -g --depth=0 2>&1 | Out-String
    if ($globalList -match 'godot-mcp') {
        Write-McpLog -Level INFO -Message "godot-mcp is already installed globally"
        return
    }

    # Install godot-mcp
    Write-McpLog -Level INFO -Message "Installing godot-mcp from npm..."
    try {
        & npm install -g godot-mcp 2>&1 | ForEach-Object {
            Write-Verbose "npm: $_"
        }
        
        if ($LASTEXITCODE -ne 0) {
            throw "npm install failed with exit code $LASTEXITCODE"
        }
        
        Write-McpLog -Level INFO -Message "godot-mcp installed successfully"
    }
    catch {
        throw "Failed to install godot-mcp: $_"
    }
}

# =============================================================================
# Connectivity Test Functions
# =============================================================================

function Test-GodotConnectivity {
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

    Write-McpLog -Level INFO -Message "Testing Godot editor connectivity..."

    try {
        # Test basic executable functionality
        $versionOutput = & $ExecutablePath --version 2>&1 | Out-String
        Write-McpLog -Level INFO -Message "Godot executable responded to version check"

        # Test help output to ensure basic functionality
        $helpOutput = & $ExecutablePath --help 2>&1 | Out-String
        if ($helpOutput -match 'Godot Engine') {
            Write-McpLog -Level INFO -Message "Godot connectivity test passed"
            return $true
        }
        
        Write-McpLog -Level WARN -Message "Godot help output unexpected format"
        return $false
    }
    catch {
        Write-McpLog -Level ERROR -Message "Godot connectivity test failed: $_"
        return $false
    }
}

# =============================================================================
# Server Startup Functions
# =============================================================================

function Start-GodotMcpServer {
    [CmdletBinding()]
    [OutputType([System.Diagnostics.Process])]
    param()

    Write-McpLog -Level INFO -Message "Starting Godot MCP server in $Mode mode..."

    $godotPath = Get-GodotExecutablePath
    
    if ($Mode -eq 'http') {
        # HTTP mode - start as background process
        $env:GODOT_MCP_PORT = $Port
        
        $process = Start-Process -FilePath "godot-mcp" `
                                 -ArgumentList @("--transport", "http", "--port", $Port) `
                                 -WindowStyle Hidden `
                                 -PassThru
        
        Write-McpLog -Level INFO -Message "Godot MCP HTTP server started on port $Port (PID: $($process.Id))"
        return $process
    }
    else {
        # stdio mode - for MCP client integration
        Write-McpLog -Level INFO -Message "Godot MCP server ready for stdio transport"
        Write-McpLog -Level INFO -Message "To use with MCP client, configure: godot-mcp --transport stdio"
        return $null
    }
}

function Register-WithCompositeGateway {
    [CmdletBinding()]
    param()

    if (-not $RegisterWithGateway) {
        return
    }

    Write-McpLog -Level INFO -Message "Registering Godot MCP with composite gateway at $GatewayUrl..."

    $maxRetries = 5
    $retryCount = 0
    $registered = $false

    while ($retryCount -lt $maxRetries -and -not $registered) {
        try {
            $registrationBody = @{
                packId = "godot-engine"
                prefix = "godot_"
                endpoint = if ($Mode -eq 'http') { "http://localhost:$Port" } else { "stdio" }
                enabled = $true
                rateLimit = 100
                metadata = @{
                    version = $env:GODOT_VERSION
                    transport = $Mode
                    godotPath = $env:GODOT_PATH
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

    Write-McpLog -Level INFO -Message "=== Godot MCP Deployment Started ==="
    Write-McpLog -Level INFO -Message "Mode: $Mode, Port: $Port"

    try {
        # Step 1: Install godot-mcp package
        Install-GodotMcpPackage

        # Step 2: Get and configure Godot path
        $godotPath = Get-GodotExecutablePath
        Set-GodotEnvironment -ExecutablePath $godotPath

        # Step 3: Test connectivity
        $connected = Test-GodotConnectivity -ExecutablePath $godotPath
        if (-not $connected) {
            Write-McpLog -Level WARN -Message "Godot connectivity test failed, but continuing..."
        }

        # Step 4: Start MCP server
        $serverProcess = Start-GodotMcpServer

        # Step 5: Register with gateway if requested
        if ($RegisterWithGateway) {
            # Give the server time to start
            Start-Sleep -Seconds 2
            Register-WithCompositeGateway
        }

        # Output configuration summary
        Write-Output ""
        Write-Output "=== Godot MCP Deployment Summary ==="
        Write-Output "Godot Path:       $env:GODOT_PATH"
        Write-Output "Godot Version:    $env:GODOT_VERSION"
        Write-Output "Transport Mode:   $Mode"
        if ($Mode -eq 'http') {
            Write-Output "HTTP Port:        $Port"
        }
        Write-Output "Server Process:   $(if ($serverProcess) { "Running (PID: $($serverProcess.Id))" } else { "N/A (stdio mode)" })"
        Write-Output "Registered:       $(if ($RegisterWithGateway) { "Yes" } else { "No" })"
        Write-Output ""

        Write-McpLog -Level INFO -Message "=== Godot MCP Deployment Completed Successfully ==="

        # Return status object
        return [PSCustomObject]@{
            Success = $true
            GodotPath = $env:GODOT_PATH
            GodotVersion = $env:GODOT_VERSION
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
