#requires -Version 5.1
<#
.SYNOPSIS
    Structured logging functions for LLM Workflow.
.DESCRIPTION
    Provides JSON-lines structured logging with correlation IDs,
    redaction support, and safe degradation on write failures.
    
    Log files follow the format: .llm-workflow/logs/yyyy-MM-dd.jsonl
    Each log entry is a JSON object with standardized fields.
.NOTES
    File Name      : Logging.ps1
    Author         : LLM Workflow Team
    Prerequisite   : PowerShell 5.1+
    Copyright      : (c) 2026 LLM Workflow Project
    License        : MIT
#>

Set-StrictMode -Version Latest

# Default log directory relative to project root
$script:DefaultLogDirectory = ".llm-workflow/logs"

# Sensitive field patterns for automatic redaction
$script:SensitivePatterns = @(
    'password',
    'secret',
    'token',
    'api.?key',
    'credential',
    'auth',
    'private.?key',
    'connection.?string'
)

# Log levels in order of severity
$script:LogLevels = @{
    'VERBOSE'  = 0
    'DEBUG'    = 1
    'INFO'     = 2
    'WARN'     = 3
    'WARNING'  = 3
    'ERROR'    = 4
    'CRITICAL' = 5
    'FATAL'    = 5
}

<#
.SYNOPSIS
    Creates a new structured log entry object.
.DESCRIPTION
    Creates a log entry with all required fields for the structured
    logging format. Handles redaction of sensitive fields and
    ensures ASCII-safe output.
.PARAMETER Level
    The log level. Valid values: VERBOSE, DEBUG, INFO, WARN, ERROR, CRITICAL, FATAL.
.PARAMETER Message
    The log message. Should be ASCII-safe for cross-platform compatibility.
.PARAMETER RunId
    The run ID to associate with this log entry. Defaults to the current run ID.
.PARAMETER CorrelationId
    An optional correlation ID for tracing related operations across
    multiple runs or components.
.PARAMETER Source
    The source component or function that generated this log entry.
.PARAMETER Metadata
    Additional key-value pairs to include in the log entry.
.PARAMETER Exception
    An optional Exception object to include in the log entry.
.PARAMETER RedactFields
    Array of field name patterns to redact from the Metadata.
.OUTPUTS
    System.Management.Automation.PSCustomObject representing the log entry.
.EXAMPLE
    PS C:\> New-LogEntry -Level INFO -Message "Sync started" -RunId "20260411T210501Z-7f2c"
    
    Creates a basic INFO log entry.
.EXAMPLE
    PS C:\> New-LogEntry -Level ERROR -Message "Connection failed" -Exception $ex -Metadata @{server="db01"}
    
    Creates an ERROR log entry with exception details.
#>
function New-LogEntry {
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory = $true)]
        [ValidateSet('VERBOSE', 'DEBUG', 'INFO', 'WARN', 'WARNING', 'ERROR', 'CRITICAL', 'FATAL')]
        [string]$Level,
        
        [Parameter(Mandatory = $true)]
        [string]$Message,
        
        [Parameter()]
        [string]$RunId = "",
        
        [Parameter()]
        [string]$CorrelationId = "",
        
        [Parameter()]
        [string]$Source = "",
        
        [Parameter()]
        [hashtable]$Metadata = @{},
        
        [Parameter()]
        [System.Exception]$Exception = $null,
        
        [Parameter()]
        [string[]]$RedactFields = @()
    )
    
    # Normalize level
    $normalizedLevel = $Level.ToUpperInvariant()
    if ($normalizedLevel -eq 'WARNING') {
        $normalizedLevel = 'WARN'
    }
    
    # Get current run ID if not provided
    if ([string]::IsNullOrEmpty($RunId)) {
        try {
            # Try to get from RunId module if available
            $runIdCmd = Get-Command Get-CurrentRunId -ErrorAction SilentlyContinue
            if ($runIdCmd) {
                $RunId = & $runIdCmd -ErrorAction SilentlyContinue
            }
        }
        catch {
            $RunId = "unknown"
        }
        if ([string]::IsNullOrEmpty($RunId)) {
            $RunId = "unknown"
        }
    }
    
    # Get source if not provided
    if ([string]::IsNullOrEmpty($Source)) {
        $callStack = Get-PSCallStack
        if ($callStack.Count -gt 1) {
            $Source = $callStack[1].FunctionName
        }
        else {
            $Source = "script"
        }
    }
    
    # Sanitize message to ASCII-safe
    $safeMessage = ConvertTo-ASCIISafe -InputString $Message
    
    # Build log entry
    $entry = [ordered]@{
        timestamp    = [DateTime]::UtcNow.ToString("yyyy-MM-ddTHH:mm:ss.fffZ", [System.Globalization.CultureInfo]::InvariantCulture)
        level        = $normalizedLevel
        message      = $safeMessage
        runId        = $RunId
        correlationId = if ($CorrelationId) { $CorrelationId } else { $null }
        source       = $Source
        pid          = $PID
        machine      = $env:COMPUTERNAME
    }
    
    # Add metadata with redaction
    if ($Metadata -and $Metadata.Count -gt 0) {
        $sanitizedMetadata = @{}
        foreach ($key in $Metadata.Keys) {
            $value = $Metadata[$key]
            if (Should-Redact -FieldName $key -RedactPatterns $RedactFields) {
                $sanitizedMetadata[$key] = "[REDACTED]"
            }
            else {
                # Convert hashtables to strings for JSON serialization safety
                if ($value -is [hashtable]) {
                    $sanitizedMetadata[$key] = ($value | ConvertTo-Json -Compress -Depth 5)
                }
                elseif ($value -is [System.Collections.IEnumerable] -and $value -isnot [string]) {
                    $sanitizedMetadata[$key] = @($value)
                }
                else {
                    $sanitizedMetadata[$key] = $value
                }
            }
        }
        $entry['metadata'] = $sanitizedMetadata
    }
    
    # Add exception details if provided
    if ($null -ne $Exception) {
        $entry['exception'] = @{
            type    = $Exception.GetType().FullName
            message = ConvertTo-ASCIISafe -InputString $Exception.Message
        }
        if ($Exception.StackTrace) {
            $entry['exception']['stackTrace'] = ConvertTo-ASCIISafe -InputString $Exception.StackTrace
        }
    }
    
    return [pscustomobject]$entry
}

<#
.SYNOPSIS
    Writes a structured log entry to the log file.
.DESCRIPTION
    Writes a log entry to the JSON-lines log file for the current date.
    Uses atomic writes (temp file + rename) for safety.
    
    If the log write fails, outputs to the error stream and continues.
.PARAMETER Entry
    The log entry object to write (created by New-LogEntry).
.PARAMETER LogDirectory
    The directory where log files are stored. Defaults to .llm-workflow/logs
.PARAMETER Force
    If specified, attempts to create the log directory if it doesn't exist.
.OUTPUTS
    None
.EXAMPLE
    PS C:\> $entry = New-LogEntry -Level INFO -Message "Operation complete"
    PS C:\> Write-StructuredLog -Entry $entry
    
    Creates and writes a log entry.
.EXAMPLE
    PS C:\> New-LogEntry -Level ERROR -Message "Failed" | Write-StructuredLog
    
    Pipeline usage for creating and writing log entries.
#>
function Write-StructuredLog {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true, ValueFromPipeline = $true)]
        [pscustomobject]$Entry,
        
        [Parameter()]
        [string]$LogDirectory = $script:DefaultLogDirectory,
        
        [Parameter()]
        [switch]$Force
    )
    
    begin {
        $logPath = Get-LogPath -LogDirectory $LogDirectory
        
        # Ensure log directory exists
        if (-not (Test-Path -LiteralPath $LogDirectory)) {
            if ($Force) {
                try {
                    New-Item -ItemType Directory -Path $LogDirectory -Force | Out-Null
                }
                catch {
                    Write-Warning "[Logging] Failed to create log directory: $_"
                    return
                }
            }
            else {
                # Silently skip if directory doesn't exist and Force not specified
                return
            }
        }
    }
    
    process {
        try {
            # Convert entry to JSON (single line for JSON-lines format)
            $jsonLine = $Entry | ConvertTo-Json -Compress -Depth 10
            
            # Ensure ASCII-safe output
            $safeLine = ConvertTo-ASCIISafe -InputString $jsonLine
            
            # Atomic write: write to temp file, then rename
            $tempFile = [System.IO.Path]::GetTempFileName()
            
            try {
                # Append to log file using temp file + rename for atomicity
                $existingContent = ""
                if (Test-Path -LiteralPath $logPath) {
                    $existingContent = Get-Content -LiteralPath $logPath -Raw -Encoding UTF8
                    if ($existingContent -and -not $existingContent.EndsWith("`n")) {
                        $existingContent += "`n"
                    }
                }
                
                $fullContent = $existingContent + $safeLine
                [System.IO.File]::WriteAllText($tempFile, $fullContent, [System.Text.Encoding]::UTF8)
                
                # Atomic rename
                [System.IO.File]::Move($tempFile, $logPath, $true)
            }
            finally {
                # Cleanup temp file if it still exists
                if (Test-Path -LiteralPath $tempFile) {
                    Remove-Item -LiteralPath $tempFile -Force -ErrorAction SilentlyContinue
                }
            }
        }
        catch {
            # Safe degradation: write to error stream but don't fail
            Write-Warning "[Logging] Failed to write log entry: $_"
        }
    }
}

<#
.SYNOPSIS
    Gets the log file path for a given date.
.DESCRIPTION
    Returns the full path to the log file for the specified date,
    defaulting to today. Creates the log directory if it doesn't exist.
.PARAMETER Date
    The date for which to get the log file path. Defaults to today.
.PARAMETER LogDirectory
    The base log directory. Defaults to .llm-workflow/logs
.OUTPUTS
    System.String. The full path to the log file.
.EXAMPLE
    PS C:\> Get-LogPath
    .llm-workflow/logs/2026-04-12.jsonl
    
    Gets the log path for today.
.EXAMPLE
    PS C:\> Get-LogPath -Date ([DateTime]::Parse("2026-04-11"))
    .llm-workflow/logs/2026-04-11.jsonl
    
    Gets the log path for a specific date.
#>
function Get-LogPath {
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter()]
        [DateTime]$Date = [DateTime]::UtcNow,
        
        [Parameter()]
        [string]$LogDirectory = $script:DefaultLogDirectory
    )
    
    $dateString = $Date.ToString("yyyy-MM-dd", [System.Globalization.CultureInfo]::InvariantCulture)
    $logFileName = "$dateString.jsonl"
    
    return Join-Path $LogDirectory $logFileName
}

<#
.SYNOPSIS
    Reads log entries from a log file.
.DESCRIPTION
    Reads and parses JSON-lines log entries from a log file,
    optionally filtering by level or run ID.
.PARAMETER Date
    The date of the log file to read. Defaults to today.
.PARAMETER LogDirectory
    The base log directory.
.PARAMETER Level
    Filter by minimum log level (e.g., WARN returns WARN, ERROR, CRITICAL).
.PARAMETER RunId
    Filter by specific run ID.
.PARAMETER CorrelationId
    Filter by correlation ID.
.PARAMETER Tail
    If specified, returns only the last N entries.
.OUTPUTS
    System.Management.Automation.PSCustomObject[] representing log entries.
.EXAMPLE
    PS C:\> Read-StructuredLog
    
    Reads all log entries from today's log file.
.EXAMPLE
    PS C:\> Read-StructuredLog -Level ERROR -Tail 10
    
    Reads the last 10 ERROR or higher level entries.
#>
function Read-StructuredLog {
    [CmdletBinding()]
    [OutputType([array])]
    param(
        [Parameter()]
        [DateTime]$Date = [DateTime]::UtcNow,
        
        [Parameter()]
        [string]$LogDirectory = $script:DefaultLogDirectory,
        
        [Parameter()]
        [ValidateSet('VERBOSE', 'DEBUG', 'INFO', 'WARN', 'WARNING', 'ERROR', 'CRITICAL', 'FATAL')]
        [string]$Level = "",
        
        [Parameter()]
        [string]$RunId = "",
        
        [Parameter()]
        [string]$CorrelationId = "",
        
        [Parameter()]
        [int]$Tail = 0
    )
    
    $logPath = Get-LogPath -Date $Date -LogDirectory $LogDirectory
    
    if (-not (Test-Path -LiteralPath $logPath)) {
        Write-Verbose "[Logging] Log file not found: $logPath"
        return @()
    }
    
    try {
        $lines = Get-Content -LiteralPath $logPath -Encoding UTF8 | Where-Object { $_ }
        
        if ($Tail -gt 0) {
            $lines = $lines | Select-Object -Last $Tail
        }
        
        $entries = @()
        foreach ($line in $lines) {
            try {
                $entry = $line | ConvertFrom-Json
                
                # Apply filters
                $include = $true
                
                if (-not [string]::IsNullOrEmpty($Level)) {
                    $minLevelValue = $script:LogLevels[$Level.ToUpperInvariant()]
                    $entryLevelValue = $script:LogLevels[$entry.level]
                    if ($entryLevelValue -lt $minLevelValue) {
                        $include = $false
                    }
                }
                
                if ($include -and -not [string]::IsNullOrEmpty($RunId)) {
                    if ($entry.runId -ne $RunId) {
                        $include = $false
                    }
                }
                
                if ($include -and -not [string]::IsNullOrEmpty($CorrelationId)) {
                    if ($entry.correlationId -ne $CorrelationId) {
                        $include = $false
                    }
                }
                
                if ($include) {
                    $entries += $entry
                }
            }
            catch {
                Write-Verbose "[Logging] Failed to parse log line: $_"
            }
        }
        
        return $entries
    }
    catch {
        Write-Warning "[Logging] Failed to read log file: $_"
        return @()
    }
}

<#
.SYNOPSIS
    Sets the default log directory path.
.DESCRIPTION
    Updates the script-level default log directory used by other
    logging functions when no explicit path is provided.
.PARAMETER Path
    The new default log directory path.
.EXAMPLE
    PS C:\> Set-LogDirectory -Path "/var/log/llm-workflow"
    
    Sets the default log directory to a custom path.
#>
function Set-LogDirectory {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path
    )
    
    $script:DefaultLogDirectory = $Path
    Write-Verbose "[Logging] Default log directory set to: $Path"
}

<#
.SYNOPSIS
    Helper function to convert string to ASCII-safe format.
.DESCRIPTION
    Removes or replaces non-ASCII characters to ensure safe JSON
    serialization and cross-platform compatibility.
.PARAMETER InputString
    The string to convert.
.OUTPUTS
    System.String. ASCII-safe version of the input.
#>
function ConvertTo-ASCIISafe {
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory = $true)]
        [AllowEmptyString()]
        [string]$InputString
    )
    
    if ([string]::IsNullOrEmpty($InputString)) {
        return $InputString
    }
    
    # Use ASCII encoding to strip non-ASCII characters
    $bytes = [System.Text.Encoding]::ASCII.GetBytes($InputString)
    $ascii = [System.Text.Encoding]::ASCII.GetString($bytes)
    
    return $ascii
}

<#
.SYNOPSIS
    Helper function to determine if a field should be redacted.
.DESCRIPTION
    Checks if a field name matches any sensitive patterns or
    explicit redaction list.
.PARAMETER FieldName
    The name of the field to check.
.PARAMETER RedactPatterns
    Additional patterns to check for redaction.
.OUTPUTS
    System.Boolean. True if the field should be redacted.
#>
function Should-Redact {
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [Parameter(Mandatory = $true)]
        [string]$FieldName,
        
        [Parameter()]
        [string[]]$RedactPatterns = @()
    )
    
    $lowerFieldName = $FieldName.ToLowerInvariant()
    $allPatterns = $script:SensitivePatterns + $RedactPatterns
    
    foreach ($pattern in $allPatterns) {
        if ($lowerFieldName -match $pattern) {
            return $true
        }
    }
    
    return $false
}

try {
    Export-ModuleMember -Function @(
        'New-LogEntry',
        'Write-StructuredLog',
        'Get-LogPath',
        'Read-StructuredLog',
        'Set-LogDirectory'
    )
}
catch {
    # Silently ignore if dot-sourced
}
