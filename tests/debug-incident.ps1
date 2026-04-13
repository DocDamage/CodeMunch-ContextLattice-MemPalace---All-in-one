$ErrorActionPreference = 'Continue'
. 'module/LLMWorkflow/retrieval/IncidentBundle.ps1' 2>&1 | Out-Null

# Create a bundle
$bundle = New-AnswerIncidentBundle -Query 'Test' -FinalAnswer 'Answer'
Write-Host 'Created bundle with ID:' $bundle.incidentId

# Export it
$export = Export-IncidentBundle -Incident $bundle
Write-Host 'Exported to:' $export.Path

# Now test importing
Write-Host ''
Write-Host 'Testing Import-IncidentBundle...'
try {
    $loaded = Import-IncidentBundle -Path $export.Path
    Write-Host 'Import SUCCESS'
    Write-Host 'Loaded type:' $loaded.GetType().Name
    Write-Host 'Loaded incidentId:' $loaded.incidentId
} catch {
    Write-Host 'Import FAILED:' $_
}

# Cleanup
Remove-Item $export.Path -Force
Write-Host ''
Write-Host 'Cleanup complete'
