$ErrorActionPreference = 'Continue'
. 'module/LLMWorkflow/retrieval/IncidentBundle.ps1' 2>&1 | Out-Null

$registryPath = '.llm-workflow/state/incident-registry.json'

# Create a sample registry file
$registry = @{
    incidents = @(
        [ordered]@{
            incidentId = 'test-123'
            query = 'Test query'
        }
    )
}

$json = $registry | ConvertTo-Json -Depth 10
Write-Host 'Original JSON:'
Write-Host $json
Write-Host ''

# Write to file
Set-Content -Path $registryPath -Value $json -Force

# Read it back
$content = Get-Content $registryPath -Raw
Write-Host 'Read back content:'
Write-Host $content
Write-Host ''

# Parse it
$parsed = $content | ConvertFrom-Json
Write-Host 'Parsed type:' $parsed.GetType().Name
Write-Host 'Parsed.incidents type:' $parsed.incidents.GetType().Name
Write-Host 'Parsed.incidents[0] type:' $parsed.incidents[0].GetType().Name

# Try ConvertTo-HashTable
Write-Host ''
Write-Host 'Converting to hashtable...'
$hash = ConvertTo-HashTable -InputObject $parsed
Write-Host 'Hash type:' $hash.GetType().Name
Write-Host 'Hash.incidents type:' $hash.incidents.GetType().Name
if ($hash.incidents.Count -gt 0) {
    Write-Host 'Hash.incidents[0] type:' $hash.incidents[0].GetType().Name
}

# Cleanup
Remove-Item $registryPath -Force -ErrorAction SilentlyContinue
