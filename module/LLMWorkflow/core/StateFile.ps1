#requires -Version 5.1
<#
.SYNOPSIS
    State File Management for LLM Workflow platform.

.DESCRIPTION
    Provides high-level state file operations with schema validation,
    versioning, and atomic update semantics. Implements the state safety
    invariant requirements from IMPROVEMENT_PROPOSALS.md section 3.2.

.NOTES
    File: StateFile.ps1
    Version: 1.0.0
    Author: LLM Workflow Team

.EXAMPLE
    # Read state with version validation
    $state = Read-StateFile -Path ".llm-workflow/state/sync-state.json" -ExpectedVersion 2

    # Update state atomically
    Update-StateFile -Path ".llm-workflow/state/sync-state.json" -Updates @{ lastSync = Get-Date }
#>

Set-StrictMode -Version Latest

function ConvertTo-Hashtable {
    [CmdletBinding()]
    param([Parameter(ValueFromPipeline = $true)]$InputObject)
    process {
        if ($null -eq $InputObject) { return $null }
        if ($InputObject -is [System.Collections.Hashtable]) { return $InputObject }
        if ($InputObject -is [System.Management.Automation.PSCustomObject]) {
            $hash = @{}
            foreach ($property in $InputObject.PSObject.Properties) {
                $hash[$property.Name] = (ConvertTo-Hashtable -InputObject $property.Value)
            }
            return $hash
        }
        if ($InputObject -is [System.Collections.IEnumerable] -and $InputObject -isnot [string]) {
            $collection = @()
            foreach ($item in $InputObject) {
                $collection += (ConvertTo-Hashtable -InputObject $item)
            }
            return $collection
        }
        return $InputObject
    }
}

# Import dependency functions (assumes AtomicWrite.ps1 is available)
# In a module context, these would be imported via the module manifest

<#
.SYNOPSIS
    Gets the default state directory for the project.

.DESCRIPTION
    Returns the canonical state directory path as defined in section 4.2
    of IMPROVEMENT_PROPOSALS.md.

.PARAMETER ProjectRoot
    The project root directory. Defaults to current directory.

.OUTPUTS
    System.String. The full path to the state directory.
#>
function Get-StateDirectory {
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

    return $stateDir
}

<#
.SYNOPSIS
    Gets the default path for a state file.

.DESCRIPTION
    Returns the canonical path for a named state file.

.PARAMETER Name
    The state file name (e.g., sync-state, heal-state, etc.).

.PARAMETER ProjectRoot
    The project root directory. Defaults to current directory.

.OUTPUTS
    System.String. The full path to the state file.
#>
function Get-StateFilePath {
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Name,
        
        [string]$ProjectRoot = "."
    )

    $stateDir = Get-StateDirectory -ProjectRoot $ProjectRoot
    
    # Ensure .json extension
    if (-not $Name.EndsWith('.json')) {
        $Name = "$Name.json"
    }

    return Join-Path $stateDir $Name
}

<#
.SYNOPSIS
    Reads a state file with schema validation.

.DESCRIPTION
    Reads a JSON state file, validates schema version if present,
    and returns the state data.

.PARAMETER Path
    The path to the state file.

.PARAMETER ExpectedVersion
    Expected schema version. If specified, validates against actual version.

.PARAMETER DefaultValue
    Value to return if file doesn't exist.

.PARAMETER ValidateScript
    Script block to validate the data structure.

.OUTPUTS
    PSObject. Result with Success, Data, Version, Error.

.EXAMPLE
    $result = Read-StateFile -Path "sync-state.json" -ExpectedVersion 2
    if ($result.Success) { $syncData = $result.Data }

.EXAMPLE
    # With default value
    $state = (Read-StateFile -Path "state.json" -DefaultValue @{ count = 0 }).Data
#>
function Read-StateFile {
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path,
        
        [int]$ExpectedVersion = 0,
        
        [object]$DefaultValue = $null,
        
        [scriptblock]$ValidateScript = $null
    )

    # Resolve path
    $resolvedPath = Resolve-Path -Path $Path -ErrorAction SilentlyContinue
    if (-not $resolvedPath) {
        $resolvedPath = $Path
    }

    # Check if file exists
    if (-not (Test-Path -LiteralPath $resolvedPath)) {
        if ($null -ne $DefaultValue) {
            return [pscustomobject]@{
                Success = $true
                Data = $DefaultValue
                Version = $ExpectedVersion
                Schema = $null
                Error = $null
                Path = $resolvedPath
                Exists = $false
            }
        }
        return [pscustomobject]@{
            Success = $false
            Data = $null
            Version = 0
            Schema = $null
            Error = "State file not found: $resolvedPath"
            Path = $resolvedPath
            Exists = $false
        }
    }

    try {
        $rawContent = [System.IO.File]::ReadAllText($resolvedPath, [System.Text.Encoding]::UTF8)
        
        # Handle empty file
        if ([string]::IsNullOrWhiteSpace($rawContent)) {
            if ($null -ne $DefaultValue) {
                return [pscustomobject]@{
                    Success = $true
                    Data = $DefaultValue
                    Version = $ExpectedVersion
                    Schema = $null
                    Error = $null
                    Path = $resolvedPath
                    Exists = $true
                }
            }
            return [pscustomobject]@{
                Success = $false
                Data = $null
                Version = 0
                Schema = $null
                Error = "State file is empty"
                Path = $resolvedPath
                Exists = $true
            }
        }

        $parsed = $rawContent | ConvertFrom-Json | ConvertTo-Hashtable

        # Check for schema header
        $schema = $null
        $data = $parsed
        $version = 0

        if ($parsed.ContainsKey("_schema") -and $parsed.ContainsKey("data")) {
            $schema = $parsed["_schema"]
            $data = $parsed["data"]
            $version = $schema["version"]
        }
        elseif ($parsed.ContainsKey("schemaVersion")) {
            # Legacy format with schemaVersion at root
            $version = $parsed["schemaVersion"]
            $data = $parsed
        }

        # Validate version if specified
        if ($ExpectedVersion -gt 0 -and $version -ne $ExpectedVersion) {
            return [pscustomobject]@{
                Success = $false
                Data = $data
                Version = $version
                Schema = $schema
                Error = "Schema version mismatch: expected $ExpectedVersion, got $version"
                Path = $resolvedPath
                Exists = $true
            }
        }

        # Run custom validation if provided
        if ($null -ne $ValidateScript) {
            $validationResult = & $ValidateScript $data
            if ($validationResult -ne $true) {
                return [pscustomobject]@{
                    Success = $false
                    Data = $data
                    Version = $version
                    Schema = $schema
                    Error = "Custom validation failed: $validationResult"
                    Path = $resolvedPath
                    Exists = $true
                }
            }
        }

        return [pscustomobject]@{
            Success = $true
            Data = $data
            Version = $version
            Schema = $schema
            Error = $null
            Path = $resolvedPath
            Exists = $true
        }
    }
    catch {
        return [pscustomobject]@{
            Success = $false
            Data = $null
            Version = 0
            Schema = $null
            Error = "Failed to read state file: $_"
            Path = $resolvedPath
            Exists = Test-Path -LiteralPath $resolvedPath
        }
    }
}

<#
.SYNOPSIS
    Writes a state file with schema header.

.DESCRIPTION
    Writes state data to a JSON file with automatic schema versioning.
    Uses atomic write operations for safety.

.PARAMETER Path
    The path to the state file.

.PARAMETER Data
    The state data to write.

.PARAMETER SchemaVersion
    Schema version for the state file. Default is 1.

.PARAMETER SchemaName
    Schema name/type identifier.

.PARAMETER BackupCount
    Number of backups to retain. Default is 5.

.PARAMETER Metadata
    Additional metadata to include in schema header.

.OUTPUTS
    PSObject. Result with Success, Path, Version, BytesWritten.

.EXAMPLE
    Write-StateFile -Path "sync-state.json" -Data $syncData -SchemaVersion 2 -SchemaName "sync-state"
#>
function Write-StateFile {
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path,
        
        [Parameter(Mandatory = $true)]
        [object]$Data,
        
        [int]$SchemaVersion = 1,
        
        [string]$SchemaName = "",
        
        [int]$BackupCount = 5,
        
        [hashtable]$Metadata = @{}
    )

    $resolvedPath = Resolve-Path -Path $Path -ErrorAction SilentlyContinue
    if (-not $resolvedPath) {
        $resolvedPath = $Path
    }

    # Build schema header
    $schemaHeader = @{
        version = $SchemaVersion
        name = if ($SchemaName) { $SchemaName } else { [System.IO.Path]::GetFileNameWithoutExtension($resolvedPath) }
        createdAt = [DateTime]::UtcNow.ToString("yyyy-MM-ddTHH:mm:ssZ")
        createdBy = [Environment]::UserName
        host = [Environment]::MachineName.ToLowerInvariant()
        pid = $PID
    }

    # Add custom metadata
    if ($Metadata.Count -gt 0) {
        foreach ($key in $Metadata.Keys) {
            if (-not $schemaHeader.ContainsKey($key)) {
                $schemaHeader[$key] = $Metadata[$key]
            }
        }
    }

    # Wrap data with schema
    $wrappedData = @{
        _schema = $schemaHeader
        data = $Data
    }

    # Perform atomic write with backup
    try {
        $dir = Split-Path -Parent $resolvedPath
        if (-not (Test-Path -LiteralPath $dir)) {
            New-Item -ItemType Directory -Path $dir -Force | Out-Null
        }

        # Convert to JSON
        $json = $wrappedData | ConvertTo-Json -Depth 20 -Compress:$false
        $bytes = [System.Text.Encoding]::UTF8.GetBytes($json)

        # Create backup if file exists
        $backupResult = $null
        if (Test-Path -LiteralPath $resolvedPath) {
            $backupResult = Backup-StateFile -Path $resolvedPath -BackupCount $BackupCount
        }

        # Atomic write
        $tempPath = "$resolvedPath.tmp.$PID.$([Guid]::NewGuid().ToString('N'))"
        $stream = [System.IO.File]::Create($tempPath)
        try {
            $stream.Write($bytes, 0, $bytes.Length)
            $stream.Flush($true)
        }
        finally {
            $stream.Close()
        }

        # Atomic rename
        if (Test-Path -LiteralPath $resolvedPath) {
            Remove-Item -LiteralPath $resolvedPath -Force -ErrorAction Stop
        }
        [System.IO.File]::Move($tempPath, $resolvedPath)

        return [pscustomobject]@{
            Success = $true
            Path = $resolvedPath
            Version = $SchemaVersion
            BytesWritten = $bytes.Length
            BackupPath = if ($backupResult) { $backupResult.BackupPath } else { $null }
        }
    }
    catch {
        # Clean up temp file
        if (Test-Path -LiteralPath $tempPath) {
            Remove-Item -LiteralPath $tempPath -Force -ErrorAction SilentlyContinue
        }

        throw "Failed to write state file: $_"
    }
}

<#
.SYNOPSIS
    Updates a state file with atomic semantics.

.DESCRIPTION
    Reads the current state, applies updates, and writes back atomically.
    Supports both simple property updates and custom update script blocks.

.PARAMETER Path
    The path to the state file.

.PARAMETER Updates
    Hashtable of property updates to apply.

.PARAMETER UpdateScript
    Script block that receives current state and returns updated state.

.PARAMETER ExpectedVersion
    Expected current schema version (optimistic locking).

.PARAMETER SchemaVersion
    New schema version after update (default: keep current).

.PARAMETER SchemaName
    Schema name/type identifier.

.PARAMETER BackupCount
    Number of backups to retain. Default is 5.

.PARAMETER CreateIfMissing
    Create file if it doesn't exist.

.PARAMETER DefaultValue
    Default value if file doesn't exist.

.OUTPUTS
    PSObject. Result with Success, Path, Data, PreviousData, UpdatedFields.

.EXAMPLE
    # Simple property update
    Update-StateFile -Path "sync-state.json" -Updates @{ lastSync = Get-Date; count = 42 }

.EXAMPLE
    # Custom update logic
    Update-StateFile -Path "counter.json" -UpdateScript { param($state) $state.count++; return $state }

.EXAMPLE
    # With optimistic locking
    Update-StateFile -Path "state.json" -Updates @{ status = "done" } -ExpectedVersion 2
#>
function Update-StateFile {
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path,
        
        [hashtable]$Updates = @{},
        
        [scriptblock]$UpdateScript = $null,
        
        [int]$ExpectedVersion = 0,
        
        [int]$SchemaVersion = 0,
        
        [string]$SchemaName = "",
        
        [int]$BackupCount = 5,
        
        [switch]$CreateIfMissing,
        
        [object]$DefaultValue = @{}
    )

    $resolvedPath = Resolve-Path -Path $Path -ErrorAction SilentlyContinue
    if (-not $resolvedPath) {
        $resolvedPath = $Path
    }

    # Read current state
    $default = if ($CreateIfMissing) { $DefaultValue } else { $null }
    $readResult = Read-StateFile -Path $resolvedPath -DefaultValue $default

    if (-not $readResult.Success -and -not $CreateIfMissing) {
        return [pscustomobject]@{
            Success = $false
            Path = $resolvedPath
            Data = $null
            PreviousData = $null
            UpdatedFields = @()
            Error = $readResult.Error
        }
    }

    $currentState = $readResult.Data
    $previousState = $currentState | ConvertTo-Json -Depth 20 | ConvertFrom-Json | ConvertTo-Hashtable

    # Check version for optimistic locking
    if ($ExpectedVersion -gt 0 -and $readResult.Exists -and $readResult.Version -ne $ExpectedVersion) {
        return [pscustomobject]@{
            Success = $false
            Path = $resolvedPath
            Data = $currentState
            PreviousData = $previousState
            UpdatedFields = @()
            Error = "Optimistic lock failed: expected version $ExpectedVersion, found version $($readResult.Version)"
        }
    }

    # Initialize state if null
    if ($null -eq $currentState) {
        $currentState = @{}
    }

    # Apply updates
    $updatedFields = [System.Collections.Generic.List[string]]::new()

    if ($null -ne $UpdateScript) {
        # Custom update script
        $currentState = & $UpdateScript $currentState
        $updatedFields.Add("(script)")
    }
    else {
        # Hashtable updates
        foreach ($key in $Updates.Keys) {
            $oldValue = $currentState[$key]
            $newValue = $Updates[$key]
            
            # Check if value actually changed
            if (($null -eq $oldValue -and $null -ne $newValue) -or
                ($null -ne $oldValue -and $oldValue -ne $newValue)) {
                $updatedFields.Add($key)
            }
            
            $currentState[$key] = $newValue
        }
    }

    # Determine schema version
    $newVersion = if ($SchemaVersion -gt 0) { $SchemaVersion } else { $readResult.Version }
    if ($newVersion -eq 0) { $newVersion = 1 }

    # Determine schema name
    $newSchemaName = if ($SchemaName) { $SchemaName } else { if ($readResult.Schema) { $readResult.Schema["name"] } else { $null } }

    try {
        # Write updated state
        $writeResult = Write-StateFile -Path $resolvedPath -Data $currentState `
            -SchemaVersion $newVersion -SchemaName $newSchemaName -BackupCount $BackupCount `
            -Metadata @{ previousVersion = $readResult.Version; updatedFields = $updatedFields }

        return [pscustomobject]@{
            Success = $writeResult.Success
            Path = $resolvedPath
            Data = $currentState
            PreviousData = $previousState
            UpdatedFields = $updatedFields.ToArray()
            Version = $newVersion
            BackupPath = $writeResult.BackupPath
            Error = $null
        }
    }
    catch {
        return [pscustomobject]@{
            Success = $false
            Path = $resolvedPath
            Data = $currentState
            PreviousData = $previousState
            UpdatedFields = $updatedFields.ToArray()
            Version = $newVersion
            BackupPath = $null
            Error = $_.Exception.Message
        }
    }
}

<#
.SYNOPSIS
    Validates a state file's schema version.

.DESCRIPTION
    Tests if a state file exists and has a compatible schema version.
    Returns detailed information about version compatibility.

.PARAMETER Path
    The path to the state file.

.PARAMETER MinVersion
    Minimum acceptable version (inclusive).

.PARAMETER MaxVersion
    Maximum acceptable version (inclusive).

.PARAMETER ExactVersion
    Exact version required.

.OUTPUTS
    PSObject. Validation result with IsValid, ActualVersion, RequiredVersion, Error.

.EXAMPLE
    $validation = Test-StateVersion -Path "state.json" -MinVersion 1 -MaxVersion 3
    if ($validation.IsValid) { # proceed }

.EXAMPLE
    Test-StateVersion -Path "state.json" -ExactVersion 2
#>
function Test-StateVersion {
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path,
        
        [int]$MinVersion = 0,
        
        [int]$MaxVersion = 0,
        
        [int]$ExactVersion = 0
    )

    $resolvedPath = Resolve-Path -Path $Path -ErrorAction SilentlyContinue
    if (-not $resolvedPath) {
        $resolvedPath = $Path
    }

    if (-not (Test-Path -LiteralPath $resolvedPath)) {
        return [pscustomobject]@{
            IsValid = $false
            Exists = $false
            ActualVersion = 0
            RequiredVersion = if ($ExactVersion -gt 0) { $ExactVersion } else { "$MinVersion-$MaxVersion" }
            Error = "State file not found: $resolvedPath"
            Path = $resolvedPath
        }
    }

    $readResult = Read-StateFile -Path $resolvedPath
    
    if (-not $readResult.Success) {
        return [pscustomobject]@{
            IsValid = $false
            Exists = $true
            ActualVersion = 0
            RequiredVersion = if ($ExactVersion -gt 0) { $ExactVersion } else { "$MinVersion-$MaxVersion" }
            Error = $readResult.Error
            Path = $resolvedPath
        }
    }

    $actualVersion = $readResult.Version
    $isValid = $true
    $errorMsg = $null

    if ($ExactVersion -gt 0) {
        $isValid = ($actualVersion -eq $ExactVersion)
        if (-not $isValid) {
            $errorMsg = "Version mismatch: expected exactly $ExactVersion, got $actualVersion"
        }
    }
    else {
        if ($MinVersion -gt 0 -and $actualVersion -lt $MinVersion) {
            $isValid = $false
            $errorMsg = "Version too old: minimum $MinVersion, got $actualVersion"
        }
        if ($MaxVersion -gt 0 -and $actualVersion -gt $MaxVersion) {
            $isValid = $false
            $errorMsg = "Version too new: maximum $MaxVersion, got $actualVersion"
        }
    }

    return [pscustomobject]@{
        IsValid = $isValid
        Exists = $true
        ActualVersion = $actualVersion
        RequiredVersion = if ($ExactVersion -gt 0) { $ExactVersion } else { "$MinVersion-$MaxVersion" }
        Error = $errorMsg
        Path = $resolvedPath
    }
}

<#
.SYNOPSIS
    Creates a backup of a state file.

.DESCRIPTION
    Manages backup rotation for state files with timestamped backups.

.PARAMETER Path
    The state file path to backup.

.PARAMETER BackupCount
    Number of backups to retain. Default is 5.

.PARAMETER BackupDirectory
    Directory to store backups. Default is same as state file.

.OUTPUTS
    PSObject. Backup result with Success, BackupPath, RemovedBackups.
#>
function Backup-StateFile {
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path,
        
        [int]$BackupCount = 5,
        
        [string]$BackupDirectory = ""
    )

    $resolvedPath = Resolve-Path -Path $Path -ErrorAction SilentlyContinue
    if (-not $resolvedPath) {
        $resolvedPath = $Path
    }

    if (-not (Test-Path -LiteralPath $resolvedPath)) {
        return [pscustomobject]@{
            Success = $true
            BackupPath = $null
            RemovedBackups = @()
            Message = "Source file does not exist, no backup needed"
        }
    }

    $fileName = [System.IO.Path]::GetFileNameWithoutExtension($resolvedPath)
    
    if ([string]::IsNullOrWhiteSpace($BackupDirectory)) {
        $BackupDirectory = Split-Path -Parent $resolvedPath
    }

    if (-not (Test-Path -LiteralPath $BackupDirectory)) {
        New-Item -ItemType Directory -Path $BackupDirectory -Force | Out-Null
    }

    # Generate backup filename with timestamp
    $timestamp = [DateTime]::Now.ToString("yyyyMMddHHmmss")
    $backupName = "$fileName.$timestamp.bak"
    $backupPath = Join-Path $BackupDirectory $backupName

    try {
        Copy-Item -LiteralPath $resolvedPath -Destination $backupPath -Force

        # Clean up old backups
        $pattern = "$fileName.*.bak"
        $oldBackups = Get-ChildItem -Path $BackupDirectory -Filter $pattern -File |
            Sort-Object -Property LastWriteTime -Descending |
            Select-Object -Skip $BackupCount

        $removed = @()
        foreach ($old in $oldBackups) {
            try {
                Remove-Item -LiteralPath $old.FullName -Force
                $removed += $old.Name
            }
            catch {
                Write-Warning "Failed to remove old backup '$($old.Name)': $_"
            }
        }

        return [pscustomobject]@{
            Success = $true
            BackupPath = $backupPath
            RemovedBackups = $removed
            Message = "Backup created successfully"
        }
    }
    catch {
        throw "Failed to create state file backup: $_"
    }
}

<#
.SYNOPSIS
    Migrates a state file to a new schema version.

.DESCRIPTION
    Reads state in old format, applies migration function, writes in new format.
    Creates backup before migration and validates the result.

.PARAMETER Path
    The state file path.

.PARAMETER FromVersion
    Current version of the state file.

.PARAMETER ToVersion
    Target version after migration.

.PARAMETER MigrationScript
    Script block that transforms data from old to new format.

.PARAMETER ValidateScript
    Optional validation script for migrated data.

.PARAMETER BackupCount
    Number of backups to retain. Default is 5.

.OUTPUTS
    PSObject. Migration result with Success, OldVersion, NewVersion, BackupPath.

.EXAMPLE
    Migrate-StateFile -Path "state.json" -FromVersion 1 -ToVersion 2 -MigrationScript {
        param($oldData)
        return @{
            items = $oldData.list
            count = $oldData.list.Count
            migratedAt = Get-Date
        }
    }
#>
function Migrate-StateFile {
    [CmdletBinding(SupportsShouldProcess = $true)]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path,
        
        [Parameter(Mandatory = $true)]
        [int]$FromVersion,
        
        [Parameter(Mandatory = $true)]
        [int]$ToVersion,
        
        [Parameter(Mandatory = $true)]
        [scriptblock]$MigrationScript,
        
        [scriptblock]$ValidateScript = $null,
        
        [int]$BackupCount = 5
    )

    # Read current state
    $readResult = Read-StateFile -Path $Path -ExpectedVersion $FromVersion
    if (-not $readResult.Success) {
        return [pscustomobject]@{
            Success = $false
            Path = $Path
            OldVersion = $readResult.Version
            NewVersion = $ToVersion
            BackupPath = $null
            Error = "Failed to read state for migration: $($readResult.Error)"
        }
    }

    # Apply migration
    try {
        $migratedData = & $MigrationScript $readResult.Data
    }
    catch {
        return [pscustomobject]@{
            Success = $false
            Path = $Path
            OldVersion = $FromVersion
            NewVersion = $ToVersion
            BackupPath = $null
            Error = "Migration script failed: $_"
        }
    }

    # Validate migrated data if validator provided
    if ($null -ne $ValidateScript) {
        $validationResult = & $ValidateScript $migratedData
        if ($validationResult -ne $true) {
            return [pscustomobject]@{
                Success = $false
                Path = $Path
                OldVersion = $FromVersion
                NewVersion = $ToVersion
                BackupPath = $null
                Error = "Migration validation failed: $validationResult"
            }
        }
    }

    # WhatIf support
    if (-not $PSCmdlet.ShouldProcess($Path, "Migrate from v$FromVersion to v$ToVersion")) {
        return [pscustomobject]@{
            Success = $true
            Path = $Path
            OldVersion = $FromVersion
            NewVersion = $ToVersion
            BackupPath = $null
            WhatIf = $true
            Error = $null
        }
    }

    # Create pre-migration backup
    $backupResult = Backup-StateFile -Path $Path -BackupCount $BackupCount

    # Write migrated state
    try {
        $writeResult = Write-StateFile -Path $Path -Data $migratedData `
            -SchemaVersion $ToVersion -BackupCount 0  # Already backed up

        return [pscustomobject]@{
            Success = $true
            Path = $Path
            OldVersion = $FromVersion
            NewVersion = $ToVersion
            BackupPath = $backupResult.BackupPath
            Error = $null
        }
    }
    catch {
        return [pscustomobject]@{
            Success = $false
            Path = $Path
            OldVersion = $FromVersion
            NewVersion = $ToVersion
            BackupPath = $backupResult.BackupPath
            Error = "Failed to write migrated state: $_"
        }
    }
}

<#
.SYNOPSIS
    Lists all state files in a project.

.DESCRIPTION
    Returns information about all state files in the canonical state directory.

.PARAMETER ProjectRoot
    The project root directory. Defaults to current directory.

.PARAMETER IncludeBackups
    Include backup files in the results.

.OUTPUTS
    System.Object[]. Array of state file information objects.

.EXAMPLE
    Get-StateFiles | Format-Table Name, Version, LastModified
#>
function Get-StateFiles {
    [CmdletBinding()]
    [OutputType([array])]
    param(
        [string]$ProjectRoot = ".",
        
        [switch]$IncludeBackups
    )

    $stateDir = Get-StateDirectory -ProjectRoot $ProjectRoot
    
    if (-not (Test-Path -LiteralPath $stateDir)) {
        return @()
    }

    $filter = if ($IncludeBackups) { "*.json" } else { "*.json" }
    $files = Get-ChildItem -Path $stateDir -Filter $filter -File

    if (-not $IncludeBackups) {
        $files = $files | Where-Object { $_.Name -notmatch '\.\d{14}\.bak$' }
    }

    $results = @()
    foreach ($file in $files) {
        $info = Read-StateFile -Path $file.FullName
        $results += [pscustomobject]@{
            Name = $file.Name
            FullPath = $file.FullName
            Version = $info.Version
            Size = $file.Length
            LastModified = $file.LastWriteTime
            Schema = if ($info.Schema) { $info.Schema["name"] } else { $null }
            Exists = $info.Exists
            Valid = $info.Success
        }
    }

    return $results
}

<#
.SYNOPSIS
    Initializes a new state file with default values.

.DESCRIPTION
    Creates a new state file if it doesn't exist, with optional default data.

.PARAMETER Path
    The state file path.

.PARAMETER DefaultData
    Default data to write if file doesn't exist.

.PARAMETER SchemaVersion
    Schema version for the state file.

.PARAMETER SchemaName
    Schema name/type identifier.

.PARAMETER Overwrite
    Overwrite existing file (destructive).

.OUTPUTS
    PSObject. Result with Success, Created, Path, Version.

.EXAMPLE
    Initialize-StateFile -Path "sync-state.json" -DefaultData @{ status = "idle"; count = 0 } -SchemaVersion 1
#>
function Initialize-StateFile {
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path,
        
        [hashtable]$DefaultData = @{},
        
        [int]$SchemaVersion = 1,
        
        [string]$SchemaName = "",
        
        [switch]$Overwrite
    )

    $resolvedPath = Resolve-Path -Path $Path -ErrorAction SilentlyContinue
    if (-not $resolvedPath) {
        $resolvedPath = $Path
    }

    $exists = Test-Path -LiteralPath $resolvedPath

    if ($exists -and -not $Overwrite) {
        $readResult = Read-StateFile -Path $resolvedPath
        return [pscustomobject]@{
            Success = $true
            Created = $false
            Path = $resolvedPath
            Version = $readResult.Version
            Data = $readResult.Data
            Message = "State file already exists, not modified"
        }
    }

    $backupResult = $null
    if ($exists -and $Overwrite) {
        $backupResult = Backup-StateFile -Path $resolvedPath
    }

    try {
        $writeResult = Write-StateFile -Path $resolvedPath -Data $DefaultData `
            -SchemaVersion $SchemaVersion -SchemaName $SchemaName

        return [pscustomobject]@{
            Success = $true
            Created = $true
            Path = $resolvedPath
            Version = $SchemaVersion
            Data = $DefaultData
            BackupPath = if ($backupResult) { $backupResult.BackupPath } else { $null }
            Message = if ($exists) { "State file overwritten" } else { "State file created" }
        }
    }
    catch {
        return [pscustomobject]@{
            Success = $false
            Created = $false
            Path = $resolvedPath
            Version = 0
            Data = $null
            BackupPath = $null
            Message = "Failed to initialize state file: $_"
        }
    }
}

# Export all public functions
Export-ModuleMember -Function @(
    'Get-StateDirectory'
    'Get-StateFilePath'
    'Read-StateFile'
    'Write-StateFile'
    'Update-StateFile'
    'Test-StateVersion'
    'Backup-StateFile'
    'Migrate-StateFile'
    'Get-StateFiles'
    'Initialize-StateFile'
)
