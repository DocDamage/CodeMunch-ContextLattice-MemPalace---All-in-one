$ErrorActionPreference = 'Continue'
try { . 'module/LLMWorkflow/retrieval/IncidentBundle.ps1' } catch {}

# Clean up
$registryPath = '.llm-workflow/state/incident-registry.json'
if (Test-Path $registryPath) {
    Remove-Item $registryPath -Force
}

# First registration
Write-Host '=== First registration ===' -ForegroundColor Cyan
$bundle1 = New-AnswerIncidentBundle -Query 'Test 1' -FinalAnswer 'Answer 1'
$reg1 = Register-Incident -Incident $bundle1
Write-Host 'Success:' $reg1.Success
Write-Host 'Path:' $reg1.Path

# Check registry
$content = Get-Content $registryPath -Raw
Write-Host 'Registry after 1st:'
Write-Host $content

# Second registration
Write-Host ''
Write-Host '=== Second registration ===' -ForegroundColor Cyan
$bundle2 = New-AnswerIncidentBundle -Query 'Test 2' -FinalAnswer 'Answer 2'
Write-Host 'Registering incident:' $bundle2.incidentId
try {
    $reg2 = Register-Incident -Incident $bundle2
    Write-Host 'Success:' $reg2.Success
} catch {
    Write-Host 'ERROR:' $_ -ForegroundColor Red
}

# Cleanup
Remove-Item $reg1.Path -Force -ErrorAction SilentlyContinue
if ($reg2.Path) { Remove-Item $reg2.Path -Force -ErrorAction SilentlyContinue }
Remove-Item $registryPath -Force -ErrorAction SilentlyContinue
