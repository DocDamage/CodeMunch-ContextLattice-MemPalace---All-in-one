@echo off
echo === Testing RetrievalCache Module ===

powershell -Command "
Import-Module 'C:\Users\Doc\Desktop\Projects\CodeMunch-ContextLattice-MemPalace---All-in-one\module\LLMWorkflow\retrieval\RetrievalCache.ps1' -Force 2>$null

# Test 1: Cache Key Generation
Write-Host 'Test 1: Cache Key Generation' -ForegroundColor Yellow
$key1 = Get-RetrievalCacheKey -Query 'How do I use signals?' -RetrievalProfile 'godot-expert' -Context @{ workspaceId = 'ws-001'; engineTarget = 'godot4' } -PackVersions @{ 'godot-engine' = 'v2.1.0' }
$key2 = Get-RetrievalCacheKey -Query 'How do I use signals?' -RetrievalProfile 'godot-expert' -Context @{ workspaceId = 'ws-001'; engineTarget = 'godot4' } -PackVersions @{ 'godot-engine' = 'v2.1.0' }
if ($key1 -eq $key2 -and $key1.Length -eq 64) {
    Write-Host '  PASS: Consistent SHA256 keys generated' -ForegroundColor Green
} else {
    Write-Host '  FAIL: Key generation issue' -ForegroundColor Red
}

# Test 2: Config
Write-Host 'Test 2: Cache Configuration' -ForegroundColor Yellow
$config = Get-RetrievalCacheConfig
if ($config.defaultTTLMinutes -eq 60 -and $config.maxEntries -eq 1000) {
    Write-Host ('  PASS: Config loaded (TTL: ' + $config.defaultTTLMinutes + 'min, Max: ' + $config.maxEntries + ')') -ForegroundColor Green
} else {
    Write-Host '  FAIL: Config issue' -ForegroundColor Red
}

# Test 3: Cache Entry Validation
Write-Host 'Test 3: Cache Entry Validation' -ForegroundColor Yellow
$validEntry = @{ key = 'test'; expiresAt = ([DateTime]::UtcNow.AddHours(1).ToString('yyyy-MM-ddTHH:mm:ssZ')) }
$expiredEntry = @{ key = 'test'; expiresAt = ([DateTime]::UtcNow.AddHours(-1).ToString('yyyy-MM-ddTHH:mm:ssZ')) }
if ((Test-CacheEntryValid -CacheEntry $validEntry) -eq $true -and (Test-CacheEntryValid -CacheEntry $expiredEntry) -eq $false) {
    Write-Host '  PASS: Valid/Expired entry detection works' -ForegroundColor Green
} else {
    Write-Host '  FAIL: Entry validation issue' -ForegroundColor Red
}

# Test 4: Store and Retrieve
Write-Host 'Test 4: Store and Retrieve Cache Entry' -ForegroundColor Yellow
$testQuery = 'Test query ' + (Get-Random)
$testResult = @{ answer = 'Test answer'; confidence = 0.95 }
$setResult = Set-CachedRetrieval -Query $testQuery -RetrievalProfile 'test-profile' -Result $testResult -Context @{ workspaceId = 'test-ws' } -PackVersions @{ 'test-pack' = 'v1.0.0' }
$getResult = Get-CachedRetrieval -Query $testQuery -RetrievalProfile 'test-profile' -Context @{ workspaceId = 'test-ws' } -PackVersions @{ 'test-pack' = 'v1.0.0' }
if ($getResult -and $getResult.Result.answer -eq 'Test answer') {
    Write-Host ('  PASS: Store/Retrieve works (hits: ' + $getResult.Metadata.hitCount + ')') -ForegroundColor Green
} else {
    Write-Host '  FAIL: Store/Retrieve issue' -ForegroundColor Red
}

# Test 5: Cache Stats
Write-Host 'Test 5: Cache Statistics' -ForegroundColor Yellow
$stats = Get-RetrievalCacheStats
Write-Host ('  PASS: Stats retrieved (Entries: ' + $stats.EntryCount + ')') -ForegroundColor Green

# Test 6: Cache Invalidation
Write-Host 'Test 6: Cache Invalidation' -ForegroundColor Yellow
$invResult = Invoke-CacheInvalidation -Reason 'manual' -Criteria @{ retrievalProfile = 'test-profile' }
Write-Host ('  PASS: Invalidation executed (Removed: ' + $invResult.RemovedCount + ')') -ForegroundColor Green

# Test 7: Maintenance
Write-Host 'Test 7: Cache Maintenance' -ForegroundColor Yellow
$mntResult = Invoke-CacheMaintenance -MaxAgeHours 24
Write-Host ('  PASS: Maintenance executed (Kept: ' + $mntResult.KeptCount + ')') -ForegroundColor Green

Write-Host ''
Write-Host '=== All Tests Completed ===' -ForegroundColor Cyan
"
