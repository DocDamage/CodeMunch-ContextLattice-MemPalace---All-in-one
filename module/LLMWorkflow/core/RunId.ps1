#requires -Version 5.1
<#
.SYNOPSIS
    Run identification functions for LLM Workflow journaling system.
.DESCRIPTION
    Provides functions for generating unique run identifiers and managing
    current run context for the journaling and checkpoint system.
    
    Run IDs follow the format: yyyyMMddTHHmmssZ-xxxx where:
    - yyyyMMddTHHmmssZ is the UTC timestamp in ISO 8601 basic format
    - xxxx is a 4-character lowercase hexadecimal random suffix
    
    Example: 20260411T210501Z-7f2c
.NOTES
    File Name      : RunId.ps1
    Author         : LLM Workflow Team
    Prerequisite   : PowerShell 5.1+
    Copyright      : (c) 2026 LLM Workflow Project
    License        : MIT
    Version        : 1.1.0
#>

Set-StrictMode -Version Latest

# Script-level variable to cache the current run ID
$script:CurrentRunId = $null
$script:CurrentRunIdCreated = $false

# RunId format pattern
$script:RunIdPattern = '^\d{8}T\d{6}Z-[0-9a-f]{4}$'

<#
.SYNOPSIS
    Generates a new unique run identifier.
.DESCRIPTION
    Creates a deterministic run ID based on the current UTC timestamp
    and a random 4-character hexadecimal suffix.
    
    The format is: yyyyMMddTHHmmssZ-xxxx
    Example: 20260411T210501Z-7f2c
.PARAMETER Timestamp
    Optional. A specific DateTime to use instead of the current UTC time.
    Defaults to [DateTime]::UtcNow.
.PARAMETER Suffix
    Optional. A specific 4-character hexadecimal suffix to use instead
    of generating a random one. Used for testing or deterministic ID generation.
.OUTPUTS
    System.String. The generated run ID in the format yyyyMMddTHHmmssZ-xxxx.
.EXAMPLE
    PS C:\> New-RunId
    20260411T210501Z-7f2c
    
    Generates a new run ID based on the current UTC time.
.EXAMPLE
    PS C:\> New-RunId -Timestamp ([DateTime]::Parse("2026-04-11T21:05:01Z"))
    20260411T210501Z-a3b9
    
    Generates a run ID for a specific timestamp.
.EXAMPLE
    PS C:\> New-RunId -Suffix "0000"
    20260411T210501Z-0000
    
    Generates a run ID with a specific suffix for testing.
#>
function New-RunId {
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter()]
        [DateTime]$Timestamp = [DateTime]::UtcNow,
        
        [Parameter()]
        [ValidatePattern('^[0-9a-f]{4}$')]
        [string]$Suffix = ""
    )
    
    # Format timestamp in ISO 8601 basic format (no separators), always UTC
    $utcTimestamp = $Timestamp.ToUniversalTime()
    $timestampPart = $utcTimestamp.ToString("yyyyMMddTHHmmssZ", [System.Globalization.CultureInfo]::InvariantCulture)
    
    # Generate random suffix if not provided
    if ([string]::IsNullOrEmpty($Suffix)) {
        # Use a cryptographically secure random number generator when available
        try {
            $rng = [System.Security.Cryptography.RandomNumberGenerator]::Create()
            $bytes = New-Object byte[] 2
            $rng.GetBytes($bytes)
            $randomValue = [BitConverter]::ToUInt16($bytes, 0)
            $Suffix = $randomValue.ToString("x4")  # Lowercase 4-digit hex
        }
        catch {
            # Fallback to System.Random if crypto RNG is not available
            $random = New-Object System.Random
            $suffixValue = $random.Next(0, 65536)  # 0 to 0xFFFF
            $Suffix = $suffixValue.ToString("x4")  # Lowercase 4-digit hex
        }
    }
    
    $runId = "$timestampPart-$Suffix"
    
    Write-Verbose "[RunId] Generated new run ID: $runId"
    
    return $runId
}

<#
.SYNOPSIS
    Gets or creates the current run ID for this PowerShell session.
.DESCRIPTION
    Returns the current run ID for the session, creating one if it doesn't
    exist yet. This provides a consistent run ID across multiple calls
    within the same session, useful for associating multiple operations
    with a single logical run.
    
    The run ID is cached at the script scope level.
.PARAMETER ForceNew
    If specified, forces the creation of a new run ID even if one already
    exists for this session.
.OUTPUTS
    System.String. The current (or new) run ID.
.EXAMPLE
    PS C:\> Get-CurrentRunId
    20260411T210501Z-7f2c
    
    Gets or creates the current run ID.
.EXAMPLE
    PS C:\> Get-CurrentRunId -ForceNew
    20260411T210502Z-9e4d
    
    Forces creation of a new run ID.
#>
function Get-CurrentRunId {
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter()]
        [switch]$ForceNew
    )
    
    if ($ForceNew -or $null -eq $script:CurrentRunId) {
        $script:CurrentRunId = New-RunId
        $script:CurrentRunIdCreated = $true
        Write-Verbose "[RunId] Created new run ID: $($script:CurrentRunId)"
    }
    else {
        Write-Verbose "[RunId] Using existing run ID: $($script:CurrentRunId)"
    }
    
    return $script:CurrentRunId
}

<#
.SYNOPSIS
    Sets the current run ID for this PowerShell session.
.DESCRIPTION
    Sets the cached run ID to a specific value, useful for resuming
    operations or associating with an existing run.
    
    Validates the run ID format before setting.
.PARAMETER RunId
    The run ID to set as the current session's run ID.
    Must be in the format yyyyMMddTHHmmssZ-xxxx.
.EXAMPLE
    PS C:\> Set-CurrentRunId -RunId "20260411T210501Z-7f2c"
    
    Sets the current run ID to the specified value.
#>
function Set-CurrentRunId {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [ValidatePattern('^\d{8}T\d{6}Z-[0-9a-f]{4}$')]
        [string]$RunId
    )
    
    $script:CurrentRunId = $RunId
    $script:CurrentRunIdCreated = $true
    Write-Verbose "[RunId] Set current run ID to: $RunId"
}

<#
.SYNOPSIS
    Clears the current run ID from the session cache.
.DESCRIPTION
    Removes the cached run ID, causing the next call to Get-CurrentRunId
    to generate a new one. Useful for starting fresh operations.
.EXAMPLE
    PS C:\> Clear-CurrentRunId
    
    Clears the current run ID from the session.
#>
function Clear-CurrentRunId {
    [CmdletBinding()]
    param()
    
    $oldRunId = $script:CurrentRunId
    $script:CurrentRunId = $null
    $script:CurrentRunIdCreated = $false
    
    if ($null -ne $oldRunId) {
        Write-Verbose "[RunId] Cleared run ID: $oldRunId"
    }
}

<#
.SYNOPSIS
    Tests if a string is a valid run ID format.
.DESCRIPTION
    Validates that a given string matches the expected run ID format
    of yyyyMMddTHHmmssZ-xxxx.
.PARAMETER RunId
    The string to validate as a run ID.
.OUTPUTS
    System.Boolean. True if the format is valid; otherwise false.
.EXAMPLE
    PS C:\> Test-RunIdFormat -RunId "20260411T210501Z-7f2c"
    True
    
    Validates the run ID format.
.EXAMPLE
    PS C:\> "invalid" | Test-RunIdFormat
    False
    
    Pipeline input is also supported.
#>
function Test-RunIdFormat {
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [Parameter(Mandatory = $true, ValueFromPipeline = $true)]
        [AllowEmptyString()]
        [string]$RunId
    )
    
    process {
        if ([string]::IsNullOrEmpty($RunId)) {
            return $false
        }
        
        # Pattern: 8 digits, T, 6 digits, Z, -, 4 hex chars
        return $RunId -match $script:RunIdPattern
    }
}

<#
.SYNOPSIS
    Parses a run ID into its component parts.
.DESCRIPTION
    Extracts the timestamp and suffix components from a valid run ID,
    returning them as a structured object.
.PARAMETER RunId
    The run ID to parse.
.OUTPUTS
    System.Management.Automation.PSCustomObject with properties:
    - RunId: The original run ID string
    - TimestampUtc: The DateTime component
    - Suffix: The 4-character hex suffix
    - IsValid: Boolean indicating if parsing succeeded
.EXAMPLE
    PS C:\> Parse-RunId -RunId "20260411T210501Z-7f2c"
    
    RunId          : 20260411T210501Z-7f2c
    TimestampUtc   : 4/11/2026 9:05:01 PM
    Suffix         : 7f2c
    IsValid        : True
#>
function Parse-RunId {
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory = $true, ValueFromPipeline = $true)]
        [string]$RunId
    )
    
    process {
        $result = [pscustomobject]@{
            RunId        = $RunId
            TimestampUtc = $null
            Suffix       = $null
            IsValid      = $false
        }
        
        if (Test-RunIdFormat -RunId $RunId) {
            try {
                # Extract timestamp part: yyyyMMddTHHmmss
                $timestampStr = $RunId.Substring(0, 15)
                $result.TimestampUtc = [DateTime]::ParseExact(
                    $timestampStr,
                    "yyyyMMddTHHmmss",
                    [System.Globalization.CultureInfo]::InvariantCulture,
                    [System.Globalization.DateTimeStyles]::AssumeUniversal -bor [System.Globalization.DateTimeStyles]::AdjustToUniversal
                )
                
                # Extract suffix part (after the dash at position 16)
                $result.Suffix = $RunId.Substring(17, 4)
                $result.IsValid = $true
            }
            catch {
                Write-Verbose "[RunId] Failed to parse run ID '$RunId': $_"
            }
        }
        
        return $result
    }
}

<#
.SYNOPSIS
    Exports run ID related functions.
.DESCRIPTION
    Returns a hashtable of all public functions defined in this module
    for explicit importing.
.OUTPUTS
    System.Collections.Hashtable
#>
function Get-RunIdFunctions {
    [CmdletBinding()]
    [OutputType([hashtable])]
    param()
    
    return @{
        'New-RunId'          = ${function:New-RunId}
        'Get-CurrentRunId'   = ${function:Get-CurrentRunId}
        'Set-CurrentRunId'   = ${function:Set-CurrentRunId}
        'Clear-CurrentRunId' = ${function:Clear-CurrentRunId}
        'Test-RunIdFormat'   = ${function:Test-RunIdFormat}
        'Parse-RunId'        = ${function:Parse-RunId}
    }
}

# Export functions
Export-ModuleMember -Function @(
    'New-RunId',
    'Get-CurrentRunId',
    'Set-CurrentRunId',
    'Clear-CurrentRunId',
    'Test-RunIdFormat',
    'Parse-RunId',
    'Get-RunIdFunctions'
)
