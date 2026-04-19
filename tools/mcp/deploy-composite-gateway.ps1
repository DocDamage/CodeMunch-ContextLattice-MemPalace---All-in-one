<#
.SYNOPSIS
    Deploys the MCP Composite Gateway for LLM Workflow platform.

.DESCRIPTION
    Configures and starts the composite gateway that routes MCP requests to
    appropriate domain packs (Godot, Blender, RPG Maker MZ). Supports HTTP and
    stdio transports, health checks, and optional service installation.

.PARAMETER Transport
    Transport mode: 'stdio' or 'http'. Default: http.

.PARAMETER Port
    Port for HTTP transport. Default: 8080.

.PARAMETER Host
    Host address for HTTP transport. Default: localhost.

.PARAMETER ConfigPath
    Path to gateway configuration JSON file.

.PARAMETER AutoLoadRoutes
    Automatically load pack routes from configuration.

.PARAMETER EnablePackServers
    Automatically deploy and register pack MCP servers (Godot, Blender, etc.).

.PARAMETER SkipHealthCheck
    Skip the health check after startup.

.PARAMETER InstallService
    Install as a system service (Windows) or systemd service (Linux).

.PARAMETER ServiceName
    Name for the installed service. Default: llm-workflow-mcp-gateway.

.PARAMETER LogLevel
    Logging level: DEBUG, INFO, WARN, ERROR. Default: INFO.

.EXAMPLE
    .\deploy-composite-gateway.ps1 -Transport http -Port 8080

.EXAMPLE
    .\deploy-composite-gateway.ps1 -AutoLoadRoutes -EnablePackServers

.EXAMPLE
    .\deploy-composite-gateway.ps1 -InstallService -ServiceName "mcp-gateway"

.NOTES
    File Name      : deploy-composite-gateway.ps1
    Author         : LLM Workflow Team
    Version        : 1.0.0
    Requires       : PowerShell 5.1+, .NET Framework 4.7.2+ (Windows) or PowerShell 7+ (Linux/macOS)
#>

[CmdletBinding()]
param(
    [Parameter()]
    [ValidateSet('stdio', 'http')]
    [string]$Transport = 'http',

    [Parameter()]
    [ValidateRange(1, 65535)]
    [int]$Port = 8080,

    [Parameter()]
    [string]$Host = 'localhost',

    [Parameter()]
    [string]$ConfigPath = "",

    [Parameter()]
    [switch]$AutoLoadRoutes,

    [Parameter()]
    [switch]$EnablePackServers,

    [Parameter()]
    [switch]$SkipHealthCheck,

    [Parameter()]
    [switch]$InstallService,

    [Parameter()]
    [string]$ServiceName = "llm-workflow-mcp-gateway",

    [Parameter()]
    [ValidateSet('DEBUG', 'INFO', 'WARN', 'ERROR')]
    [string]$LogLevel = 'INFO'
)

$ErrorActionPreference = "Stop"
$script:ScriptRoot = if (-not [string]::IsNullOrWhiteSpace($PSScriptRoot)) { $PSScriptRoot } else { (Split-Path -Parent $PSCommandPath) }

# Import modules if available
$LoggingModulePath = Join-Path $script:ScriptRoot "..\..\module\LLMWorkflow\core\Logging.ps1"
$GatewayModulePath = Join-Path $script:ScriptRoot "..\..\module\LLMWorkflow\mcp\MCPCompositeGateway.ps1"

if (Test-Path -LiteralPath $LoggingModulePath) {
    Import-Module $LoggingModulePath -Force -ErrorAction SilentlyContinue
}
if (Test-Path -LiteralPath $GatewayModulePath) {
    Import-Module $GatewayModulePath -Force -ErrorAction SilentlyContinue
}

# =============================================================================
# Logging Functions
# =============================================================================

function Write-GatewayLog {
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
    $logEntry = "[$timestamp] [Gateway-$Level] $Message"
    
    switch ($Level) {
        'ERROR' { Write-Error $logEntry }
        'WARN'  { Write-Warning $logEntry }
        default { Write-Output $logEntry }
    }

    # Also write to structured log if available
    if (Get-Command 'Write-StructuredLog' -ErrorAction SilentlyContinue) {
        $entry = New-LogEntry -Level $Level -Message $Message -Metadata $Metadata -Source "deploy-composite-gateway"
        Write-StructuredLog -Entry $entry -Force
    }
}

# =============================================================================
# Configuration Functions
# =============================================================================

function Get-DefaultGatewayConfig {
    [CmdletBinding()]
    [OutputType([hashtable])]
    param()

    return @{
        gateway = @{
            name = "LLM-Workflow-MCP-Gateway"
            version = "1.0.0"
            transport = $Transport
            port = $Port
            host = $Host
            logLevel = $LogLevel
        }
        routes = @(
            @{
                packId = "godot-engine"
                prefix = "godot_"
                endpoint = "stdio"
                enabled = $false  # Disabled until manually deployed
                rateLimit = 100
                priority = 1
            },
            @{
                packId = "blender-engine"
                prefix = "blender_"
                endpoint = "stdio"
                enabled = $false  # Disabled until manually deployed
                rateLimit = 100
                priority = 1
            },
            @{
                packId = "rpgmaker-mz"
                prefix = "rpgmaker_"
                endpoint = "stdio"
                enabled = $false
                rateLimit = 100
                priority = 1
            },
            @{
                packId = "common-tools"
                prefix = "common_"
                endpoint = "stdio"
                enabled = $true
                rateLimit = 200
                priority = 2
            }
        )
        circuitBreaker = @{
            enabled = $true
            threshold = 5
            timeoutSeconds = 30
        }
        rateLimiting = @{
            enabled = $true
            defaultRateLimit = 100
        }
    }
}

function Import-GatewayConfig {
    [CmdletBinding()]
    [OutputType([hashtable])]
    param()

    # 1. Check provided path
    if (-not [string]::IsNullOrWhiteSpace($ConfigPath)) {
        if (Test-Path -LiteralPath $ConfigPath) {
            Write-GatewayLog -Level INFO -Message "Loading gateway configuration from: $ConfigPath"
            $configContent = Get-Content -LiteralPath $ConfigPath -Raw | ConvertFrom-Json -AsHashtable
            return $configContent
        }
        throw "Configuration file not found: $ConfigPath"
    }

    # 2. Check environment variable
    $envConfigPath = [Environment]::GetEnvironmentVariable('MCP_GATEWAY_CONFIG', 'Process')
    if (-not [string]::IsNullOrWhiteSpace($envConfigPath) -and (Test-Path -LiteralPath $envConfigPath)) {
        Write-GatewayLog -Level INFO -Message "Loading gateway configuration from env: $envConfigPath"
        $configContent = Get-Content -LiteralPath $envConfigPath -Raw | ConvertFrom-Json -AsHashtable
        return $configContent
    }

    # 3. Check default locations
    $defaultPaths = @(
        (Join-Path $script:ScriptRoot "..\..\.llm-workflow\mcp-gateway.json"),
        (Join-Path $script:ScriptRoot "gateway-config.json"),
        "/etc/llm-workflow/mcp-gateway.json",
        "$env:USERPROFILE\.llm-workflow\mcp-gateway.json"
    )

    foreach ($path in $defaultPaths) {
        if (Test-Path -LiteralPath $path) {
            Write-GatewayLog -Level INFO -Message "Loading gateway configuration from: $path"
            $configContent = Get-Content -LiteralPath $path -Raw | ConvertFrom-Json -AsHashtable
            return $configContent
        }
    }

    # 4. Return default configuration
    Write-GatewayLog -Level INFO -Message "Using default gateway configuration"
    return Get-DefaultGatewayConfig
}

# =============================================================================
# Route Configuration Functions
# =============================================================================

function Initialize-PackRoutes {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [hashtable]$Config
    )

    if (-not $AutoLoadRoutes) {
        Write-GatewayLog -Level INFO -Message "Auto-loading routes disabled"
        return
    }

    Write-GatewayLog -Level INFO -Message "Initializing pack routes..."

    $routes = $Config.routes
    if (-not $routes) {
        Write-GatewayLog -Level WARN -Message "No routes defined in configuration"
        return
    }

    foreach ($route in $routes) {
        if (-not $route.enabled) {
            Write-GatewayLog -Level INFO -Message "Route for $($route.packId) is disabled, skipping"
            continue
        }

        try {
            # Check if the Add-MCPPackRoute function is available
            if (Get-Command 'Add-MCPPackRoute' -ErrorAction SilentlyContinue) {
                $null = Add-MCPPackRoute `
                    -PackId $route.packId `
                    -Endpoint $route.endpoint `
                    -ToolPrefix $route.prefix `
                    -Priority $route.priority `
                    -Enabled $route.enabled `
                    -RateLimit $route.rateLimit `
                    -Metadata ($route.metadata ? $route.metadata : @{})
                
                Write-GatewayLog -Level INFO -Message "Registered route: $($route.packId) -> $($route.endpoint)"
            }
            else {
                Write-GatewayLog -Level WARN -Message "Add-MCPPackRoute not available, route registration skipped"
            }
        }
        catch {
            Write-GatewayLog -Level ERROR -Message "Failed to register route for $($route.packId): $_"
        }
    }
}

function Deploy-PackServers {
    [CmdletBinding()]
    param()

    if (-not $EnablePackServers) {
        return
    }

    Write-GatewayLog -Level INFO -Message "Deploying pack MCP servers..."

    $packScripts = @(
        @{ Name = "Godot"; Script = "deploy-godot-mcp.ps1"; Port = 8091 }
        @{ Name = "Blender"; Script = "deploy-blender-mcp.ps1"; Port = 8092 }
    )

    foreach ($pack in $packScripts) {
        $scriptPath = Join-Path $script:ScriptRoot $pack.Script
        if (Test-Path -LiteralPath $scriptPath) {
            try {
                Write-GatewayLog -Level INFO -Message "Deploying $($pack.Name) MCP server..."
                & $scriptPath -Mode http -Port $pack.Port -RegisterWithGateway -GatewayUrl "http://$Host`:$Port"
            }
            catch {
                Write-GatewayLog -Level ERROR -Message "Failed to deploy $($pack.Name) server: $_"
            }
        }
        else {
            Write-GatewayLog -Level WARN -Message "Deployment script not found: $($pack.Script)"
        }
    }
}

# =============================================================================
# Gateway Startup Functions
# =============================================================================

function Start-GatewayServer {
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Mandatory = $true)]
        [hashtable]$Config
    )

    Write-GatewayLog -Level INFO -Message "Starting MCP Composite Gateway..."
    Write-GatewayLog -Level INFO -Message "Transport: $Transport, Port: $Port, Host: $Host"

    # Use the module function if available
    if (Get-Command 'Start-MCPCompositeGateway' -ErrorAction SilentlyContinue) {
        $status = Start-MCPCompositeGateway `
            -Transport $Transport `
            -Port $Port `
            -Host $Host `
            -AutoLoadRoutes:$AutoLoadRoutes
        
        return $status
    }

    # Fallback: Simple HTTP listener for basic operation
    Write-GatewayLog -Level WARN -Message "MCP Composite Gateway module not available, using fallback implementation"
    return Start-FallbackGateway
}

function Start-FallbackGateway {
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param()

    try {
        $listener = [System.Net.HttpListener]::new()
        $listener.Prefixes.Add("http://$Host`:$Port/")
        $listener.Start()

        Write-GatewayLog -Level INFO -Message "Fallback gateway started on http://$Host`:$Port/"

        # Store listener in script scope for cleanup
        $script:HttpListener = $listener

        # Start request handler in background
        $runspace = [runspacefactory]::CreateRunspace()
        $runspace.Open()
        $powershell = [powershell]::Create()
        $powershell.Runspace = $runspace

        $powershell.AddScript({
            param($Listener, $LogLevel)
            
            while ($Listener.IsListening) {
                try {
                    $context = $Listener.GetContext()
                    $request = $context.Request
                    $response = $context.Response

                    # Handle health check
                    if ($request.Url.PathAndQuery -eq '/health') {
                        $healthResponse = @{
                            status = 'healthy'
                            timestamp = [DateTime]::UtcNow.ToString('o')
                            version = '1.0.0-fallback'
                        } | ConvertTo-Json -Compress

                        $buffer = [System.Text.Encoding]::UTF8.GetBytes($healthResponse)
                        $response.ContentType = 'application/json'
                        $response.ContentLength64 = $buffer.Length
                        $response.OutputStream.Write($buffer, 0, $buffer.Length)
                    }
                    else {
                        $response.StatusCode = 404
                    }
                    
                    $response.Close()
                }
                catch {
                    if ($Listener.IsListening) {
                        Write-Warning "Request handling error: $_"
                    }
                }
            }
        }) | Out-Null

        $powershell.AddArgument($listener) | Out-Null
        $powershell.AddArgument($LogLevel) | Out-Null

        $asyncResult = $powershell.BeginInvoke()

        $script:GatewayPowerShell = $powershell
        $script:GatewayRunspace = $runspace

        return [PSCustomObject]@{
            Success = $true
            Transport = $Transport
            Port = $Port
            Host = $Host
            Mode = 'fallback'
            IsRunning = $true
        }
    }
    catch {
        Write-GatewayLog -Level ERROR -Message "Failed to start fallback gateway: $_"
        throw
    }
}

# =============================================================================
# Health Check Functions
# =============================================================================

function Test-GatewayHealth {
    [CmdletBinding()]
    [OutputType([bool])]
    param()

    if ($SkipHealthCheck) {
        Write-GatewayLog -Level INFO -Message "Health check skipped (as requested)"
        return $true
    }

    Write-GatewayLog -Level INFO -Message "Running gateway health check..."

    $maxRetries = 5
    $retryCount = 0
    $healthy = $false

    while ($retryCount -lt $maxRetries -and -not $healthy) {
        try {
            $response = Invoke-RestMethod -Uri "http://$Host`:$Port/health" `
                                          -Method GET `
                                          -TimeoutSec 5
            
            if ($response.status -eq 'healthy') {
                Write-GatewayLog -Level INFO -Message "Gateway health check passed"
                $healthy = $true
            }
            else {
                Write-GatewayLog -Level WARN -Message "Gateway health check returned unexpected status: $($response.status)"
            }
        }
        catch {
            $retryCount++
            if ($retryCount -lt $maxRetries) {
                Write-GatewayLog -Level WARN -Message "Health check attempt $retryCount failed, retrying in 1s..."
                Start-Sleep -Seconds 1
            }
            else {
                Write-GatewayLog -Level ERROR -Message "Gateway health check failed after $maxRetries attempts: $_"
            }
        }
    }

    return $healthy
}

# =============================================================================
# Service Installation Functions
# =============================================================================

function Install-GatewayService {
    [CmdletBinding()]
    param()

    if (-not $InstallService) {
        return
    }

    Write-GatewayLog -Level INFO -Message "Installing gateway as service: $ServiceName"

    if ($IsWindows -or ($PSVersionTable.PSVersion.Major -lt 6 -and $env:OS -eq 'Windows_NT')) {
        Install-WindowsService
    }
    elseif ($IsLinux) {
        Install-SystemdService
    }
    else {
        Write-GatewayLog -Level WARN -Message "Service installation not supported on this platform"
    }
}

function Install-WindowsService {
    [CmdletBinding()]
    param()

    try {
        # Check if running as administrator
        $currentPrincipal = New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())
        if (-not $currentPrincipal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
            Write-GatewayLog -Level WARN -Message "Service installation requires administrator privileges"
            return
        }

        # Create service using sc.exe or New-Service
        $exePath = (Get-Command pwsh -ErrorAction SilentlyContinue)?.Source
        if (-not $exePath) {
            $exePath = (Get-Command powershell -ErrorAction SilentlyContinue)?.Source
        }

        $scriptPath = Join-Path $script:ScriptRoot "deploy-composite-gateway.ps1"
        $arguments = "-ExecutionPolicy Bypass -NoProfile -File `"$scriptPath`" -Transport $Transport -Port $Port -Host $Host"

        # Remove existing service if present
        $existingService = Get-Service -Name $ServiceName -ErrorAction SilentlyContinue
        if ($existingService) {
            Write-GatewayLog -Level INFO -Message "Removing existing service..."
            & sc.exe delete $ServiceName 2>&1 | Out-Null
            Start-Sleep -Seconds 2
        }

        # Create new service
        & sc.exe create $ServiceName `
            binPath= "`"$exePath`" $arguments" `
            start= auto `
            DisplayName= "LLM Workflow MCP Gateway" 2>&1 | Out-Null

        Write-GatewayLog -Level INFO -Message "Windows service installed successfully: $ServiceName"
        Write-GatewayLog -Level INFO -Message "To start the service, run: Start-Service $ServiceName"
    }
    catch {
        Write-GatewayLog -Level ERROR -Message "Failed to install Windows service: $_"
    }
}

function Install-SystemdService {
    [CmdletBinding()]
    param()

    try {
        $serviceContent = @"
[Unit]
Description=LLM Workflow MCP Gateway
After=network.target

[Service]
Type=simple
ExecStart=/usr/bin/pwsh -ExecutionPolicy Bypass -NoProfile -File "$PSScriptRoot/deploy-composite-gateway.ps1" -Transport $Transport -Port $Port -Host $Host
Restart=always
RestartSec=10
User=$env:USER

[Install]
WantedBy=multi-user.target
"@

        $serviceFilePath = "/etc/systemd/system/$ServiceName.service"
        $serviceContent | Set-Content -LiteralPath $serviceFilePath -Encoding UTF8

        & systemctl daemon-reload 2>&1 | Out-Null
        & systemctl enable $ServiceName 2>&1 | Out-Null

        Write-GatewayLog -Level INFO -Message "Systemd service installed: $ServiceName"
        Write-GatewayLog -Level INFO -Message "To start: sudo systemctl start $ServiceName"
    }
    catch {
        Write-GatewayLog -Level ERROR -Message "Failed to install systemd service: $_"
    }
}

# =============================================================================
# Main Execution
# =============================================================================

function Main {
    [CmdletBinding()]
    param()

    Write-GatewayLog -Level INFO -Message "=== MCP Composite Gateway Deployment Started ==="

    try {
        # Step 1: Load configuration
        $config = Import-GatewayConfig

        # Override config with command line parameters
        if ($PSBoundParameters.ContainsKey('Transport')) { $config.gateway.transport = $Transport }
        if ($PSBoundParameters.ContainsKey('Port')) { $config.gateway.port = $Port }
        if ($PSBoundParameters.ContainsKey('Host')) { $config.gateway.host = $Host }
        if ($PSBoundParameters.ContainsKey('LogLevel')) { $config.gateway.logLevel = $LogLevel }

        # Update script variables from config
        $script:Transport = $config.gateway.transport
        $script:Port = $config.gateway.port
        $script:Host = $config.gateway.host
        $script:LogLevel = $config.gateway.logLevel

        # Step 2: Deploy pack servers if requested
        if ($EnablePackServers) {
            Deploy-PackServers
        }

        # Step 3: Start gateway
        $gatewayStatus = Start-GatewayServer -Config $config

        # Step 4: Initialize routes
        Initialize-PackRoutes -Config $config

        # Step 5: Health check
        $healthy = Test-GatewayHealth

        # Step 6: Install service if requested
        Install-GatewayService

        # Output summary
        Write-Output ""
        Write-Output "=== MCP Composite Gateway Deployment Summary ==="
        Write-Output "Gateway Status:   $(if ($gatewayStatus.IsRunning) { "Running" } else { "Stopped" })"
        Write-Output "Transport:        $Transport"
        Write-Output "Endpoint:         http://$Host`:$Port/"
        Write-Output "Health Status:    $(if ($healthy) { "Healthy" } else { "Unhealthy" })"
        Write-Output "Routes Loaded:    $(if ($AutoLoadRoutes) { "Yes" } else { "No" })"
        Write-Output "Pack Servers:     $(if ($EnablePackServers) { "Enabled" } else { "Disabled" })"
        Write-Output "Service:          $(if ($InstallService) { "Installed ($ServiceName)" } else { "Not installed" })"
        Write-Output ""
        Write-Output "Health Endpoint:  http://$Host`:$Port/health"
        Write-Output ""

        Write-GatewayLog -Level INFO -Message "=== MCP Composite Gateway Deployment Completed Successfully ==="

        return [PSCustomObject]@{
            Success = $true
            Transport = $Transport
            Port = $Port
            Host = $Host
            IsRunning = $gatewayStatus.IsRunning
            Healthy = $healthy
            ServiceInstalled = $InstallService.IsPresent
            ServiceName = if ($InstallService) { $ServiceName } else { $null }
        }
    }
    catch {
        Write-GatewayLog -Level ERROR -Message "Deployment failed: $_"
        throw
    }
}

# Cleanup function for graceful shutdown
function Stop-Gateway {
    if ($script:HttpListener) {
        $script:HttpListener.Stop()
        $script:HttpListener.Close()
    }
    if ($script:GatewayPowerShell) {
        $script:GatewayPowerShell.Stop()
        $script:GatewayPowerShell.Dispose()
    }
    if ($script:GatewayRunspace) {
        $script:GatewayRunspace.Close()
        $script:GatewayRunspace.Dispose()
    }
}

# Register cleanup on script exit
$null = Register-EngineEvent -SourceIdentifier PowerShell.Exiting -Action { Stop-Gateway }

# Run main function
Main
