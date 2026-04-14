#requires -Version 5.1
<#
.SYNOPSIS
    PowerShell adapter for Apache Tika fallback document extraction.

.DESCRIPTION
    Provides an HTTP-based PowerShell interface to an Apache Tika server.
    Used as a fallback when Docling is unavailable or fails. Supports PDF,
    DOCX, PPTX, and additional formats that Tika handles.

.PARAMETER TikaUrl
    Base URL of the Tika server (e.g., http://localhost:9998).

.PARAMETER FilePath
    Path to the document file to extract.

.PARAMETER TimeoutSeconds
    HTTP request timeout.

.OUTPUTS
    System.Collections.Hashtable. Normalized extraction result.

.NOTES
    File Name      : TikaAdapter.ps1
    Author         : LLM Workflow Team
    Version        : 1.0.0
    Prerequisite   : PowerShell 5.1+, running Apache Tika server
    Copyright      : (c) 2026 LLM Workflow Project
    License        : MIT
#>

Set-StrictMode -Version Latest

$script:ModuleVersion = '1.0.0'
$script:ModuleName = 'TikaAdapter'
$script:SupportedFormats = @('.pdf', '.docx', '.pptx', '.xlsx', '.odt', '.ods', '.odp', '.rtf', '.txt', '.html', '.htm', '.epub')

<#
.SYNOPSIS
    Creates a new Tika adapter configuration.

.DESCRIPTION
    Returns a hashtable with Tika adapter settings including server URL
    and HTTP timeout values.

.PARAMETER TikaUrl
    Base URL of the Tika server.

.PARAMETER TimeoutSeconds
    Request timeout in seconds.

.OUTPUTS
    System.Collections.Hashtable. Adapter configuration object.
#>
function New-TikaAdapter {
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [Parameter()]
        [string]$TikaUrl = 'http://localhost:9998',

        [Parameter()]
        [int]$TimeoutSeconds = 120
    )

    $normalizedUrl = $TikaUrl.TrimEnd('/')
    if ($normalizedUrl -notmatch '^https?://') {
        $normalizedUrl = "http://$normalizedUrl"
    }

    return [ordered]@{
        adapterName = 'TikaAdapter'
        adapterVersion = $script:ModuleVersion
        tikaUrl = $normalizedUrl
        timeoutSeconds = $TimeoutSeconds
        supportedFormats = $script:SupportedFormats
        createdAt = [DateTime]::UtcNow.ToString('o')
    }
}

<#
.SYNOPSIS
    Tests whether the Apache Tika server is reachable.

.DESCRIPTION
    Sends a lightweight GET request to the Tika server root or /version
    to verify connectivity.

.PARAMETER Adapter
    Adapter configuration from New-TikaAdapter.

.OUTPUTS
    System.Boolean. $true if the Tika server responds.
#>
function Test-TikaAvailable {
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [Parameter()]
        [hashtable]$Adapter = (New-TikaAdapter)
    )

    try {
        $uri = "$($Adapter.tikaUrl)/version"
        $response = Invoke-WebRequest -Uri $uri -Method GET -TimeoutSec 10 -UseBasicParsing -ErrorAction Stop
        return ($response.StatusCode -eq 200)
    }
    catch {
        Write-Verbose "[$script:ModuleName] Tika availability check failed: $_"
        return $false
    }
}

<#
.SYNOPSIS
    Invokes Tika extraction on a document file via HTTP.

.DESCRIPTION
    Posts the document binary to the Tika /tika endpoint and returns
    normalized output with text, pages, and confidence metadata.
    If Tika is unreachable, returns a failure record with engine = 'tika-unavailable'.

.PARAMETER FilePath
    Path to the document file.

.PARAMETER Adapter
    Adapter configuration from New-TikaAdapter.

.PARAMETER Accept
    Preferred Accept header for Tika (text/plain by default).

.OUTPUTS
    System.Collections.Hashtable. Normalized extraction result.
#>
function Invoke-TikaExtraction {
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [Parameter(Mandatory = $true, Position = 0)]
        [Alias('Path')]
        [string]$FilePath,

        [Parameter()]
        [hashtable]$Adapter = (New-TikaAdapter),

        [Parameter()]
        [string]$Accept = 'text/plain'
    )

    $resolvedPath = Resolve-Path -Path $FilePath -ErrorAction SilentlyContinue | Select-Object -ExpandProperty Path
    if ([string]::IsNullOrWhiteSpace($resolvedPath) -or -not (Test-Path -LiteralPath $resolvedPath)) {
        return [ordered]@{
            success = $false
            engine = 'tika'
            sourcePath = $FilePath
            format = $null
            text = ''
            pages = @()
            confidence = 0.0
            errors = @("File not found: $FilePath")
            warnings = @()
            extractedAt = [DateTime]::UtcNow.ToString('o')
        }
    }

    $extension = [System.IO.Path]::GetExtension($resolvedPath).ToLower()
    if ($script:SupportedFormats -notcontains $extension) {
        return [ordered]@{
            success = $false
            engine = 'tika'
            sourcePath = $resolvedPath
            format = $extension.TrimStart('.')
            text = ''
            pages = @()
            confidence = 0.0
            errors = @("Unsupported format: $extension")
            warnings = @()
            extractedAt = [DateTime]::UtcNow.ToString('o')
        }
    }

    if (-not (Test-TikaAvailable -Adapter $Adapter)) {
        return [ordered]@{
            success = $false
            engine = 'tika-unavailable'
            sourcePath = $resolvedPath
            format = $extension.TrimStart('.')
            text = ''
            pages = @()
            confidence = 0.0
            errors = @('Tika server is not reachable.')
            warnings = @('Ensure the Apache Tika server is running at the configured URL.')
            extractedAt = [DateTime]::UtcNow.ToString('o')
        }
    }

    try {
        $uri = "$($Adapter.tikaUrl)/tika"
        $fileBytes = [System.IO.File]::ReadAllBytes($resolvedPath)

        $response = Invoke-WebRequest -Uri $uri -Method PUT -Body $fileBytes -ContentType 'application/octet-stream' -Headers @{
            Accept = $Accept
        } -TimeoutSec $Adapter.timeoutSeconds -UseBasicParsing -ErrorAction Stop

        $extractedText = [string]$response.Content

        # Approximate pages by splitting on form-feed or large paragraph gaps
        $rawPages = $extractedText -split "`f"
        if ($rawPages.Count -le 1) {
            $chunks = $extractedText -split "`r?`n`r?`n`r?`n"
            $rawPages = if ($chunks.Count -gt 0) { $chunks } else { @($extractedText) }
        }

        $pages = for ($i = 0; $i -lt $rawPages.Count; $i++) {
            [ordered]@{
                pageNumber = $i + 1
                text = $rawPages[$i].Trim()
            }
        }

        return [ordered]@{
            success = $true
            engine = 'tika'
            sourcePath = $resolvedPath
            format = $extension.TrimStart('.')
            text = $extractedText
            pages = @($pages)
            confidence = 0.75
            errors = @()
            warnings = @()
            extractedAt = [DateTime]::UtcNow.ToString('o')
        }
    }
    catch {
        Write-Verbose "[$script:ModuleName] Tika extraction failed: $_"
        return [ordered]@{
            success = $false
            engine = 'tika'
            sourcePath = $resolvedPath
            format = $extension.TrimStart('.')
            text = ''
            pages = @()
            confidence = 0.0
            errors = @("Tika extraction failed: $_")
            warnings = @()
            extractedAt = [DateTime]::UtcNow.ToString('o')
        }
    }
}

if ($null -ne $MyInvocation.MyCommand.Module) {
if ($ExecutionContext.SessionState.Module) {
    Export-ModuleMember -Function @(
        'New-TikaAdapter',
        'Invoke-TikaExtraction',
        'Test-TikaAvailable'
    )
}

}
