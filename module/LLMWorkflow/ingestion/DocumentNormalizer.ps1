#requires -Version 5.1
<#
.SYNOPSIS
    Normalizes document extraction output from multiple engines.

.DESCRIPTION
    Takes raw extraction results from Docling, Tika, or other document
    extraction engines and produces a consistent normalized schema.
    The normalized schema includes: sourcePath, format, pages[], chunks[],
    extractedAt, and engine.

    Also provides utilities for splitting documents by page and merging
    document chunks back together.

.PARAMETER ExtractionResult
    Raw extraction result hashtable from an engine adapter.

.PARAMETER EngineName
    Name of the engine that produced the extraction.

.PARAMETER PreferredChunkSize
    Target character count for each chunk when splitting.

.PARAMETER ChunkOverlap
    Number of overlapping characters between adjacent chunks.

.OUTPUTS
    System.Collections.Hashtable. Normalized document output.

.NOTES
    File Name      : DocumentNormalizer.ps1
    Author         : LLM Workflow Team
    Version        : 1.0.0
    Prerequisite   : PowerShell 5.1+
    Copyright      : (c) 2026 LLM Workflow Project
    License        : MIT
#>

Set-StrictMode -Version Latest

$script:ModuleVersion = '1.0.0'
$script:ModuleName = 'DocumentNormalizer'

<#
.SYNOPSIS
    Creates a new document normalizer configuration.

.DESCRIPTION
    Returns a hashtable with normalizer settings including default chunk size,
    overlap, and maximum page length.

.PARAMETER PreferredChunkSize
    Target size in characters for each chunk.

.PARAMETER ChunkOverlap
    Overlap size in characters between chunks.

.OUTPUTS
    System.Collections.Hashtable. Normalizer configuration object.
#>
function New-DocumentNormalizer {
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [Parameter()]
        [int]$PreferredChunkSize = 2000,

        [Parameter()]
        [int]$ChunkOverlap = 200
    )

    return [ordered]@{
        normalizerName = 'DocumentNormalizer'
        normalizerVersion = $script:ModuleVersion
        preferredChunkSize = $PreferredChunkSize
        chunkOverlap = $ChunkOverlap
        createdAt = [DateTime]::UtcNow.ToString('o')
    }
}

<#
.SYNOPSIS
    Normalizes a raw extraction result into the standard schema.

.DESCRIPTION
    Converts engine-specific extraction output into a consistent document
    envelope with sourcePath, format, pages[], chunks[], extractedAt, and engine.

.PARAMETER ExtractionResult
    Raw extraction result hashtable.

.PARAMETER EngineName
    Name of the extraction engine (e.g., 'docling', 'tika').

.PARAMETER Normalizer
    Normalizer configuration from New-DocumentNormalizer.

.OUTPUTS
    System.Collections.Hashtable. Normalized document envelope.
#>
function Normalize-DocumentOutput {
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [Parameter(Mandatory = $true, Position = 0)]
        [hashtable]$ExtractionResult,

        [Parameter(Mandatory = $true, Position = 1)]
        [string]$EngineName,

        [Parameter()]
        [hashtable]$Normalizer = (New-DocumentNormalizer)
    )

    $sourcePath = if ($ExtractionResult.Contains('sourcePath')) { $ExtractionResult.sourcePath } else { '' }
    $format = if ($ExtractionResult.Contains('format')) { $ExtractionResult.format } else { '' }
    $text = if ($ExtractionResult.Contains('text')) { $ExtractionResult.text } else { '' }
    $pages = @()
    if ($ExtractionResult.Contains('pages')) { $pages = @($ExtractionResult.pages) }
    $success = if ($ExtractionResult.Contains('success')) { [bool]$ExtractionResult.success } else { $false }
    $errors = @()
    if ($ExtractionResult.Contains('errors')) { $errors = @($ExtractionResult.errors) }
    $warnings = @()
    if ($ExtractionResult.Contains('warnings')) { $warnings = @($ExtractionResult.warnings) }
    $confidence = if ($ExtractionResult.Contains('confidence')) { [double]$ExtractionResult.confidence } else { 0.0 }
    $extractedAt = if ($ExtractionResult.Contains('extractedAt')) { $ExtractionResult.extractedAt } else { [DateTime]::UtcNow.ToString('o') }

    # Ensure pages are normalized
    $normalizedPages = @()
    if ($pages.Count -gt 0) {
        foreach ($page in $pages) {
            if ($page -is [hashtable]) {
                $normalizedPages += [ordered]@{
                    pageNumber = if ($page.Contains('pageNumber')) { [int]$page.pageNumber } else { $normalizedPages.Count + 1 }
                    text = if ($page.Contains('text')) { [string]$page.text } else { '' }
                }
            }
            elseif ($page -is [pscustomobject]) {
                $normalizedPages += [ordered]@{
                    pageNumber = if ($null -ne $page.pageNumber) { [int]$page.pageNumber } else { $normalizedPages.Count + 1 }
                    text = if ($null -ne $page.text) { [string]$page.text } else { '' }
                }
            }
        }
    }
    elseif (-not [string]::IsNullOrWhiteSpace($text)) {
        $normalizedPages = @([ordered]@{
            pageNumber = 1
            text = $text
        })
    }

    # Build chunks from pages
    $chunks = @()
    foreach ($page in $normalizedPages) {
        $pageChunks = Split-DocumentByPage -PageText $page.text -PageNumber $page.pageNumber -Normalizer $Normalizer
        foreach ($chunk in $pageChunks) {
            $chunks += $chunk
        }
    }

    return [ordered]@{
        sourcePath = $sourcePath
        format = $format
        engine = $EngineName
        success = $success
        confidence = $confidence
        pages = $normalizedPages
        chunks = $chunks
        errors = $errors
        warnings = $warnings
        extractedAt = $extractedAt
        normalizedAt = [DateTime]::UtcNow.ToString('o')
        normalizerVersion = $script:ModuleVersion
    }
}

<#
.SYNOPSIS
    Splits a single page of text into chunks.

.DESCRIPTION
    Breaks a page into smaller chunks respecting paragraph boundaries where
    possible. Each chunk includes chunkId, pageNumber, text, and charCount.

.PARAMETER PageText
    Text content of the page.

.PARAMETER PageNumber
    Page number to associate with the chunks.

.PARAMETER Normalizer
    Normalizer configuration from New-DocumentNormalizer.

.OUTPUTS
    System.Array. Array of chunk hashtables.
#>
function Split-DocumentByPage {
    [CmdletBinding()]
    [OutputType([array])]
    param(
        [Parameter(Mandatory = $true, Position = 0)]
        [AllowEmptyString()]
        [string]$PageText,

        [Parameter(Mandatory = $true, Position = 1)]
        [int]$PageNumber,

        [Parameter()]
        [hashtable]$Normalizer = (New-DocumentNormalizer)
    )

    if ([string]::IsNullOrWhiteSpace($PageText)) {
        return ,@()
    }

    $targetSize = $Normalizer.preferredChunkSize
    $overlap = $Normalizer.chunkOverlap
    $paragraphs = $PageText -split "`r?`n`r?`n"

    $chunks = @()
    $currentChunk = ''
    $chunkIndex = 1

    foreach ($paragraph in $paragraphs) {
        $trimmed = $paragraph.Trim()
        if ([string]::IsNullOrWhiteSpace($trimmed)) { continue }

        # If a single paragraph exceeds target size, force-split it
        if ($trimmed.Length -gt $targetSize) {
            if (-not [string]::IsNullOrWhiteSpace($currentChunk)) {
                $chunks += [ordered]@{
                    chunkId = "p${PageNumber}-c$chunkIndex"
                    pageNumber = $PageNumber
                    text = $currentChunk
                    charCount = $currentChunk.Length
                }
                $chunkIndex++
                $currentChunk = ''
            }

            $stride = $targetSize - $overlap
            if ($stride -le 0) { $stride = $targetSize }
            for ($i = 0; $i -lt $trimmed.Length; $i += $stride) {
                $len = [math]::Min($targetSize, $trimmed.Length - $i)
                $piece = $trimmed.Substring($i, $len)
                $chunks += [ordered]@{
                    chunkId = "p${PageNumber}-c$chunkIndex"
                    pageNumber = $PageNumber
                    text = $piece
                    charCount = $piece.Length
                }
                $chunkIndex++
            }
            continue
        }

        $proposed = if ([string]::IsNullOrWhiteSpace($currentChunk)) { $trimmed } else { "$currentChunk`n`n$trimmed" }

        if ($proposed.Length -le $targetSize -or $currentChunk.Length -eq 0) {
            $currentChunk = $proposed
        }
        else {
            # Flush current chunk
            $chunks += [ordered]@{
                chunkId = "p${PageNumber}-c$chunkIndex"
                pageNumber = $PageNumber
                text = $currentChunk
                charCount = $currentChunk.Length
            }
            $chunkIndex++

            # Start new chunk with overlap
            if ($overlap -gt 0 -and $currentChunk.Length -gt $overlap) {
                $overlapText = $currentChunk.Substring($currentChunk.Length - $overlap)
                $currentChunk = "$overlapText`n`n$trimmed"
            }
            else {
                $currentChunk = $trimmed
            }
        }
    }

    if (-not [string]::IsNullOrWhiteSpace($currentChunk)) {
        $chunks += [ordered]@{
            chunkId = "p${PageNumber}-c$chunkIndex"
            pageNumber = $PageNumber
            text = $currentChunk
            charCount = $currentChunk.Length
        }
    }

    return ,$chunks
}

<#
.SYNOPSIS
    Merges multiple document chunks back into a single text.

.DESCRIPTION
    Concatenates chunk texts in order, optionally adding page break markers
    when page boundaries are crossed.

.PARAMETER Chunks
    Array of chunk hashtables.

.PARAMETER IncludePageBreaks
    If specified, inserts a page break marker between different pages.

.OUTPUTS
    System.String. Merged text.
#>
function Merge-DocumentChunks {
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory = $true, Position = 0)]
        [array]$Chunks,

        [Parameter()]
        [switch]$IncludePageBreaks
    )

    if ($Chunks.Count -eq 0) {
        return ''
    }

    $parts = @()
    $lastPage = 0

    foreach ($chunk in $Chunks) {
        $pageNumber = if ($chunk -is [hashtable] -and $chunk.Contains('pageNumber')) { [int]$chunk.pageNumber } elseif ($null -ne $chunk.pageNumber) { [int]$chunk.pageNumber } else { 0 }
        $text = if ($chunk -is [hashtable] -and $chunk.Contains('text')) { [string]$chunk.text } elseif ($null -ne $chunk.text) { [string]$chunk.text } else { '' }

        if ($IncludePageBreaks -and $lastPage -ne 0 -and $pageNumber -ne $lastPage) {
            $parts += "`f" # form feed page break
        }

        $parts += $text
        $lastPage = $pageNumber
    }

    return $parts -join "`n`n"
}

if ($null -ne $MyInvocation.MyCommand.Module) {
if ($ExecutionContext.SessionState.Module) {
    Export-ModuleMember -Function @(
        'New-DocumentNormalizer',
        'Normalize-DocumentOutput',
        'Split-DocumentByPage',
        'Merge-DocumentChunks'
    )
}

}

