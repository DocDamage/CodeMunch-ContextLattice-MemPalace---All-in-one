#requires -Version 5.1
<#
.SYNOPSIS
    OpenTelemetry bridge for HTTP-based span export.
.DESCRIPTION
    Provides functions to initialize trace contexts and send spans
    to an OpenTelemetry Collector via HTTP POST. Supports single-span
    and batch export, correlation ID propagation, and safe degradation
    on network or serialization failures.
.NOTES
    File Name      : OpenTelemetryBridge.ps1
    Author         : LLM Workflow Team
    Prerequisite   : PowerShell 5.1+
    Copyright      : (c) 2026 LLM Workflow Project
    License        : MIT
#>

Set-StrictMode -Version Latest

# Default collector endpoint
$script:DefaultCollectorEndpoint = "http://localhost:4318/v1/traces"

<#
.SYNOPSIS
    Creates a new OpenTelemetry trace context.
.DESCRIPTION
    Initializes a trace context with a trace ID, an optional parent span ID,
    and a correlation ID. The context can be passed to downstream functions
    to ensure consistent trace propagation.
.PARAMETER TraceId
    Optional. A pre-existing trace ID. If omitted, a new 32-char hex trace ID is generated.
.PARAMETER ParentSpanId
    Optional. The parent span ID for nested trace propagation.
.PARAMETER CorrelationId
    Optional. A correlation ID to link related operations.
.PARAMETER Attributes
    Optional. Base attributes to include in every span sent from this context.
.OUTPUTS
    System.Management.Automation.PSCustomObject representing the trace context.
.EXAMPLE
    PS C:\> $ctx = New-OTelTrace -CorrelationId "run-20260413-001"
    
    Creates a trace context with a correlation ID.
#>
function New-OTelTrace {
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
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
        $traceIdCmd = Get-Command New-TraceId -ErrorAction SilentlyContinue
        if ($traceIdCmd) {
            $TraceId = & $traceIdCmd
        }
        else {
            # Fallback ID generation if SpanFactory is not loaded
            $bytes = New-Object byte[] 16
            try {
                $rng = [System.Security.Cryptography.RandomNumberGenerator]::Create()
                $rng.GetBytes($bytes)
            }
            catch {
                for ($i = 0; $i -lt 16; $i++) {
                    $bytes[$i] = [byte](Get-Random -Minimum 0 -Maximum 256)
                }
            }
            $sb = New-Object System.Text.StringBuilder 32
            foreach ($b in $bytes) {
                [void]$sb.Append($b.ToString("x2"))
            }
            $TraceId = $sb.ToString()
        }
    }

    $context = [pscustomobject][ordered]@{
        traceId       = $TraceId
        parentSpanId  = if ($ParentSpanId) { $ParentSpanId } else { $null }
        correlationId = if ($CorrelationId) { $CorrelationId } else { $null }
        attributes    = if ($Attributes) { $Attributes.Clone() } else { @{} }
        createdAt     = [DateTime]::UtcNow.ToString("yyyy-MM-ddTHH:mm:ss.fffffffZ", [System.Globalization.CultureInfo]::InvariantCulture)
    }

    Write-Verbose "[OpenTelemetryBridge] Created trace context $TraceId"
    return $context
}

<#
.SYNOPSIS
    Sends a single span to the OpenTelemetry Collector.
.DESCRIPTION
    Serializes a span or trace envelope into an OTLP-compatible JSON
    payload and POSTs it to the configured collector endpoint. On failure,
    writes a warning and returns a result object indicating success or failure.
.PARAMETER Span
    The span object or trace envelope to send.
.PARAMETER CollectorEndpoint
    Optional. The collector URL. Defaults to http://localhost:4318/v1/traces.
.PARAMETER TimeoutSeconds
    Optional. HTTP timeout in seconds. Defaults to 30.
.PARAMETER AdditionalHeaders
    Optional. Hashtable of extra HTTP headers to include.
.OUTPUTS
    System.Management.Automation.PSCustomObject with properties:
    - Success: Boolean
    - StatusCode: HTTP status code (or -1 on failure)
    - Error: Error message if any
.EXAMPLE
    PS C:\> Send-OTelSpan -Span $envelope
    
    Sends a single span to the local collector.
#>
function Send-OTelSpan {
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory = $true)]
        [pscustomobject]$Span,

        [Parameter()]
        [string]$CollectorEndpoint = $script:DefaultCollectorEndpoint,

        [Parameter()]
        [int]$TimeoutSeconds = 30,

        [Parameter()]
        [hashtable]$AdditionalHeaders = @{}
    )

    $result = [pscustomobject][ordered]@{
        Success    = $false
        StatusCode = -1
        Error      = $null
    }

    try {
        $payload = ConvertTo-OTelPayload -Span $Span
        $jsonBody = $payload | ConvertTo-Json -Compress -Depth 10

        $headers = @{
            'Content-Type' = 'application/json'
        }

        foreach ($key in $AdditionalHeaders.Keys) {
            $headers[$key] = $AdditionalHeaders[$key]
        }

        $response = Invoke-RestMethod -Uri $CollectorEndpoint -Method POST -Body $jsonBody -Headers $headers -TimeoutSec $TimeoutSeconds -UseBasicParsing

        $result.Success = $true
        $result.StatusCode = 200
        Write-Verbose "[OpenTelemetryBridge] Sent span '$($Span.name)' successfully"
    }
    catch [System.Net.WebException] {
        $result.Error = $_.Exception.Message
        if ($_.Exception.Response) {
            $result.StatusCode = [int]$_.Exception.Response.StatusCode
        }
        Write-Warning "[OpenTelemetryBridge] Failed to send span '$($Span.name)': $($result.Error)"
    }
    catch {
        $result.Error = $_.Exception.Message
        Write-Warning "[OpenTelemetryBridge] Failed to send span '$($Span.name)': $($result.Error)"
    }

    return $result
}

<#
.SYNOPSIS
    Exports a batch of spans to the OpenTelemetry Collector.
.DESCRIPTION
    Serializes multiple spans into a single OTLP-compatible JSON payload
    and POSTs it to the collector endpoint. Failed individual spans are
    logged but do not abort the entire batch.
.PARAMETER Spans
    An array of span objects or trace envelopes to export.
.PARAMETER CollectorEndpoint
    Optional. The collector URL. Defaults to http://localhost:4318/v1/traces.
.PARAMETER TimeoutSeconds
    Optional. HTTP timeout in seconds. Defaults to 30.
.PARAMETER AdditionalHeaders
    Optional. Hashtable of extra HTTP headers to include.
.OUTPUTS
    System.Management.Automation.PSCustomObject with properties:
    - Success: Boolean indicating overall batch acceptance
    - SentCount: Number of spans in the payload
    - StatusCode: HTTP status code (or -1 on failure)
    - Error: Error message if any
.EXAMPLE
    PS C:\> Export-OTelBatch -Spans @($span1, $span2, $span3)
    
    Exports a batch of three spans.
#>
function Export-OTelBatch {
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory = $true)]
        [array]$Spans,

        [Parameter()]
        [string]$CollectorEndpoint = $script:DefaultCollectorEndpoint,

        [Parameter()]
        [int]$TimeoutSeconds = 30,

        [Parameter()]
        [hashtable]$AdditionalHeaders = @{}
    )

    $result = [pscustomobject][ordered]@{
        Success    = $false
        SentCount  = 0
        StatusCode = -1
        Error      = $null
    }

    if (-not $Spans -or $Spans.Count -eq 0) {
        $result.Success = $true
        return $result
    }

    try {
        $otelSpans = @()
        foreach ($span in $Spans) {
            $otelSpans += ConvertTo-OTelSpanObject -Span $span
        }

        $payload = @{
            resourceSpans = @(
                @{
                    resource = @{
                        attributes = @(
                            @{
                                key   = "service.name"
                                value = @{
                                    stringValue = "llmworkflow"
                                }
                            }
                        )
                    }
                    scopeSpans = @(
                        @{
                            scope  = @{
                                name    = "llmworkflow.telemetry"
                                version = "1.0.0"
                            }
                            spans  = $otelSpans
                        }
                    )
                }
            )
        }

        $jsonBody = $payload | ConvertTo-Json -Compress -Depth 10

        $headers = @{
            'Content-Type' = 'application/json'
        }

        foreach ($key in $AdditionalHeaders.Keys) {
            $headers[$key] = $AdditionalHeaders[$key]
        }

        $response = Invoke-RestMethod -Uri $CollectorEndpoint -Method POST -Body $jsonBody -Headers $headers -TimeoutSec $TimeoutSeconds -UseBasicParsing

        $result.Success = $true
        $result.SentCount = $otelSpans.Count
        $result.StatusCode = 200
        Write-Verbose "[OpenTelemetryBridge] Exported batch of $($otelSpans.Count) spans successfully"
    }
    catch [System.Net.WebException] {
        $result.Error = $_.Exception.Message
        if ($_.Exception.Response) {
            $result.StatusCode = [int]$_.Exception.Response.StatusCode
        }
        Write-Warning "[OpenTelemetryBridge] Failed to export batch: $($result.Error)"
    }
    catch {
        $result.Error = $_.Exception.Message
        Write-Warning "[OpenTelemetryBridge] Failed to export batch: $($result.Error)"
    }

    return $result
}

<#
.SYNOPSIS
    Helper that converts a span/envelope to a full OTLP payload wrapper.
.DESCRIPTION
    Internal helper used by Send-OTelSpan to wrap a single span in the
    resourceSpans structure expected by OTLP HTTP receivers.
.PARAMETER Span
    The span object or trace envelope to convert.
.OUTPUTS
    System.Collections.Hashtable representing the OTLP payload.
#>
function ConvertTo-OTelPayload {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [pscustomobject]$Span
    )

    $otelSpan = ConvertTo-OTelSpanObject -Span $Span

    return @{
        resourceSpans = @(
            @{
                resource = @{
                    attributes = @(
                        @{
                            key   = "service.name"
                            value = @{
                                stringValue = "llmworkflow"
                            }
                        }
                    )
                }
                scopeSpans = @(
                    @{
                        scope = @{
                            name    = "llmworkflow.telemetry"
                            version = "1.0.0"
                        }
                        spans = @($otelSpan)
                    }
                )
            }
        )
    }
}

<#
.SYNOPSIS
    Helper that converts a span/envelope to an OTLP span object.
.DESCRIPTION
    Internal helper that maps span/envelope properties to the OTLP
    JSON field names and types. Handles attribute conversion,
    event conversion, and timestamp formatting.
.PARAMETER Span
    The span object or trace envelope to convert.
.OUTPUTS
    System.Collections.Hashtable representing the OTLP span.
#>
function ConvertTo-OTelSpanObject {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [pscustomobject]$Span
    )

    $otelSpan = @{
        traceId           = $Span.traceId
        spanId            = $Span.spanId
        name              = $Span.name
        kind              = 1  # SPAN_KIND_INTERNAL
        startTimeUnixNano = ConvertTo-UnixTimeNano -IsoString $Span.startTime
    }

    if ($Span.parentSpanId) {
        $otelSpan['parentSpanId'] = $Span.parentSpanId
    }

    if ($Span.endTime) {
        $otelSpan['endTimeUnixNano'] = ConvertTo-UnixTimeNano -IsoString $Span.endTime
    }

    if ($Span.status) {
        $code = 0
        if ($Span.status -eq 'OK') { $code = 1 }
        if ($Span.status -eq 'ERROR') { $code = 2 }
        $otelSpan['status'] = @{
            code = $code
        }
    }

    $otelSpan['attributes'] = ConvertTo-OTelAttributes -Attributes $Span.attributes

    if ($Span.events -and $Span.events.Count -gt 0) {
        $eventList = @()
        foreach ($evt in $Span.events) {
            $eventObj = @{
                name       = $evt.name
                timeUnixNano = $evt.timeUnixNano
                attributes = ConvertTo-OTelAttributes -Attributes $evt.attributes
            }
            $eventList += $eventObj
        }
        $otelSpan['events'] = $eventList
    }

    if ($Span.correlationId) {
        $otelSpan['attributes'] += @{
            key   = "correlation.id"
            value = @{ stringValue = $Span.correlationId }
        }
    }

    return $otelSpan
}

<#
.SYNOPSIS
    Helper that converts a hashtable to OTLP attribute key-value list.
.DESCRIPTION
    Maps PowerShell hashtable entries into the OTLP attribute array
    format with typed values (stringValue, intValue, boolValue).
.PARAMETER Attributes
    The hashtable of attributes to convert.
.OUTPUTS
    System.Array of OTLP attribute objects.
#>
function ConvertTo-OTelAttributes {
    [CmdletBinding()]
    param(
        [Parameter()]
        [hashtable]$Attributes = @{}
    )

    $attrList = @()
    if (-not $Attributes) {
        return ,[object[]]$attrList
    }

    foreach ($key in $Attributes.Keys) {
        $value = $Attributes[$key]
        $attrValue = @{}

        if ($value -is [bool]) {
            $attrValue['boolValue'] = $value
        }
        elseif ($value -is [int] -or $value -is [long] -or $value -is [double]) {
            $attrValue['doubleValue'] = [double]$value
        }
        else {
            $attrValue['stringValue'] = [string]$value
        }

        $attrList += @{
            key   = $key
            value = $attrValue
        }
    }

    return ,[object[]]$attrList
}

<#
.SYNOPSIS
    Helper that converts an ISO 8601 string to Unix nanoseconds.
.DESCRIPTION
    Parses the input string and returns nanoseconds since Unix epoch.
    Returns $null for empty or invalid strings.
.PARAMETER IsoString
    The ISO 8601 timestamp string.
.OUTPUTS
    System.Nullable[System.Int64]. Unix time in nanoseconds, or $null.
#>
function ConvertTo-UnixTimeNano {
    [CmdletBinding()]
    param(
        [Parameter()]
        [string]$IsoString = ""
    )

    if ([string]::IsNullOrEmpty($IsoString)) {
        return $null
    }

    try {
        $dt = [DateTime]::Parse($IsoString, [System.Globalization.CultureInfo]::InvariantCulture, [System.Globalization.DateTimeStyles]::RoundtripKind)
        $offset = New-Object DateTimeOffset $dt
        return $offset.ToUnixTimeMilliseconds() * 1000000
    }
    catch {
        Write-Verbose "[OpenTelemetryBridge] Failed to parse timestamp '$IsoString': $_"
        return $null
    }
}

if ($ExecutionContext.SessionState.Module) {
    Export-ModuleMember -Function @(
    'New-OTelTrace',
    'Send-OTelSpan',
    'Export-OTelBatch'
)
}
