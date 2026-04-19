#requires -Version 5.1
<#
.SYNOPSIS
    Retrieval Cache and Invalidation Module for LLM Workflow Platform - Phase 5.

.DESCRIPTION
    Implements Section 14.4 Retrieval Cache and Invalidation for the LLM Workflow platform.
    
    Cache Key Components:
    - Query hash (SHA256 of normalized query)
    - Retrieval profile identifier
    - Active pack versions
    - Project/workspace context
    - Taxonomy version
    - Engine-target filters
    
    Cache Invalidation Triggers:
    - Promoted pack build changes
    - Deprecation/tombstone changes
    - Private-project pack updates
    - Extraction schema or ranking changes
    
    Features:
    - SHA256-based cache key generation
    - Configurable TTL (1 hour default, 24 hours for API lookups)
    - LRU eviction with max 1000 entries
    - Atomic file operations using JSON Lines format
    - Thread-safe with file locking
    - Size limits and automatic maintenance

.NOTES
    File: RetrievalCache.ps1
    Version: 1.0.0
    Author: LLM Workflow Team
    Phase: 5 - Retrieval and Answer Integrity

.EXAMPLE
    # Store a retrieval result
    Set-CachedRetrieval -Query "How do I use signals?" `
                        -RetrievalProfile "godot-expert" `
                        -Result $retrievalResult `
                        -Context @{ workspaceId = "ws-001"; engineTarget = "godot4" } `
                        -PackVersions @{ "godot-engine" = "v2.1.0" }

.EXAMPLE
    # Retrieve cached result
    $cached = Get-CachedRetrieval -Query "How do I use signals?" `
                                  -RetrievalProfile "godot-expert" `
                                  -Context @{ workspaceId = "ws-001"; engineTarget = "godot4" } `
                                  -PackVersions @{ "godot-engine" = "v2.1.0" }

.EXAMPLE
    # Invalidate cache after pack update
    Invoke-PackCacheInvalidation -PackId "godot-engine" -NewVersion "v2.2.0"

.EXAMPLE
    # Run cache maintenance
    Invoke-CacheMaintenance -MaxAgeHours 24
#>

Set-StrictMode -Version Latest

#===============================================================================
# Configuration and Constants
#===============================================================================

$script:CacheSchemaVersion = 1
$script:DefaultCacheDirectory = ".llm-workflow/cache"
$script:DefaultCacheFileName = "retrieval-cache.jsonl"
$script:DefaultConfigFileName = "retrieval-cache-config.json"
$script:DefaultLockName = "retrieval-cache"

# Default configuration
$script:DefaultConfig = @{
    schemaVersion = $script:CacheSchemaVersion
    defaultTTLMinutes = 60           # 1 hour for normal queries
    apiLookupTTLMinutes = 1440       # 24 hours for API lookups
    maxEntries = 1000                # Maximum cache entries
    maxCacheSizeMB = 100             # Maximum cache size in MB
    maintenanceIntervalHours = 6     # How often to run maintenance
    hashAlgorithm = "SHA256"         # Hash algorithm for cache keys
    compressionEnabled = $false      # Whether to compress cache entries
    writeBufferSize = 10             # Number of writes before flush
    lastModified = [DateTime]::UtcNow.ToString("yyyy-MM-ddTHH:mm:ssZ")
}

# Telemetry is now handled via centralized helpers in telemetry/TelemetryHelpers.ps1


# In-memory write buffer for batching
$script:WriteBuffer = [System.Collections.Generic.List[hashtable]]::new()
$script:ConfigCache = $null
$script:ConfigCacheTimestamp = [DateTime]::MinValue

#===============================================================================
# Cache Key Generation (Section 14.4)
#===============================================================================

<#
.SYNOPSIS
    Generates a cache key for retrieval queries.

.DESCRIPTION
    Creates a SHA256 hash-based cache key from:
    - Normalized query string
    - Retrieval profile
    - Pack versions (sorted for consistency)
    - Workspace/project context
    - Taxonomy version
    - Engine-target filters

.PARAMETER Query
    The search query string.

.PARAMETER RetrievalProfile
    The retrieval profile identifier (e.g., "godot-expert", "rpgmaker-beginner").

.PARAMETER Context
    Hashtable containing workspace context including:
    - workspaceId: The workspace identifier
    - engineTarget: Target engine (e.g., "godot4", "rpgmaker-mz")
    - taxonomyVersion: Version of the taxonomy
    - projectRoot: Project root path

.PARAMETER PackVersions
    Hashtable mapping pack IDs to their versions.

.OUTPUTS
    System.String. The SHA256 cache key.

.EXAMPLE
    $key = Get-RetrievalCacheKey -Query "How do I use signals?" `
                                  -RetrievalProfile "godot-expert" `
                                  -Context @{ workspaceId = "ws-001"; engineTarget = "godot4" } `
                                  -PackVersions @{ "godot-engine" = "v2.1.0" }
#>
function Get-RetrievalCacheKey {
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Query,

        [Parameter(Mandatory = $true)]
        [string]$RetrievalProfile,

        [Parameter()]
        [hashtable]$Context = @{},

        [Parameter()]
        [hashtable]$PackVersions = @{}
    )

    process {
        # Normalize query: lowercase, trim, collapse whitespace
        $normalizedQuery = $Query.ToLowerInvariant().Trim() -replace '\s+', ' '

        # Create ordered components for consistent hashing
        $components = [System.Collections.Generic.List[string]]::new()

        # 1. Query hash component
        $components.Add("q:$normalizedQuery")

        # 2. Retrieval profile
        $components.Add("p:$($RetrievalProfile.ToLowerInvariant())")

        # 3. Pack versions (sorted by key for consistency)
        if ($PackVersions -and $PackVersions.Count -gt 0) {
            $sortedPacks = $PackVersions.GetEnumerator() | Sort-Object -Property Key
            $packVersionString = ($sortedPacks | ForEach-Object { "$($_.Key)=$($_.Value)" }) -join ";"
            $components.Add("v:$packVersionString")
        }

        # 4. Context components
        if ($Context) {
            # Workspace ID
            if ($Context.ContainsKey("workspaceId") -and -not [string]::IsNullOrWhiteSpace($Context.workspaceId)) {
                $components.Add("w:$($Context.workspaceId)")
            }

            # Engine target
            if ($Context.ContainsKey("engineTarget") -and -not [string]::IsNullOrWhiteSpace($Context.engineTarget)) {
                $components.Add("e:$($Context.engineTarget.ToLowerInvariant())")
            }

            # Taxonomy version
            if ($Context.ContainsKey("taxonomyVersion") -and -not [string]::IsNullOrWhiteSpace($Context.taxonomyVersion)) {
                $components.Add("t:$($Context.taxonomyVersion)")
            }
        }

        # Combine all components
        $keyString = $components -join "|"

        # Generate SHA256 hash
        $sha256 = [System.Security.Cryptography.SHA256]::Create()
        $bytes = [System.Text.Encoding]::UTF8.GetBytes($keyString)
        $hashBytes = $sha256.ComputeHash($bytes)
        $sha256.Dispose()

        # Convert to hex string
        $hashString = [BitConverter]::ToString($hashBytes) -replace '-', ''

        Write-Verbose "[RetrievalCache] Generated cache key: $hashString from components: $keyString"
        return $hashString.ToLowerInvariant()
    }
}

<#
.SYNOPSIS
    Generates a hash of the query string only.

.DESCRIPTION
    Creates a simple SHA256 hash of the normalized query for quick lookup.

.PARAMETER Query
    The query string to hash.

.OUTPUTS
    System.String. The SHA256 query hash.
#>
function Get-QueryHash {
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Query
    )

    process {
        $normalizedQuery = $Query.ToLowerInvariant().Trim() -replace '\s+', ' '
        $sha256 = [System.Security.Cryptography.SHA256]::Create()
        $bytes = [System.Text.Encoding]::UTF8.GetBytes($normalizedQuery)
        $hashBytes = $sha256.ComputeHash($bytes)
        $sha256.Dispose()

        return ([BitConverter]::ToString($hashBytes) -replace '-', '').ToLowerInvariant()
    }
}

#===============================================================================
# Cache Storage Functions
#===============================================================================

<#
.SYNOPSIS
    Stores a retrieval result in the cache.

.DESCRIPTION
    Saves a retrieval result to the cache with proper metadata, TTL, and
    automatic eviction if size limits are exceeded.

.PARAMETER Query
    The original search query.

.PARAMETER RetrievalProfile
    The retrieval profile used.

.PARAMETER Result
    The retrieval result data to cache.

.PARAMETER Context
    Hashtable containing workspace context.

.PARAMETER PackVersions
    Hashtable of pack IDs to versions used for this retrieval.

.PARAMETER TTL
    Time-to-live duration. Defaults to 1 hour from config.

.PARAMETER IsAPILookup
    If specified, uses the longer API lookup TTL (24 hours).

.PARAMETER ProjectRoot
    The project root directory. Defaults to current directory.

.PARAMETER SkipEviction
    Skip LRU eviction check (useful for batch operations).

.OUTPUTS
    PSCustomObject. Cache entry metadata including key and expiration.

.EXAMPLE
    Set-CachedRetrieval -Query "How do I use signals?" `
                        -RetrievalProfile "godot-expert" `
                        -Result $result `
                        -PackVersions @{ "godot-engine" = "v2.1.0" }
#>
function Set-CachedRetrieval {
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Query,

        [Parameter(Mandatory = $true)]
        [string]$RetrievalProfile,

        [Parameter(Mandatory = $true)]
        [hashtable]$Result,

        [Parameter()]
        [hashtable]$Context = @{},

        [Parameter()]
        [hashtable]$PackVersions = @{},

        [Parameter()]
        [TimeSpan]$TTL = [TimeSpan]::Zero,

        [Parameter()]
        [switch]$IsAPILookup = $false,

        [Parameter()]
        [string]$ProjectRoot = ".",

        [Parameter()]
        [switch]$SkipEviction = $false,

        [Parameter()]
        [string]$CorrelationId = [Guid]::NewGuid().ToString()
    )

    process {
        $traceAttributes = @{
            Query = $Query
            RetrievalProfile = $RetrievalProfile
            IsAPILookup = $IsAPILookup.IsPresent
        }
        [void](Write-FunctionTelemetry -CorrelationId $CorrelationId -FunctionName 'Set-CachedRetrieval' -Attributes $traceAttributes)
        $config = Get-RetrievalCacheConfig -ProjectRoot $ProjectRoot

        # Determine TTL
        if ($TTL -eq [TimeSpan]::Zero) {
            $ttlMinutes = if ($IsAPILookup) { $config.apiLookupTTLMinutes } else { $config.defaultTTLMinutes }
            $TTL = [TimeSpan]::FromMinutes($ttlMinutes)
        }

        # Generate cache key
        $cacheKey = Get-RetrievalCacheKey -Query $Query `
                                          -RetrievalProfile $RetrievalProfile `
                                          -Context $Context `
                                          -PackVersions $PackVersions

        $queryHash = Get-QueryHash -Query $Query

        # Create cache entry
        $now = [DateTime]::UtcNow
        $entry = [ordered]@{
            key = $cacheKey
            createdAt = $now.ToString("yyyy-MM-ddTHH:mm:ssZ")
            expiresAt = $now.Add($TTL).ToString("yyyy-MM-ddTHH:mm:ssZ")
            query = $Query
            queryHash = $queryHash
            retrievalProfile = $RetrievalProfile
            packVersions = if ($PackVersions) { $PackVersions } else { @{} }
            taxonomyVersion = if ($Context.ContainsKey("taxonomyVersion")) { $Context.taxonomyVersion } else { "1" }
            context = @{
                workspaceId = if ($Context.ContainsKey("workspaceId")) { $Context.workspaceId } else { "" }
                engineTarget = if ($Context.ContainsKey("engineTarget")) { $Context.engineTarget } else { "" }
                projectRoot = $ProjectRoot
            }
            result = $Result
            metadata = [ordered]@{
                hitCount = 0
                lastAccessed = $null
                accessCount = 0
                entrySizeBytes = 0
            }
        }

        # Calculate entry size (approximate)
        $jsonTemp = $entry | ConvertTo-Json -Depth 10 -Compress
        $entry.metadata.entrySizeBytes = [System.Text.Encoding]::UTF8.GetByteCount($jsonTemp)

        # Acquire lock for thread safety
        $lockAcquired = $false
        $lockFile = $null
        $cacheFile = Get-CacheFilePath -ProjectRoot $ProjectRoot

        try {
            # Ensure cache directory exists
            $cacheDir = Split-Path -Parent $cacheFile
            if (-not (Test-Path -LiteralPath $cacheDir)) {
                New-Item -ItemType Directory -Path $cacheDir -Force | Out-Null
            }

            # Acquire file lock
            $lockFile = Acquire-CacheLock -ProjectRoot $ProjectRoot -TimeoutSeconds 30
            $lockAcquired = $true

            # Load existing cache (ensure array type)
            $cacheEntries = [array](Read-CacheFile -CacheFile $cacheFile)
            if ($null -eq $cacheEntries) { $cacheEntries = @() }

            # Remove any existing entry with same key
            $cacheEntries = @($cacheEntries | Where-Object { $_.key -ne $cacheKey })

            # Check if we need to evict entries
            if (-not $SkipEviction -and $cacheEntries.Count -ge $config.maxEntries) {
                $entriesToEvict = $cacheEntries.Count - $config.maxEntries + 1
                Write-Verbose "[RetrievalCache] Evicting $entriesToEvict entries due to size limit"
                $cacheEntries = Perform-LRUEviction -Entries $cacheEntries -Count $entriesToEvict
            }

            # Add new entry
            $cacheEntries += $entry

            # Write cache back to file atomically
            Write-CacheFile -CacheFile $cacheFile -Entries $cacheEntries

            Write-Verbose "[RetrievalCache] Stored cache entry: $cacheKey (expires: $($entry.expiresAt))"
        }
        finally {
            if ($lockAcquired -and $lockFile) {
                Release-CacheLock -LockFile $lockFile
            }
        }

        return [pscustomobject]@{
            Success = $true
            Key = $cacheKey
            ExpiresAt = $entry.expiresAt
            EntrySizeBytes = $entry.metadata.entrySizeBytes
        }
    }
}

<#
.SYNOPSIS
    Retrieves a cached retrieval result.

.DESCRIPTION
    Looks up a cached retrieval result by query, profile, and context.
    Updates hit count and last accessed timestamp on successful retrieval.

.PARAMETER Query
    The search query.

.PARAMETER RetrievalProfile
    The retrieval profile used.

.PARAMETER Context
    Hashtable containing workspace context.

.PARAMETER PackVersions
    Hashtable of pack IDs to versions.

.PARAMETER ProjectRoot
    The project root directory. Defaults to current directory.

.PARAMETER SkipUpdateStats
    Skip updating hit count and last accessed timestamp.

.OUTPUTS
    PSCustomObject. The cache entry if found and valid, $null otherwise.

.EXAMPLE
    $cached = Get-CachedRetrieval -Query "How do I use signals?" `
                                  -RetrievalProfile "godot-expert" `
                                  -PackVersions @{ "godot-engine" = "v2.1.0" }
#>
function Get-CachedRetrieval {
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Query,

        [Parameter(Mandatory = $true)]
        [string]$RetrievalProfile,

        [Parameter()]
        [hashtable]$Context = @{},

        [Parameter()]
        [hashtable]$PackVersions = @{},

        [Parameter()]
        [string]$ProjectRoot = ".",

        [Parameter()]
        [switch]$SkipUpdateStats = $false,

        [Parameter()]
        [string]$CorrelationId = [Guid]::NewGuid().ToString()
    )

    process {
        $traceAttributes = @{
            Query = $Query
            RetrievalProfile = $RetrievalProfile
        }
        [void](Write-FunctionTelemetry -CorrelationId $CorrelationId -FunctionName 'Get-CachedRetrieval' -Attributes $traceAttributes)
        # Generate cache key
        $cacheKey = Get-RetrievalCacheKey -Query $Query `
                                          -RetrievalProfile $RetrievalProfile `
                                          -Context $Context `
                                          -PackVersions $PackVersions

        $cacheFile = Get-CacheFilePath -ProjectRoot $ProjectRoot

        # Check if cache file exists
        if (-not (Test-Path -LiteralPath $cacheFile)) {
            Write-Verbose "[RetrievalCache] Cache file not found: $cacheFile"
            return $null
        }

        $lockAcquired = $false
        $lockFile = $null
        $entry = $null

        try {
            # Acquire lock
            $lockFile = Acquire-CacheLock -ProjectRoot $ProjectRoot -TimeoutSeconds 10
            $lockAcquired = $true

            # Read cache and find entry
            $cacheEntries = [array](Read-CacheFile -CacheFile $cacheFile)
            if ($null -eq $cacheEntries) { $cacheEntries = @() }
            $entry = $cacheEntries | Where-Object { $_.key -eq $cacheKey } | Select-Object -First 1

            if (-not $entry) {
                Write-Verbose "[RetrievalCache] Cache miss for key: $cacheKey"
                return $null
            }

            # Validate entry
            if (-not (Test-CacheEntryValid -CacheEntry $entry)) {
                Write-Verbose "[RetrievalCache] Cache entry expired or invalid: $cacheKey"
                
                # Remove expired entry
                $cacheEntries = @($cacheEntries | Where-Object { $_.key -ne $cacheKey })
                Write-CacheFile -CacheFile $cacheFile -Entries $cacheEntries
                
                return $null
            }

            # Update statistics
            if (-not $SkipUpdateStats) {
                $entry.metadata.hitCount++
                $entry.metadata.lastAccessed = [DateTime]::UtcNow.ToString("yyyy-MM-ddTHH:mm:ssZ")
                $entry.metadata.accessCount = $entry.metadata.hitCount

                # Write updated cache
                Write-CacheFile -CacheFile $cacheFile -Entries $cacheEntries
            }

            Write-Verbose "[RetrievalCache] Cache hit for key: $cacheKey (hits: $($entry.metadata.hitCount))"
        }
        finally {
            if ($lockAcquired -and $lockFile) {
                Release-CacheLock -LockFile $lockFile
            }
        }

        # Return the entry without internal metadata
        return [pscustomobject]@{
            Key = $entry.key
            CreatedAt = $entry.createdAt
            ExpiresAt = $entry.expiresAt
            Query = $entry.query
            RetrievalProfile = $entry.retrievalProfile
            PackVersions = $entry.packVersions
            TaxonomyVersion = $entry.taxonomyVersion
            Context = $entry.context
            Result = $entry.result
            Metadata = $entry.metadata
        }
    }
}

<#
.SYNOPSIS
    Tests if a cache entry is valid (not expired).

.DESCRIPTION
    Checks if a cache entry has expired based on its expiresAt timestamp.

.PARAMETER CacheEntry
    The cache entry to validate.

.OUTPUTS
    System.Boolean. True if valid and not expired, false otherwise.

.EXAMPLE
    $isValid = Test-CacheEntryValid -CacheEntry $entry
#>
function Test-CacheEntryValid {
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [Parameter(Mandatory = $true)]
        [hashtable]$CacheEntry
    )

    process {
        # Check required fields
        if (-not $CacheEntry.ContainsKey("expiresAt") -or [string]::IsNullOrWhiteSpace($CacheEntry.expiresAt)) {
            Write-Verbose "[RetrievalCache] Invalid entry: missing expiresAt"
            return $false
        }

        if (-not $CacheEntry.ContainsKey("key") -or [string]::IsNullOrWhiteSpace($CacheEntry.key)) {
            Write-Verbose "[RetrievalCache] Invalid entry: missing key"
            return $false
        }

        # Parse expiration (handle both UTC and local times)
        try {
            $expiresAt = [DateTime]::MinValue
            $parsed = $false
            
            # Try parsing as round-trip format first (with 'Z' UTC marker)
            try {
                $expiresAt = [DateTime]::Parse($CacheEntry.expiresAt, [System.Globalization.CultureInfo]::InvariantCulture, [System.Globalization.DateTimeStyles]::RoundtripKind)
                $parsed = $true
            }
            catch {
                # Fallback to standard parse
                $expiresAt = [DateTime]::Parse($CacheEntry.expiresAt)
                $parsed = $true
            }
            
            if (-not $parsed) {
                return $false
            }
            
            $now = [DateTime]::UtcNow

            if ($expiresAt -le $now) {
                Write-Verbose "[RetrievalCache] Entry expired at $($CacheEntry.expiresAt)"
                return $false
            }
        }
        catch {
            Write-Verbose "[RetrievalCache] Failed to parse expiration date: $($CacheEntry.expiresAt)"
            return $false
        }

        return $true
    }
}

#===============================================================================
# Cache Invalidation Functions
#===============================================================================

<#
.SYNOPSIS
    Invalidates cache entries based on specified criteria.

.DESCRIPTION
    Removes cache entries matching the specified reason and criteria.
    Supports invalidation by pack, profile, or custom criteria.

.PARAMETER Reason
    The reason for invalidation: 'pack-update', 'schema-change', 'ranking-change', 'manual', or 'maintenance'.

.PARAMETER PackId
    Pack ID to invalidate. Use '*' for all packs (default).

.PARAMETER Criteria
    Additional criteria hashtable for selective invalidation.
    Can include: retrievalProfile, queryPattern, engineTarget, etc.

.PARAMETER ProjectRoot
    The project root directory. Defaults to current directory.

.PARAMETER DryRun
    If specified, returns what would be invalidated without actually removing.

.OUTPUTS
    PSCustomObject. Invalidation result with count of removed entries and affected keys.

.EXAMPLE
    Invoke-CacheInvalidation -Reason 'pack-update' -PackId 'godot-engine'

.EXAMPLE
    Invoke-CacheInvalidation -Reason 'manual' -Criteria @{ retrievalProfile = 'deprecated-profile' }
#>
function Invoke-CacheInvalidation {
    [CmdletBinding(SupportsShouldProcess = $true)]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory = $true)]
        [ValidateSet('pack-update', 'schema-change', 'ranking-change', 'manual', 'maintenance')]
        [string]$Reason,

        [Parameter()]
        [string]$PackId = '*',

        [Parameter()]
        [hashtable]$Criteria = @{},

        [Parameter()]
        [string]$ProjectRoot = ".",

        [Parameter()]
        [switch]$DryRun = $false
    )

    process {
        $cacheFile = Get-CacheFilePath -ProjectRoot $ProjectRoot

        if (-not (Test-Path -LiteralPath $cacheFile)) {
            Write-Verbose "[RetrievalCache] Cache file not found: $cacheFile"
            return [pscustomobject]@{
                Success = $true
                RemovedCount = 0
                AffectedKeys = @()
                Reason = $Reason
                Message = "Cache file not found, nothing to invalidate"
            }
        }

        $lockAcquired = $false
        $lockFile = $null
        $removedKeys = [System.Collections.Generic.List[string]]::new()

        try {
            # Acquire lock
            $lockFile = Acquire-CacheLock -ProjectRoot $ProjectRoot -TimeoutSeconds 30
            $lockAcquired = $true

            # Read cache
            $cacheEntries = @(Read-CacheFile -CacheFile $cacheFile)
            $originalCount = $cacheEntries.Count

            # Filter entries to keep (inverse of what to remove)
            $entriesToKeep = [System.Collections.Generic.List[hashtable]]::new()

            foreach ($entry in $cacheEntries) {
                $shouldRemove = $false

                # Check pack-based invalidation
                if ($PackId -ne '*' -and $entry.packVersions) {
                    if ($entry.packVersions.ContainsKey($PackId)) {
                        $shouldRemove = $true
                    }
                }

                # Check criteria-based invalidation
                if ($Criteria.Count -gt 0) {
                    # Check retrieval profile
                    if ($Criteria.ContainsKey("retrievalProfile") -and 
                        $entry.retrievalProfile -eq $Criteria.retrievalProfile) {
                        $shouldRemove = $true
                    }

                    # Check engine target
                    if ($Criteria.ContainsKey("engineTarget") -and 
                        $entry.context -and 
                        $entry.context.engineTarget -eq $Criteria.engineTarget) {
                        $shouldRemove = $true
                    }

                    # Check query pattern
                    if ($Criteria.ContainsKey("queryPattern") -and 
                        $entry.query -match $Criteria.queryPattern) {
                        $shouldRemove = $true
                    }

                    # Check taxonomy version
                    if ($Criteria.ContainsKey("taxonomyVersion") -and 
                        $entry.taxonomyVersion -eq $Criteria.taxonomyVersion) {
                        $shouldRemove = $true
                    }

                    # Check workspace
                    if ($Criteria.ContainsKey("workspaceId") -and 
                        $entry.context -and 
                        $entry.context.workspaceId -eq $Criteria.workspaceId) {
                        $shouldRemove = $true
                    }
                }

                # If wildcard pack specified, remove all (useful for schema changes)
                if ($PackId -eq '*' -and $Criteria.Count -eq 0 -and $Reason -eq 'schema-change') {
                    $shouldRemove = $true
                }

                if ($shouldRemove) {
                    $removedKeys.Add($entry.key)
                }
                else {
                    $entriesToKeep.Add($entry)
                }
            }

            $removedCount = $removedKeys.Count

            # Perform actual removal if not dry run
            if (-not $DryRun -and $removedCount -gt 0) {
                if ($PSCmdlet.ShouldProcess("$removedCount cache entries", "Invalidate")) {
                    Write-CacheFile -CacheFile $cacheFile -Entries $entriesToKeep
                    Write-Verbose "[RetrievalCache] Invalidated $removedCount entries (reason: $Reason)"
                }
            }
            elseif ($DryRun) {
                Write-Verbose "[RetrievalCache] Dry run: would invalidate $removedCount entries"
            }

            return [pscustomobject]@{
                Success = $true
                RemovedCount = $removedCount
                AffectedKeys = $removedKeys.ToArray()
                Reason = $Reason
                PackId = $PackId
                OriginalCount = $originalCount
                RemainingCount = $entriesToKeep.Count
                DryRun = $DryRun.IsPresent
            }
        }
        finally {
            if ($lockAcquired -and $lockFile) {
                Release-CacheLock -LockFile $lockFile
            }
        }
    }
}

<#
.SYNOPSIS
    Invalidates cache entries when a pack is updated.

.DESCRIPTION
    Removes all cache entries that depend on a specific pack version.
    Called when a pack is promoted, updated, or deprecated.

.PARAMETER PackId
    The ID of the updated pack.

.PARAMETER NewVersion
    The new version of the pack.

.PARAMETER ProjectRoot
    The project root directory. Defaults to current directory.

.PARAMETER UpdateType
    Type of update: 'promotion', 'deprecation', 'tombstone', 'private-update'.

.OUTPUTS
    PSCustomObject. Invalidation result.

.EXAMPLE
    Invoke-PackCacheInvalidation -PackId 'godot-engine' -NewVersion 'v2.2.0' -UpdateType 'promotion'
#>
function Invoke-PackCacheInvalidation {
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory = $true)]
        [string]$PackId,

        [Parameter()]
        [string]$NewVersion = "",

        [Parameter()]
        [string]$ProjectRoot = ".",

        [Parameter()]
        [ValidateSet('promotion', 'deprecation', 'tombstone', 'private-update', 'schema-change')]
        [string]$UpdateType = 'promotion'
    )

    process {
        Write-Verbose "[RetrievalCache] Processing pack update: $PackId -> $NewVersion (type: $UpdateType)"

        # Map update type to invalidation reason
        $reason = switch ($UpdateType) {
            'promotion' { 'pack-update' }
            'deprecation' { 'pack-update' }
            'tombstone' { 'pack-update' }
            'private-update' { 'pack-update' }
            'schema-change' { 'schema-change' }
            default { 'pack-update' }
        }

        # Perform invalidation
        $result = Invoke-CacheInvalidation -Reason $reason `
                                          -PackId $PackId `
                                          -ProjectRoot $ProjectRoot

        # Add pack-specific metadata
        $result | Add-Member -NotePropertyName 'PackId' -NotePropertyValue $PackId -Force
        $result | Add-Member -NotePropertyName 'NewVersion' -NotePropertyValue $NewVersion -Force
        $result | Add-Member -NotePropertyName 'UpdateType' -NotePropertyValue $UpdateType -Force

        Write-Verbose "[RetrievalCache] Pack invalidation complete for $PackId`: removed $($result.RemovedCount) entries"

        return $result
    }
}

<#
.SYNOPSIS
    Clears the entire retrieval cache.

.DESCRIPTION
    Removes all cache entries. Use with caution in production.

.PARAMETER Force
    Skip confirmation prompt.

.PARAMETER ProjectRoot
    The project root directory. Defaults to current directory.

.PARAMETER BackupFirst
    Create a backup before clearing.

.OUTPUTS
    PSCustomObject. Result of the clear operation.

.EXAMPLE
    Clear-RetrievalCache -Force
#>
function Clear-RetrievalCache {
    [CmdletBinding(SupportsShouldProcess = $true)]
    [OutputType([pscustomobject])]
    param(
        [Parameter()]
        [switch]$Force = $false,

        [Parameter()]
        [string]$ProjectRoot = ".",

        [Parameter()]
        [switch]$BackupFirst = $true
    )

    process {
        $cacheFile = Get-CacheFilePath -ProjectRoot $ProjectRoot

        if (-not (Test-Path -LiteralPath $cacheFile)) {
            return [pscustomobject]@{
                Success = $true
                Message = "Cache file does not exist"
                BackupPath = $null
            }
        }

        # Get entry count before clearing
        $entries = @(Read-CacheFile -CacheFile $cacheFile)
        $entryCount = $entries.Count

        $backupPath = $null

        if ($PSCmdlet.ShouldProcess("retrieval cache ($entryCount entries)", "Clear")) {
            if ($Force -or $PSCmdlet.ShouldContinue("Are you sure you want to clear the cache?", "Confirm Cache Clear")) {
                
                $lockAcquired = $false
                $lockFile = $null

                try {
                    # Create backup if requested
                    if ($BackupFirst) {
                        $backupPath = "$cacheFile.backup.$([DateTime]::Now.ToString('yyyyMMddHHmmss'))"
                        Copy-Item -LiteralPath $cacheFile -Destination $backupPath -Force
                    }

                    # Acquire lock
                    $lockFile = Acquire-CacheLock -ProjectRoot $ProjectRoot -TimeoutSeconds 30
                    $lockAcquired = $true

                    # Write empty cache
                    Write-CacheFile -CacheFile $cacheFile -Entries @()

                    Write-Verbose "[RetrievalCache] Cache cleared: $entryCount entries removed"

                    return [pscustomobject]@{
                        Success = $true
                        RemovedCount = $entryCount
                        BackupPath = $backupPath
                        Message = "Cache cleared successfully"
                    }
                }
                finally {
                    if ($lockAcquired -and $lockFile) {
                        Release-CacheLock -LockFile $lockFile
                    }
                }
            }
        }

        return [pscustomobject]@{
            Success = $false
            Message = "Operation cancelled"
            RemovedCount = 0
        }
    }
}

#===============================================================================
# Cache Maintenance Functions
#===============================================================================

<#
.SYNOPSIS
    Performs cache maintenance by removing expired entries.

.DESCRIPTION
    Scans the cache and removes entries that have exceeded their TTL.
    Can also remove entries older than a specified age regardless of TTL.

.PARAMETER MaxAgeHours
    Maximum age in hours. Entries older than this are removed even if not expired.

.PARAMETER ProjectRoot
    The project root directory. Defaults to current directory.

.PARAMETER DryRun
    If specified, returns what would be removed without actually removing.

.OUTPUTS
    PSCustomObject. Maintenance result with counts of removed and kept entries.

.EXAMPLE
    Invoke-CacheMaintenance -MaxAgeHours 24
#>
function Invoke-CacheMaintenance {
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter()]
        [int]$MaxAgeHours = 24,

        [Parameter()]
        [string]$ProjectRoot = ".",

        [Parameter()]
        [switch]$DryRun = $false
    )

    process {
        $cacheFile = Get-CacheFilePath -ProjectRoot $ProjectRoot

        if (-not (Test-Path -LiteralPath $cacheFile)) {
            return [pscustomobject]@{
                Success = $true
                RemovedCount = 0
                ExpiredCount = 0
                OldCount = 0
                KeptCount = 0
                Message = "Cache file not found"
            }
        }

        $lockAcquired = $false
        $lockFile = $null

        try {
            # Acquire lock
            $lockFile = Acquire-CacheLock -ProjectRoot $ProjectRoot -TimeoutSeconds 60
            $lockAcquired = $true

            # Read cache
            $cacheEntries = @(Read-CacheFile -CacheFile $cacheFile)
            $originalCount = $cacheEntries.Count

            $now = [DateTime]::UtcNow
            $maxAge = [TimeSpan]::FromHours($MaxAgeHours)

            $expiredCount = 0
            $oldCount = 0
            $keptEntries = [System.Collections.Generic.List[hashtable]]::new()
            $removedKeys = [System.Collections.Generic.List[string]]::new()

            foreach ($entry in $cacheEntries) {
                $remove = $false
                $reason = ""

                # Check if expired
                if (-not (Test-CacheEntryValid -CacheEntry $entry)) {
                    $remove = $true
                    $reason = "expired"
                    $expiredCount++
                }
                else {
                    # Check if too old
                    try {
                        $createdAt = [DateTime]::Parse($entry.createdAt)
                        if (($now - $createdAt) -gt $maxAge) {
                            $remove = $true
                            $reason = "too old (> $MaxAgeHours hours)"
                            $oldCount++
                        }
                    }
                    catch {
                        # Invalid date, consider for removal
                        $remove = $true
                        $reason = "invalid date"
                        $oldCount++
                    }
                }

                if ($remove) {
                    $removedKeys.Add($entry.key)
                    Write-Verbose "[RetrievalCache] Maintenance: removing entry $($entry.key) ($reason)"
                }
                else {
                    $keptEntries.Add($entry)
                }
            }

            $removedCount = $removedKeys.Count
            $keptCount = $keptEntries.Count

            # Write updated cache if not dry run
            if (-not $DryRun -and $removedCount -gt 0) {
                Write-CacheFile -CacheFile $cacheFile -Entries $keptEntries
            }

            Write-Verbose "[RetrievalCache] Maintenance complete: removed $removedCount (expired: $expiredCount, old: $oldCount), kept $keptCount"

            return [pscustomobject]@{
                Success = $true
                RemovedCount = $removedCount
                ExpiredCount = $expiredCount
                OldCount = $oldCount
                KeptCount = $keptCount
                OriginalCount = $originalCount
                DryRun = $DryRun.IsPresent
                RemovedKeys = $removedKeys.ToArray()
            }
        }
        finally {
            if ($lockAcquired -and $lockFile) {
                Release-CacheLock -LockFile $lockFile
            }
        }
    }
}

<#
.SYNOPSIS
    Gets cache statistics.

.DESCRIPTION
    Returns statistics about the cache including entry count, size,
    hit rates, and expiration distribution.

.PARAMETER ProjectRoot
    The project root directory. Defaults to current directory.

.OUTPUTS
    PSCustomObject. Cache statistics.

.EXAMPLE
    $stats = Get-RetrievalCacheStats
    Write-Host "Cache has $($stats.EntryCount) entries"
#>
function Get-RetrievalCacheStats {
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter()]
        [string]$ProjectRoot = "."
    )

    process {
        $cacheFile = Get-CacheFilePath -ProjectRoot $ProjectRoot
        $config = Get-RetrievalCacheConfig -ProjectRoot $ProjectRoot

        if (-not (Test-Path -LiteralPath $cacheFile)) {
            return [pscustomobject]@{
                CacheFile = $cacheFile
                Exists = $false
                EntryCount = 0
                TotalSizeBytes = 0
                TotalSizeMB = 0
                ExpiredCount = 0
                ValidCount = 0
                HitRate = 0
                AverageHits = 0
                Config = $config
            }
        }

        $entries = @(Read-CacheFile -CacheFile $cacheFile)
        $now = [DateTime]::UtcNow

        $totalHits = 0
        $totalSize = 0
        $expiredCount = 0
        $accessedCount = 0

        $profileStats = @{}
        $packStats = @{}

        foreach ($entry in $entries) {
            # Count hits
            if ($entry.metadata -and $entry.metadata.hitCount) {
                $totalHits += $entry.metadata.hitCount
                if ($entry.metadata.hitCount -gt 0) {
                    $accessedCount++
                }
            }

            # Count size
            if ($entry.metadata -and $entry.metadata.entrySizeBytes) {
                $totalSize += $entry.metadata.entrySizeBytes
            }

            # Check expiration
            if (-not (Test-CacheEntryValid -CacheEntry $entry)) {
                $expiredCount++
            }

            # Profile stats
            if ($entry.retrievalProfile) {
                if (-not $profileStats.ContainsKey($entry.retrievalProfile)) {
                    $profileStats[$entry.retrievalProfile] = 0
                }
                $profileStats[$entry.retrievalProfile]++
            }

            # Pack stats
            if ($entry.packVersions) {
                foreach ($packId in $entry.packVersions.Keys) {
                    if (-not $packStats.ContainsKey($packId)) {
                        $packStats[$packId] = 0
                    }
                    $packStats[$packId]++
                }
            }
        }

        $entryCount = $entries.Count
        $validCount = $entryCount - $expiredCount
        $averageHits = if ($entryCount -gt 0) { $totalHits / $entryCount } else { 0 }

        # Calculate hit rate (entries accessed / total entries)
        $hitRate = if ($entryCount -gt 0) { $accessedCount / $entryCount } else { 0 }

        $fileInfo = Get-Item -LiteralPath $cacheFile

        return [pscustomobject]@{
            CacheFile = $cacheFile
            Exists = $true
            EntryCount = $entryCount
            ValidCount = $validCount
            ExpiredCount = $expiredCount
            TotalSizeBytes = $totalSize
            TotalSizeMB = [math]::Round($totalSize / 1MB, 2)
            FileSizeBytes = $fileInfo.Length
            FileSizeMB = [math]::Round($fileInfo.Length / 1MB, 2)
            TotalHits = $totalHits
            AverageHits = [math]::Round($averageHits, 2)
            HitRate = [math]::Round($hitRate, 4)
            MaxEntries = $config.maxEntries
            UtilizationPercent = if ($config.maxEntries -gt 0) { [math]::Round(($entryCount / $config.maxEntries) * 100, 2) } else { 0 }
            ProfileDistribution = $profileStats
            PackDistribution = $packStats
            LastMaintenance = $config.lastModified
            Config = $config
        }
    }
}

#===============================================================================
# Configuration Functions
#===============================================================================

<#
.SYNOPSIS
    Gets the retrieval cache configuration.

.DESCRIPTION
    Loads the cache configuration from file or returns defaults.
    Caches the configuration in memory for performance.

.PARAMETER ProjectRoot
    The project root directory. Defaults to current directory.

.PARAMETER ForceReload
    Force reload from file, bypassing in-memory cache.

.OUTPUTS
    Hashtable. The cache configuration.

.EXAMPLE
    $config = Get-RetrievalCacheConfig
    Write-Host "Default TTL: $($config.defaultTTLMinutes) minutes"
#>
function Get-RetrievalCacheConfig {
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [Parameter()]
        [string]$ProjectRoot = ".",

        [Parameter()]
        [switch]$ForceReload = $false
    )

    process {
        # Check in-memory cache first
        if (-not $ForceReload -and $script:ConfigCache -ne $null) {
            $cacheAge = [DateTime]::Now - $script:ConfigCacheTimestamp
            if ($cacheAge.TotalMinutes -lt 5) {
                return $script:ConfigCache
            }
        }

        $configPath = Get-CacheConfigPath -ProjectRoot $ProjectRoot

        if (Test-Path -LiteralPath $configPath) {
            try {
                $json = Get-Content -LiteralPath $configPath -Raw -ErrorAction Stop
                $config = $json | ConvertFrom-Json -AsHashtable
                
                # Merge with defaults to ensure all keys exist
                $mergedConfig = $script:DefaultConfig.Clone()
                foreach ($key in $config.Keys) {
                    $mergedConfig[$key] = $config[$key]
                }

                # Update in-memory cache
                $script:ConfigCache = $mergedConfig
                $script:ConfigCacheTimestamp = [DateTime]::Now

                return $mergedConfig
            }
            catch {
                Write-Warning "[RetrievalCache] Failed to load config from $configPath`: $_"
                return $script:DefaultConfig
            }
        }

        return $script:DefaultConfig
    }
}

<#
.SYNOPSIS
    Sets the retrieval cache configuration.

.DESCRIPTION
    Saves the cache configuration to file.

.PARAMETER Config
    Hashtable containing configuration values to set.
    Can include: defaultTTLMinutes, apiLookupTTLMinutes, maxEntries, etc.

.PARAMETER ProjectRoot
    The project root directory. Defaults to current directory.

.OUTPUTS
    PSCustomObject. Result of the save operation.

.EXAMPLE
    Set-RetrievalCacheConfig -Config @{ defaultTTLMinutes = 120; maxEntries = 2000 }
#>
function Set-RetrievalCacheConfig {
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory = $true)]
        [hashtable]$Config,

        [Parameter()]
        [string]$ProjectRoot = "."
    )

    process {
        # Load existing config
        $existingConfig = Get-RetrievalCacheConfig -ProjectRoot $ProjectRoot -ForceReload

        # Merge new config
        $newConfig = $existingConfig.Clone()
        foreach ($key in $Config.Keys) {
            $newConfig[$key] = $Config[$key]
        }

        # Update timestamp
        $newConfig["lastModified"] = [DateTime]::UtcNow.ToString("yyyy-MM-ddTHH:mm:ssZ")

        $configPath = Get-CacheConfigPath -ProjectRoot $ProjectRoot

        # Ensure directory exists
        $configDir = Split-Path -Parent $configPath
        if (-not (Test-Path -LiteralPath $configDir)) {
            New-Item -ItemType Directory -Path $configDir -Force | Out-Null
        }

        try {
            # Convert to JSON and save
            $json = $newConfig | ConvertTo-Json -Depth 5
            $json | Out-File -FilePath $configPath -Encoding UTF8 -Force

            # Update in-memory cache
            $script:ConfigCache = $newConfig
            $script:ConfigCacheTimestamp = [DateTime]::Now

            Write-Verbose "[RetrievalCache] Configuration saved to: $configPath"

            return [pscustomobject]@{
                Success = $true
                ConfigPath = $configPath
                Config = $newConfig
            }
        }
        catch {
            throw "Failed to save cache configuration: $_"
        }
    }
}

#===============================================================================
# Internal Helper Functions
#===============================================================================

<#
.SYNOPSIS
    Gets the cache file path.
#>
function Get-CacheFilePath {
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [string]$ProjectRoot = "."
    )

    $resolvedRoot = Resolve-Path -Path $ProjectRoot -ErrorAction SilentlyContinue
    if (-not $resolvedRoot) {
        $resolvedRoot = $ProjectRoot
    }

    return Join-Path $resolvedRoot (Join-Path $script:DefaultCacheDirectory $script:DefaultCacheFileName)
}

<#
.SYNOPSIS
    Gets the cache config file path.
#>
function Get-CacheConfigPath {
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [string]$ProjectRoot = "."
    )

    $resolvedRoot = Resolve-Path -Path $ProjectRoot -ErrorAction SilentlyContinue
    if (-not $resolvedRoot) {
        $resolvedRoot = $ProjectRoot
    }

    return Join-Path $resolvedRoot (Join-Path $script:DefaultCacheDirectory $script:DefaultConfigFileName)
}

<#
.SYNOPSIS
    Acquires a file lock for thread-safe cache operations.
#>
function Acquire-CacheLock {
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [string]$ProjectRoot = ".",
        [int]$TimeoutSeconds = 30
    )

    $lockDir = Join-Path $ProjectRoot ".llm-workflow/locks"
    if (-not (Test-Path -LiteralPath $lockDir)) {
        New-Item -ItemType Directory -Path $lockDir -Force | Out-Null
    }

    $lockFile = Join-Path $lockDir "$script:DefaultLockName.lock"
    $startTime = [DateTime]::Now

    while ($true) {
        try {
            # Try to create lock file exclusively
            $stream = [System.IO.File]::Open($lockFile, [System.IO.FileMode]::CreateNew, 
                [System.IO.FileAccess]::Write, [System.IO.FileShare]::None)
            $stream.Close()
            $stream.Dispose()

            # Write lock metadata
            $lockContent = @{
                pid = $PID
                host = [Environment]::MachineName
                timestamp = [DateTime]::UtcNow.ToString("yyyy-MM-ddTHH:mm:ssZ")
            } | ConvertTo-Json

            [System.IO.File]::WriteAllText($lockFile, $lockContent, [System.Text.Encoding]::UTF8)

            return $lockFile
        }
        catch [System.IO.IOException] {
            $elapsed = ([DateTime]::Now - $startTime).TotalSeconds
            if ($elapsed -ge $TimeoutSeconds) {
                throw "Timeout waiting for cache lock after $TimeoutSeconds seconds"
            }
            Start-Sleep -Milliseconds 50
        }
    }
}

<#
.SYNOPSIS
    Releases the cache file lock.
#>
function Release-CacheLock {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$LockFile
    )

    if (Test-Path -LiteralPath $LockFile) {
        try {
            Remove-Item -LiteralPath $LockFile -Force -ErrorAction Stop
        }
        catch {
            Write-Warning "[RetrievalCache] Failed to release lock: $_"
        }
    }
}

<#
.SYNOPSIS
    Reads the cache file and returns entries.
#>
function Read-CacheFile {
    [CmdletBinding()]
    [OutputType([array])]
    param(
        [Parameter(Mandatory = $true)]
        [string]$CacheFile
    )

    if (-not (Test-Path -LiteralPath $CacheFile)) {
        return @()
    }

    try {
        $lines = [System.IO.File]::ReadAllLines($CacheFile, [System.Text.Encoding]::UTF8)
        $entries = [System.Collections.Generic.List[hashtable]]::new()

        foreach ($line in $lines) {
            if ([string]::IsNullOrWhiteSpace($line)) {
                continue
            }

            try {
                # Parse JSON (PS 5.1 doesn't have -AsHashtable, so we convert PSCustomObject)
                $parsed = $line | ConvertFrom-Json
                $entry = ConvertTo-Hashtable -InputObject $parsed
                
                if ($entry -and $entry.ContainsKey('key')) {
                    $entries.Add($entry)
                }
            }
            catch {
                Write-Verbose "[RetrievalCache] Skipping invalid cache line: $_"
            }
        }

        # Use unary comma to prevent PowerShell from unwrapping single-element arrays
        $array = $entries.ToArray()
        return @(,$array)
    }
    catch {
        Write-Warning "[RetrievalCache] Failed to read cache file: $_"
        return @()
    }
}
<#
.SYNOPSIS
    Writes cache entries to file atomically.
#>
function Write-CacheFile {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$CacheFile,

        [Parameter(Mandatory = $true)]
        [AllowEmptyCollection()]
        [array]$Entries
    )

    $tempFile = "$CacheFile.tmp.$PID"

    try {
        # Build JSON Lines content
        $lines = [System.Collections.Generic.List[string]]::new()
        foreach ($entry in $Entries) {
            $line = $entry | ConvertTo-Json -Depth 10 -Compress
            $lines.Add($line)
        }

        $content = $lines -join "`n"

        # Write to temp file
        [System.IO.File]::WriteAllText($tempFile, $content, [System.Text.Encoding]::UTF8)

        # Atomic move (delete destination first for .NET Framework compatibility)
        if (Test-Path -LiteralPath $CacheFile) {
            Remove-Item -LiteralPath $CacheFile -Force -ErrorAction Stop
        }
        [System.IO.File]::Move($tempFile, $CacheFile)
    }
    catch {
        # Clean up temp file on error
        if (Test-Path -LiteralPath $tempFile) {
            Remove-Item -LiteralPath $tempFile -Force -ErrorAction SilentlyContinue
        }
        throw "Failed to write cache file: $_"
    }
}

<#
.SYNOPSIS
    Performs LRU eviction on cache entries.
#>
function Perform-LRUEviction {
    [CmdletBinding()]
    [OutputType([array])]
    param(
        [Parameter(Mandatory = $true)]
        [array]$Entries,

        [Parameter(Mandatory = $true)]
        [int]$Count
    )

    if ($Count -le 0 -or $Entries.Count -eq 0) {
        return $Entries
    }

    # Sort by last accessed (nulls first), then by hit count (ascending)
    $sorted = $Entries | Sort-Object -Property {
        if ($_.metadata -and $_.metadata.lastAccessed) {
            [DateTime]::Parse($_.metadata.lastAccessed)
        }
        else {
            [DateTime]::MinValue
        }
    }, {
        if ($_.metadata -and $_.metadata.hitCount) {
            $_.metadata.hitCount
        }
        else {
            0
        }
    }

    # Keep the top entries (remove the oldest/least used)
    $keepCount = $Entries.Count - $Count
    if ($keepCount -lt 0) {
        $keepCount = 0
    }

    return @($sorted | Select-Object -First $keepCount)
}

#===============================================================================
# Module Export
#===============================================================================

Export-ModuleMember -Function @(
    'Get-CachedRetrieval'
    'Set-CachedRetrieval'
    'Get-RetrievalCacheKey'
    'Get-QueryHash'
    'Test-CacheEntryValid'
    'Invoke-CacheInvalidation'
    'Invoke-PackCacheInvalidation'
    'Get-RetrievalCacheStats'
    'Clear-RetrievalCache'
    'Invoke-CacheMaintenance'
    'Get-RetrievalCacheConfig'
    'Set-RetrievalCacheConfig'
)
