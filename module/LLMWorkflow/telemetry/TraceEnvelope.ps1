#requires -Version 5.1
<#
.SYNOPSIS
    Trace envelope schema and operations for OpenTelemetry-compatible spans.
.DESCRIPTION
    Defines the trace envelope structure and provides functions to create,
    modify, and finalize envelopes. Envelopes encapsulate span data in a
    serialization-friendly format for export to collectors.
.NOTES
    File Name      : TraceEnvelope.ps1
    Author         : LLM Workflow Team
    Prerequisite   : PowerShell 5.1+
    Copyright      : (c) 2026 LLM Workflow Project
    License        : MIT
#>

Set-StrictMode -Version Latest

<#
.SYNOPSIS
    Creates a new trace envelope from a span or raw parameters.
.DESCRIPTION
    Constructs a trace envelope containing traceId, spanId, parentSpanId,
    name, timestamps, attributes, events, status, and an optional correlation ID.
    If a span object is provided, its properties are used directly.
.PARAMETER Span
    Optional. A span object created by SpanFactory to seed the envelope.
.PARAMETER TraceId
    Optional. The trace ID. Required if Span is not provided.
.PARAMETER SpanId
    Optional. The span ID. Required if Span is not provided.
.PARAMETER Name
    Optional. The span name. Required if Span is not provided.
.PARAMETER ParentSpanId
    Optional. The parent span ID.
.PARAMETER StartTime
    Optional. The ISO 8601 start timestamp.
.PARAMETER EndTime
    Optional. The ISO 8601 end timestamp.
.PARAMETER Attributes
    Optional. Hashtable of span attributes.
.PARAMETER Events
    Optional. Array of event objects.
.PARAMETER Status
    Optional. The span status. Defaults to UNSET.
.PARAMETER CorrelationId
    Optional. A correlation ID for cross-boundary linking.
.OUTPUTS
    System.Management.Automation.PSCustomObject representing the trace envelope.
.EXAMPLE
    PS C:\> $envelope = New-TraceEnvelope -Span $span
    
    Creates an envelope from an existing span object.
.EXAMPLE
    PS C:\> $envelope = New-TraceEnvelope -TraceId "abc..." -SpanId "def..." -Name "Query"
    
    Creates an envelope from raw parameters.
#>
function New-TraceEnvelope {
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(ParameterSetName = 'FromSpan')]
        [pscustomobject]$Span,

        [Parameter(ParameterSetName = 'FromParameters', Mandatory = $true)]
        [string]$TraceId,

        [Parameter(ParameterSetName = 'FromParameters', Mandatory = $true)]
        [string]$SpanId,

        [Parameter(ParameterSetName = 'FromParameters', Mandatory = $true)]
        [string]$Name,

        [Parameter(ParameterSetName = 'FromParameters')]
        [string]$ParentSpanId = "",

        [Parameter(ParameterSetName = 'FromParameters')]
        [string]$StartTime = "",

        [Parameter(ParameterSetName = 'FromParameters')]
        [string]$EndTime = "",

        [Parameter(ParameterSetName = 'FromParameters')]
        [hashtable]$Attributes = @{},

        [Parameter(ParameterSetName = 'FromParameters')]
        [array]$Events = @(),

        [Parameter(ParameterSetName = 'FromParameters')]
        [ValidateSet('UNSET', 'OK', 'ERROR')]
        [string]$Status = 'UNSET',

        [Parameter(ParameterSetName = 'FromParameters')]
        [string]$CorrelationId = ""
    )

    if ($PSCmdlet.ParameterSetName -eq 'FromSpan') {
        if (-not $Span) {
            throw "Span parameter cannot be null when using FromSpan parameter set."
        }

        $envelope = [pscustomobject][ordered]@{
            traceId       = $Span.traceId
            spanId        = $Span.spanId
            parentSpanId  = if ($Span.parentSpanId) { $Span.parentSpanId } else { $null }
            name          = $Span.name
            startTime     = if ($Span.startTime) { $Span.startTime } else { $null }
            endTime       = if ($Span.endTime) { $Span.endTime } else { $null }
            attributes    = if ($Span.attributes) { $Span.attributes.Clone() } else { @{} }
            events        = if ($Span.events) { @($Span.events) } else { New-Object System.Collections.ArrayList }
            status        = $Span.status
            correlationId = if ($Span.correlationId) { $Span.correlationId } else { $null }
            schemaVersion = 1
            isClosed      = $false
        }
    }
    else {
        $envelope = [pscustomobject][ordered]@{
            traceId       = $TraceId
            spanId        = $SpanId
            parentSpanId  = if ($ParentSpanId) { $ParentSpanId } else { $null }
            name          = $Name
            startTime     = if ($StartTime) { $StartTime } else { $null }
            endTime       = if ($EndTime) { $EndTime } else { $null }
            attributes    = if ($Attributes) { $Attributes.Clone() } else { @{} }
            events        = if ($Events) { @($Events) } else { New-Object System.Collections.ArrayList }
            status        = $Status
            correlationId = if ($CorrelationId) { $CorrelationId } else { $null }
            schemaVersion = 1
            isClosed      = $false
        }
    }

    Write-Verbose "[TraceEnvelope] Created envelope for span '$($envelope.name)' ($($envelope.spanId))"
    return $envelope
}

<#
.SYNOPSIS
    Adds an event to a trace envelope.
.DESCRIPTION
    Appends a structured event to the envelope's event array without
    modifying the underlying span. Useful for enriching an envelope
    before export.
.PARAMETER Envelope
    The trace envelope to modify.
.PARAMETER Name
    The event name.
.PARAMETER Timestamp
    Optional. The event timestamp. Defaults to UTC now.
.PARAMETER Attributes
    Optional. Hashtable of event-specific attributes.
.OUTPUTS
    System.Management.Automation.PSCustomObject. The updated envelope.
.EXAMPLE
    PS C:\> $envelope | Add-TraceEvent -Name "evaluation.scored" -Attributes @{ score = 0.94 }
    
    Adds an evaluation scored event to the envelope.
#>
function Add-TraceEvent {
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory = $true, ValueFromPipeline = $true)]
        [pscustomobject]$Envelope,

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
            name         = $Name
            timeUnixNano = ([DateTimeOffset]$Timestamp).ToUnixTimeMilliseconds() * 1000000
            attributes   = if ($Attributes) { $Attributes.Clone() } else { @{} }
        }

        $Envelope.events += $eventItem
        Write-Verbose "[TraceEnvelope] Added event '$Name' to envelope '$($Envelope.name)'"
        return $Envelope
    }
}

<#
.SYNOPSIS
    Closes a trace envelope, finalizing its state.
.DESCRIPTION
    Sets the end time to the current UTC time if not already set,
    updates the status, and marks the envelope as closed. Closed
    envelopes are ready for serialization and export.
.PARAMETER Envelope
    The trace envelope to close.
.PARAMETER Status
    Optional. The final status. Defaults to OK.
.OUTPUTS
    System.Management.Automation.PSCustomObject. The updated envelope.
.EXAMPLE
    PS C:\> $envelope | Close-TraceEnvelope -Status OK
    
    Finalizes the envelope with an OK status.
#>
function Close-TraceEnvelope {
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory = $true, ValueFromPipeline = $true)]
        [pscustomobject]$Envelope,

        [Parameter()]
        [ValidateSet('UNSET', 'OK', 'ERROR')]
        [string]$Status = 'OK'
    )

    process {
        if ($Envelope.isClosed) {
            Write-Verbose "[TraceEnvelope] Envelope '$($Envelope.name)' is already closed."
            return $Envelope
        }

        if ([string]::IsNullOrEmpty($Envelope.endTime)) {
            $Envelope.endTime = [DateTime]::UtcNow.ToString("yyyy-MM-ddTHH:mm:ss.fffffffZ", [System.Globalization.CultureInfo]::InvariantCulture)
        }

        $Envelope.status = $Status
        $Envelope.isClosed = $true

        Write-Verbose "[TraceEnvelope] Closed envelope '$($Envelope.name)' at $($Envelope.endTime) with status $Status"
        return $Envelope
    }
}

if ($ExecutionContext.SessionState.Module) {
    Export-ModuleMember -Function @(
    'New-TraceEnvelope',
    'Add-TraceEvent',
    'Close-TraceEnvelope'
)
}
