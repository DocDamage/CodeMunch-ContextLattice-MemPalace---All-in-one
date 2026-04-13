#requires -Version 5.1
Set-StrictMode -Version Latest

<#
.SYNOPSIS
    Orchestrates the full security baseline for the LLM Workflow platform.
.DESCRIPTION
    Runs secret scan, SBOM build, vulnerability scan, and produces a
    consolidated report. Accepts parameters to control output location
    and whether the pipeline should fail on critical findings.
    Safe to run without external security tools installed.
.NOTES
    File: Invoke-SecurityBaseline.ps1
    Version: 1.0.0
    Compatible with: PowerShell 5.1+
#>

#region Private Helpers

function Test-PromotionGate {
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory = $true)]
        [pscustomobject]$SecretScanReport,

        [Parameter(Mandatory = $true)]
        [pscustomobject]$VulnerabilityScanReport,

        [Parameter()]
        [int]$MaxAllowedCritical = 0,

        [Parameter()]
        [int]$MaxAllowedHigh = 0
    )

    $blockedBy = @()

    if ($SecretScanReport.summary.critical -gt $MaxAllowedCritical) {
        $blockedBy += "secrets-critical"
    }

    if ($SecretScanReport.summary.high -gt $MaxAllowedHigh) {
        $blockedBy += "secrets-high"
    }

    if ($VulnerabilityScanReport.summary.critical -gt $MaxAllowedCritical) {
        $blockedBy += "vulns-critical"
    }

    if ($VulnerabilityScanReport.summary.high -gt $MaxAllowedHigh) {
        $blockedBy += "vulns-high"
    }

    $passed = ($blockedBy.Count -eq 0)

    return [pscustomobject]@{
        Passed = $passed
        BlockedBy = $blockedBy
        Thresholds = [ordered]@{
            MaxAllowedCritical = $MaxAllowedCritical
            MaxAllowedHigh = $MaxAllowedHigh
        }
        SecretScan = [ordered]@{
            Critical = $SecretScanReport.summary.critical
            High = $SecretScanReport.summary.high
        }
        VulnerabilityScan = [ordered]@{
            Critical = $VulnerabilityScanReport.summary.critical
            High = $VulnerabilityScanReport.summary.high
        }
    }
}

function Import-SecurityScript {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Name
    )

    $scriptDir = $PSScriptRoot
    if ([string]::IsNullOrEmpty($scriptDir)) {
        $scriptDir = Join-Path (Get-Location).Path 'scripts' 'security'
    }

    $scriptPath = Join-Path $scriptDir $Name
    if (Test-Path -LiteralPath $scriptPath) {
        . $scriptPath
        return $true
    }

    return $false
}

#endregion

#region Public Functions

function Invoke-SecurityBaseline {
    <#
    .SYNOPSIS
        Orchestrates the full security baseline scan and reporting.
    .DESCRIPTION
        Executes secret scanning, SBOM generation, and vulnerability scanning.
        Produces individual reports and a consolidated security baseline report.
        Optionally fails when critical findings are detected.
    .PARAMETER ProjectRoot
        The root directory to scan. Defaults to the current working directory.
    .PARAMETER OutputPath
        Directory to write reports. Defaults to ./security-reports.
    .PARAMETER FailOnCritical
        If specified, throws an error when any critical finding is detected.
    .PARAMETER MaxAllowedCritical
        Maximum allowed critical findings before promotion is blocked. Default is 0.
    .PARAMETER MaxAllowedHigh
        Maximum allowed high findings before promotion is blocked. Default is 0.
    .EXAMPLE
        Invoke-SecurityBaseline -ProjectRoot . -OutputPath ./reports -FailOnCritical
    .OUTPUTS
        System.Management.Automation.PSCustomObject
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter()]
        [string]$ProjectRoot = (Get-Location).Path,

        [Parameter()]
        [string]$OutputPath = "security-reports",

        [Parameter()]
        [switch]$FailOnCritical,

        [Parameter()]
        [int]$MaxAllowedCritical = 0,

        [Parameter()]
        [int]$MaxAllowedHigh = 0
    )

    if (-not (Test-Path -LiteralPath $ProjectRoot)) {
        throw "Project root not found: $ProjectRoot"
    }

    if (-not (Test-Path -LiteralPath $OutputPath)) {
        New-Item -ItemType Directory -Path $OutputPath -Force | Out-Null
    }

    # Ensure dependent functions are available
    $scriptsToImport = @('Invoke-SecretScan.ps1', 'Invoke-SBOMBuild.ps1', 'Invoke-VulnerabilityScan.ps1')
    foreach ($scriptName in $scriptsToImport) {
        $imported = Import-SecurityScript -Name $scriptName
        if (-not $imported) {
            Write-Warning "[Invoke-SecurityBaseline] Could not import $scriptName"
        }
    }

    $resolvedOutput = Resolve-Path -LiteralPath $OutputPath
    $timestamp = [DateTime]::UtcNow.ToString('yyyy-MM-ddTHH-mm-ssZ')

    Write-Host "[Invoke-SecurityBaseline] Starting security baseline scan..." -ForegroundColor Cyan

    # Run secret scan
    Write-Host "[Invoke-SecurityBaseline] Running secret scan..."
    $secretReportPath = Join-Path $resolvedOutput "secret-scan-$timestamp.json"
    $secretReport = Invoke-SecretScan -ProjectRoot $ProjectRoot -OutputPath $secretReportPath

    # Run SBOM build
    Write-Host "[Invoke-SecurityBaseline] Building SBOM..."
    $sbomPath = Join-Path $resolvedOutput "sbom-$timestamp.json"
    $sbomResult = Invoke-SBOMBuild -ProjectRoot $ProjectRoot -OutputPath $sbomPath

    # Run vulnerability scan
    Write-Host "[Invoke-SecurityBaseline] Running vulnerability scan..."
    $vulnReportPath = Join-Path $resolvedOutput "vulnerability-scan-$timestamp.json"
    $vulnReport = Invoke-VulnerabilityScan -ProjectRoot $ProjectRoot -OutputPath $vulnReportPath

    # Evaluate promotion gate
    $promotionGate = Test-PromotionGate `
        -SecretScanReport $secretReport `
        -VulnerabilityScanReport $vulnReport `
        -MaxAllowedCritical $MaxAllowedCritical `
        -MaxAllowedHigh $MaxAllowedHigh

    $overallPassed = $promotionGate.Passed -and
                     ($secretReport.summary.totalFindings -eq 0 -or
                      ($secretReport.summary.critical -eq 0 -and -not $FailOnCritical))

    $consolidated = [pscustomobject]@{
        timestamp = [DateTime]::UtcNow.ToString('yyyy-MM-ddTHH:mm:ssZ')
        projectRoot = (Resolve-Path -LiteralPath $ProjectRoot).Path
        outputDirectory = $resolvedOutput.Path
        overallPassed = $overallPassed
        promotionGate = $promotionGate
        scans = [ordered]@{
            secretScan = [ordered]@{
                reportPath = $secretReportPath
                summary = $secretReport.summary
            }
            sbom = [ordered]@{
                outputPath = $sbomPath
                componentCount = $sbomResult.componentCount
                success = $sbomResult.success
            }
            vulnerabilityScan = [ordered]@{
                reportPath = $vulnReportPath
                summary = $vulnReport.summary
            }
        }
    }

    $consolidatedPath = Join-Path $resolvedOutput "security-baseline-$timestamp.json"
    $consolidated | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $consolidatedPath -Encoding UTF8

    Write-Host "[Invoke-SecurityBaseline] Secret scan findings: $($secretReport.summary.totalFindings)" -ForegroundColor $(if ($secretReport.summary.totalFindings -gt 0) { 'Yellow' } else { 'Green' })
    Write-Host "[Invoke-SecurityBaseline] Vulnerability findings: $($vulnReport.summary.totalFindings)" -ForegroundColor $(if ($vulnReport.summary.totalFindings -gt 0) { 'Yellow' } else { 'Green' })
    Write-Host "[Invoke-SecurityBaseline] SBOM components: $($sbomResult.componentCount)" -ForegroundColor Cyan
    Write-Host "[Invoke-SecurityBaseline] Reports written to: $($resolvedOutput.Path)" -ForegroundColor Cyan

    if ($FailOnCritical -and (($secretReport.summary.critical + $vulnReport.summary.critical) -gt 0)) {
        throw "[Invoke-SecurityBaseline] Critical findings detected. Failing baseline."
    }

    return $consolidated
}

#endregion
