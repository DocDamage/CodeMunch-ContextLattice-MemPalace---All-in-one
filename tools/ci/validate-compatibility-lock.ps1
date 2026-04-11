[CmdletBinding()]
param(
    [string]$LockFile = "compatibility.lock.json",
    [string]$ManifestFile = "module/LLMWorkflow/LLMWorkflow.psd1"
)

$ErrorActionPreference = "Stop"

function Assert-HasProperty {
    param(
        [Parameter(Mandatory = $true)]
        [object]$Object,
        [Parameter(Mandatory = $true)]
        [string]$PropertyName
    )
    if (-not $Object.PSObject.Properties.Name.Contains($PropertyName)) {
        throw "Missing required property '$PropertyName'."
    }
}

if (-not (Test-Path -LiteralPath $LockFile)) {
    throw "Missing lock file: $LockFile"
}
if (-not (Test-Path -LiteralPath $ManifestFile)) {
    throw "Missing module manifest: $ManifestFile"
}

$lockRaw = Get-Content -LiteralPath $LockFile -Raw
$lock = $lockRaw | ConvertFrom-Json

Assert-HasProperty -Object $lock -PropertyName "schema_version"
Assert-HasProperty -Object $lock -PropertyName "updated_utc"
Assert-HasProperty -Object $lock -PropertyName "tooling"
Assert-HasProperty -Object $lock -PropertyName "components"

if ([int]$lock.schema_version -ne 1) {
    throw "Unsupported schema_version: $($lock.schema_version)"
}

$null = [datetime]::Parse($lock.updated_utc)

Assert-HasProperty -Object $lock.tooling -PropertyName "llmworkflow_module_version"
Assert-HasProperty -Object $lock.tooling -PropertyName "tested_shells"
Assert-HasProperty -Object $lock.tooling -PropertyName "tested_python"

$lockVersion = [string]$lock.tooling.llmworkflow_module_version
if ($lockVersion -notmatch '^\d+\.\d+\.\d+$') {
    throw "tooling.llmworkflow_module_version is not semver core: $lockVersion"
}

$manifest = Import-PowerShellDataFile -Path $ManifestFile
$manifestVersion = [string]$manifest.ModuleVersion
if ($manifestVersion -ne $lockVersion) {
    throw "Manifest version '$manifestVersion' does not match lock version '$lockVersion'."
}

foreach ($componentName in @("codemunch_pro", "contextlattice", "mempalace", "chromadb")) {
    if (-not $lock.components.PSObject.Properties.Name.Contains($componentName)) {
        throw "Missing components.$componentName entry."
    }
}

foreach ($gitComponent in @("codemunch_pro", "contextlattice", "mempalace")) {
    $entry = $lock.components.$gitComponent
    Assert-HasProperty -Object $entry -PropertyName "source"
    Assert-HasProperty -Object $entry -PropertyName "tested_ref"
    if ([string]$entry.tested_ref -notmatch '^[0-9a-f]{40}$') {
        throw "components.$gitComponent.tested_ref must be a 40-char commit SHA."
    }
}

$chroma = $lock.components.chromadb
Assert-HasProperty -Object $chroma -PropertyName "source"
Assert-HasProperty -Object $chroma -PropertyName "constraint"

Write-Output "[compat-lock] OK: lock file is valid and matches module manifest version."

