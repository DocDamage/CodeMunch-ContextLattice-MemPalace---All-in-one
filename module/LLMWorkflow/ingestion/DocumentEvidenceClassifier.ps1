#requires -Version 5.1
<#
.SYNOPSIS
    Classifies document extraction quality for evidence use.

.DESCRIPTION
    Evaluates document extraction results and assigns quality scores for:
    - OCR quality (text readability and completeness)
    - Structural preservation (page boundaries, headings, lists)
    - Source authority (document origin and format trustworthiness)

    Low-quality extractions can be flagged for quarantine or fallback routing.

.PARAMETER NormalizedDocument
    Normalized document output hashtable.

.PARAMETER MinimumQualityThreshold
    Minimum overall score (0.0-1.0) for the document to pass evidence quality.

.OUTPUTS
    System.Collections.Hashtable. Quality classification result.

.NOTES
    File Name      : DocumentEvidenceClassifier.ps1
    Author         : LLM Workflow Team
    Version        : 1.0.0
    Prerequisite   : PowerShell 5.1+
    Copyright      : (c) 2026 LLM Workflow Project
    License        : MIT
#>

Set-StrictMode -Version Latest

$script:ModuleVersion = '1.0.0'
$script:ModuleName = 'DocumentEvidenceClassifier'

<#
.SYNOPSIS
    Creates a new document evidence classifier configuration.

.DESCRIPTION
    Returns a hashtable with classifier settings including score weights
    and minimum thresholds.

.PARAMETER MinimumQualityThreshold
    Minimum overall score for passing evidence quality.

.PARAMETER OcrWeight
    Weight for the OCR quality component.

.PARAMETER StructuralWeight
    Weight for the structural preservation component.

.PARAMETER AuthorityWeight
    Weight for the source authority component.

.OUTPUTS
    System.Collections.Hashtable. Classifier configuration object.
#>
function New-DocumentEvidenceClassifier {
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [Parameter()]
        [double]$MinimumQualityThreshold = 0.60,

        [Parameter()]
        [double]$OcrWeight = 0.40,

        [Parameter()]
        [double]$StructuralWeight = 0.35,

        [Parameter()]
        [double]$AuthorityWeight = 0.25
    )

    return [ordered]@{
        classifierName = 'DocumentEvidenceClassifier'
        classifierVersion = $script:ModuleVersion
        minimumQualityThreshold = $MinimumQualityThreshold
        ocrWeight = $OcrWeight
        structuralWeight = $StructuralWeight
        authorityWeight = $AuthorityWeight
        createdAt = [DateTime]::UtcNow.ToString('o')
    }
}

<#
.SYNOPSIS
    Tests whether a normalized document meets evidence quality standards.

.DESCRIPTION
    Calculates the overall evidence quality score and returns a boolean
    indicating whether the document passes the configured threshold.
    Also returns detailed scores and any issues found.

.PARAMETER NormalizedDocument
    Normalized document output hashtable.

.PARAMETER Classifier
    Classifier configuration from New-DocumentEvidenceClassifier.

.OUTPUTS
    System.Boolean. $true if the document meets quality standards.
#>
function Test-DocumentEvidenceQuality {
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [Parameter(Mandatory = $true, Position = 0)]
        [hashtable]$NormalizedDocument,

        [Parameter()]
        [hashtable]$Classifier = (New-DocumentEvidenceClassifier)
    )

    $scoreResult = Get-DocumentEvidenceScore -NormalizedDocument $NormalizedDocument -Classifier $Classifier
    return [bool]$scoreResult.passed
}

<#
.SYNOPSIS
    Gets detailed evidence quality scores for a normalized document.

.DESCRIPTION
    Computes and returns individual and overall quality scores:
    - ocrQuality: based on text density, empty pages, and engine confidence
    - structuralPreservation: based on chunk/page alignment and formatting hints
    - sourceAuthority: based on file format and engine reputation

.PARAMETER NormalizedDocument
    Normalized document output hashtable.

.PARAMETER Classifier
    Classifier configuration from New-DocumentEvidenceClassifier.

.OUTPUTS
    System.Collections.Hashtable. Detailed score result.
#>
function Get-DocumentEvidenceScore {
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [Parameter(Mandatory = $true, Position = 0)]
        [hashtable]$NormalizedDocument,

        [Parameter()]
        [hashtable]$Classifier = (New-DocumentEvidenceClassifier)
    )

    $pages = @()
    if ($NormalizedDocument.Contains('pages')) { $pages = @($NormalizedDocument.pages) }
    $chunks = @()
    if ($NormalizedDocument.Contains('chunks')) { $chunks = @($NormalizedDocument.chunks) }
    $engine = if ($NormalizedDocument.Contains('engine')) { [string]$NormalizedDocument.engine } else { 'unknown' }
    $format = if ($NormalizedDocument.Contains('format')) { [string]$NormalizedDocument.format } else { '' }
    $success = if ($NormalizedDocument.Contains('success')) { [bool]$NormalizedDocument.success } else { $false }
    $confidence = if ($NormalizedDocument.Contains('confidence')) { [double]$NormalizedDocument.confidence } else { 0.0 }
    $errors = @()
    if ($NormalizedDocument.Contains('errors')) { $errors = @($NormalizedDocument.errors) }

    $issues = @()

    if (-not $success) {
        $issues += @{ type = 'extraction-failed'; severity = 'critical'; description = 'Document extraction reported failure.' }
    }

    if ($errors.Count -gt 0) {
        $issues += @{ type = 'extraction-errors'; severity = 'high'; description = "Extraction produced $($errors.Count) error(s)."; count = $errors.Count }
    }

    # OCR Quality
    $ocrScore = 0.0
    if ($success -and $pages.Count -gt 0) {
        $totalPageChars = 0
        $emptyPages = 0
        foreach ($page in $pages) {
            $pageText = if ($page -is [hashtable] -and $page.Contains('text')) { $page.text } elseif ($null -ne $page.text) { $page.text } else { '' }
            $len = $pageText.Length
            $totalPageChars += $len
            if ($len -lt 20) { $emptyPages++ }
        }

        $averageCharsPerPage = $totalPageChars / $pages.Count
        $emptyPageRatio = if ($pages.Count -gt 0) { $emptyPages / $pages.Count } else { 0 }

        $ocrScore = [math]::Min(1.0, $averageCharsPerPage / 1000.0)
        $ocrScore = $ocrScore * (1.0 - $emptyPageRatio)
        $ocrScore = $ocrScore * $confidence

        if ($emptyPageRatio -gt 0.3) {
            $issues += @{ type = 'low-ocr-yield'; severity = 'high'; description = "$emptyPages of $($pages.Count) pages appear nearly empty."; emptyPageRatio = $emptyPageRatio }
        }
        elseif ($emptyPageRatio -gt 0.1) {
            $issues += @{ type = 'moderate-ocr-yield'; severity = 'medium'; description = "Some pages have very low text content."; emptyPageRatio = $emptyPageRatio }
        }
    }
    else {
        $issues += @{ type = 'no-pages'; severity = 'critical'; description = 'No pages were extracted from the document.' }
    }

    # Structural Preservation
    $structuralScore = 0.0
    if ($pages.Count -gt 0) {
        $structuralScore = [math]::Min(1.0, $pages.Count / 10.0) * 0.3

        # Reward chunk alignment with pages
        if ($chunks.Count -ge $pages.Count) {
            $structuralScore += 0.35
        }
        elseif ($chunks.Count -gt 0) {
            $structuralScore += 0.15
        }

        # Check for formatting hints (headings, lists) in text
        $sampleText = ($pages | ForEach-Object { if ($_ -is [hashtable] -and $_.Contains('text')) { $_.text } elseif ($null -ne $_.text) { $_.text } else { '' } }) -join "`n"
        $hasHeadings = $sampleText -match '^#{1,6}\s' -or $sampleText -match "`r?`n[A-Z][A-Z\s]{2,}[`r?`n]"
        $hasLists = $sampleText -match '^\s*[-*\d]\.' -or $sampleText -match "`r?`n\s*[-*\d]\."

        if ($hasHeadings) { $structuralScore += 0.175 }
        if ($hasLists) { $structuralScore += 0.175 }
    }
    $structuralScore = [math]::Min(1.0, $structuralScore)

    # Source Authority
    $authorityScore = 0.0
    $formatAuthorityMap = @{
        'pdf' = 1.0
        'docx' = 0.95
        'pptx' = 0.90
        'xlsx' = 0.90
        'odt' = 0.85
        'odp' = 0.85
        'ods' = 0.85
        'html' = 0.70
        'htm' = 0.70
        'txt' = 0.80
        'rtf' = 0.75
        'epub' = 0.80
    }

    $authorityScore = if ($formatAuthorityMap.Contains($format.ToLower())) { $formatAuthorityMap[$format.ToLower()] } else { 0.60 }

    $engineAuthorityMap = @{
        'docling' = 1.0
        'tika' = 0.85
        'docling-unavailable' = 0.0
        'tika-unavailable' = 0.0
        'unknown' = 0.50
    }

    if ($engineAuthorityMap.Contains($engine.ToLower())) {
        $authorityScore = $authorityScore * $engineAuthorityMap[$engine.ToLower()]
    }
    else {
        $authorityScore = $authorityScore * 0.70
    }

    $overallScore = ($ocrScore * $Classifier.ocrWeight) +
                    ($structuralScore * $Classifier.structuralWeight) +
                    ($authorityScore * $Classifier.authorityWeight)

    $passed = ($overallScore -ge $Classifier.minimumQualityThreshold) -and $success -and (@($issues | Where-Object { $_.severity -eq 'critical' }).Count -eq 0)

    if (-not $passed -and $success) {
        $desc = 'Overall score {0} is below threshold {1}.' -f ([math]::Round($overallScore,3)), $Classifier.minimumQualityThreshold
        $issues += @{ type = 'below-threshold'; severity = 'medium'; description = $desc }
    }

    return [ordered]@{
        passed = $passed
        overallScore = [math]::Round($overallScore, 4)
        scores = [ordered]@{
            ocrQuality = [math]::Round($ocrScore, 4)
            structuralPreservation = [math]::Round($structuralScore, 4)
            sourceAuthority = [math]::Round($authorityScore, 4)
        }
        weights = [ordered]@{
            ocrWeight = $Classifier.ocrWeight
            structuralWeight = $Classifier.structuralWeight
            authorityWeight = $Classifier.authorityWeight
        }
        threshold = $Classifier.minimumQualityThreshold
        issues = $issues
        engine = $engine
        format = $format
        pageCount = $pages.Count
        chunkCount = $chunks.Count
        evaluatedAt = [DateTime]::UtcNow.ToString('o')
        classifierVersion = $script:ModuleVersion
    }
}

if ($null -ne $MyInvocation.MyCommand.Module) {
if ($ExecutionContext.SessionState.Module) {
    Export-ModuleMember -Function @(
        'New-DocumentEvidenceClassifier',
        'Test-DocumentEvidenceQuality',
        'Get-DocumentEvidenceScore'
    )
}

}

