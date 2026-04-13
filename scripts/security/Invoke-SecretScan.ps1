#requires -Version 5.1
Set-StrictMode -Version Latest

<#
.SYNOPSIS
    Secret scanning wrapper for the LLM Workflow platform.
.DESCRIPTION
    Simulates TruffleHog-style scanning by running regex-based secret detection
    using the existing patterns from module/LLMWorkflow/core/Visibility.ps1.
    Produces findings with file paths, line numbers, and severity.
    Safe to run without external tools installed.
.NOTES
    File: Invoke-SecretScan.ps1
    Version: 1.0.0
    Compatible with: PowerShell 5.1+
#>

#region Secret Patterns (mirrored from Visibility.ps1)

$script:SecretPatterns = @{
    OpenAI_API_Key = @{
        Pattern = 'sk-[a-zA-Z0-9]{48}'
        Type = 'api_key'
        Severity = 'critical'
    }
    Anthropic_API_Key = @{
        Pattern = 'sk-ant-[a-zA-Z0-9]{32,}'
        Type = 'api_key'
        Severity = 'critical'
    }
    AWS_Access_Key = @{
        Pattern = 'AKIA[0-9A-Z]{16}'
        Type = 'api_key'
        Severity = 'critical'
    }
    AWS_Secret_Key = @{
        Pattern = '[0-9a-zA-Z/+]{40}'
        Type = 'secret_key'
        Severity = 'critical'
    }
    Generic_API_Key = @{
        Pattern = '(?i)(api[_-]?key|apikey)\s*[:=]\s*["'']?[a-zA-Z0-9_\-]{16,}["'']?'
        Type = 'api_key'
        Severity = 'high'
    }
    Bearer_Token = @{
        Pattern = 'bearer\s+[a-zA-Z0-9_\-\.]+'
        Type = 'token'
        Severity = 'high'
    }
    JWT_Token = @{
        Pattern = 'eyJ[a-zA-Z0-9_\-]*\.eyJ[a-zA-Z0-9_\-]*\.[a-zA-Z0-9_\-]*'
        Type = 'jwt'
        Severity = 'high'
    }
    SQL_Connection = @{
        Pattern = '(?i)(Server|Data Source)=[^;]+;.*(Password|Pwd)=[^;]+'
        Type = 'connection_string'
        Severity = 'critical'
    }
    MongoDB_URI = @{
        Pattern = 'mongodb(\+srv)?://[^:]+:[^@]+@'
        Type = 'connection_string'
        Severity = 'critical'
    }
    Redis_Connection = @{
        Pattern = 'redis://:[^@]+@'
        Type = 'connection_string'
        Severity = 'critical'
    }
    RSA_Private_Key = @{
        Pattern = '-----BEGIN RSA PRIVATE KEY-----'
        Type = 'private_key'
        Severity = 'critical'
    }
    SSH_Private_Key = @{
        Pattern = '-----BEGIN OPENSSH PRIVATE KEY-----'
        Type = 'private_key'
        Severity = 'critical'
    }
    PEM_Private_Key = @{
        Pattern = '-----BEGIN PRIVATE KEY-----'
        Type = 'private_key'
        Severity = 'critical'
    }
    Credit_Card = @{
        Pattern = '\b(?:4[0-9]{12}(?:[0-9]{3})?|5[1-5][0-9]{14}|3[47][0-9]{13}|3(?:0[0-5]|[68][0-9])[0-9]{11}|6(?:011|5[0-9]{2})[0-9]{12}|(?:2131|1800|35\d{3})\d{11})\b'
        Type = 'pii'
        Severity = 'critical'
    }
    SSN = @{
        Pattern = '\b\d{3}-\d{2}-\d{4}\b'
        Type = 'pii'
        Severity = 'critical'
    }
    Email_Address = @{
        Pattern = '\b[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Z|a-z]{2,}\b'
        Type = 'pii'
        Severity = 'medium'
    }
    Password_in_URL = @{
        Pattern = '(?i)[:/][^/:]+:[^@/]+@'
        Type = 'password'
        Severity = 'critical'
    }
    Password_Assignment = @{
        Pattern = '(?i)(password|passwd|pwd)\s*[:=]\s*["''][^"'']+["'']'
        Type = 'password'
        Severity = 'high'
    }
}

#endregion

#region Private Helpers

function Test-ShouldScanFile {
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path,

        [Parameter()]
        [string[]]$ExcludePaths = @('.git', 'node_modules', '.venv', 'venv', 'dist', 'build', 'out', 'coverage', '.llm-workflow/logs')
    )

    foreach ($exclude in $ExcludePaths) {
        if ($Path -like "*$exclude*") {
            return $false
        }
    }

    $extension = [System.IO.Path]::GetExtension($Path).ToLowerInvariant()
    $scanExtensions = @('.ps1', '.psm1', '.json', '.yml', '.yaml', '.env', '.config', '.txt', '.md', '.psd1', '.dockerfile')
    $scanable = $scanExtensions -contains $extension

    # Also scan files without extension that look like configs or scripts
    if (-not $scanable -and [string]::IsNullOrEmpty($extension)) {
        $fileName = [System.IO.Path]::GetFileName($Path).ToLowerInvariant()
        if ($fileName -in @('dockerfile', 'makefile', 'jenkinsfile')) {
            $scanable = $true
        }
    }

    return $scanable
}

function Get-FileFindings {
    [CmdletBinding()]
    [OutputType([array])]
    param(
        [Parameter(Mandatory = $true)]
        [string]$FilePath
    )

    $findings = @()

    try {
        $lines = @(Get-Content -LiteralPath $FilePath -ErrorAction Stop)
    }
    catch {
        Write-Verbose "[Invoke-SecretScan] Unable to read file: $FilePath"
        return $findings
    }

    for ($lineNumber = 0; $lineNumber -lt $lines.Count; $lineNumber++) {
        $line = $lines[$lineNumber]
        if ([string]::IsNullOrEmpty($line)) { continue }

        foreach ($patternName in $script:SecretPatterns.Keys) {
            $patternInfo = $script:SecretPatterns[$patternName]
            $regex = $null
            $matches = $null

            try {
                $regex = [regex]::new($patternInfo.Pattern)
                $matches = $regex.Matches($line)
            }
            catch {
                continue
            }

            foreach ($match in $matches) {
                $findings += [pscustomobject]@{
                    FilePath = $FilePath
                    LineNumber = $lineNumber + 1
                    PatternName = $patternName
                    Type = $patternInfo.Type
                    Severity = $patternInfo.Severity
                    MatchedValue = $match.Value
                    LineText = $line.Trim()
                }
            }
        }
    }

    return $findings
}

#endregion

#region Public Functions

function Invoke-SecretScan {
    <#
    .SYNOPSIS
        Runs a regex-based secret scan over the project directory.
    .DESCRIPTION
        Scans text-based files for secrets using patterns derived from
        module/LLMWorkflow/core/Visibility.ps1. Produces a structured
        report with file paths, line numbers, matched values, and severity.
    .PARAMETER ProjectRoot
        The root directory to scan. Defaults to the current working directory.
    .PARAMETER OutputPath
        Optional path to write a JSON report.
    .PARAMETER SeverityThreshold
        Minimum severity to include in findings: low, medium, high, critical.
    .PARAMETER IncludePatterns
        Specific pattern names to include (scans all if not specified).
    .PARAMETER ExcludePatterns
        Pattern names to exclude from scanning.
    .EXAMPLE
        Invoke-SecretScan -ProjectRoot . -OutputPath ./secret-scan-results.json
    .OUTPUTS
        System.Management.Automation.PSCustomObject
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter()]
        [string]$ProjectRoot = (Get-Location).Path,

        [Parameter()]
        [string]$OutputPath = "",

        [Parameter()]
        [ValidateSet('low', 'medium', 'high', 'critical')]
        [string]$SeverityThreshold = 'low',

        [Parameter()]
        [string[]]$IncludePatterns = @(),

        [Parameter()]
        [string[]]$ExcludePatterns = @()
    )

    $severityRank = @{ 'low' = 0; 'medium' = 1; 'high' = 2; 'critical' = 3 }
    $minSeverity = $severityRank[$SeverityThreshold]

    $patternsToUse = $script:SecretPatterns
    if ($IncludePatterns.Count -gt 0) {
        $filteredPatterns = @{}
        foreach ($name in $IncludePatterns) {
            if ($script:SecretPatterns.ContainsKey($name)) {
                $filteredPatterns[$name] = $script:SecretPatterns[$name]
            }
        }
        $patternsToUse = $filteredPatterns
    }

    $allFindings = @()
    $scannedFiles = 0

    if (-not (Test-Path -LiteralPath $ProjectRoot)) {
        throw "Project root not found: $ProjectRoot"
    }

    $files = Get-ChildItem -Path $ProjectRoot -File -Recurse -ErrorAction SilentlyContinue

    foreach ($file in $files) {
        if (-not (Test-ShouldScanFile -Path $file.FullName)) {
            continue
        }

        $fileFindings = @(Get-FileFindings -FilePath $file.FullName)
        $scannedFiles++

        foreach ($finding in $fileFindings) {
            $patternSeverity = $severityRank[$finding.Severity]
            if ($patternSeverity -lt $minSeverity) {
                continue
            }

            if ($ExcludePatterns -contains $finding.PatternName) {
                continue
            }

            $allFindings += $finding
        }
    }

    $summary = @{
        scannedFiles = $scannedFiles
        totalFindings = @($allFindings).Count
        critical = @($allFindings | Where-Object { $_.Severity -eq 'critical' }).Count
        high = @($allFindings | Where-Object { $_.Severity -eq 'high' }).Count
        medium = @($allFindings | Where-Object { $_.Severity -eq 'medium' }).Count
        low = @($allFindings | Where-Object { $_.Severity -eq 'low' }).Count
    }

    $report = [pscustomobject]@{
        scanType = 'secret'
        tool = 'Invoke-SecretScan (TruffleHog-compatible)'
        timestamp = [DateTime]::UtcNow.ToString('yyyy-MM-ddTHH:mm:ssZ')
        projectRoot = (Resolve-Path -LiteralPath $ProjectRoot).Path
        summary = $summary
        findings = $allFindings
    }

    if ($OutputPath) {
        $parent = Split-Path -Parent $OutputPath
        if ($parent -and -not (Test-Path -LiteralPath $parent)) {
            New-Item -ItemType Directory -Path $parent -Force | Out-Null
        }
        $report | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $OutputPath -Encoding UTF8
    }

    return $report
}

#endregion
