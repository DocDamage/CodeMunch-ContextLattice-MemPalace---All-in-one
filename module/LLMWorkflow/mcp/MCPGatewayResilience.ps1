#requires -Version 5.1
Set-StrictMode -Version Latest

#>
function Test-MCPGatewayHealth {
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter()]
        [string]$PackId = '',

        [Parameter()]
        [string]$CorrelationId = '',

        [Parameter()]
        [switch]$UpdateRouteStatus
    )

    begin {
        Ensure-GatewayRunning

        if ([string]::IsNullOrEmpty($CorrelationId)) {
            $CorrelationId = [Guid]::NewGuid().ToString()
        }
    }

    process {
        $packHealthResults = @()
        $healthyCount = 0
        $unhealthyCount = 0
        $unknownCount = 0

        $routesToCheck = if ($PackId) {
            @($script:GatewayState.routes[$PackId]) | Where-Object { $_ -ne $null }
        }
        else {
            $script:GatewayState.routes.Values
        }

        foreach ($route in $routesToCheck) {
            $healthResult = _Test-PackHealth -Route $route -CorrelationId $CorrelationId

            switch ($healthResult.status) {
                'healthy' { $healthyCount++ }
                'unhealthy' { $unhealthyCount++ }
                default { $unknownCount++ }
            }

            $packHealthResults += $healthResult

            # Update route status if requested
            if ($UpdateRouteStatus) {
                if ($healthResult.status -eq 'healthy') {
                    $route.enabled = $true
                }
                elseif ($healthResult.status -eq 'unhealthy') {
                    $route.enabled = $false
                }
                $route.healthStatus = $healthResult.status
                $route.lastHealthCheck = [DateTime]::UtcNow.ToString("o")
            }
        }

        $overallHealth = if ($unhealthyCount -eq 0 -and $healthyCount -gt 0) { 'healthy' }
                        elseif ($healthyCount -eq 0) { 'unhealthy' }
                        else { 'degraded' }

        Write-GatewayStructuredLog -Level INFO -Message "Gateway health check completed" -CorrelationId $CorrelationId -Metadata @{
            overallHealth = $overallHealth
            healthyPacks = $healthyCount
            unhealthyPacks = $unhealthyCount
            unknownPacks = $unknownCount
            totalPacks = ($routesToCheck | Measure-Object).Count
        }

        return [PSCustomObject]@{
            jsonrpc = "2.0"
            result = @{
                overallHealth = $overallHealth
                gatewayId = $script:GatewayState.gatewayId
                isRunning = $script:GatewayState.isRunning
                uptime = if ($script:GatewayState.startedAt) { ([DateTime]::UtcNow - $script:GatewayState.startedAt).ToString() } else { $null }
                packs = $packHealthResults
                summary = @{
                    total = ($routesToCheck | Measure-Object).Count
                    healthy = $healthyCount
                    unhealthy = $unhealthyCount
                    unknown = $unknownCount
                }
                timestamp = [DateTime]::UtcNow.ToString("o")
            }
            id = $CorrelationId
            correlationId = $CorrelationId
        }
    }
}


#>
function Test-MCPCircuitBreaker {
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory = $true)]
        [string]$PackId
    )

    begin {
        Ensure-GatewayRunning
    }

    process {
        $result = Test-CircuitBreaker -PackId $PackId

        return [PSCustomObject]@{
            packId = $PackId
            allowed = $result.allowed
            state = $result.state
            timestamp = [DateTime]::UtcNow.ToString("o")
        }
    }
}


#>
function Record-MCPSuccess {
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory = $true)]
        [string]$PackId
    )

    begin {
        Ensure-GatewayRunning
    }

    process {
        if (-not $script:GatewayState.circuitBreakers.ContainsKey($PackId)) {
            return [PSCustomObject]@{
                packId = $PackId
                success = $false
                error = "No circuit breaker found for pack"
            }
        }

        $previousState = $script:GatewayState.circuitBreakers[$PackId].state
        Record-CircuitBreakerSuccess -PackId $PackId
        $currentState = $script:GatewayState.circuitBreakers[$PackId].state

        $cb = $script:GatewayState.circuitBreakers[$PackId]

        return [PSCustomObject]@{
            packId = $PackId
            success = $true
            previousState = $previousState
            currentState = $currentState
            stateChanged = ($previousState -ne $currentState)
            successCount = $cb.successCount
            timestamp = [DateTime]::UtcNow.ToString("o")
        }
    }
}


#>
function Record-MCPFailure {
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory = $true)]
        [string]$PackId,

        [Parameter()]
        [string]$ErrorMessage = ''
    )

    begin {
        Ensure-GatewayRunning
    }

    process {
        if (-not $script:GatewayState.circuitBreakers.ContainsKey($PackId)) {
            return [PSCustomObject]@{
                packId = $PackId
                success = $false
                error = "No circuit breaker found for pack"
            }
        }

        $previousState = $script:GatewayState.circuitBreakers[$PackId].state
        Record-CircuitBreakerFailure -PackId $PackId
        $currentState = $script:GatewayState.circuitBreakers[$PackId].state

        $cb = $script:GatewayState.circuitBreakers[$PackId]
        $config = $script:GatewayState.config

        return [PSCustomObject]@{
            packId = $PackId
            success = $true
            previousState = $previousState
            currentState = $currentState
            stateChanged = ($previousState -ne $currentState)
            failureCount = $cb.failureCount
            threshold = $config.circuitBreakerThreshold
            thresholdReached = ($cb.failureCount -ge $config.circuitBreakerThreshold)
            errorMessage = $ErrorMessage
            timestamp = [DateTime]::UtcNow.ToString("o")
        }
    }
}


#>
function Reset-MCPCircuitBreaker {
    [CmdletBinding()]
    [OutputType([pscustomobject])]
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
        if (-not $script:GatewayState.circuitBreakers.ContainsKey($PackId)) {
            return [PSCustomObject]@{
                packId = $PackId
                success = $false
                error = "No circuit breaker found for pack"
            }
        }

        $cb = $script:GatewayState.circuitBreakers[$PackId]
        $previousState = $cb.state

        # Reset to closed state
        $cb.state = $script:CircuitBreakerStates.CLOSED
        $cb.failureCount = 0
        $cb.successCount = 0
        $cb.openedAt = $null
        $cb.lastFailureAt = $null

        Write-GatewayStructuredLog -Level INFO -Message "Circuit breaker manually reset" -Metadata @{
            packId = $PackId
            previousState = $previousState
            force = $Force.IsPresent
        }

        return [PSCustomObject]@{
            packId = $PackId
            success = $true
            previousState = $previousState
            currentState = $cb.state
            resetAt = [DateTime]::UtcNow.ToString("o")
        }
    }
}


#>
function Test-MCPRateLimit {
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory = $true)]
        [string]$PackId,

        [Parameter()]
        [switch]$ConsumeToken
    )

    begin {
        Ensure-GatewayRunning
    }

    process {
        if (-not $script:GatewayState.rateLimiters.ContainsKey($PackId)) {
            return [PSCustomObject]@{
                packId = $PackId
                allowed = $true
                reason = "No rate limiter configured"
                timestamp = [DateTime]::UtcNow.ToString("o")
            }
        }

        $limiter = $script:GatewayState.rateLimiters[$PackId]
        $route = $script:GatewayState.routes[$PackId]
        $now = [DateTime]::UtcNow

        # Refill tokens based on elapsed time (token bucket algorithm)
        $timeSinceRefill = ($now - $limiter.lastRefill).TotalSeconds
        $tokensToAdd = [Math]::Floor($timeSinceRefill * ($route.rateLimit / 60))

        if ($tokensToAdd -gt 0) {
            $limiter.tokens = [Math]::Min($route.rateLimit, $limiter.tokens + $tokensToAdd)
            $limiter.lastRefill = $now
        }

        $allowed = $limiter.tokens -gt 0
        $retryAfter = 0

        if (-not $allowed) {
            $secondsPerToken = 60.0 / $route.rateLimit
            $retryAfter = [Math]::Ceiling($secondsPerToken - ($now - $limiter.lastRefill).TotalSeconds)
            $retryAfter = [Math]::Max(1, $retryAfter)
        }
        elseif ($ConsumeToken) {
            $limiter.tokens--
            $limiter.requestCount++
        }

        return [PSCustomObject]@{
            packId = $PackId
            allowed = $allowed
            remainingTokens = $limiter.tokens
            rateLimit = $route.rateLimit
            retryAfter = $retryAfter
            consumed = $ConsumeToken.IsPresent
            timestamp = [DateTime]::UtcNow.ToString("o")
        }
    }
}


#>
function Get-MCPRateLimitStatus {
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter()]
        [string]$PackId = ''
    )

    begin {
        Ensure-GatewayRunning
    }

    process {
        $packIds = if ($PackId) { @($PackId) } else { @($script:GatewayState.rateLimiters.Keys) }
        $results = @()

        foreach ($id in $packIds) {
            if (-not $script:GatewayState.rateLimiters.ContainsKey($id)) {
                continue
            }

            $limiter = $script:GatewayState.rateLimiters[$id]
            $route = $script:GatewayState.routes[$id]
            $now = [DateTime]::UtcNow

            # Calculate refill rate
            $secondsPerToken = if ($route.rateLimit -gt 0) { 60.0 / $route.rateLimit } else { 0 }
            $timeUntilNextToken = $secondsPerToken - ($now - $limiter.lastRefill).TotalSeconds

            $results += [PSCustomObject]@{
                packId = $id
                allowed = $limiter.tokens -gt 0
                currentTokens = $limiter.tokens
                maxTokens = $route.rateLimit
                requestCount = $limiter.requestCount
                windowStart = $limiter.windowStart.ToString("o")
                lastRefill = $limiter.lastRefill.ToString("o")
                timeUntilNextTokenSeconds = [Math]::Max(0, [Math]::Round($timeUntilNextToken, 2))
                timestamp = [DateTime]::UtcNow.ToString("o")
            }
        }

        if ($PackId) {
            return $results | Select-Object -First 1
        }
        return $results
    }
}


#>
function _Test-RateLimit {
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory = $true)]
        [string]$PackId
    )

    if (-not $script:GatewayState.rateLimiters.ContainsKey($PackId)) {
        return @{ allowed = $true; retryAfter = 0 }
    }

    $limiter = $script:GatewayState.rateLimiters[$PackId]
    $route = $script:GatewayState.routes[$PackId]
    $now = [DateTime]::UtcNow

    # Refill tokens based on elapsed time (token bucket algorithm)
    $timeSinceRefill = ($now - $limiter.lastRefill).TotalSeconds
    $tokensToAdd = [Math]::Floor($timeSinceRefill * ($route.rateLimit / 60))

    if ($tokensToAdd -gt 0) {
        $limiter.tokens = [Math]::Min($route.rateLimit, $limiter.tokens + $tokensToAdd)
        $limiter.lastRefill = $now
    }

    # Check if request can proceed
    if ($limiter.tokens -gt 0) {
        $limiter.tokens--
        $limiter.requestCount++
        return @{ allowed = $true; retryAfter = 0 }
    }

    # Calculate retry after
    $secondsPerToken = 60.0 / $route.rateLimit
    $retryAfter = [Math]::Ceiling($secondsPerToken - ($now - $limiter.lastRefill).TotalSeconds)

    return @{ allowed = $false; retryAfter = [Math]::Max(1, $retryAfter) }
}


#>
function Initialize-RateLimiters {
    [CmdletBinding()]
    param()

    foreach ($packId in $script:GatewayState.routes.Keys) {
        $route = $script:GatewayState.routes[$packId]
        $script:GatewayState.rateLimiters[$packId] = @{
            tokens = $route.rateLimit
            lastRefill = [DateTime]::UtcNow
            windowStart = [DateTime]::UtcNow
            requestCount = 0
        }
    }
}


#>
function Initialize-CircuitBreaker {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$PackId
    )

    $script:GatewayState.circuitBreakers[$PackId] = @{
        state = $script:CircuitBreakerStates.CLOSED
        failureCount = 0
        successCount = 0
        lastFailureAt = $null
        lastSuccessAt = $null
        openedAt = $null
    }
}


#>
function Initialize-CircuitBreakers {
    [CmdletBinding()]
    param()

    foreach ($packId in $script:GatewayState.routes.Keys) {
        Initialize-CircuitBreaker -PackId $packId
    }
}


#>
function Test-CircuitBreaker {
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory = $true)]
        [string]$PackId
    )

    if (-not $script:GatewayState.circuitBreakers.ContainsKey($PackId)) {
        return @{ allowed = $true; state = $script:CircuitBreakerStates.CLOSED }
    }

    $cb = $script:GatewayState.circuitBreakers[$PackId]
    $config = $script:GatewayState.config

    switch ($cb.state) {
        $script:CircuitBreakerStates.CLOSED {
            return @{ allowed = $true; state = $cb.state }
        }
        $script:CircuitBreakerStates.OPEN {
            # Check if timeout has elapsed
            if ($cb.openedAt) {
                $elapsed = ([DateTime]::UtcNow - [DateTime]::Parse($cb.openedAt)).TotalSeconds
                if ($elapsed -ge $config.circuitBreakerTimeoutSeconds) {
                    # Transition to half-open
                    $cb.state = $script:CircuitBreakerStates.HALF_OPEN
                    $cb.failureCount = 0
                    return @{ allowed = $true; state = $cb.state }
                }
            }
            return @{ allowed = $false; state = $cb.state }
        }
        $script:CircuitBreakerStates.HALF_OPEN {
            # Allow limited requests to test recovery
            return @{ allowed = $true; state = $cb.state }
        }
        default {
            return @{ allowed = $true; state = $cb.state }
        }
    }
}


#>
function Record-CircuitBreakerSuccess {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$PackId
    )

    if (-not $script:GatewayState.circuitBreakers.ContainsKey($PackId)) {
        return
    }

    $cb = $script:GatewayState.circuitBreakers[$PackId]
    $cb.successCount++
    $cb.lastSuccessAt = [DateTime]::UtcNow.ToString("o")

    # If in half-open state, close the circuit
    if ($cb.state -eq $script:CircuitBreakerStates.HALF_OPEN) {
        $cb.state = $script:CircuitBreakerStates.CLOSED
        $cb.failureCount = 0
        Write-Verbose "Circuit breaker for '$PackId' closed after recovery"
    }
}


#>
function Record-CircuitBreakerFailure {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$PackId
    )

    if (-not $script:GatewayState.circuitBreakers.ContainsKey($PackId)) {
        return
    }

    $cb = $script:GatewayState.circuitBreakers[$PackId]
    $config = $script:GatewayState.config

    $cb.failureCount++
    $cb.lastFailureAt = [DateTime]::UtcNow.ToString("o")

    # Check if threshold reached
    if ($cb.state -eq $script:CircuitBreakerStates.CLOSED -and $cb.failureCount -ge $config.circuitBreakerThreshold) {
        $cb.state = $script:CircuitBreakerStates.OPEN
        $cb.openedAt = [DateTime]::UtcNow.ToString("o")
        Write-Verbose "Circuit breaker for '$PackId' opened after $($cb.failureCount) failures"
    }
    elseif ($cb.state -eq $script:CircuitBreakerStates.HALF_OPEN) {
        # Re-open immediately on failure in half-open state
        $cb.state = $script:CircuitBreakerStates.OPEN
        $cb.openedAt = [DateTime]::UtcNow.ToString("o")
        Write-Verbose "Circuit breaker for '$PackId' re-opened after failure in half-open state"
    }
}


#>
function _Test-PackHealth {
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory = $true)]
        [pscustomobject]$Route,

        [Parameter()]
        [string]$CorrelationId = ''
    )

    $startTime = [DateTime]::UtcNow
    $healthStatus = 'unknown'
    $error = $null
    $responseTime = 0

    try {
        if ($Route.endpoint -eq 'stdio') {
            # For stdio, check if process is available
            # Placeholder implementation
            $healthStatus = 'healthy'
        }
        elseif ($Route.endpoint.StartsWith('http')) {
            $uri = "$($Route.endpoint)$($Route.healthCheckPath)"
            $response = Invoke-RestMethod -Uri $uri -Method Get -TimeoutSec 5 -ErrorAction Stop
            $responseTime = ([DateTime]::UtcNow - $startTime).TotalMilliseconds
            $healthStatus = 'healthy'
        }
        else {
            $healthStatus = 'unknown'
        }
    }
    catch {
        $healthStatus = 'unhealthy'
        $error = $_.Exception.Message
        $responseTime = ([DateTime]::UtcNow - $startTime).TotalMilliseconds
    }

    return [PSCustomObject]@{
        packId = $Route.packId
        status = $healthStatus
        responseTimeMs = [Math]::Round($responseTime, 2)
        endpoint = $Route.endpoint
        checkedAt = [DateTime]::UtcNow.ToString("o")
        error = $error
    }
}


