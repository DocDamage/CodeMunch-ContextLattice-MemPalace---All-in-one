# Test Convert-PSObjectToHashtable
$ProjectRoot = Resolve-Path (Join-Path $PSScriptRoot "..")
$modulePath = Join-Path $ProjectRoot "module\LLMWorkflow\core\TypeConverters.ps1"
if (Test-Path $modulePath) { . $modulePath }

$json = '{"key":"test","value":123,"nested":{"a":1}}'
$obj = $json | ConvertFrom-Json

Write-Host "Input type: $($obj.GetType().Name)"
$hash = Convert-PSObjectToHashtable -InputObject $obj
Write-Host "Output type: $($hash.GetType().Name)"
Write-Host "Has key: $($hash.ContainsKey('key'))"
Write-Host "Key value: $($hash.key)"
Write-Host "Nested type: $($hash.nested.GetType().Name)"
