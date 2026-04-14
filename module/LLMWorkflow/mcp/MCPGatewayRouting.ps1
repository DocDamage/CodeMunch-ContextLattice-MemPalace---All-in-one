#requires -Version 5.1
Set-StrictMode -Version Latest

#>
function Add-MCPPackRoute {
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory = $true)]
        [string]$PackId,

        [Parameter(Mandatory = $true)]
        [string]$Endpoint,

        [Parameter(Mandatory = $true)]
        [string]$ToolPrefix,

        [Parameter()]
        [int]$Priority = 1,

        [Parameter()]
        [bool]$Enabled = $true,

        [Parameter()]
        [int]$RateLimit = 0,

        [Parameter()]
        [string]$FallbackPackId = '',

        [Parameter()]
        [hashtable]$Metadata = @{}
    )

    begin {
        Ensure-GatewayRunning

        # Use default rate limit if not specified
        if ($RateLimit -eq 0) {
            $RateLimit = $script:GatewayState.config.defaultRateLimit
        }
    }

    process {
        # Validate prefix format
        $prefix = $ToolPrefix.ToLower()
        if (-not $prefix.EndsWith('_')) {
            $prefix = "$prefix`_"
        }

        $validPrefix = $false
        foreach ($valid in $script:ValidToolPrefixes) {
            if ($prefix.StartsWith($valid.TrimEnd('_'), [System.StringComparison]::OrdinalIgnoreCase)) {
                $validPrefix = $true
                break
            }
        }

        if (-not $validPrefix) {
            Write-Warning "Tool prefix '$prefix' does not match known pack prefixes. Known: $($script:ValidToolPrefixes -join ', ')"
        }

        # Check for duplicate pack ID
        if ($script:GatewayState.routes.ContainsKey($PackId)) {
            Write-Warning "Route for pack '$PackId' already exists. Updating configuration."
        }

        # Check for prefix conflict
        foreach ($existingRoute in $script:GatewayState.routes.Values) {
            if ($existingRoute.prefix -eq $prefix -and $existingRoute.packId -ne $PackId) {
                throw "Prefix '$prefix' is already registered by pack '$($existingRoute.packId)'"
            }
        }

        $correlationId = [Guid]::NewGuid().ToString()

        # Create route configuration
        $route = [PSCustomObject]@{
            packId = $PackId
            prefix = $prefix
            endpoint = $Endpoint
            priority = $Priority
            enabled = $Enabled
            rateLimit = $RateLimit
            fallbackPackId = if ([string]::IsNullOrEmpty($FallbackPackId)) { $null } else { $FallbackPackId }
            metadata = $Metadata
            registeredAt = [DateTime]::UtcNow.ToString("o")
            requestCount = 0
            lastRequestAt = $null
            healthStatus = 'unknown'
            lastHealthCheck = $null
        }

        # Register route
        $script:GatewayState.routes[$PackId] = $route

        # Initialize rate limiter
        $script:GatewayState.rateLimiters[$PackId] = @{
            tokens = $RateLimit
            lastRefill = [DateTime]::UtcNow
            windowStart = [DateTime]::UtcNow
            requestCount = 0
        }

        # Initialize circuit breaker
        Initialize-CircuitBreaker -PackId $PackId

        # Log registration
        Write-GatewayStructuredLog -Level INFO -Message "Pack route added" -CorrelationId $correlationId -Metadata @{
            packId = $PackId
            prefix = $prefix
            endpoint = $Endpoint
            priority = $Priority
        }

        return $route
    }
}


#>
function Remove-MCPPackRoute {
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [Parameter(Mandatory = $true)]
        [string]$PackId,

        [Parameter()]
        [switch]$Force
    )

    begin {
        Ensure-GatewayRunning
    }

    process {
        if (-not $script:GatewayState.routes.ContainsKey($PackId)) {
            Write-Warning "Route for pack '$PackId' not found."
            return $false
        }

        # Check for active sessions using this pack
        $activeSessions = $script:GatewayState.sessions.Values | Where-Object {
            $_.packContexts.ContainsKey($PackId) -and $_.isActive
        }

        if ($activeSessions -and -not $Force) {
            throw "Cannot remove pack '$PackId': Active sessions exist. Use -Force to override."
        }

        # Remove route
        $route = $script:GatewayState.routes[$PackId]
        $script:GatewayState.routes.Remove($PackId)
        $script:GatewayState.rateLimiters.Remove($PackId)
        $script:GatewayState.circuitBreakers.Remove($PackId)

        $correlationId = [Guid]::NewGuid().ToString()

        # Log removal
        Write-GatewayStructuredLog -Level INFO -Message "Pack route removed" -CorrelationId $correlationId -Metadata @{
            packId = $PackId
            prefix = $route.prefix
            force = $Force.IsPresent
            hadActiveSessions = ($activeSessions | Measure-Object).Count -gt 0
        }

        return $true
    }
}


#>
function Register-MCPPackRoute {
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory = $true)]
        [string]$PackId,

        [Parameter(Mandatory = $true)]
        [string]$Prefix,

        [Parameter()]
        [string]$Endpoint = 'stdio',

        [Parameter()]
        [bool]$Enabled = $true,

        [Parameter()]
        [int]$RateLimit = 100,

        [Parameter()]
        [string]$FallbackPackId = '',

        [Parameter()]
        [hashtable]$Metadata = @{}
    )

    process {
        $params = @{
            PackId = $PackId
            ToolPrefix = $Prefix
            Endpoint = $Endpoint
            Enabled = $Enabled
            RateLimit = $RateLimit
            Metadata = $Metadata
        }

        if ($FallbackPackId) {
            $params['FallbackPackId'] = $FallbackPackId
        }

        return Add-MCPPackRoute @params
    }
}


#>
function Unregister-MCPPackRoute {
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [Parameter(Mandatory = $true)]
        [string]$PackId,

        [Parameter()]
        [switch]$Force
    )

    process {
        return Remove-MCPPackRoute -PackId $PackId -Force:$Force
    }
}


#>
function Get-MCPPackRoutes {
    [CmdletBinding()]
    [OutputType([array])]
    param(
        [Parameter()]
        [switch]$EnabledOnly,

        [Parameter()]
        [string]$PackId = '*',

        [Parameter()]
        [switch]$IncludeHealth
    )

    begin {
        Ensure-GatewayRunning
    }

    process {
        $routes = $script:GatewayState.routes.Values

        if ($EnabledOnly) {
            $routes = $routes | Where-Object { $_.enabled }
        }

        if ($PackId -ne '*') {
            $routes = $routes | Where-Object { $_.packId -like $PackId }
        }

        # Add health status if requested
        if ($IncludeHealth) {
            $routes = $routes | ForEach-Object {
                $route = $_
                $cb = $script:GatewayState.circuitBreakers[$route.packId]
                if ($cb) {
                    $route | Add-Member -NotePropertyName 'circuitBreakerState' -NotePropertyValue $cb.state -Force
                }
                $route
            }
        }

        return @($routes | Sort-Object -Property packId)
    }
}


#>
function Get-MCPGatewayManifest {
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter()]
        [switch]$IncludeMetadata,

        [Parameter()]
        [string]$FilterPrefix = '*',

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
        $allTools = @()
        $enabledRoutes = $script:GatewayState.routes.Values | Where-Object { $_.enabled }

        foreach ($route in $enabledRoutes) {
            try {
                # Check circuit breaker before querying
                if ($script:GatewayState.config.enableCircuitBreaker) {
                    $cbResult = Test-CircuitBreaker -PackId $route.packId
                    if (-not $cbResult.allowed) {
                        Write-Verbose "Skipping manifest query for $($route.packId): Circuit breaker open"
                        continue
                    }
                }

                $tools = Get-ToolsFromPack -Route $route

                foreach ($tool in $tools) {
                    if ($FilterPrefix -ne '*' -and -not $tool.name.StartsWith($FilterPrefix, [System.StringComparison]::OrdinalIgnoreCase)) {
                        continue
                    }

                    $toolInfo = [PSCustomObject]@{
                        name = $tool.name
                        description = $tool.description
                        inputSchema = if ($tool.inputSchema) { $tool.inputSchema } else { @{ type = 'object'; properties = @{} } }
                        packId = $route.packId
                        prefix = $route.prefix
                    }

                    if ($IncludeMetadata) {
                        $toolInfo | Add-Member -NotePropertyName 'metadata' -NotePropertyValue $route.metadata -Force
                        $toolInfo | Add-Member -NotePropertyName 'routeEndpoint' -NotePropertyValue $route.endpoint -Force
                        $toolInfo | Add-Member -NotePropertyName 'packPriority' -NotePropertyValue $route.priority -Force
                    }

                    $allTools += $toolInfo
                }
            }
            catch {
                Write-Verbose "Failed to get tools from pack '$($route.packId)': $($_.Exception.Message)"
            }
        }

        Write-GatewayStructuredLog -Level INFO -Message "Gateway manifest generated" -CorrelationId $CorrelationId -Metadata @{
            toolCount = $allTools.Count
            packCount = ($enabledRoutes | Measure-Object).Count
            filterPrefix = $FilterPrefix
        }

        # Return as JSON-RPC 2.0 response
        return New-JsonRpcSuccessResponse -Id $CorrelationId -Result @{
            tools = $allTools
            total = $allTools.Count
            packs = @($enabledRoutes | ForEach-Object { $_.packId })
        } -CorrelationId $CorrelationId
    }
}


#>
function Get-MCPAggregatedTools {
    [CmdletBinding()]
    [OutputType([array])]
    param(
        [Parameter()]
        [switch]$IncludeMetadata,

        [Parameter()]
        [string]$FilterPrefix = '*'
    )

    process {
        $response = Get-MCPGatewayManifest -IncludeMetadata:$IncludeMetadata -FilterPrefix $FilterPrefix
        if ($response.result) {
            return $response.result.tools
        }
        return @()
    }
}


#>
function Get-MCPPackRoute {
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory = $true)]
        [string]$PackId,

        [Parameter()]
        [switch]$IncludeHealthStatus
    )

    begin {
        Ensure-GatewayRunning
    }

    process {
        if (-not $script:GatewayState.routes.ContainsKey($PackId)) {
            return $null
        }

        $route = $script:GatewayState.routes[$PackId]

        if ($IncludeHealthStatus) {
            $route = $route | Select-Object *
            $cb = $script:GatewayState.circuitBreakers[$PackId]
            if ($cb) {
                $route | Add-Member -NotePropertyName 'circuitBreakerState' -NotePropertyValue $cb.state -Force
                $route | Add-Member -NotePropertyName 'failureCount' -NotePropertyValue $cb.failureCount -Force
                $route | Add-Member -NotePropertyName 'lastFailureAt' -NotePropertyValue $cb.lastFailureAt -Force
            }
            $rl = $script:GatewayState.rateLimiters[$PackId]
            if ($rl) {
                $route | Add-Member -NotePropertyName 'currentTokens' -NotePropertyValue $rl.tokens -Force
                $route | Add-Member -NotePropertyName 'requestCount' -NotePropertyValue $rl.requestCount -Force
            }
        }

        return $route
    }
}


#>
function Route-MCPRequest {
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory = $true)]
        [hashtable]$Request,

        [Parameter()]
        [string]$SessionId = '',

        [Parameter()]
        [string]$CorrelationId = ''
    )

    process {
        return Invoke-MCPGatewayRequest -Request $Request -SessionId $SessionId -CorrelationId $CorrelationId -UseFallback
    }
}


#>
function Resolve-PackFromToolName {
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory = $true)]
        [string]$ToolName
    )

    $toolNameLower = $ToolName.ToLower()

    # Find matching route based on prefix
    $matchingRoutes = @()
    foreach ($route in $script:GatewayState.routes.Values) {
        if (-not $route.enabled) { continue }

        if ($toolNameLower.StartsWith($route.prefix)) {
            $matchingRoutes += $route
        }
    }

    if ($matchingRoutes.Count -eq 0) {
        return $null
    }

    # Apply load balancing strategy to select route
    $strategy = $script:GatewayState.config.loadBalancingStrategy
    
    switch ($strategy) {
        'priority' {
            # Select highest priority route
            return ($matchingRoutes | Sort-Object -Property priority -Descending | Select-Object -First 1).packId
        }
        'least-connections' {
            # For now, use request count as proxy for connections
            return ($matchingRoutes | Sort-Object -Property requestCount | Select-Object -First 1).packId
        }
        default {
            # Round-robin (default) - for single matching, just return it
            if ($matchingRoutes.Count -eq 1) {
                return $matchingRoutes[0].packId
            }
            # Otherwise, pick the one with least recent request
            return ($matchingRoutes | Sort-Object -Property lastRequestAt | Select-Object -First 1).packId
        }
    }
}


#>
function Get-FallbackPack {
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory = $true)]
        [string]$PackId
    )

    if (-not $script:GatewayState.routes.ContainsKey($PackId)) {
        return $null
    }

    $route = $script:GatewayState.routes[$PackId]
    $fallback = $route.fallbackPackId

    # Verify fallback exists and is enabled
    if ($fallback -and $script:GatewayState.routes.ContainsKey($fallback)) {
        $fallbackRoute = $script:GatewayState.routes[$fallback]
        if ($fallbackRoute.enabled) {
            # Check circuit breaker
            if ($script:GatewayState.config.enableCircuitBreaker) {
                $cbResult = Test-CircuitBreaker -PackId $fallback
                if ($cbResult.allowed) {
                    return $fallback
                }
            }
            else {
                return $fallback
            }
        }
    }

    return $null
}


#>
function Get-ToolsFromPack {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [pscustomobject]$Route
    )

    if ($Route.endpoint -eq 'stdio') {
        # Placeholder for stdio tool discovery
        # In real implementation, would query the pack process
        return @(
            @{ name = "$($Route.prefix)query"; description = "Query $Route.packId"; inputSchema = @{ type = 'object'; properties = @{} } }
            @{ name = "$($Route.prefix)get_evidence"; description = "Get evidence from $Route.packId"; inputSchema = @{ type = 'object'; properties = @{} } }
            @{ name = "$($Route.prefix)init_context"; description = "Initialize context in $Route.packId"; inputSchema = @{ type = 'object'; properties = @{} } }
            @{ name = "$($Route.prefix)cleanup_context"; description = "Cleanup context in $Route.packId"; inputSchema = @{ type = 'object'; properties = @{} } }
        )
    }
    elseif ($Route.endpoint.StartsWith('http')) {
        $uri = "$($Route.endpoint)/mcp/v1/tools"
        $response = Invoke-RestMethod -Uri $uri -Method Get -ErrorAction Stop
        return $response.tools
    }

    return @()
}


#>
function Get-CrossPackTargets {
    [CmdletBinding()]
    [OutputType([array])]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Query
    )

    $queryLower = $Query.ToLower()
    $targets = @()

    # Simple keyword-based detection
    $packKeywords = @{
        'godot-engine' = @('godot', 'gdscript', 'node', 'scene', 'signal')
        'blender-engine' = @('blender', 'bpy', 'mesh', 'material', 'animation')
        'rpgmaker-mz' = @('rpg maker', 'rmmz', 'plugin', 'event', 'notetag')
    }

    foreach ($packId in $packKeywords.Keys) {
        $route = $script:GatewayState.routes[$packId]
        if (-not $route -or -not $route.enabled) { continue }

        $keywords = $packKeywords[$packId]
        foreach ($keyword in $keywords) {
            if ($queryLower.Contains($keyword)) {
                $targets += $packId
                break
            }
        }
    }

    # If no specific packs matched, include all enabled packs
    if ($targets.Count -eq 0) {
        $targets = $script:GatewayState.routes.Values |
            Where-Object { $_.enabled } |
            Select-Object -ExpandProperty packId
    }

    return $targets | Select-Object -Unique
}


