$ErrorActionPreference = 'Continue'
. 'module/LLMWorkflow/retrieval/IncidentBundle.ps1' 2>&1 | Out-Null

$registryPath = '.llm-workflow/state/incident-registry.json'

# Clean up first
if (Test-Path $registryPath) {
    Remove-Item $registryPath -Force
}

# Register first incident
$bundle1 = New-AnswerIncidentBundle -Query 'Test 1' -FinalAnswer 'Answer 1'
Write-Host 'Registering first incident:' $bundle1.incidentId
$reg1 = Register-Incident -Incident $bundle1
Write-Host 'Result:' $reg1.Success

# Check the registry content
if (Test-Path $registryPath) {
    $content = Get-Content $registryPath -Raw
    Write-Host ''
    Write-Host 'Registry content after first registration:'
    Write-Host $content
}

# Register second incident
$bundle2 = New-AnswerIncidentBundle -Query 'Test 2' -FinalAnswer 'Answer 2'
Write-Host ''
Write-Host 'Registering second incident:' $bundle2.incidentId
try {
    $reg2 = Register-Incident -Incident $bundle2
    Write-Host 'Result:' $reg2.Success
} catch {
    Write-Host 'ERROR:' $_
}

# Check the registry content again
if (Test-Path $registryPath) {
    $content = Get-Content $registryPath -Raw
    Write-Host ''
    Write-Host 'Registry content after second registration:'
    Write-Host $content
}

# Cleanup
Remove-Item $reg1.Path -Force -ErrorAction SilentlyContinue
Remove-Item $reg2.Path -Force -ErrorAction SilentlyContinue
Remove-Item $registryPath -Force -ErrorAction SilentlyContinue
Write-Host ''
Write-Host 'Cleanup complete'
