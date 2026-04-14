#requires -Version 5.1
<#
.SYNOPSIS
    Centralized telemetry helpers for the LLM Workflow Platform.
.DESCRIPTION
    Provides standardized functions to record telemetry without duplicating
    logic across multiple domain scripts. Uses OpenTelemetryBridge and
    SpanFactory if available.
.NOTES
    File Name      : TelemetryHelpers.ps1
    Author         : LLM Workflow Team
    Prerequisite   : PowerShell 5.1+
    Copyright      : (c) 2026 LLM Workflow Project
    License        : MIT
#>

Set-StrictMode -Version Latest

# Global in-memory trace log for debugging/dashboarding
if (-not (Get-Variable -Name "TelemetryTraceLog" -Scope Script -ErrorAction SilentlyContinue)) {
    $script:TelemetryTraceLog = [System.Collections.ArrayList]::new()
}

<#
.SYNOPSIS
    Records telemetry for a function execution.
.DESCRIPTION
    Creates and starts a span for the given function name, attaches attributes,
    and immediately stops it with an OK status. This is a "shorthand" helper
    for instrumentation.
.PARAMETER CorrelationId
    The correlation ID for the trace.
.PARAMETER FunctionName
    The name of the function being instrumented.
.PARAMETER Attributes
    Optional hashtable of attributes to attach to the span.
.OUTPUTS
    The created span object or a basic telemetry entry.
#>
function Write-FunctionTelemetry {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$CorrelationId,

        [Parameter(Mandatory = $true)]
        [string]$FunctionName,

        [Parameter()]
        [hashtable]$Attributes = @{}
    )

    $newSpanCmd = Get-Command New-Span -ErrorAction SilentlyContinue
    $startSpanCmd = Get-Command Start-Span -ErrorAction SilentlyContinue
    $stopSpanCmd = Get-Command Stop-Span -ErrorAction SilentlyContinue

    $spanResult = $null

    if ($newSpanCmd -and $startSpanCmd -and $stopSpanCmd) {
        $spanResult = & $newSpanCmd -Name $FunctionName -CorrelationId $CorrelationId -Attributes $Attributes |
                      & $startSpanCmd |
                      & $stopSpanCmd -Status OK
        
        # Add to global log
        [void]$script:TelemetryTraceLog.Add($spanResult)
        
        Write-Verbose "[$FunctionName] OTel Span Recorded: $($spanResult.spanId)"
    }
    else {
        # Fallback to simple entry if OTel infrastructure is not loaded
        $spanResult = [pscustomobject][ordered]@{
            timestamp     = [DateTime]::UtcNow.ToString("yyyy-MM-ddTHH:mm:ss.fffffffZ")
            correlationId = $CorrelationId
            function      = $FunctionName
            attributes    = $Attributes
            type          = "SimpleTelemetry"
        }
        
        [void]$script:TelemetryTraceLog.Add($spanResult)
        Write-Verbose "[$FunctionName] Simple Telemetry Recorded (SpanFactory not found)"
    }

    return $spanResult
}

<#
.SYNOPSIS
    Clears the in-memory telemetry log.
#>
function Clear-TelemetryLog {
    $script:TelemetryTraceLog.Clear()
}

<#
.SYNOPSIS
    Returns the current in-memory telemetry log.
#>
function Get-TelemetryLog {
    return $script:TelemetryTraceLog
}

if ($ExecutionContext.SessionState.Module) {
    Export-ModuleMember -Function @(
        'Write-FunctionTelemetry',
        'Clear-TelemetryLog',
        'Get-TelemetryLog'
    )
}
