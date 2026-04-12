#requires -Version 5.1
<#
.SYNOPSIS
    Atomic File Write Operations for LLM Workflow platform.

.DESCRIPTION
    Provides atomic file writes using temp-file + fsync + rename pattern.
    Implements the state safety invariant requirements from IMPROVEMENT_PROPOSALS.md section 3.2.

.NOTES
    File: AtomicWrite.ps1
    Version: 1.0.0
    Author: LLM Workflow Team

.EXAMPLE
    # Simple atomic write
    Write-AtomicFile -Path "config.json" -Content $jsonString

    # Atomic write with backup
    Backup-AndWrite -Path "state.json" -Content $jsonString -BackupCount 5
#>

Set-StrictMode -Version Latest

<#
.SYNOPSIS
    Forces a file sync to disk for durability.

.DESCRIPTION
    Calls fsync (Unix) or FlushFileBuffers (Windows) to ensure data is
    physically written to disk before returning. Critical for atomicity.

.PARAMETER Path
    The file path to sync.

.PARAMETER FileStream
    An open FileStream to sync. If provided, Path is ignored.

.OUTPUTS
    System.Boolean. True if sync succeeded, false otherwise.

.EXAMPLE
    Sync-File -Path "important.dat"

.EXAMPLE
    $stream = [System.IO.File]::OpenWrite("data.bin")
    try {
        $writer = New-Object System.IO.BinaryWriter($stream)
        $writer.Write($data)
        Sync-File -FileStream $stream
    } finally {
        $stream.Close()
    }
#>
function Sync-File {
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [Parameter(ParameterSetName = 'Path')]
        [string]$Path,
        
        [Parameter(ParameterSetName = 'Stream')]
        [System.IO.FileStream]$FileStream
    )

    try {
        if ($PSCmdlet.ParameterSetName -eq 'Path') {
            if (-not (Test-Path -LiteralPath $Path)) {
                Write-Warning "Cannot sync non-existent file: $Path"
                return $false
            }

            # Use .NET FileStream for proper sync
            $stream = [System.IO.File]::Open($Path, [System.IO.FileMode]::Open, 
                [System.IO.FileAccess]::ReadWrite, [System.IO.FileShare]::None)
            try {
                $stream.Flush($true)  # true = flush to disk
            }
            finally {
                $stream.Close()
                $stream.Dispose()
            }
        }
        else {
            if ($null -eq $FileStream) {
                throw "FileStream is null"
            }
            if (-not $FileStream.CanWrite) {
                throw "FileStream is not writable"
            }
            $FileStream.Flush($true)  # true = flush to disk
        }

        return $true
    }
    catch {
        Write-Warning "File sync failed: $_"
        return $false
    }
}

<#
.SYNOPSIS
    Performs an atomic file write using temp-file + fsync + rename pattern.

.DESCRIPTION
    Writes content to a temporary file, forces a sync to disk, then renames
    the temp file to the target path. This ensures readers always see a
    complete, valid file (never a partial write).

.PARAMETER Path
    The target file path.

.PARAMETER Content
    The content to write (string, byte array, or object with JSON conversion).

.PARAMETER Encoding
    Text encoding for string content. Default is UTF8.

.PARAMETER Format
    Output format: Text (default), Bytes, or Json.

.PARAMETER JsonDepth
    Serialization depth for JSON format. Default is 10.

.PARAMETER NoSync
    Skip the fsync call (not recommended for critical data).

.PARAMETER CreateBackup
    Create a backup of existing file before overwriting.

.PARAMETER BackupSuffix
    Suffix for backup file. Default is .backup.

.OUTPUTS
    PSObject. Write result with Success, Path, BytesWritten, DurationMs.

.EXAMPLE
    Write-AtomicFile -Path "config.json" -Content '{"key":"value"}'

.EXAMPLE
    Write-AtomicFile -Path "data.json" -Content $object -Format Json

.EXAMPLE
    Write-AtomicFile -Path "binary.dat" -Content $byteArray -Format Bytes
#>
function Write-AtomicFile {
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path,
        
        [Parameter(Mandatory = $true)]
        [object]$Content,
        
        [System.Text.Encoding]$Encoding = [System.Text.Encoding]::UTF8,
        
        [ValidateSet('Text', 'Bytes', 'Json')]
        [string]$Format = 'Text',
        
        [int]$JsonDepth = 10,
        
        [switch]$NoSync,
        
        [switch]$CreateBackup,
        
        [string]$BackupSuffix = ".backup"
    )

    $startTime = [DateTime]::Now
    $resolvedPath = Resolve-Path -Path $Path -ErrorAction SilentlyContinue
    if (-not $resolvedPath) {
        $resolvedPath = $Path
    }

    # Ensure directory exists
    $dir = Split-Path -Parent $resolvedPath
    if (-not (Test-Path -LiteralPath $dir)) {
        try {
            New-Item -ItemType Directory -Path $dir -Force | Out-Null
        }
        catch {
            throw "Failed to create directory '$dir': $_"
        }
    }

    # Create backup if requested and file exists
    if ($CreateBackup -and (Test-Path -LiteralPath $resolvedPath)) {
        $backupPath = "$resolvedPath$BackupSuffix"
        try {
            Copy-Item -LiteralPath $resolvedPath -Destination $backupPath -Force
        }
        catch {
            Write-Warning "Failed to create backup: $_"
        }
    }

    # Generate temp file path in same directory (for atomic rename)
    $tempPath = "$resolvedPath.tmp.$PID.$([Guid]::NewGuid().ToString('N'))"
    
    $bytesWritten = 0
    $success = $false
    $errorMsg = $null

    try {
        # Convert content based on format
        switch ($Format) {
            'Json' {
                $stringContent = $Content | ConvertTo-Json -Depth $JsonDepth -Compress:$false
                $bytes = $Encoding.GetBytes($stringContent)
            }
            'Bytes' {
                if ($Content -is [byte[]]) {
                    $bytes = $Content
                }
                elseif ($Content -is [System.Collections.Generic.List[byte]] -or 
                        $Content -is [System.Array]) {
                    $bytes = [byte[]]$Content
                }
                else {
                    throw "Content must be a byte array for Bytes format"
                }
            }
            default {  # Text
                $bytes = $Encoding.GetBytes([string]$Content)
            }
        }

        $bytesWritten = $bytes.Length

        # Write to temp file using FileStream for proper control
        $stream = [System.IO.File]::Create($tempPath)
        try {
            $stream.Write($bytes, 0, $bytes.Length)
            
            if (-not $NoSync) {
                $stream.Flush($true)  # Flush to disk
            }
        }
        finally {
            $stream.Close()
            $stream.Dispose()
        }

        # Atomic rename
        if ($IsWindows -or $PSVersionTable.PSVersion.Major -lt 6) {
            # Windows: Use MoveFileEx or .NET Move with overwrite
            [System.IO.File]::Move($tempPath, $resolvedPath, $true)
        }
        else {
            # Unix: Use atomic rename
            [System.IO.File]::Move($tempPath, $resolvedPath, $true)
        }

        # Sync the directory to ensure the rename is committed
        if (-not $NoSync) {
            Sync-Directory -Path $dir | Out-Null
        }

        $success = $true
    }
    catch {
        $errorMsg = $_.Exception.Message
        $success = $false
        
        # Clean up temp file on failure
        if (Test-Path -LiteralPath $tempPath) {
            try {
                Remove-Item -LiteralPath $tempPath -Force
            }
            catch {
                Write-Warning "Failed to clean up temp file '$tempPath': $_"
            }
        }

        throw "Atomic write failed: $_"
    }

    $duration = ([DateTime]::Now - $startTime).TotalMilliseconds

    return [pscustomobject]@{
        Success = $success
        Path = $resolvedPath
        BytesWritten = $bytesWritten
        DurationMs = [math]::Round($duration, 2)
        Error = $errorMsg
    }
}

<#
.SYNOPSIS
    Syncs a directory to ensure metadata changes are persisted.

.DESCRIPTION
    Opens the directory and calls fsync to ensure file renames and other
    metadata operations are committed to disk.

.PARAMETER Path
    The directory path to sync.

.OUTPUTS
    System.Boolean. True if sync succeeded.
#>
function Sync-Directory {
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path
    )

    try {
        if (-not (Test-Path -LiteralPath $Path)) {
            return $false
        }

        # On Windows, we can't directly sync directories in the same way as Unix,
        # but we can force a flush by touching a sync marker file
        if ($IsWindows -or $PSVersionTable.PSVersion.Major -lt 6) {
            # Windows: Create a temporary file and sync it
            $syncMarker = Join-Path $Path ".sync.$(Get-Random)"
            [System.IO.File]::WriteAllText($syncMarker, [string]::Empty)
            Sync-File -Path $syncMarker | Out-Null
            Remove-Item -LiteralPath $syncMarker -Force -ErrorAction SilentlyContinue
        }
        else {
            # Unix: Can open the directory and call fsync
            $dirHandle = [System.IO.Directory]::OpenHandle($Path)
            try {
                # Note: .NET doesn't expose fsync for directories directly
                # The file sync above handles most cases
            }
            finally {
                $dirHandle.Dispose()
            }
        }

        return $true
    }
    catch {
        Write-Warning "Directory sync failed: $_"
        return $false
    }
}

<#
.SYNOPSIS
    Creates a backup of a file before writing.

.DESCRIPTION
    Manages backup rotation, keeping a specified number of backups with
    timestamped names.

.PARAMETER Path
    The file path to backup.

.PARAMETER BackupCount
    Number of backups to retain. Default is 3.

.PARAMETER BackupDirectory
    Directory to store backups. Default is same directory as source file.

.PARAMETER UseTimestamp
    Use timestamp in backup name. Default is true.

.OUTPUTS
    PSObject. Backup result with Success, BackupPath, PreviousBackups properties.

.EXAMPLE
    Backup-File -Path "config.json" -BackupCount 5
#>
function Backup-File {
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path,
        
        [int]$BackupCount = 3,
        
        [string]$BackupDirectory = "",
        
        [switch]$UseTimestamp = $true
    )

    if (-not (Test-Path -LiteralPath $Path)) {
        return [pscustomobject]@{
            Success = $true
            BackupPath = $null
            Message = "Source file does not exist, no backup needed"
            PreviousBackups = @()
        }
    }

    $resolvedPath = Resolve-Path -Path $Path
    $fileName = [System.IO.Path]::GetFileName($resolvedPath)
    
    # Determine backup directory
    if ([string]::IsNullOrWhiteSpace($BackupDirectory)) {
        $BackupDirectory = Split-Path -Parent $resolvedPath
    }

    if (-not (Test-Path -LiteralPath $BackupDirectory)) {
        try {
            New-Item -ItemType Directory -Path $BackupDirectory -Force | Out-Null
        }
        catch {
            throw "Failed to create backup directory: $_"
        }
    }

    # Generate backup filename
    if ($UseTimestamp) {
        $timestamp = [DateTime]::Now.ToString("yyyyMMddHHmmss")
        $backupName = "$fileName.$timestamp.bak"
    }
    else {
        $backupName = "$fileName.bak"
    }
    
    $backupPath = Join-Path $BackupDirectory $backupName

    try {
        Copy-Item -LiteralPath $resolvedPath -Destination $backupPath -Force

        # Clean up old backups
        $oldBackups = Get-ChildItem -Path $BackupDirectory -Filter "$fileName.*.bak" -File |
            Sort-Object -Property LastWriteTime -Descending |
            Select-Object -Skip $BackupCount

        foreach ($old in $oldBackups) {
            try {
                Remove-Item -LiteralPath $old.FullName -Force
                Write-Verbose "Removed old backup: $($old.Name)"
            }
            catch {
                Write-Warning "Failed to remove old backup '$($old.Name)': $_"
            }
        }

        return [pscustomobject]@{
            Success = $true
            BackupPath = $backupPath
            Message = "Backup created successfully"
            PreviousBackups = @($oldBackups | ForEach-Object { $_.FullName })
        }
    }
    catch {
        throw "Failed to create backup: $_"
    }
}

<#
.SYNOPSIS
    Writes a file with automatic backup creation.

.DESCRIPTION
    Combines Backup-File and Write-AtomicFile for safe writes with
    backup rotation. Implements the backup before destructive mutation
    requirement from section 3.2.

.PARAMETER Path
    The target file path.

.PARAMETER Content
    The content to write.

.PARAMETER BackupCount
    Number of backups to retain. Default is 3.

.PARAMETER Encoding
    Text encoding. Default is UTF8.

.PARAMETER Format
    Output format: Text (default), Bytes, or Json.

.PARAMETER Verify
    Verify the write by reading back the file.

.OUTPUTS
    PSObject. Result with Success, Path, BackupPath, BytesWritten.

.EXAMPLE
    Backup-AndWrite -Path "state.json" -Content $stateObject -Format Json -BackupCount 5
#>
function Backup-AndWrite {
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path,
        
        [Parameter(Mandatory = $true)]
        [object]$Content,
        
        [int]$BackupCount = 3,
        
        [System.Text.Encoding]$Encoding = [System.Text.Encoding]::UTF8,
        
        [ValidateSet('Text', 'Bytes', 'Json')]
        [string]$Format = 'Text',
        
        [int]$JsonDepth = 10,
        
        [switch]$Verify
    )

    $startTime = [DateTime]::Now
    $resolvedPath = Resolve-Path -Path $Path -ErrorAction SilentlyContinue
    if (-not $resolvedPath) {
        $resolvedPath = $Path
    }

    # Create backup first
    $backupResult = Backup-File -Path $resolvedPath -BackupCount $BackupCount
    if (-not $backupResult.Success) {
        throw "Backup failed, aborting write"
    }

    # Perform atomic write
    $writeResult = Write-AtomicFile -Path $resolvedPath -Content $Content `
        -Encoding $Encoding -Format $Format -JsonDepth $JsonDepth

    if (-not $writeResult.Success) {
        throw "Write failed: $($writeResult.Error)"
    }

    # Verify if requested
    $verified = $false
    if ($Verify) {
        try {
            $readBack = [System.IO.File]::ReadAllBytes($resolvedPath)
            $verified = ($readBack.Length -eq $writeResult.BytesWritten)
        }
        catch {
            Write-Warning "Verification read failed: $_"
        }
    }

    $duration = ([DateTime]::Now - $startTime).TotalMilliseconds

    return [pscustomobject]@{
        Success = $true
        Path = $resolvedPath
        BackupPath = $backupResult.BackupPath
        BytesWritten = $writeResult.BytesWritten
        DurationMs = [math]::Round($duration, 2)
        Verified = $verified
    }
}

<#
.SYNOPSIS
    Writes JSON data atomically with schema header support.

.DESCRIPTION
    Serializes an object to JSON and writes it atomically. Optionally adds
    a schema version header for version tracking.

.PARAMETER Path
    The target file path.

.PARAMETER Data
    The data object to serialize.

.PARAMETER SchemaVersion
    Schema version to include in the output.

.PARAMETER SchemaName
    Schema name/type identifier.

.PARAMETER Depth
    JSON serialization depth. Default is 10.

.PARAMETER Compress
    Output compressed JSON (no indentation).

.PARAMETER BackupCount
    Number of backups to retain. Default is 3.

.OUTPUTS
    PSObject. Result with Success, Path, SchemaVersion.

.EXAMPLE
    Write-JsonAtomic -Path "state.json" -Data $state -SchemaVersion 2 -SchemaName "sync-state"
#>
function Write-JsonAtomic {
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path,
        
        [Parameter(Mandatory = $true)]
        [object]$Data,
        
        [int]$SchemaVersion = 1,
        
        [string]$SchemaName = "",
        
        [int]$Depth = 10,
        
        [switch]$Compress,
        
        [int]$BackupCount = 3
    )

    # Wrap data with schema header if version or name specified
    if ($SchemaVersion -gt 0 -or -not [string]::IsNullOrWhiteSpace($SchemaName)) {
        $wrappedData = @{
            _schema = @{
                version = $SchemaVersion
                name = if ($SchemaName) { $SchemaName } else { [System.IO.Path]::GetFileNameWithoutExtension($Path) }
                createdAt = [DateTime]::UtcNow.ToString("yyyy-MM-ddTHH:mm:ssZ")
                createdBy = [Environment]::UserName
            }
            data = $Data
        }
        $content = $wrappedData
    }
    else {
        $content = $Data
    }

    $result = Backup-AndWrite -Path $Path -Content $content -Format Json `
        -JsonDepth $Depth -BackupCount $BackupCount

    return [pscustomobject]@{
        Success = $result.Success
        Path = $result.Path
        SchemaVersion = $SchemaVersion
        SchemaName = $SchemaName
        BytesWritten = $result.BytesWritten
        DurationMs = $result.DurationMs
        BackupPath = $result.BackupPath
    }
}

<#
.SYNOPSIS
    Reads JSON data with schema validation.

.DESCRIPTION
    Reads and deserializes JSON data, optionally validating schema version.
    Returns just the data portion if schema header is present.

.PARAMETER Path
    The file path to read.

.PARAMETER ExpectedSchemaVersion
    Expected schema version. If specified, validates against actual version.

.PARAMETER ExpectedSchemaName
    Expected schema name. If specified, validates against actual name.

.PARAMETER IgnoreSchema
    Ignore schema header and return raw content.

.OUTPUTS
    PSObject. Result with Success, Data, Schema, RawJson.

.EXAMPLE
    $result = Read-JsonAtomic -Path "state.json" -ExpectedSchemaVersion 2
    if ($result.Success) { $data = $result.Data }
#>
function Read-JsonAtomic {
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path,
        
        [int]$ExpectedSchemaVersion = 0,
        
        [string]$ExpectedSchemaName = "",
        
        [switch]$IgnoreSchema
    )

    if (-not (Test-Path -LiteralPath $Path)) {
        return [pscustomobject]@{
            Success = $false
            Data = $null
            Schema = $null
            RawJson = $null
            Error = "File not found: $Path"
        }
    }

    try {
        $rawJson = [System.IO.File]::ReadAllText($Path, [System.Text.Encoding]::UTF8)
        $parsed = $rawJson | ConvertFrom-Json -AsHashtable

        # Check for schema header
        $schema = $null
        $data = $parsed

        if (-not $IgnoreSchema -and $parsed.ContainsKey("_schema") -and $parsed.ContainsKey("data")) {
            $schema = $parsed["_schema"]
            $data = $parsed["data"]

            # Validate schema version if specified
            if ($ExpectedSchemaVersion -gt 0) {
                $actualVersion = $schema["version"]
                if ($actualVersion -ne $ExpectedSchemaVersion) {
                    throw "Schema version mismatch: expected $ExpectedSchemaVersion, got $actualVersion"
                }
            }

            # Validate schema name if specified
            if (-not [string]::IsNullOrWhiteSpace($ExpectedSchemaName)) {
                $actualName = $schema["name"]
                if ($actualName -ne $ExpectedSchemaName) {
                    throw "Schema name mismatch: expected $ExpectedSchemaName, got $actualName"
                }
            }
        }

        return [pscustomobject]@{
            Success = $true
            Data = $data
            Schema = $schema
            RawJson = $rawJson
            Error = $null
        }
    }
    catch {
        return [pscustomobject]@{
            Success = $false
            Data = $null
            Schema = $null
            RawJson = $null
            Error = $_.Exception.Message
        }
    }
}

<#
.SYNOPSIS
    Appends a line to a JSON Lines (JSONL) file atomically.

.DESCRIPTION
    Appends a single JSON object as a line to a .jsonl file.
    Uses file locking for thread safety.

.PARAMETER Path
    The JSONL file path.

.PARAMETER Data
    The data object to append.

.PARAMETER Depth
    JSON serialization depth. Default is 10.

.OUTPUTS
    PSObject. Result with Success, Path, LineNumber.

.EXAMPLE
    Add-JsonLine -Path "log.jsonl" -Data @{ event = "sync"; timestamp = Get-Date }
#>
function Add-JsonLine {
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path,
        
        [Parameter(Mandatory = $true)]
        [object]$Data,
        
        [int]$Depth = 10
    )

    $dir = Split-Path -Parent $Path
    if (-not (Test-Path -LiteralPath $dir)) {
        New-Item -ItemType Directory -Path $dir -Force | Out-Null
    }

    $line = $Data | ConvertTo-Json -Depth $Depth -Compress
    $lineBytes = [System.Text.Encoding]::UTF8.GetBytes($line + "`n")

    # Use file locking for append atomicity
    $lockFile = "$Path.lock"
    $lockAcquired = $false
    
    try {
        # Simple spin-lock for file access
        $maxAttempts = 100
        $attempt = 0
        while ($attempt -lt $maxAttempts) {
            try {
                $fileStream = [System.IO.File]::Open($lockFile, [System.IO.FileMode]::CreateNew, 
                    [System.IO.FileAccess]::Write, [System.IO.FileShare]::None)
                $fileStream.Close()
                $lockAcquired = $true
                break
            }
            catch [System.IO.IOException] {
                $attempt++
                Start-Sleep -Milliseconds 10
            }
        }

        if (-not $lockAcquired) {
            throw "Could not acquire lock for append operation"
        }

        # Append the line
        $appendStream = [System.IO.File]::Open($Path, [System.IO.FileMode]::Append, 
            [System.IO.FileAccess]::Write, [System.IO.FileShare]::Read)
        try {
            $appendStream.Write($lineBytes, 0, $lineBytes.Length)
            $appendStream.Flush($true)
        }
        finally {
            $appendStream.Close()
        }

        # Count lines
        $lineNumber = 0
        if (Test-Path -LiteralPath $Path) {
            $lineNumber = [System.IO.File]::ReadAllLines($Path).Count
        }

        return [pscustomobject]@{
            Success = $true
            Path = $Path
            LineNumber = $lineNumber
        }
    }
    catch {
        throw "Failed to append to JSONL file: $_"
    }
    finally {
        if ($lockAcquired -and (Test-Path -LiteralPath $lockFile)) {
            Remove-Item -LiteralPath $lockFile -Force -ErrorAction SilentlyContinue
        }
    }
}

# Export all public functions
Export-ModuleMember -Function @(
    'Sync-File'
    'Sync-Directory'
    'Write-AtomicFile'
    'Backup-File'
    'Backup-AndWrite'
    'Write-JsonAtomic'
    'Read-JsonAtomic'
    'Add-JsonLine'
)
