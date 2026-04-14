#requires -Version 5.1
Set-StrictMode -Version Latest

#===============================================================================
# Pack Query Tools
#===============================================================================

<#
.SYNOPSIS
    Queries pack knowledge via MCP.
.DESCRIPTION
    Performs a knowledge query across configured packs using the
    ContextLattice retrieval system.
.PARAMETER Query
    The search query string.
.PARAMETER PackIds
    Optional array of pack IDs to search. Default: all packs.
.PARAMETER Limit
    Maximum number of results. Default: 5.
.PARAMETER ContextWindow
    Context window size for results. Default: 2000.
.OUTPUTS
    System.Management.Automation.PSCustomObject with query results.
.EXAMPLE
    PS C:\> Invoke-MCPPackQuery -Query "how to create a node in Godot"
    
    Searches for Godot node creation documentation.
#>
function Invoke-MCPPackQuery {
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$Query,
        
        [Parameter()]
        [string[]]$PackIds = @(),
        
        [Parameter()]
        [ValidateRange(1, 50)]
        [int]$Limit = 5,
        
        [Parameter()]
        [ValidateRange(100, 10000)]
        [int]$ContextWindow = 2000
    )
    
    try {
        # Build query parameters
        $queryParams = @{
            query = $Query
            limit = $Limit
            contextWindow = $ContextWindow
        }
        
        if ($PackIds.Count -gt 0) {
            $queryParams['packIds'] = $PackIds
        }
        
        Write-MCPLog -Level INFO -Message "Executing pack query" -Metadata @{
            query = $Query
            packCount = $PackIds.Count
            limit = $Limit
        }
        
        # Try to use ContextLattice if available
        $contextLatticeUrl = [Environment]::GetEnvironmentVariable('CONTEXTLATTICE_ORCHESTRATOR_URL')
        $apiKey = [Environment]::GetEnvironmentVariable('CONTEXTLATTICE_ORCHESTRATOR_API_KEY')
        
        if (-not [string]::IsNullOrEmpty($contextLatticeUrl) -and -not [string]::IsNullOrEmpty($apiKey)) {
            # Use ContextLattice API
            $headers = @{
                'Content-Type' = 'application/json'
                'x-api-key' = $apiKey
            }
            
            $body = @{
                query = $Query
                limit = $Limit
            } | ConvertTo-Json
            
            $url = "$($contextLatticeUrl.TrimEnd('/'))/query"
            
            try {
                $response = Invoke-RestMethod -Uri $url -Method POST -Headers $headers -Body $body -TimeoutSec 30
                
                return [pscustomobject]@{
                    success = $true
                    query = $Query
                    results = $response.results
                    totalResults = $response.results.Count
                    source = 'contextlattice'
                    timestamp = [DateTime]::UtcNow.ToString('O')
                }
            }
            catch {
                Write-MCPLog -Level WARN -Message "ContextLattice query failed, falling back to local: $_"
            }
        }
        
        # Fallback: search local pack files
        $localResults = Search-LocalPackContent -Query $Query -PackIds $PackIds -Limit $Limit
        
        return [pscustomobject]@{
            success = $true
            query = $Query
            results = $localResults
            totalResults = $localResults.Count
            source = 'local'
            timestamp = [DateTime]::UtcNow.ToString('O')
        }
    }
    catch {
        Write-MCPLog -Level ERROR -Message "Pack query failed: $_"
        return [pscustomobject]@{
            success = $false
            query = $Query
            error = $_.Exception.Message
            results = @()
            totalResults = 0
            timestamp = [DateTime]::UtcNow.ToString('O')
        }
    }
}

<#
.SYNOPSIS
    Gets pack health and status information.
.DESCRIPTION
    Returns status information about configured packs including
    availability, version, and health scores.
.PARAMETER PackId
    Optional specific pack ID to check.
.OUTPUTS
    System.Management.Automation.PSCustomObject with pack status.
.EXAMPLE
    PS C:\> Get-MCPPackStatus
    
    Returns status for all packs.
#>
function Get-MCPPackStatus {
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter()]
        [string]$PackId = ''
    )
    
    try {
        $packs = [System.Collections.Generic.List[object]]::new()
        
        # Check packs directory
        $packsDir = 'packs'
        if (Test-Path -LiteralPath $packsDir) {
            $packFolders = Get-ChildItem -Path $packsDir -Directory -ErrorAction SilentlyContinue
            
            foreach ($folder in $packFolders) {
                if (-not [string]::IsNullOrEmpty($PackId) -and $folder.Name -ne $PackId) {
                    continue
                }
                
                $manifestPath = Join-Path $folder.FullName 'pack.json'
                $manifest = @{}
                
                if (Test-Path -LiteralPath $manifestPath) {
                    try {
                        $content = Get-Content -LiteralPath $manifestPath -Raw | ConvertFrom-Json
                        $manifest = @{
                            name = $content.name
                            version = $content.version
                            description = $content.description
                        }
                    }
                    catch {
                        $manifest = @{ error = 'Invalid manifest' }
                    }
                }
                
                # Check for indexed content
                $indexPath = Join-Path $folder.FullName 'index'
                $hasIndex = Test-Path -LiteralPath $indexPath
                
                # Calculate basic health metrics
                $fileCount = (Get-ChildItem -Path $folder.FullName -Recurse -File -ErrorAction SilentlyContinue).Count
                $lastModified = (Get-Item -LiteralPath $folder.FullName).LastWriteTimeUtc
                
                $packs.Add([pscustomobject]@{
                    id = $folder.Name
                    path = $folder.FullName
                    manifest = $manifest
                    hasIndex = $hasIndex
                    fileCount = $fileCount
                    lastModified = $lastModified.ToString('O')
                    status = if ($hasIndex) { 'indexed' } else { 'unindexed' }
                    health = Calculate-PackHealth -FileCount $fileCount -HasIndex $hasIndex -LastModified $lastModified
                })
            }
        }
        
        return [pscustomobject]@{
            success = $true
            totalPacks = $packs.Count
            packs = $packs.ToArray()
            timestamp = [DateTime]::UtcNow.ToString('O')
        }
    }
    catch {
        Write-MCPLog -Level ERROR -Message "Failed to get pack status: $_"
        return [pscustomobject]@{
            success = $false
            error = $_.Exception.Message
            timestamp = [DateTime]::UtcNow.ToString('O')
        }
    }
}

function Search-LocalPackContent {
    [CmdletBinding()]
    [OutputType([array])]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Query,
        
        [Parameter()]
        [string[]]$PackIds = @(),
        
        [Parameter()]
        [int]$Limit = 5
    )
    
    $results = [System.Collections.Generic.List[object]]::new()
    $packsDir = 'packs'
    
    if (-not (Test-Path -LiteralPath $packsDir)) {
        return $results.ToArray()
    }
    
    $searchTerms = $Query.ToLower() -split '\s+' | Where-Object { $_.Length -gt 2 }
    
    $packFolders = Get-ChildItem -Path $packsDir -Directory -ErrorAction SilentlyContinue
    foreach ($folder in $packFolders) {
        if ($PackIds.Count -gt 0 -and $folder.Name -notin $PackIds) {
            continue
        }
        
        # Search markdown files
        $mdFiles = Get-ChildItem -Path $folder.FullName -Filter '*.md' -Recurse -ErrorAction SilentlyContinue | Select-Object -First $Limit
        
        foreach ($file in $mdFiles) {
            try {
                $content = Get-Content -LiteralPath $file.FullName -Raw -ErrorAction SilentlyContinue
                $contentLower = $content.ToLower()
                
                $score = 0
                foreach ($term in $searchTerms) {
                    if ($contentLower.Contains($term)) {
                        $score += 1
                    }
                }
                
                if ($score -gt 0) {
                    # Extract snippet
                    $snippet = $content.Substring(0, [Math]::Min(200, $content.Length))
                    $snippet = $snippet -replace "[\r\n]+", ' '
                    
                    $results.Add([pscustomobject]@{
                        title = $file.BaseName
                        content = $snippet
                        pack = $folder.Name
                        score = $score
                        path = $file.FullName
                    })
                }
            }
            catch {
                # Continue to next file
            }
        }
    }
    
    # Sort by score and limit
    return $results | Sort-Object -Property score -Descending | Select-Object -First $Limit
}

<#
.SYNOPSIS
    Calculates a simple pack health score.
.DESCRIPTION
    Evaluates pack health based on file count, indexing status, and freshness.
.PARAMETER FileCount
    Number of files in the pack.
.PARAMETER HasIndex
    Whether the pack has been indexed.
.PARAMETER LastModified
    Last modification time.
.OUTPUTS
    Hashtable with health metrics.
#>
function Calculate-PackHealth {
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [Parameter(Mandatory = $true)]
        [int]$FileCount,
        
        [Parameter(Mandatory = $true)]
        [bool]$HasIndex,
        
        [Parameter(Mandatory = $true)]
        [DateTime]$LastModified
    )
    
    $daysSinceUpdate = ([DateTime]::UtcNow - $LastModified).TotalDays
    
    $score = 0
    if ($FileCount -gt 0) { $score += 25 }
    if ($FileCount -gt 10) { $score += 25 }
    if ($HasIndex) { $score += 25 }
    if ($daysSinceUpdate -lt 30) { $score += 25 }
    
    $status = switch ($score) {
        { $_ -ge 80 } { 'healthy' }
        { $_ -ge 50 } { 'degraded' }
        default { 'unhealthy' }
    }
    
    return @{
        score = $score
        status = $status
        metrics = @{
            fileCount = $FileCount
            hasIndex = $HasIndex
            daysSinceUpdate = [int]$daysSinceUpdate
        }
    }
}

<#
.SYNOPSIS
    Merges MCP configuration.
.DESCRIPTION
    Merges override configuration with base defaults.
.PARAMETER BaseConfig
    The base configuration.
.PARAMETER OverrideConfig
    Configuration to override with.
.OUTPUTS
    Merged configuration hashtable.
#>
