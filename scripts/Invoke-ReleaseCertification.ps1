#requires -Version 5.1
<#
.SYNOPSIS
    Runs the full v1.0 release certification suite for LLMWorkflow.

.DESCRIPTION
    Evaluates release readiness across all categories defined in
    docs/V1_RELEASE_CRITERIA.md and produces structured JSON and Markdown
    certification reports.

    Functions:
    - Invoke-ReleaseCertification: runs all checks and outputs a report
    - Test-ReleaseCriteria: returns a boolean result for each category
    - Export-CertificationReport: writes JSON and Markdown reports to disk

.PARAMETER ProjectRoot
    The root directory of the LLMWorkflow project to certify.
    Defaults to the current working directory.

.PARAMETER OutputPath
    Directory where certification reports will be written.
    Defaults to "certification-reports".

.EXAMPLE
    .\Invoke-ReleaseCertification.ps1 -ProjectRoot . -OutputPath .\reports

.EXAMPLE
    Invoke-ReleaseCertification -ProjectRoot F:\LLMWorkflow -OutputPath F:\reports

.OUTPUTS
    System.Management.Automation.PSCustomObject
    A structured certification report with per-category results and overall pass/fail.

.NOTES
    File: Invoke-ReleaseCertification.ps1
    Version: 1.0.0
    Author: LLM Workflow Team
    Compatible with: PowerShell 5.1+
#>

Set-StrictMode -Version Latest

#region Private Helpers

function Test-FileExists {
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path
    )
    return (Test-Path -LiteralPath $Path)
}

function Test-DirectoryHasFiles {
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Directory,

        [Parameter(Mandatory = $true)]
        [string]$Filter
    )

    if (-not (Test-Path -LiteralPath $Directory)) {
        return $false
    }

    $files = Get-ChildItem -Path $Directory -Filter $Filter -ErrorAction SilentlyContinue
    $fileList = @($files)
    return ($fileList.Count -gt 0)
}

function Get-CertificationStatus {
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory = $true)]
        [bool]$Passed
    )

    if ($Passed) { return 'PASS' }
    return 'FAIL'
}

#endregion

#region Public Functions

function Test-ReleaseCriteria {
    <#
    .SYNOPSIS
        Evaluates each release certification category and returns boolean results.

    .DESCRIPTION
        Performs existence and content checks for documentation, observability,
        policy, ingestion, security, durable execution, MCP governance, retrieval,
        and CI validation artifacts.

    .PARAMETER ProjectRoot
        Root path of the project to evaluate.

    .OUTPUTS
        System.Management.Automation.PSCustomObject
        Boolean results per category and an overall Passed flag.
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter()]
        [string]$ProjectRoot = (Get-Location).Path
    )

    if (-not (Test-Path -LiteralPath $ProjectRoot)) {
        throw "Project root not found: $ProjectRoot"
    }

    $moduleRoot = Join-Path $ProjectRoot "module\LLMWorkflow"
    $docsRoot = Join-Path $ProjectRoot "docs"
    $scriptsRoot = Join-Path $ProjectRoot "scripts"
    $policyRoot = Join-Path $ProjectRoot "policy"
    $ciRoot = Join-Path $ProjectRoot "tools\ci"

    # --- Documentation Truth ---
    $versionPath = Join-Path $ProjectRoot "VERSION"
    $versionExists = Test-FileExists -Path $versionPath
    $versionNotEmpty = $false
    if ($versionExists) {
        $versionContent = Get-Content -LiteralPath $versionPath -Raw -ErrorAction SilentlyContinue
        $versionNotEmpty = -not [string]::IsNullOrWhiteSpace($versionContent)
    }

    $requiredDocs = @(
        'V1_RELEASE_CRITERIA.md',
        'RELEASE_CERTIFICATION_CHECKLIST.md',
        'RELEASE_STATE.md',
        'DOCS_TRUTH_MATRIX.md',
        'DOCUMENT_INGESTION_MODEL.md',
        'GAME_ASSET_INGESTION_MODEL.md',
        'SECURITY_BASELINE.md',
        'SUPPLY_CHAIN_POLICY.md',
        'POLICY_RUNTIME_MODEL.md',
        'OBSERVABILITY_ARCHITECTURE.md',
        'EVALUATION_OPERATIONS.md',
        'SELF_HEALING.md'
    )

    $allDocsExist = $true
    foreach ($doc in $requiredDocs) {
        $docPath = Join-Path $docsRoot $doc
        if (-not (Test-FileExists -Path $docPath)) {
            $allDocsExist = $false
            break
        }
    }

    $documentationTruth = $versionExists -and $versionNotEmpty -and $allDocsExist

    # --- Observability ---
    $observability = (
        (Test-FileExists -Path (Join-Path $moduleRoot "telemetry\SpanFactory.ps1")) -and
        (Test-FileExists -Path (Join-Path $moduleRoot "telemetry\TraceEnvelope.ps1")) -and
        (Test-FileExists -Path (Join-Path $moduleRoot "telemetry\OpenTelemetryBridge.ps1"))
    )

    # --- Policy ---
    $policy = (
        (Test-FileExists -Path (Join-Path $moduleRoot "policy\PolicyAdapter.ps1")) -and
        (Test-DirectoryHasFiles -Directory (Join-Path $policyRoot "opa") -Filter "*.rego")
    )

    # --- Document Ingestion ---
    $documentIngestion = (
        (Test-FileExists -Path (Join-Path $moduleRoot "ingestion\DoclingAdapter.ps1")) -and
        (Test-FileExists -Path (Join-Path $moduleRoot "ingestion\TikaAdapter.ps1")) -and
        (Test-FileExists -Path (Join-Path $moduleRoot "ingestion\DocumentNormalizer.ps1"))
    )

    # --- Game Asset Ingestion ---
    $gameAssetIngestion = (
        (Test-FileExists -Path (Join-Path $moduleRoot "extraction\SpriteSheetParser.ps1")) -and
        (Test-FileExists -Path (Join-Path $moduleRoot "ingestion\MarketplaceProvenanceNormalizer.ps1"))
    )

    # --- Security ---
    $security = (
        (Test-FileExists -Path (Join-Path $scriptsRoot "security\Invoke-SecurityBaseline.ps1")) -and
        (Test-FileExists -Path (Join-Path $scriptsRoot "security\Invoke-SBOMBuild.ps1")) -and
        (Test-FileExists -Path (Join-Path $scriptsRoot "security\Invoke-SecretScan.ps1")) -and
        (Test-FileExists -Path (Join-Path $scriptsRoot "security\Invoke-VulnerabilityScan.ps1"))
    )

    # --- Durable Execution ---
    $durableExecution = Test-FileExists -Path (Join-Path $moduleRoot "workflow\DurableOrchestrator.ps1")

    # --- MCP Governance ---
    $mcpGovernance = (
        (Test-FileExists -Path (Join-Path $moduleRoot "mcp\MCPToolRegistry.ps1")) -and
        (Test-FileExists -Path (Join-Path $moduleRoot "mcp\MCPToolLifecycle.ps1"))
    )

    # --- Retrieval Backend ---
    $retrievalBackend = Test-FileExists -Path (Join-Path $moduleRoot "retrieval\RetrievalBackendAdapter.ps1")

    # --- CI Validation ---
    $ciValidation = Test-FileExists -Path (Join-Path $ciRoot "validate-docs-truth.ps1")

    $overallPassed = (
        $documentationTruth -and
        $observability -and
        $policy -and
        $documentIngestion -and
        $gameAssetIngestion -and
        $security -and
        $durableExecution -and
        $mcpGovernance -and
        $retrievalBackend -and
        $ciValidation
    )

    return [pscustomobject]@{
        ProjectRoot = (Resolve-Path -LiteralPath $ProjectRoot).Path
        Timestamp = [DateTime]::UtcNow.ToString('yyyy-MM-ddTHH:mm:ssZ')
        OverallPassed = $overallPassed
        Categories = [ordered]@{
            DocumentationTruth = $documentationTruth
            Observability = $observability
            Policy = $policy
            DocumentIngestion = $documentIngestion
            GameAssetIngestion = $gameAssetIngestion
            Security = $security
            DurableExecution = $durableExecution
            MCPGovernance = $mcpGovernance
            RetrievalBackend = $retrievalBackend
            CIValidation = $ciValidation
        }
    }
}

function Export-CertificationReport {
    <#
    .SYNOPSIS
        Writes the certification report to JSON and Markdown files.

    .DESCRIPTION
        Serializes the certification report object to JSON and generates a
        human-readable Markdown summary suitable for attaching to release
        certification checklists.

    .PARAMETER Report
        The PSCustomObject returned by Test-ReleaseCriteria or Invoke-ReleaseCertification.

    .PARAMETER OutputPath
        Directory where the reports will be written.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [pscustomobject]$Report,

        [Parameter()]
        [string]$OutputPath = "certification-reports"
    )

    if (-not (Test-Path -LiteralPath $OutputPath)) {
        New-Item -ItemType Directory -Path $OutputPath -Force | Out-Null
    }

    $resolvedOutput = Resolve-Path -LiteralPath $OutputPath
    $timestamp = [DateTime]::UtcNow.ToString('yyyy-MM-ddTHH-mm-ssZ')
    $baseName = "certification-report-$timestamp"

    # JSON report
    $jsonPath = Join-Path $resolvedOutput "$baseName.json"
    $Report | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $jsonPath -Encoding UTF8

    # Markdown report
    $mdPath = Join-Path $resolvedOutput "$baseName.md"
    $overallStatus = Get-CertificationStatus -Passed $Report.OverallPassed

    $mdLines = [System.Collections.Generic.List[string]]::new()
    $mdLines.Add("# LLMWorkflow v1.0 Certification Report")
    $mdLines.Add("")
    $mdLines.Add("- **Project Root:** $($Report.ProjectRoot)")
    $mdLines.Add("- **Timestamp:** $($Report.Timestamp)")
    $mdLines.Add("- **Overall Status:** $overallStatus")
    $mdLines.Add("")
    $mdLines.Add("## Category Results")
    $mdLines.Add("")
    $mdLines.Add("| Category | Status |")
    $mdLines.Add("|----------|--------|")

    foreach ($category in $Report.Categories.Keys) {
        $passed = $Report.Categories[$category]
        $status = Get-CertificationStatus -Passed $passed
        $mdLines.Add("| $category | $status |")
    }

    $mdLines.Add("")
    $mdLines.Add("## Details")
    $mdLines.Add("")
    if ($Report.OverallPassed) {
        $mdLines.Add("All certification criteria passed. The release candidate is cleared for promotion to v1.0.")
    }
    else {
        $mdLines.Add("One or more certification criteria failed. Release promotion is **blocked** until all categories pass.")
        $mdLines.Add("")
        $mdLines.Add("### Failed Categories")
        $mdLines.Add("")
        foreach ($category in $Report.Categories.Keys) {
            if (-not $Report.Categories[$category]) {
                $mdLines.Add("- $category")
            }
        }
    }

    $mdLines.Add("")
    $mdLines.Add("---")
    $mdLines.Add("*Generated by Invoke-ReleaseCertification.ps1*")

    $mdLines -join "`r`n" | Set-Content -LiteralPath $mdPath -Encoding UTF8

    Write-Host "[Export-CertificationReport] JSON report written to: $jsonPath" -ForegroundColor Cyan
    Write-Host "[Export-CertificationReport] Markdown report written to: $mdPath" -ForegroundColor Cyan

    return [pscustomobject]@{
        JsonPath = $jsonPath
        MarkdownPath = $mdPath
    }
}

function Invoke-ReleaseCertification {
    <#
    .SYNOPSIS
        Runs the full release certification suite and produces a report.

    .DESCRIPTION
        Executes Test-ReleaseCriteria across all defined categories, then exports
        the results to JSON and Markdown via Export-CertificationReport.

    .PARAMETER ProjectRoot
        Root directory of the project to certify. Defaults to the current location.

    .PARAMETER OutputPath
        Directory for the generated reports. Defaults to "certification-reports".

    .OUTPUTS
        System.Management.Automation.PSCustomObject
        The full certification report including per-category results and report file paths.
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter()]
        [string]$ProjectRoot = (Get-Location).Path,

        [Parameter()]
        [string]$OutputPath = "certification-reports"
    )

    Write-Host "[Invoke-ReleaseCertification] Starting certification for: $ProjectRoot" -ForegroundColor Cyan

    $criteria = Test-ReleaseCriteria -ProjectRoot $ProjectRoot

    Write-Host "[Invoke-ReleaseCertification] Certification evaluation complete." -ForegroundColor Cyan
    foreach ($category in $criteria.Categories.Keys) {
        $status = Get-CertificationStatus -Passed $criteria.Categories[$category]
        $color = if ($criteria.Categories[$category]) { 'Green' } else { 'Red' }
        Write-Host "  $category : $status" -ForegroundColor $color
    }

    $overallStatus = Get-CertificationStatus -Passed $criteria.OverallPassed
    $overallColor = if ($criteria.OverallPassed) { 'Green' } else { 'Red' }
    Write-Host "[Invoke-ReleaseCertification] Overall: $overallStatus" -ForegroundColor $overallColor

    $reportPaths = Export-CertificationReport -Report $criteria -OutputPath $OutputPath

    $result = [pscustomobject]@{
        ProjectRoot = $criteria.ProjectRoot
        Timestamp = $criteria.Timestamp
        OverallPassed = $criteria.OverallPassed
        Categories = $criteria.Categories
        ReportPaths = $reportPaths
    }

    return $result
}

#endregion

# Export module members when loaded as a module
if ($ExecutionContext.SessionState.Module) {
    Export-ModuleMember -Function @(
        'Invoke-ReleaseCertification',
        'Test-ReleaseCriteria',
        'Export-CertificationReport'
    )
}
