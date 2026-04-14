<#
.SYNOPSIS
    MCP Composite Gateway for LLM Workflow Platform - Phase 7 Implementation

.DESCRIPTION
    Implements a unified MCP (Model Context Protocol) gateway that routes requests
    to appropriate domain packs (RPG Maker MZ, Godot, Blender) with:
    - Session management
    - Rate limiting
    - Circuit breaker pattern for fault tolerance
    - Cross-pack operations support
    - JSON-RPC 2.0 protocol compliance
    - Structured logging with correlation IDs

.NOTES
    Author: LLM Workflow Platform
    Version: 1.1.0
    Date: 2026-04-12
    Implements: Phase 7 MCP Composite Gateway

.TECHNICAL_REQUIREMENTS
    - Route requests based on tool name prefix (e.g., "godot_", "blender_", "rpgmaker_")
    - Support session-scoped context sharing between packs
    - Include rate limiting per pack
    - Include circuit breaker pattern for fault tolerance
    - Support pack fallbacks if primary is unavailable
    - Log all routing decisions with correlation IDs
    - Return proper JSON-RPC 2.0 responses
#>

#requires -Version 5.1
Set-StrictMode -Version Latest

# Import Logging module for structured logging
$LoggingModulePath = Join-Path $PSScriptRoot "../core/Logging.ps1"
if (Test-Path -LiteralPath $LoggingModulePath) {
    Import-Module $LoggingModulePath -Force -ErrorAction SilentlyContinue
}

#region Module State

# In-memory gateway state
$script:GatewayState = @{
    isRunning = $false
    startedAt = $null
    routes = @{}  # packId -> route config
    sessions = @{}  # sessionId -> session data
    pipelines = @{}  # pipelineId -> pipeline config
    rateLimiters = @{}  # packId -> rate limiter state
    circuitBreakers = @{}  # packId -> circuit breaker state
    httpListener = $null
    correlationContext = @{}  # correlationId -> request context
    logs = @()
    config = @{
        defaultRateLimit = 100  # requests per minute
        sessionTimeoutMinutes = 30
        enableFallback = $true
        enableCircuitBreaker = $true
        logRetentionCount = 1000
        circuitBreakerThreshold = 5  # failures before opening
        circuitBreakerTimeoutSeconds = 30
        loadBalancingStrategy = 'round-robin'  # round-robin, least-connections, priority
        stdioMode = $true
        httpPort = 8080
    }
}

# Pack route schema defaults
$script:DefaultRouteConfig = @{
    packId = ''
    prefix = ''
    endpoint = 'stdio'  # or "http://localhost:port"
    enabled = $true
    rateLimit = 100
    fallbackPackId = $null
    priority = 1  # Higher = preferred
    healthCheckPath = '/health'
    metadata = @{}
}

# Valid tool prefixes by domain
$script:ValidToolPrefixes = @(
    'godot_'
    'blender_'
    'rpgmaker_'
    'rmmz_'
    'common_'
    'workflow_'
)

# Circuit breaker states
$script:CircuitBreakerStates = @{
    CLOSED = 'CLOSED'      # Normal operation
    OPEN = 'OPEN'          # Failing, rejecting requests
    HALF_OPEN = 'HALF_OPEN'  # Testing if recovered
}

#endregion

#region Gateway Lifecycle Functions

<#
.SYNOPSIS
    Creates a new MCP Composite Gateway configuration.

.DESCRIPTION
    Creates a composite gateway configuration object with all the settings
    needed for pack routing, load balancing, circuit breaker, and logging.

.PARAMETER Name
    The unique name for this gateway instance.

.PARAMETER Config
    Optional configuration hashtable with settings for rate limiting,
    circuit breaker, load balancing, etc.

.PARAMETER LoadBalancingStrategy
    The load balancing strategy: 'round-robin', 'least-connections', or 'priority'.

.PARAMETER EnableCircuitBreaker
    Enable circuit breaker pattern for fault tolerance.

.PARAMETER CircuitBreakerThreshold
    Number of consecutive failures before opening the circuit.

.PARAMETER CircuitBreakerTimeoutSeconds
    Time in seconds before attempting to close an open circuit.

.PARAMETER DefaultRateLimit
    Default requests per minute limit per pack.

.PARAMETER SessionTimeoutMinutes
    Session timeout in minutes.

.EXAMPLE
    $gateway = New-MCPCompositeGateway -Name "production-gateway" -LoadBalancingStrategy "priority"

.OUTPUTS
    PSCustomObject with gateway configuration.
#>
function New-MCPCompositeGateway {
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Name,

        [Parameter()]
        [hashtable]$Config = @{},

        [Parameter()]
        [ValidateSet('round-robin', 'least-connections', 'priority')]
        [string]$LoadBalancingStrategy = 'round-robin',

        [Parameter()]
        [bool]$EnableCircuitBreaker = $true,

        [Parameter()]
        [int]$CircuitBreakerThreshold = 5,

        [Parameter()]
        [int]$CircuitBreakerTimeoutSeconds = 30,

        [Parameter()]
        [int]$DefaultRateLimit = 100,

        [Parameter()]
        [int]$SessionTimeoutMinutes = 30
    )

    process {
        $gatewayId = [Guid]::NewGuid().ToString()

        $gatewayConfig = [PSCustomObject]@{
            gatewayId = $gatewayId
            name = $Name
            createdAt = [DateTime]::UtcNow.ToString("o")
            loadBalancingStrategy = $LoadBalancingStrategy
            enableCircuitBreaker = $EnableCircuitBreaker
            circuitBreakerThreshold = $CircuitBreakerThreshold
            circuitBreakerTimeoutSeconds = $CircuitBreakerTimeoutSeconds
            defaultRateLimit = $DefaultRateLimit
            sessionTimeoutMinutes = $SessionTimeoutMinutes
            routes = @()
            customSettings = $Config
        }

        # Update script-level config defaults
        $script:GatewayState.config.loadBalancingStrategy = $LoadBalancingStrategy
        $script:GatewayState.config.enableCircuitBreaker = $EnableCircuitBreaker
        $script:GatewayState.config.circuitBreakerThreshold = $CircuitBreakerThreshold
        $script:GatewayState.config.circuitBreakerTimeoutSeconds = $CircuitBreakerTimeoutSeconds
        $script:GatewayState.config.defaultRateLimit = $DefaultRateLimit
        $script:GatewayState.config.sessionTimeoutMinutes = $SessionTimeoutMinutes

        # Log gateway creation
        Write-GatewayStructuredLog -Level INFO -Message "MCP Composite Gateway created" -CorrelationId $gatewayId -Metadata @{
            gatewayName = $Name
            gatewayId = $gatewayId
            loadBalancingStrategy = $LoadBalancingStrategy
            enableCircuitBreaker = $EnableCircuitBreaker
        }

        return $gatewayConfig
    }
}

<#
.SYNOPSIS
    Starts the MCP Composite Gateway.

.DESCRIPTION
    Initializes the gateway, loads registered routes, sets up HTTP listener or
    stdio bridge, and prepares for handling MCP requests. Must be called before
    other gateway operations.

.PARAMETER ConfigPath
    Optional path to gateway configuration file.

.PARAMETER AutoLoadRoutes
    Automatically load routes from configuration.

.PARAMETER Transport
    Transport mode: 'stdio' or 'http'. Default: stdio.

.PARAMETER Port
    Port for HTTP transport. Default: 8080.

.PARAMETER Host
    Host address for HTTP transport. Default: localhost.

.EXAMPLE
    Start-MCPCompositeGateway -AutoLoadRoutes

.EXAMPLE
    Start-MCPCompositeGateway -Transport http -Port 9090

.OUTPUTS
    PSCustomObject with gateway status.
#>
function Start-MCPCompositeGateway {
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter()]
        [string]$ConfigPath = '',

        [Parameter()]
        [switch]$AutoLoadRoutes,

        [Parameter()]
        [ValidateSet('stdio', 'http')]
        [string]$Transport = 'stdio',

        [Parameter()]
        [ValidateRange(1, 65535)]
        [int]$Port = 8080,

        [Parameter()]
        [string]$Host = 'localhost'
    )

    begin {
        $gatewayId = [Guid]::NewGuid().ToString()
        Write-Verbose "Starting MCP Composite Gateway [$gatewayId]"
    }

    process {
        if ($script:GatewayState.isRunning) {
            Write-Warning "Gateway is already running. Use Stop-MCPCompositeGateway first to restart."
            return Get-MCPCompositeGatewayStatus
        }

        # Reset state
        $script:GatewayState.isRunning = $true
        $script:GatewayState.startedAt = [DateTime]::UtcNow
        $script:GatewayState.gatewayId = $gatewayId
        $script:GatewayState.transport = $Transport
        $script:GatewayState.httpPort = $Port
        $script:GatewayState.httpHost = $Host

        # Load configuration if provided
        if ($ConfigPath -and (Test-Path -LiteralPath $ConfigPath)) {
            try {
                $configData = Get-Content -Path $ConfigPath -Raw | ConvertFrom-Json -AsHashtable
                if ($configData) {
                    $script:GatewayState.config = Merge-GatewayConfig -Base $script:GatewayState.config -Override $configData
                }
            }
            catch {
                Write-Warning "Failed to load configuration from $ConfigPath : $_"
            }
        }

        # Auto-load routes if requested
        if ($AutoLoadRoutes) {
            Import-MCPRoutesFromConfig
        }

        # Initialize rate limiters
        Initialize-RateLimiters

        # Initialize circuit breakers
        Initialize-CircuitBreakers

        # Setup HTTP listener if transport is http
        if ($Transport -eq 'http') {
            Start-MCPGatewayHttpListener -Port $Port -Host $Host
        }

        # Log startup with structured logging
        Write-GatewayStructuredLog -Level INFO -Message "Gateway started" -CorrelationId $gatewayId -Metadata @{
            gatewayId = $gatewayId
            transport = $Transport
            port = if ($Transport -eq 'http') { $Port } else { $null }
            autoLoadRoutes = $AutoLoadRoutes.IsPresent
            routeCount = $script:GatewayState.routes.Count
        }

        return Get-MCPCompositeGatewayStatus
    }
}

<#
.SYNOPSIS
    Stops the MCP Composite Gateway.

.DESCRIPTION
    Gracefully shuts down the gateway, closing all sessions, stopping HTTP
    listener, and cleaning up resources.

.PARAMETER Force
    Force immediate shutdown without waiting for active requests.

.PARAMETER TimeoutSeconds
    Maximum time to wait for graceful shutdown. Default: 30.

.EXAMPLE
    Stop-MCPCompositeGateway

.OUTPUTS
    PSCustomObject with shutdown status.
#>
function Stop-MCPCompositeGateway {
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter()]
        [switch]$Force,

        [Parameter()]
        [ValidateRange(0, 300)]
        [int]$TimeoutSeconds = 30
    )

    process {
        if (-not $script:GatewayState.isRunning) {
            Write-Warning "Gateway is not running."
            return [PSCustomObject]@{
                success = $false
                message = "Gateway is not running"
            }
        }

        $stopwatch = [System.Diagnostics.Stopwatch]::StartNew()

        # Clean up sessions
        $activeSessions = $script:GatewayState.sessions.Count
        if ($activeSessions -gt 0 -and -not $Force) {
            Write-Verbose "Cleaning up $activeSessions active sessions..."
            foreach ($sessionId in @($script:GatewayState.sessions.Keys)) {
                try {
                    Remove-MCPSession -SessionId $sessionId -ErrorAction SilentlyContinue | Out-Null
                }
                catch {
                    Write-Verbose "Error removing session $sessionId : $_"
                }

                # Check timeout
                if ($stopwatch.Elapsed.TotalSeconds -gt $TimeoutSeconds) {
                    Write-Warning "Shutdown timeout reached. Some sessions may not have been cleaned up."
                    break
                }
            }
        }

        # Stop HTTP listener if running
        if ($script:GatewayState.httpListener -ne $null) {
            try {
                $script:GatewayState.httpListener.Stop()
                $script:GatewayState.httpListener.Close()
                $script:GatewayState.httpListener = $null
                Write-Verbose "HTTP listener stopped."
            }
            catch {
                Write-Warning "Error stopping HTTP listener: $_"
            }
        }

        # Log shutdown
        $uptime = [DateTime]::UtcNow - $script:GatewayState.startedAt
        Write-GatewayStructuredLog -Level INFO -Message "Gateway stopped" -CorrelationId $script:GatewayState.gatewayId -Metadata @{
            uptimeMinutes = [Math]::Round($uptime.TotalMinutes, 2)
            forceShutdown = $Force.IsPresent
            sessionsCleaned = $activeSessions
            shutdownDurationMs = $stopwatch.ElapsedMilliseconds
        }

        # Reset state
        $script:GatewayState.isRunning = $false
        $script:GatewayState.startedAt = $null
        $script:GatewayState.sessions.Clear()
        $script:GatewayState.rateLimiters.Clear()
        $script:GatewayState.circuitBreakers.Clear()
        $script:GatewayState.correlationContext.Clear()

        $stopwatch.Stop()

        return [PSCustomObject]@{
            success = $true
            message = "Gateway stopped successfully"
            uptime = $uptime.ToString()
            sessionsCleaned = $activeSessions
            shutdownDurationMs = $stopwatch.ElapsedMilliseconds
        }
    }
}

<#
.SYNOPSIS
    Gets the current status of the MCP Composite Gateway.

.DESCRIPTION
    Returns detailed status information about the gateway including
    runtime state, route count, session count, and configuration.

.EXAMPLE
    $status = Get-MCPCompositeGatewayStatus

.OUTPUTS
    PSCustomObject with gateway status.
#>
function Get-MCPCompositeGatewayStatus {
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param()

    process {
        $uptime = if ($script:GatewayState.startedAt) {
            [DateTime]::UtcNow - $script:GatewayState.startedAt
        }
        else {
            [TimeSpan]::Zero
        }

        $enabledRoutes = $script:GatewayState.routes.Values | Where-Object { $_.enabled }
        $disabledRoutes = $script:GatewayState.routes.Values | Where-Object { -not $_.enabled }

        $circuitBreakerSummary = @{}
        foreach ($packId in $script:GatewayState.circuitBreakers.Keys) {
            $cb = $script:GatewayState.circuitBreakers[$packId]
            $circuitBreakerSummary[$packId] = @{
                state = $cb.state
                failureCount = $cb.failureCount
                successCount = $cb.successCount
                lastFailureAt = $cb.lastFailureAt
            }
        }

        return [PSCustomObject]@{
            isRunning = $script:GatewayState.isRunning
            gatewayId = $script:GatewayState.gatewayId
            startedAt = $script:GatewayState.startedAt
            uptime = $uptime.ToString()
            uptimeMinutes = [Math]::Round($uptime.TotalMinutes, 2)
            transport = $script:GatewayState.transport
            httpPort = if ($script:GatewayState.httpPort) { $script:GatewayState.httpPort } else { $null }
            routeCount = $script:GatewayState.routes.Count
            enabledRouteCount = ($enabledRoutes | Measure-Object).Count
            disabledRouteCount = ($disabledRoutes | Measure-Object).Count
            sessionCount = $script:GatewayState.sessions.Count
            activeSessions = ($script:GatewayState.sessions.Values | Where-Object { $_.isActive } | Measure-Object).Count
            circuitBreakerStates = $circuitBreakerSummary
            config = $script:GatewayState.config
            routes = @($enabledRoutes | ForEach-Object { $_.packId })
            timestamp = [DateTime]::UtcNow.ToString("o")
        }
    }
}

#endregion

#region Pack Route Management

<#
.SYNOPSIS
    Adds a route for a pack to the gateway.

.DESCRIPTION
    Adds a new pack route to the gateway's routing table. Routes determine
    how MCP requests are directed to specific domain packs.

.PARAMETER PackId
    Unique identifier for the pack (e.g., "godot-engine", "blender-engine").

.PARAMETER Endpoint
    MCP server endpoint: "stdio" or HTTP URL like "http://localhost:8080".

.PARAMETER ToolPrefix
    Tool name prefix for routing (e.g., "godot_", "blender_").

.PARAMETER Priority
    Route priority for load balancing. Higher = preferred. Default: 1.

.PARAMETER Enabled
    Whether the route is enabled (default: $true).

.PARAMETER RateLimit
    Requests per minute limit (default: from gateway config).

.PARAMETER FallbackPackId
    Alternative pack ID to use if this pack is unavailable.

.PARAMETER Metadata
    Additional metadata for the route.

.EXAMPLE
    Add-MCPPackRoute -PackId "godot-engine" -ToolPrefix "godot_" -Endpoint "stdio" -Priority 2

.OUTPUTS
    PSCustomObject with the registered route configuration.

<#
.SYNOPSIS
    Removes a pack route from the gateway.

.DESCRIPTION
    Removes a pack route from the gateway's routing table.

.PARAMETER PackId
    The pack ID to remove.

.PARAMETER Force
    Force removal even if active sessions exist.

.EXAMPLE
    Remove-MCPPackRoute -PackId "godot-engine"

.OUTPUTS
    Boolean indicating success.

<#
.SYNOPSIS
    Registers a pack route with the gateway (alias for Add-MCPPackRoute).

.DESCRIPTION
    Backward-compatible alias for Add-MCPPackRoute.

<#
.SYNOPSIS
    Unregisters a pack route from the gateway (alias for Remove-MCPPackRoute).

.DESCRIPTION
    Backward-compatible alias for Remove-MCPPackRoute.

<#
.SYNOPSIS
    Gets all registered pack routes.

.DESCRIPTION
    Returns a list of all registered pack routes with their configurations.

.PARAMETER EnabledOnly
    Return only enabled routes.

.PARAMETER PackId
    Filter by specific pack ID (supports wildcards).

.PARAMETER IncludeHealth
    Include health check status for each route.

.EXAMPLE
    $routes = Get-MCPPackRoutes -EnabledOnly

.OUTPUTS
    Array of PSCustomObject route configurations.

#endregion

#region Request Routing and Gateway Operations

<#
.SYNOPSIS
    Routes an MCP gateway request to the appropriate pack.

.DESCRIPTION
    Determines the target pack based on tool name prefix and routes the
    request accordingly, applying:
    - Rate limiting
    - Circuit breaker pattern
    - Load balancing
    - Fallback logic
    - JSON-RPC 2.0 response formatting

.PARAMETER Request
    The JSON-RPC 2.0 request object with method, params, and id.

.PARAMETER ToolName
    The name of the MCP tool to invoke (alternative to Request).

.PARAMETER Arguments
    Arguments to pass to the tool (alternative to Request).

.PARAMETER SessionId
    Optional session ID for context-aware routing.

.PARAMETER CorrelationId
    Optional correlation ID for tracing. Auto-generated if not provided.

.PARAMETER UseFallback
    Allow fallback to alternative packs if primary fails.

.EXAMPLE
    $response = Invoke-MCPGatewayRequest -Request @{ jsonrpc = "2.0"; method = "tools/call"; params = @{ name = "godot_scene_create" }; id = 1 }

.EXAMPLE
    $response = Invoke-MCPGatewayRequest -ToolName "godot_scene_create" -Arguments @{ name = "Main" }

.OUTPUTS
    PSCustomObject with JSON-RPC 2.0 response format.
#>
function Invoke-MCPGatewayRequest {
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(ParameterSetName = 'Request')]
        [hashtable]$Request,

        [Parameter(ParameterSetName = 'Tool', Mandatory = $true)]
        [string]$ToolName,

        [Parameter(ParameterSetName = 'Tool')]
        [hashtable]$Arguments = @{},

        [Parameter()]
        [string]$SessionId = '',

        [Parameter()]
        [string]$CorrelationId = '',

        [Parameter()]
        [switch]$UseFallback
    )

    begin {
        Ensure-GatewayRunning

        # Generate correlation ID if not provided
        if ([string]::IsNullOrEmpty($CorrelationId)) {
            $CorrelationId = [Guid]::NewGuid().ToString()
        }

        # Extract tool name and arguments from request if provided
        if ($Request) {
            if ($Request.params -and $Request.params.name) {
                $ToolName = $Request.params.name
                $Arguments = $Request.params.arguments
                if (-not $Arguments) { $Arguments = @{} }
            }
            elseif ($Request.method -and $Request.method -eq 'tools/call') {
                $ToolName = $Request.params.name
                $Arguments = $Request.params.arguments
                if (-not $Arguments) { $Arguments = @{} }
            }
            else {
                return New-JsonRpcErrorResponse -Id ($Request.id) -Code -32600 -Message "Invalid request format" -CorrelationId $CorrelationId
            }
        }

        if ([string]::IsNullOrEmpty($ToolName)) {
            return New-JsonRpcErrorResponse -Id ($Request.id) -Code -32600 -Message "Tool name is required" -CorrelationId $CorrelationId
        }
    }

    process {
        $startTime = [DateTime]::UtcNow
        $requestId = if ($Request -and $Request.id) { $Request.id } else { [Guid]::NewGuid().ToString() }

        # Store correlation context
        $script:GatewayState.correlationContext[$CorrelationId] = @{
            requestId = $requestId
            toolName = $ToolName
            startedAt = $startTime
            sessionId = $SessionId
        }

        # Determine target pack from tool name prefix
        $targetPack = Resolve-PackFromToolName -ToolName $ToolName

        if (-not $targetPack) {
            $errorResponse = New-JsonRpcErrorResponse -Id $requestId -Code -32601 -Message "No route found for tool: $ToolName" -CorrelationId $CorrelationId
            
            Write-GatewayStructuredLog -Level ERROR -Message "Routing failed: No route found" -CorrelationId $CorrelationId -Metadata @{
                requestId = $requestId
                toolName = $ToolName
            }
            
            return $errorResponse
        }

        # Check circuit breaker
        if ($script:GatewayState.config.enableCircuitBreaker) {
            $cbResult = Test-CircuitBreaker -PackId $targetPack
            if (-not $cbResult.allowed) {
                # Try fallback if available
                if ($UseFallback -or $script:GatewayState.config.enableFallback) {
                    $fallbackPack = Get-FallbackPack -PackId $targetPack
                    if ($fallbackPack) {
                        Write-GatewayStructuredLog -Level WARN -Message "Circuit breaker open, using fallback" -CorrelationId $CorrelationId -Metadata @{
                            requestId = $requestId
                            primaryPack = $targetPack
                            fallbackPack = $fallbackPack
                        }
                        $targetPack = $fallbackPack
                    }
                    else {
                        return New-JsonRpcErrorResponse -Id $requestId -Code -32000 -Message "Circuit breaker open for pack: $targetPack" -CorrelationId $CorrelationId
                    }
                }
                else {
                    return New-JsonRpcErrorResponse -Id $requestId -Code -32000 -Message "Circuit breaker open for pack: $targetPack" -CorrelationId $CorrelationId
                }
            }
        }

        # Check rate limit
        $rateLimitResult = _Test-RateLimit -PackId $targetPack
        if (-not $rateLimitResult.allowed) {
            # Try fallback if available
            $fallbackPack = Get-FallbackPack -PackId $targetPack
            if ($fallbackPack -and $script:GatewayState.config.enableFallback) {
                Write-GatewayStructuredLog -Level WARN -Message "Rate limit exceeded, using fallback" -CorrelationId $CorrelationId -Metadata @{
                    requestId = $requestId
                    primaryPack = $targetPack
                    fallbackPack = $fallbackPack
                }
                $targetPack = $fallbackPack
            }
            else {
                return New-JsonRpcErrorResponse -Id $requestId -Code -32001 -Message "Rate limit exceeded for pack: $targetPack" -Data @{ retryAfter = $rateLimitResult.retryAfter } -CorrelationId $CorrelationId
            }
        }

        # Get route configuration
        $route = $script:GatewayState.routes[$targetPack]
        if (-not $route -or -not $route.enabled) {
            return New-JsonRpcErrorResponse -Id $requestId -Code -32601 -Message "Route disabled or not found for pack: $targetPack" -CorrelationId $CorrelationId
        }

        # Update route statistics
        $route.requestCount++
        $route.lastRequestAt = [DateTime]::UtcNow.ToString("o")

        # Execute the tool via appropriate endpoint
        try {
            $response = Invoke-ToolAtEndpoint -Route $route -ToolName $ToolName -Arguments $Arguments -SessionId $SessionId -CorrelationId $CorrelationId
            $duration = ([DateTime]::UtcNow - $startTime).TotalMilliseconds

            # Record success for circuit breaker
            Record-CircuitBreakerSuccess -PackId $targetPack

            Write-GatewayStructuredLog -Level INFO -Message "Request routed successfully" -CorrelationId $CorrelationId -Metadata @{
                requestId = $requestId
                toolName = $ToolName
                packId = $targetPack
                durationMs = [Math]::Round($duration, 2)
            }

            # Return JSON-RPC 2.0 success response
            return New-JsonRpcSuccessResponse -Id $requestId -Result $response -CorrelationId $CorrelationId
        }
        catch {
            $duration = ([DateTime]::UtcNow - $startTime).TotalMilliseconds
            
            # Record failure for circuit breaker
            Record-CircuitBreakerFailure -PackId $targetPack

            Write-GatewayStructuredLog -Level ERROR -Message "Request routing failed" -CorrelationId $CorrelationId -Metadata @{
                requestId = $requestId
                toolName = $ToolName
                packId = $targetPack
                error = $_.Exception.Message
                durationMs = [Math]::Round($duration, 2)
            }

            return New-JsonRpcErrorResponse -Id $requestId -Code -32603 -Message "Tool execution failed: $($_.Exception.Message)" -CorrelationId $CorrelationId
        }
    }
}

<#
.SYNOPSIS
    Routes an MCP request to the appropriate pack (alias for Invoke-MCPGatewayRequest).

.DESCRIPTION
    Backward-compatible alias for Invoke-MCPGatewayRequest.
#>
function Invoke-MCPPackRoute {
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory = $true)]
        [string]$ToolName,

        [Parameter()]
        [hashtable]$Arguments = @{},

        [Parameter()]
        [string]$SessionId = '',

        [Parameter()]
        [string]$RequestId = ''
    )

    process {
        $correlationId = if ($RequestId) { $RequestId } else { [Guid]::NewGuid().ToString() }
        return Invoke-MCPGatewayRequest -ToolName $ToolName -Arguments $Arguments -SessionId $SessionId -CorrelationId $correlationId
    }
}

<#
.SYNOPSIS
    Gets the aggregated tool manifest from all connected packs.

.DESCRIPTION
    Returns a unified MCP tools list containing all tools from all registered
    and enabled pack routes, formatted as an MCP tools/list response.

.PARAMETER IncludeMetadata
    Include additional metadata for each tool.

.PARAMETER FilterPrefix
    Filter tools by prefix pattern.

.PARAMETER CorrelationId
    Optional correlation ID for tracing.

.EXAMPLE
    $manifest = Get-MCPGatewayManifest

.EXAMPLE
    $manifest = Get-MCPGatewayManifest -FilterPrefix "godot_"

.OUTPUTS
    PSCustomObject with JSON-RPC 2.0 response containing aggregated tools.

<#
.SYNOPSIS
    Gets all tools from all registered packs (alias for Get-MCPGatewayManifest).

.DESCRIPTION
    Backward-compatible alias for Get-MCPGatewayManifest.

<#
.SYNOPSIS
    Performs health checks on all connected pack servers.

.DESCRIPTION
    Tests connectivity and health status for all registered pack routes,
    returning detailed health information for each pack and the overall
    gateway health.

.PARAMETER PackId
    Specific pack ID to check. If not provided, checks all packs.

.PARAMETER CorrelationId
    Optional correlation ID for tracing.

.PARAMETER UpdateRouteStatus
    Update route enabled status based on health check results.

.EXAMPLE
    $health = Test-MCPGatewayHealth

.EXAMPLE
    $health = Test-MCPGatewayHealth -PackId "godot-engine"

.OUTPUTS
    PSCustomObject with health status for each pack and overall summary.

<#
.SYNOPSIS
    Determines which pack handles a specific tool.

.DESCRIPTION
    Resolves the target pack for a given tool name based on routing rules
    and prefix matching.

.PARAMETER ToolName
    The name of the tool to resolve.

.PARAMETER IncludeFallback
    Include fallback pack in the result if available.

.EXAMPLE
    $target = Resolve-MCPToolTarget -ToolName "godot_scene_create"

.OUTPUTS
    PSCustomObject with pack resolution information.
#>
function Resolve-MCPToolTarget {
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory = $true)]
        [string]$ToolName,

        [Parameter()]
        [switch]$IncludeFallback
    )

    begin {
        Ensure-GatewayRunning
    }

    process {
        $primaryPack = Resolve-PackFromToolName -ToolName $ToolName

        if (-not $primaryPack) {
            return [PSCustomObject]@{
                resolved = $false
                toolName = $ToolName
                primaryPack = $null
                fallbackPack = $null
                reason = "No matching route found"
            }
        }

        $route = $script:GatewayState.routes[$primaryPack]
        $result = [PSCustomObject]@{
            resolved = $true
            toolName = $ToolName
            primaryPack = $primaryPack
            route = $route
            prefix = $route.prefix
            reason = "Prefix match"
        }

        if ($IncludeFallback) {
            $fallbackPack = Get-FallbackPack -PackId $primaryPack
            $result | Add-Member -NotePropertyName 'fallbackPack' -NotePropertyValue $fallbackPack -Force
        }

        return $result
    }
}

#endregion

#region Cross-Pack Operations

<#
.SYNOPSIS
    Executes a query across multiple packs.

.DESCRIPTION
    Routes a query to multiple applicable packs and aggregates the results,
    applying cross-pack arbitration rules.

.PARAMETER Query
    The query string to execute.

.PARAMETER TargetPacks
    Array of pack IDs to query. If empty, determines automatically.

.PARAMETER SessionId
    Optional session ID for context sharing.

.PARAMETER AggregateResults
    Aggregate results from multiple packs (default: $true).

.PARAMETER MaxResultsPerPack
    Maximum results to return per pack.

.PARAMETER CorrelationId
    Optional correlation ID for tracing.

.EXAMPLE
    $results = Invoke-MCPCrossPackQuery -Query "scene management" -TargetPacks @("godot-engine", "blender-engine")

.OUTPUTS
    PSCustomObject with aggregated query results.

<#
.SYNOPSIS
    Executes a tool via the gateway's routing system.

.DESCRIPTION
    High-level function to invoke an MCP tool with automatic routing,
    session management, and error handling.

.PARAMETER ToolName
    The name of the tool to execute.

.PARAMETER Arguments
    Arguments to pass to the tool.

.PARAMETER SessionId
    Optional session ID for context.

.PARAMETER UseFallback
    Allow fallback to alternative packs if primary fails.

.PARAMETER TimeoutSeconds
    Timeout for tool execution (default: 60).

.PARAMETER CorrelationId
    Optional correlation ID for tracing.

.EXAMPLE
    $result = Invoke-MCPAggregatedTool -ToolName "godot_scene_create" -Arguments @{ name = "Main" }

.OUTPUTS
    PSCustomObject with execution result.

<#
.SYNOPSIS
    Gets evidence from multiple packs.

.DESCRIPTION
    Retrieves supporting evidence for a claim or query from multiple
    pack sources, with confidence scoring per Section 13.2.

.PARAMETER Claim
    The claim or statement to verify.

.PARAMETER SourcePacks
    Array of pack IDs to query for evidence.

.PARAMETER MinConfidence
    Minimum confidence threshold (0.0 to 1.0).

.PARAMETER SessionId
    Optional session ID.

.PARAMETER CorrelationId
    Optional correlation ID for tracing.

.EXAMPLE
    $evidence = Get-MCPCrossPackEvidence -Claim "Use signals for decoupling" -SourcePacks @("godot-engine")

.OUTPUTS
    PSCustomObject with evidence from multiple sources.

<#
.SYNOPSIS
    Creates a cross-pack context for multi-domain operations.

.DESCRIPTION
    Establishes a shared context across multiple packs, enabling coordinated
    operations and data sharing between domains.

.PARAMETER PackIds
    Array of pack IDs to include in the context.

.PARAMETER InitialData
    Initial context data to share across packs.

.PARAMETER SessionId
    Optional session ID to extend.

.PARAMETER ExpiryMinutes
    Context expiry time in minutes.

.PARAMETER CorrelationId
    Optional correlation ID for tracing.

.EXAMPLE
    $context = New-MCPCrossPackContext -PackIds @("godot-engine", "blender-engine") -InitialData @{ project = "MyGame" }

.OUTPUTS
    PSCustomObject with cross-pack context information.

#endregion

#region Blenderâ†’Godot Pipeline Functions

<#
.SYNOPSIS
    Exports assets from Blender to Godot format.

.DESCRIPTION
    Coordinates the export of assets from Blender to Godot-compatible formats,
    managing the pipeline workflow between the two packs.

.PARAMETER SourcePath
    Path to the Blender source file or directory.

.PARAMETER OutputPath
    Output path for Godot-compatible files.

.PARAMETER Options
    Export options (format, settings, etc.).

.PARAMETER SessionId
    Optional session ID for pipeline context.

.PARAMETER WaitForCompletion
    Wait for export to complete before returning.

.PARAMETER CorrelationId
    Optional correlation ID for tracing.

.EXAMPLE
    $result = Invoke-MCPBlenderToGodotExport -SourcePath "./models/character.blend" -OutputPath "./godot/assets/"

.OUTPUTS
    PSCustomObject with export operation status.

<#
.SYNOPSIS
    Gets the status of a pipeline operation.

.DESCRIPTION
    Retrieves current status and progress information for a pipeline,
    including Blenderâ†’Godot export operations.

.PARAMETER PipelineId
    The pipeline ID to check.

.PARAMETER IncludeHistory
    Include full operation history.

.EXAMPLE
    $status = Get-MCPPipelineStatus -PipelineId "blender-to-godot-123"

.OUTPUTS
    PSCustomObject with pipeline status.

<#
.SYNOPSIS
    Registers a pipeline step configuration.

.DESCRIPTION
    Adds a step to a pipeline definition for multi-stage operations
    like Blenderâ†’Godot asset export workflows.

.PARAMETER PipelineId
    The pipeline ID to add the step to.

.PARAMETER StepConfig
    Step configuration hashtable with stepId, toolName, arguments.

.PARAMETER DependsOn
    Array of step IDs that must complete before this step.

.EXAMPLE
    Register-MCPPipelineStep -PipelineId "asset-pipeline" -StepConfig @{ stepId = "export"; toolName = "blender_export" }

.OUTPUTS
    PSCustomObject with registered step information.

#endregion

#region Session Management Functions

<#
.SYNOPSIS
    Creates a new MCP session.

.DESCRIPTION
    Establishes a session for context sharing across multiple MCP tool
    invocations and pack interactions.

.PARAMETER ContextData
    Initial context data for the session.

.PARAMETER ExpiryMinutes
    Session expiry time in minutes (default: 30).

.PARAMETER Metadata
    Additional session metadata.

.PARAMETER CorrelationId
    Optional correlation ID for tracing.

.EXAMPLE
    $session = New-MCPSession -ContextData @{ project = "MyGame" } -ExpiryMinutes 60

.OUTPUTS
    PSCustomObject with session information.

<#
.SYNOPSIS
    Gets session information.

.DESCRIPTION
    Retrieves session details including context data, pack contexts,
    and activity information.

.PARAMETER SessionId
    The session ID to retrieve.

.PARAMETER IncludeInactive
    Include expired or inactive sessions.

.EXAMPLE
    $session = Get-MCPSession -SessionId "550e8400-e29b-41d4-a716-446655440000"

.OUTPUTS
    PSCustomObject with session information, or $null if not found.

<#
.SYNOPSIS
    Removes an MCP session.

.DESCRIPTION
    Cleans up a session and notifies all associated packs to release
    their context resources.

.PARAMETER SessionId
    The session ID to remove.

.PARAMETER Force
    Force removal even if cleanup fails.

.PARAMETER CorrelationId
    Optional correlation ID for tracing.

.EXAMPLE
    Remove-MCPSession -SessionId "550e8400-e29b-41d4-a716-446655440000"

.OUTPUTS
    Boolean indicating success.

#endregion

#region Additional Session Management Functions

<#
.SYNOPSIS
    Updates session context data.

.DESCRIPTION
    Updates the context data for an existing session, optionally merging
    with existing context or replacing it entirely.

.PARAMETER SessionId
    The session ID to update.

.PARAMETER ContextData
    New context data to add/update.

.PARAMETER Merge
    Merge with existing context (default: $true). If $false, replaces existing context.

.PARAMETER CorrelationId
    Optional correlation ID for tracing.

.EXAMPLE
    Update-SessionContext -SessionId "550e8400..." -ContextData @{ project = "UpdatedGame" }

.OUTPUTS
    PSCustomObject with updated session information.

#endregion

#region Additional Routing Functions

<#
.SYNOPSIS
    Gets a specific pack route configuration.

.DESCRIPTION
    Retrieves the route configuration for a specific pack by ID.

.PARAMETER PackId
    The pack ID to get the route for.

.PARAMETER IncludeHealthStatus
    Include current health status and circuit breaker state.

.EXAMPLE
    $route = Get-MCPPackRoute -PackId "godot-engine"

.OUTPUTS
    PSCustomObject with route configuration, or $null if not found.

<#
.SYNOPSIS
    Routes an MCP request to the appropriate pack.

.DESCRIPTION
    Routes a request to the appropriate pack based on tool name prefix,
    applying rate limiting and circuit breaker patterns. This is an alias
    for Invoke-MCPGatewayRequest with simplified parameter set.

.PARAMETER Request
    The JSON-RPC 2.0 request object.

.PARAMETER SessionId
    Optional session ID for context-aware routing.

.PARAMETER CorrelationId
    Optional correlation ID for tracing.

.EXAMPLE
    $response = Route-MCPRequest -Request $jsonRpcRequest

.OUTPUTS
    PSCustomObject with JSON-RPC 2.0 response.

#endregion

#region Circuit Breaker Functions

<#
.SYNOPSIS
    Tests if a circuit breaker allows requests for a pack.

.DESCRIPTION
    Checks the circuit breaker state for a pack and returns whether
    requests are currently allowed, along with state details.

.PARAMETER PackId
    The pack ID to check.

.EXAMPLE
    $result = Test-MCPCircuitBreaker -PackId "godot-engine"
    if ($result.allowed) { # proceed with request }

.OUTPUTS
    PSCustomObject with allowed (bool), state, and retryAfter information.

<#
.SYNOPSIS
    Records a successful request for circuit breaker tracking.

.DESCRIPTION
    Records a success for the circuit breaker associated with a pack,
    potentially closing the circuit if it was half-open.

.PARAMETER PackId
    The pack ID to record success for.

.EXAMPLE
    Record-MCPSuccess -PackId "godot-engine"

.OUTPUTS
    PSCustomObject with updated circuit breaker state.

<#
.SYNOPSIS
    Records a failed request for circuit breaker tracking.

.DESCRIPTION
    Records a failure for the circuit breaker associated with a pack,
    potentially opening the circuit if threshold is reached.

.PARAMETER PackId
    The pack ID to record failure for.

.PARAMETER ErrorMessage
    Optional error message describing the failure.

.EXAMPLE
    Record-MCPFailure -PackId "godot-engine" -ErrorMessage "Connection timeout"

.OUTPUTS
    PSCustomObject with updated circuit breaker state.

<#
.SYNOPSIS
    Manually resets a circuit breaker.

.DESCRIPTION
    Forces a circuit breaker to the CLOSED state, clearing any
    failure counts. Use with caution - typically only for recovery scenarios.

.PARAMETER PackId
    The pack ID whose circuit breaker to reset.

.PARAMETER Force
    Force reset even if circuit is healthy.

.EXAMPLE
    Reset-MCPCircuitBreaker -PackId "godot-engine"

.OUTPUTS
    PSCustomObject with reset result.

#endregion

#region Rate Limiting Functions

<#
.SYNOPSIS
    Tests if a request is allowed under rate limiting rules.

.DESCRIPTION
    Checks if a request to the specified pack would be allowed
    under current rate limiting constraints.

.PARAMETER PackId
    The pack ID to check rate limit for.

.PARAMETER ConsumeToken
    Actually consume a token if allowed (default: $false for testing).

.EXAMPLE
    $result = Test-MCPRateLimit -PackId "godot-engine"
    if ($result.allowed) { # proceed with request }

.OUTPUTS
    PSCustomObject with allowed status, remaining tokens, and retry info.

<#
.SYNOPSIS
    Gets the current rate limit status for a pack or all packs.

.DESCRIPTION
    Returns detailed rate limiting information including current tokens,
    request counts, and window information.

.PARAMETER PackId
    Specific pack ID to get status for. If not provided, returns all packs.

.EXAMPLE
    $status = Get-MCPRateLimitStatus -PackId "godot-engine"
    $allStatus = Get-MCPRateLimitStatus

.OUTPUTS
    PSCustomObject or array of PSCustomObject with rate limit status.

#endregion

#region Request Processing Functions

<#
.SYNOPSIS
    Starts the MCP Gateway server.

.DESCRIPTION
    Alias for Start-MCPCompositeGateway for simplified naming.
    Starts the gateway with the specified transport and configuration.

.PARAMETER Transport
    Transport mode: 'stdio' or 'http'. Default: stdio.

.PARAMETER Port
    Port for HTTP transport. Default: 8080.

.PARAMETER Host
    Host address for HTTP transport. Default: localhost.

.PARAMETER AutoLoadRoutes
    Automatically load routes from configuration.

.PARAMETER ConfigPath
    Optional path to gateway configuration file.

.EXAMPLE
    Start-MCPGateway -Transport http -Port 9090

.OUTPUTS
    PSCustomObject with gateway status.
#>
function Start-MCPGateway {
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter()]
        [ValidateSet('stdio', 'http')]
        [string]$Transport = 'stdio',

        [Parameter()]
        [ValidateRange(1, 65535)]
        [int]$Port = 8080,

        [Parameter()]
        [string]$Host = 'localhost',

        [Parameter()]
        [switch]$AutoLoadRoutes,

        [Parameter()]
        [string]$ConfigPath = ''
    )

    process {
        $params = @{
            Transport = $Transport
            Port = $Port
            Host = $Host
            AutoLoadRoutes = $AutoLoadRoutes
        }
        if ($ConfigPath) {
            $params['ConfigPath'] = $ConfigPath
        }
        return Start-MCPCompositeGateway @params
    }
}

<#
.SYNOPSIS
    Stops the MCP Gateway server.

.DESCRIPTION
    Alias for Stop-MCPCompositeGateway for simplified naming.
    Gracefully shuts down the gateway.

.PARAMETER Force
    Force immediate shutdown without waiting for active requests.

.PARAMETER TimeoutSeconds
    Maximum time to wait for graceful shutdown. Default: 30.

.EXAMPLE
    Stop-MCPGateway

.OUTPUTS
    PSCustomObject with shutdown status.
#>
function Stop-MCPGateway {
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter()]
        [switch]$Force,

        [Parameter()]
        [ValidateRange(0, 300)]
        [int]$TimeoutSeconds = 30
    )

    process {
        return Stop-MCPCompositeGateway -Force:$Force -TimeoutSeconds $TimeoutSeconds
    }
}

<#
.SYNOPSIS
    Processes an MCP gateway request.

.DESCRIPTION
    Main request handler for the gateway. Processes incoming MCP requests,
    routes them to appropriate packs, and returns structured responses.
    This is the primary entry point for request processing.

.PARAMETER Request
    The JSON-RPC 2.0 request object.

.PARAMETER RawJson
    Raw JSON string of the request (alternative to Request).

.PARAMETER SessionId
    Optional session ID for context-aware routing.

.PARAMETER CorrelationId
    Optional correlation ID for tracing. Auto-generated if not provided.

.EXAMPLE
    $response = Process-MCPGatewayRequest -Request $jsonRpcRequest

.EXAMPLE
    $response = Process-MCPGatewayRequest -RawJson '{"jsonrpc":"2.0","method":"tools/call",...}'

.OUTPUTS
    PSCustomObject with JSON-RPC 2.0 response.
#>
function Process-MCPGatewayRequest {
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(ParameterSetName = 'Request')]
        [hashtable]$Request,

        [Parameter(ParameterSetName = 'RawJson')]
        [string]$RawJson,

        [Parameter()]
        [string]$SessionId = '',

        [Parameter()]
        [string]$CorrelationId = ''
    )

    begin {
        Ensure-GatewayRunning

        if ([string]::IsNullOrEmpty($CorrelationId)) {
            $CorrelationId = [Guid]::NewGuid().ToString()
        }
    }

    process {
        # Parse raw JSON if provided
        if ($RawJson) {
            try {
                $Request = $RawJson | ConvertFrom-Json -AsHashtable
            }
            catch {
                return New-JsonRpcErrorResponse -Id $null -Code -32700 -Message "Parse error: $($_.Exception.Message)" -CorrelationId $CorrelationId
            }
        }

        # Validate request
        if (-not $Request) {
            return New-JsonRpcErrorResponse -Id $null -Code -32600 -Message "Invalid request: Request is null" -CorrelationId $CorrelationId
        }

        if ($Request.jsonrpc -ne '2.0') {
            return New-JsonRpcErrorResponse -Id ($Request.id) -Code -32600 -Message "Invalid request: jsonrpc must be '2.0'" -CorrelationId $CorrelationId
        }

        $requestId = if ($Request.id) { $Request.id } else { [Guid]::NewGuid().ToString() }

        # Log request receipt
        Write-GatewayStructuredLog -Level INFO -Message "Processing gateway request" -CorrelationId $CorrelationId -Metadata @{
            requestId = $requestId
            method = $Request.method
            sessionId = $SessionId
        }

        try {
            # Route the request
            $result = Invoke-MCPGatewayRequest -Request $Request -SessionId $SessionId -CorrelationId $CorrelationId -UseFallback
            return $result
        }
        catch {
            Write-GatewayStructuredLog -Level ERROR -Message "Request processing failed" -CorrelationId $CorrelationId -Metadata @{
                requestId = $requestId
                error = $_.Exception.Message
            }

            return New-JsonRpcErrorResponse -Id $requestId -Code -32603 -Message "Internal error: $($_.Exception.Message)" -CorrelationId $CorrelationId
        }
    }
}

#endregion

#region Helper Functions

<#
.SYNOPSIS
    Ensures the gateway is running.

.DESCRIPTION
    Internal helper that throws an exception if the gateway is not running.
#>
function Ensure-GatewayRunning {
    [CmdletBinding()]
    param()

    if (-not $script:GatewayState.isRunning) {
        throw "MCP Composite Gateway is not running. Call Start-MCPCompositeGateway first."
    }
}

<#
.SYNOPSIS
    Resolves the target pack from a tool name.

.DESCRIPTION
    Extracts the prefix from a tool name and maps it to a registered pack.

<#
.SYNOPSIS
    Gets the fallback pack for a given pack.

<#
.SYNOPSIS
    Tests rate limit for a pack.

<#
.SYNOPSIS
    Initializes rate limiters for all routes.

<#
.SYNOPSIS
    Initializes a circuit breaker for a pack.

<#
.SYNOPSIS
    Initializes circuit breakers for all routes.

<#
.SYNOPSIS
    Tests if a circuit breaker allows a request.

<#
.SYNOPSIS
    Records a success for circuit breaker tracking.

<#
.SYNOPSIS
    Records a failure for circuit breaker tracking.

<#
.SYNOPSIS
    Invokes a tool at the specified route endpoint.

.DESCRIPTION
    Internal helper to execute tools via stdio or HTTP endpoints.
#>
function Invoke-ToolAtEndpoint {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [pscustomobject]$Route,

        [Parameter(Mandatory = $true)]
        [string]$ToolName,

        [Parameter()]
        [hashtable]$Arguments = @{},

        [Parameter()]
        [string]$SessionId = '',

        [Parameter()]
        [string]$CorrelationId = ''
    )

    # Build request payload
    $payload = @{
        jsonrpc = "2.0"
        method = "tools/call"
        params = @{
            name = $ToolName
            arguments = $Arguments
        }
        id = [Guid]::NewGuid().ToString()
    }

    if (-not [string]::IsNullOrEmpty($SessionId)) {
        $payload.params.sessionId = $SessionId
    }

    if (-not [string]::IsNullOrEmpty($CorrelationId)) {
        $payload.params.correlationId = $CorrelationId
    }

    if ($Route.endpoint -eq 'stdio') {
        # For stdio, we would typically invoke a local process
        # This is a placeholder for actual stdio implementation
        return @{
            toolName = $ToolName
            route = $Route.packId
            endpoint = 'stdio'
            result = "Tool '$ToolName' invoked via stdio (placeholder)"
        }
    }
    elseif ($Route.endpoint.StartsWith('http')) {
        # HTTP endpoint invocation
        $uri = "$($Route.endpoint)/mcp/v1/tools/$ToolName"
        $body = $payload | ConvertTo-Json -Depth 5

        $response = Invoke-RestMethod -Uri $uri -Method Post -Body $body -ContentType 'application/json' -ErrorAction Stop
        return $response.result
    }
    else {
        throw "Unknown endpoint type: $($Route.endpoint)"
    }
}

<#
.SYNOPSIS
    Gets tools from a pack route.

.DESCRIPTION
    Retrieves available tools from a pack via its endpoint.

<#
.SYNOPSIS
    Determines target packs for cross-pack queries.

.DESCRIPTION
    Analyzes query and returns relevant pack IDs.

<#
.SYNOPSIS
    Tests health of a pack route.

.DESCRIPTION
    Performs health check on a specific pack route.

<#
.SYNOPSIS
    Starts the HTTP listener for the gateway.

.DESCRIPTION
    Sets up an HTTP listener for handling MCP requests over HTTP.
#>
function Start-MCPGatewayHttpListener {
    [CmdletBinding()]
    param(
        [Parameter()]
        [int]$Port = 8080,

        [Parameter()]
        [string]$Host = 'localhost'
    )

    try {
        $listener = New-Object System.Net.HttpListener
        $listener.Prefixes.Add("http://$Host`:$Port`/")
        $listener.Start()
        $script:GatewayState.httpListener = $listener

        Write-Verbose "HTTP listener started on http://$Host`:$Port`/"

        # Start request handling in background
        Start-Job -ScriptBlock {
            param($Listener, $GatewayState)
            while ($Listener.IsListening) {
                $context = $Listener.GetContext()
                $request = $context.Request
                $response = $context.Response

                try {
                    if ($request.Url.PathAndQuery -eq '/mcp/v1/tools') {
                        # Return tools list
                        $tools = Get-MCPGatewayManifest
                        $json = $tools | ConvertTo-Json -Depth 10
                        $buffer = [System.Text.Encoding]::UTF8.GetBytes($json)
                        $response.ContentType = 'application/json'
                        $response.OutputStream.Write($buffer, 0, $buffer.Length)
                    }
                    elseif ($request.Url.PathAndQuery -eq '/health') {
                        # Health check endpoint
                        $health = Test-MCPGatewayHealth
                        $json = $health | ConvertTo-Json -Depth 10
                        $buffer = [System.Text.Encoding]::UTF8.GetBytes($json)
                        $response.ContentType = 'application/json'
                        $response.OutputStream.Write($buffer, 0, $buffer.Length)
                    }
                    else {
                        $response.StatusCode = 404
                    }
                }
                finally {
                    $response.Close()
                }
            }
        } -ArgumentList $listener, $script:GatewayState | Out-Null
    }
    catch {
        Write-Warning "Failed to start HTTP listener: $_"
        throw
    }
}

<#
.SYNOPSIS
    Creates a JSON-RPC 2.0 success response.

.DESCRIPTION
    Helper function to create a properly formatted JSON-RPC 2.0 success response.
#>
function New-JsonRpcSuccessResponse {
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter()]
        [object]$Id = $null,

        [Parameter(Mandatory = $true)]
        [object]$Result,

        [Parameter()]
        [string]$CorrelationId = ''
    )

    $response = [PSCustomObject]@{
        jsonrpc = "2.0"
        result = $Result
        id = $Id
    }

    if (-not [string]::IsNullOrEmpty($CorrelationId)) {
        $response | Add-Member -NotePropertyName 'correlationId' -NotePropertyValue $CorrelationId -Force
    }

    return $response
}

<#
.SYNOPSIS
    Creates a JSON-RPC 2.0 error response.

.DESCRIPTION
    Helper function to create a properly formatted JSON-RPC 2.0 error response.
#>
function New-JsonRpcErrorResponse {
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter()]
        [object]$Id = $null,

        [Parameter(Mandatory = $true)]
        [int]$Code,

        [Parameter(Mandatory = $true)]
        [string]$Message,

        [Parameter()]
        [object]$Data = $null,

        [Parameter()]
        [string]$CorrelationId = ''
    )

    $errorObj = @{
        code = $Code
        message = $Message
    }

    if ($Data) {
        $errorObj['data'] = $Data
    }

    $response = [PSCustomObject]@{
        jsonrpc = "2.0"
        error = $errorObj
        id = $Id
    }

    if (-not [string]::IsNullOrEmpty($CorrelationId)) {
        $response | Add-Member -NotePropertyName 'correlationId' -NotePropertyValue $CorrelationId -Force
    }

    return $response
}

<#
.SYNOPSIS
    Writes a structured log entry for gateway operations.

.DESCRIPTION
    Helper function that integrates with the Logging.ps1 module if available,
    otherwise falls back to internal logging.
#>
function Write-GatewayStructuredLog {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [ValidateSet('VERBOSE', 'DEBUG', 'INFO', 'WARN', 'ERROR', 'CRITICAL', 'FATAL')]
        [string]$Level,

        [Parameter(Mandatory = $true)]
        [string]$Message,

        [Parameter()]
        [string]$CorrelationId = '',

        [Parameter()]
        [hashtable]$Metadata = @{},

        [Parameter()]
        [System.Exception]$Exception = $null
    )

    # Add gateway context to metadata
    $Metadata['gatewayId'] = $script:GatewayState.gatewayId
    $Metadata['isRunning'] = $script:GatewayState.isRunning

    # Try to use structured logging module
    $newLogEntryCmd = Get-Command New-LogEntry -ErrorAction SilentlyContinue
    $writeStructuredLogCmd = Get-Command Write-StructuredLog -ErrorAction SilentlyContinue

    if ($newLogEntryCmd -and $writeStructuredLogCmd) {
        try {
            $entry = New-LogEntry -Level $Level -Message $Message -CorrelationId $CorrelationId -Source "MCPCompositeGateway" -Metadata $Metadata -Exception $Exception
            Write-StructuredLog -Entry $entry
            return
        }
        catch {
            # Fall through to internal logging
        }
    }

    # Fallback to internal logging
    Add-GatewayLog -Level $Level -Message $Message -Context $Metadata
}

<#
.SYNOPSIS
    Adds a log entry to the gateway logs.

.DESCRIPTION
    Internal logging function with rotation.
#>
function Add-GatewayLog {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [ValidateSet('Debug', 'Info', 'Warning', 'Error')]
        [string]$Level,

        [Parameter(Mandatory = $true)]
        [string]$Message,

        [Parameter()]
        [hashtable]$Context = @{}
    )

    $logEntry = [PSCustomObject]@{
        timestamp = [DateTime]::UtcNow.ToString("o")
        level = $Level
        message = $Message
        context = $Context
    }

    $script:GatewayState.logs += $logEntry

    # Simple log rotation
    $maxLogs = $script:GatewayState.config.logRetentionCount
    if ($script:GatewayState.logs.Count -gt $maxLogs) {
        $script:GatewayState.logs = $script:GatewayState.logs | Select-Object -Last $maxLogs
    }

    # Also write to verbose/debug streams
    switch ($Level) {
        'Debug' { Write-Verbose $Message }
        'Info' { Write-Verbose $Message }
        'Warning' { Write-Warning $Message }
        'Error' { Write-Error $Message }
    }
}

<#
.SYNOPSIS
    Merges gateway configuration.

.DESCRIPTION
    Helper to merge configuration overrides with defaults.
#>
function Merge-GatewayConfig {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [hashtable]$Base,

        [Parameter(Mandatory = $true)]
        [hashtable]$Override
    )

    $result = $Base.Clone()

    foreach ($key in $Override.Keys) {
        if ($result.ContainsKey($key) -and $Override[$key] -is [hashtable] -and $result[$key] -is [hashtable]) {
            $result[$key] = Merge-GatewayConfig -Base $result[$key] -Override $Override[$key]
        }
        else {
            $result[$key] = $Override[$key]
        }
    }

    return $result
}

<#
.SYNOPSIS
    Imports routes from configuration.

.DESCRIPTION
    Helper to load routes from config file.
#>
function Import-MCPRoutesFromConfig {
    [CmdletBinding()]
    param()

    $configPath = Join-Path $PWD '.llm-workflow/mcp-gateway-config.json'

    if (-not (Test-Path -LiteralPath $configPath)) {
        Write-Verbose "No gateway config found at $configPath"
        return
    }

    try {
        $config = Get-Content -Path $configPath -Raw | ConvertFrom-Json -AsHashtable

        if ($config.routes) {
            foreach ($route in $config.routes) {
                Add-MCPPackRoute `
                    -PackId $route.packId `
                    -ToolPrefix $route.prefix `
                    -Endpoint $route.endpoint `
                    -Enabled ($route.enabled -ne $false) `
                    -RateLimit $(if ($route.rateLimit) { $route.rateLimit } else { 100 }) `
                    -FallbackPackId $(if ($route.fallbackPackId) { $route.fallbackPackId } else { '' }) `
                    -Metadata $(if ($route.metadata) { $route.metadata } else { @{} }) `
                    -Priority $(if ($route.priority) { $route.priority } else { 1 })
            }
        }

        Add-GatewayLog -Level 'Info' -Message "Routes imported from config" -Context @{
            configPath = $configPath
            routeCount = $config.routes.Count
        }
    }
    catch {
        Write-Warning "Failed to import routes from config: $($_.Exception.Message)"
    }
}

#endregion

# Export functions
Export-ModuleMember -Function @(
    # Gateway Lifecycle
    'New-MCPCompositeGateway',
    'Start-MCPCompositeGateway',
    'Stop-MCPCompositeGateway',
    'Start-MCPGateway',
    'Stop-MCPGateway',
    'Get-MCPCompositeGatewayStatus',
    
    # Pack Route Management
    'Add-MCPPackRoute',
    'Remove-MCPPackRoute',
    'Register-MCPPackRoute',
    'Unregister-MCPPackRoute',
    'Get-MCPPackRoutes',
    'Get-MCPPackRoute',
    'Route-MCPRequest',
    
    # Request Routing and Gateway Operations
    'Invoke-MCPGatewayRequest',
    'Invoke-MCPPackRoute',
    'Get-MCPGatewayManifest',
    'Get-MCPAggregatedTools',
    'Test-MCPGatewayHealth',
    'Resolve-MCPToolTarget',
    'Process-MCPGatewayRequest',
    
    # Cross-Pack Operations
    'Invoke-MCPCrossPackQuery',
    'Invoke-MCPAggregatedTool',
    'Get-MCPCrossPackEvidence',
    'New-MCPCrossPackContext',
    
    # Blenderâ†’Godot Pipeline
    'Invoke-MCPBlenderToGodotExport',
    'Get-MCPPipelineStatus',
    'Register-MCPPipelineStep',
    
    # Session Management
    'New-MCPSession',
    'Get-MCPSession',
    'Remove-MCPSession',
    'Update-SessionContext',
    
    # Circuit Breaker Functions
    'Test-MCPCircuitBreaker',
    'Record-MCPSuccess',
    'Record-MCPFailure',
    'Reset-MCPCircuitBreaker',
    
    # Rate Limiting Functions
    'Test-MCPRateLimit',
    'Get-MCPRateLimitStatus'
)
