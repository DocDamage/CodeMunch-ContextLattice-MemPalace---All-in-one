#requires -Version 5.1
Set-StrictMode -Version Latest


function Get-ReviewStatePath {
    <#
    .SYNOPSIS
        Gets the path to the review gates state file.
    
    .PARAMETER ProjectRoot
        The project root directory. Defaults to current directory.
    
    .OUTPUTS
        System.String. The full path to the review state file.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [string]$ProjectRoot = "."
    )
    
    $resolvedRoot = Resolve-Path -Path $ProjectRoot -ErrorAction SilentlyContinue
    if (-not $resolvedRoot) {
        $resolvedRoot = $ProjectRoot
    }
    
    $stateDir = Join-Path $resolvedRoot ".llm-workflow\state"
    
    if (-not (Test-Path -LiteralPath $stateDir)) {
        try {
            New-Item -ItemType Directory -Path $stateDir -Force | Out-Null
        }
        catch {
            throw "Failed to create state directory: $stateDir. Error: $_"
        }
    }
    
    return Join-Path $stateDir $script:ReviewStateFileName
}



function Get-ReviewLogPath {
    <#
    .SYNOPSIS
        Gets the path to the review log file (JSON Lines format).
    
    .PARAMETER ProjectRoot
        The project root directory.
    
    .OUTPUTS
        System.String. The full path to the review log file.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [string]$ProjectRoot = "."
    )
    
    $resolvedRoot = Resolve-Path -Path $ProjectRoot -ErrorAction SilentlyContinue
    if (-not $resolvedRoot) {
        $resolvedRoot = $ProjectRoot
    }
    
    $logsDir = Join-Path $resolvedRoot ".llm-workflow\logs"
    
    if (-not (Test-Path -LiteralPath $logsDir)) {
        try {
            New-Item -ItemType Directory -Path $logsDir -Force | Out-Null
        }
        catch {
            throw "Failed to create logs directory: $logsDir. Error: $_"
        }
    }
    
    return Join-Path $logsDir $script:ReviewLogFileName
}



function Get-ReviewState {
    <#
    .SYNOPSIS
        Loads the review gates state from file.
    
    .PARAMETER ProjectRoot
        The project root directory.
    
    .OUTPUTS
        Hashtable. The review state data.
    #>
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [string]$ProjectRoot = "."
    )
    
    $statePath = Get-ReviewStatePath -ProjectRoot $ProjectRoot
    
    if (-not (Test-Path -LiteralPath $statePath)) {
        # Initialize empty state
        return @{
            schemaVersion = $script:ReviewStateSchemaVersion
            schemaName = $script:ReviewStateSchemaName
            requests = @{}
            policies = @{}
            stats = @{
                totalRequests = 0
                approvedCount = 0
                rejectedCount = 0
                pendingCount = 0
                expiredCount = 0
            }
            lastUpdated = [DateTime]::UtcNow.ToString("yyyy-MM-ddTHH:mm:ssZ")
        }
    }
    
    try {
        $content = Get-Content -LiteralPath $statePath -Raw -Encoding UTF8
        
        # Handle empty file
        if ([string]::IsNullOrWhiteSpace($content)) {
            throw "State file is empty"
        }
        
        $jsonObj = $content | ConvertFrom-Json
        
        # Handle null result from ConvertFrom-Json
        if ($null -eq $jsonObj) {
            throw "Failed to parse state file"
        }
        
        # Convert PSCustomObject to Hashtable (PowerShell 5.1 compatible)
        $state = ConvertTo-Hashtable -InputObject $jsonObj
        
        # Ensure required structure exists
        if (-not $state -or -not $state.ContainsKey('requests')) { $state = @{}; $state['requests'] = @{} }
        if (-not $state.ContainsKey('policies')) { $state['policies'] = @{} }
        if (-not $state.ContainsKey('stats')) { 
            $state['stats'] = @{
                totalRequests = 0
                approvedCount = 0
                rejectedCount = 0
                pendingCount = 0
                expiredCount = 0
            }
        }
        if (-not $state.ContainsKey('schemaName')) {
            $state['schemaName'] = $script:ReviewStateSchemaName
        }
        
        return $state
    }
    catch {
        Write-Warning "Failed to load review state: $_. Initializing new state."
        return @{
            schemaVersion = $script:ReviewStateSchemaVersion
            schemaName = $script:ReviewStateSchemaName
            requests = @{}
            policies = @{}
            stats = @{
                totalRequests = 0
                approvedCount = 0
                rejectedCount = 0
                pendingCount = 0
                expiredCount = 0
            }
            lastUpdated = [DateTime]::UtcNow.ToString("yyyy-MM-ddTHH:mm:ssZ")
        }
    }
}



function Save-ReviewState {
    <#
    .SYNOPSIS
        Saves the review gates state to file atomically.
    
    .PARAMETER State
        The state data to save.
    
    .PARAMETER ProjectRoot
        The project root directory.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [hashtable]$State,
        
        [string]$ProjectRoot = "."
    )
    
    $statePath = Get-ReviewStatePath -ProjectRoot $ProjectRoot
    $State['lastUpdated'] = [DateTime]::UtcNow.ToString("yyyy-MM-ddTHH:mm:ssZ")
    
    try {
        # Create backup if file exists
        if (Test-Path -LiteralPath $statePath) {
            $backupTimestamp = [DateTime]::Now.ToString("yyyyMMddHHmmss")
            $backupPath = "$statePath.backup.$backupTimestamp"
            Copy-Item -LiteralPath $statePath -Destination $backupPath -Force -ErrorAction SilentlyContinue
        }
        
        # Atomic write
        $tempPath = "$statePath.tmp.$PID.$([Guid]::NewGuid().ToString('N'))"
        $json = $State | ConvertTo-Json -Depth 20 -Compress:$false
        [System.IO.File]::WriteAllText($tempPath, $json, [System.Text.Encoding]::UTF8)
        
        # Atomic rename (PowerShell 5.1 compatible)
        if (Test-Path -LiteralPath $statePath) {
            Remove-Item -LiteralPath $statePath -Force -ErrorAction SilentlyContinue
        }
        Move-Item -LiteralPath $tempPath -Destination $statePath -Force
        
        return
    }
    catch {
        # Clean up temp file
        if (Test-Path -LiteralPath $tempPath) {
            Remove-Item -LiteralPath $tempPath -Force -ErrorAction SilentlyContinue
        }
        throw "Failed to save review state: $_"
    }
}



function Write-ReviewLogEntry {
    <#
    .SYNOPSIS
        Writes an entry to the review log (JSON Lines format).
    
    .DESCRIPTION
        Persists review events to a JSON Lines log file as per Section 10.3
        requirement for persistent review log with run ID.
    
    .PARAMETER Entry
        The log entry to write.
    
    .PARAMETER ProjectRoot
        The project root directory.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [hashtable]$Entry,
        
        [string]$ProjectRoot = "."
    )
    
    try {
        $logPath = Get-ReviewLogPath -ProjectRoot $ProjectRoot
        
        # Add standard fields
        $Entry['timestamp'] = [DateTime]::UtcNow.ToString("yyyy-MM-ddTHH:mm:ss.fffZ")
        if (-not $Entry.ContainsKey('runId')) {
            $Entry['runId'] = Get-CurrentRunId -ErrorAction SilentlyContinue
        }
        
        # Convert to JSON line
        $jsonLine = $Entry | ConvertTo-Json -Compress -Depth 5
        
        # Append to log file
        $jsonLine | Out-File -FilePath $logPath -Encoding UTF8 -Append
    }
    catch {
        Write-Warning "Failed to write review log entry: $_"
    }
}



function Update-ReviewRequest {
    <#
    .SYNOPSIS
        Updates a specific review request in the state.
    
    .PARAMETER RequestId
        The review request ID.
    
    .PARAMETER Updates
        Hashtable of updates to apply.
    
    .PARAMETER ProjectRoot
        The project root directory.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$RequestId,
        
        [Parameter(Mandatory = $true)]
        [hashtable]$Updates,
        
        [string]$ProjectRoot = "."
    )
    
    $state = Get-ReviewState -ProjectRoot $ProjectRoot
    
    if (-not $state.requests.ContainsKey($RequestId)) {
        throw "Review request not found: $RequestId"
    }
    
    $request = $state.requests[$RequestId]
    
    # Apply updates
    foreach ($key in $Updates.Keys) {
        $request[$key] = $Updates[$key]
    }
    
    $request['updatedAt'] = [DateTime]::UtcNow.ToString("yyyy-MM-ddTHH:mm:ssZ")
    
    Save-ReviewState -State $state -ProjectRoot $ProjectRoot
    return $request
}



function ConvertTo-Hashtable {
    <#
    .SYNOPSIS
        Recursively converts a PSCustomObject to a Hashtable.
    
    .DESCRIPTION
        PowerShell 5.1 compatible conversion of JSON objects to hashtables.
    
    .PARAMETER InputObject
        The object to convert.
    
    .OUTPUTS
        Hashtable representation of the input object.
    #>
    param($InputObject)
    
    if ($null -eq $InputObject) {
        return $null
    }
    
    if ($InputObject -is [Array] -or $InputObject -is [System.Collections.ArrayList]) {
        $array = @()
        foreach ($item in $InputObject) {
            $converted = ConvertTo-Hashtable -InputObject $item
            $array += $converted
        }
        return $array
    }
    
    if ($InputObject -is [PSObject]) {
        $hash = @{}
        foreach ($property in $InputObject.PSObject.Properties) {
            $value = ConvertTo-Hashtable -InputObject $property.Value
            $hash[$property.Name] = $value
        }
        return $hash
    }
    
    return $InputObject
}



function Get-PropertyValue {
    <#
    .SYNOPSIS
        Safely gets a property value from an object (hashtable or PSCustomObject).
    
    .DESCRIPTION
        PowerShell 5.1 compatible property accessor that works with both
        hashtables and PSCustomObjects.
    
    .PARAMETER Object
        The object to get the property from.
    
    .PARAMETER PropertyName
        The name of the property.
    
    .OUTPUTS
        The property value, or null if not found.
    #>
    param($Object, $PropertyName)
    
    if ($null -eq $Object) {
        return $null
    }
    
    if ($Object -is [hashtable]) {
        if ($Object.ContainsKey($PropertyName)) {
            return $Object[$PropertyName]
        }
    }
    elseif ($Object.PSObject -and $Object.PSObject.Properties[$PropertyName]) {
        return $Object.PSObject.Properties[$PropertyName].Value
    }
    
    return $null
}


