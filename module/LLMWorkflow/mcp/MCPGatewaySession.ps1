#requires -Version 5.1
Set-StrictMode -Version Latest

#>
function New-MCPSession {
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter()]
        [hashtable]$ContextData = @{},

        [Parameter()]
        [int]$ExpiryMinutes = 30,

        [Parameter()]
        [hashtable]$Metadata = @{},

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
        $sessionId = [Guid]::NewGuid().ToString()
        $now = [DateTime]::UtcNow

        $session = [PSCustomObject]@{
            sessionId = $sessionId
            correlationId = $CorrelationId
            createdAt = $now.ToString("o")
            expiresAt = $now.AddMinutes($ExpiryMinutes).ToString("o")
            isActive = $true
            contextData = $ContextData
            packContexts = @{}  # packId -> pack-specific context
            metadata = $Metadata
            requestCount = 0
            lastActivityAt = $now.ToString("o")
        }

        $script:GatewayState.sessions[$sessionId] = $session

        Write-GatewayStructuredLog -Level INFO -Message "Session created" -CorrelationId $CorrelationId -Metadata @{
            sessionId = $sessionId
            expiresAt = $session.expiresAt
        }

        return $session
    }
}


#>
function Get-MCPSession {
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory = $true)]
        [string]$SessionId,

        [Parameter()]
        [switch]$IncludeInactive
    )

    begin {
        Ensure-GatewayRunning
    }

    process {
        if (-not $script:GatewayState.sessions.ContainsKey($SessionId)) {
            return $null
        }

        $session = $script:GatewayState.sessions[$SessionId]

        # Check if session has expired
        $expiresAt = [DateTime]::Parse($session.expiresAt)
        if ($expiresAt -lt [DateTime]::UtcNow -and -not $IncludeInactive) {
            return $null
        }

        # Update activity if active
        if ($session.isActive -and $expiresAt -ge [DateTime]::UtcNow) {
            $session.lastActivityAt = [DateTime]::UtcNow.ToString("o")
        }

        return $session
    }
}


#>
function Remove-MCPSession {
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [Parameter(Mandatory = $true)]
        [string]$SessionId,

        [Parameter()]
        [switch]$Force,

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
        if (-not $script:GatewayState.sessions.ContainsKey($SessionId)) {
            Write-Warning "Session '$SessionId' not found."
            return $false
        }

        $session = $script:GatewayState.sessions[$SessionId]

        # Notify packs to clean up their contexts
        $cleanupErrors = @()
        foreach ($packId in $session.packContexts.Keys) {
            $route = $script:GatewayState.routes[$packId]
            if (-not $route -or -not $route.enabled) {
                continue
            }

            try {
                $toolName = "$($route.prefix)cleanup_context"
                $arguments = @{
                    sessionId = $SessionId
                }
                Invoke-ToolAtEndpoint -Route $route -ToolName $toolName -Arguments $arguments -SessionId $SessionId -CorrelationId $CorrelationId | Out-Null
            }
            catch {
                $cleanupErrors += "Pack '$packId': $($_.Exception.Message)"
                if (-not $Force) {
                    throw "Failed to cleanup pack context for '$packId': $($_.Exception.Message)"
                }
            }
        }

        # Remove session
        $script:GatewayState.sessions.Remove($SessionId)

        Write-GatewayStructuredLog -Level INFO -Message "Session removed" -CorrelationId $CorrelationId -Metadata @{
            sessionId = $SessionId
            cleanupErrors = $cleanupErrors
            force = $Force.IsPresent
        }

        return $true
    }
}


#>
function Update-SessionContext {
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory = $true)]
        [string]$SessionId,

        [Parameter(Mandatory = $true)]
        [hashtable]$ContextData,

        [Parameter()]
        [bool]$Merge = $true,

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
        $session = Get-MCPSession -SessionId $SessionId
        if (-not $session) {
            throw "Session '$SessionId' not found or expired"
        }

        if ($Merge) {
            # Merge new context with existing
            foreach ($key in $ContextData.Keys) {
                $session.contextData[$key] = $ContextData[$key]
            }
        }
        else {
            # Replace entire context
            $session.contextData = $ContextData
        }

        # Update activity timestamp
        $session.lastActivityAt = [DateTime]::UtcNow.ToString("o")
        $session.requestCount++

        Write-GatewayStructuredLog -Level INFO -Message "Session context updated" -CorrelationId $CorrelationId -Metadata @{
            sessionId = $SessionId
            merge = $Merge
            contextKeys = @($ContextData.Keys)
        }

        return $session
    }
}


