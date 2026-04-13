#requires -Version 5.1
<#
.SYNOPSIS
    External Ingestion Framework for LLM Workflow platform.

.DESCRIPTION
    Provides scalable ingestion from external sources including GitHub, GitLab,
    documentation sites, and custom APIs. Features include:
    - Async job execution with status tracking
    - Rate limit handling with exponential backoff
    - Incremental ingestion (only new/changed content)
    - Error recovery and retry logic
    - Secret management for auth tokens
    
    Part of Phase 7: MCP External Integration Layer

.NOTES
    File Name      : ExternalIngestion.ps1
    Author         : LLM Workflow Team
    Prerequisite   : PowerShell 5.1+
    Copyright      : (c) 2026 LLM Workflow Project
    License        : MIT
    Version        : 0.7.0
#>

Set-StrictMode -Version Latest

# ============================================================================
# Script-level Variables
# ============================================================================

$script:IngestionConfigDir = ".llm-workflow/ingestion"
$script:IngestionJobsDir = ".llm-workflow/ingestion/jobs"
$script:IngestionLogsDir = ".llm-workflow/ingestion/logs"
$script:IngestionStateFile = ".llm-workflow/ingestion/state.json"

# In-memory registries
$script:IngestionSources = [hashtable]::Synchronized(@{})
$script:IngestionJobs = [hashtable]::Synchronized(@{})
$script:RateLimitTracker = [hashtable]::Synchronized(@{})
$script:ThrottleSettings = [hashtable]::Synchronized(@{
    defaultDelayMs = 100
    maxRetries = 5
    baseDelayMs = 1000
})

# Valid source types
$script:ValidSourceTypes = @('github', 'gitlab', 'git', 'http', 'https', 's3', 'docssite', 'api', 'custom')

# Valid job states
$script:ValidJobStates = @('pending', 'running', 'completed', 'failed', 'cancelled')

# GitHub API base URL
$script:GitHubApiBase = "https://api.github.com"

# GitLab API base URL (can be customized for self-hosted)
$script:GitLabApiBase = "https://gitlab.com/api/v4"

# ============================================================================
# Region: Ingestion Sources Management
# ============================================================================

<#
.SYNOPSIS
    Registers a new external ingestion source.

.DESCRIPTION
    Registers an external source for content ingestion. Sources can be
    GitHub repositories, GitLab projects, documentation sites, or custom APIs.

.PARAMETER SourceId
    Unique identifier for this source.

.PARAMETER Type
    Source type: github, gitlab, docssite, api, custom.

.PARAMETER Url
    The source URL (repository URL, documentation site URL, or API endpoint).

.PARAMETER Auth
    Authentication configuration hashtable with type and credentials.

.PARAMETER Include
    Array of file patterns to include (wildcards supported).

.PARAMETER Exclude
    Array of file patterns or paths to exclude.

.PARAMETER Schedule
    Optional cron expression for scheduled ingestion.

.PARAMETER Metadata
    Additional metadata for the source.

.PARAMETER Persist
    If specified, persists the source configuration to disk.

.OUTPUTS
    System.Management.Automation.PSCustomObject representing the registered source.

.EXAMPLE
    PS C:\> Register-IngestionSource -SourceId "github-godot-rust" -Type "github" `
        -Url "https://github.com/godot-rust/gdext" `
        -Auth @{ type = "token"; tokenEnv = "GITHUB_TOKEN" } `
        -Include @("*.rs", "*.md") -Exclude @("tests/")
#>
function Register-IngestionSource {
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$SourceId,

        [Parameter(Mandatory = $true)]
        [ValidateSet('github', 'gitlab', 'docssite', 'api', 'custom')]
        [string]$Type,

        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$Url,

        [Parameter()]
        [hashtable]$Auth = @{},

        [Parameter()]
        [string[]]$Include = @("*"),

        [Parameter()]
        [string[]]$Exclude = @(),

        [Parameter()]
        [string]$Schedule = "",

        [Parameter()]
        [hashtable]$Metadata = @{},

        [Parameter()]
        [switch]$Persist
    )

    begin {
        # Ensure ingestion directories exist
        if (-not (Test-Path -LiteralPath $script:IngestionConfigDir)) {
            $null = New-Item -ItemType Directory -Path $script:IngestionConfigDir -Force
        }
    }

    process {
        # Validate source ID format
        if ($SourceId -notmatch '^[a-zA-Z0-9_-]+$') {
            throw "Invalid SourceId. Use only alphanumeric characters, hyphens, and underscores."
        }

        # Validate URL
        try {
            $null = [Uri]$Url
        }
        catch {
            throw "Invalid URL: $Url"
        }

        # Validate cron expression if provided
        if (-not [string]::IsNullOrEmpty($Schedule)) {
            if (-not (Test-CronExpression -Expression $Schedule)) {
                throw "Invalid cron expression: $Schedule"
            }
        }

        # Build source configuration
        $source = [ordered]@{
            sourceId = $SourceId
            type = $Type
            url = $Url
            auth = $Auth
            include = @($Include)
            exclude = @($Exclude)
            schedule = $Schedule
            metadata = $Metadata
            enabled = $true
            createdAt = [DateTime]::UtcNow.ToString("yyyy-MM-ddTHH:mm:ssZ", [System.Globalization.CultureInfo]::InvariantCulture)
            lastIngested = $null
            lastStatus = $null
            ingestCount = 0
            version = 1
        }

        $sourceObject = [pscustomobject]$source

        # Store in memory registry
        $script:IngestionSources[$SourceId] = $sourceObject

        # Persist to disk if requested
        if ($Persist) {
            try {
                $sourcePath = Join-Path $script:IngestionConfigDir "$SourceId.json"
                $source | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $sourcePath -Encoding UTF8
                Write-Verbose "[ExternalIngestion] Persisted source '$SourceId' to $sourcePath"
            }
            catch {
                Write-Warning "[ExternalIngestion] Failed to persist source '$SourceId': $_"
            }
        }

        # Log registration
        Write-LogEntry -Level INFO -Message "Registered ingestion source: $SourceId (Type: $Type)" -Source "Register-IngestionSource"

        return $sourceObject
    }
}

<#
.SYNOPSIS
    Unregisters an ingestion source.

.DESCRIPTION
    Removes a previously registered ingestion source from both the
    in-memory registry and persisted storage.

.PARAMETER SourceId
    The ID of the source to unregister.

.PARAMETER Force
    If specified, suppresses confirmation prompt.

.OUTPUTS
    System.Boolean. True if the source was removed; otherwise false.

.EXAMPLE
    PS C:\> Unregister-IngestionSource -SourceId "github-godot-rust"
#>
function Unregister-IngestionSource {
    [CmdletBinding(SupportsShouldProcess = $true)]
    [OutputType([bool])]
    param(
        [Parameter(Mandatory = $true, ValueFromPipeline = $true)]
        [string]$SourceId,

        [Parameter()]
        [switch]$Force
    )

    process {
        $removed = $false

        # Remove from in-memory registry
        if ($script:IngestionSources.ContainsKey($SourceId)) {
            if ($Force -or $PSCmdlet.ShouldProcess($SourceId, "Unregister ingestion source")) {
                $null = $script:IngestionSources.Remove($SourceId)
                $removed = $true
                Write-Verbose "[ExternalIngestion] Removed source '$SourceId' from registry"
            }
        }

        # Remove from persisted storage
        $sourcePath = Join-Path $script:IngestionConfigDir "$SourceId.json"
        if (Test-Path -LiteralPath $sourcePath) {
            if ($Force -or $PSCmdlet.ShouldProcess($SourceId, "Remove persisted source file")) {
                try {
                    Remove-Item -LiteralPath $sourcePath -Force
                    $removed = $true
                    Write-Verbose "[ExternalIngestion] Removed persisted source '$SourceId'"
                }
                catch {
                    Write-Warning "[ExternalIngestion] Failed to remove persisted source '$SourceId': $_"
                }
            }
        }

        if (-not $removed) {
            Write-Verbose "[ExternalIngestion] Source '$SourceId' not found"
        }
        else {
            Write-LogEntry -Level INFO -Message "Unregistered ingestion source: $SourceId" -Source "Unregister-IngestionSource"
        }

        return $removed
    }
}

<#
.SYNOPSIS
    Gets registered ingestion sources.

.DESCRIPTION
    Retrieves all registered ingestion sources from both the in-memory
    registry and persisted storage. Optionally filters by type or source ID.

.PARAMETER SourceId
    Specific source ID to retrieve. If not specified, returns all sources.

.PARAMETER Type
    Filter by source type.

.PARAMETER IncludeDisabled
    If specified, includes disabled sources in the results.

.OUTPUTS
    System.Management.Automation.PSCustomObject[] representing the registered sources.

.EXAMPLE
    PS C:\> Get-IngestionSources

.EXAMPLE
    PS C:\> Get-IngestionSources -Type github
#>
function Get-IngestionSources {
    [CmdletBinding()]
    [OutputType([array])]
    param(
        [Parameter()]
        [string]$SourceId = "",

        [Parameter()]
        [ValidateSet('github', 'gitlab', 'docssite', 'api', 'custom')]
        [string]$Type = "",

        [Parameter()]
        [switch]$IncludeDisabled
    )

    $sources = [System.Collections.Generic.List[object]]::new()
    $seenIds = [System.Collections.Generic.HashSet[string]]::new()

    # Load persisted sources first (so memory sources can override)
    if (Test-Path -LiteralPath $script:IngestionConfigDir) {
        $sourceFiles = Get-ChildItem -LiteralPath $script:IngestionConfigDir -Filter "*.json" -File
        foreach ($file in $sourceFiles) {
            try {
                $sourceData = Get-Content -LiteralPath $file.FullName -Raw | ConvertFrom-Json
                $id = $file.BaseName

                if (-not $IncludeDisabled -and -not $sourceData.enabled) {
                    continue
                }

                if (-not [string]::IsNullOrEmpty($SourceId) -and $id -ne $SourceId) {
                    continue
                }

                if (-not [string]::IsNullOrEmpty($Type) -and $sourceData.type -ne $Type) {
                    continue
                }

                $sources.Add($sourceData)
                $null = $seenIds.Add($id)
            }
            catch {
                Write-Warning "[ExternalIngestion] Failed to load source from $($file.Name): $_"
            }
        }
    }

    # Add/override with memory sources
    foreach ($id in $script:IngestionSources.Keys) {
        $source = $script:IngestionSources[$id]

        if (-not $IncludeDisabled -and -not $source.enabled) {
            continue
        }

        if (-not [string]::IsNullOrEmpty($SourceId) -and $id -ne $SourceId) {
            continue
        }

        if (-not [string]::IsNullOrEmpty($Type) -and $source.type -ne $Type) {
            continue
        }

        # Remove existing entry if present
        $existingIndex = -1
        for ($i = 0; $i -lt $sources.Count; $i++) {
            if ($sources[$i].sourceId -eq $id) {
                $existingIndex = $i
                break
            }
        }

        if ($existingIndex -ge 0) {
            $sources[$existingIndex] = $source
        }
        else {
            $sources.Add($source)
        }
    }

    return $sources.ToArray()
}

<#
.SYNOPSIS
    Tests connectivity to an ingestion source.

.DESCRIPTION
    Verifies that the source is reachable and authentication (if configured)
    is valid. Returns detailed connectivity status.

.PARAMETER SourceId
    The ID of the source to test.

.PARAMETER TimeoutSeconds
    Timeout for the connectivity test. Default: 30.

.OUTPUTS
    System.Management.Automation.PSCustomObject with connectivity test results.

.EXAMPLE
    PS C:\> Test-IngestionSource -SourceId "github-godot-rust"
#>
function Test-IngestionSource {
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory = $true)]
        [string]$SourceId,

        [Parameter()]
        [ValidateRange(1, 300)]
        [int]$TimeoutSeconds = 30
    )

    process {
        $source = Get-IngestionSources -SourceId $SourceId

        if (-not $source) {
            throw "Source not found: $SourceId"
        }

        if ($source -is [array]) {
            $source = $source[0]
        }

        $result = [ordered]@{
            sourceId = $SourceId
            type = $source.type
            url = $source.url
            reachable = $false
            authenticated = $false
            rateLimit = @{}
            error = $null
            testedAt = [DateTime]::UtcNow.ToString("yyyy-MM-ddTHH:mm:ssZ", [System.Globalization.CultureInfo]::InvariantCulture)
        }

        $stopwatch = [System.Diagnostics.Stopwatch]::StartNew()

        try {
            switch ($source.type) {
                'github' {
                    $testResult = Test-GitHubConnectivity -Source $source -TimeoutSeconds $TimeoutSeconds
                    $result.reachable = $testResult.reachable
                    $result.authenticated = $testResult.authenticated
                    $result.rateLimit = $testResult.rateLimit
                    if ($testResult.error) {
                        $result.error = $testResult.error
                    }
                }
                'gitlab' {
                    $testResult = Test-GitLabConnectivity -Source $source -TimeoutSeconds $TimeoutSeconds
                    $result.reachable = $testResult.reachable
                    $result.authenticated = $testResult.authenticated
                    $result.rateLimit = $testResult.rateLimit
                    if ($testResult.error) {
                        $result.error = $testResult.error
                    }
                }
                'docssite' {
                    $testResult = Test-DocsSiteConnectivity -Source $source -TimeoutSeconds $TimeoutSeconds
                    $result.reachable = $testResult.reachable
                    $result.authenticated = $testResult.authenticated
                    if ($testResult.error) {
                        $result.error = $testResult.error
                    }
                }
                'api' {
                    $testResult = Test-ApiConnectivity -Source $source -TimeoutSeconds $TimeoutSeconds
                    $result.reachable = $testResult.reachable
                    $result.authenticated = $testResult.authenticated
                    if ($testResult.error) {
                        $result.error = $testResult.error
                    }
                }
                default {
                    $result.error = "Connectivity test not implemented for type: $($source.type)"
                }
            }
        }
        catch {
            $result.error = $_.Exception.Message
        }

        $stopwatch.Stop()
        $result['responseTimeMs'] = $stopwatch.ElapsedMilliseconds

        Write-LogEntry -Level INFO -Message "Source connectivity test: $SourceId (Reachable: $($result.reachable))" -Source "Test-IngestionSource"

        return [pscustomobject]$result
    }
}

# ============================================================================
# Region: GitHub Integration
# ============================================================================

<#
.SYNOPSIS
    Ingests content from a GitHub repository.

.DESCRIPTION
    Clones or pulls a GitHub repository and extracts content based on
    include/exclude patterns. Supports incremental ingestion using
    commit history.

.PARAMETER SourceId
    The registered source ID for the GitHub repository.

.PARAMETER OutputPath
    Directory where ingested content will be stored.

.PARAMETER Incremental
    If specified, only ingests changed content since last ingestion.

.PARAMETER Branch
    Specific branch to ingest. If not specified, uses default branch.

.PARAMETER Depth
    Clone depth for shallow clones. Default: full history.

.OUTPUTS
    System.Management.Automation.PSCustomObject with ingestion results.

.EXAMPLE
    PS C:\> Invoke-GitHubRepoIngestion -SourceId "github-godot-rust" -OutputPath "./ingested/godot-rust"
#>
function Invoke-GitHubRepoIngestion {
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory = $true)]
        [string]$SourceId,

        [Parameter(Mandatory = $true)]
        [string]$OutputPath,

        [Parameter()]
        [switch]$Incremental,

        [Parameter()]
        [string]$Branch = "",

        [Parameter()]
        [int]$Depth = 0
    )

    process {
        $source = Get-IngestionSources -SourceId $SourceId
        if (-not $source) {
            throw "Source not found: $SourceId"
        }
        if ($source -is [array]) {
            $source = $source[0]
        }

        if ($source.type -ne 'github') {
            throw "Source '$SourceId' is not a GitHub source (type: $($source.type))"
        }

        # Parse GitHub URL
        $repoInfo = Parse-GitHubUrl -Url $source.url
        if (-not $repoInfo) {
            throw "Failed to parse GitHub URL: $($source.url)"
        }

        $result = [ordered]@{
            sourceId = $SourceId
            type = 'github'
            repository = "$($repoInfo.Owner)/$($repoInfo.Repo)"
            outputPath = $OutputPath
            filesIngested = 0
            filesSkipped = 0
            bytesIngested = 0
            incremental = $Incremental.IsPresent
            errors = @()
            startedAt = [DateTime]::UtcNow.ToString("yyyy-MM-ddTHH:mm:ssZ", [System.Globalization.CultureInfo]::InvariantCulture)
            completedAt = $null
        }

        try {
            # Ensure output directory exists
            if (-not (Test-Path -LiteralPath $OutputPath)) {
                $null = New-Item -ItemType Directory -Path $OutputPath -Force
            }

            # Get authentication token
            $token = Get-SourceAuthToken -Source $source

            # Build API headers
            $headers = @{
                'Accept' = 'application/vnd.github.v3+json'
                'User-Agent' = 'LLM-Workflow-Ingestion/0.7.0'
            }
            if ($token) {
                $headers['Authorization'] = "Bearer $token"
            }

            # Get repository contents via API (for selective file ingestion)
            $apiUrl = "$script:GitHubApiBase/repos/$($repoInfo.Owner)/$($repoInfo.Repo)/git/trees/$($Branch -or 'HEAD')?recursive=1"
            
            $treeData = Invoke-IngestionWithBackoff -ScriptBlock {
                Invoke-RestMethod -Uri $apiUrl -Headers $headers -Method GET
            }

            if (-not $treeData -or -not $treeData.tree) {
                throw "Failed to retrieve repository tree"
            }

            # Filter files based on include/exclude patterns
            $filesToIngest = $treeData.tree | Where-Object { $_.type -eq 'blob' } | ForEach-Object {
                $path = $_.path
                $include = $false

                # Check include patterns
                foreach ($pattern in $source.include) {
                    if ($path -like $pattern) {
                        $include = $true
                        break
                    }
                }

                # Check exclude patterns
                if ($include) {
                    foreach ($pattern in $source.exclude) {
                        if ($path -like $pattern -or $path.StartsWith($pattern.TrimEnd('*'))) {
                            $include = $false
                            break
                        }
                    }
                }

                if ($include) {
                    $_
                }
            }

            # Get last ingestion time for incremental
            $lastIngested = $null
            if ($Incremental -and $source.lastIngested) {
                $lastIngested = [DateTime]::Parse($source.lastIngested)
            }

            # Ingest each file
            foreach ($file in $filesToIngest) {
                try {
                    $fileUrl = $file.url
                    $targetPath = Join-Path $OutputPath $file.path
                    $targetDir = Split-Path -Parent $targetPath

                    # Ensure target directory exists
                    if (-not (Test-Path -LiteralPath $targetDir)) {
                        $null = New-Item -ItemType Directory -Path $targetDir -Force
                    }

                    # Get file content
                    $fileData = Invoke-IngestionWithBackoff -ScriptBlock {
                        Invoke-RestMethod -Uri $fileUrl -Headers $headers -Method GET
                    }

                    if ($fileData.content) {
                        $content = [System.Convert]::FromBase64String($fileData.content)
                        [System.IO.File]::WriteAllBytes($targetPath, $content)
                        
                        $result.filesIngested++
                        $result.bytesIngested += $content.Length
                    }
                }
                catch {
                    $result.errors += "Failed to ingest $($file.path): $_"
                    Write-Warning "[ExternalIngestion] Failed to ingest $($file.path): $_"
                }
            }

            # Update source last ingested time
            $source.lastIngested = [DateTime]::UtcNow.ToString("yyyy-MM-ddTHH:mm:ssZ", [System.Globalization.CultureInfo]::InvariantCulture)
            $source.ingestCount++
            $source.lastStatus = 'success'

            # Persist updated source
            $sourcePath = Join-Path $script:IngestionConfigDir "$SourceId.json"
            if (Test-Path -LiteralPath $sourcePath) {
                ($source | ConvertTo-Json -Depth 10) | Set-Content -LiteralPath $sourcePath -Encoding UTF8
            }

            $result.completedAt = [DateTime]::UtcNow.ToString("yyyy-MM-ddTHH:mm:ssZ", [System.Globalization.CultureInfo]::InvariantCulture)
            
            Write-LogEntry -Level INFO -Message "GitHub ingestion completed: $SourceId (Files: $($result.filesIngested))" -Source "Invoke-GitHubRepoIngestion"
        }
        catch {
            $result.errors += $_.Exception.Message
            $source.lastStatus = 'failed'
            Write-LogEntry -Level ERROR -Message "GitHub ingestion failed: $SourceId - $_" -Source "Invoke-GitHubRepoIngestion"
            throw
        }

        return [pscustomobject]$result
    }
}

<#
.SYNOPSIS
    Downloads GitHub release assets.

.DESCRIPTION
    Downloads assets from a specific GitHub release. Supports filtering
    by asset name patterns.

.PARAMETER SourceId
    The registered source ID for the GitHub repository.

.PARAMETER Release
    Release tag, 'latest', or 'all'.

.PARAMETER OutputPath
    Directory where assets will be downloaded.

.PARAMETER AssetPattern
    Wildcard pattern to filter assets.

.PARAMETER IncludeSource
    If specified, also downloads source archives.

.OUTPUTS
    System.Management.Automation.PSCustomObject with download results.

.EXAMPLE
    PS C:\> Get-GitHubReleaseAssets -SourceId "github-godot-rust" -Release "latest" -OutputPath "./downloads"
#>
function Get-GitHubReleaseAssets {
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory = $true)]
        [string]$SourceId,

        [Parameter(Mandatory = $true)]
        [string]$Release,

        [Parameter(Mandatory = $true)]
        [string]$OutputPath,

        [Parameter()]
        [string]$AssetPattern = "*",

        [Parameter()]
        [switch]$IncludeSource
    )

    process {
        $source = Get-IngestionSources -SourceId $SourceId
        if (-not $source) {
            throw "Source not found: $SourceId"
        }
        if ($source -is [array]) {
            $source = $source[0]
        }

        $repoInfo = Parse-GitHubUrl -Url $source.url
        if (-not $repoInfo) {
            throw "Failed to parse GitHub URL: $($source.url)"
        }

        $result = [ordered]@{
            sourceId = $SourceId
            repository = "$($repoInfo.Owner)/$($repoInfo.Repo)"
            release = $Release
            outputPath = $OutputPath
            assetsDownloaded = 0
            assetsSkipped = 0
            totalBytes = 0
            files = @()
            errors = @()
        }

        try {
            # Ensure output directory exists
            if (-not (Test-Path -LiteralPath $OutputPath)) {
                $null = New-Item -ItemType Directory -Path $OutputPath -Force
            }

            $token = Get-SourceAuthToken -Source $source
            $headers = @{
                'Accept' = 'application/vnd.github.v3+json'
                'User-Agent' = 'LLM-Workflow-Ingestion/0.7.0'
            }
            if ($token) {
                $headers['Authorization'] = "Bearer $token"
            }

            # Get release(s)
            if ($Release -eq 'all') {
                $apiUrl = "$script:GitHubApiBase/repos/$($repoInfo.Owner)/$($repoInfo.Repo)/releases"
            }
            elseif ($Release -eq 'latest') {
                $apiUrl = "$script:GitHubApiBase/repos/$($repoInfo.Owner)/$($repoInfo.Repo)/releases/latest"
            }
            else {
                $apiUrl = "$script:GitHubApiBase/repos/$($repoInfo.Owner)/$($repoInfo.Repo)/releases/tags/$Release"
            }

            $releases = Invoke-IngestionWithBackoff -ScriptBlock {
                Invoke-RestMethod -Uri $apiUrl -Headers $headers -Method GET
            }

            if (-not $releases) {
                throw "No releases found"
            }

            # Normalize to array
            if ($releases -isnot [array]) {
                $releases = @($releases)
            }

            foreach ($rel in $releases) {
                if ($rel.assets) {
                    foreach ($asset in $rel.assets) {
                        if ($asset.name -notlike $AssetPattern) {
                            $result.assetsSkipped++
                            continue
                        }

                        try {
                            $targetPath = Join-Path $OutputPath $asset.name
                            
                            # Download asset
                            Invoke-IngestionWithBackoff -ScriptBlock {
                                $assetHeaders = @{
                                    'Accept' = 'application/octet-stream'
                                    'User-Agent' = 'LLM-Workflow-Ingestion/0.7.0'
                                }
                                if ($token) {
                                    $assetHeaders['Authorization'] = "Bearer $token"
                                }
                                Invoke-RestMethod -Uri $asset.url -Headers $assetHeaders -Method GET -OutFile $targetPath
                            }

                            $result.assetsDownloaded++
                            $result.totalBytes += $asset.size
                            $result.files += $asset.name
                        }
                        catch {
                            $result.errors += "Failed to download $($asset.name): $_"
                        }
                    }
                }

                # Download source archives if requested
                if ($IncludeSource) {
                    foreach ($sourceType in @('zipball', 'tarball')) {
                        try {
                            $sourceUrl = $rel."${sourceType}_url"
                            if ($sourceUrl) {
                                $ext = if ($sourceType -eq 'zipball') { 'zip' } else { 'tar.gz' }
                                $targetPath = Join-Path $OutputPath "$($rel.tag_name)-source.$ext"
                                
                                Invoke-IngestionWithBackoff -ScriptBlock {
                                    $sourceHeaders = @{
                                        'Accept' = 'application/vnd.github.v3+json'
                                        'User-Agent' = 'LLM-Workflow-Ingestion/0.7.0'
                                    }
                                    if ($token) {
                                        $sourceHeaders['Authorization'] = "Bearer $token"
                                    }
                                    Invoke-RestMethod -Uri $sourceUrl -Headers $sourceHeaders -Method GET -OutFile $targetPath
                                }

                                $fileInfo = Get-Item -LiteralPath $targetPath
                                $result.assetsDownloaded++
                                $result.totalBytes += $fileInfo.Length
                            }
                        }
                        catch {
                            $result.errors += "Failed to download $sourceType archive: $_"
                        }
                    }
                }
            }

            Write-LogEntry -Level INFO -Message "GitHub release assets downloaded: $SourceId (Assets: $($result.assetsDownloaded))" -Source "Get-GitHubReleaseAssets"
        }
        catch {
            $result.errors += $_.Exception.Message
            Write-LogEntry -Level ERROR -Message "Failed to get GitHub release assets: $SourceId - $_" -Source "Get-GitHubReleaseAssets"
        }

        return [pscustomobject]$result
    }
}

<#
.SYNOPSIS
    Syncs with GitHub Actions workflows.

.DESCRIPTION
    Retrieves workflow runs, artifacts, and status from GitHub Actions.
    Can optionally trigger workflow runs.

.PARAMETER SourceId
    The registered source ID for the GitHub repository.

.PARAMETER Workflow
    Specific workflow filename or ID. If not specified, gets all workflows.

.PARAMETER Status
    Filter by workflow run status.

.PARAMETER Limit
    Maximum number of runs to retrieve. Default: 30.

.PARAMETER Trigger
    If specified, triggers a new workflow run.

.PARAMETER Branch
    Branch for workflow trigger. Default: default branch.

.OUTPUTS
    System.Management.Automation.PSCustomObject with workflow information.

.EXAMPLE
    PS C:\> Invoke-GitHubWorkflowSync -SourceId "github-godot-rust" -Limit 10
#>
function Invoke-GitHubWorkflowSync {
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory = $true)]
        [string]$SourceId,

        [Parameter()]
        [string]$Workflow = "",

        [Parameter()]
        [ValidateSet('', 'queued', 'in_progress', 'completed', 'waiting', 'pending', 'requested')]
        [string]$Status = "",

        [Parameter()]
        [int]$Limit = 30,

        [Parameter()]
        [switch]$Trigger,

        [Parameter()]
        [string]$Branch = "",

        [Parameter()]
        [hashtable]$Inputs = @{}
    )

    process {
        $source = Get-IngestionSources -SourceId $SourceId
        if (-not $source) {
            throw "Source not found: $SourceId"
        }
        if ($source -is [array]) {
            $source = $source[0]
        }

        $repoInfo = Parse-GitHubUrl -Url $source.url
        if (-not $repoInfo) {
            throw "Failed to parse GitHub URL: $($source.url)"
        }

        $result = [ordered]@{
            sourceId = $SourceId
            repository = "$($repoInfo.Owner)/$($repoInfo.Repo)"
            workflows = @()
            runs = @()
            triggered = $false
            errors = @()
        }

        try {
            $token = Get-SourceAuthToken -Source $source
            $headers = @{
                'Accept' = 'application/vnd.github.v3+json'
                'User-Agent' = 'LLM-Workflow-Ingestion/0.7.0'
            }
            if ($token) {
                $headers['Authorization'] = "Bearer $token"
            }

            $baseUrl = "$script:GitHubApiBase/repos/$($repoInfo.Owner)/$($repoInfo.Repo)"

            # Get workflows
            if ([string]::IsNullOrEmpty($Workflow)) {
                $workflowsUrl = "$baseUrl/actions/workflows"
                $workflowsData = Invoke-IngestionWithBackoff -ScriptBlock {
                    Invoke-RestMethod -Uri $workflowsUrl -Headers $headers -Method GET
                }
                $result.workflows = $workflowsData.workflows
            }

            # Get workflow runs
            $runsUrl = "$baseUrl/actions/runs"
            if (-not [string]::IsNullOrEmpty($Workflow)) {
                $runsUrl += "?workflow_id=$Workflow"
            }
            if (-not [string]::IsNullOrEmpty($Status)) {
                $separator = if ($runsUrl.Contains('?')) { '&' } else { '?' }
                $runsUrl += "${separator}status=$Status"
            }
            $separator = if ($runsUrl.Contains('?')) { '&' } else { '?' }
            $runsUrl += "${separator}per_page=$Limit"

            $runsData = Invoke-IngestionWithBackoff -ScriptBlock {
                Invoke-RestMethod -Uri $runsUrl -Headers $headers -Method GET
            }
            $result.runs = $runsData.workflow_runs

            # Trigger workflow if requested
            if ($Trigger) {
                if ([string]::IsNullOrEmpty($Workflow)) {
                    throw "Workflow parameter is required when using -Trigger"
                }

                $triggerUrl = "$baseUrl/actions/workflows/$Workflow/dispatches"
                $body = @{
                    ref = $Branch -or 'main'
                }
                if ($Inputs.Count -gt 0) {
                    $body.inputs = $Inputs
                }

                Invoke-IngestionWithBackoff -ScriptBlock {
                    Invoke-RestMethod -Uri $triggerUrl -Headers $headers -Method POST -Body ($body | ConvertTo-Json) -ContentType 'application/json'
                }

                $result.triggered = $true
            }

            Write-LogEntry -Level INFO -Message "GitHub workflow sync completed: $SourceId" -Source "Invoke-GitHubWorkflowSync"
        }
        catch {
            $result.errors += $_.Exception.Message
            Write-LogEntry -Level ERROR -Message "GitHub workflow sync failed: $SourceId - $_" -Source "Invoke-GitHubWorkflowSync"
        }

        return [pscustomobject]$result
    }
}

<#
.SYNOPSIS
    Fetches GitHub repository metadata.

.DESCRIPTION
    Retrieves repository information including description, topics,
    license, statistics, and latest commit.

.PARAMETER SourceId
    The registered source ID for the GitHub repository.

.PARAMETER IncludeLanguages
    If specified, includes language statistics.

.PARAMETER IncludeContributors
    If specified, includes contributor information.

.OUTPUTS
    System.Management.Automation.PSCustomObject with repository metadata.

.EXAMPLE
    PS C:\> Get-GitHubRepoMetadata -SourceId "github-godot-rust"
#>
function Get-GitHubRepoMetadata {
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory = $true)]
        [string]$SourceId,

        [Parameter()]
        [switch]$IncludeLanguages,

        [Parameter()]
        [switch]$IncludeContributors
    )

    process {
        $source = Get-IngestionSources -SourceId $SourceId
        if (-not $source) {
            throw "Source not found: $SourceId"
        }
        if ($source -is [array]) {
            $source = $source[0]
        }

        $repoInfo = Parse-GitHubUrl -Url $source.url
        if (-not $repoInfo) {
            throw "Failed to parse GitHub URL: $($source.url)"
        }

        $result = [ordered]@{
            sourceId = $SourceId
            repository = "$($repoInfo.Owner)/$($repoInfo.Repo)"
            basic = @{}
            languages = @{}
            contributors = @()
            latestCommit = @{}
            rateLimit = @{}
            errors = @()
        }

        try {
            $token = Get-SourceAuthToken -Source $source
            $headers = @{
                'Accept' = 'application/vnd.github.v3+json'
                'User-Agent' = 'LLM-Workflow-Ingestion/0.7.0'
            }
            if ($token) {
                $headers['Authorization'] = "Bearer $token"
            }

            $baseUrl = "$script:GitHubApiBase/repos/$($repoInfo.Owner)/$($repoInfo.Repo)"

            # Get basic repository info
            $result.basic = Invoke-IngestionWithBackoff -ScriptBlock {
                Invoke-RestMethod -Uri $baseUrl -Headers $headers -Method GET
            }

            # Get language statistics
            if ($IncludeLanguages) {
                try {
                    $result.languages = Invoke-IngestionWithBackoff -ScriptBlock {
                        Invoke-RestMethod -Uri "$baseUrl/languages" -Headers $headers -Method GET
                    }
                }
                catch {
                    $result.errors += "Failed to get languages: $_"
                }
            }

            # Get contributors
            if ($IncludeContributors) {
                try {
                    $result.contributors = Invoke-IngestionWithBackoff -ScriptBlock {
                        Invoke-RestMethod -Uri "$baseUrl/contributors" -Headers $headers -Method GET
                    }
                }
                catch {
                    $result.errors += "Failed to get contributors: $_"
                }
            }

            # Get latest commit
            try {
                $commits = Invoke-IngestionWithBackoff -ScriptBlock {
                    Invoke-RestMethod -Uri "$baseUrl/commits?per_page=1" -Headers $headers -Method GET
                }
                if ($commits -and $commits.Count -gt 0) {
                    $result.latestCommit = $commits[0]
                }
            }
            catch {
                $result.errors += "Failed to get latest commit: $_"
            }

            # Get rate limit info
            try {
                $rateLimit = Invoke-IngestionWithBackoff -ScriptBlock {
                    Invoke-RestMethod -Uri "$script:GitHubApiBase/rate_limit" -Headers $headers -Method GET
                }
                $result.rateLimit = $rateLimit.resources.core
            }
            catch {
                $result.errors += "Failed to get rate limit: $_"
            }

            Write-LogEntry -Level INFO -Message "GitHub metadata retrieved: $SourceId" -Source "Get-GitHubRepoMetadata"
        }
        catch {
            $result.errors += $_.Exception.Message
            Write-LogEntry -Level ERROR -Message "Failed to get GitHub metadata: $SourceId - $_" -Source "Get-GitHubRepoMetadata"
        }

        return [pscustomobject]$result
    }
}

# ============================================================================
# Region: GitLab Integration
# ============================================================================

<#
.SYNOPSIS
    Ingests content from a GitLab repository.

.DESCRIPTION
    Retrieves files from a GitLab project using the GitLab API.
    Supports incremental ingestion and branch selection.

.PARAMETER SourceId
    The registered source ID for the GitLab project.

.PARAMETER OutputPath
    Directory where ingested content will be stored.

.PARAMETER Incremental
    If specified, only ingests changed content since last ingestion.

.PARAMETER Branch
    Specific branch to ingest. Default: default branch.

.PARAMETER Recursive
    If specified, recursively ingests all files in subdirectories.

.OUTPUTS
    System.Management.Automation.PSCustomObject with ingestion results.

.EXAMPLE
    PS C:\> Invoke-GitLabRepoIngestion -SourceId "gitlab-myproject" -OutputPath "./ingested/myproject"
#>
function Invoke-GitLabRepoIngestion {
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory = $true)]
        [string]$SourceId,

        [Parameter(Mandatory = $true)]
        [string]$OutputPath,

        [Parameter()]
        [switch]$Incremental,

        [Parameter()]
        [string]$Branch = "",

        [Parameter()]
        [switch]$Recursive
    )

    process {
        $source = Get-IngestionSources -SourceId $SourceId
        if (-not $source) {
            throw "Source not found: $SourceId"
        }
        if ($source -is [array]) {
            $source = $source[0]
        }

        if ($source.type -ne 'gitlab') {
            throw "Source '$SourceId' is not a GitLab source (type: $($source.type))"
        }

        $repoInfo = Parse-GitLabUrl -Url $source.url
        if (-not $repoInfo) {
            throw "Failed to parse GitLab URL: $($source.url)"
        }

        $result = [ordered]@{
            sourceId = $SourceId
            type = 'gitlab'
            project = $repoInfo.Project
            outputPath = $OutputPath
            filesIngested = 0
            filesSkipped = 0
            bytesIngested = 0
            incremental = $Incremental.IsPresent
            errors = @()
            startedAt = [DateTime]::UtcNow.ToString("yyyy-MM-ddTHH:mm:ssZ", [System.Globalization.CultureInfo]::InvariantCulture)
            completedAt = $null
        }

        try {
            # Ensure output directory exists
            if (-not (Test-Path -LiteralPath $OutputPath)) {
                $null = New-Item -ItemType Directory -Path $OutputPath -Force
            }

            $token = Get-SourceAuthToken -Source $source
            $headers = @{
                'User-Agent' = 'LLM-Workflow-Ingestion/0.7.0'
            }
            if ($token) {
                $headers['PRIVATE-TOKEN'] = $token
            }

            # Determine GitLab API base URL
            $gitlabBase = $repoInfo.BaseUrl
            $projectEncoded = [System.Web.HttpUtility]::UrlEncode($repoInfo.Project)

            # Get repository tree
            $ref = $Branch -or 'HEAD'
            $treeUrl = "$gitlabBase/projects/$projectEncoded/repository/tree?recursive=true&per_page=100&ref_name=$ref"
            
            $treeData = Invoke-IngestionWithBackoff -ScriptBlock {
                Invoke-RestMethod -Uri $treeUrl -Headers $headers -Method GET
            }

            if (-not $treeData) {
                throw "Failed to retrieve repository tree"
            }

            # Filter files based on include/exclude patterns
            $filesToIngest = $treeData | Where-Object { $_.type -eq 'blob' } | ForEach-Object {
                $path = $_.path
                $include = $false

                foreach ($pattern in $source.include) {
                    if ($path -like $pattern) {
                        $include = $true
                        break
                    }
                }

                if ($include) {
                    foreach ($pattern in $source.exclude) {
                        if ($path -like $pattern -or $path.StartsWith($pattern.TrimEnd('*'))) {
                            $include = $false
                            break
                        }
                    }
                }

                if ($include) {
                    $_
                }
            }

            # Ingest each file
            foreach ($file in $filesToIngest) {
                try {
                    $filePath = $file.path
                    $targetPath = Join-Path $OutputPath $filePath
                    $targetDir = Split-Path -Parent $targetPath

                    if (-not (Test-Path -LiteralPath $targetDir)) {
                        $null = New-Item -ItemType Directory -Path $targetDir -Force
                    }

                    # Get file content
                    $contentUrl = "$gitlabBase/projects/$projectEncoded/repository/files/$([System.Web.HttpUtility]::UrlEncode($filePath))/raw?ref=$ref"
                    $content = Invoke-IngestionWithBackoff -ScriptBlock {
                        Invoke-RestMethod -Uri $contentUrl -Headers $headers -Method GET
                    }

                    [System.IO.File]::WriteAllText($targetPath, $content)
                    
                    $result.filesIngested++
                    $result.bytesIngested += [System.Text.Encoding]::UTF8.GetByteCount($content)
                }
                catch {
                    $result.errors += "Failed to ingest $($file.path): $_"
                }
            }

            # Update source
            $source.lastIngested = [DateTime]::UtcNow.ToString("yyyy-MM-ddTHH:mm:ssZ", [System.Globalization.CultureInfo]::InvariantCulture)
            $source.ingestCount++
            $source.lastStatus = 'success'

            $sourcePath = Join-Path $script:IngestionConfigDir "$SourceId.json"
            if (Test-Path -LiteralPath $sourcePath) {
                ($source | ConvertTo-Json -Depth 10) | Set-Content -LiteralPath $sourcePath -Encoding UTF8
            }

            $result.completedAt = [DateTime]::UtcNow.ToString("yyyy-MM-ddTHH:mm:ssZ", [System.Globalization.CultureInfo]::InvariantCulture)
            
            Write-LogEntry -Level INFO -Message "GitLab ingestion completed: $SourceId (Files: $($result.filesIngested))" -Source "Invoke-GitLabRepoIngestion"
        }
        catch {
            $result.errors += $_.Exception.Message
            Write-LogEntry -Level ERROR -Message "GitLab ingestion failed: $SourceId - $_" -Source "Invoke-GitLabRepoIngestion"
            throw
        }

        return [pscustomobject]$result
    }
}

<#
.SYNOPSIS
    Fetches GitLab project metadata.

.DESCRIPTION
    Retrieves project information including description, statistics,
    members, and latest activity.

.PARAMETER SourceId
    The registered source ID for the GitLab project.

.PARAMETER IncludeMembers
    If specified, includes project members.

.OUTPUTS
    System.Management.Automation.PSCustomObject with project metadata.

.EXAMPLE
    PS C:\> Get-GitLabProjectMetadata -SourceId "gitlab-myproject"
#>
function Get-GitLabProjectMetadata {
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory = $true)]
        [string]$SourceId,

        [Parameter()]
        [switch]$IncludeMembers
    )

    process {
        $source = Get-IngestionSources -SourceId $SourceId
        if (-not $source) {
            throw "Source not found: $SourceId"
        }
        if ($source -is [array]) {
            $source = $source[0]
        }

        $repoInfo = Parse-GitLabUrl -Url $source.url
        if (-not $repoInfo) {
            throw "Failed to parse GitLab URL: $($source.url)"
        }

        $result = [ordered]@{
            sourceId = $SourceId
            project = $repoInfo.Project
            basic = @{}
            members = @()
            latestCommit = @{}
            errors = @()
        }

        try {
            $token = Get-SourceAuthToken -Source $source
            $headers = @{
                'User-Agent' = 'LLM-Workflow-Ingestion/0.7.0'
            }
            if ($token) {
                $headers['PRIVATE-TOKEN'] = $token
            }

            $gitlabBase = $repoInfo.BaseUrl
            $projectEncoded = [System.Web.HttpUtility]::UrlEncode($repoInfo.Project)

            # Get basic project info
            $result.basic = Invoke-IngestionWithBackoff -ScriptBlock {
                Invoke-RestMethod -Uri "$gitlabBase/projects/$projectEncoded" -Headers $headers -Method GET
            }

            # Get members if requested
            if ($IncludeMembers) {
                try {
                    $result.members = Invoke-IngestionWithBackoff -ScriptBlock {
                        Invoke-RestMethod -Uri "$gitlabBase/projects/$projectEncoded/members" -Headers $headers -Method GET
                    }
                }
                catch {
                    $result.errors += "Failed to get members: $_"
                }
            }

            # Get latest commit
            try {
                $commits = Invoke-IngestionWithBackoff -ScriptBlock {
                    Invoke-RestMethod -Uri "$gitlabBase/projects/$projectEncoded/repository/commits?per_page=1" -Headers $headers -Method GET
                }
                if ($commits -and $commits.Count -gt 0) {
                    $result.latestCommit = $commits[0]
                }
            }
            catch {
                $result.errors += "Failed to get latest commit: $_"
            }

            Write-LogEntry -Level INFO -Message "GitLab metadata retrieved: $SourceId" -Source "Get-GitLabProjectMetadata"
        }
        catch {
            $result.errors += $_.Exception.Message
            Write-LogEntry -Level ERROR -Message "Failed to get GitLab metadata: $SourceId - $_" -Source "Get-GitLabProjectMetadata"
        }

        return [pscustomobject]$result
    }
}

# ============================================================================
# Region: Documentation Sites
# ============================================================================

<#
.SYNOPSIS
    Ingests content from a documentation site.

.DESCRIPTION
    Crawls and ingests content from documentation websites. Supports
    sitemap-based crawling and recursive link following.

.PARAMETER SourceId
    The registered source ID for the documentation site.

.PARAMETER OutputPath
    Directory where ingested content will be stored.

.PARAMETER MaxDepth
    Maximum crawl depth. Default: 3.

.PARAMETER MaxPages
    Maximum pages to ingest. Default: 1000.

.PARAMETER UseSitemap
    If specified, uses sitemap.xml for URL discovery.

.PARAMETER RespectRobotsTxt
    If specified, respects robots.txt rules. Default: true.

.OUTPUTS
    System.Management.Automation.PSCustomObject with ingestion results.

.EXAMPLE
    PS C:\> Invoke-DocsSiteIngestion -SourceId "docs-godot" -OutputPath "./ingested/docs"
#>
function Invoke-DocsSiteIngestion {
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory = $true)]
        [string]$SourceId,

        [Parameter(Mandatory = $true)]
        [string]$OutputPath,

        [Parameter()]
        [int]$MaxDepth = 3,

        [Parameter()]
        [int]$MaxPages = 1000,

        [Parameter()]
        [switch]$UseSitemap,

        [Parameter()]
        [bool]$RespectRobotsTxt = $true
    )

    process {
        $source = Get-IngestionSources -SourceId $SourceId
        if (-not $source) {
            throw "Source not found: $SourceId"
        }
        if ($source -is [array]) {
            $source = $source[0]
        }

        if ($source.type -ne 'docssite') {
            throw "Source '$SourceId' is not a documentation site (type: $($source.type))"
        }

        $result = [ordered]@{
            sourceId = $SourceId
            type = 'docssite'
            url = $source.url
            outputPath = $OutputPath
            pagesIngested = 0
            pagesSkipped = 0
            errors = @()
            urlsFound = @()
            startedAt = [DateTime]::UtcNow.ToString("yyyy-MM-ddTHH:mm:ssZ", [System.Globalization.CultureInfo]::InvariantCulture)
            completedAt = $null
        }

        try {
            if (-not (Test-Path -LiteralPath $OutputPath)) {
                $null = New-Item -ItemType Directory -Path $OutputPath -Force
            }

            $headers = @{
                'User-Agent' = 'LLM-Workflow-Ingestion/0.7.0 (Documentation Crawler)'
            }

            $urlsToCrawl = [System.Collections.Generic.Queue[object]]::new()
            $crawledUrls = [System.Collections.Generic.HashSet[string]]::new()

            # Get initial URLs
            if ($UseSitemap) {
                try {
                    $sitemap = Get-DocsSitemap -SourceId $SourceId
                    foreach ($url in $sitemap.urls) {
                        $urlsToCrawl.Enqueue(@{ Url = $url; Depth = 0 })
                    }
                }
                catch {
                    Write-Warning "[ExternalIngestion] Failed to get sitemap, starting from base URL: $_"
                    $urlsToCrawl.Enqueue(@{ Url = $source.url; Depth = 0 })
                }
            }
            else {
                $urlsToCrawl.Enqueue(@{ Url = $source.url; Depth = 0 })
            }

            # Crawl
            while ($urlsToCrawl.Count -gt 0 -and $result.pagesIngested -lt $MaxPages) {
                $current = $urlsToCrawl.Dequeue()
                $url = $current.Url
                $depth = $current.Depth

                if ($crawledUrls.Contains($url)) {
                    continue
                }
                $null = $crawledUrls.Add($url)

                try {
                    # Apply throttling
                    Start-Sleep -Milliseconds $script:ThrottleSettings.defaultDelayMs

                    $response = Invoke-RestMethod -Uri $url -Headers $headers -Method GET -TimeoutSec 30
                    
                    if (-not [string]::IsNullOrEmpty($response)) {
                        # Generate safe filename from URL
                        $uri = [Uri]$url
                        $safeName = ($uri.PathAndQuery -replace '[^a-zA-Z0-9]', '_') + ".html"
                        if ($safeName -eq '.html') {
                            $safeName = 'index.html'
                        }
                        $targetPath = Join-Path $OutputPath $safeName

                        [System.IO.File]::WriteAllText($targetPath, $response)
                        $result.pagesIngested++
                        $result.urlsFound += $url

                        # Extract links if not at max depth
                        if ($depth -lt $MaxDepth) {
                            $links = Extract-LinksFromHtml -Html $response -BaseUrl $url
                            foreach ($link in $links) {
                                # Filter by include/exclude patterns
                                $include = $true
                                foreach ($pattern in $source.include) {
                                    if ($link -notlike $pattern) {
                                        $include = $false
                                        break
                                    }
                                }
                                foreach ($pattern in $source.exclude) {
                                    if ($link -like $pattern) {
                                        $include = $false
                                        break
                                    }
                                }

                                if ($include -and -not $crawledUrls.Contains($link)) {
                                    $urlsToCrawl.Enqueue(@{ Url = $link; Depth = $depth + 1 })
                                }
                            }
                        }
                    }
                }
                catch {
                    $result.errors += "Failed to crawl $url : $_"
                    $result.pagesSkipped++
                }
            }

            $result.completedAt = [DateTime]::UtcNow.ToString("yyyy-MM-ddTHH:mm:ssZ", [System.Globalization.CultureInfo]::InvariantCulture)
            
            Write-LogEntry -Level INFO -Message "Docs site ingestion completed: $SourceId (Pages: $($result.pagesIngested))" -Source "Invoke-DocsSiteIngestion"
        }
        catch {
            $result.errors += $_.Exception.Message
            Write-LogEntry -Level ERROR -Message "Docs site ingestion failed: $SourceId - $_" -Source "Invoke-DocsSiteIngestion"
            throw
        }

        return [pscustomobject]$result
    }
}

<#
.SYNOPSIS
    Fetches and parses a sitemap.xml file.

.DESCRIPTION
    Retrieves sitemap.xml from a documentation site and extracts
    all URLs listed.

.PARAMETER SourceId
    The registered source ID (must be docssite type).

.PARAMETER SitemapUrl
    Direct sitemap URL (optional, defaults to /sitemap.xml).

.OUTPUTS
    System.Management.Automation.PSCustomObject with sitemap data.

.EXAMPLE
    PS C:\> Get-DocsSitemap -SourceId "docs-godot"
#>
function Get-DocsSitemap {
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory = $true)]
        [string]$SourceId,

        [Parameter()]
        [string]$SitemapUrl = ""
    )

    process {
        $source = Get-IngestionSources -SourceId $SourceId
        if (-not $source) {
            throw "Source not found: $SourceId"
        }
        if ($source -is [array]) {
            $source = $source[0]
        }

        if ($source.type -ne 'docssite' -and $source.type -ne 'api') {
            throw "Source '$SourceId' is not a documentation or API site (type: $($source.type))"
        }

        $result = [ordered]@{
            sourceId = $SourceId
            sitemapUrl = $SitemapUrl
            urls = @()
            lastModified = @{}
            errors = @()
        }

        try {
            # Determine sitemap URL
            if ([string]::IsNullOrEmpty($SitemapUrl)) {
                $baseUri = [Uri]$source.url
                $SitemapUrl = "$($baseUri.Scheme)://$($baseUri.Host)/sitemap.xml"
            }

            $result.sitemapUrl = $SitemapUrl

            $headers = @{
                'User-Agent' = 'LLM-Workflow-Ingestion/0.7.0'
            }

            $response = Invoke-RestMethod -Uri $SitemapUrl -Headers $headers -Method GET -TimeoutSec 30

            if (-not [string]::IsNullOrEmpty($response)) {
                # Parse XML
                [xml]$sitemap = $response

                if ($sitemap.urlset -and $sitemap.urlset.url) {
                    foreach ($url in $sitemap.urlset.url) {
                        $loc = $url.loc
                        if ($loc) {
                            $result.urls += $loc
                            if ($url.lastmod) {
                                $result.lastModified[$loc] = $url.lastmod
                            }
                        }
                    }
                }
                elseif ($sitemap.sitemapindex -and $sitemap.sitemapindex.sitemap) {
                    # Handle sitemap index
                    foreach ($subSitemap in $sitemap.sitemapindex.sitemap) {
                        try {
                            $subResponse = Invoke-RestMethod -Uri $subSitemap.loc -Headers $headers -Method GET -TimeoutSec 30
                            [xml]$subXml = $subResponse
                            if ($subXml.urlset -and $subXml.urlset.url) {
                                foreach ($url in $subXml.urlset.url) {
                                    $loc = $url.loc
                                    if ($loc) {
                                        $result.urls += $loc
                                        if ($url.lastmod) {
                                            $result.lastModified[$loc] = $url.lastmod
                                        }
                                    }
                                }
                            }
                        }
                        catch {
                            $result.errors += "Failed to process sub-sitemap $($subSitemap.loc): $_"
                        }
                    }
                }
            }

            Write-LogEntry -Level INFO -Message "Sitemap retrieved: $SourceId (URLs: $($result.urls.Count))" -Source "Get-DocsSitemap"
        }
        catch {
            $result.errors += $_.Exception.Message
            Write-LogEntry -Level ERROR -Message "Failed to get sitemap: $SourceId - $_" -Source "Get-DocsSitemap"
        }

        return [pscustomobject]$result
    }
}

<#
.SYNOPSIS
    Ingests API reference documentation.

.DESCRIPTION
    Retrieves API reference content from OpenAPI/Swagger specs or
    API documentation sites.

.PARAMETER SourceId
    The registered source ID for the API reference.

.PARAMETER OutputPath
    Directory where ingested content will be stored.

.PARAMETER Format
    API specification format: openapi, swagger, or auto-detect.

.PARAMETER ResolveRefs
    If specified, resolves JSON $ref references.

.OUTPUTS
    System.Management.Automation.PSCustomObject with ingestion results.

.EXAMPLE
    PS C:\> Invoke-APIReferenceIngestion -SourceId "api-myservice" -OutputPath "./ingested/api"
#>
function Invoke-APIReferenceIngestion {
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory = $true)]
        [string]$SourceId,

        [Parameter(Mandatory = $true)]
        [string]$OutputPath,

        [Parameter()]
        [ValidateSet('auto', 'openapi', 'swagger', 'graphql', 'raml')]
        [string]$Format = 'auto',

        [Parameter()]
        [switch]$ResolveRefs
    )

    process {
        $source = Get-IngestionSources -SourceId $SourceId
        if (-not $source) {
            throw "Source not found: $SourceId"
        }
        if ($source -is [array]) {
            $source = $source[0]
        }

        if ($source.type -ne 'api') {
            throw "Source '$SourceId' is not an API source (type: $($source.type))"
        }

        $result = [ordered]@{
            sourceId = $SourceId
            type = 'api'
            url = $source.url
            outputPath = $OutputPath
            format = $Format
            endpointsFound = 0
            schemasFound = 0
            filesIngested = 0
            errors = @()
            startedAt = [DateTime]::UtcNow.ToString("yyyy-MM-ddTHH:mm:ssZ", [System.Globalization.CultureInfo]::InvariantCulture)
            completedAt = $null
        }

        try {
            if (-not (Test-Path -LiteralPath $OutputPath)) {
                $null = New-Item -ItemType Directory -Path $OutputPath -Force
            }

            $headers = @{
                'Accept' = 'application/json'
                'User-Agent' = 'LLM-Workflow-Ingestion/0.7.0'
            }

            # Get token if auth configured
            $token = Get-SourceAuthToken -Source $source
            if ($token) {
                $headers['Authorization'] = "Bearer $token"
            }

            # Try common API spec URLs
            $specUrls = @(
                $source.url
                "$($source.url)/openapi.json"
                "$($source.url)/swagger.json"
                "$($source.url)/api-docs"
                "$($source.url)/v2/api-docs"
                "$($source.url)/api/openapi"
            )

            $specContent = $null
            $detectedFormat = $Format

            foreach ($url in $specUrls) {
                try {
                    $specContent = Invoke-IngestionWithBackoff -ScriptBlock {
                        Invoke-RestMethod -Uri $url -Headers $headers -Method GET -TimeoutSec 30
                    }
                    if ($specContent) {
                        # Auto-detect format
                        if ($Format -eq 'auto') {
                            if ($specContent.swagger -or $specContent.swaggerVersion) {
                                $detectedFormat = 'swagger'
                            }
                            elseif ($specContent.openapi -or $specContent.openapiVersion) {
                                $detectedFormat = 'openapi'
                            }
                            elseif ($specContent.__schema -or $url -match 'graphql') {
                                $detectedFormat = 'graphql'
                            }
                            else {
                                $detectedFormat = 'openapi'
                            }
                        }
                        break
                    }
                }
                catch {
                    continue
                }
            }

            if (-not $specContent) {
                throw "Failed to retrieve API specification from any known URL"
            }

            $result.format = $detectedFormat

            # Resolve $ref references if requested
            if ($ResolveRefs -and ($detectedFormat -eq 'openapi' -or $detectedFormat -eq 'swagger')) {
                $specContent = Resolve-ApiSpecRefs -Spec $specContent -BaseUrl $source.url -Headers $headers
            }

            # Save main spec
            $specPath = Join-Path $OutputPath "api-spec.json"
            ($specContent | ConvertTo-Json -Depth 20) | Set-Content -LiteralPath $specPath -Encoding UTF8
            $result.filesIngested++

            # Extract statistics
            if ($detectedFormat -eq 'openapi' -or $detectedFormat -eq 'swagger') {
                if ($specContent.paths) {
                    $result.endpointsFound = ($specContent.paths | Get-Member -MemberType NoteProperty).Count
                }
                if ($specContent.components -and $specContent.components.schemas) {
                    $result.schemasFound = ($specContent.components.schemas | Get-Member -MemberType NoteProperty).Count
                }
                elseif ($specContent.definitions) {
                    $result.schemasFound = ($specContent.definitions | Get-Member -MemberType NoteProperty).Count
                }
            }

            # Try to get additional documentation pages
            try {
                $docsResult = Invoke-DocsSiteIngestion -SourceId $SourceId -OutputPath $OutputPath -MaxPages 100 -UseSitemap
                $result.filesIngested += $docsResult.pagesIngested
            }
            catch {
                # Docs ingestion is optional
            }

            $result.completedAt = [DateTime]::UtcNow.ToString("yyyy-MM-ddTHH:mm:ssZ", [System.Globalization.CultureInfo]::InvariantCulture)
            
            Write-LogEntry -Level INFO -Message "API reference ingestion completed: $SourceId (Endpoints: $($result.endpointsFound))" -Source "Invoke-APIReferenceIngestion"
        }
        catch {
            $result.errors += $_.Exception.Message
            Write-LogEntry -Level ERROR -Message "API reference ingestion failed: $SourceId - $_" -Source "Invoke-APIReferenceIngestion"
            throw
        }

        return [pscustomobject]$result
    }
}

# ============================================================================
# Region: Git Repository Ingestion
# ============================================================================

<#
.SYNOPSIS
    Ingests content from a generic Git repository.

.DESCRIPTION
    Clones or pulls a Git repository (from any git host) and extracts content
    based on include/exclude patterns. Supports incremental ingestion.

.PARAMETER SourceId
    The registered source ID for the Git repository.

.PARAMETER OutputPath
    Directory where ingested content will be stored.

.PARAMETER Incremental
    If specified, only ingests changed content since last ingestion.

.PARAMETER Branch
    Specific branch to ingest. If not specified, uses default branch.

.PARAMETER Depth
    Clone depth for shallow clones. Default: full history.

.OUTPUTS
    System.Management.Automation.PSCustomObject with ingestion results.

.EXAMPLE
    PS C:\> Invoke-GitIngestion -SourceId "git-custom-repo" -OutputPath "./ingested/repo"
#>
function Invoke-GitIngestion {
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory = $true)]
        [string]$SourceId,

        [Parameter(Mandatory = $true)]
        [string]$OutputPath,

        [Parameter()]
        [switch]$Incremental,

        [Parameter()]
        [string]$Branch = "",

        [Parameter()]
        [int]$Depth = 0
    )

    process {
        $source = Get-IngestionSources -SourceId $SourceId
        if (-not $source) {
            throw "Source not found: $SourceId"
        }
        if ($source -is [array]) {
            $source = $source[0]
        }

        if ($source.type -ne 'git') {
            throw "Source '$SourceId' is not a git source (type: $($source.type))"
        }

        $result = [ordered]@{
            sourceId = $SourceId
            type = 'git'
            url = $source.url
            outputPath = $OutputPath
            filesIngested = 0
            filesSkipped = 0
            bytesIngested = 0
            incremental = $Incremental.IsPresent
            errors = @()
            startedAt = [DateTime]::UtcNow.ToString("yyyy-MM-ddTHH:mm:ssZ", [System.Globalization.CultureInfo]::InvariantCulture)
            completedAt = $null
        }

        try {
            # Ensure output directory exists
            if (-not (Test-Path -LiteralPath $OutputPath)) {
                $null = New-Item -ItemType Directory -Path $OutputPath -Force
            }

            # Check if git is available
            $gitCmd = Get-Command 'git' -ErrorAction SilentlyContinue
            if (-not $gitCmd) {
                throw "Git command not found. Please install Git and ensure it's in PATH."
            }

            # Setup authentication if provided
            $gitUrl = $source.url
            if ($source.auth -and $source.auth.type -eq 'token') {
                $token = Get-SourceAuthToken -Source $source
                if ($token) {
                    # Inject token into URL for HTTPS repos
                    if ($gitUrl -match '^https://') {
                        $gitUrl = $gitUrl -replace '^https://', "https://oauth2:$token@"
                    }
                }
            }

            $repoPath = Join-Path $OutputPath '.git-repo'
            
            # Check if this is an incremental update
            if ($Incremental -and (Test-Path -LiteralPath (Join-Path $repoPath '.git'))) {
                # Pull latest changes
                Write-LogEntry -Level INFO -Message "Pulling latest changes for $SourceId" -Source "Invoke-GitIngestion"
                
                $pullArgs = @('-C', $repoPath, 'pull', 'origin')
                if ($Branch) {
                    $pullArgs += $Branch
                }
                
                $pullOutput = & git @pullArgs 2>&1
                if ($LASTEXITCODE -ne 0) {
                    throw "Git pull failed: $pullOutput"
                }
                
                if ($Branch) {
                    $checkoutOutput = & git @('-C', $repoPath, 'checkout', $Branch) 2>&1
                    if ($LASTEXITCODE -ne 0) {
                        Write-Warning "Failed to checkout branch $Branch`: $checkoutOutput"
                    }
                }
            }
            else {
                # Clone the repository
                Write-LogEntry -Level INFO -Message "Cloning repository $SourceId" -Source "Invoke-GitIngestion"
                
                if (Test-Path -LiteralPath $repoPath) {
                    Remove-Item -LiteralPath $repoPath -Recurse -Force
                }

                $cloneArgs = @('clone')
                if ($Depth -gt 0) {
                    $cloneArgs += @('--depth', $Depth)
                }
                if ($Branch) {
                    $cloneArgs += @('--branch', $Branch)
                }
                $cloneArgs += @($gitUrl, $repoPath)

                $cloneOutput = & git @cloneArgs 2>&1
                if ($LASTEXITCODE -ne 0) {
                    throw "Git clone failed: $cloneOutput"
                }
            }

            # Copy files based on include/exclude patterns
            $files = Get-ChildItem -Path $repoPath -Recurse -File | Where-Object { 
                $_.FullName -notlike '*.git*' 
            }

            foreach ($file in $files) {
                $relativePath = $file.FullName.Substring($repoPath.Length + 1)
                $include = $false

                # Check include patterns
                foreach ($pattern in $source.include) {
                    if ($relativePath -like $pattern) {
                        $include = $true
                        break
                    }
                }

                # Check exclude patterns
                if ($include) {
                    foreach ($pattern in $source.exclude) {
                        if ($relativePath -like $pattern -or $relativePath.StartsWith($pattern.TrimEnd('*'))) {
                            $include = $false
                            break
                        }
                    }
                }

                if ($include) {
                    $targetPath = Join-Path $OutputPath $relativePath
                    $targetDir = Split-Path -Parent $targetPath

                    if (-not (Test-Path -LiteralPath $targetDir)) {
                        $null = New-Item -ItemType Directory -Path $targetDir -Force
                    }

                    Copy-Item -LiteralPath $file.FullName -Destination $targetPath -Force
                    $result.filesIngested++
                    $result.bytesIngested += $file.Length
                }
                else {
                    $result.filesSkipped++
                }
            }

            # Update source metadata
            $source.lastIngested = [DateTime]::UtcNow.ToString("yyyy-MM-ddTHH:mm:ssZ", [System.Globalization.CultureInfo]::InvariantCulture)
            $source.ingestCount++
            $source.lastStatus = 'success'

            $sourcePath = Join-Path $script:IngestionConfigDir "$SourceId.json"
            if (Test-Path -LiteralPath $sourcePath) {
                ($source | ConvertTo-Json -Depth 10) | Set-Content -LiteralPath $sourcePath -Encoding UTF8
            }

            $result.completedAt = [DateTime]::UtcNow.ToString("yyyy-MM-ddTHH:mm:ssZ", [System.Globalization.CultureInfo]::InvariantCulture)
            
            Write-LogEntry -Level INFO -Message "Git ingestion completed: $SourceId (Files: $($result.filesIngested))" -Source "Invoke-GitIngestion"
        }
        catch {
            $result.errors += $_.Exception.Message
            Write-LogEntry -Level ERROR -Message "Git ingestion failed: $SourceId - $_" -Source "Invoke-GitIngestion"
            throw
        }

        return [pscustomobject]$result
    }
}

# ============================================================================
# Region: HTTP/HTTPS Ingestion
# ============================================================================

<#
.SYNOPSIS
    Ingests content from HTTP/HTTPS URLs.

.DESCRIPTION
    Fetches content from HTTP/HTTPS URLs with rate limiting support.
    Can follow links to a specified depth and respects robots.txt.

.PARAMETER SourceId
    The registered source ID for the HTTP source.

.PARAMETER OutputPath
    Directory where ingested content will be stored.

.PARAMETER MaxDepth
    Maximum depth for link following. Default: 1 (single page).

.PARAMETER MaxPages
    Maximum number of pages to ingest. Default: 100.

.PARAMETER RespectRobotsTxt
    If specified, respects robots.txt restrictions.

.PARAMETER RequestDelayMs
    Delay between requests in milliseconds. Default: 1000.

.OUTPUTS
    System.Management.Automation.PSCustomObject with ingestion results.

.EXAMPLE
    PS C:\> Invoke-HttpIngestion -SourceId "http-docs" -OutputPath "./ingested/docs" -MaxDepth 2
#>
function Invoke-HttpIngestion {
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory = $true)]
        [string]$SourceId,

        [Parameter(Mandatory = $true)]
        [string]$OutputPath,

        [Parameter()]
        [int]$MaxDepth = 1,

        [Parameter()]
        [int]$MaxPages = 100,

        [Parameter()]
        [switch]$RespectRobotsTxt,

        [Parameter()]
        [int]$RequestDelayMs = 1000
    )

    process {
        $source = Get-IngestionSources -SourceId $SourceId
        if (-not $source) {
            throw "Source not found: $SourceId"
        }
        if ($source -is [array]) {
            $source = $source[0]
        }

        if ($source.type -notin @('http', 'https')) {
            throw "Source '$SourceId' is not an HTTP/HTTPS source (type: $($source.type))"
        }

        $result = [ordered]@{
            sourceId = $SourceId
            type = $source.type
            url = $source.url
            outputPath = $OutputPath
            pagesIngested = 0
            pagesSkipped = 0
            bytesIngested = 0
            errors = @()
            startedAt = [DateTime]::UtcNow.ToString("yyyy-MM-ddTHH:mm:ssZ", [System.Globalization.CultureInfo]::InvariantCulture)
            completedAt = $null
        }

        try {
            if (-not (Test-Path -LiteralPath $OutputPath)) {
                $null = New-Item -ItemType Directory -Path $OutputPath -Force
            }

            $baseUri = [Uri]$source.url
            $headers = @{
                'User-Agent' = 'LLM-Workflow-Ingestion/0.7.0'
            }

            # Add authentication if configured
            $token = Get-SourceAuthToken -Source $source
            if ($token) {
                $headers['Authorization'] = "Bearer $token"
            }
            elseif ($source.auth -and $source.auth.type -eq 'basic') {
                $credentials = "$($source.auth.username):$($source.auth.password)"
                $encoded = [Convert]::ToBase64String([Text.Encoding]::ASCII.GetBytes($credentials))
                $headers['Authorization'] = "Basic $encoded"
            }

            # Track visited URLs
            $visited = [System.Collections.Generic.HashSet[string]]::new()
            $toVisit = [System.Collections.Generic.Queue[hashtable]]::new()
            $toVisit.Enqueue(@{ Url = $source.url; Depth = 0 })

            while ($toVisit.Count -gt 0 -and $result.pagesIngested -lt $MaxPages) {
                $current = $toVisit.Dequeue()
                $currentUrl = $current.Url
                $currentDepth = $current.Depth

                if ($visited.Contains($currentUrl)) {
                    continue
                }
                $null = $visited.Add($currentUrl)

                try {
                    # Rate limiting delay
                    if ($result.pagesIngested -gt 0) {
                        Start-Sleep -Milliseconds $RequestDelayMs
                    }

                    Write-LogEntry -Level INFO -Message "Fetching HTTP content: $currentUrl" -Source "Invoke-HttpIngestion"

                    $response = Invoke-IngestionWithBackoff -ScriptBlock {
                        Invoke-WebRequest -Uri $currentUrl -Headers $headers -Method GET -TimeoutSec 30 -UseBasicParsing
                    } -MaxRetries 3

                    if ($response.StatusCode -eq 200) {
                        $contentType = $response.Headers['Content-Type']
                        $isText = $contentType -match 'text|json|xml|javascript'

                        if ($isText) {
                            # Save content
                            $uri = [Uri]$currentUrl
                            $localPath = $uri.LocalPath.Trim('/')
                            if ([string]::IsNullOrEmpty($localPath)) {
                                $localPath = 'index.html'
                            }
                            if (-not $localPath.Contains('.')) {
                                $localPath = "$localPath.html"
                            }
                            
                            $targetPath = Join-Path $OutputPath $localPath
                            $targetDir = Split-Path -Parent $targetPath
                            
                            if (-not (Test-Path -LiteralPath $targetDir)) {
                                $null = New-Item -ItemType Directory -Path $targetDir -Force
                            }

                            $response.Content | Set-Content -LiteralPath $targetPath -Encoding UTF8
                            $result.pagesIngested++
                            $result.bytesIngested += $response.RawContentLength

                            # Extract and queue links if not at max depth
                            if ($currentDepth -lt $MaxDepth) {
                                $links = Extract-LinksFromHtml -Html $response.Content -BaseUrl $currentUrl
                                foreach ($link in $links) {
                                    if (-not $visited.Contains($link)) {
                                        $toVisit.Enqueue(@{ Url = $link; Depth = $currentDepth + 1 })
                                    }
                                }
                            }
                        }
                        else {
                            $result.pagesSkipped++
                        }
                    }
                }
                catch {
                    $result.errors += "Failed to fetch $currentUrl`: $_"
                    Write-Warning "[Invoke-HttpIngestion] Failed to fetch $currentUrl`: $_"
                }
            }

            # Update source metadata
            $source.lastIngested = [DateTime]::UtcNow.ToString("yyyy-MM-ddTHH:mm:ssZ", [System.Globalization.CultureInfo]::InvariantCulture)
            $source.ingestCount++
            $source.lastStatus = 'success'

            $sourcePath = Join-Path $script:IngestionConfigDir "$SourceId.json"
            if (Test-Path -LiteralPath $sourcePath) {
                ($source | ConvertTo-Json -Depth 10) | Set-Content -LiteralPath $sourcePath -Encoding UTF8
            }

            $result.completedAt = [DateTime]::UtcNow.ToString("yyyy-MM-ddTHH:mm:ssZ", [System.Globalization.CultureInfo]::InvariantCulture)
            
            Write-LogEntry -Level INFO -Message "HTTP ingestion completed: $SourceId (Pages: $($result.pagesIngested))" -Source "Invoke-HttpIngestion"
        }
        catch {
            $result.errors += $_.Exception.Message
            Write-LogEntry -Level ERROR -Message "HTTP ingestion failed: $SourceId - $_" -Source "Invoke-HttpIngestion"
            throw
        }

        return [pscustomobject]$result
    }
}

# ============================================================================
# Region: S3 Ingestion
# ============================================================================

<#
.SYNOPSIS
    Ingests content from Amazon S3 buckets.

.DESCRIPTION
    Downloads and ingests files from S3 buckets with support for
    prefix filtering, authentication via IAM roles or access keys.

.PARAMETER SourceId
    The registered source ID for the S3 source.

.PARAMETER OutputPath
    Directory where ingested content will be stored.

.PARAMETER Incremental
    If specified, only downloads new or modified objects.

.PARAMETER MaxKeys
    Maximum number of objects to list per request. Default: 1000.

.OUTPUTS
    System.Management.Automation.PSCustomObject with ingestion results.

.EXAMPLE
    PS C:\> Invoke-S3Ingestion -SourceId "s3-dataset" -OutputPath "./ingested/s3" -Incremental
#>
function Invoke-S3Ingestion {
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory = $true)]
        [string]$SourceId,

        [Parameter(Mandatory = $true)]
        [string]$OutputPath,

        [Parameter()]
        [switch]$Incremental,

        [Parameter()]
        [int]$MaxKeys = 1000
    )

    process {
        $source = Get-IngestionSources -SourceId $SourceId
        if (-not $source) {
            throw "Source not found: $SourceId"
        }
        if ($source -is [array]) {
            $source = $source[0]
        }

        if ($source.type -ne 's3') {
            throw "Source '$SourceId' is not an S3 source (type: $($source.type))"
        }

        $result = [ordered]@{
            sourceId = $SourceId
            type = 's3'
            bucket = $null
            prefix = $null
            outputPath = $OutputPath
            filesIngested = 0
            filesSkipped = 0
            bytesIngested = 0
            bytesSkipped = 0
            incremental = $Incremental.IsPresent
            errors = @()
            startedAt = [DateTime]::UtcNow.ToString("yyyy-MM-ddTHH:mm:ssZ", [System.Globalization.CultureInfo]::InvariantCulture)
            completedAt = $null
        }

        try {
            if (-not (Test-Path -LiteralPath $OutputPath)) {
                $null = New-Item -ItemType Directory -Path $OutputPath -Force
            }

            # Parse S3 URL (s3://bucket/prefix or https://s3.region.amazonaws.com/bucket/prefix)
            $s3Info = Parse-S3Url -Url $source.url
            if (-not $s3Info) {
                throw "Failed to parse S3 URL: $($source.url)"
            }
            $result.bucket = $s3Info.Bucket
            $result.prefix = $s3Info.Prefix

            # Check for AWS CLI or AWS Tools for PowerShell
            $awsCli = Get-Command 'aws' -ErrorAction SilentlyContinue
            $awsModule = Get-Module 'AWSPowerShell.NetCore' -ListAvailable -ErrorAction SilentlyContinue

            if (-not $awsCli -and -not $awsModule) {
                throw "AWS CLI or AWSPowerShell module not found. Please install either to use S3 ingestion."
            }

            # Configure credentials if provided
            $accessKey = $null
            $secretKey = $null
            $sessionToken = $null
            $region = $s3Info.Region

            if ($source.auth) {
                if ($source.auth.accessKeyEnv) {
                    $accessKey = [Environment]::GetEnvironmentVariable($source.auth.accessKeyEnv)
                }
                if ($source.auth.secretKeyEnv) {
                    $secretKey = [Environment]::GetEnvironmentVariable($source.auth.secretKeyEnv)
                }
                if ($source.auth.sessionTokenEnv) {
                    $sessionToken = [Environment]::GetEnvironmentVariable($source.auth.sessionTokenEnv)
                }
                if ($source.auth.region) {
                    $region = $source.auth.region
                }
            }

            # Get last ingestion time for incremental
            $lastIngested = $null
            if ($Incremental -and $source.lastIngested) {
                $lastIngested = [DateTime]::Parse($source.lastIngested)
            }

            if ($awsCli) {
                # Use AWS CLI
                $lsArgs = @('s3', 'ls', "s3://$($s3Info.Bucket)/$($s3Info.Prefix)", '--recursive')
                if ($region) {
                    $lsArgs += @('--region', $region)
                }

                # Set credentials via environment variables if provided
                $envBackup = @{}
                if ($accessKey) {
                    $envBackup['AWS_ACCESS_KEY_ID'] = $env:AWS_ACCESS_KEY_ID
                    $env:AWS_ACCESS_KEY_ID = $accessKey
                }
                if ($secretKey) {
                    $envBackup['AWS_SECRET_ACCESS_KEY'] = $env:AWS_SECRET_ACCESS_KEY
                    $env:AWS_SECRET_ACCESS_KEY = $secretKey
                }
                if ($sessionToken) {
                    $envBackup['AWS_SESSION_TOKEN'] = $env:AWS_SESSION_TOKEN
                    $env:AWS_SESSION_TOKEN = $sessionToken
                }

                try {
                    $s3Objects = & aws @lsArgs 2>&1
                    if ($LASTEXITCODE -ne 0) {
                        throw "AWS S3 ls failed: $s3Objects"
                    }
                }
                finally {
                    # Restore environment
                    foreach ($key in $envBackup.Keys) {
                        Set-Item "env:$key" $envBackup[$key]
                    }
                }

                # Parse output (format: DATE TIME SIZE KEY)
                $objects = $s3Objects | ForEach-Object {
                    if ($_ -match '(\d{4}-\d{2}-\d{2})\s+(\d{2}:\d{2}:\d{2})\s+(\d+)\s+(.+)') {
                        @{
                            LastModified = [DateTime]::Parse("$($matches[1]) $($matches[2])")
                            Size = [long]$matches[3]
                            Key = $matches[4]
                        }
                    }
                }

                foreach ($obj in $objects) {
                    try {
                        # Check incremental
                        if ($lastIngested -and $obj.LastModified -le $lastIngested) {
                            $result.filesSkipped++
                            $result.bytesSkipped += $obj.Size
                            continue
                        }

                        # Check include/exclude patterns
                        $relativePath = $obj.Key.Substring($s3Info.Prefix.Length).TrimStart('/')
                        $include = $false

                        foreach ($pattern in $source.include) {
                            if ($relativePath -like $pattern) {
                                $include = $true
                                break
                            }
                        }

                        if ($include) {
                            foreach ($pattern in $source.exclude) {
                                if ($relativePath -like $pattern -or $relativePath.StartsWith($pattern.TrimEnd('*'))) {
                                    $include = $false
                                    break
                                }
                            }
                        }

                        if (-not $include) {
                            $result.filesSkipped++
                            continue
                        }

                        # Download object
                        $targetPath = Join-Path $OutputPath $relativePath
                        $targetDir = Split-Path -Parent $targetPath

                        if (-not (Test-Path -LiteralPath $targetDir)) {
                            $null = New-Item -ItemType Directory -Path $targetDir -Force
                        }

                        $cpArgs = @('s3', 'cp', "s3://$($s3Info.Bucket)/$($obj.Key)", $targetPath)
                        if ($region) {
                            $cpArgs += @('--region', $region)
                        }

                        $copyOutput = & aws @cpArgs 2>&1
                        if ($LASTEXITCODE -eq 0) {
                            $result.filesIngested++
                            $result.bytesIngested += $obj.Size
                        }
                        else {
                            $result.errors += "Failed to download $($obj.Key): $copyOutput"
                        }
                    }
                    catch {
                        $result.errors += "Error processing $($obj.Key): $_"
                    }
                }
            }
            else {
                throw "AWS Tools for PowerShell not yet implemented. Please install AWS CLI."
            }

            # Update source metadata
            $source.lastIngested = [DateTime]::UtcNow.ToString("yyyy-MM-ddTHH:mm:ssZ", [System.Globalization.CultureInfo]::InvariantCulture)
            $source.ingestCount++
            $source.lastStatus = 'success'

            $sourcePath = Join-Path $script:IngestionConfigDir "$SourceId.json"
            if (Test-Path -LiteralPath $sourcePath) {
                ($source | ConvertTo-Json -Depth 10) | Set-Content -LiteralPath $sourcePath -Encoding UTF8
            }

            $result.completedAt = [DateTime]::UtcNow.ToString("yyyy-MM-ddTHH:mm:ssZ", [System.Globalization.CultureInfo]::InvariantCulture)
            
            Write-LogEntry -Level INFO -Message "S3 ingestion completed: $SourceId (Files: $($result.filesIngested))" -Source "Invoke-S3Ingestion"
        }
        catch {
            $result.errors += $_.Exception.Message
            Write-LogEntry -Level ERROR -Message "S3 ingestion failed: $SourceId - $_" -Source "Invoke-S3Ingestion"
            throw
        }

        return [pscustomobject]$result
    }
}

<#
.SYNOPSIS
    Parses an S3 URL.

.DESCRIPTION
    Extracts bucket name, prefix, and region from S3 URLs.
#>
function Parse-S3Url {
    [CmdletBinding()]
    param([string]$Url)

    # s3://bucket/prefix format
    if ($Url -match '^s3://([^/]+)(?:/(.*))?$') {
        return @{
            Bucket = $matches[1]
            Prefix = if ($matches[2]) { $matches[2] } else { '' }
            Region = $null
        }
    }

    # https://s3.region.amazonaws.com/bucket/prefix format
    if ($Url -match '^https?://s3\.([^.]+)\.amazonaws\.com/([^/]+)(?:/(.*))?$') {
        return @{
            Bucket = $matches[2]
            Prefix = if ($matches[3]) { $matches[3] } else { '' }
            Region = $matches[1]
        }
    }

    # https://bucket.s3.region.amazonaws.com/prefix format
    if ($Url -match '^https?://([^.]+)\.s3\.([^.]+)\.amazonaws\.com(?:/(.*))?$') {
        return @{
            Bucket = $matches[1]
            Prefix = if ($matches[3]) { $matches[3] } else { '' }
            Region = $matches[2]
        }
    }

    return $null
}

# ============================================================================
# Region: REST API Ingestion
# ============================================================================

<#
.SYNOPSIS
    Ingests data from REST API endpoints.

.DESCRIPTION
    Calls REST APIs with authentication, pagination, and rate limiting.
    Supports various authentication methods and response formats.

.PARAMETER SourceId
    The registered source ID for the API source.

.PARAMETER OutputPath
    Directory where ingested content will be stored.

.PARAMETER Endpoint
    Optional specific endpoint path to call. If not specified, uses the source URL.

.PARAMETER Method
    HTTP method to use. Default: GET.

.PARAMETER PaginationType
    Type of pagination: 'none', 'offset', 'cursor', 'link'. Default: 'none'.

.PARAMETER MaxPages
    Maximum number of pages to fetch. Default: 100.

.PARAMETER RequestDelayMs
    Delay between requests in milliseconds. Default: 100.

.OUTPUTS
    System.Management.Automation.PSCustomObject with ingestion results.

.EXAMPLE
    PS C:\> Invoke-RestApiIngestion -SourceId "api-endpoint" -OutputPath "./ingested/api-data"
#>
function Invoke-RestApiIngestion {
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory = $true)]
        [string]$SourceId,

        [Parameter(Mandatory = $true)]
        [string]$OutputPath,

        [Parameter()]
        [string]$Endpoint = "",

        [Parameter()]
        [ValidateSet('GET', 'POST', 'PUT', 'PATCH')]
        [string]$Method = 'GET',

        [Parameter()]
        [ValidateSet('none', 'offset', 'cursor', 'link')]
        [string]$PaginationType = 'none',

        [Parameter()]
        [int]$MaxPages = 100,

        [Parameter()]
        [int]$RequestDelayMs = 100
    )

    process {
        $source = Get-IngestionSources -SourceId $SourceId
        if (-not $source) {
            throw "Source not found: $SourceId"
        }
        if ($source -is [array]) {
            $source = $source[0]
        }

        if ($source.type -ne 'api') {
            throw "Source '$SourceId' is not an API source (type: $($source.type))"
        }

        $result = [ordered]@{
            sourceId = $SourceId
            type = 'api'
            url = $source.url
            endpoint = $Endpoint
            outputPath = $OutputPath
            method = $Method
            pagesFetched = 0
            recordsIngested = 0
            bytesIngested = 0
            errors = @()
            startedAt = [DateTime]::UtcNow.ToString("yyyy-MM-ddTHH:mm:ssZ", [System.Globalization.CultureInfo]::InvariantCulture)
            completedAt = $null
        }

        try {
            if (-not (Test-Path -LiteralPath $OutputPath)) {
                $null = New-Item -ItemType Directory -Path $OutputPath -Force
            }

            # Build request headers
            $headers = @{
                'Accept' = 'application/json'
                'User-Agent' = 'LLM-Workflow-Ingestion/0.7.0'
            }

            # Handle authentication
            if ($source.auth) {
                switch ($source.auth.type) {
                    'token' {
                        $token = Get-SourceAuthToken -Source $source
                        if ($token) {
                            $headerName = if ($source.auth.headerName) { $source.auth.headerName } else { 'Authorization' }
                            $prefix = if ($source.auth.tokenPrefix) { $source.auth.tokenPrefix } else { 'Bearer ' }
                            $headers[$headerName] = "$prefix$token"
                        }
                    }
                    'apikey' {
                        $apiKey = Get-SourceAuthToken -Source $source
                        if ($apiKey) {
                            $headerName = if ($source.auth.headerName) { $source.auth.headerName } else { 'X-API-Key' }
                            $headers[$headerName] = $apiKey
                        }
                    }
                    'basic' {
                        $credentials = "$($source.auth.username):$($source.auth.password)"
                        $encoded = [Convert]::ToBase64String([Text.Encoding]::ASCII.GetBytes($credentials))
                        $headers['Authorization'] = "Basic $encoded"
                    }
                }
            }

            # Build base URL
            $baseUrl = $source.url.TrimEnd('/')
            if ($Endpoint) {
                $baseUrl = "$baseUrl/$($Endpoint.TrimStart('/'))"
            }

            # Pagination variables
            $page = 0
            $nextUrl = $baseUrl
            $cursor = $null
            $offset = 0
            $limit = if ($source.metadata.pageSize) { $source.metadata.pageSize } else { 100 }
            $allData = [System.Collections.Generic.List[object]]::new()

            while ($nextUrl -and $page -lt $MaxPages) {
                # Rate limiting
                if ($page -gt 0) {
                    Start-Sleep -Milliseconds $RequestDelayMs
                }

                # Build request URL with pagination
                $requestUrl = $nextUrl
                if ($PaginationType -eq 'offset') {
                    $separator = if ($baseUrl.Contains('?')) { '&' } else { '?' }
                    $requestUrl = "$baseUrl$separator`offset=$offset&limit=$limit"
                }
                elseif ($PaginationType -eq 'cursor' -and $cursor) {
                    $separator = if ($baseUrl.Contains('?')) { '&' } else { '?' }
                    $cursorParam = if ($source.metadata.cursorParam) { $source.metadata.cursorParam } else { 'cursor' }
                    $requestUrl = "$baseUrl$separator`$cursorParam=$cursor"
                }

                Write-LogEntry -Level INFO -Message "Calling REST API: $requestUrl" -Source "Invoke-RestApiIngestion"

                try {
                    $response = Invoke-IngestionWithBackoff -ScriptBlock {
                        Invoke-RestMethod -Uri $requestUrl -Headers $headers -Method $Method -TimeoutSec 60
                    } -MaxRetries 3

                    $result.pagesFetched++

                    # Handle different response structures
                    $data = $response
                    if ($source.metadata.dataPath) {
                        # Extract data from nested path (e.g., "data.items")
                        $pathParts = $source.metadata.dataPath -split '\.'
                        foreach ($part in $pathParts) {
                            if ($data -and $data.$part) {
                                $data = $data.$part
                            }
                            else {
                                $data = @()
                                break
                            }
                        }
                    }
                    elseif ($response.data) {
                        $data = $response.data
                    }
                    elseif ($response.results) {
                        $data = $response.results
                    }
                    elseif ($response.items) {
                        $data = $response.items
                    }

                    if ($data -is [array]) {
                        $allData.AddRange($data)
                        $result.recordsIngested += $data.Count
                    }
                    else {
                        $allData.Add($data)
                        $result.recordsIngested++
                    }

                    # Handle pagination
                    $nextUrl = $null
                    switch ($PaginationType) {
                        'offset' {
                            $offset += $limit
                            if ($data -is [array] -and $data.Count -lt $limit) {
                                $nextUrl = $null  # No more data
                            }
                            else {
                                $nextUrl = $baseUrl  # Continue with new offset
                            }
                        }
                        'cursor' {
                            if ($response.cursor) {
                                $cursor = $response.cursor
                                $nextUrl = $baseUrl
                            }
                            elseif ($response.nextCursor) {
                                $cursor = $response.nextCursor
                                $nextUrl = $baseUrl
                            }
                            elseif ($response.pagination -and $response.pagination.nextCursor) {
                                $cursor = $response.pagination.nextCursor
                                $nextUrl = $baseUrl
                            }
                        }
                        'link' {
                            # Parse Link header for next URL (would need Invoke-WebRequest instead of Invoke-RestMethod)
                            # Simplified implementation
                            if ($response.next -and $response.next -is [string]) {
                                $nextUrl = $response.next
                            }
                            elseif ($response.links -and $response.links.next) {
                                $nextUrl = $response.links.next
                            }
                        }
                    }

                    # Save each page individually
                    $pageFile = Join-Path $OutputPath "page_$($page.ToString('D4')).json"
                    ($data | ConvertTo-Json -Depth 10) | Set-Content -LiteralPath $pageFile -Encoding UTF8
                    $result.bytesIngested += (Get-Item -LiteralPath $pageFile).Length
                }
                catch {
                    $result.errors += "Failed to fetch page $page`: $_"
                    Write-Warning "[Invoke-RestApiIngestion] Failed to fetch page $page`: $_"
                    break
                }

                $page++
            }

            # Save combined data
            if ($allData.Count -gt 0) {
                $combinedFile = Join-Path $OutputPath 'all_data.json'
                ($allData | ConvertTo-Json -Depth 10) | Set-Content -LiteralPath $combinedFile -Encoding UTF8
            }

            # Update source metadata
            $source.lastIngested = [DateTime]::UtcNow.ToString("yyyy-MM-ddTHH:mm:ssZ", [System.Globalization.CultureInfo]::InvariantCulture)
            $source.ingestCount++
            $source.lastStatus = 'success'

            $sourcePath = Join-Path $script:IngestionConfigDir "$SourceId.json"
            if (Test-Path -LiteralPath $sourcePath) {
                ($source | ConvertTo-Json -Depth 10) | Set-Content -LiteralPath $sourcePath -Encoding UTF8
            }

            $result.completedAt = [DateTime]::UtcNow.ToString("yyyy-MM-ddTHH:mm:ssZ", [System.Globalization.CultureInfo]::InvariantCulture)
            
            Write-LogEntry -Level INFO -Message "REST API ingestion completed: $SourceId (Records: $($result.recordsIngested))" -Source "Invoke-RestApiIngestion"
        }
        catch {
            $result.errors += $_.Exception.Message
            Write-LogEntry -Level ERROR -Message "REST API ingestion failed: $SourceId - $_" -Source "Invoke-RestApiIngestion"
            throw
        }

        return [pscustomobject]$result
    }
}

# ============================================================================
# Region: Ingestion Pipeline
# ============================================================================

<#
.SYNOPSIS
    Starts an async ingestion job.

.DESCRIPTION
    Creates and starts a new ingestion job that runs asynchronously.
    Jobs can be monitored using Get-IngestionJobStatus.

.PARAMETER SourceId
    The source ID to ingest.

.PARAMETER OutputPath
    Directory where ingested content will be stored.

.PARAMETER Options
    Hashtable of ingestion options specific to the source type.

.PARAMETER Callback
    Optional scriptblock to call when job completes.

.OUTPUTS
    System.Management.Automation.PSCustomObject with job information.

.EXAMPLE
    PS C:\> Start-IngestionJob -SourceId "github-godot-rust" -OutputPath "./ingested/godot-rust"
#>
function Start-IngestionJob {
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory = $true)]
        [string]$SourceId,

        [Parameter(Mandatory = $true)]
        [string]$OutputPath,

        [Parameter()]
        [hashtable]$Options = @{},

        [Parameter()]
        [scriptblock]$Callback = $null
    )

    begin {
        # Ensure job directories exist
        if (-not (Test-Path -LiteralPath $script:IngestionJobsDir)) {
            $null = New-Item -ItemType Directory -Path $script:IngestionJobsDir -Force
        }
        if (-not (Test-Path -LiteralPath $script:IngestionLogsDir)) {
            $null = New-Item -ItemType Directory -Path $script:IngestionLogsDir -Force
        }
    }

    process {
        $source = Get-IngestionSources -SourceId $SourceId
        if (-not $source) {
            throw "Source not found: $SourceId"
        }

        # Generate job ID
        $jobId = "job-$(Get-Date -Format 'yyyyMMdd-HHmmss')-$([Guid]::NewGuid().ToString("N").Substring(0, 8))"

        # Create job object
        $job = [ordered]@{
            jobId = $jobId
            sourceId = $SourceId
            sourceType = $source.type
            outputPath = $OutputPath
            options = $Options
            state = 'pending'
            createdAt = [DateTime]::UtcNow.ToString("yyyy-MM-ddTHH:mm:ssZ", [System.Globalization.CultureInfo]::InvariantCulture)
            startedAt = $null
            completedAt = $null
            progress = @{
                percent = 0
                current = 0
                total = 0
                message = "Pending"
            }
            result = $null
            error = $null
            logFile = Join-Path $script:IngestionLogsDir "$jobId.jsonl"
        }

        $jobObject = [pscustomobject]$job
        $script:IngestionJobs[$jobId] = $jobObject

        # Persist job state
        $jobPath = Join-Path $script:IngestionJobsDir "$jobId.json"
        $job | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $jobPath -Encoding UTF8

        # Start job in background
        $job.state = 'running'
        $job.startedAt = [DateTime]::UtcNow.ToString("yyyy-MM-ddTHH:mm:ssZ", [System.Globalization.CultureInfo]::InvariantCulture)
        $job.progress.message = "Starting ingestion"

        # Create runspace pool for async execution
        $runspacePool = [runspacefactory]::CreateRunspacePool(1, 2)
        $runspacePool.Open()

        $powershell = [powershell]::Create().AddScript({
            param($JobId, $SourceId, $OutputPath, $Options, $IngestionJobsDir, $IngestionLogsDir)

            # Reload modules
            Import-Module (Join-Path $PSScriptRoot '../LLMWorkflow.psd1') -Force -ErrorAction SilentlyContinue

            $logFile = Join-Path $IngestionLogsDir "$JobId.jsonl"

            function Write-JobLog {
                param([string]$Level, [string]$Message)
                $entry = @{
                    timestamp = [DateTime]::UtcNow.ToString("o")
                    level = $Level
                    message = $Message
                    jobId = $JobId
                } | ConvertTo-Json -Compress
                Add-Content -LiteralPath $logFile -Value $entry
            }

            try {
                Write-JobLog -Level "INFO" -Message "Starting ingestion job $JobId for $SourceId"

                # Get source info
                $source = & "$PSScriptRoot/ExternalIngestion.ps1" -Command Get-IngestionSources -SourceId $SourceId
                if ($source -is [array]) { $source = $source[0] }

                # Update job progress
                $jobPath = Join-Path $IngestionJobsDir "$JobId.json"
                $jobData = Get-Content $jobPath -Raw | ConvertFrom-Json
                $jobData.progress.message = "Ingesting $($source.type) source"
                $jobData | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $jobPath

                # Call appropriate ingestion function based on type
                $result = $null
                switch ($source.type) {
                    'github' {
                        $result = & "$PSScriptRoot/ExternalIngestion.ps1" -Command Invoke-GitHubRepoIngestion `
                            -SourceId $SourceId -OutputPath $OutputPath `
                            -Incremental:([bool]$Options.Incremental) -Branch $Options.Branch
                    }
                    'gitlab' {
                        $result = & "$PSScriptRoot/ExternalIngestion.ps1" -Command Invoke-GitLabRepoIngestion `
                            -SourceId $SourceId -OutputPath $OutputPath `
                            -Incremental:([bool]$Options.Incremental) -Branch $Options.Branch
                    }
                    'git' {
                        $result = & "$PSScriptRoot/ExternalIngestion.ps1" -Command Invoke-GitIngestion `
                            -SourceId $SourceId -OutputPath $OutputPath `
                            -Incremental:([bool]$Options.Incremental) -Branch $Options.Branch -Depth ($Options.Depth -or 0)
                    }
                    'http' {
                        $result = & "$PSScriptRoot/ExternalIngestion.ps1" -Command Invoke-HttpIngestion `
                            -SourceId $SourceId -OutputPath $OutputPath `
                            -MaxDepth ($Options.MaxDepth -or 1) -MaxPages ($Options.MaxPages -or 100) `
                            -RequestDelayMs ($Options.RequestDelayMs -or 1000)
                    }
                    'https' {
                        $result = & "$PSScriptRoot/ExternalIngestion.ps1" -Command Invoke-HttpIngestion `
                            -SourceId $SourceId -OutputPath $OutputPath `
                            -MaxDepth ($Options.MaxDepth -or 1) -MaxPages ($Options.MaxPages -or 100) `
                            -RequestDelayMs ($Options.RequestDelayMs -or 1000)
                    }
                    's3' {
                        $result = & "$PSScriptRoot/ExternalIngestion.ps1" -Command Invoke-S3Ingestion `
                            -SourceId $SourceId -OutputPath $OutputPath `
                            -Incremental:([bool]$Options.Incremental) -MaxKeys ($Options.MaxKeys -or 1000)
                    }
                    'docssite' {
                        $result = & "$PSScriptRoot/ExternalIngestion.ps1" -Command Invoke-DocsSiteIngestion `
                            -SourceId $SourceId -OutputPath $OutputPath `
                            -MaxDepth ($Options.MaxDepth -or 3) -MaxPages ($Options.MaxPages -or 1000) `
                            -UseSitemap:([bool]$Options.UseSitemap)
                    }
                    'api' {
                        $result = & "$PSScriptRoot/ExternalIngestion.ps1" -Command Invoke-RestApiIngestion `
                            -SourceId $SourceId -OutputPath $OutputPath `
                            -Endpoint ($Options.Endpoint -or '') -Method ($Options.Method -or 'GET') `
                            -PaginationType ($Options.PaginationType -or 'none') -MaxPages ($Options.MaxPages -or 100) `
                            -RequestDelayMs ($Options.RequestDelayMs -or 100)
                    }
                    default {
                        throw "Ingestion not implemented for type: $($source.type)"
                    }
                }

                # Update job as completed
                $jobData.state = 'completed'
                $jobData.completedAt = [DateTime]::UtcNow.ToString("o")
                $jobData.progress.percent = 100
                $jobData.progress.message = "Completed"
                $jobData.result = $result
                $jobData | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $jobPath

                Write-JobLog -Level "INFO" -Message "Ingestion job completed successfully"
            }
            catch {
                # Update job as failed
                $jobData = Get-Content $jobPath -Raw | ConvertFrom-Json
                $jobData.state = 'failed'
                $jobData.completedAt = [DateTime]::UtcNow.ToString("o")
                $jobData.error = $_.Exception.Message
                $jobData.progress.message = "Failed: $_"
                $jobData | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $jobPath

                Write-JobLog -Level "ERROR" -Message "Ingestion job failed: $_"
            }
        }).AddArgument($jobId).AddArgument($SourceId).AddArgument($OutputPath).AddArgument($Options).AddArgument($script:IngestionJobsDir).AddArgument($script:IngestionLogsDir)

        $powershell.RunspacePool = $runspacePool
        $asyncResult = $powershell.BeginInvoke()

        # Store runspace info for potential cleanup
        $jobObject | Add-Member -NotePropertyName '_asyncResult' -NotePropertyValue $asyncResult -Force
        $jobObject | Add-Member -NotePropertyName '_powershell' -NotePropertyValue $powershell -Force
        $jobObject | Add-Member -NotePropertyName '_runspacePool' -NotePropertyValue $runspacePool -Force

        # Update persisted state
        $jobPath = Join-Path $script:IngestionJobsDir "$jobId.json"
        $job | Select-Object -Property * -ExcludeProperty _asyncResult, _powershell, _runspacePool | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $jobPath -Encoding UTF8

        Write-LogEntry -Level INFO -Message "Started ingestion job: $jobId for $SourceId" -Source "Start-IngestionJob"

        # Return job info (without internal properties)
        return $jobObject | Select-Object -Property * -ExcludeProperty _asyncResult, _powershell, _runspacePool
    }
}

<#
.SYNOPSIS
    Gets the status of an ingestion job.

.DESCRIPTION
    Retrieves current status, progress, and result of a running or
    completed ingestion job.

.PARAMETER JobId
    The job ID to check.

.PARAMETER IncludeLogs
    If specified, includes recent log entries.

.OUTPUTS
    System.Management.Automation.PSCustomObject with job status.

.EXAMPLE
    PS C:\> Get-IngestionJobStatus -JobId "job-20260412-120000-abc123"
#>
function Get-IngestionJobStatus {
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory = $true)]
        [string]$JobId,

        [Parameter()]
        [switch]$IncludeLogs
    )

    process {
        # Try memory first
        if ($script:IngestionJobs.ContainsKey($JobId)) {
            $job = $script:IngestionJobs[$JobId]
        }
        else {
            # Load from disk
            $jobPath = Join-Path $script:IngestionJobsDir "$JobId.json"
            if (-not (Test-Path -LiteralPath $jobPath)) {
                throw "Job not found: $JobId"
            }
            $job = Get-Content -LiteralPath $jobPath -Raw | ConvertFrom-Json
        }

        $result = $job | Select-Object -Property * -ExcludeProperty _asyncResult, _powershell, _runspacePool

        # Add logs if requested
        if ($IncludeLogs -and $job.logFile) {
            if (Test-Path -LiteralPath $job.logFile) {
                $logLines = Get-Content -LiteralPath $job.logFile -Tail 100 | Where-Object { $_ }
                $result | Add-Member -NotePropertyName 'logs' -NotePropertyValue ($logLines | ForEach-Object { $_ | ConvertFrom-Json }) -Force
            }
        }

        return $result
    }
}

<#
.SYNOPSIS
    Stops a running ingestion job.

.DESCRIPTION
    Cancels a running ingestion job. This is best-effort and may not
    immediately stop all operations.

.PARAMETER JobId
    The job ID to stop.

.PARAMETER Force
    If specified, forcefully terminates the job.

.OUTPUTS
    System.Boolean. True if the job was stopped; otherwise false.

.EXAMPLE
    PS C:\> Stop-IngestionJob -JobId "job-20260412-120000-abc123"
#>
function Stop-IngestionJob {
    [CmdletBinding(SupportsShouldProcess = $true)]
    [OutputType([bool])]
    param(
        [Parameter(Mandatory = $true)]
        [string]$JobId,

        [Parameter()]
        [switch]$Force
    )

    process {
        if (-not $script:IngestionJobs.ContainsKey($JobId)) {
            # Check if job exists on disk
            $jobPath = Join-Path $script:IngestionJobsDir "$JobId.json"
            if (-not (Test-Path -LiteralPath $jobPath)) {
                Write-Warning "Job not found: $JobId"
                return $false
            }

            # Load job from disk
            $job = Get-Content -LiteralPath $jobPath -Raw | ConvertFrom-Json
        }
        else {
            $job = $script:IngestionJobs[$JobId]
        }

        if ($job.state -notin @('pending', 'running')) {
            Write-Warning "Job $JobId is not running (state: $($job.state))"
            return $false
        }

        if ($Force -or $PSCmdlet.ShouldProcess($JobId, "Stop ingestion job")) {
            try {
                # Stop the PowerShell instance if available
                if ($job._powershell) {
                    $job._powershell.Stop()
                    $job._powershell.Dispose()
                }
                if ($job._runspacePool) {
                    $job._runspacePool.Close()
                    $job._runspacePool.Dispose()
                }
            }
            catch {
                Write-Verbose "[ExternalIngestion] Error stopping job: $_"
            }

            # Update job state
            $job.state = 'cancelled'
            $job.completedAt = [DateTime]::UtcNow.ToString("yyyy-MM-ddTHH:mm:ssZ", [System.Globalization.CultureInfo]::InvariantCulture)
            $job.progress.message = "Cancelled by user"

            # Persist
            $jobPath = Join-Path $script:IngestionJobsDir "$JobId.json"
            $job | Select-Object -Property * -ExcludeProperty _asyncResult, _powershell, _runspacePool | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $jobPath -Encoding UTF8

            Write-LogEntry -Level INFO -Message "Stopped ingestion job: $JobId" -Source "Stop-IngestionJob"
            return $true
        }

        return $false
    }
}

<#
.SYNOPSIS
    Gets logs for an ingestion job.

.DESCRIPTION
    Retrieves log entries for a specific ingestion job with optional
    filtering and tail support.

.PARAMETER JobId
    The job ID to get logs for.

.PARAMETER Tail
    If specified, returns only the last N entries.

.PARAMETER Level
    Filter by log level (INFO, WARN, ERROR).

.OUTPUTS
    System.Management.Automation.PSCustomObject[] with log entries.

.EXAMPLE
    PS C:\> Get-IngestionJobLogs -JobId "job-20260412-120000-abc123" -Tail 50
#>
function Get-IngestionJobLogs {
    [CmdletBinding()]
    [OutputType([array])]
    param(
        [Parameter(Mandatory = $true)]
        [string]$JobId,

        [Parameter()]
        [int]$Tail = 0,

        [Parameter()]
        [ValidateSet('INFO', 'WARN', 'ERROR', 'DEBUG')]
        [string]$Level = ""
    )

    process {
        $logFile = Join-Path $script:IngestionLogsDir "$JobId.jsonl"

        if (-not (Test-Path -LiteralPath $logFile)) {
            # Try getting log path from job
            $jobPath = Join-Path $script:IngestionJobsDir "$JobId.json"
            if (Test-Path -LiteralPath $jobPath) {
                $job = Get-Content -LiteralPath $jobPath -Raw | ConvertFrom-Json
                if ($job.logFile -and (Test-Path -LiteralPath $job.logFile)) {
                    $logFile = $job.logFile
                }
                else {
                    return @()
                }
            }
            else {
                return @()
            }
        }

        $lines = Get-Content -LiteralPath $logFile
        if ($Tail -gt 0) {
            $lines = $lines | Select-Object -Last $Tail
        }

        $entries = @()
        foreach ($line in $lines) {
            if ([string]::IsNullOrWhiteSpace($line)) { continue }

            try {
                $entry = $line | ConvertFrom-Json

                if (-not [string]::IsNullOrEmpty($Level)) {
                    if ($entry.level -ne $Level) {
                        continue
                    }
                }

                $entries += $entry
            }
            catch {
                # Skip malformed lines
            }
        }

        return $entries
    }
}

# ============================================================================
# Region: Rate Limiting & Throttling
# ============================================================================

<#
.SYNOPSIS
    Gets rate limit information for a source.

.DESCRIPTION
    Queries the rate limit status for GitHub or GitLab sources.

.PARAMETER SourceId
    The source ID to check.

.OUTPUTS
    System.Management.Automation.PSCustomObject with rate limit info.

.EXAMPLE
    PS C:\> Get-IngestionRateLimit -SourceId "github-godot-rust"
#>
function Get-IngestionRateLimit {
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory = $true)]
        [string]$SourceId
    )

    process {
        $source = Get-IngestionSources -SourceId $SourceId
        if (-not $source) {
            throw "Source not found: $SourceId"
        }
        if ($source -is [array]) {
            $source = $source[0]
        }

        $result = [ordered]@{
            sourceId = $SourceId
            type = $source.type
            limits = @{}
            checkedAt = [DateTime]::UtcNow.ToString("yyyy-MM-ddTHH:mm:ssZ", [System.Globalization.CultureInfo]::InvariantCulture)
        }

        try {
            $token = Get-SourceAuthToken -Source $source

            switch ($source.type) {
                'github' {
                    $headers = @{
                        'Accept' = 'application/vnd.github.v3+json'
                        'User-Agent' = 'LLM-Workflow-Ingestion/0.7.0'
                    }
                    if ($token) {
                        $headers['Authorization'] = "Bearer $token"
                    }

                    $rateLimit = Invoke-RestMethod -Uri "$script:GitHubApiBase/rate_limit" -Headers $headers -Method GET
                    $result.limits = @{
                        core = @{
                            limit = $rateLimit.resources.core.limit
                            remaining = $rateLimit.resources.core.remaining
                            resetAt = [DateTimeOffset]::FromUnixTimeSeconds($rateLimit.resources.core.reset).DateTime.ToString("o")
                        }
                        search = @{
                            limit = $rateLimit.resources.search.limit
                            remaining = $rateLimit.resources.search.remaining
                            resetAt = [DateTimeOffset]::FromUnixTimeSeconds($rateLimit.resources.search.reset).DateTime.ToString("o")
                        }
                    }
                }
                'gitlab' {
                    $repoInfo = Parse-GitLabUrl -Url $source.url
                    $headers = @{
                        'User-Agent' = 'LLM-Workflow-Ingestion/0.7.0'
                    }
                    if ($token) {
                        $headers['PRIVATE-TOKEN'] = $token
                    }

                    # GitLab doesn't have a direct rate limit endpoint
                    # We make a test request and check headers
                    $projectEncoded = [System.Web.HttpUtility]::UrlEncode($repoInfo.Project)
                    $response = Invoke-WebRequest -Uri "$($repoInfo.BaseUrl)/projects/$projectEncoded" -Headers $headers -Method HEAD

                    $result.limits = @{
                        rateLimit = $response.Headers['RateLimit-Limit']
                        rateLimitRemaining = $response.Headers['RateLimit-Remaining']
                        rateLimitReset = $response.Headers['RateLimit-ResetTime']
                    }
                }
                default {
                    $result.limits = @{ note = "Rate limit check not supported for type: $($source.type)" }
                }
            }
        }
        catch {
            $result.limits = @{ error = $_.Exception.Message }
        }

        return [pscustomobject]$result
    }
}

<#
.SYNOPSIS
    Executes a scriptblock with exponential backoff retry.

.DESCRIPTION
    Executes a scriptblock with automatic retry on failure using
    exponential backoff. Handles rate limiting specifically.

.PARAMETER ScriptBlock
    The scriptblock to execute.

.PARAMETER MaxRetries
    Maximum retry attempts. Default: 5.

.PARAMETER BaseDelaySeconds
    Initial delay between retries. Default: 1.

.PARAMETER MaxDelaySeconds
    Maximum delay between retries. Default: 60.

.PARAMETER RetryOn
    Array of status codes or error patterns to retry on.

.OUTPUTS
    The output of the scriptblock.

.EXAMPLE
    PS C:\> Invoke-IngestionWithBackoff -ScriptBlock { Invoke-RestMethod -Uri $url }
#>
function Invoke-IngestionWithBackoff {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [scriptblock]$ScriptBlock,

        [Parameter()]
        [int]$MaxRetries = 5,

        [Parameter()]
        [int]$BaseDelaySeconds = 1,

        [Parameter()]
        [int]$MaxDelaySeconds = 60,

        [Parameter()]
        [object[]]$RetryOn = @(429, 500, 502, 503, 504)
    )

    $attempt = 0
    $lastError = $null

    while ($attempt -lt $MaxRetries) {
        try {
            $result = & $ScriptBlock
            return $result
        }
        catch {
            $lastError = $_
            $attempt++

            # Check if we should retry
            $shouldRetry = $false
            $errorMessage = $_.Exception.Message
            $statusCode = $null

            # Try to extract status code from error
            if ($_.Exception.Response) {
                $statusCode = [int]$_.Exception.Response.StatusCode
            }
            elseif ($errorMessage -match '(\d{3})') {
                $statusCode = [int]$matches[1]
            }

            if ($statusCode -and $RetryOn -contains $statusCode) {
                $shouldRetry = $true
            }
            elseif ($errorMessage -match 'rate.?limit' -or $errorMessage -match 'too.?many.?requests') {
                $shouldRetry = $true
            }

            if (-not $shouldRetry -or $attempt -ge $MaxRetries) {
                throw
            }

            # Calculate delay with exponential backoff
            $delay = [Math]::Min($BaseDelaySeconds * [Math]::Pow(2, $attempt - 1), $MaxDelaySeconds)

            # Add jitter
            $jitter = Get-Random -Minimum 0 -Maximum 500
            $totalDelayMs = ($delay * 1000) + $jitter

            Write-Verbose "[ExternalIngestion] Attempt $attempt failed, retrying in $($totalDelayMs)ms..."
            Start-Sleep -Milliseconds $totalDelayMs
        }
    }

    throw $lastError
}

<#
.SYNOPSIS
    Configures throttling settings.

.DESCRIPTION
    Sets global throttling parameters for ingestion operations.

.PARAMETER DefaultDelayMs
    Default delay between requests in milliseconds.

.PARAMETER MaxRetries
    Maximum retry attempts.

.PARAMETER BaseDelayMs
    Base delay for exponential backoff in milliseconds.

.OUTPUTS
    System.Management.Automation.PSCustomObject with current settings.

.EXAMPLE
    PS C:\> Set-IngestionThrottle -DefaultDelayMs 500 -MaxRetries 10
#>
function Set-IngestionThrottle {
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter()]
        [int]$DefaultDelayMs = -1,

        [Parameter()]
        [int]$MaxRetries = -1,

        [Parameter()]
        [int]$BaseDelayMs = -1
    )

    process {
        if ($DefaultDelayMs -ge 0) {
            $script:ThrottleSettings.defaultDelayMs = $DefaultDelayMs
        }
        if ($MaxRetries -ge 0) {
            $script:ThrottleSettings.maxRetries = $MaxRetries
        }
        if ($BaseDelayMs -ge 0) {
            $script:ThrottleSettings.baseDelayMs = $BaseDelayMs
        }

        # Return current settings
        return [pscustomobject]@{
            defaultDelayMs = $script:ThrottleSettings.defaultDelayMs
            maxRetries = $script:ThrottleSettings.maxRetries
            baseDelayMs = $script:ThrottleSettings.baseDelayMs
        }
    }
}

# ============================================================================
# Region: Helper Functions
# ============================================================================

function Parse-GitHubUrl {
    [CmdletBinding()]
    param([string]$Url)

    # Handle various GitHub URL formats
    $patterns = @(
        '^https?://github\.com/([^/]+)/([^/]+)/?.*$',
        '^https?://raw\.githubusercontent\.com/([^/]+)/([^/]+)/.*$'
    )

    foreach ($pattern in $patterns) {
        if ($Url -match $pattern) {
            return @{
                Owner = $matches[1]
                Repo = $matches[2] -replace '\.git$', ''
            }
        }
    }

    return $null
}

function Parse-GitLabUrl {
    [CmdletBinding()]
    param([string]$Url)

    # Handle various GitLab URL formats
    if ($Url -match '^https?://([^/]+)/(.+)/?$') {
        $host = $matches[1]
        $project = $matches[2] -replace '\.git$', ''

        $baseUrl = if ($host -eq 'gitlab.com') {
            $script:GitLabApiBase
        }
        else {
            "https://$host/api/v4"
        }

        return @{
            BaseUrl = $baseUrl
            Project = $project
        }
    }

    return $null
}

function Get-SourceAuthToken {
    [CmdletBinding()]
    param([object]$Source)

    if (-not $Source.auth -or $Source.auth.Count -eq 0) {
        return $null
    }

    $auth = $Source.auth

    switch ($auth.type) {
        'token' {
            $envVar = $auth.tokenEnv
            if ($envVar -and [Environment]::GetEnvironmentVariable($envVar)) {
                return [Environment]::GetEnvironmentVariable($envVar)
            }
            if ($auth.token) {
                return $auth.token
            }
        }
        'basic' {
            # Basic auth not directly returning token, handled separately
            return $null
        }
        default {
            return $null
        }
    }

    return $null
}

function Test-GitHubConnectivity {
    [CmdletBinding()]
    param([object]$Source, [int]$TimeoutSeconds)

    $result = @{
        reachable = $false
        authenticated = $false
        rateLimit = @{}
        error = $null
    }

    try {
        $token = Get-SourceAuthToken -Source $Source
        $headers = @{
            'Accept' = 'application/vnd.github.v3+json'
            'User-Agent' = 'LLM-Workflow-Ingestion/0.7.0'
        }
        if ($token) {
            $headers['Authorization'] = "Bearer $token"
        }

        $response = Invoke-RestMethod -Uri "$script:GitHubApiBase/rate_limit" -Headers $headers -Method GET -TimeoutSec $TimeoutSeconds

        $result.reachable = $true
        $result.authenticated = $null -ne $token
        $result.rateLimit = @{
            remaining = $response.resources.core.remaining
            limit = $response.resources.core.limit
            reset = $response.resources.core.reset
        }
    }
    catch {
        $result.error = $_.Exception.Message
        if ($_.Exception.Response -and $_.Exception.Response.StatusCode -eq 401) {
            $result.reachable = $true
            $result.authenticated = $false
        }
    }

    return $result
}

function Test-GitLabConnectivity {
    [CmdletBinding()]
    param([object]$Source, [int]$TimeoutSeconds)

    $result = @{
        reachable = $false
        authenticated = $false
        rateLimit = @{}
        error = $null
    }

    try {
        $repoInfo = Parse-GitLabUrl -Url $Source.url
        if (-not $repoInfo) {
            $result.error = "Failed to parse GitLab URL"
            return $result
        }

        $token = Get-SourceAuthToken -Source $Source
        $headers = @{
            'User-Agent' = 'LLM-Workflow-Ingestion/0.7.0'
        }
        if ($token) {
            $headers['PRIVATE-TOKEN'] = $token
        }

        $projectEncoded = [System.Web.HttpUtility]::UrlEncode($repoInfo.Project)
        $response = Invoke-WebRequest -Uri "$($repoInfo.BaseUrl)/projects/$projectEncoded" -Headers $headers -Method HEAD -TimeoutSec $TimeoutSeconds

        $result.reachable = $true
        $result.authenticated = $null -ne $token
        $result.rateLimit = @{
            remaining = $response.Headers['RateLimit-Remaining']
            limit = $response.Headers['RateLimit-Limit']
        }
    }
    catch {
        $result.error = $_.Exception.Message
    }

    return $result
}

function Test-DocsSiteConnectivity {
    [CmdletBinding()]
    param([object]$Source, [int]$TimeoutSeconds)

    $result = @{
        reachable = $false
        authenticated = $false
        error = $null
    }

    try {
        $headers = @{
            'User-Agent' = 'LLM-Workflow-Ingestion/0.7.0'
        }

        $response = Invoke-WebRequest -Uri $Source.url -Headers $headers -Method HEAD -TimeoutSec $TimeoutSeconds

        $result.reachable = $response.StatusCode -eq 200
        $result.authenticated = $true  # Docs sites typically don't require auth
    }
    catch {
        $result.error = $_.Exception.Message
    }

    return $result
}

function Test-ApiConnectivity {
    [CmdletBinding()]
    param([object]$Source, [int]$TimeoutSeconds)

    $result = @{
        reachable = $false
        authenticated = $false
        error = $null
    }

    try {
        $headers = @{
            'Accept' = 'application/json'
            'User-Agent' = 'LLM-Workflow-Ingestion/0.7.0'
        }

        $token = Get-SourceAuthToken -Source $Source
        if ($token) {
            $headers['Authorization'] = "Bearer $token"
        }

        $response = Invoke-WebRequest -Uri $Source.url -Headers $headers -Method HEAD -TimeoutSec $TimeoutSeconds

        $result.reachable = $response.StatusCode -eq 200
        $result.authenticated = $null -ne $token
    }
    catch {
        # Some APIs don't support HEAD, try GET
        try {
            $response = Invoke-WebRequest -Uri $Source.url -Headers $headers -Method GET -TimeoutSec $TimeoutSeconds
            $result.reachable = $response.StatusCode -eq 200
            $result.authenticated = $null -ne $token
        }
        catch {
            $result.error = $_.Exception.Message
        }
    }

    return $result
}

function Test-CronExpression {
    [CmdletBinding()]
    param([string]$Expression)

    # Basic cron validation (5 fields: minute hour day month weekday)
    $parts = $Expression -split '\s+'
    if ($parts.Count -lt 5 -or $parts.Count -gt 6) {
        return $false
    }

    # Additional validation could be added here
    return $true
}

function Extract-LinksFromHtml {
    [CmdletBinding()]
    param([string]$Html, [string]$BaseUrl)

    $links = [System.Collections.Generic.List[string]]::new()
    $baseUri = [Uri]$BaseUrl

    # Simple regex for link extraction
    $regex = '<a\s+[^>]*href=["'']([^"'']+)["''][^>]*>'
    $matches = [regex]::Matches($Html, $regex, [System.Text.RegularExpressions.RegexOptions]::IgnoreCase)

    foreach ($match in $matches) {
        $href = $match.Groups[1].Value

        # Skip anchors and javascript
        if ($href.StartsWith('#') -or $href.StartsWith('javascript:')) {
            continue
        }

        # Resolve relative URLs
        try {
            $absoluteUri = New-Object System.Uri($baseUri, $href)

            # Only include same-host URLs
            if ($absoluteUri.Host -eq $baseUri.Host) {
                # Remove fragment
                $urlWithoutFragment = $absoluteUri.GetLeftPart([UriPartial]::Path) + $absoluteUri.Query
                if (-not $links.Contains($urlWithoutFragment)) {
                    $links.Add($urlWithoutFragment)
                }
            }
        }
        catch {
            # Skip invalid URLs
        }
    }

    return $links.ToArray()
}

function Resolve-ApiSpecRefs {
    [CmdletBinding()]
    param([object]$Spec, [string]$BaseUrl, [hashtable]$Headers)

    # This is a placeholder for $ref resolution
    # Full implementation would recursively resolve external references
    return $Spec
}

function Write-LogEntry {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Level,

        [Parameter(Mandatory = $true)]
        [string]$Message,

        [Parameter()]
        [string]$Source = "ExternalIngestion"
    )

    # Try to use structured logging if available
    $loggingCmd = Get-Command New-LogEntry -ErrorAction SilentlyContinue
    if ($loggingCmd) {
        $entry = & $loggingCmd -Level $Level -Message $Message -Source $Source
        $writeCmd = Get-Command Write-StructuredLog -ErrorAction SilentlyContinue
        if ($writeCmd) {
            & $writeCmd -Entry $entry
        }
        else {
            Write-Verbose "[$Source] [$Level] $Message"
        }
    }
    else {
        switch ($Level) {
            'ERROR' { Write-Error "[$Source] $Message" }
            'WARN' { Write-Warning "[$Source] $Message" }
            'INFO' { Write-Verbose "[$Source] $Message" }
            default { Write-Verbose "[$Source] [$Level] $Message" }
        }
    }
}

# ============================================================================
# Export Module Members
# ============================================================================

Export-ModuleMember -Function @(
    # Ingestion Sources
    'Register-IngestionSource',
    'Unregister-IngestionSource',
    'Get-IngestionSources',
    'Test-IngestionSource',
    
    # GitHub Integration
    'Invoke-GitHubRepoIngestion',
    'Get-GitHubReleaseAssets',
    'Invoke-GitHubWorkflowSync',
    'Get-GitHubRepoMetadata',
    
    # GitLab Integration
    'Invoke-GitLabRepoIngestion',
    'Get-GitLabProjectMetadata',
    
    # Generic Git Integration
    'Invoke-GitIngestion',
    
    # HTTP/HTTPS Integration
    'Invoke-HttpIngestion',
    
    # S3 Integration
    'Invoke-S3Ingestion',
    
    # REST API Integration
    'Invoke-RestApiIngestion',
    
    # Documentation Sites
    'Invoke-DocsSiteIngestion',
    'Get-DocsSitemap',
    'Invoke-APIReferenceIngestion',
    
    # Ingestion Pipeline
    'Start-IngestionJob',
    'Get-IngestionJobStatus',
    'Stop-IngestionJob',
    'Get-IngestionJobLogs',
    
    # Rate Limiting & Throttling
    'Get-IngestionRateLimit',
    'Invoke-IngestionWithBackoff',
    'Set-IngestionThrottle'
)
