# Policy Decision Cache
# Provides an in-memory cache for policy decisions with TTL support.
# Improves performance for repeated policy queries and enables explainability.

Set-StrictMode -Version Latest

#===============================================================================
# Cache Store
#===============================================================================

$script:PolicyCache = @{}
$script:DefaultCacheTtlSeconds = 300

#===============================================================================
# Cache Functions
#===============================================================================

function Get-PolicyDecisionCache {
    <#
    .SYNOPSIS
        Retrieves a cached policy decision if it exists and has not expired.
    
    .DESCRIPTION
        Looks up a policy decision in the in-memory cache by key.
        Returns the cached entry including decision, explanation, and metadata.
    
    .PARAMETER Key
        The cache key to look up. Typically derived from adapter ID, domain,
        and a hash of the input object.
    
    .OUTPUTS
        PSCustomObject containing the cached decision, or $null if not found or expired.
    
    .EXAMPLE
        $entry = Get-PolicyDecisionCache -Key "adapter1:execution_mode:abc123"
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Key
    )
    
    if (-not $script:PolicyCache.ContainsKey($Key)) {
        Write-Verbose "Cache miss for key '$Key'."
        return $null
    }
    
    $entry = $script:PolicyCache[$Key]
    $now = [DateTime]::UtcNow
    
    if ($now -gt $entry.ExpiresAt) {
        Write-Verbose "Cache entry for key '$Key' has expired."
        [void]$script:PolicyCache.Remove($Key)
        return $null
    }
    
    Write-Verbose "Cache hit for key '$Key'."
    return [PSCustomObject]@{
        Key = $Key
        Decision = $entry.Decision
        Explanation = $entry.Explanation
        Engine = $entry.Engine
        Fallback = $entry.Fallback
        CachedAt = $entry.CachedAt
        ExpiresAt = $entry.ExpiresAt
        TtlSeconds = $entry.TtlSeconds
        Hit = $true
    }
}

function Set-PolicyDecisionCache {
    <#
    .SYNOPSIS
        Stores a policy decision in the in-memory cache.
    
    .DESCRIPTION
        Caches a policy decision with a configurable TTL. If the key already
        exists, it is overwritten with the new value and TTL.
    
    .PARAMETER Key
        The cache key.
    
    .PARAMETER DecisionResult
        The PSCustomObject result from Invoke-PolicyDecision.
    
    .PARAMETER TtlSeconds
        Time-to-live in seconds. Defaults to 300 (5 minutes).
    
    .OUTPUTS
        PSCustomObject representing the stored cache entry.
    
    .EXAMPLE
        Set-PolicyDecisionCache -Key "adapter1:execution_mode:abc123" -DecisionResult $result -TtlSeconds 60
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Key,
        
        [Parameter(Mandatory = $true)]
        [PSCustomObject]$DecisionResult,
        
        [int]$TtlSeconds = $script:DefaultCacheTtlSeconds
    )
    
    $now = [DateTime]::UtcNow
    $entry = @{
        Decision = $DecisionResult.Decision
        Explanation = $DecisionResult.Explanation
        Engine = $DecisionResult.Engine
        Fallback = $DecisionResult.Fallback
        CachedAt = $now.ToString("o")
        ExpiresAt = $now.AddSeconds($TtlSeconds)
        TtlSeconds = $TtlSeconds
    }
    
    $script:PolicyCache[$Key] = $entry
    
    Write-Verbose "Cached policy decision for key '$Key' with TTL $TtlSeconds seconds."
    
    return [PSCustomObject]@{
        Key = $Key
        Decision = $entry.Decision
        Explanation = $entry.Explanation
        Engine = $entry.Engine
        Fallback = $entry.Fallback
        CachedAt = $entry.CachedAt
        ExpiresAt = $entry.ExpiresAt
        TtlSeconds = $entry.TtlSeconds
    }
}

function Clear-PolicyDecisionCache {
    <#
    .SYNOPSIS
        Clears policy decision cache entries.
    
    .DESCRIPTION
        Removes all entries, expired entries only, or a specific key from the cache.
    
    .PARAMETER Key
        Optional specific key to remove.
    
    .PARAMETER ExpiredOnly
        If specified, removes only expired entries.
    
    .OUTPUTS
        Int representing the number of entries removed.
    
    .EXAMPLE
        Clear-PolicyDecisionCache
        Clear-PolicyDecisionCache -ExpiredOnly
        Clear-PolicyDecisionCache -Key "adapter1:execution_mode:abc123"
    #>
    [CmdletBinding()]
    param(
        [string]$Key = "",
        [switch]$ExpiredOnly
    )
    
    $removedCount = 0
    
    if (-not [string]::IsNullOrWhiteSpace($Key)) {
        if ($script:PolicyCache.ContainsKey($Key)) {
            [void]$script:PolicyCache.Remove($Key)
            $removedCount = 1
            Write-Verbose "Removed cache entry for key '$Key'."
        }
        return $removedCount
    }
    
    if ($ExpiredOnly) {
        $now = [DateTime]::UtcNow
        $keysToRemove = $script:PolicyCache.Keys | Where-Object {
            $script:PolicyCache[$_].ExpiresAt -lt $now
        }
        foreach ($k in $keysToRemove) {
            [void]$script:PolicyCache.Remove($k)
            $removedCount++
        }
        Write-Verbose "Removed $removedCount expired cache entries."
        return $removedCount
    }
    
    $count = $script:PolicyCache.Count
    $script:PolicyCache.Clear()
    Write-Verbose "Cleared all $count cache entries."
    return $count
}

function Test-PolicyDecisionCache {
    <#
    .SYNOPSIS
        Tests whether a valid (non-expired) cache entry exists for a given key.
    
    .DESCRIPTION
        Returns $true if the key exists in the cache and has not expired,
        $false otherwise. Does not return the cached value.
    
    .PARAMETER Key
        The cache key to test.
    
    .OUTPUTS
        Boolean
    
    .EXAMPLE
        if (Test-PolicyDecisionCache -Key "adapter1:execution_mode:abc123") { ... }
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Key
    )
    
    if (-not $script:PolicyCache.ContainsKey($Key)) {
        return $false
    }
    
    $entry = $script:PolicyCache[$Key]
    if ([DateTime]::UtcNow -gt $entry.ExpiresAt) {
        [void]$script:PolicyCache.Remove($Key)
        return $false
    }
    
    return $true
}

function New-PolicyCacheKey {
    <#
    .SYNOPSIS
        Generates a deterministic cache key for a policy decision request.
    
    .DESCRIPTION
        Creates a cache key from adapter ID, domain, and the normalized input
        object using a stable string hash.
    
    .PARAMETER AdapterId
        The adapter identifier.
    
    .PARAMETER Domain
        The policy domain.
    
    .PARAMETER InputObject
        The query input object.
    
    .OUTPUTS
        String cache key.
    
    .EXAMPLE
        $key = New-PolicyCacheKey -AdapterId "a1" -Domain "execution_mode" -InputObject @{ mode = "ci" }
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$AdapterId,
        
        [Parameter(Mandatory = $true)]
        [string]$Domain,
        
        [Parameter(Mandatory = $true)]
        [object]$InputObject
    )
    
    $inputJson = ""
    if ($InputObject -is [hashtable] -or $InputObject -is [System.Collections.IDictionary]) {
        $sorted = $InputObject.GetEnumerator() | Sort-Object Key
        $inputJson = ($sorted | ForEach-Object { "$($_.Key)=$($_.Value)" }) -join ";"
    }
    else {
        $inputJson = $InputObject | ConvertTo-Json -Depth 10 -Compress
    }
    
    $sha256 = [System.Security.Cryptography.SHA256]::Create()
    $bytes = [System.Text.Encoding]::UTF8.GetBytes($inputJson)
    $hashBytes = $sha256.ComputeHash($bytes)
    $hashString = [BitConverter]::ToString($hashBytes).Replace("-", "").Substring(0, 16).ToLowerInvariant()
    
    return "$AdapterId`:$Domain`:$hashString"
}

function Get-PolicyDecisionCacheStatistics {
    <#
    .SYNOPSIS
        Returns statistics about the policy decision cache.
    
    .OUTPUTS
        PSCustomObject with cache statistics.
    #>
    [CmdletBinding()]
    param()
    
    $now = [DateTime]::UtcNow
    $total = $script:PolicyCache.Count
    $expired = 0
    foreach ($key in $script:PolicyCache.Keys) {
        if ($script:PolicyCache[$key].ExpiresAt -lt $now) {
            $expired++
        }
    }
    
    return [PSCustomObject]@{
        TotalEntries = $total
        ExpiredEntries = $expired
        ValidEntries = $total - $expired
        DefaultTtlSeconds = $script:DefaultCacheTtlSeconds
    }
}

# Export module members when loaded as a module
if ($ExecutionContext.SessionState.Module) {
    Export-ModuleMember -Function @(
        'Get-PolicyDecisionCache',
        'Set-PolicyDecisionCache',
        'Clear-PolicyDecisionCache',
        'Test-PolicyDecisionCache',
        'New-PolicyCacheKey',
        'Get-PolicyDecisionCacheStatistics'
    ) -Variable @() -Alias @()
}
