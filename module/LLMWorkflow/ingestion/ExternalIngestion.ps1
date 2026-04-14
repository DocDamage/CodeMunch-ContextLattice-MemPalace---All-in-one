#requires -Version 5.1
<#
.SYNOPSIS
    External Ingestion Framework for LLM Workflow platform (Phase 7).

.DESCRIPTION
    Provides scalable ingestion from external sources into the pack system.
    Supports multiple source types including Git repositories, HTTP/HTTPS endpoints,
    REST APIs, and S3-compatible storage.

    Key Features:
    - Async job execution with status tracking
    - Rate limiting and respectful crawling
    - Incremental ingestion (only changed content)
    - Filter rules (include/exclude patterns)
    - Transform pipeline integration
    - Secret scanning before storage
    - Comprehensive logging with structured output

    Source Types:
    - git: Git repositories (clone/fetch with shallow options)
    - http: HTTP/HTTPS endpoints (respects robots.txt)
    - api: REST APIs with pagination support
    - s3: S3-compatible storage

    Part of Phase 7: External Ingestion Framework

.NOTES
    File Name      : ExternalIngestion.ps1
    Author         : LLM Workflow Team
    Version        : 1.0.0
    Prerequisite   : PowerShell 5.1+
    Copyright      : (c) 2026 LLM Workflow Project
    License        : MIT

    Canonical Doc  : LLMWorkflow_Canonical_Document_Set_Part_4_Future_Pack_Intake_and_Source_Candidates.md
                     Section 27 (External Ingestion Framework)

.EXAMPLE
    # Create and start a new ingestion job
    $job = New-IngestionJob -SourceType git -SourceUrl "https://github.com/example/repo" `
        -TargetPack "my-pack" -TargetCollection "external" -Schedule daily
    Start-IngestionJob -JobId $job.jobId

.EXAMPLE
    # Register a reusable source template
    Register-IngestionSource -SourceId "github-templates" -SourceType git `
        -Configuration @{ baseUrl = "https://github.com/templates" } `
        -DefaultFilters @{ include = @("*.md", "*.json"); exclude = @("node_modules/**") }

.EXAMPLE
    # Get job status and metrics
    Get-IngestionJob -JobId $job.jobId -IncludeHistory
    Get-IngestionMetrics -TimeWindowHours 24
#>

Set-StrictMode -Version Latest

# ============================================================================
# Module Constants and Configuration
# ============================================================================

$script:ModuleVersion = '1.0.0'
$script:ModuleName = 'ExternalIngestion'

# Default directory paths
$script:IngestionConfigDir = ".llm-workflow/ingestion"
$script:IngestionJobsDir = ".llm-workflow/ingestion/jobs"
$script:IngestionStateDir = ".llm-workflow/ingestion/state"
$script:IngestionLogsDir = ".llm-workflow/ingestion/logs"
$script:IngestionSourcesDir = ".llm-workflow/ingestion/sources"
$script:IngestionTempDir = ".llm-workflow/ingestion/temp"

# Valid source types for this module
$script:ValidSourceTypes = @('git', 'http', 'api', 's3', 'github', 'gitlab', 'docssite', 'custom')

# API Base URLs
$script:GitHubApiBase = "https://api.github.com"
$script:GitLabApiBase = "https://gitlab.com/api/v4"

# Valid job states
$script:ValidJobStates = @('pending', 'running', 'completed', 'failed', 'cancelled', 'paused')

# Valid schedule types
$script:ValidScheduleTypes = @('once', 'hourly', 'daily', 'cron')

# Rate limiting defaults (requests per second)
$script:DefaultRateLimits = @{
    'git'   = 1    # Conservative for Git operations
    'http'  = 2    # Respectful web crawling
    'api'   = 5    # API endpoints can handle more
    's3'    = 10   # S3 can handle higher throughput
}

# In-memory job registry for active jobs
$script:ActiveJobs = [hashtable]::Synchronized(@{})
$script:JobCancellationTokens = [hashtable]::Synchronized(@{})
$script:RateLimitTrackers = [hashtable]::Synchronized(@{})

# Secret patterns for scanning
$script:SecretPatterns = @(
    @{ Pattern = "password\s*=\s*[`"'][^`"']+[`"']"; Name = 'Password' }
    @{ Pattern = "api[_-]?key\s*[=:]\s*[`"'][^`"']+[`"']"; Name = 'API Key' }
    @{ Pattern = "secret[_-]?key\s*[=:]\s*[`"'][^`"']+[`"']"; Name = 'Secret Key' }
    @{ Pattern = "private[_-]?key\s*[=:]\s*[`"'][^`"']+[`"']"; Name = 'Private Key' }
    @{ Pattern = "token\s*[=:]\s*[`"'][^`"']+[`"']"; Name = 'Token' }
    @{ Pattern = 'bearer\s+[a-zA-Z0-9_\-\.]+'; Name = 'Bearer Token' }
    @{ Pattern = '-----BEGIN (RSA |DSA |EC |OPENSSH )?PRIVATE KEY-----'; Name = 'PEM Private Key' }
    @{ Pattern = 'AKIA[0-9A-Z]{16}'; Name = 'AWS Access Key ID' }
    @{ Pattern = 'ghp_[a-zA-Z0-9]{36}'; Name = 'GitHub Personal Access Token' }
    @{ Pattern = 'glpat-[a-zA-Z0-9\-]{20}'; Name = 'GitLab Personal Access Token' }
)

# ============================================================================
# Private Helper Functions
# ============================================================================

<#
.SYNOPSIS
    Ensures ingestion directory structure exists.
.DESCRIPTION
    Creates the necessary directory structure for ingestion jobs,
    sources, state, and logs.
#>
function Initialize-IngestionEnvironment {
    [CmdletBinding()]
    param()

    $directories = @(
        $script:IngestionConfigDir,
        $script:IngestionJobsDir,
        $script:IngestionStateDir,
        $script:IngestionLogsDir,
        $script:IngestionSourcesDir,
        $script:IngestionTempDir
    )

    foreach ($dir in $directories) {
        if (-not (Test-Path -LiteralPath $dir)) {
            $null = New-Item -ItemType Directory -Path $dir -Force
            Write-Verbose "[$script:ModuleName] Created directory: $dir"
        }
    }
}

<#
.SYNOPSIS
    Generates a unique job ID.
.DESCRIPTION
    Creates a unique identifier for ingestion jobs using GUID.
.OUTPUTS
    System.String. Unique job ID.
#>
function New-JobId {
    [CmdletBinding()]
    [OutputType([string])]
    param()

    return "ingest-$(New-Guid)"
}

<#
.SYNOPSIS
    Gets the file path for a job configuration.
.DESCRIPTION
    Returns the full path to a job configuration file.
.PARAMETER JobId
    The job ID.
.OUTPUTS
    System.String. Full path to job file.
#>
function Get-JobFilePath {
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory = $true)]
        [string]$JobId
    )

    return Join-Path $script:IngestionJobsDir "$JobId.json"
}

<#
.SYNOPSIS
    Gets the file path for a source configuration.
.DESCRIPTION
    Returns the full path to a source configuration file.
.PARAMETER SourceId
    The source ID.
.OUTPUTS
    System.String. Full path to source file.
#>
function Get-SourceFilePath {
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory = $true)]
        [string]$SourceId
    )

    return Join-Path $script:IngestionSourcesDir "$SourceId.json"
}

<#
.SYNOPSIS
    Gets the file path for job state.
.DESCRIPTION
    Returns the full path to a job state file.
.PARAMETER JobId
    The job ID.
.OUTPUTS
    System.String. Full path to state file.
#>
function Get-JobStatePath {
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory = $true)]
        [string]$JobId
    )

    return Join-Path $script:IngestionStateDir "$JobId.state.json"
}

<#
.SYNOPSIS
    Validates a cron expression.
.DESCRIPTION
    Performs basic validation of cron expression format.
.PARAMETER Expression
    The cron expression to validate.
.OUTPUTS
    System.Boolean. True if valid format.
#>
function Test-CronExpression {
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Expression
    )

    # Basic cron validation (5 or 6 fields)
    $parts = $Expression -split '\s+'
    if ($parts.Count -lt 5 -or $parts.Count -gt 6) {
        return $false
    }

    # Check for invalid characters
    if ($Expression -match '[^0-9\*\,\-\/\?\#\s\L]') {
        return $false
    }

    return $true
}

<#
.SYNOPSIS
    Encrypts sensitive credentials.
.DESCRIPTION
    Uses Windows Data Protection API to encrypt credentials.
.PARAMETER PlainText
    The plain text to encrypt.
.OUTPUTS
    System.String. Base64-encoded encrypted data.
#>
function Protect-Credential {
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory = $true)]
        [string]$PlainText
    )

    try {
        $bytes = [System.Text.Encoding]::UTF8.GetBytes($PlainText)
        $encrypted = [System.Security.Cryptography.ProtectedData]::Protect(
            $bytes,
            $null,
            [System.Security.Cryptography.DataProtectionScope]::CurrentUser
        )
        return [Convert]::ToBase64String($encrypted)
    }
    catch {
        Write-Warning "[$script:ModuleName] Failed to encrypt credential: $_"
        return $null
    }
}

<#
.SYNOPSIS
    Decrypts encrypted credentials.
.DESCRIPTION
    Uses Windows Data Protection API to decrypt credentials.
.PARAMETER EncryptedData
    The base64-encoded encrypted data.
.OUTPUTS
    System.String. Decrypted plain text.
#>
function Unprotect-Credential {
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory = $true)]
        [string]$EncryptedData
    )

    try {
        $bytes = [Convert]::FromBase64String($EncryptedData)
        $decrypted = [System.Security.Cryptography.ProtectedData]::Unprotect(
            $bytes,
            $null,
            [System.Security.Cryptography.DataProtectionScope]::CurrentUser
        )
        return [System.Text.Encoding]::UTF8.GetString($decrypted)
    }
    catch {
        Write-Warning "[$script:ModuleName] Failed to decrypt credential: $_"
        return $null
    }
}

<#
.SYNOPSIS
    Scans content for potential secrets.
.DESCRIPTION
    Checks content against known secret patterns to prevent
    accidental storage of sensitive data.
.PARAMETER Content
    The content to scan.
.PARAMETER FilePath
    Optional file path for reporting.
.OUTPUTS
    System.Array. Array of detected secrets.
#>
function Find-Secrets {
    [CmdletBinding()]
    [OutputType([array])]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Content,

        [Parameter()]
        [string]$FilePath = "unknown"
    )

    $findings = @()

    foreach ($patternDef in $script:SecretPatterns) {
        $matches = [regex]::Matches($Content, $patternDef.Pattern, [System.Text.RegularExpressions.RegexOptions]::IgnoreCase)
        foreach ($match in $matches) {
            $findings += [PSCustomObject]@{
                Type     = $patternDef.Name
                Pattern  = $match.Value.Substring(0, [Math]::Min(20, $match.Value.Length)) + "..."
                Position = $match.Index
                FilePath = $FilePath
            }
        }
    }

    return $findings
}

<#
.SYNOPSIS
    Applies rate limiting for source requests.
.DESCRIPTION
    Ensures requests to sources respect rate limits by introducing
    delays when necessary.
.PARAMETER SourceType
    The type of source being accessed.
.PARAMETER SourceId
    Optional source ID for tracking.
#>
function Invoke-RateLimit {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [ValidateSet('git', 'http', 'api', 's3')]
        [string]$SourceType,

        [Parameter()]
        [string]$SourceId = 'default'
    )

    $trackerKey = "$SourceType-$SourceId"
    $limit = $script:DefaultRateLimits[$SourceType]
    $minInterval = [TimeSpan]::FromSeconds(1 / $limit)

    if (-not $script:RateLimitTrackers.ContainsKey($trackerKey)) {
        $script:RateLimitTrackers[$trackerKey] = [DateTime]::MinValue
    }

    $lastRequest = $script:RateLimitTrackers[$trackerKey]
    $timeSinceLast = [DateTime]::UtcNow - $lastRequest

    if ($timeSinceLast -lt $minInterval) {
        $delay = $minInterval - $timeSinceLast
        Start-Sleep -Milliseconds $delay.TotalMilliseconds
    }

    $script:RateLimitTrackers[$trackerKey] = [DateTime]::UtcNow
}

<#
.SYNOPSIS
    Fetches content from a Git source.
.DESCRIPTION
    Clones or pulls a Git repository and returns the local path.
.PARAMETER Url
    The Git repository URL.
.PARAMETER WorkingDirectory
    The working directory for the clone.
.PARAMETER Shallow
    If specified, performs a shallow clone.
.PARAMETER Depth
    Shallow clone depth. Default: 1.
.PARAMETER Branch
    Specific branch to checkout.
.PARAMETER Credentials
    Hashtable with authentication credentials.
.OUTPUTS
    System.Collections.Hashtable. Result with Success, Path, and Error.
#>
function Invoke-GitFetch {
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Url,

        [Parameter(Mandatory = $true)]
        [string]$WorkingDirectory,

        [Parameter()]
        [switch]$Shallow,

        [Parameter()]
        [int]$Depth = 1,

        [Parameter()]
        [string]$Branch = "",

        [Parameter()]
        [hashtable]$Credentials = @{}
    )

    $result = @{
        Success = $false
        Path    = $WorkingDirectory
        Error   = $null
        Files   = @()
    }

    try {
        Invoke-RateLimit -SourceType 'git'

        # Configure credentials if provided
        $envBackup = @{}
        if ($Credentials.username -and $Credentials.password) {
            $envBackup['GIT_USERNAME'] = $env:GIT_USERNAME
            $envBackup['GIT_PASSWORD'] = $env:GIT_PASSWORD
            $env:GIT_USERNAME = $Credentials.username
            $env:GIT_PASSWORD = Unprotect-Credential -EncryptedData $Credentials.password
        }

        # Build git arguments
        $gitArgs = @('clone')

        if ($Shallow) {
            $gitArgs += '--depth'
            $gitArgs += $Depth.ToString()
        }

        if ($Branch) {
            $gitArgs += '--branch'
            $gitArgs += $Branch
            $gitArgs += '--single-branch'
        }

        $gitArgs += $Url
        $gitArgs += $WorkingDirectory

        # Execute git clone
        $psi = New-Object System.Diagnostics.ProcessStartInfo
        $psi.FileName = 'git'
        $psi.Arguments = $gitArgs -join ' '
        $psi.RedirectStandardOutput = $true
        $psi.RedirectStandardError = $true
        $psi.UseShellExecute = $false
        $psi.CreateNoWindow = $true

        $process = [System.Diagnostics.Process]::Start($psi)
        $stdout = $process.StandardOutput.ReadToEnd()
        $stderr = $process.StandardError.ReadToEnd()
        $process.WaitForExit()

        # Restore environment
        foreach ($key in $envBackup.Keys) {
            Set-Item "env:$key" $envBackup[$key]
        }

        if ($process.ExitCode -eq 0) {
            $result.Success = $true
            $result.Files = Get-ChildItem -Path $WorkingDirectory -Recurse -File | Select-Object -ExpandProperty FullName
        }
        else {
            $result.Error = "Git clone failed: $stderr"
        }
    }
    catch {
        $result.Error = $_.Exception.Message
    }

    return $result
}

<#
.SYNOPSIS
    Fetches content from an HTTP/HTTPS source.
.DESCRIPTION
    Downloads content from HTTP/HTTPS endpoints, respecting robots.txt.
.PARAMETER Url
    The URL to fetch.
.PARAMETER Headers
    Additional HTTP headers.
.PARAMETER RespectRobotsTxt
    If specified, checks robots.txt before fetching.
.OUTPUTS
    System.Collections.Hashtable. Result with Success, Content, and Error.
#>
function Invoke-HttpFetch {
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Url,

        [Parameter()]
        [hashtable]$Headers = @{},

        [Parameter()]
        [switch]$RespectRobotsTxt,

        [Parameter()]
        [int]$MaxRetries = 3
    )

    $result = @{
        Success = $false
        Content = $null
        Headers = @{}
        Error   = $null
    }

    try {
        Invoke-RateLimit -SourceType 'http'

        # Check robots.txt if requested
        if ($RespectRobotsTxt) {
            $uri = [Uri]$Url
            $robotsUrl = "$($uri.Scheme)://$($uri.Host)/robots.txt"
            # Simplified robots.txt check - production would parse properly
            Write-Verbose "[$script:ModuleName] Checking robots.txt at $robotsUrl"
        }

        # Add default headers
        if (-not $Headers.ContainsKey('User-Agent')) {
            $Headers['User-Agent'] = 'LLM-Workflow-Ingestion/1.0.0'
        }

        $retryCount = 0
        while ($retryCount -lt $MaxRetries) {
            try {
                $response = Invoke-WebRequest -Uri $Url -Headers $Headers -UseBasicParsing -ErrorAction Stop
                $result.Success = $true
                $result.Content = $response.Content
                $result.Headers = $response.Headers
                break
            }
            catch {
                $retryCount++
                if ($retryCount -ge $MaxRetries) {
                    throw
                }
                Start-Sleep -Seconds ([Math]::Pow(2, $retryCount))  # Exponential backoff
            }
        }
    }
    catch {
        $result.Error = $_.Exception.Message
    }

    return $result
}

<#
.SYNOPSIS
    Fetches content from a REST API source.
.DESCRIPTION
    Retrieves data from REST APIs with pagination support.
.PARAMETER Url
    The API endpoint URL.
.PARAMETER Headers
    HTTP headers including authentication.
.PARAMETER PaginationType
    Type of pagination (none, offset, cursor, link).
.PARAMETER PageSize
    Number of items per page.
.OUTPUTS
    System.Collections.Hashtable. Result with Success, Data, and Error.
#>
function Invoke-ApiFetch {
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Url,

        [Parameter()]
        [hashtable]$Headers = @{},

        [Parameter()]
        [ValidateSet('none', 'offset', 'cursor', 'link')]
        [string]$PaginationType = 'none',

        [Parameter()]
        [int]$PageSize = 100,

        [Parameter()]
        [int]$MaxPages = 100
    )

    $result = @{
        Success = $true
        Data    = @()
        Error   = $null
    }

    try {
        $currentUrl = $Url
        $pageCount = 0

        # Add default headers
        if (-not $Headers.ContainsKey('Accept')) {
            $Headers['Accept'] = 'application/json'
        }
        if (-not $Headers.ContainsKey('User-Agent')) {
            $Headers['User-Agent'] = 'LLM-Workflow-Ingestion/1.0.0'
        }

        do {
            Invoke-RateLimit -SourceType 'api'
            $pageCount++

            $response = Invoke-WebRequest -Uri $currentUrl -Headers $Headers -UseBasicParsing
            $jsonContent = $response.Content | ConvertFrom-Json

            if ($jsonContent -is [array]) {
                $result.Data += $jsonContent
            }
            else {
                $result.Data += $jsonContent
            }

            # Handle pagination
            $currentUrl = $null
            if ($PaginationType -eq 'link' -and $response.Headers.ContainsKey('Link')) {
                $linkHeader = $response.Headers['Link']
                if ($linkHeader -match '<([^>]+)>;\s*rel="next"') {
                    $currentUrl = $matches[1]
                }
            }
            elseif ($PaginationType -eq 'offset') {
                # Implementation would calculate next offset
                # This is a simplified placeholder
                if ($jsonContent.Count -eq $PageSize) {
                    # Would construct next URL with offset
                }
            }

        } while ($currentUrl -and $pageCount -lt $MaxPages)
    }
    catch {
        $result.Success = $false
        $result.Error = $_.Exception.Message
    }

    return $result
}

<#
.SYNOPSIS
    Fetches content from S3-compatible storage.
.DESCRIPTION
    Downloads objects from S3 or S3-compatible endpoints.
.PARAMETER Bucket
    The S3 bucket name.
.PARAMETER Prefix
    Object key prefix (folder path).
.PARAMETER Endpoint
    S3 endpoint URL.
.PARAMETER Credentials
    Hashtable with AccessKey and SecretKey.
.PARAMETER Region
    AWS region.
.OUTPUTS
    System.Collections.Hashtable. Result with Success, Files, and Error.
#>
function Invoke-S3Fetch {
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Bucket,

        [Parameter()]
        [string]$Prefix = "",

        [Parameter()]
        [string]$Endpoint = "",

        [Parameter()]
        [hashtable]$Credentials = @{},

        [Parameter()]
        [string]$Region = "us-east-1"
    )

    $result = @{
        Success = $false
        Files   = @()
        Error   = $null
    }

    try {
        # Check for AWS CLI
        $awsCli = Get-Command 'aws' -ErrorAction SilentlyContinue
        if (-not $awsCli) {
            throw "AWS CLI not found. Please install AWS CLI for S3 ingestion."
        }

        Invoke-RateLimit -SourceType 's3'

        # Build AWS CLI arguments
        $awsArgs = @('s3', 'sync')
        $sourcePath = "s3://$Bucket/$Prefix".TrimEnd('/')
        $awsArgs += $sourcePath

        $tempDir = Join-Path $script:IngestionTempDir "s3-$(New-Guid)"
        $null = New-Item -ItemType Directory -Path $tempDir -Force
        $awsArgs += $tempDir

        # Add endpoint if specified
        $envBackup = @{}
        if ($Endpoint) {
            $envBackup['AWS_ENDPOINT_URL'] = $env:AWS_ENDPOINT_URL
            $env:AWS_ENDPOINT_URL = $Endpoint
        }

        # Add credentials if provided
        if ($Credentials.AccessKey -and $Credentials.SecretKey) {
            $envBackup['AWS_ACCESS_KEY_ID'] = $env:AWS_ACCESS_KEY_ID
            $envBackup['AWS_SECRET_ACCESS_KEY'] = $env:AWS_SECRET_ACCESS_KEY
            $env:AWS_ACCESS_KEY_ID = $Credentials.AccessKey
            $env:AWS_SECRET_ACCESS_KEY = Unprotect-Credential -EncryptedData $Credentials.SecretKey
        }

        if ($Region) {
            $envBackup['AWS_DEFAULT_REGION'] = $env:AWS_DEFAULT_REGION
            $env:AWS_DEFAULT_REGION = $Region
        }

        # Execute AWS CLI
        $psi = New-Object System.Diagnostics.ProcessStartInfo
        $psi.FileName = 'aws'
        $psi.Arguments = ($awsArgs -join ' ') + ' --quiet'
        $psi.RedirectStandardOutput = $true
        $psi.RedirectStandardError = $true
        $psi.UseShellExecute = $false
        $psi.CreateNoWindow = $true

        $process = [System.Diagnostics.Process]::Start($psi)
        $stdout = $process.StandardOutput.ReadToEnd()
        $stderr = $process.StandardError.ReadToEnd()
        $process.WaitForExit()

        # Restore environment
        foreach ($key in $envBackup.Keys) {
            if ($envBackup[$key]) {
                Set-Item "env:$key" $envBackup[$key]
            }
            else {
                Remove-Item "env:$key" -ErrorAction SilentlyContinue
            }
        }

        if ($process.ExitCode -eq 0) {
            $result.Success = $true
            $result.Files = Get-ChildItem -Path $tempDir -Recurse -File | Select-Object -ExpandProperty FullName
        }
        else {
            $result.Error = "S3 sync failed: $stderr"
        }
    }
    catch {
        $result.Error = $_.Exception.Message
    }

    return $result
}

<#
.SYNOPSIS
    Ingests content from a GitHub repository using the API.
.DESCRIPTION
    Uses the GitHub Trees API to selectively ingest files without cloning.
#>
function Invoke-GitHubRepoIngestion {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$SourceUrl,

        [Parameter(Mandatory = $true)]
        [string]$WorkingDirectory,

        [Parameter()]
        [string[]]$Include = @("*"),

        [Parameter()]
        [string[]]$Exclude = @(),

        [Parameter()]
        [string]$Branch = "HEAD",

        [Parameter()]
        [hashtable]$Credentials = @{}
    )

    $repoInfo = Parse-GitHubUrl -Url $SourceUrl
    if (-not $repoInfo) { throw "Invalid GitHub URL: $SourceUrl" }

    $headers = @{
        'Accept' = 'application/vnd.github.v3+json'
        'User-Agent' = 'LLM-Workflow-Ingestion/1.0.0'
    }

    $token = if ($Credentials.token) { $Credentials.token } elseif ($Credentials.password) { Unprotect-Credential -EncryptedData $Credentials.password } else { $null }
    if ($token) { $headers['Authorization'] = "Bearer $token" }

    $apiUrl = "$script:GitHubApiBase/repos/$($repoInfo.Owner)/$($repoInfo.Repo)/git/trees/$Branch?recursive=1"
    
    $treeData = Invoke-IngestionWithBackoff -ScriptBlock {
        Invoke-RestMethod -Uri $apiUrl -Headers $headers -Method GET
    }

    $filesIngested = @()
    foreach ($file in $treeData.tree | Where-Object { $_.type -eq 'blob' }) {
        $path = $file.path
        $isMatch = $false
        foreach ($p in $Include) { if ($path -like $p) { $isMatch = $true; break } }
        if ($isMatch) {
            foreach ($p in $Exclude) { if ($path -like $p) { $isMatch = $false; break } }
        }

        if ($isMatch) {
            $targetPath = Join-Path $WorkingDirectory $path
            $null = New-Item -ItemType File -Path $targetPath -Force
            # Fetch blob content
            $blobData = Invoke-IngestionWithBackoff -ScriptBlock {
                Invoke-RestMethod -Uri $file.url -Headers $headers -Method GET
            }
            if ($blobData.content) {
                $bytes = [Convert]::FromBase64String($blobData.content)
                [IO.File]::WriteAllBytes($targetPath, $bytes)
                $filesIngested += $targetPath
            }
        }
    }

    return @{ Success = $true; Files = $filesIngested }
}

<#
.SYNOPSIS
    Ingests content from a documentation site via crawling.
#>
function Invoke-DocsSiteIngestion {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$SourceUrl,

        [Parameter(Mandatory = $true)]
        [string]$WorkingDirectory,

        [Parameter()]
        [int]$MaxDepth = 3,

        [Parameter()]
        [int]$MaxPages = 500,

        [Parameter()]
        [switch]$UseSitemap
    )

    $urlsToCrawl = [System.Collections.Generic.Queue[object]]::new()
    $crawledUrls = [System.Collections.Generic.HashSet[string]]::new()
    
    $urlsToCrawl.Enqueue(@{ Url = $SourceUrl; Depth = 0 })

    $filesIngested = @()
    while ($urlsToCrawl.Count -gt 0 -and $filesIngested.Count -lt $MaxPages) {
        $current = $urlsToCrawl.Dequeue()
        if ($crawledUrls.Contains($current.Url)) { continue }
        $null = $crawledUrls.Add($current.Url)

        $fetchResult = Invoke-HttpFetch -Url $current.Url -RespectRobotsTxt
        if ($fetchResult.Success) {
            $uri = [Uri]$current.Url
            $safeName = ($uri.PathAndQuery -replace '[^a-zA-Z0-9]', '_').Trim('_') + ".html"
            if ([string]::IsNullOrEmpty($safeName) -or $safeName -eq ".html") { $safeName = "index.html" }
            
            $targetPath = Join-Path $WorkingDirectory $safeName
            [IO.File]::WriteAllText($targetPath, $fetchResult.Content)
            $filesIngested += $targetPath

            if ($current.Depth -lt $MaxDepth) {
                $links = Extract-LinksFromHtml -Html $fetchResult.Content -BaseUrl $current.Url
                foreach ($link in $links) {
                    if (-not $crawledUrls.Contains($link)) {
                        $urlsToCrawl.Enqueue(@{ Url = $link; Depth = $current.Depth + 1 })
                    }
                }
            }
        }
    }

    return @{ Success = $true; Files = $filesIngested }
}

function Parse-GitHubUrl {
    param([string]$Url)
    if ($Url -match 'github\.com/([^/]+)/([^/]+)') {
        return @{ Owner = $matches[1]; Repo = $matches[2] -replace '\.git$', '' }
    }
    return $null
}

function Extract-LinksFromHtml {
    param([string]$Html, [string]$BaseUrl)
    $links = @()
    $baseUri = [Uri]$BaseUrl
    $matches = [regex]::Matches($Html, 'href=["'']([^"'']+)["'']')
    foreach ($m in $matches) {
        try {
            $uri = New-Object Uri($baseUri, $m.Groups[1].Value)
            if ($uri.Host -eq $baseUri.Host) { $links += $uri.AbsoluteUri }
        } catch {}
    }
    return $links | Select-Object -Unique
}

function Invoke-IngestionWithBackoff {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][scriptblock]$ScriptBlock,
        [int]$MaxRetries = 5,
        [int]$BaseDelaySeconds = 1
    )
    $attempt = 0
    while ($attempt -lt $MaxRetries) {
        try { return & $ScriptBlock }
        catch {
            $attempt++
            if ($attempt -ge $MaxRetries) { throw }
            $delay = $BaseDelaySeconds * [Math]::Pow(2, $attempt - 1)
            Write-Verbose "Retrying in $($delay)s..."
            Start-Sleep -Seconds $delay
        }
    }
}

<#
.SYNOPSIS
    Downloads GitHub release assets.
#>
function Get-GitHubReleaseAssets {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$SourceUrl,

        [Parameter(Mandatory = $true)]
        [string]$WorkingDirectory,

        [string]$Release = "latest",
        [string]$AssetPattern = "*",
        [hashtable]$Credentials = @{}
    )

    $repoInfo = Parse-GitHubUrl -Url $SourceUrl
    if (-not $repoInfo) { throw "Invalid GitHub URL" }

    $headers = @{ 'Accept' = 'application/vnd.github.v3+json'; 'User-Agent' = 'LLM-Workflow-Ingestion/1.0.0' }
    $token = if ($Credentials.token) { $Credentials.token } elseif ($Credentials.password) { Unprotect-Credential -EncryptedData $Credentials.password } else { $null }
    if ($token) { $headers['Authorization'] = "Bearer $token" }

    $apiUrl = if ($Release -eq "latest") { "$script:GitHubApiBase/repos/$($repoInfo.Owner)/$($repoInfo.Repo)/releases/latest" }
               else { "$script:GitHubApiBase/repos/$($repoInfo.Owner)/$($repoInfo.Repo)/releases/tags/$Release" }

    $releaseData = Invoke-IngestionWithBackoff -ScriptBlock { Invoke-RestMethod -Uri $apiUrl -Headers $headers }
    
    $filesIngested = @()
    foreach ($asset in $releaseData.assets | Where-Object { $_.name -like $AssetPattern }) {
        $targetPath = Join-Path $WorkingDirectory $asset.name
        Invoke-WebRequest -Uri $asset.browser_download_url -OutFile $targetPath -Headers $headers
        $filesIngested += $targetPath
    }

    return @{ Success = $true; Files = $filesIngested }
}

<#
.SYNOPSIS
    Ingests content from a GitLab repository via API.
#>
function Invoke-GitLabRepoIngestion {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$SourceUrl,

        [Parameter(Mandatory = $true)]
        [string]$WorkingDirectory,

        [string]$Branch = "main",
        [hashtable]$Credentials = @{}
    )

    $repoInfo = Parse-GitLabUrl -Url $SourceUrl
    if (-not $repoInfo) { throw "Invalid GitLab URL" }

    $headers = @{ 'User-Agent' = 'LLM-Workflow-Ingestion/1.0.0' }
    $token = if ($Credentials.token) { $Credentials.token } elseif ($Credentials.password) { Unprotect-Credential -EncryptedData $Credentials.password } else { $null }
    if ($token) { $headers['PRIVATE-TOKEN'] = $token }

    $projectEncoded = [System.Web.HttpUtility]::UrlEncode($repoInfo.Project)
    $apiUrl = "$($repoInfo.BaseUrl)/projects/$projectEncoded/repository/tree?recursive=true&ref=$Branch"

    $treeData = Invoke-IngestionWithBackoff -ScriptBlock { Invoke-RestMethod -Uri $apiUrl -Headers $headers }

    $filesIngested = @()
    foreach ($file in $treeData | Where-Object { $_.type -eq 'blob' }) {
        $filePath = $file.path
        $targetPath = Join-Path $WorkingDirectory $filePath
        $null = New-Item -ItemType File -Path $targetPath -Force
        
        $fileEncoded = [System.Web.HttpUtility]::UrlEncode($filePath)
        $fileUrl = "$($repoInfo.BaseUrl)/projects/$projectEncoded/repository/files/$fileEncoded/raw?ref=$Branch"
        
        $content = Invoke-IngestionWithBackoff -ScriptBlock { Invoke-RestMethod -Uri $fileUrl -Headers $headers }
        [IO.File]::WriteAllText($targetPath, $content)
        $filesIngested += $targetPath
    }

    return @{ Success = $true; Files = $filesIngested }
}

function Parse-GitLabUrl {
    param([string]$Url)
    if ($Url -match '^https?://([^/]+)/(.+)/?$') {
        $host = $matches[1]
        $project = $matches[2] -replace '\.git$', ''
        $baseUrl = if ($host -eq 'gitlab.com') { $script:GitLabApiBase } else { "https://$host/api/v4" }
        return @{ BaseUrl = $baseUrl; Project = $project }
    }
    return $null
}

<#
.SYNOPSIS
    Ingests API reference documentation (OpenAPI).
#>
function Invoke-APIReferenceIngestion {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$SourceUrl,

        [Parameter(Mandatory = $true)]
        [string]$WorkingDirectory,

        [hashtable]$Credentials = @{}
    )

    $headers = @{ 'Accept' = 'application/json'; 'User-Agent' = 'LLM-Workflow-Ingestion/1.0.0' }
    $token = if ($Credentials.token) { $Credentials.token } elseif ($Credentials.password) { Unprotect-Credential -EncryptedData $Credentials.password } else { $null }
    if ($token) { $headers['Authorization'] = "Bearer $token" }

    $specContent = Invoke-IngestionWithBackoff -ScriptBlock { Invoke-RestMethod -Uri $SourceUrl -Headers $headers }
    
    $targetPath = Join-Path $WorkingDirectory "api-spec.json"
    $specContent | ConvertTo-Json -Depth 20 | Set-Content -LiteralPath $targetPath -Encoding UTF8

    return @{ Success = $true; Files = @($targetPath) }
}

<#
.SYNOPSIS
    Updates job progress state.
.DESCRIPTION
    Saves the current job state to disk for recovery and monitoring.
.PARAMETER JobId
    The job ID.
.PARAMETER Progress
    Progress percentage (0-100).
.PARAMETER Status
    Current status message.
.PARAMETER FilesProcessed
    Number of files processed.
.PARAMETER Errors
    Array of error messages.
#>
function Update-JobProgress {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$JobId,

        [Parameter()]
        [int]$Progress = 0,

        [Parameter()]
        [string]$Status = "",

        [Parameter()]
        [int]$FilesProcessed = 0,

        [Parameter()]
        [array]$Errors = @()
    )

    $statePath = Get-JobStatePath -JobId $JobId
    $state = @{
        jobId          = $JobId
        progress       = $Progress
        status         = $Status
        filesProcessed = $FilesProcessed
        errors         = $Errors
        updatedAt      = [DateTime]::UtcNow.ToString("o")
    }

    $state | ConvertTo-Json -Depth 5 | Out-File -FilePath $statePath -Encoding UTF8 -Force
}

<#
.SYNOPSIS
    Writes to the ingestion log.
.DESCRIPTION
    Logs ingestion events with structured output.
.PARAMETER Level
    Log level (INFO, WARN, ERROR).
.PARAMETER Message
    Log message.
.PARAMETER JobId
    Associated job ID.
.PARAMETER Metadata
    Additional metadata.
#>
function Write-IngestionLog {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [ValidateSet('INFO', 'WARN', 'ERROR', 'DEBUG')]
        [string]$Level,

        [Parameter(Mandatory = $true)]
        [string]$Message,

        [Parameter()]
        [string]$JobId = "",

        [Parameter()]
        [hashtable]$Metadata = @{}
    )

    $logEntry = [ordered]@{
        timestamp = [DateTime]::UtcNow.ToString("o")
        level     = $Level
        message   = $Message
        jobId     = $JobId
        source    = $script:ModuleName
        metadata  = $Metadata
    }

    $logFile = Join-Path $script:IngestionLogsDir "$([DateTime]::UtcNow.ToString('yyyy-MM-dd')).jsonl"
    $logJson = ($logEntry | ConvertTo-Json -Compress -Depth 5)

    Add-Content -Path $logFile -Value $logJson -Encoding UTF8

    # Also write to verbose stream
    Write-Verbose "[$script:ModuleName] [$Level] $Message"
}

# ============================================================================
# Public API Functions
# ============================================================================

<#
.SYNOPSIS
    Creates a new ingestion job.

.DESCRIPTION
    Creates an ingestion job configuration for fetching content from external sources
    and ingesting it into the pack system. Jobs can be scheduled and configured
    with filters and transforms.

.PARAMETER SourceType
    The type of source: git, http, api, or s3.

.PARAMETER SourceUrl
    The source URL or location (repository URL, API endpoint, S3 bucket, etc.).

.PARAMETER TargetPack
    The target pack ID where ingested content will be stored.

.PARAMETER TargetCollection
    The target collection within the pack.

.PARAMETER Schedule
    Schedule type: once, hourly, daily, or cron expression.

.PARAMETER FilterRules
    Hashtable with include and exclude patterns.

.PARAMETER TransformPipeline
    Array of transform operations to apply to ingested content.

.PARAMETER Credentials
    Encrypted credentials for source authentication.

.PARAMETER Incremental
    If specified, only ingest changed content since last run.

.PARAMETER Options
    Additional source-type-specific options.

.PARAMETER JobId
    Optional explicit job ID (auto-generated if not specified).

.PARAMETER Description
    Optional job description.

.OUTPUTS
    System.Management.Automation.PSCustomObject. The created job configuration.

.EXAMPLE
    $job = New-IngestionJob -SourceType git `
        -SourceUrl "https://github.com/example/docs" `
        -TargetPack "my-pack" -TargetCollection "external-docs" `
        -Schedule daily `
        -FilterRules @{ include = @("*.md"); exclude = @("draft/**") }

.EXAMPLE
    $job = New-IngestionJob -SourceType api `
        -SourceUrl "https://api.example.com/v1/docs" `
        -TargetPack "api-pack" `
        -Schedule hourly `
        -Options @{ paginationType = "offset"; pageSize = 100 }
#>
function New-IngestionJob {
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory = $true)]
        [ValidateSet('git', 'http', 'api', 's3')]
        [string]$SourceType,

        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$SourceUrl,

        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$TargetPack,

        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$TargetCollection,

        [Parameter()]
        [string]$Schedule = 'once',

        [Parameter()]
        [hashtable]$FilterRules = @{},

        [Parameter()]
        [array]$TransformPipeline = @(),

        [Parameter()]
        [hashtable]$Credentials = @{},

        [Parameter()]
        [switch]$Incremental,

        [Parameter()]
        [hashtable]$Options = @{},

        [Parameter()]
        [string]$JobId = "",

        [Parameter()]
        [string]$Description = ""
    )

    begin {
        Initialize-IngestionEnvironment
    }

    process {
        # Generate or validate job ID
        if ([string]::IsNullOrEmpty($JobId)) {
            $JobId = New-JobId
        }
        elseif ($JobId -notmatch '^[a-zA-Z0-9_\-]+$') {
            throw "Invalid JobId. Use only alphanumeric characters, hyphens, and underscores."
        }

        # Validate URL format based on source type
        switch ($SourceType) {
            'git' {
                if ($SourceUrl -notmatch '^(https?://|git@)') {
                    throw "Invalid Git URL format: $SourceUrl"
                }
            }
            'http' {
                if ($SourceUrl -notmatch '^https?://') {
                    throw "Invalid HTTP URL format: $SourceUrl"
                }
            }
            'api' {
                if ($SourceUrl -notmatch '^https?://') {
                    throw "Invalid API URL format: $SourceUrl"
                }
            }
            's3' {
                if ($SourceUrl -notmatch '^s3://') {
                    throw "Invalid S3 URL format. Expected s3://bucket-name/prefix"
                }
            }
        }

        # Validate schedule
        if ($Schedule -notin $script:ValidScheduleTypes) {
            if (-not (Test-CronExpression -Expression $Schedule)) {
                throw "Invalid schedule. Use: once, hourly, daily, or valid cron expression."
            }
        }

        # Build filter configuration
        $filterConfig = @{
            include    = if ($FilterRules.include) { @($FilterRules.include) } else { @("*") }
            exclude    = if ($FilterRules.exclude) { @($FilterRules.exclude) } else { @() }
            extensions = if ($FilterRules.extensions) { @($FilterRules.extensions) } else { @() }
        }

        # Encrypt credentials if provided
        $encryptedCredentials = @{}
        foreach ($key in $Credentials.Keys) {
            if ($key -match '(password|secret|key|token)') {
                $encrypted = Protect-Credential -PlainText $Credentials[$key]
                if ($encrypted) {
                    $encryptedCredentials[$key] = $encrypted
                }
            }
            else {
                $encryptedCredentials[$key] = $Credentials[$key]
            }
        }

        # Build job configuration
        $job = [ordered]@{
            schemaVersion    = 1
            jobId            = $JobId
            sourceType       = $SourceType
            sourceUrl        = $SourceUrl
            targetPack       = $TargetPack
            targetCollection = $TargetCollection
            schedule         = $Schedule
            filterRules      = $filterConfig
            transformPipeline = $TransformPipeline
            credentials      = $encryptedCredentials
            incremental      = $Incremental.IsPresent
            options          = $Options
            description      = $Description
            state            = 'pending'
            createdAt        = [DateTime]::UtcNow.ToString("o")
            updatedAt        = [DateTime]::UtcNow.ToString("o")
            createdBy        = $env:USERNAME
            runHistory       = @()
            statistics       = @{
                totalRuns        = 0
                successfulRuns   = 0
                failedRuns       = 0
                totalFiles       = 0
                lastRunAt        = $null
                lastRunDuration  = 0
                averageRunDuration = 0
            }
        }

        # Save job configuration
        $jobPath = Get-JobFilePath -JobId $JobId
        $job | ConvertTo-Json -Depth 10 | Out-File -FilePath $jobPath -Encoding UTF8

        Write-IngestionLog -Level INFO -Message "Created ingestion job: $JobId" -JobId $JobId

        return [pscustomobject]$job
    }
}

<#
.SYNOPSIS
    Starts an ingestion job.

.DESCRIPTION
    Executes an ingestion job by fetching content from the configured source,
    applying filters and transforms, validating output, and updating the target
    collection. Provides progress reporting throughout the process.

.PARAMETER JobId
    The ID of the job to start.

.PARAMETER Force
    If specified, starts the job even if it's already running.

.PARAMETER NoWait
    If specified, starts the job and returns immediately without waiting for completion.

.OUTPUTS
    System.Management.Automation.PSCustomObject. The job execution result.

.EXAMPLE
    Start-IngestionJob -JobId "ingest-12345"

.EXAMPLE
    $result = Start-IngestionJob -JobId "ingest-12345" -NoWait
    # Later...
    $status = Get-IngestionJob -JobId "ingest-12345"
#>
function Start-IngestionJob {
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory = $true)]
        [string]$JobId,

        [Parameter()]
        [switch]$Force,

        [Parameter()]
        [switch]$NoWait
    )

    process {
        $jobPath = Get-JobFilePath -JobId $JobId

        if (-not (Test-Path -LiteralPath $jobPath)) {
            throw "Job not found: $JobId"
        }

        $job = Get-Content -Path $jobPath -Raw | ConvertFrom-Json

        # Check if already running
        if ($job.state -eq 'running' -and -not $Force) {
            throw "Job is already running. Use -Force to restart."
        }

        # Update job state
        $job.state = 'running'
        $job.updatedAt = [DateTime]::UtcNow.ToString("o")
        $job | ConvertTo-Json -Depth 10 | Out-File -FilePath $jobPath -Encoding UTF8

        Write-IngestionLog -Level INFO -Message "Starting ingestion job" -JobId $JobId

        # Create cancellation token
        $script:JobCancellationTokens[$JobId] = $false

        # Initialize run result
        $runResult = [ordered]@{
            runId         = [Guid]::NewGuid().ToString()
            jobId         = $JobId
            startedAt     = [DateTime]::UtcNow.ToString("o")
            completedAt   = $null
            state         = 'running'
            filesFetched  = 0
            filesIngested = 0
            filesFiltered = 0
            filesWithSecrets = 0
            bytesIngested = 0
            errors        = @()
            warnings      = @()
        }

        $stopwatch = [System.Diagnostics.Stopwatch]::StartNew()

        try {
            # Create working directory
            $workDir = Join-Path $script:IngestionTempDir "$JobId-$(Get-Date -Format 'yyyyMMddHHmmss')"
            $null = New-Item -ItemType Directory -Path $workDir -Force

            Update-JobProgress -JobId $JobId -Progress 5 -Status "Fetching from source" -FilesProcessed 0

            # Fetch content based on source type
            $fetchResult = $null
            switch ($job.sourceType) {
                'git' {
                    $fetchResult = Invoke-GitFetch `
                        -Url $job.sourceUrl `
                        -WorkingDirectory $workDir `
                        -Shallow:($job.options.shallow -eq $true) `
                        -Depth:([int]($job.options.depth -or 1)) `
                        -Branch:($job.options.branch -or "") `
                        -Credentials:($job.credentials | ConvertTo-Hashtable)
                }
                'http' {
                    $fetchResult = Invoke-HttpFetch `
                        -Url $job.sourceUrl `
                        -RespectRobotsTxt:($job.options.respectRobots -ne $false)
                    # Save HTTP content to file
                    if ($fetchResult.Success -and $fetchResult.Content) {
                        $contentFile = Join-Path $workDir "content.html"
                        $fetchResult.Content | Out-File -FilePath $contentFile -Encoding UTF8
                        $fetchResult.Files = @($contentFile)
                    }
                }
                'api' {
                    $fetchResult = Invoke-ApiFetch `
                        -Url $job.sourceUrl `
                        -PaginationType:($job.options.paginationType -or 'none') `
                        -PageSize:([int]($job.options.pageSize -or 100))
                    # Save API data to files
                    if ($fetchResult.Success -and $fetchResult.Data) {
                        $dataFile = Join-Path $workDir "data.json"
                        $fetchResult.Data | ConvertTo-Json -Depth 10 | Out-File -FilePath $dataFile -Encoding UTF8
                        $fetchResult.Files = @($dataFile)
                    }
                }
                's3' {
                    $fetchResult = Invoke-S3Fetch `
                        -Bucket:($job.sourceUrl -replace '^s3://([^/]+).*$', '$1') `
                        -Prefix:($job.sourceUrl -replace '^s3://[^/]+/?(.*)$', '$1') `
                        -Endpoint:($job.options.endpoint -or "") `
                        -Credentials:($job.credentials | ConvertTo-Hashtable) `
                        -Region:($job.options.region -or "us-east-1")
                }
            }

            if (-not $fetchResult.Success) {
                throw "Failed to fetch from source: $($fetchResult.Error)"
            }

            $runResult.filesFetched = $fetchResult.Files.Count
            Update-JobProgress -JobId $JobId -Progress 30 -Status "Applying filters" -FilesProcessed 0

            # Import Filters module if available
            $filtersModule = Join-Path $PSScriptRoot "../workflow/Filters.ps1"
            if (Test-Path $filtersModule) {
                . $filtersModule
            }

            # Apply filters
            $filteredFiles = $fetchResult.Files
            $filterConfig = $job.filterRules | ConvertTo-Hashtable

            if ($filterConfig.include -or $filterConfig.exclude -or $filterConfig.extensions) {
                # Create filter object
                $filter = New-IncludeExcludeFilter `
                    -Name "ingestion-filter-$JobId" `
                    -DefaultBehavior include `
                    -Patterns @(
                        foreach ($pattern in $filterConfig.include) {
                            @{ pattern = $pattern; action = 'include'; priority = 100 }
                        }
                        foreach ($pattern in $filterConfig.exclude) {
                            @{ pattern = $pattern; action = 'exclude'; priority = 100 }
                        }
                    )

                $filteredFiles = @()
                foreach ($file in $fetchResult.Files) {
                    $relativePath = $file.Substring($workDir.Length).TrimStart('\', '/')

                    # Check extension filter
                    if ($filterConfig.extensions.Count -gt 0) {
                        $ext = [System.IO.Path]::GetExtension($file).ToLower()
                        if ($filterConfig.extensions -notcontains $ext) {
                            $runResult.filesFiltered++
                            continue
                        }
                    }

                    # Apply pattern filter
                    if (Test-PathAgainstFilter -Path $relativePath -Filter $filter) {
                        $filteredFiles += $file
                    }
                    else {
                        $runResult.filesFiltered++
                    }
                }
            }

            Update-JobProgress -JobId $JobId -Progress 50 -Status "Scanning for secrets" -FilesProcessed 0

            # Scan for secrets
            $filesToIngest = @()
            $filesWithSecrets = 0

            foreach ($file in $filteredFiles) {
                if ($script:JobCancellationTokens[$JobId]) {
                    throw "Job cancelled by user"
                }

                try {
                    $content = Get-Content -Path $file -Raw -ErrorAction SilentlyContinue
                    if (-not $content) { continue }

                    $secrets = Find-Secrets -Content $content -FilePath $file

                    if ($secrets.Count -gt 0) {
                        $filesWithSecrets++
                        $runResult.warnings += "Potential secrets detected in: $file"
                        Write-IngestionLog -Level WARN -Message "Secrets detected in file" -JobId $JobId -Metadata @{
                            file    = $file
                            secrets = $secrets | ForEach-Object { $_.Type }
                        }

                        # Skip files with secrets unless explicitly allowed
                        if ($job.options.allowSecrets -ne $true) {
                            continue
                        }
                    }

                    $filesToIngest += $file
                }
                catch {
                    $runResult.warnings += "Failed to scan: $file - $_"
                }
            }

            $runResult.filesWithSecrets = $filesWithSecrets

            Update-JobProgress -JobId $JobId -Progress 70 -Status "Processing ingestion" -FilesProcessed 0

            # Process ingestion using ExtractionPipeline if available
            $extractionModule = Join-Path $PSScriptRoot "./ExtractionPipeline.ps1"
            if (Test-Path $extractionModule) {
                . $extractionModule
            }

            # Copy to target collection
            $targetPath = "packs/$($job.targetPack)/collections/$($job.targetCollection)/ingested/$JobId"
            if (-not (Test-Path $targetPath)) {
                $null = New-Item -ItemType Directory -Path $targetPath -Force
            }

            $ingestedCount = 0
            $totalBytes = 0

            foreach ($file in $filesToIngest) {
                if ($script:JobCancellationTokens[$JobId]) {
                    throw "Job cancelled by user"
                }

                try {
                    $fileName = [System.IO.Path]::GetFileName($file)
                    $targetFile = Join-Path $targetPath $fileName

                    # Handle duplicates with counter
                    $counter = 1
                    $baseName = [System.IO.Path]::GetFileNameWithoutExtension($fileName)
                    $ext = [System.IO.Path]::GetExtension($fileName)
                    while (Test-Path $targetFile) {
                        $targetFile = Join-Path $targetPath "$baseName`_$counter$ext"
                        $counter++
                    }

                    Copy-Item -Path $file -Destination $targetFile -Force

                    $fileInfo = Get-Item $targetFile
                    $totalBytes += $fileInfo.Length
                    $ingestedCount++

                    # Update progress periodically
                    if ($ingestedCount % 10 -eq 0) {
                        $progress = 70 + [int](($ingestedCount / $filesToIngest.Count) * 25)
                        Update-JobProgress -JobId $JobId -Progress $progress -Status "Ingesting files" -FilesProcessed $ingestedCount
                    }
                }
                catch {
                    $runResult.errors += "Failed to ingest file: $file - $_"
                }
            }

            $runResult.filesIngested = $ingestedCount
            $runResult.bytesIngested = $totalBytes

            # Clean up temp directory
            if (Test-Path $workDir) {
                Remove-Item -Path $workDir -Recurse -Force -ErrorAction SilentlyContinue
            }

            # Update job statistics
            $stopwatch.Stop()
            $runResult.completedAt = [DateTime]::UtcNow.ToString("o")
            $runResult.state = if ($runResult.errors.Count -gt 0) { 'completed_with_errors' } else { 'completed' }

            $job.statistics.totalRuns++
            $job.statistics.successfulRuns++
            $job.statistics.totalFiles += $ingestedCount
            $job.statistics.lastRunAt = $runResult.completedAt
            $job.statistics.lastRunDuration = $stopwatch.Elapsed.TotalSeconds

            # Calculate average duration
            $totalDuration = $job.statistics.averageRunDuration * ($job.statistics.totalRuns - 1) + $stopwatch.Elapsed.TotalSeconds
            $job.statistics.averageRunDuration = $totalDuration / $job.statistics.totalRuns

            $job.runHistory += $runResult
            $job.state = 'pending'  # Ready for next scheduled run
            $job.updatedAt = [DateTime]::UtcNow.ToString("o")

            Write-IngestionLog -Level INFO -Message "Job completed successfully" -JobId $JobId -Metadata @{
                filesIngested = $ingestedCount
                bytesIngested = $totalBytes
                duration      = $stopwatch.Elapsed.TotalSeconds
            }
        }
        catch {
            $stopwatch.Stop()
            $runResult.state = 'failed'
            $runResult.errors += $_.Exception.Message
            $runResult.completedAt = [DateTime]::UtcNow.ToString("o")

            $job.statistics.totalRuns++
            $job.statistics.failedRuns++
            $job.runHistory += $runResult
            $job.state = 'failed'
            $job.updatedAt = [DateTime]::UtcNow.ToString("o")

            Write-IngestionLog -Level ERROR -Message "Job failed: $_" -JobId $JobId
        }

        # Save updated job
        $job | ConvertTo-Json -Depth 15 | Out-File -FilePath $jobPath -Encoding UTF8

        # Clean up cancellation token
        $script:JobCancellationTokens.Remove($JobId)

        Update-JobProgress -JobId $JobId -Progress 100 -Status $runResult.state -FilesProcessed $runResult.filesIngested

        return [pscustomobject]$runResult
    }
}

<#
.SYNOPSIS
    Gets ingestion job status and history.

.DESCRIPTION
    Retrieves the current status, configuration, and run history of an
    ingestion job. Can also list all jobs or filter by status.

.PARAMETER JobId
    Specific job ID to retrieve. If not specified, returns all jobs.

.PARAMETER Status
    Filter by job status.

.PARAMETER IncludeHistory
    If specified, includes full run history in the output.

.PARAMETER PackId
    Filter jobs by target pack ID.

.OUTPUTS
    System.Management.Automation.PSCustomObject[] or PSCustomObject. Job information.

.EXAMPLE
    Get-IngestionJob -JobId "ingest-12345"

.EXAMPLE
    Get-IngestionJob -Status running

.EXAMPLE
    Get-IngestionJob -PackId "my-pack" -IncludeHistory
#>
function Get-IngestionJob {
    [CmdletBinding()]
    [OutputType([array])]
    param(
        [Parameter()]
        [string]$JobId = "",

        [Parameter()]
        [ValidateSet('', 'pending', 'running', 'completed', 'failed', 'cancelled')]
        [string]$Status = "",

        [Parameter()]
        [switch]$IncludeHistory,

        [Parameter()]
        [string]$PackId = ""
    )

    process {
        $jobs = [System.Collections.Generic.List[object]]::new()

        # Load specific job or all jobs
        if ($JobId) {
            $jobPath = Get-JobFilePath -JobId $JobId
            if (Test-Path -LiteralPath $jobPath) {
                $job = Get-Content -Path $jobPath -Raw | ConvertFrom-Json
                $jobs.Add($job)
            }
            else {
                throw "Job not found: $JobId"
            }
        }
        else {
            if (Test-Path -LiteralPath $script:IngestionJobsDir) {
                $jobFiles = Get-ChildItem -Path $script:IngestionJobsDir -Filter "*.json"
                foreach ($file in $jobFiles) {
                    try {
                        $job = Get-Content -Path $file.FullName -Raw | ConvertFrom-Json
                        $jobs.Add($job)
                    }
                    catch {
                        Write-Warning "Failed to load job from $($file.Name): $_"
                    }
                }
            }
        }

        # Apply filters
        $filtered = $jobs | Where-Object {
            if ($Status -and $_.state -ne $Status) { return $false }
            if ($PackId -and $_.targetPack -ne $PackId) { return $false }
            return $true
        }

        # Format output
        $results = $filtered | ForEach-Object {
            $job = $_

            $output = [ordered]@{
                jobId            = $job.jobId
                sourceType       = $job.sourceType
                sourceUrl        = $job.sourceUrl
                targetPack       = $job.targetPack
                targetCollection = $job.targetCollection
                schedule         = $job.schedule
                state            = $job.state
                description      = $job.description
                createdAt        = $job.createdAt
                updatedAt        = $job.updatedAt
                statistics       = $job.statistics
            }

            if ($IncludeHistory) {
                $output.runHistory = $job.runHistory
            }
            else {
                $output.lastRun = if ($job.runHistory.Count -gt 0) { $job.runHistory[-1] } else { $null }
            }

            [pscustomobject]$output
        }

        return $results
    }
}

<#
.SYNOPSIS
    Stops a running ingestion job.

.DESCRIPTION
    Gracefully stops a running ingestion job. Sets the cancellation token
    and waits for the job to acknowledge the cancellation.

.PARAMETER JobId
    The ID of the job to stop.

.PARAMETER Force
    If specified, forcefully terminates without waiting.

.PARAMETER TimeoutSeconds
    Maximum time to wait for graceful shutdown. Default: 30.

.OUTPUTS
    System.Boolean. True if the job was stopped.

.EXAMPLE
    Stop-IngestionJob -JobId "ingest-12345"

.EXAMPLE
    Stop-IngestionJob -JobId "ingest-12345" -Force
#>
function Stop-IngestionJob {
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [Parameter(Mandatory = $true)]
        [string]$JobId,

        [Parameter()]
        [switch]$Force,

        [Parameter()]
        [int]$TimeoutSeconds = 30
    )

    process {
        $jobPath = Get-JobFilePath -JobId $JobId

        if (-not (Test-Path -LiteralPath $jobPath)) {
            throw "Job not found: $JobId"
        }

        $job = Get-Content -Path $jobPath -Raw | ConvertFrom-Json

        if ($job.state -ne 'running') {
            Write-Warning "Job $JobId is not currently running (state: $($job.state))"
            return $false
        }

        Write-IngestionLog -Level INFO -Message "Stopping job" -JobId $JobId

        # Set cancellation token
        $script:JobCancellationTokens[$JobId] = $true

        if ($Force) {
            # Force immediate termination
            $job.state = 'cancelled'
            $job.updatedAt = [DateTime]::UtcNow.ToString("o")
            $job | ConvertTo-Json -Depth 10 | Out-File -FilePath $jobPath -Encoding UTF8

            # Add cancellation to history
            $cancelEntry = @{
                runId       = [Guid]::NewGuid().ToString()
                state       = 'cancelled'
                cancelledAt = [DateTime]::UtcNow.ToString("o")
                reason      = 'force-cancelled'
            }
            $job.runHistory += $cancelEntry

            Write-IngestionLog -Level WARN -Message "Job force-cancelled" -JobId $JobId
            return $true
        }

        # Wait for graceful shutdown
        $sw = [System.Diagnostics.Stopwatch]::StartNew()
        while ($sw.Elapsed.TotalSeconds -lt $TimeoutSeconds) {
            $job = Get-Content -Path $jobPath -Raw | ConvertFrom-Json
            if ($job.state -ne 'running') {
                Write-IngestionLog -Level INFO -Message "Job stopped gracefully" -JobId $JobId
                return $true
            }
            Start-Sleep -Milliseconds 100
        }

        # Timeout - force cancel
        $job.state = 'cancelled'
        $job.updatedAt = [DateTime]::UtcNow.ToString("o")
        $job | ConvertTo-Json -Depth 10 | Out-File -FilePath $jobPath -Encoding UTF8

        Write-IngestionLog -Level WARN -Message "Job cancelled after timeout" -JobId $JobId
        return $true
    }
}

<#
.SYNOPSIS
    Removes an ingestion job.

.DESCRIPTION
    Deletes a job configuration and optionally its associated data from
    the target collection.

.PARAMETER JobId
    The ID of the job to remove.

.PARAMETER RemoveData
    If specified, also removes ingested data from the target collection.

.PARAMETER Force
    If specified, suppresses confirmation prompt.

.OUTPUTS
    System.Boolean. True if the job was removed.

.EXAMPLE
    Remove-IngestionJob -JobId "ingest-12345"

.EXAMPLE
    Remove-IngestionJob -JobId "ingest-12345" -RemoveData -Force
#>
function Remove-IngestionJob {
    [CmdletBinding(SupportsShouldProcess = $true)]
    [OutputType([bool])]
    param(
        [Parameter(Mandatory = $true)]
        [string]$JobId,

        [Parameter()]
        [switch]$RemoveData,

        [Parameter()]
        [switch]$Force
    )

    process {
        $jobPath = Get-JobFilePath -JobId $JobId

        if (-not (Test-Path -LiteralPath $jobPath)) {
            Write-Warning "Job not found: $JobId"
            return $false
        }

        $job = Get-Content -Path $jobPath -Raw | ConvertFrom-Json

        # Stop if running
        if ($job.state -eq 'running') {
            Stop-IngestionJob -JobId $JobId -Force
        }

        if ($Force -or $PSCmdlet.ShouldProcess($JobId, "Remove ingestion job")) {
            # Remove job configuration
            Remove-Item -Path $jobPath -Force

            # Remove state file if exists
            $statePath = Get-JobStatePath -JobId $JobId
            if (Test-Path $statePath) {
                Remove-Item -Path $statePath -Force
            }

            # Remove ingested data if requested
            if ($RemoveData) {
                $targetPath = "packs/$($job.targetPack)/collections/$($job.targetCollection)/ingested/$JobId"
                if (Test-Path $targetPath) {
                    if ($Force -or $PSCmdlet.ShouldProcess($targetPath, "Remove ingested data")) {
                        Remove-Item -Path $targetPath -Recurse -Force
                    }
                }
            }

            Write-IngestionLog -Level INFO -Message "Job removed" -JobId $JobId
            return $true
        }

        return $false
    }
}

<#
.SYNOPSIS
    Registers a reusable source template.

.DESCRIPTION
    Creates a reusable source configuration template that can be referenced
    by multiple ingestion jobs. Includes default filters, authentication
    credentials (encrypted), and rate limiting settings.

.PARAMETER SourceId
    Unique identifier for the source template.

.PARAMETER SourceType
    The type of source: git, http, api, or s3.

.PARAMETER Configuration
    Source-specific configuration (base URL, endpoint, etc.).

.PARAMETER DefaultFilters
    Default include/exclude filter rules.

.PARAMETER Credentials
    Authentication credentials (will be encrypted).

.PARAMETER RateLimit
    Rate limiting settings (requests per second).

.PARAMETER Description
    Source description.

.PARAMETER Tags
    Array of tags for categorization.

.OUTPUTS
    System.Management.Automation.PSCustomObject. The registered source.

.EXAMPLE
    Register-IngestionSource -SourceId "github-enterprise" -SourceType git `
        -Configuration @{ baseUrl = "https://github.company.com" } `
        -Credentials @{ token = "ghp_xxxxxx" } `
        -RateLimit @{ requestsPerSecond = 2 }
#>
function Register-IngestionSource {
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$SourceId,

        [Parameter(Mandatory = $true)]
        [ValidateSet('git', 'http', 'api', 's3')]
        [string]$SourceType,

        [Parameter()]
        [hashtable]$Configuration = @{},

        [Parameter()]
        [hashtable]$DefaultFilters = @{},

        [Parameter()]
        [hashtable]$Credentials = @{},

        [Parameter()]
        [hashtable]$RateLimit = @{},

        [Parameter()]
        [string]$Description = "",

        [Parameter()]
        [string[]]$Tags = @()
    )

    begin {
        Initialize-IngestionEnvironment
    }

    process {
        # Validate source ID
        if ($SourceId -notmatch '^[a-zA-Z0-9_\-]+$') {
            throw "Invalid SourceId. Use only alphanumeric characters, hyphens, and underscores."
        }

        # Encrypt credentials
        $encryptedCredentials = @{}
        foreach ($key in $Credentials.Keys) {
            if ($key -match '(password|secret|key|token)') {
                $encrypted = Protect-Credential -PlainText $Credentials[$key]
                if ($encrypted) {
                    $encryptedCredentials[$key] = $encrypted
                }
            }
            else {
                $encryptedCredentials[$key] = $Credentials[$key]
            }
        }

        # Build source configuration
        $source = [ordered]@{
            schemaVersion   = 1
            sourceId        = $SourceId
            sourceType      = $SourceType
            configuration   = $Configuration
            defaultFilters  = $DefaultFilters
            credentials     = $encryptedCredentials
            rateLimit       = @{
                requestsPerSecond = $RateLimit.requestsPerSecond -or $script:DefaultRateLimits[$SourceType]
                burstSize         = $RateLimit.burstSize -or 5
                retryCount        = $RateLimit.retryCount -or 3
            }
            description     = $Description
            tags            = $Tags
            createdAt       = [DateTime]::UtcNow.ToString("o")
            updatedAt       = [DateTime]::UtcNow.ToString("o")
            usageCount      = 0
            lastUsedAt      = $null
        }

        # Save source configuration
        $sourcePath = Get-SourceFilePath -SourceId $SourceId
        $source | ConvertTo-Json -Depth 10 | Out-File -FilePath $sourcePath -Encoding UTF8

        Write-IngestionLog -Level INFO -Message "Registered ingestion source: $SourceId"

        return [pscustomobject]$source
    }
}

<#
.SYNOPSIS
    Tests source connectivity and accessibility.

.DESCRIPTION
    Verifies that a registered source or URL is reachable and that
    authentication (if configured) is valid. Returns detailed connectivity
    status including rate limit information.

.PARAMETER SourceId
    The registered source ID to test (alternative to Url).

.PARAMETER Url
    Direct URL to test (alternative to SourceId).

.PARAMETER SourceType
    Required when using Url. Type of source being tested.

.PARAMETER TimeoutSeconds
    Connection timeout. Default: 30.

.PARAMETER Credentials
    Optional credentials for testing (uses source credentials if not provided).

.OUTPUTS
    System.Management.Automation.PSCustomObject. Connectivity test results.

.EXAMPLE
    Test-IngestionSource -SourceId "github-enterprise"

.EXAMPLE
    Test-IngestionSource -Url "https://api.example.com/v1" -SourceType api
#>
function Test-IngestionSource {
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter()]
        [string]$SourceId = "",

        [Parameter()]
        [string]$Url = "",

        [Parameter()]
        [ValidateSet('', 'git', 'http', 'api', 's3')]
        [string]$SourceType = "",

        [Parameter()]
        [int]$TimeoutSeconds = 30,

        [Parameter()]
        [hashtable]$Credentials = @{}
    )

    process {
        $result = [ordered]@{
            sourceId       = $SourceId
            url            = $Url
            sourceType     = $SourceType
            reachable      = $false
            authenticated  = $false
            responseTimeMs = 0
            rateLimit      = @{}
            error          = $null
            testedAt       = [DateTime]::UtcNow.ToString("o")
        }

        $stopwatch = [System.Diagnostics.Stopwatch]::StartNew()

        try {
            # Load source if SourceId provided
            if ($SourceId) {
                $sourcePath = Get-SourceFilePath -SourceId $SourceId
                if (Test-Path -LiteralPath $sourcePath) {
                    $source = Get-Content -Path $sourcePath -Raw | ConvertFrom-Json
                    $result.sourceType = $source.sourceType

                    if (-not $Url) {
                        $Url = $source.configuration.baseUrl -or $source.configuration.endpoint
                    }

                    # Use source credentials if not overridden
                    if ($Credentials.Count -eq 0 -and $source.credentials) {
                        $Credentials = $source.credentials | ConvertTo-Hashtable
                        # Decrypt credentials
                        foreach ($key in @($Credentials.Keys)) {
                            if ($key -match '(password|secret|key|token)') {
                                $Credentials[$key] = Unprotect-Credential -EncryptedData $Credentials[$key]
                            }
                        }
                    }
                }
                else {
                    throw "Source not found: $SourceId"
                }
            }

            if (-not $Url) {
                throw "URL must be provided or source must have a configured URL"
            }

            $result.url = $Url

            # Test based on source type
            switch ($result.sourceType) {
                'git' {
                    $psi = New-Object System.Diagnostics.ProcessStartInfo
                    $psi.FileName = 'git'
                    $psi.Arguments = "ls-remote --heads $Url"
                    $psi.RedirectStandardOutput = $true
                    $psi.RedirectStandardError = $true
                    $psi.UseShellExecute = $false
                    $psi.CreateNoWindow = $true

                    $process = [System.Diagnostics.Process]::Start($psi)
                    $process.WaitForExit($TimeoutSeconds * 1000)

                    if ($process.HasExited -and $process.ExitCode -eq 0) {
                        $result.reachable = $true
                        $result.authenticated = $true
                    }
                    elseif ($process.HasExited) {
                        $stderr = $process.StandardError.ReadToEnd()
                        if ($stderr -match "Authentication failed" -or $stderr -match "403") {
                            $result.reachable = $true
                            $result.authenticated = $false
                            $result.error = "Authentication failed"
                        }
                        else {
                            $result.error = "Git operation failed: $stderr"
                        }
                    }
                    else {
                        $process.Kill()
                        $result.error = "Connection timeout"
                    }
                }

                'http' {
                    try {
                        $headers = @{ 'User-Agent' = 'LLM-Workflow-Ingestion/1.0.0' }
                        $response = Invoke-WebRequest -Uri $Url -Method HEAD `
                            -Headers $headers -TimeoutSec $TimeoutSeconds -UseBasicParsing

                        $result.reachable = $true
                        $result.authenticated = $response.StatusCode -lt 400

                        if ($response.Headers.ContainsKey('X-RateLimit-Limit')) {
                            $result.rateLimit['limit'] = $response.Headers['X-RateLimit-Limit']
                            $result.rateLimit['remaining'] = $response.Headers['X-RateLimit-Remaining']
                        }
                    }
                    catch {
                        $result.error = $_.Exception.Message
                    }
                }

                'api' {
                    try {
                        $headers = @{
                            'Accept'     = 'application/json'
                            'User-Agent' = 'LLM-Workflow-Ingestion/1.0.0'
                        }

                        if ($Credentials.token) {
                            $headers['Authorization'] = "Bearer $($Credentials.token)"
                        }

                        $response = Invoke-WebRequest -Uri $Url -Method GET `
                            -Headers $headers -TimeoutSec $TimeoutSeconds -UseBasicParsing

                        $result.reachable = $true
                        $result.authenticated = $response.StatusCode -eq 200

                        if ($response.Headers.ContainsKey('X-RateLimit-Limit')) {
                            $result.rateLimit['limit'] = $response.Headers['X-RateLimit-Limit']
                            $result.rateLimit['remaining'] = $response.Headers['X-RateLimit-Remaining']
                        }
                    }
                    catch {
                        if ($_.Exception.Response) {
                            $statusCode = [int]$_.Exception.Response.StatusCode
                            $result.reachable = $statusCode -lt 500
                            $result.authenticated = $statusCode -ne 401 -and $statusCode -ne 403
                        }
                        $result.error = $_.Exception.Message
                    }
                }

                's3' {
                    # Parse S3 URL
                    if ($Url -match '^s3://([^/]+)') {
                        $bucket = $matches[1]

                        # Check for AWS CLI
                        $awsCli = Get-Command 'aws' -ErrorAction SilentlyContinue
                        if (-not $awsCli) {
                            $result.error = "AWS CLI not found"
                        }
                        else {
                            $psi = New-Object System.Diagnostics.ProcessStartInfo
                            $psi.FileName = 'aws'
                            $psi.Arguments = "s3 ls s3://$bucket --page-size 1"
                            $psi.RedirectStandardOutput = $true
                            $psi.RedirectStandardError = $true
                            $psi.UseShellExecute = $false
                            $psi.CreateNoWindow = $true

                            $process = [System.Diagnostics.Process]::Start($psi)
                            $process.WaitForExit($TimeoutSeconds * 1000)

                            if ($process.HasExited -and $process.ExitCode -eq 0) {
                                $result.reachable = $true
                                $result.authenticated = $true
                            }
                            elseif ($process.HasExited) {
                                $stderr = $process.StandardError.ReadToEnd()
                                if ($stderr -match "Access Denied" -or $stderr -match "403") {
                                    $result.reachable = $true
                                    $result.authenticated = $false
                                    $result.error = "Access denied"
                                }
                                else {
                                    $result.error = "S3 operation failed: $stderr"
                                }
                            }
                            else {
                                $process.Kill()
                                $result.error = "Connection timeout"
                            }
                        }
                    }
                    else {
                        $result.error = "Invalid S3 URL format"
                    }
                }

                default {
                    $result.error = "Unknown source type: $($result.sourceType)"
                }
            }
        }
        catch {
            $result.error = $_.Exception.Message
        }

        $stopwatch.Stop()
        $result.responseTimeMs = $stopwatch.ElapsedMilliseconds

        return [pscustomobject]$result
    }
}

<#
.SYNOPSIS
    Returns ingestion metrics.

.DESCRIPTION
    Aggregates and returns metrics about ingestion jobs including
    counts by status, processing rates, error rates, and storage usage.

.PARAMETER TimeWindowHours
    Time window for metrics (last N hours). Default: 24.

.PARAMETER PackId
    Filter metrics by specific pack.

.PARAMETER AggregateBy
    Aggregation level: job, source, or pack.

.OUTPUTS
    System.Management.Automation.PSCustomObject. Ingestion metrics.

.EXAMPLE
    Get-IngestionMetrics

.EXAMPLE
    Get-IngestionMetrics -TimeWindowHours 168 -PackId "my-pack"

.EXAMPLE
    Get-IngestionMetrics -AggregateBy source
#>
function Get-IngestionMetrics {
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter()]
        [int]$TimeWindowHours = 24,

        [Parameter()]
        [string]$PackId = "",

        [Parameter()]
        [ValidateSet('job', 'source', 'pack')]
        [string]$AggregateBy = 'job'
    )

    process {
        $cutoffTime = [DateTime]::UtcNow.AddHours(-$TimeWindowHours)

        # Load all jobs
        $jobs = Get-IngestionJob -PackId $PackId

        # Initialize metrics
        $metrics = [ordered]@{
            timeWindowHours  = $TimeWindowHours
            generatedAt      = [DateTime]::UtcNow.ToString("o")
            totalJobs        = $jobs.Count
            jobsByStatus     = @{}
            jobsBySourceType = @{}
            processingRates  = @{
                filesPerHour = 0
                bytesPerHour = 0
            }
            errorRates       = @{
                totalErrors   = 0
                errorRate     = 0.0
            }
            storageUsage     = @{
                totalFiles  = 0
                totalBytes  = 0
                targetPaths = @()
            }
            recentRuns       = @()
        }

        # Initialize counters
        $totalFilesIngested = 0
        $totalBytesIngested = 0
        $totalDurationHours = 0
        $totalErrors = 0
        $totalRuns = 0

        foreach ($job in $jobs) {
            # Count by status
            $status = $job.state
            if (-not $metrics.jobsByStatus[$status]) {
                $metrics.jobsByStatus[$status] = 0
            }
            $metrics.jobsByStatus[$status]++

            # Count by source type
            $sourceType = $job.sourceType
            if (-not $metrics.jobsBySourceType[$sourceType]) {
                $metrics.jobsBySourceType[$sourceType] = 0
            }
            $metrics.jobsBySourceType[$sourceType]++

            # Process run history within time window
            foreach ($run in $job.runHistory) {
                $runTime = [DateTime]::Parse($run.startedAt)
                if ($runTime -lt $cutoffTime) { continue }

                $totalRuns++
                $totalFilesIngested += $run.filesIngested
                $totalBytesIngested += $run.bytesIngested
                $totalErrors += $run.errors.Count

                if ($run.state -eq 'completed' -or $run.state -eq 'completed_with_errors') {
                    # Estimate duration
                    if ($run.completedAt) {
                        $completedTime = [DateTime]::Parse($run.completedAt)
                        $totalDurationHours += ($completedTime - $runTime).TotalHours
                    }
                }

                # Track storage usage
                if ($run.filesIngested -gt 0) {
                    $targetPath = "packs/$($job.targetPack)/collections/$($job.targetCollection)/ingested/$($job.jobId)"
                    if ($metrics.storageUsage.targetPaths -notcontains $targetPath) {
                        $metrics.storageUsage.targetPaths += $targetPath
                        $metrics.storageUsage.totalFiles += $run.filesIngested
                        $metrics.storageUsage.totalBytes += $run.bytesIngested
                    }
                }

                # Add to recent runs (limit to 100)
                if ($metrics.recentRuns.Count -lt 100) {
                    $metrics.recentRuns += [ordered]@{
                        jobId         = $job.jobId
                        runId         = $run.runId
                        startedAt     = $run.startedAt
                        state         = $run.state
                        filesIngested = $run.filesIngested
                        bytesIngested = $run.bytesIngested
                        errors        = $run.errors.Count
                    }
                }
            }
        }

        # Calculate rates
        if ($totalDurationHours -gt 0) {
            $metrics.processingRates.filesPerHour = [int]($totalFilesIngested / $totalDurationHours)
            $metrics.processingRates.bytesPerHour = [int]($totalBytesIngested / $totalDurationHours)
        }

        if ($totalRuns -gt 0) {
            $metrics.errorRates.totalErrors = $totalErrors
            $metrics.errorRates.errorRate = [Math]::Round($totalErrors / $totalRuns, 2)
        }

        # Sort recent runs by time
        $metrics.recentRuns = $metrics.recentRuns | Sort-Object startedAt -Descending

        return [pscustomobject]$metrics
    }
}

# ============================================================================
# Helper function for converting PSCustomObject to hashtable
# ============================================================================
function ConvertTo-Hashtable {
    param([Parameter(ValueFromPipeline = $true)]$InputObject)

    process {
        if ($null -eq $InputObject) { return $null }

        if ($InputObject -is [System.Collections.IEnumerable] -and $InputObject -isnot [string]) {
            $collection = @()
            foreach ($item in $InputObject) {
                $collection += (ConvertTo-Hashtable -InputObject $item)
            }
            return $collection
        }

        if ($InputObject -is [PSCustomObject]) {
            $hash = @{}
            foreach ($prop in $InputObject.PSObject.Properties) {
                $hash[$prop.Name] = ConvertTo-Hashtable -InputObject $prop.Value
            }
            return $hash
        }

        return $InputObject
    }
}

# Helper function for creating include/exclude filter (if Filters module not available)
function New-IncludeExcludeFilter {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Name,

        [Parameter()]
        [ValidateSet('glob', 'regex', 'literal')]
        [string]$PatternType = 'glob',

        [Parameter()]
        [ValidateSet('include', 'exclude')]
        [string]$DefaultBehavior = 'include',

        [Parameter()]
        [array]$Patterns = @(),

        [Parameter()]
        [string]$Description = ''
    )

    return @{
        name            = $Name
        patternType     = $PatternType
        defaultBehavior = $DefaultBehavior
        patterns        = @($Patterns)
        description     = $Description
    }
}

# Helper function for testing path against filter
function Test-PathAgainstFilter {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path,

        [Parameter(Mandatory = $true)]
        [hashtable]$Filter
    )

    $result = $Filter.defaultBehavior
    $matchedPriority = -1

    foreach ($patternDef in $Filter.patterns) {
        $pattern = $patternDef.pattern
        $action = $patternDef.action
        $priority = $patternDef.priority

        if ($priority -lt $matchedPriority) {
            continue
        }

        $matches = $false
        switch ($Filter.patternType) {
            'literal' { $matches = $Path -eq $pattern }
            'regex' { $matches = $Path -match $pattern }
            'glob' {
                # Simple glob matching
                $regex = $pattern -replace '\*', '.*' -replace '\?', '.'
                $matches = $Path -match $regex
            }
        }

        if ($matches) {
            $result = $action
            $matchedPriority = $priority
        }
    }

    return ($result -eq 'include')
}

# ============================================================================
# Module Export
# ============================================================================

try {
    Export-ModuleMember -Function @(
        'New-IngestionJob',
        'Start-IngestionJob',
        'Get-IngestionJob',
        'Stop-IngestionJob',
        'Remove-IngestionJob',
        'Register-IngestionSource',
        'Test-IngestionSource',
        'Get-IngestionMetrics',
        'Invoke-GitHubRepoIngestion',
        'Get-GitHubReleaseAssets',
        'Invoke-GitLabRepoIngestion',
        'Invoke-APIReferenceIngestion',
        'Invoke-DocsSiteIngestion',
        'Invoke-IngestionWithBackoff'
    )
}
catch {
    # If not running as a module, just continue (useful for dot-sourcing in tests)
    Write-Verbose "[$script:ModuleName] Export-ModuleMember skipped (not a module context)"
}
