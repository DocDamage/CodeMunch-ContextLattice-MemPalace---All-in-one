# Test Convert-PSObjectToHashtable
Import-Module 'C:\Users\Doc\Desktop\Projects\CodeMunch-ContextLattice-MemPalace---All-in-one\module\LLMWorkflow\retrieval\RetrievalCache.ps1' -Force 2>&1 | Out-Null

$json = '{"key":"test","value":123,"nested":{"a":1}}'
$obj = $json | ConvertFrom-Json

Write-Host "Input type: $($obj.GetType().Name)"
$hash = Convert-PSObjectToHashtable -InputObject $obj
Write-Host "Output type: $($hash.GetType().Name)"
Write-Host "Has key: $($hash.ContainsKey('key'))"
Write-Host "Key value: $($hash.key)"
Write-Host "Nested type: $($hash.nested.GetType().Name)"
