#requires -Version 5.1
<#
.SYNOPSIS
    Span factory for OpenTelemetry-compatible trace generation.
.DESCRIPTION
    Provides functions to create, manage, and manipulate trace spans
    with valid W3C trace context identifiers. Supports attribute and
    event attachment, lifecycle management, and correlation ID propagation.
.NOTES
    File Name      : SpanFactory.ps1
    Author         : LLM Workflow Team
    Prerequisite   : PowerShell 5.1+
    Copyright      : (c) 2026 LLM Workflow Project
    License        : MIT
#>

Set-StrictMode -Version Latest

<#
.SYNOPSIS
    Generates a new 32-character hexadecimal trace ID.
.DESCRIPTION
    Creates a cryptographically secure 128-bit trace ID
    formatted as a 32-character lowercase hexadecimal string.
.OUTPUTS
    System.String. A 32-character hex trace ID.
.EXAMPLE
    PS C:\> New-TraceId
    4bf92f3577b34da6a3ce929d0e0e4736
#>
function New-TraceId {
    [CmdletBinding()]
    [OutputType([string])]
    param()

    $bytes = New-Object byte[] 16
    try {
        $rng = [System.Security.Cryptography.RandomNumberGenerator]::Create()
        $rng.GetBytes($bytes)
    }
    catch {
        # Fallback for environments without crypto RNG
        for ($i = 0; $i -lt 16; $i++) {
            $bytes[$i] = [byte](Get-Random -Minimum 0 -Maximum 256)
        }
    }

    $sb = New-Object System.Text.StringBuilder 32
    foreach ($b in $bytes) {
        [void]$sb.Append($b.ToString("x2"))
    }

    return $sb.ToString()
}

<#
.SYNOPSIS
    Generates a new 16-character hexadecimal span ID.
.DESCRIPTION
    Creates a cryptographically secure 64-bit span ID
    formatted as a 16-character lowercase hexadecimal string.
.OUTPUTS
    System.String. A 16-character hex span ID.
.EXAMPLE
    PS C:\> New-SpanId
    00f067aa0ba902b7
#>
function New-SpanId {
    [CmdletBinding()]
    [OutputType([string])]
    param()

    $bytes = New-Object byte[] 8
    try {
        $rng = [System.Security.Cryptography.RandomNumberGenerator]::Create()
        $rng.GetBytes($bytes)
    }
    catch {
        for ($i = 0; $i -lt 8; $i++) {
            $bytes[$i] = [byte](Get-Random -Minimum 0 -Maximum 256)
        }
    }

    $sb = New-Object System.Text.StringBuilder 16
    foreach ($b in $bytes) {
        [void]$sb.Append($b.ToString("x2"))
    }

    return $sb.ToString()
}

<#
.SYNOPSIS
    Creates a new span object.
.DESCRIPTION
    Initializes a span with a unique span ID, an optional trace ID,
    parent span ID, and name. The span is created in a non-started state.
.PARAMETER Name
    The operation name for the span.
.PARAMETER TraceId
    Optional. The trace ID to associate with this span. Defaults to a new trace ID.
.PARAMETER ParentSpanId
    Optional. The parent span ID for hierarchical traces.
.PARAMETER CorrelationId
    Optional. A correlation ID to link related operations across boundaries.
.PARAMETER Attributes
    Optional. Initial hashtable of span attributes.
.OUTPUTS
    System.Management.Automation.PSCustomObject representing the span.
.EXAMPLE
    PS C:\> $span = New-Span -Name "QueryRouter.Resolve"
    
    Creates a new span for the QueryRouter resolution operation.
#>
function New-Span {
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Name,

        [Parameter()]
        [string]$TraceId = "",

        [Parameter()]
        [string]$ParentSpanId = "",

        [Parameter()]
        [string]$CorrelationId = "",

        [Parameter()]
        [hashtable]$Attributes = @{}
    )

    if ([string]::IsNullOrEmpty($TraceId)) {
        $TraceId = New-TraceId
    }

    $span = [pscustomobject][ordered]@{
        traceId       = $TraceId
        spanId        = New-SpanId
        parentSpanId  = if ($ParentSpanId) { $ParentSpanId } else { $null }
        name          = $Name
        startTime     = $null
        endTime       = $null
        status        = "UNSET"
        attributes    = if ($Attributes) { $Attributes.Clone() } else { @{} }
        events        = @()
        correlationId = if ($CorrelationId) { $CorrelationId } else { $null }
        isStarted     = $false
        isStopped     = $false
    }

    Write-Verbose "[SpanFactory] Created span '$Name' ($($span.spanId)) in trace $TraceId"
    return $span
}

<#
.SYNOPSIS
    Starts a span, recording the start time.
.DESCRIPTION
    Sets the span start time to the current UTC time and marks
    the span as started. Throws if the span is already stopped.
.PARAMETER Span
    The span object to start.
.OUTPUTS
    System.Management.Automation.PSCustomObject. The updated span.
.EXAMPLE
    PS C:\> $span = New-Span -Name "QueryRouter.Resolve" | Start-Span
    
    Creates and starts a span in a pipeline.
#>
function Start-Span {
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory = $true, ValueFromPipeline = $true)]
        [pscustomobject]$Span
    )

    process {
        if ($Span.isStopped) {
            throw "Cannot start a span that has already been stopped."
        }

        $Span.startTime = [DateTime]::UtcNow.ToString("yyyy-MM-ddTHH:mm:ss.fffffffZ", [System.Globalization.CultureInfo]::InvariantCulture)
        $Span.isStarted = $true

        Write-Verbose "[SpanFactory] Started span '$($Span.name)' at $($Span.startTime)"
        return $Span
    }
}

<#
.SYNOPSIS
    Stops a span, recording the end time and optional status.
.DESCRIPTION
    Sets the span end time to the current UTC time, updates the
    status, and marks the span as stopped. Throws if the span is
    not started or already stopped.
.PARAMETER Span
    The span object to stop.
.PARAMETER Status
    Optional. The final status: UNSET, OK, or ERROR. Defaults to OK.
.OUTPUTS
    System.Management.Automation.PSCustomObject. The updated span.
.EXAMPLE
    PS C:\> $span = New-Span -Name "QueryRouter.Resolve" | Start-Span | Stop-Span
    
    Creates, starts, and stops a span.
#>
function Stop-Span {
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory = $true, ValueFromPipeline = $true)]
        [pscustomobject]$Span,

        [Parameter()]
        [ValidateSet('UNSET', 'OK', 'ERROR')]
        [string]$Status = 'OK'
    )

    process {
        if (-not $Span.isStarted) {
            throw "Cannot stop a span that has not been started."
        }

        if ($Span.isStopped) {
            throw "Cannot stop a span that has already been stopped."
        }

        $Span.endTime = [DateTime]::UtcNow.ToString("yyyy-MM-ddTHH:mm:ss.fffffffZ", [System.Globalization.CultureInfo]::InvariantCulture)
        $Span.status = $Status
        $Span.isStopped = $true

        Write-Verbose "[SpanFactory] Stopped span '$($Span.name)' at $($Span.endTime) with status $Status"
        return $Span
    }
}

<#
.SYNOPSIS
    Adds an attribute to a span.
.DESCRIPTION
    Inserts or updates a key-value pair in the span's attribute hashtable.
    Supports string, numeric, and boolean values.
.PARAMETER Span
    The span object to modify.
.PARAMETER Key
    The attribute key.
.PARAMETER Value
    The attribute value.
.OUTPUTS
    System.Management.Automation.PSCustomObject. The updated span.
.EXAMPLE
    PS C:\> $span | Add-SpanAttribute -Key "router.strategy" -Value "authority"
    
    Adds a router strategy attribute to the span.
#>
function Add-SpanAttribute {
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory = $true, ValueFromPipeline = $true)]
        [pscustomobject]$Span,

        [Parameter(Mandatory = $true)]
        [string]$Key,

        [Parameter(Mandatory = $true)]
        [object]$Value
    )

    process {
        if ([string]::IsNullOrEmpty($Key)) {
            throw "Attribute key cannot be null or empty."
        }

        $Span.attributes[$Key] = $Value
        Write-Verbose "[SpanFactory] Added attribute '$Key' to span '$($Span.name)'"
        return $Span
    }
}

<#
.SYNOPSIS
    Adds a timed event to a span.
.DESCRIPTION
    Appends an event with a name, optional timestamp, and attributes
    to the span's event collection. Useful for marking milestones
    within a long-running operation.
.PARAMETER Span
    The span object to modify.
.PARAMETER Name
    The event name.
.PARAMETER Timestamp
    Optional. The event timestamp. Defaults to UTC now.
.PARAMETER Attributes
    Optional. Hashtable of event-specific attributes.
.OUTPUTS
    System.Management.Automation.PSCustomObject. The updated span.
.EXAMPLE
    PS C:\> $span | Add-SpanEvent -Name "cache.hit" -Attributes @{ "cache.key" = "pack-rpgmz-001" }
    
    Records a cache hit event on the span.
#>
function Add-SpanEvent {
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory = $true, ValueFromPipeline = $true)]
        [pscustomobject]$Span,

        [Parameter(Mandatory = $true)]
        [string]$Name,

        [Parameter()]
        [DateTime]$Timestamp = [DateTime]::UtcNow,

        [Parameter()]
        [hashtable]$Attributes = @{}
    )

    process {
        if ([string]::IsNullOrEmpty($Name)) {
            throw "Event name cannot be null or empty."
        }

        $eventItem = [pscustomobject][ordered]@{
            name       = $Name
            timeUnixNano = ([DateTimeOffset]$Timestamp).ToUnixTimeMilliseconds() * 1000000
            attributes = if ($Attributes) { $Attributes.Clone() } else { @{} }
        }

        $Span.events += $eventItem
        Write-Verbose "[SpanFactory] Added event '$Name' to span '$($Span.name)'"
        return $Span
    }
}

if ($ExecutionContext.SessionState.Module) {
    Export-ModuleMember -Function @(
    'New-TraceId',
    'New-SpanId',
    'New-Span',
    'Start-Span',
    'Stop-Span',
    'Add-SpanAttribute',
    'Add-SpanEvent'
)
}
