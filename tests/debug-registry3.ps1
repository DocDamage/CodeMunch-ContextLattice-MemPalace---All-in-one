$ErrorActionPreference = 'Continue'
. 'module/LLMWorkflow/retrieval/IncidentBundle.ps1' 2>&1 | Out-Null

# Simulate what happens when ConvertTo-HashTable receives a hashtable
$testHash = @{
    incidents = @(
        @{ incidentId = 'test-1'; query = 'Query 1' }
        @{ incidentId = 'test-2'; query = 'Query 2' }
    )
}

Write-Host 'Input type:' $testHash.GetType().Name
Write-Host 'Input.incidents type:' $testHash.incidents.GetType().Name
Write-Host ''

# Try ConvertTo-HashTable on this
Write-Host 'Converting...'
$result = ConvertTo-HashTable -InputObject $testHash
Write-Host 'Result type:' $result.GetType().Name
Write-Host 'Result.incidents type:' $result.incidents.GetType().Name
Write-Host 'Result.incidents count:' $result.incidents.Count
