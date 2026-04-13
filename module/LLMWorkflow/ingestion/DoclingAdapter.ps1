#requires -Version 5.1
<#
.SYNOPSIS
    PowerShell adapter for Docling document ingestion.

.DESCRIPTION
    Provides a PowerShell interface to the Docling document extraction tool.
    Supports PDF, DOCX, and PPTX formats. Returns normalized output containing
    extracted text, page boundaries, and confidence estimates.

    The adapter attempts to invoke Docling via Python (docling CLI or module).
    If Docling is not available, functions return graceful fallback information.

.PARAMETER PythonPath
    Path to the Python executable. Defaults to 'python' or 'python3'.

.PARAMETER FilePath
    Path to the document file to extract.

.PARAMETER OutputFormat
    Desired Docling output format hint (markdown, json, text).

.OUTPUTS
    System.Collections.Hashtable. Normalized extraction result.

.NOTES
    File Name      : DoclingAdapter.ps1
    Author         : LLM Workflow Team
    Version        : 1.0.0
    Prerequisite   : PowerShell 5.1+, Docling Python package (optional)
    Copyright      : (c) 2026 LLM Workflow Project
    License        : MIT
#>

Set-StrictMode -Version Latest

$script:ModuleVersion = '1.0.0'
$script:ModuleName = 'DoclingAdapter'
$script:SupportedFormats = @('.pdf', '.docx', '.pptx')

<#
.SYNOPSIS
    Creates a new Docling adapter configuration.

.DESCRIPTION
    Returns a hashtable with Docling adapter settings including Python path,
    CLI arguments, and timeout values.

.PARAMETER PythonPath
    Path to the Python executable.

.PARAMETER TimeoutSeconds
    Extraction timeout in seconds.

.OUTPUTS
    System.Collections.Hashtable. Adapter configuration object.
#>
function New-DoclingAdapter {
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [Parameter()]
        [string]$PythonPath = '',

        [Parameter()]
        [int]$TimeoutSeconds = 300
    )

    $resolvedPython = if ([string]::IsNullOrWhiteSpace($PythonPath)) {
        $candidates = @('python', 'python3', 'py')
        $found = $null
        foreach ($candidate in $candidates) {
            $cmd = Get-Command -Name $candidate -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
            if ($cmd) {
                $found = $cmd.Source
                break
            }
        }
        if ([string]::IsNullOrWhiteSpace($found)) { 'python' } else { $found }
    } else {
        $PythonPath
    }

    return [ordered]@{
        adapterName = 'DoclingAdapter'
        adapterVersion = $script:ModuleVersion
        pythonPath = $resolvedPython
        timeoutSeconds = $TimeoutSeconds
        supportedFormats = $script:SupportedFormats
        createdAt = [DateTime]::UtcNow.ToString('o')
    }
}

<#
.SYNOPSIS
    Tests whether Docling is available on the system.

.DESCRIPTION
    Checks if the Docling Python package is installed and callable.
    Tests by importing the docling module via the configured Python executable.

.PARAMETER Adapter
    Adapter configuration from New-DoclingAdapter.

.OUTPUTS
    System.Boolean. $true if Docling is available.
#>
function Test-DoclingAvailable {
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [Parameter()]
        [hashtable]$Adapter = (New-DoclingAdapter)
    )

    $python = $Adapter.pythonPath
    if (-not (Test-Path -LiteralPath $python -ErrorAction SilentlyContinue)) {
        # Also try command resolution
        $cmd = Get-Command -Name $python -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
        if (-not $cmd) {
            return $false
        }
        $python = $cmd.Source
    }

    try {
        $psi = New-Object System.Diagnostics.ProcessStartInfo
        $psi.FileName = $python
        $psi.Arguments = '-c "import docling; print(docling.__version__)"'
        $psi.RedirectStandardOutput = $true
        $psi.RedirectStandardError = $true
        $psi.UseShellExecute = $false
        $psi.CreateNoWindow = $true

        $process = [System.Diagnostics.Process]::Start($psi)
        if (-not $process) {
            return $false
        }

        $null = $process.WaitForExit(15000)
        if (-not $process.HasExited) {
            try { $process.Kill() } catch { }
            return $false
        }

        return ($process.ExitCode -eq 0)
    }
    catch {
        Write-Verbose "[$script:ModuleName] Docling availability check failed: $_"
        return $false
    }
}

<#
.SYNOPSIS
    Invokes Docling extraction on a document file.

.DESCRIPTION
    Runs Docling against the specified document and returns normalized output.
    The output includes extracted text, page array, and confidence metadata.
    If Docling is unavailable, returns a failure record with engine = 'docling-unavailable'.

.PARAMETER FilePath
    Path to the document file.

.PARAMETER Adapter
    Adapter configuration from New-DoclingAdapter.

.PARAMETER OutputFormat
    Preferred intermediate format: markdown (default), json, or text.

.OUTPUTS
    System.Collections.Hashtable. Normalized extraction result.
#>
function Invoke-DoclingExtraction {
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [Parameter(Mandatory = $true, Position = 0)]
        [Alias('Path')]
        [string]$FilePath,

        [Parameter()]
        [hashtable]$Adapter = (New-DoclingAdapter),

        [Parameter()]
        [ValidateSet('markdown', 'json', 'text')]
        [string]$OutputFormat = 'markdown'
    )

    $resolvedPath = Resolve-Path -Path $FilePath -ErrorAction SilentlyContinue | Select-Object -ExpandProperty Path
    if ([string]::IsNullOrWhiteSpace($resolvedPath) -or -not (Test-Path -LiteralPath $resolvedPath)) {
        return [ordered]@{
            success = $false
            engine = 'docling'
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
            engine = 'docling'
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

    if (-not (Test-DoclingAvailable -Adapter $Adapter)) {
        return [ordered]@{
            success = $false
            engine = 'docling-unavailable'
            sourcePath = $resolvedPath
            format = $extension.TrimStart('.')
            text = ''
            pages = @()
            confidence = 0.0
            errors = @('Docling is not available on this system.')
            warnings = @('Install Docling Python package to enable document extraction.')
            extractedAt = [DateTime]::UtcNow.ToString('o')
        }
    }

    $python = $Adapter.pythonPath
    $cmd = Get-Command -Name $python -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($cmd) { $python = $cmd.Source }

    $tempOutDir = Join-Path ([System.IO.Path]::GetTempPath()) ([System.Guid]::NewGuid().ToString())
    New-Item -ItemType Directory -Path $tempOutDir -Force | Out-Null

    try {
        # Build a small inline Python script to call docling
        $pyScript = @"
import sys, json, os
try:
    from docling.document_converter import DocumentConverter
    src = r'$($resolvedPath -replace "'", "''")'
    converter = DocumentConverter()
    result = converter.convert(src)
    text = result.document.export_to_markdown()
    # Approximate pages by splitting on form-feed or large blank lines
    raw_pages = text.split('\f')
    if len(raw_pages) <= 1:
        # fallback: split by double-newlines into chunks approximating pages
        chunks = text.split('\n\n\n')
        raw_pages = chunks if chunks else [text]
    pages = []
    for idx, p in enumerate(raw_pages):
        pages.append({
            "pageNumber": idx + 1,
            "text": p.strip()
        })
    out = {
        "success": True,
        "text": text,
        "pages": pages,
        "confidence": 0.92,
        "errors": [],
        "warnings": []
    }
    print(json.dumps(out))
except Exception as e:
    out = {"success": False, "text": "", "pages": [], "confidence": 0.0, "errors": [str(e)], "warnings": []}
    print(json.dumps(out))
"@

        $pyPath = Join-Path $tempOutDir 'docling_run.py'
        $pyScript | Set-Content -LiteralPath $pyPath -Encoding UTF8

        $psi = New-Object System.Diagnostics.ProcessStartInfo
        $psi.FileName = $python
        $psi.Arguments = "`"$pyPath`""
        $psi.RedirectStandardOutput = $true
        $psi.RedirectStandardError = $true
        $psi.UseShellExecute = $false
        $psi.CreateNoWindow = $true
        $psi.WorkingDirectory = $tempOutDir

        $process = [System.Diagnostics.Process]::Start($psi)
        if (-not $process) {
            throw 'Failed to start Python process for Docling extraction.'
        }

        $completed = $process.WaitForExit($Adapter.timeoutSeconds * 1000)
        if (-not $completed) {
            try { $process.Kill() } catch { }
            throw 'Docling extraction timed out.'
        }

        $stdout = $process.StandardOutput.ReadToEnd()
        $stderr = $process.StandardError.ReadToEnd()

        if ($process.ExitCode -ne 0 -and [string]::IsNullOrWhiteSpace($stdout)) {
            throw "Docling process exited with code $($process.ExitCode): $stderr"
        }

        $result = $stdout | ConvertFrom-Json -ErrorAction Stop

        return [ordered]@{
            success = [bool]$result.success
            engine = 'docling'
            sourcePath = $resolvedPath
            format = $extension.TrimStart('.')
            text = [string]$result.text
            pages = @($result.pages)
            confidence = [double]($result.confidence)
            errors = @($result.errors)
            warnings = @($result.warnings)
            extractedAt = [DateTime]::UtcNow.ToString('o')
        }
    }
    catch {
        Write-Verbose "[$script:ModuleName] Extraction failed: $_"
        return [ordered]@{
            success = $false
            engine = 'docling'
            sourcePath = $resolvedPath
            format = $extension.TrimStart('.')
            text = ''
            pages = @()
            confidence = 0.0
            errors = @("Extraction failed: $_")
            warnings = @()
            extractedAt = [DateTime]::UtcNow.ToString('o')
        }
    }
    finally {
        if (Test-Path -LiteralPath $tempOutDir) {
            Remove-Item -LiteralPath $tempOutDir -Recurse -Force -ErrorAction SilentlyContinue
        }
    }
}

if ($null -ne $MyInvocation.MyCommand.Module) {
if ($ExecutionContext.SessionState.Module) {
    Export-ModuleMember -Function @(
        'New-DoclingAdapter',
        'Invoke-DoclingExtraction',
        'Test-DoclingAvailable'
    )
}

}
