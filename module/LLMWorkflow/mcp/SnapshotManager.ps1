#requires -Version 5.1
<#
.SYNOPSIS
    Snapshot Import/Export Manager for LLM Workflow platform.

.DESCRIPTION
    Implements Phase 7 snapshot functionality for backup, migration, and sharing
    of complete pack states between environments. Supports compression, encryption,
    integrity verification, and streaming for large snapshots.

.NOTES
    File: SnapshotManager.ps1
    Version: 1.0.0
    Author: LLM Workflow Team
    Phase: 7 - Snapshots Import/Export

.SUPPORTED_FORMATS
    - JSON: Plain JSON snapshot manifest and data
    - ZIP: Compressed archive containing snapshot components
    - Encrypted: AES-256 encrypted snapshots for sensitive data

.EXAMPLE
    # Create and export a pack snapshot
    $snapshot = New-PackSnapshot -PackId "godot-engine" -Path "./packs"
    Export-PackSnapshot -Snapshot $snapshot -OutputPath "backup.zip" -Format Zip

.EXAMPLE
    # Import and restore a snapshot
    $imported = Import-PackSnapshot -Path "backup.zip"
    Restore-FromSnapshot -Snapshot $imported -TargetPath "./restored"

.LINK
    LLMWorkflow_Canonical_Document_Set_Part_1_Core_Architecture_and_Operations.md
#>

Set-StrictMode -Version Latest

# Module-level constants
$script:SnapshotSchemaVersion = "1.0"
$script:SnapshotTypes = @('pack', 'workspace', 'incremental')
$script:CompressionLevels = @('Optimal', 'Fastest', 'NoCompression')
$script:DefaultCompressionLevel = 'Optimal'
$script:EncryptionAlgorithm = "AES"
$script:HashAlgorithm = "SHA256"

# ============================================================================
# Internal Helper Functions
# ============================================================================

<#
.SYNOPSIS
    Generates a unique snapshot ID.

.DESCRIPTION
    Creates a unique identifier for snapshots with format 'snap-<timestamp>-<random>'.

.OUTPUTS
    System.String. The generated snapshot ID.
#>
function New-SnapshotId {
    [CmdletBinding()]
    [OutputType([string])]
    param()

    $timestamp = [DateTime]::UtcNow.ToString("yyyyMMddHHmmss")
    $randomHex = (Get-Random -Minimum 0 -Maximum 268435455).ToString("x8")
    $hostName = $(if ($env:COMPUTERNAME) { $env:COMPUTERNAME } else { "unknown" }).ToLowerInvariant()
    return "snap-$timestamp-$randomHex-$hostName"
}

<#
.SYNOPSIS
    Computes SHA256 checksums for files in a directory.

.DESCRIPTION
    Calculates SHA256 hashes for all files in the specified path recursively.

.PARAMETER Path
    The root directory to scan.

.PARAMETER ExcludePatterns
    Array of glob patterns to exclude from checksum calculation.

.OUTPUTS
    System.Collections.Hashtable. Dictionary of relative paths to checksums.
#>
function Get-DirectoryChecksums {
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path,

        [string[]]$ExcludePatterns = @('*.tmp', '*.lock', '.git*', 'node_modules', '__pycache__', '.llm-workflow/state/*.lock')
    )

    if (-not (Test-Path -LiteralPath $Path)) {
        return @{}
    }

    $checksums = @{}
    $resolvedPath = Resolve-Path -Path $Path

    $files = Get-ChildItem -Path $Path -File -Recurse | Where-Object {
        $file = $_
        $exclude = $false
        foreach ($pattern in $ExcludePatterns) {
            if ($file.Name -like $pattern -or $file.FullName -like "*$pattern*") {
                $exclude = $true
                break
            }
        }
        -not $exclude
    }

    foreach ($file in $files) {
        try {
            $relativePath = $file.FullName.Substring($resolvedPath.Path.Length).TrimStart('\', '/')
            $stream = [System.IO.File]::OpenRead($file.FullName)
            try {
                $sha256 = [System.Security.Cryptography.SHA256]::Create()
                $hashBytes = $sha256.ComputeHash($stream)
                $hashString = [BitConverter]::ToString($hashBytes).Replace("-", "").ToLowerInvariant()
                $checksums[$relativePath] = $hashString
            }
            finally {
                $stream.Close()
                $stream.Dispose()
                $sha256.Dispose()
            }
        }
        catch {
            Write-Warning "Failed to compute checksum for '$($file.FullName)': $_"
        }
    }

    return $checksums
}

<#
.SYNOPSIS
    Verifies checksums against current files.

.DESCRIPTION
    Validates that files match their expected checksums.

.PARAMETER Path
    The root directory to verify.

.PARAMETER Checksums
    Hashtable of relative paths to expected checksums.

.OUTPUTS
    PSObject. Verification result with Valid, Mismatches, and Missing arrays.
#>
function Test-DirectoryChecksums {
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path,

        [Parameter(Mandatory = $true)]
        [hashtable]$Checksums
    )

    $valid = @()
    $mismatches = @()
    $missing = @()

    foreach ($relativePath in $Checksums.Keys) {
        $fullPath = Join-Path -Path $Path -ChildPath $relativePath

        if (-not (Test-Path -LiteralPath $fullPath)) {
            $missing += $relativePath
            continue
        }

        try {
            $stream = [System.IO.File]::OpenRead($fullPath)
            try {
                $sha256 = [System.Security.Cryptography.SHA256]::Create()
                $hashBytes = $sha256.ComputeHash($stream)
                $actualHash = [BitConverter]::ToString($hashBytes).Replace("-", "").ToLowerInvariant()

                if ($actualHash -eq $Checksums[$relativePath]) {
                    $valid += $relativePath
                }
                else {
                    $mismatches += @{
                        Path = $relativePath
                        Expected = $Checksums[$relativePath]
                        Actual = $actualHash
                    }
                }
            }
            finally {
                $stream.Close()
                $stream.Dispose()
                $sha256.Dispose()
            }
        }
        catch {
            $mismatches += @{
                Path = $relativePath
                Expected = $Checksums[$relativePath]
                Actual = "ERROR: $_"
            }
        }
    }

    return [pscustomobject]@{
        Valid = $valid
        ValidCount = $valid.Count
        Mismatches = $mismatches
        MismatchCount = $mismatches.Count
        Missing = $missing
        MissingCount = $missing.Count
        IsValid = ($mismatches.Count -eq 0 -and $missing.Count -eq 0)
    }
}

<#
.SYNOPSIS
    Derives an AES key from a password using PBKDF2.

.DESCRIPTION
    Creates a 256-bit AES key from a password and salt using PBKDF2-HMAC-SHA256.

.PARAMETER Password
    The password to derive the key from.

.PARAMETER Salt
    The salt bytes. If not provided, generates random salt.

.PARAMETER Iterations
    Number of PBKDF2 iterations. Default is 10000.

.OUTPUTS
    PSObject. Object with Key, Salt, and Iterations.
#>
function Derive-EncryptionKey {
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Password,

        [byte[]]$Salt,

        [int]$Iterations = 10000
    )

    if (-not $Salt) {
        $Salt = New-Object byte[] 32
        $rng = [System.Security.Cryptography.RandomNumberGenerator]::Create()
        try {
            $rng.GetBytes($Salt)
        }
        finally {
            $rng.Dispose()
        }
    }

    $pbkdf2 = New-Object System.Security.Cryptography.Rfc2898DeriveBytes($Password, $Salt, $Iterations, [System.Security.Cryptography.HashAlgorithmName]::SHA256)
    try {
        $key = $pbkdf2.GetBytes(32)  # 256 bits

        return [pscustomobject]@{
            Key = $key
            Salt = $Salt
            Iterations = $Iterations
        }
    }
    finally {
        $pbkdf2.Dispose()
    }
}

<#
.SYNOPSIS
    Gets the snapshot storage directory path.

.DESCRIPTION
    Returns the path to the snapshots storage directory, creating it if needed.

.PARAMETER ProjectRoot
    The project root directory.

.OUTPUTS
    System.String. The snapshot storage path.
#>
function Get-SnapshotStoragePath {
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [string]$ProjectRoot = "."
    )

    $resolvedRoot = Resolve-Path -Path $ProjectRoot -ErrorAction SilentlyContinue
    if (-not $resolvedRoot) {
        $resolvedRoot = $ProjectRoot
    }

    $storagePath = Join-Path $resolvedRoot ".llm-workflow/snapshots"

    if (-not (Test-Path -LiteralPath $storagePath)) {
        try {
            New-Item -ItemType Directory -Path $storagePath -Force | Out-Null
        }
        catch {
            throw "Failed to create snapshot storage directory: $storagePath. Error: $_"
        }
    }

    return $storagePath
}

<#
.SYNOPSIS
    Copies directory contents with progress tracking.

.DESCRIPTION
    Recursively copies directory contents with optional progress reporting.

.PARAMETER Source
    Source directory.

.PARAMETER Destination
    Destination directory.

.PARAMETER ExcludePatterns
    Patterns to exclude.

.OUTPUTS
    PSObject. Copy statistics.
#>
function Copy-DirectoryWithProgress {
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Source,

        [Parameter(Mandatory = $true)]
        [string]$Destination,

        [string[]]$ExcludePatterns = @()
    )

    if (-not (Test-Path -LiteralPath $Source)) {
        throw "Source directory not found: $Source"
    }

    if (-not (Test-Path -LiteralPath $Destination)) {
        New-Item -ItemType Directory -Path $Destination -Force | Out-Null
    }

    $files = Get-ChildItem -Path $Source -File -Recurse | Where-Object {
        $file = $_
        $exclude = $false
        foreach ($pattern in $ExcludePatterns) {
            if ($file.Name -like $pattern -or $file.FullName -like "*$pattern*") {
                $exclude = $true
                break
            }
        }
        -not $exclude
    }

    $copied = 0
    $errors = 0
    $totalBytes = 0

    foreach ($file in $files) {
        try {
            $relativePath = $file.FullName.Substring((Resolve-Path $Source).Path.Length).TrimStart('\', '/')
            $destPath = Join-Path $Destination $relativePath
            $destDir = Split-Path -Parent $destPath

            if (-not (Test-Path -LiteralPath $destDir)) {
                New-Item -ItemType Directory -Path $destDir -Force | Out-Null
            }

            Copy-Item -LiteralPath $file.FullName -Destination $destPath -Force
            $copied++
            $totalBytes += $file.Length
        }
        catch {
            $errors++
            Write-Warning "Failed to copy '$($file.FullName)': $_"
        }
    }

    return [pscustomobject]@{
        FilesCopied = $copied
        FilesFailed = $errors
        TotalBytes = $totalBytes
    }
}

# ============================================================================
# Snapshot Creation Functions
# ============================================================================

<#
.SYNOPSIS
    Creates a snapshot of the current pack state.

.DESCRIPTION
    Captures a complete snapshot of a pack including manifest, lockfile,
    annotations, and source registry information.

.PARAMETER PackId
    The pack identifier.

.PARAMETER PackPath
    Path to the pack directory.

.PARAMETER SnapshotId
    Optional custom snapshot ID. If not provided, one will be generated.

.PARAMETER Annotations
    Optional annotations to include with the snapshot.

.PARAMETER ProjectRoot
    The project root directory.

.OUTPUTS
    PSObject. The snapshot object with manifest and metadata.

.EXAMPLE
    $snapshot = New-PackSnapshot -PackId "godot-engine" -PackPath "./packs/godot-engine"
#>
function New-PackSnapshot {
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory = $true)]
        [string]$PackId,

        [Parameter(Mandatory = $true)]
        [string]$PackPath,

        [string]$SnapshotId = "",

        [hashtable]$Annotations = @{},

        [string]$ProjectRoot = "."
    )

    if (-not (Test-Path -LiteralPath $PackPath)) {
        throw "Pack path not found: $PackPath"
    }

    $resolvedPath = Resolve-Path -Path $PackPath
    $snapshotId = if ($SnapshotId) { $SnapshotId } else { New-SnapshotId }
    $createdAt = [DateTime]::UtcNow.ToString("yyyy-MM-ddTHH:mm:ssZ")
    $createdBy = "$env:USERNAME@$env:COMPUTERNAME"

    # Load lockfile if exists
    $lockfile = $null
    $lockfilePath = Join-Path $resolvedPath "pack.lock.json"
    if (Test-Path -LiteralPath $lockfilePath) {
        try {
            $lockfile = Get-Content -LiteralPath $lockfilePath -Raw | ConvertFrom-Json -AsHashtable
        }
        catch {
            Write-Warning "Failed to load lockfile: $_"
        }
    }

    # Load registry info if exists
    $registry = @{}
    $registryPath = Join-Path $resolvedPath "registry.json"
    if (Test-Path -LiteralPath $registryPath) {
        try {
            $registry = Get-Content -LiteralPath $registryPath -Raw | ConvertFrom-Json -AsHashtable
        }
        catch {
            Write-Warning "Failed to load registry: $_"
        }
    }

    # Calculate checksums
    $checksums = Get-DirectoryChecksums -Path $resolvedPath

    # Build manifest
    $manifest = @{
        snapshotVersion = $script:SnapshotSchemaVersion
        createdAt = $createdAt
        createdBy = $createdBy
        snapshotId = $snapshotId
        type = "pack"
        packId = $PackId
        packVersion = if ($lockfile) { $lockfile.packVersion } else { "unknown" }
        sourcePath = $resolvedPath.Path
        sourceRegistry = $registry
        lockfile = $lockfile
        annotations = $Annotations
        checksums = $checksums
        fileCount = $checksums.Count
        metadata = @{
            hostName = $env:COMPUTERNAME
            hostUser = $env:USERNAME
            powershellVersion = $PSVersionTable.PSVersion.ToString()
            platform = [System.Environment]::OSVersion.Platform.ToString()
        }
    }

    Write-Verbose "Created pack snapshot $snapshotId for pack '$PackId' with $($checksums.Count) files"

    return [pscustomobject]@{
        SnapshotId = $snapshotId
        Manifest = $manifest
        PackPath = $resolvedPath.Path
        CreatedAt = $createdAt
        Type = "pack"
    }
}

<#
.SYNOPSIS
    Creates a snapshot of the entire workspace.

.DESCRIPTION
    Captures a complete snapshot of the workspace including all packs,
    configuration, and state.

.PARAMETER WorkspacePath
    Path to the workspace directory.

.PARAMETER IncludePacks
    Array of pack IDs to include. If empty, includes all packs.

.PARAMETER ExcludePacks
    Array of pack IDs to exclude.

.PARAMETER IncludeState
    Include workspace state files.

.PARAMETER ProjectRoot
    The project root directory.

.OUTPUTS
    PSObject. The workspace snapshot object.

.EXAMPLE
    $snapshot = New-WorkspaceSnapshot -WorkspacePath "." -IncludeState
#>
function New-WorkspaceSnapshot {
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory = $true)]
        [string]$WorkspacePath,

        [string[]]$IncludePacks = @(),

        [string[]]$ExcludePacks = @(),

        [switch]$IncludeState,

        [string]$ProjectRoot = "."
    )

    if (-not (Test-Path -LiteralPath $WorkspacePath)) {
        throw "Workspace path not found: $WorkspacePath"
    }

    $resolvedPath = Resolve-Path -Path $WorkspacePath
    $snapshotId = New-SnapshotId
    $createdAt = [DateTime]::UtcNow.ToString("yyyy-MM-ddTHH:mm:ssZ")
    $createdBy = "$env:USERNAME@$env:COMPUTERNAME"

    # Discover packs
    $packsDir = Join-Path $resolvedPath "packs"
    $packSnapshots = @()

    if (Test-Path -LiteralPath $packsDir) {
        $packDirs = Get-ChildItem -Path $packsDir -Directory

        foreach ($packDir in $packDirs) {
            $packId = $packDir.Name

            # Apply include/exclude filters
            if ($IncludePacks.Count -gt 0 -and $IncludePacks -notcontains $packId) {
                continue
            }
            if ($ExcludePacks -contains $packId) {
                continue
            }

            try {
                $packSnapshot = New-PackSnapshot -PackId $packId -PackPath $packDir.FullName -ProjectRoot $ProjectRoot
                $packSnapshots += $packSnapshot
                Write-Verbose "Added pack '$packId' to workspace snapshot"
            }
            catch {
                Write-Warning "Failed to snapshot pack '$packId': $_"
            }
        }
    }

    # Capture workspace configuration
    $config = @{}
    $configFiles = @('llm-workflow.json', 'workspace.json', '.llm-workflow/config.json')
    foreach ($configFile in $configFiles) {
        $configPath = Join-Path $resolvedPath $configFile
        if (Test-Path -LiteralPath $configPath) {
            try {
                $config = Get-Content -LiteralPath $configPath -Raw | ConvertFrom-Json -AsHashtable
                break
            }
            catch {
                Write-Verbose "Failed to load config from $configFile"
            }
        }
    }

    # Calculate workspace-wide checksums
    $checksums = Get-DirectoryChecksums -Path $resolvedPath -ExcludePatterns @('*.tmp', '*.lock', '.git*', 'node_modules', '__pycache__', '.llm-workflow/snapshots/*')

    # Include state if requested
    $state = @{}
    if ($IncludeState) {
        $stateDir = Join-Path $resolvedPath ".llm-workflow/state"
        if (Test-Path -LiteralPath $stateDir) {
            $stateFiles = Get-ChildItem -Path $stateDir -File -Filter "*.json"
            foreach ($stateFile in $stateFiles) {
                try {
                    $stateContent = Get-Content -LiteralPath $stateFile.FullName -Raw | ConvertFrom-Json -AsHashtable
                    $state[$stateFile.Name] = $stateContent
                }
                catch {
                    Write-Verbose "Failed to load state file: $($stateFile.Name)"
                }
            }
        }
    }

    # Build manifest
    $manifest = @{
        snapshotVersion = $script:SnapshotSchemaVersion
        createdAt = $createdAt
        createdBy = $createdBy
        snapshotId = $snapshotId
        type = "workspace"
        workspacePath = $resolvedPath.Path
        packCount = $packSnapshots.Count
        packs = $packSnapshots | ForEach-Object { $_.Manifest }
        config = $config
        state = $state
        checksums = $checksums
        fileCount = $checksums.Count
        metadata = @{
            hostName = $env:COMPUTERNAME
            hostUser = $env:USERNAME
            powershellVersion = $PSVersionTable.PSVersion.ToString()
            platform = [System.Environment]::OSVersion.Platform.ToString()
        }
    }

    Write-Verbose "Created workspace snapshot $snapshotId with $($packSnapshots.Count) packs"

    return [pscustomobject]@{
        SnapshotId = $snapshotId
        Manifest = $manifest
        WorkspacePath = $resolvedPath.Path
        PackSnapshots = $packSnapshots
        CreatedAt = $createdAt
        Type = "workspace"
    }
}

<#
.SYNOPSIS
    Creates an incremental (delta) snapshot from a previous snapshot.

.DESCRIPTION
    Creates a snapshot containing only changes since a base snapshot.
    Useful for efficient backups and transfers.

.PARAMETER BaseSnapshot
    The base snapshot to compare against.

.PARAMETER CurrentPath
    Path to the current state to snapshot.

.PARAMETER PackId
    The pack identifier.

.PARAMETER ProjectRoot
    The project root directory.

.OUTPUTS
    PSObject. The incremental snapshot object.

.EXAMPLE
    $incremental = New-IncrementalSnapshot -BaseSnapshot $base -CurrentPath "./packs/godot-engine" -PackId "godot-engine"
#>
function New-IncrementalSnapshot {
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory = $true)]
        [pscustomobject]$BaseSnapshot,

        [Parameter(Mandatory = $true)]
        [string]$CurrentPath,

        [Parameter(Mandatory = $true)]
        [string]$PackId,

        [string]$ProjectRoot = "."
    )

    if (-not (Test-Path -LiteralPath $CurrentPath)) {
        throw "Current path not found: $CurrentPath"
    }

    $resolvedPath = Resolve-Path -Path $CurrentPath
    $snapshotId = New-SnapshotId
    $createdAt = [DateTime]::UtcNow.ToString("yyyy-MM-ddTHH:mm:ssZ")
    $createdBy = "$env:USERNAME@$env:COMPUTERNAME"

    # Calculate current checksums
    $currentChecksums = Get-DirectoryChecksums -Path $resolvedPath

    # Compare with base checksums
    $baseChecksums = $BaseSnapshot.Manifest.checksums
    $added = @()
    $modified = @()
    $removed = @()
    $unchanged = @()

    # Find added and modified files
    foreach ($file in $currentChecksums.Keys) {
        if (-not $baseChecksums.ContainsKey($file)) {
            $added += $file
        }
        elseif ($currentChecksums[$file] -ne $baseChecksums[$file]) {
            $modified += $file
        }
        else {
            $unchanged += $file
        }
    }

    # Find removed files
    foreach ($file in $baseChecksums.Keys) {
        if (-not $currentChecksums.ContainsKey($file)) {
            $removed += $file
        }
    }

    # Load lockfile if exists
    $lockfile = $null
    $lockfilePath = Join-Path $resolvedPath "pack.lock.json"
    if (Test-Path -LiteralPath $lockfilePath) {
        try {
            $lockfile = Get-Content -LiteralPath $lockfilePath -Raw | ConvertFrom-Json -AsHashtable
        }
        catch {
            Write-Warning "Failed to load lockfile: $_"
        }
    }

    # Build delta manifest
    $delta = @{
        baseSnapshotId = $BaseSnapshot.SnapshotId
        addedFiles = $added
        modifiedFiles = $modified
        removedFiles = $removed
        unchangedFiles = $unchanged
        addedCount = $added.Count
        modifiedCount = $modified.Count
        removedCount = $removed.Count
    }

    # Build manifest
    $manifest = @{
        snapshotVersion = $script:SnapshotSchemaVersion
        createdAt = $createdAt
        createdBy = $createdBy
        snapshotId = $snapshotId
        type = "incremental"
        packId = $PackId
        sourcePath = $resolvedPath.Path
        delta = $delta
        checksums = $currentChecksums
        lockfile = $lockfile
        metadata = @{
            hostName = $env:COMPUTERNAME
            hostUser = $env:USERNAME
            powershellVersion = $PSVersionTable.PSVersion.ToString()
            platform = [System.Environment]::OSVersion.Platform.ToString()
        }
    }

    Write-Verbose "Created incremental snapshot $snapshotId (added: $($added.Count), modified: $($modified.Count), removed: $($removed.Count))"

    return [pscustomobject]@{
        SnapshotId = $snapshotId
        Manifest = $manifest
        BaseSnapshotId = $BaseSnapshot.SnapshotId
        PackPath = $resolvedPath.Path
        CreatedAt = $createdAt
        Type = "incremental"
        Delta = $delta
    }
}

<#
.SYNOPSIS
    Gets the manifest from a snapshot.

.DESCRIPTION
    Extracts and returns the manifest metadata from a snapshot object
    or a snapshot file.

.PARAMETER Snapshot
    The snapshot object.

.PARAMETER Path
    Path to a snapshot file (JSON or ZIP).

.OUTPUTS
    PSObject. The snapshot manifest.

.EXAMPLE
    $manifest = Get-SnapshotManifest -Snapshot $snapshot

.EXAMPLE
    $manifest = Get-SnapshotManifest -Path "backup.zip"
#>
function Get-SnapshotManifest {
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(ParameterSetName = 'Object', Mandatory = $true)]
        [pscustomobject]$Snapshot,

        [Parameter(ParameterSetName = 'File', Mandatory = $true)]
        [string]$Path
    )

    if ($PSCmdlet.ParameterSetName -eq 'Object') {
        if ($Snapshot.Manifest) {
            return [pscustomobject]$Snapshot.Manifest
        }
        return $Snapshot
    }

    if (-not (Test-Path -LiteralPath $Path)) {
        throw "Snapshot file not found: $Path"
    }

    $resolvedPath = Resolve-Path -Path $Path
    $extension = [System.IO.Path]::GetExtension($resolvedPath.Path).ToLowerInvariant()

    if ($extension -eq '.json') {
        # Direct JSON file
        $content = Get-Content -LiteralPath $resolvedPath.Path -Raw
        $manifest = $content | ConvertFrom-Json -AsHashtable
        return [pscustomobject]$manifest
    }
    elseif ($extension -eq '.zip') {
        # ZIP archive - extract manifest
        try {
            Add-Type -AssemblyName System.IO.Compression.FileSystem
            $zip = [System.IO.Compression.ZipFile]::OpenRead($resolvedPath.Path)
            try {
                $manifestEntry = $zip.Entries | Where-Object { $_.Name -eq "manifest.json" } | Select-Object -First 1

                if (-not $manifestEntry) {
                    throw "Manifest not found in snapshot archive"
                }

                $stream = $manifestEntry.Open()
                try {
                    $reader = New-Object System.IO.StreamReader($stream)
                    $content = $reader.ReadToEnd()
                    $manifest = $content | ConvertFrom-Json -AsHashtable
                    return [pscustomobject]$manifest
                }
                finally {
                    $reader.Close()
                    $stream.Close()
                }
            }
            finally {
                $zip.Dispose()
            }
        }
        catch {
            throw "Failed to read snapshot manifest: $_"
        }
    }
    else {
        throw "Unsupported snapshot format: $extension"
    }
}

# ============================================================================
# Snapshot Export Functions
# ============================================================================

<#
.SYNOPSIS
    Exports a pack snapshot to a file.

.DESCRIPTION
    Exports a snapshot to JSON or ZIP format with optional compression
    and encryption.

.PARAMETER Snapshot
    The snapshot object to export.

.PARAMETER OutputPath
    The destination file path.

.PARAMETER Format
    Export format: Json or Zip.

.PARAMETER Compress
    Apply compression (ZIP format).

.PARAMETER Encrypt
    Encrypt the snapshot with AES-256.

.PARAMETER Password
    Encryption password (required if -Encrypt specified).

.PARAMETER IncludeSourceFiles
    Include actual source files in export (not just manifest).

.OUTPUTS
    PSObject. Export result with Path, Size, and Checksum.

.EXAMPLE
    Export-PackSnapshot -Snapshot $snapshot -OutputPath "backup.zip" -Format Zip -IncludeSourceFiles
#>
function Export-PackSnapshot {
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory = $true)]
        [pscustomobject]$Snapshot,

        [Parameter(Mandatory = $true)]
        [string]$OutputPath,

        [ValidateSet('Json', 'Zip')]
        [string]$Format = 'Zip',

        [switch]$Compress,

        [switch]$Encrypt,

        [string]$Password = "",

        [switch]$IncludeSourceFiles
    )

    if ($Encrypt -and [string]::IsNullOrWhiteSpace($Password)) {
        throw "Password is required when encryption is enabled"
    }

    # Ensure output directory exists
    $outputDir = Split-Path -Parent $OutputPath
    if ($outputDir -and -not (Test-Path -LiteralPath $outputDir)) {
        New-Item -ItemType Directory -Path $outputDir -Force | Out-Null
    }

    $tempDir = [System.IO.Path]::GetTempPath() + [Guid]::NewGuid().ToString("N")
    New-Item -ItemType Directory -Path $tempDir -Force | Out-Null

    try {
        # Write manifest
        $manifestPath = Join-Path $tempDir "manifest.json"
        $manifestJson = $Snapshot.Manifest | ConvertTo-Json -Depth 10
        [System.IO.File]::WriteAllText($manifestPath, $manifestJson, [System.Text.Encoding]::UTF8)

        # Include source files if requested
        if ($IncludeSourceFiles -and $Snapshot.PackPath) {
            $sourceDir = Join-Path $tempDir "source"
            New-Item -ItemType Directory -Path $sourceDir -Force | Out-Null
            Copy-DirectoryWithProgress -Source $Snapshot.PackPath -Destination $sourceDir -ExcludePatterns @('*.tmp', '*.lock')
        }

        if ($Format -eq 'Json') {
            # Export as JSON
            if ($Compress -or $Encrypt) {
                throw "JSON format does not support compression or encryption. Use Zip format."
            }

            Copy-Item -LiteralPath $manifestPath -Destination $OutputPath -Force
            $fileInfo = Get-Item -LiteralPath $OutputPath

            # Calculate checksum
            $stream = [System.IO.File]::OpenRead($OutputPath)
            try {
                $sha256 = [System.Security.Cryptography.SHA256]::Create()
                $hashBytes = $sha256.ComputeHash($stream)
                $checksum = [BitConverter]::ToString($hashBytes).Replace("-", "").ToLowerInvariant()
            }
            finally {
                $stream.Close()
                $sha256.Dispose()
            }

            return [pscustomobject]@{
                Success = $true
                Path = $OutputPath
                Format = 'Json'
                Size = $fileInfo.Length
                Checksum = $checksum
                SnapshotId = $Snapshot.SnapshotId
            }
        }
        else {
            # Export as ZIP
            Add-Type -AssemblyName System.IO.Compression.FileSystem

            if (Test-Path -LiteralPath $OutputPath) {
                Remove-Item -LiteralPath $OutputPath -Force
            }

            # Create ZIP
            $compressionLevel = [System.IO.Compression.CompressionLevel]::Optimal
            [System.IO.Compression.ZipFile]::CreateFromDirectory($tempDir, $OutputPath, $compressionLevel, $false)

            # Encrypt if requested
            if ($Encrypt) {
                $encryptedPath = "$OutputPath.enc"
                $keyData = Derive-EncryptionKey -Password $Password

                # Generate IV
                $iv = New-Object byte[] 16
                $rng = [System.Security.Cryptography.RandomNumberGenerator]::Create()
                try {
                    $rng.GetBytes($iv)
                }
                finally {
                    $rng.Dispose()
                }

                # Encrypt file
                $inputBytes = [System.IO.File]::ReadAllBytes($OutputPath)
                $aes = [System.Security.Cryptography.Aes]::Create()
                try {
                    $aes.Key = $keyData.Key
                    $aes.IV = $iv
                    $aes.Mode = [System.Security.Cryptography.CipherMode]::CBC
                    $aes.Padding = [System.Security.Cryptography.PaddingMode]::PKCS7

                    $encryptor = $aes.CreateEncryptor()
                    $encryptedBytes = $encryptor.TransformFinalBlock($inputBytes, 0, $inputBytes.Length)

                    # Write encrypted data with salt and IV prepended
                    $outputStream = [System.IO.File]::Create($encryptedPath)
                    try {
                        $outputStream.Write($keyData.Salt, 0, $keyData.Salt.Length)
                        $outputStream.Write($iv, 0, $iv.Length)
                        $outputStream.Write($encryptedBytes, 0, $encryptedBytes.Length)
                    }
                    finally {
                        $outputStream.Close()
                    }
                }
                finally {
                    $aes.Dispose()
                }

                # Replace original with encrypted
                Remove-Item -LiteralPath $OutputPath -Force
                Rename-Item -LiteralPath $encryptedPath -NewName (Split-Path -Leaf $OutputPath)
            }

            $fileInfo = Get-Item -LiteralPath $OutputPath

            # Calculate checksum
            $stream = [System.IO.File]::OpenRead($OutputPath)
            try {
                $sha256 = [System.Security.Cryptography.SHA256]::Create()
                $hashBytes = $sha256.ComputeHash($stream)
                $checksum = [BitConverter]::ToString($hashBytes).Replace("-", "").ToLowerInvariant()
            }
            finally {
                $stream.Close()
                $sha256.Dispose()
            }

            return [pscustomobject]@{
                Success = $true
                Path = $OutputPath
                Format = 'Zip'
                Encrypted = $Encrypt
                Size = $fileInfo.Length
                Checksum = $checksum
                SnapshotId = $Snapshot.SnapshotId
            }
        }
    }
    finally {
        # Cleanup temp directory
        if (Test-Path -LiteralPath $tempDir) {
            Remove-Item -LiteralPath $tempDir -Recurse -Force -ErrorAction SilentlyContinue
        }
    }
}

<#
.SYNOPSIS
    Exports a workspace snapshot to an archive.

.DESCRIPTION
    Exports a complete workspace snapshot including all packs,
    configuration, and optional state.

.PARAMETER Snapshot
    The workspace snapshot object.

.PARAMETER OutputPath
    The destination file path.

.PARAMETER Encrypt
    Encrypt the snapshot.

.PARAMETER Password
    Encryption password.

.PARAMETER IncludeState
    Include workspace state in export.

.OUTPUTS
    PSObject. Export result.

.EXAMPLE
    Export-WorkspaceSnapshot -Snapshot $wsSnapshot -OutputPath "workspace-backup.zip"
#>
function Export-WorkspaceSnapshot {
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory = $true)]
        [pscustomobject]$Snapshot,

        [Parameter(Mandatory = $true)]
        [string]$OutputPath,

        [switch]$Encrypt,

        [string]$Password = "",

        [switch]$IncludeState
    )

    if ($Encrypt -and [string]::IsNullOrWhiteSpace($Password)) {
        throw "Password is required when encryption is enabled"
    }

    # Ensure output directory exists
    $outputDir = Split-Path -Parent $OutputPath
    if ($outputDir -and -not (Test-Path -LiteralPath $outputDir)) {
        New-Item -ItemType Directory -Path $outputDir -Force | Out-Null
    }

    $tempDir = [System.IO.Path]::GetTempPath() + [Guid]::NewGuid().ToString("N")
    New-Item -ItemType Directory -Path $tempDir -Force | Out-Null

    try {
        # Write manifest
        $manifestPath = Join-Path $tempDir "manifest.json"
        $manifestJson = $Snapshot.Manifest | ConvertTo-Json -Depth 10
        [System.IO.File]::WriteAllText($manifestPath, $manifestJson, [System.Text.Encoding]::UTF8)

        # Create packs directory
        $packsDir = Join-Path $tempDir "packs"
        New-Item -ItemType Directory -Path $packsDir -Force | Out-Null

        # Export each pack
        foreach ($packSnapshot in $Snapshot.PackSnapshots) {
            $packDir = Join-Path $packsDir $packSnapshot.Manifest.packId
            New-Item -ItemType Directory -Path $packDir -Force | Out-Null

            $packManifestPath = Join-Path $packDir "manifest.json"
            $packManifestJson = $packSnapshot.Manifest | ConvertTo-Json -Depth 10
            [System.IO.File]::WriteAllText($packManifestPath, $packManifestJson, [System.Text.Encoding]::UTF8)

            # Copy pack source files
            if ($packSnapshot.PackPath -and (Test-Path -LiteralPath $packSnapshot.PackPath)) {
                Copy-DirectoryWithProgress -Source $packSnapshot.PackPath -Destination $packDir -ExcludePatterns @('*.tmp', '*.lock')
            }
        }

        # Include state if requested
        if ($IncludeState -and $Snapshot.Manifest.state) {
            $stateDir = Join-Path $tempDir "state"
            New-Item -ItemType Directory -Path $stateDir -Force | Out-Null

            foreach ($stateFile in $Snapshot.Manifest.state.Keys) {
                $statePath = Join-Path $stateDir $stateFile
                $stateJson = $Snapshot.Manifest.state[$stateFile] | ConvertTo-Json -Depth 10
                [System.IO.File]::WriteAllText($statePath, $stateJson, [System.Text.Encoding]::UTF8)
            }
        }

        # Create ZIP
        Add-Type -AssemblyName System.IO.Compression.FileSystem

        if (Test-Path -LiteralPath $OutputPath) {
            Remove-Item -LiteralPath $OutputPath -Force
        }

        $compressionLevel = [System.IO.Compression.CompressionLevel]::Optimal
        [System.IO.Compression.ZipFile]::CreateFromDirectory($tempDir, $OutputPath, $compressionLevel, $false)

        # Encrypt if requested
        if ($Encrypt) {
            $encryptedPath = "$OutputPath.enc"
            $keyData = Derive-EncryptionKey -Password $Password

            $iv = New-Object byte[] 16
            $rng = [System.Security.Cryptography.RandomNumberGenerator]::Create()
            try {
                $rng.GetBytes($iv)
            }
            finally {
                $rng.Dispose()
            }

            $inputBytes = [System.IO.File]::ReadAllBytes($OutputPath)
            $aes = [System.Security.Cryptography.Aes]::Create()
            try {
                $aes.Key = $keyData.Key
                $aes.IV = $iv
                $aes.Mode = [System.Security.Cryptography.CipherMode]::CBC
                $aes.Padding = [System.Security.Cryptography.PaddingMode]::PKCS7

                $encryptor = $aes.CreateEncryptor()
                $encryptedBytes = $encryptor.TransformFinalBlock($inputBytes, 0, $inputBytes.Length)

                $outputStream = [System.IO.File]::Create($encryptedPath)
                try {
                    $outputStream.Write($keyData.Salt, 0, $keyData.Salt.Length)
                    $outputStream.Write($iv, 0, $iv.Length)
                    $outputStream.Write($encryptedBytes, 0, $encryptedBytes.Length)
                }
                finally {
                    $outputStream.Close()
                }
            }
            finally {
                $aes.Dispose()
            }

            Remove-Item -LiteralPath $OutputPath -Force
            Rename-Item -LiteralPath $encryptedPath -NewName (Split-Path -Leaf $OutputPath)
        }

        $fileInfo = Get-Item -LiteralPath $OutputPath

        # Calculate checksum
        $stream = [System.IO.File]::OpenRead($OutputPath)
        try {
            $sha256 = [System.Security.Cryptography.SHA256]::Create()
            $hashBytes = $sha256.ComputeHash($stream)
            $checksum = [BitConverter]::ToString($hashBytes).Replace("-", "").ToLowerInvariant()
        }
        finally {
            $stream.Close()
            $sha256.Dispose()
        }

        return [pscustomobject]@{
            Success = $true
            Path = $OutputPath
            Format = 'Zip'
            Encrypted = $Encrypt
            Size = $fileInfo.Length
            Checksum = $checksum
            SnapshotId = $Snapshot.SnapshotId
            PackCount = $Snapshot.PackSnapshots.Count
        }
    }
    finally {
        if (Test-Path -LiteralPath $tempDir) {
            Remove-Item -LiteralPath $tempDir -Recurse -Force -ErrorAction SilentlyContinue
        }
    }
}

<#
.SYNOPSIS
    Uploads a snapshot to remote storage.

.DESCRIPTION
    Uploads a snapshot file to a remote storage endpoint.
    Supports HTTP/HTTPS endpoints and file system paths.

.PARAMETER SnapshotPath
    Path to the snapshot file.

.PARAMETER RemoteUrl
    Remote endpoint URL.

.PARAMETER Headers
    Optional HTTP headers for authentication.

.PARAMETER Credential
    Optional credentials for authentication.

.OUTPUTS
    PSObject. Upload result.

.EXAMPLE
    Export-SnapshotToRemote -SnapshotPath "backup.zip" -RemoteUrl "https://backup.example.com/snapshots" -Headers @{ "Authorization" = "Bearer token" }
#>
function Export-SnapshotToRemote {
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory = $true)]
        [string]$SnapshotPath,

        [Parameter(Mandatory = $true)]
        [string]$RemoteUrl,

        [hashtable]$Headers = @{},

        [pscredential]$Credential
    )

    if (-not (Test-Path -LiteralPath $SnapshotPath)) {
        throw "Snapshot file not found: $SnapshotPath"
    }

    $fileInfo = Get-Item -LiteralPath $SnapshotPath
    $fileName = $fileInfo.Name

    try {
        if ($RemoteUrl -match '^https?://') {
            # HTTP upload
            $uri = "$RemoteUrl/$fileName"

            $invokeParams = @{
                Uri = $uri
                Method = 'PUT'
                InFile = $SnapshotPath
                ContentType = 'application/zip'
            }

            if ($Headers.Count -gt 0) {
                $invokeParams['Headers'] = $Headers
            }

            if ($Credential) {
                $invokeParams['Credential'] = $Credential
            }

            $response = Invoke-WebRequest @invokeParams

            return [pscustomobject]@{
                Success = $response.StatusCode -ge 200 -and $response.StatusCode -lt 300
                RemoteUrl = $uri
                StatusCode = $response.StatusCode
                BytesUploaded = $fileInfo.Length
            }
        }
        else {
            # File system copy
            $destPath = Join-Path $RemoteUrl $fileName
            $destDir = Split-Path -Parent $destPath

            if (-not (Test-Path -LiteralPath $destDir)) {
                New-Item -ItemType Directory -Path $destDir -Force | Out-Null
            }

            Copy-Item -LiteralPath $SnapshotPath -Destination $destPath -Force

            return [pscustomobject]@{
                Success = $true
                RemotePath = $destPath
                BytesUploaded = $fileInfo.Length
            }
        }
    }
    catch {
        throw "Failed to upload snapshot: $_"
    }
}

<#
.SYNOPSIS
    Compresses snapshot data to a ZIP archive.

.DESCRIPTION
    Creates a compressed ZIP archive from snapshot data or files.

.PARAMETER InputPath
    Path to snapshot files or directory.

.PARAMETER OutputPath
    Path for the output ZIP file.

.PARAMETER CompressionLevel
    Compression level: Optimal, Fastest, or NoCompression.

.OUTPUTS
    PSObject. Compression result.

.EXAMPLE
    Compress-Snapshot -InputPath "./snapshot-data" -OutputPath "snapshot.zip" -CompressionLevel Optimal
#>
function Compress-Snapshot {
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory = $true)]
        [string]$InputPath,

        [Parameter(Mandatory = $true)]
        [string]$OutputPath,

        [ValidateSet('Optimal', 'Fastest', 'NoCompression')]
        [string]$CompressionLevel = 'Optimal'
    )

    if (-not (Test-Path -LiteralPath $InputPath)) {
        throw "Input path not found: $InputPath"
    }

    # Ensure output directory exists
    $outputDir = Split-Path -Parent $OutputPath
    if ($outputDir -and -not (Test-Path -LiteralPath $outputDir)) {
        New-Item -ItemType Directory -Path $outputDir -Force | Out-Null
    }

    if (Test-Path -LiteralPath $OutputPath) {
        Remove-Item -LiteralPath $OutputPath -Force
    }

    try {
        Add-Type -AssemblyName System.IO.Compression.FileSystem

        $compression = [System.IO.Compression.CompressionLevel]::$CompressionLevel

        if ((Get-Item -LiteralPath $InputPath) -is [System.IO.FileInfo]) {
            # Single file - create ZIP with just that file
            $tempDir = [System.IO.Path]::GetTempPath() + [Guid]::NewGuid().ToString("N")
            New-Item -ItemType Directory -Path $tempDir -Force | Out-Null
            try {
                Copy-Item -LiteralPath $InputPath -Destination $tempDir
                [System.IO.Compression.ZipFile]::CreateFromDirectory($tempDir, $OutputPath, $compression, $false)
            }
            finally {
                Remove-Item -LiteralPath $tempDir -Recurse -Force -ErrorAction SilentlyContinue
            }
        }
        else {
            # Directory
            [System.IO.Compression.ZipFile]::CreateFromDirectory($InputPath, $OutputPath, $compression, $false)
        }

        $fileInfo = Get-Item -LiteralPath $OutputPath

        return [pscustomobject]@{
            Success = $true
            InputPath = $InputPath
            OutputPath = $OutputPath
            CompressionLevel = $CompressionLevel
            OriginalSize = (Get-ChildItem -Path $InputPath -Recurse -File | Measure-Object -Property Length -Sum).Sum
            CompressedSize = $fileInfo.Length
            Ratio = [math]::Round((1 - ($fileInfo.Length / (Get-ChildItem -Path $InputPath -Recurse -File | Measure-Object -Property Length -Sum).Sum)) * 100, 2)
        }
    }
    catch {
        throw "Failed to compress snapshot: $_"
    }
}

# ============================================================================
# Snapshot Import Functions
# ============================================================================

<#
.SYNOPSIS
    Imports a pack snapshot from a file.

.DESCRIPTION
    Imports a snapshot from JSON or ZIP format, optionally decrypting
    if encrypted.

.PARAMETER Path
    Path to the snapshot file.

.PARAMETER Password
    Decryption password if snapshot is encrypted.

.PARAMETER VerifyIntegrity
    Verify checksums after import.

.PARAMETER ProjectRoot
    Project root for context.

.OUTPUTS
    PSObject. Imported snapshot object.

.EXAMPLE
    $snapshot = Import-PackSnapshot -Path "backup.zip"

.EXAMPLE
    $snapshot = Import-PackSnapshot -Path "backup.zip" -Password "secret" -VerifyIntegrity
#>
function Import-PackSnapshot {
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path,

        [string]$Password = "",

        [switch]$VerifyIntegrity,

        [string]$ProjectRoot = "."
    )

    if (-not (Test-Path -LiteralPath $Path)) {
        throw "Snapshot file not found: $Path"
    }

    $resolvedPath = Resolve-Path -Path $Path
    $tempDir = [System.IO.Path]::GetTempPath() + [Guid]::NewGuid().ToString("N")
    New-Item -ItemType Directory -Path $tempDir -Force | Out-Null

    try {
        # Try to decrypt if password provided or file appears encrypted
        $workingPath = $resolvedPath.Path

        if (-not [string]::IsNullOrWhiteSpace($Password)) {
            # Attempt decryption
            try {
                $inputBytes = [System.IO.File]::ReadAllBytes($resolvedPath.Path)

                # Extract salt, IV, and encrypted data
                $salt = New-Object byte[] 32
                $iv = New-Object byte[] 16
                [Array]::Copy($inputBytes, 0, $salt, 0, 32)
                [Array]::Copy($inputBytes, 32, $iv, 0, 16)
                $encryptedBytes = New-Object byte[] ($inputBytes.Length - 48)
                [Array]::Copy($inputBytes, 48, $encryptedBytes, 0, $encryptedBytes.Length)

                # Derive key
                $keyData = Derive-EncryptionKey -Password $Password -Salt $salt

                # Decrypt
                $aes = [System.Security.Cryptography.Aes]::Create()
                try {
                    $aes.Key = $keyData.Key
                    $aes.IV = $iv
                    $aes.Mode = [System.Security.Cryptography.CipherMode]::CBC
                    $aes.Padding = [System.Security.Cryptography.PaddingMode]::PKCS7

                    $decryptor = $aes.CreateDecryptor()
                    $decryptedBytes = $decryptor.TransformFinalBlock($encryptedBytes, 0, $encryptedBytes.Length)

                    $workingPath = Join-Path $tempDir "decrypted.zip"
                    [System.IO.File]::WriteAllBytes($workingPath, $decryptedBytes)
                }
                finally {
                    $aes.Dispose()
                }
            }
            catch {
                throw "Failed to decrypt snapshot (wrong password or not encrypted): $_"
            }
        }

        # Determine file type
        $extension = [System.IO.Path]::GetExtension($workingPath).ToLowerInvariant()
        $manifest = $null

        if ($extension -eq '.json') {
            # Direct JSON
            $content = Get-Content -LiteralPath $workingPath -Raw
            $manifest = $content | ConvertFrom-Json -AsHashtable
        }
        else {
            # ZIP archive
            Add-Type -AssemblyName System.IO.Compression.FileSystem
            $zip = [System.IO.Compression.ZipFile]::OpenRead($workingPath)
            try {
                # Extract all
                [System.IO.Compression.ZipFileExtensions]::ExtractToDirectory($zip, $tempDir)

                # Read manifest
                $manifestPath = Join-Path $tempDir "manifest.json"
                if (-not (Test-Path -LiteralPath $manifestPath)) {
                    throw "Manifest not found in snapshot"
                }

                $content = Get-Content -LiteralPath $manifestPath -Raw
                $manifest = $content | ConvertFrom-Json -AsHashtable
            }
            finally {
                $zip.Dispose()
            }
        }

        # Verify integrity if requested
        if ($VerifyIntegrity -and $manifest.checksums) {
            $sourceDir = Join-Path $tempDir "source"
            if (Test-Path -LiteralPath $sourceDir) {
                $verifyResult = Test-DirectoryChecksums -Path $sourceDir -Checksums $manifest.checksums
                if (-not $verifyResult.IsValid) {
                    Write-Warning "Integrity check failed: $($verifyResult.MismatchCount) mismatches, $($verifyResult.MissingCount) missing files"
                }
            }
        }

        $snapshot = [pscustomobject]@{
            SnapshotId = $manifest.snapshotId
            Manifest = $manifest
            Type = $manifest.type
            ImportedAt = [DateTime]::UtcNow.ToString("yyyy-MM-ddTHH:mm:ssZ")
            SourcePath = $Path
        }

        # Include source path if available
        $sourceDir = Join-Path $tempDir "source"
        if (Test-Path -LiteralPath $sourceDir) {
            $snapshot | Add-Member -MemberType NoteProperty -Name 'ContentPath' -Value $sourceDir
        }

        return $snapshot
    }
    finally {
        # Note: We don't cleanup tempDir here because the caller may need ContentPath
        # The caller is responsible for cleanup or use Restore-FromSnapshot
    }
}

<#
.SYNOPSIS
    Imports a workspace snapshot from an archive.

.DESCRIPTION
    Imports a complete workspace snapshot including all packs.

.PARAMETER Path
    Path to the workspace snapshot archive.

.PARAMETER Password
    Decryption password if encrypted.

.PARAMETER VerifyIntegrity
    Verify checksums.

.OUTPUTS
    PSObject. Imported workspace snapshot.

.EXAMPLE
    $wsSnapshot = Import-WorkspaceSnapshot -Path "workspace-backup.zip"
#>
function Import-WorkspaceSnapshot {
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path,

        [string]$Password = "",

        [switch]$VerifyIntegrity
    )

    if (-not (Test-Path -LiteralPath $Path)) {
        throw "Snapshot file not found: $Path"
    }

    $resolvedPath = Resolve-Path -Path $Path
    $tempDir = [System.IO.Path]::GetTempPath() + [Guid]::NewGuid().ToString("N")
    New-Item -ItemType Directory -Path $tempDir -Force | Out-Null

    try {
        # Decrypt if needed
        $workingPath = $resolvedPath.Path

        if (-not [string]::IsNullOrWhiteSpace($Password)) {
            try {
                $inputBytes = [System.IO.File]::ReadAllBytes($resolvedPath.Path)

                $salt = New-Object byte[] 32
                $iv = New-Object byte[] 16
                [Array]::Copy($inputBytes, 0, $salt, 0, 32)
                [Array]::Copy($inputBytes, 32, $iv, 0, 16)
                $encryptedBytes = New-Object byte[] ($inputBytes.Length - 48)
                [Array]::Copy($inputBytes, 48, $encryptedBytes, 0, $encryptedBytes.Length)

                $keyData = Derive-EncryptionKey -Password $Password -Salt $salt

                $aes = [System.Security.Cryptography.Aes]::Create()
                try {
                    $aes.Key = $keyData.Key
                    $aes.IV = $iv
                    $aes.Mode = [System.Security.Cryptography.CipherMode]::CBC
                    $aes.Padding = [System.Security.Cryptography.PaddingMode]::PKCS7

                    $decryptor = $aes.CreateDecryptor()
                    $decryptedBytes = $decryptor.TransformFinalBlock($encryptedBytes, 0, $encryptedBytes.Length)

                    $workingPath = Join-Path $tempDir "decrypted.zip"
                    [System.IO.File]::WriteAllBytes($workingPath, $decryptedBytes)
                }
                finally {
                    $aes.Dispose()
                }
            }
            catch {
                throw "Failed to decrypt snapshot: $_"
            }
        }

        # Extract ZIP
        Add-Type -AssemblyName System.IO.Compression.FileSystem
        $zip = [System.IO.Compression.ZipFile]::OpenRead($workingPath)
        try {
            [System.IO.Compression.ZipFileExtensions]::ExtractToDirectory($zip, $tempDir)
        }
        finally {
            $zip.Dispose()
        }

        # Read manifest
        $manifestPath = Join-Path $tempDir "manifest.json"
        if (-not (Test-Path -LiteralPath $manifestPath)) {
            throw "Manifest not found in workspace snapshot"
        }

        $content = Get-Content -LiteralPath $manifestPath -Raw
        $manifest = $content | ConvertFrom-Json -AsHashtable

        # Load pack snapshots
        $packSnapshots = @()
        $packsDir = Join-Path $tempDir "packs"
        if (Test-Path -LiteralPath $packsDir) {
            $packDirs = Get-ChildItem -Path $packsDir -Directory
            foreach ($packDir in $packDirs) {
                $packManifestPath = Join-Path $packDir.FullName "manifest.json"
                if (Test-Path -LiteralPath $packManifestPath) {
                    $packContent = Get-Content -LiteralPath $packManifestPath -Raw
                    $packManifest = $packContent | ConvertFrom-Json -AsHashtable
                    $packSnapshots += [pscustomobject]@{
                        SnapshotId = $packManifest.snapshotId
                        Manifest = $packManifest
                        Type = "pack"
                    }
                }
            }
        }

        # Verify integrity if requested
        if ($VerifyIntegrity -and $manifest.checksums) {
            $verifyResult = Test-DirectoryChecksums -Path $tempDir -Checksums $manifest.checksums
            if (-not $verifyResult.IsValid) {
                Write-Warning "Integrity check failed: $($verifyResult.MismatchCount) mismatches"
            }
        }

        return [pscustomobject]@{
            SnapshotId = $manifest.snapshotId
            Manifest = $manifest
            PackSnapshots = $packSnapshots
            Type = "workspace"
            ContentPath = $tempDir
            ImportedAt = [DateTime]::UtcNow.ToString("yyyy-MM-ddTHH:mm:ssZ")
            SourcePath = $Path
        }
    }
    catch {
        # Cleanup on error
        if (Test-Path -LiteralPath $tempDir) {
            Remove-Item -LiteralPath $tempDir -Recurse -Force -ErrorAction SilentlyContinue
        }
        throw
    }
}

<#
.SYNOPSIS
    Downloads and imports a snapshot from remote storage.

.DESCRIPTION
    Downloads a snapshot from a remote URL and imports it.

.PARAMETER RemoteUrl
    URL of the remote snapshot.

.PARAMETER Password
    Decryption password if encrypted.

.PARAMETER Headers
    Optional HTTP headers.

.PARAMETER Credential
    Optional credentials.

.PARAMETER TempPath
    Temporary download path.

.OUTPUTS
    PSObject. Imported snapshot.

.EXAMPLE
    $snapshot = Import-SnapshotFromRemote -RemoteUrl "https://backup.example.com/snapshots/backup.zip"
#>
function Import-SnapshotFromRemote {
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory = $true)]
        [string]$RemoteUrl,

        [string]$Password = "",

        [hashtable]$Headers = @{},

        [pscredential]$Credential,

        [string]$TempPath = ""
    )

    if ([string]::IsNullOrWhiteSpace($TempPath)) {
        $TempPath = Join-Path ([System.IO.Path]::GetTempPath()) ([Guid]::NewGuid().ToString("N") + ".zip")
    }

    try {
        # Download
        $invokeParams = @{
            Uri = $RemoteUrl
            OutFile = $TempPath
        }

        if ($Headers.Count -gt 0) {
            $invokeParams['Headers'] = $Headers
        }

        if ($Credential) {
            $invokeParams['Credential'] = $Credential
        }

        Invoke-WebRequest @invokeParams

        # Import based on type
        $snapshot = Import-PackSnapshot -Path $TempPath -Password $Password

        $snapshot | Add-Member -MemberType NoteProperty -Name 'RemoteUrl' -Value $RemoteUrl -Force

        return $snapshot
    }
    catch {
        throw "Failed to import snapshot from remote: $_"
    }
    finally {
        if (Test-Path -LiteralPath $TempPath) {
            Remove-Item -LiteralPath $TempPath -Force -ErrorAction SilentlyContinue
        }
    }
}

<#
.SYNOPSIS
    Tests version compatibility of a snapshot.

.DESCRIPTION
    Checks if a snapshot is compatible with the current platform version.

.PARAMETER Snapshot
    The snapshot to test.

.PARAMETER CurrentVersion
    Current platform version to test against.

.OUTPUTS
    PSObject. Compatibility result.

.EXAMPLE
    $compat = Test-SnapshotCompatibility -Snapshot $snapshot -CurrentVersion "1.0"
#>
function Test-SnapshotCompatibility {
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory = $true, ParameterSetName = 'Object')]
        [pscustomobject]$Snapshot,

        [Parameter(Mandatory = $true, ParameterSetName = 'File')]
        [string]$Path,

        [string]$CurrentVersion = $script:SnapshotSchemaVersion
    )

    if ($PSCmdlet.ParameterSetName -eq 'File') {
        $Snapshot = Get-SnapshotManifest -Path $Path
    }

    $manifest = if ($Snapshot.Manifest) { $Snapshot.Manifest } else { $Snapshot }

    $snapshotVersion = $manifest.snapshotVersion
    $isCompatible = $true
    $issues = @()

    # Check schema version compatibility
    if ($snapshotVersion) {
        $snapshotMajor = [version]$snapshotVersion
        $currentMajor = [version]$CurrentVersion

        if ($snapshotMajor.Major -gt $currentMajor.Major) {
            $isCompatible = $false
            $issues += "Snapshot schema version ($snapshotVersion) is newer than current ($CurrentVersion)"
        }
        elseif ($snapshotMajor.Major -lt $currentMajor.Major) {
            $issues += "Snapshot schema version ($snapshotVersion) is older than current ($CurrentVersion) - migration may be needed"
        }
    }
    else {
        $isCompatible = $false
        $issues += "Snapshot has no schema version"
    }

    # Check platform compatibility
    $snapshotPlatform = if ($manifest.metadata) { $manifest.metadata.platform } else { $null }
    $currentPlatform = [System.Environment]::OSVersion.Platform.ToString()

    if ($snapshotPlatform -and $snapshotPlatform -ne $currentPlatform) {
        $issues += "Snapshot created on different platform ($snapshotPlatform vs $currentPlatform)"
    }

    # Check pack/toolkit version compatibility
    if ($manifest.lockfile -and $manifest.lockfile.toolkitVersion) {
        $lockfileVersion = [version]$manifest.lockfile.toolkitVersion
        # Add version compatibility logic here if needed
    }

    return [pscustomobject]@{
        IsCompatible = $isCompatible
        SnapshotVersion = $snapshotVersion
        CurrentVersion = $CurrentVersion
        Issues = $issues
        Warnings = if ($issues.Count -gt 0 -and $isCompatible) { $issues } else { @() }
        Errors = if (-not $isCompatible) { $issues } else { @() }
    }
}

# ============================================================================
# Snapshot Management Functions
# ============================================================================

<#
.SYNOPSIS
    Lists available snapshots.

.DESCRIPTION
    Lists snapshots in the snapshot storage directory.

.PARAMETER ProjectRoot
    Project root directory.

.PARAMETER PackId
    Filter by pack ID.

.PARAMETER Type
    Filter by snapshot type.

.OUTPUTS
    PSObject[]. Array of snapshot metadata.

.EXAMPLE
    $snapshots = Get-SnapshotList -PackId "godot-engine"
#>
function Get-SnapshotList {
    [CmdletBinding()]
    [OutputType([array])]
    param(
        [string]$ProjectRoot = ".",

        [string]$PackId = "",

        [ValidateSet('', 'pack', 'workspace', 'incremental')]
        [string]$Type = ""
    )

    $storagePath = Get-SnapshotStoragePath -ProjectRoot $ProjectRoot
    $snapshots = @()

    if (-not (Test-Path -LiteralPath $storagePath)) {
        return $snapshots
    }

    $files = Get-ChildItem -Path $storagePath -File | Where-Object {
        $_.Extension -in @('.json', '.zip', '.snap')
    }

    foreach ($file in $files) {
        try {
            $manifest = Get-SnapshotManifest -Path $file.FullName

            # Apply filters
            if ($PackId -and $manifest.packId -ne $PackId) {
                continue
            }
            if ($Type -and $manifest.type -ne $Type) {
                continue
            }

            $snapshots += [pscustomobject]@{
                SnapshotId = $manifest.snapshotId
                Type = $manifest.type
                PackId = $manifest.packId
                CreatedAt = $manifest.createdAt
                CreatedBy = $manifest.createdBy
                FilePath = $file.FullName
                FileSize = $file.Length
                FileName = $file.Name
                Version = $manifest.packVersion
            }
        }
        catch {
            Write-Verbose "Failed to read snapshot: $($file.Name)"
        }
    }

    return $snapshots | Sort-Object CreatedAt -Descending
}

<#
.SYNOPSIS
    Removes a snapshot.

.DESCRIPTION
    Deletes a snapshot file from storage.

.PARAMETER SnapshotId
    ID of the snapshot to remove.

.PARAMETER Path
    Path to the snapshot file.

.PARAMETER ProjectRoot
    Project root directory.

.PARAMETER Force
    Skip confirmation.

.OUTPUTS
    System.Boolean. True if removed.

.EXAMPLE
    Remove-Snapshot -SnapshotId "snap-20260101..." -Force

.EXAMPLE
    Remove-Snapshot -Path "backup.zip" -Force
#>
function Remove-Snapshot {
    [CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'High')]
    [OutputType([bool])]
    param(
        [Parameter(ParameterSetName = 'Id')]
        [string]$SnapshotId,

        [Parameter(ParameterSetName = 'Path', Mandatory = $true)]
        [string]$Path,

        [string]$ProjectRoot = ".",

        [switch]$Force
    )

    if ($PSCmdlet.ParameterSetName -eq 'Id') {
        # Find by ID
        $snapshots = Get-SnapshotList -ProjectRoot $ProjectRoot
        $snapshot = $snapshots | Where-Object { $_.SnapshotId -eq $SnapshotId } | Select-Object -First 1

        if (-not $snapshot) {
            Write-Warning "Snapshot not found: $SnapshotId"
            return $false
        }

        $Path = $snapshot.FilePath
    }

    if (-not (Test-Path -LiteralPath $Path)) {
        Write-Warning "Snapshot file not found: $Path"
        return $false
    }

    $target = "snapshot at $Path"
    if ($Force -or $PSCmdlet.ShouldProcess($target, "Remove")) {
        Remove-Item -LiteralPath $Path -Force
        Write-Verbose "Removed snapshot: $Path"
        return $true
    }

    return $false
}

<#
.SYNOPSIS
    Restores state from a snapshot.

.DESCRIPTION
    Restores pack or workspace state from a snapshot.

.PARAMETER Snapshot
    The snapshot object to restore from.

.PARAMETER Path
    Path to the snapshot file.

.PARAMETER TargetPath
    Destination path for restoration.

.PARAMETER Password
    Decryption password if needed.

.PARAMETER VerifyIntegrity
    Verify checksums after restore.

.OUTPUTS
    PSObject. Restore result.

.EXAMPLE
    Restore-FromSnapshot -Snapshot $snapshot -TargetPath "./restored"

.EXAMPLE
    Restore-FromSnapshot -Path "backup.zip" -TargetPath "./restored" -VerifyIntegrity
#>
function Restore-FromSnapshot {
    [CmdletBinding(SupportsShouldProcess = $true)]
    [OutputType([pscustomobject])]
    param(
        [Parameter(ParameterSetName = 'Object', Mandatory = $true)]
        [pscustomobject]$Snapshot,

        [Parameter(ParameterSetName = 'File', Mandatory = $true)]
        [string]$Path,

        [Parameter(Mandatory = $true)]
        [string]$TargetPath,

        [string]$Password = "",

        [switch]$VerifyIntegrity
    )

    if ($PSCmdlet.ParameterSetName -eq 'File') {
        $Snapshot = Import-PackSnapshot -Path $Path -Password $Password
    }

    $manifest = $Snapshot.Manifest
    $snapshotType = $manifest.type

    if ($PSCmdlet.ShouldProcess("snapshot $($Snapshot.SnapshotId) to '$TargetPath'", "Restore")) {
        if ($snapshotType -eq 'workspace') {
            return Restore-WorkspaceSnapshot -Snapshot $Snapshot -TargetPath $TargetPath -VerifyIntegrity:$VerifyIntegrity
        }
        else {
            return Restore-PackSnapshotInternal -Snapshot $Snapshot -TargetPath $TargetPath -VerifyIntegrity:$VerifyIntegrity
        }
    }

    return $null
}

<#
.SYNOPSIS
    Internal function to restore a pack snapshot.
#>
function Restore-PackSnapshotInternal {
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory = $true)]
        [pscustomobject]$Snapshot,

        [Parameter(Mandatory = $true)]
        [string]$TargetPath,

        [switch]$VerifyIntegrity
    )

    $manifest = $Snapshot.Manifest

    # Ensure target directory exists
    if (-not (Test-Path -LiteralPath $TargetPath)) {
        New-Item -ItemType Directory -Path $TargetPath -Force | Out-Null
    }

    $sourcePath = $Snapshot.ContentPath
    if (-not $sourcePath -and $Snapshot.PackPath) {
        $sourcePath = $Snapshot.PackPath
    }

    if ($sourcePath -and (Test-Path -LiteralPath $sourcePath)) {
        $copyResult = Copy-DirectoryWithProgress -Source $sourcePath -Destination $TargetPath

        # Verify integrity
        if ($VerifyIntegrity -and $manifest.checksums) {
            $verifyResult = Test-DirectoryChecksums -Path $TargetPath -Checksums $manifest.checksums

            return [pscustomobject]@{
                Success = $verifyResult.IsValid
                SnapshotId = $Snapshot.SnapshotId
                TargetPath = $TargetPath
                FilesRestored = $copyResult.FilesCopied
                FilesFailed = $copyResult.FilesFailed
                IntegrityCheck = $verifyResult
            }
        }

        return [pscustomobject]@{
            Success = $true
            SnapshotId = $Snapshot.SnapshotId
            TargetPath = $TargetPath
            FilesRestored = $copyResult.FilesCopied
            FilesFailed = $copyResult.FilesFailed
        }
    }
    else {
        # No content available - just restore manifest
        $manifestPath = Join-Path $TargetPath "manifest.json"
        $manifestJson = $manifest | ConvertTo-Json -Depth 10
        [System.IO.File]::WriteAllText($manifestPath, $manifestJson, [System.Text.Encoding]::UTF8)

        return [pscustomobject]@{
            Success = $true
            SnapshotId = $Snapshot.SnapshotId
            TargetPath = $TargetPath
            FilesRestored = 0
            Note = "Manifest-only restore (no content available)"
        }
    }
}

<#
.SYNOPSIS
    Internal function to restore a workspace snapshot.
#>
function Restore-WorkspaceSnapshot {
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory = $true)]
        [pscustomobject]$Snapshot,

        [Parameter(Mandatory = $true)]
        [string]$TargetPath,

        [switch]$VerifyIntegrity
    )

    $manifest = $Snapshot.Manifest

    # Ensure target directory exists
    if (-not (Test-Path -LiteralPath $TargetPath)) {
        New-Item -ItemType Directory -Path $TargetPath -Force | Out-Null
    }

    $results = @()
    $allSuccess = $true

    # Restore each pack
    $packsDir = Join-Path $TargetPath "packs"
    if (-not (Test-Path -LiteralPath $packsDir)) {
        New-Item -ItemType Directory -Path $packsDir -Force | Out-Null
    }

    foreach ($packManifest in $manifest.packs) {
        $packId = $packManifest.packId
        $packTargetPath = Join-Path $packsDir $packId

        # Find pack content in extracted snapshot
        $contentPath = $null
        if ($Snapshot.ContentPath) {
            $potentialPath = Join-Path $Snapshot.ContentPath "packs/$packId"
            if (Test-Path -LiteralPath $potentialPath) {
                $contentPath = $potentialPath
            }
        }

        $packSnapshot = [pscustomobject]@{
            SnapshotId = $packManifest.snapshotId
            Manifest = $packManifest
            ContentPath = $contentPath
        }

        $result = Restore-PackSnapshotInternal -Snapshot $packSnapshot -TargetPath $packTargetPath -VerifyIntegrity:$VerifyIntegrity
        $results += $result

        if (-not $result.Success) {
            $allSuccess = $false
        }
    }

    # Restore state if present
    if ($manifest.state) {
        $stateDir = Join-Path $TargetPath ".llm-workflow/state"
        if (-not (Test-Path -LiteralPath $stateDir)) {
            New-Item -ItemType Directory -Path $stateDir -Force | Out-Null
        }

        foreach ($stateFile in $manifest.state.Keys) {
            $statePath = Join-Path $stateDir $stateFile
            $stateJson = $manifest.state[$stateFile] | ConvertTo-Json -Depth 10
            [System.IO.File]::WriteAllText($statePath, $stateJson, [System.Text.Encoding]::UTF8)
        }
    }

    return [pscustomobject]@{
        Success = $allSuccess
        SnapshotId = $Snapshot.SnapshotId
        TargetPath = $TargetPath
        PackResults = $results
        PacksRestored = ($results | Where-Object { $_.Success }).Count
        TotalPacks = $results.Count
    }
}

<#
.SYNOPSIS
    Compares two snapshots.

.DESCRIPTION
    Compares two snapshots and returns differences.

.PARAMETER ReferenceSnapshot
    The reference (baseline) snapshot.

.PARAMETER DifferenceSnapshot
    The snapshot to compare against.

.PARAMETER CompareContent
    Also compare file contents (not just manifests).

.OUTPUTS
    PSObject. Comparison result with differences.

.EXAMPLE
    $diff = Compare-Snapshots -ReferenceSnapshot $snap1 -DifferenceSnapshot $snap2
#>
function Compare-Snapshots {
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory = $true)]
        [pscustomobject]$ReferenceSnapshot,

        [Parameter(Mandatory = $true)]
        [pscustomobject]$DifferenceSnapshot,

        [switch]$CompareContent
    )

    $refManifest = $ReferenceSnapshot.Manifest
    $diffManifest = $DifferenceSnapshot.Manifest

    $added = @()
    $removed = @()
    $modified = @()
    $unchanged = @()

    # Compare checksums
    $refChecksums = $refManifest.checksums
    $diffChecksums = $diffManifest.checksums

    foreach ($file in $diffChecksums.Keys) {
        if (-not $refChecksums.ContainsKey($file)) {
            $added += $file
        }
        elseif ($refChecksums[$file] -ne $diffChecksums[$file]) {
            $modified += [pscustomobject]@{
                Path = $file
                ReferenceChecksum = $refChecksums[$file]
                DifferenceChecksum = $diffChecksums[$file]
            }
        }
        else {
            $unchanged += $file
        }
    }

    foreach ($file in $refChecksums.Keys) {
        if (-not $diffChecksums.ContainsKey($file)) {
            $removed += $file
        }
    }

    # Compare manifest properties
    $manifestDiffs = @{}
    $propertiesToCompare = @('packVersion', 'snapshotVersion', 'packId')

    foreach ($prop in $propertiesToCompare) {
        $refValue = $refManifest[$prop]
        $diffValue = $diffManifest[$prop]

        if ($refValue -ne $diffValue) {
            $manifestDiffs[$prop] = @{
                Reference = $refValue
                Difference = $diffValue
            }
        }
    }

    return [pscustomobject]@{
        ReferenceSnapshotId = $ReferenceSnapshot.SnapshotId
        DifferenceSnapshotId = $DifferenceSnapshot.SnapshotId
        AddedFiles = $added
        AddedCount = $added.Count
        RemovedFiles = $removed
        RemovedCount = $removed.Count
        ModifiedFiles = $modified
        ModifiedCount = $modified.Count
        UnchangedFiles = $unchanged
        UnchangedCount = $unchanged.Count
        ManifestDifferences = $manifestDiffs
        AreEqual = ($added.Count -eq 0 -and $removed.Count -eq 0 -and $modified.Count -eq 0 -and $manifestDiffs.Count -eq 0)
    }
}

# ============================================================================
# Encryption/Security Functions
# ============================================================================

<#
.SYNOPSIS
    Encrypts a snapshot file.

.DESCRIPTION
    Encrypts a snapshot file using AES-256 encryption.

.PARAMETER Path
    Path to the snapshot file.

.PARAMETER Password
    Encryption password.

.PARAMETER OutputPath
    Optional output path (defaults to .enc extension).

.OUTPUTS
    PSObject. Encryption result.

.EXAMPLE
    Protect-Snapshot -Path "backup.zip" -Password "secret123"
#>
function Protect-Snapshot {
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path,

        [Parameter(Mandatory = $true)]
        [string]$Password,

        [string]$OutputPath = ""
    )

    if (-not (Test-Path -LiteralPath $Path)) {
        throw "Snapshot file not found: $Path"
    }

    if ([string]::IsNullOrWhiteSpace($OutputPath)) {
        $OutputPath = "$Path.enc"
    }

    try {
        $inputBytes = [System.IO.File]::ReadAllBytes($Path)

        # Generate salt and IV
        $salt = New-Object byte[] 32
        $iv = New-Object byte[] 16
        $rng = [System.Security.Cryptography.RandomNumberGenerator]::Create()
        try {
            $rng.GetBytes($salt)
            $rng.GetBytes($iv)
        }
        finally {
            $rng.Dispose()
        }

        # Derive key
        $keyData = Derive-EncryptionKey -Password $Password -Salt $salt

        # Encrypt
        $aes = [System.Security.Cryptography.Aes]::Create()
        try {
            $aes.Key = $keyData.Key
            $aes.IV = $iv
            $aes.Mode = [System.Security.Cryptography.CipherMode]::CBC
            $aes.Padding = [System.Security.Cryptography.PaddingMode]::PKCS7

            $encryptor = $aes.CreateEncryptor()
            $encryptedBytes = $encryptor.TransformFinalBlock($inputBytes, 0, $inputBytes.Length)

            # Write output with salt and IV prepended
            $outputStream = [System.IO.File]::Create($OutputPath)
            try {
                $outputStream.Write($salt, 0, $salt.Length)
                $outputStream.Write($iv, 0, $iv.Length)
                $outputStream.Write($encryptedBytes, 0, $encryptedBytes.Length)
            }
            finally {
                $outputStream.Close()
            }
        }
        finally {
            $aes.Dispose()
        }

        $fileInfo = Get-Item -LiteralPath $OutputPath

        return [pscustomobject]@{
            Success = $true
            OriginalPath = $Path
            EncryptedPath = $OutputPath
            OriginalSize = $inputBytes.Length
            EncryptedSize = $fileInfo.Length
        }
    }
    catch {
        throw "Failed to encrypt snapshot: $_"
    }
}

<#
.SYNOPSIS
    Decrypts a snapshot file.

.DESCRIPTION
    Decrypts an AES-256 encrypted snapshot file.

.PARAMETER Path
    Path to the encrypted snapshot.

.PARAMETER Password
    Decryption password.

.PARAMETER OutputPath
    Output path for decrypted file.

.OUTPUTS
    PSObject. Decryption result.

.EXAMPLE
    Unprotect-Snapshot -Path "backup.zip.enc" -Password "secret123" -OutputPath "backup.zip"
#>
function Unprotect-Snapshot {
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path,

        [Parameter(Mandatory = $true)]
        [string]$Password,

        [Parameter(Mandatory = $true)]
        [string]$OutputPath
    )

    if (-not (Test-Path -LiteralPath $Path)) {
        throw "Encrypted snapshot file not found: $Path"
    }

    try {
        $inputBytes = [System.IO.File]::ReadAllBytes($Path)

        if ($inputBytes.Length -lt 48) {
            throw "Invalid encrypted file (too small)"
        }

        # Extract salt, IV, and encrypted data
        $salt = New-Object byte[] 32
        $iv = New-Object byte[] 16
        [Array]::Copy($inputBytes, 0, $salt, 0, 32)
        [Array]::Copy($inputBytes, 32, $iv, 0, 16)
        $encryptedBytes = New-Object byte[] ($inputBytes.Length - 48)
        [Array]::Copy($inputBytes, 48, $encryptedBytes, 0, $encryptedBytes.Length)

        # Derive key
        $keyData = Derive-EncryptionKey -Password $Password -Salt $salt

        # Decrypt
        $aes = [System.Security.Cryptography.Aes]::Create()
        try {
            $aes.Key = $keyData.Key
            $aes.IV = $iv
            $aes.Mode = [System.Security.Cryptography.CipherMode]::CBC
            $aes.Padding = [System.Security.Cryptography.PaddingMode]::PKCS7

            $decryptor = $aes.CreateDecryptor()
            $decryptedBytes = $decryptor.TransformFinalBlock($encryptedBytes, 0, $encryptedBytes.Length)

            [System.IO.File]::WriteAllBytes($OutputPath, $decryptedBytes)
        }
        finally {
            $aes.Dispose()
        }

        $fileInfo = Get-Item -LiteralPath $OutputPath

        return [pscustomobject]@{
            Success = $true
            EncryptedPath = $Path
            DecryptedPath = $OutputPath
            EncryptedSize = $inputBytes.Length
            DecryptedSize = $fileInfo.Length
        }
    }
    catch {
        throw "Failed to decrypt snapshot (wrong password or corrupted file): $_"
    }
}

<#
.SYNOPSIS
    Verifies snapshot integrity using checksums.

.DESCRIPTION
    Validates that a snapshot's files match their recorded checksums.

.PARAMETER Snapshot
    The snapshot object.

.PARAMETER Path
    Path to the snapshot file.

.PARAMETER ContentPath
    Path to the extracted content (if already extracted).

.OUTPUTS
    PSObject. Integrity check result.

.EXAMPLE
    $integrity = Test-SnapshotIntegrity -Path "backup.zip"
#>
function Test-SnapshotIntegrity {
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(ParameterSetName = 'Object')]
        [pscustomobject]$Snapshot,

        [Parameter(ParameterSetName = 'File', Mandatory = $true)]
        [string]$Path,

        [string]$ContentPath = "",

        [string]$Password = ""
    )

    if ($PSCmdlet.ParameterSetName -eq 'File') {
        $Snapshot = Import-PackSnapshot -Path $Path -Password $Password
    }

    $manifest = if ($Snapshot.Manifest) { $Snapshot.Manifest } else { $Snapshot }

    if (-not $manifest.checksums) {
        return [pscustomobject]@{
            IsValid = $true
            ValidCount = 0
            MismatchCount = 0
            MissingCount = 0
            Warning = "No checksums in manifest"
        }
    }

    # Determine content path
    $checkPath = $ContentPath
    if ([string]::IsNullOrWhiteSpace($checkPath)) {
        $checkPath = $Snapshot.ContentPath
    }
    if ([string]::IsNullOrWhiteSpace($checkPath)) {
        $checkPath = $Snapshot.PackPath
    }

    if (-not $checkPath -or -not (Test-Path -LiteralPath $checkPath)) {
        return [pscustomobject]@{
            IsValid = $false
            ValidCount = 0
            MismatchCount = 0
            MissingCount = $manifest.checksums.Count
            Error = "Content path not available for verification"
            MissingFiles = @($manifest.checksums.Keys)
        }
    }

    return Test-DirectoryChecksums -Path $checkPath -Checksums $manifest.checksums
}

# ============================================================================
# Export Module Members
# ============================================================================

Export-ModuleMember -Function @(
    # Snapshot Creation
    'New-PackSnapshot'
    'New-WorkspaceSnapshot'
    'New-IncrementalSnapshot'
    'Get-SnapshotManifest'
    # Snapshot Export
    'Export-PackSnapshot'
    'Export-WorkspaceSnapshot'
    'Export-SnapshotToRemote'
    'Compress-Snapshot'
    # Snapshot Import
    'Import-PackSnapshot'
    'Import-WorkspaceSnapshot'
    'Import-SnapshotFromRemote'
    'Test-SnapshotCompatibility'
    # Snapshot Management
    'Get-SnapshotList'
    'Remove-Snapshot'
    'Restore-FromSnapshot'
    'Compare-Snapshots'
    # Encryption/Security
    'Protect-Snapshot'
    'Unprotect-Snapshot'
    'Test-SnapshotIntegrity'
)
