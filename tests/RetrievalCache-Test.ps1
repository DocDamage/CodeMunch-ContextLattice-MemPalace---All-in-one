#requires -Version 5.1
<#
.SYNOPSIS
    Comprehensive RetrievalCache Module Tests
#>

$ErrorActionPreference = "Stop"
$ProjectRoot = "C:\Users\Doc\Desktop\Projects\CodeMunch-ContextLattice-MemPalace---All-in-one"

# Cleanup first
Remove-Item "$ProjectRoot\.llm-workflow\locks\*.lock" -Force -ErrorAction SilentlyContinue
Remove-Item "$ProjectRoot\.llm-workflow\cache\retrieval-cache.jsonl" -Force -ErrorAction SilentlyContinue

# Import module (suppress non-critical warnings)
Import-Module "$ProjectRoot\module\LLMWorkflow\retrieval\RetrievalCache.ps1" -Force 2>&1 | Out-Null

Write-Host "=== RetrievalCache Module Tests ===" -ForegroundColor Cyan

# Test 1: Cache Key Generation
Write-Host "`nTest 1: Cache Key Generation" -ForegroundColor Yellow
$key1 = Get-RetrievalCacheKey -Query "How do I use signals?" -RetrievalProfile "godot-expert" -Context @{ workspaceId = "ws-001"; engineTarget = "godot4" } -PackVersions @{ "godot-engine" = "v2.1.0" }
$key2 = Get-RetrievalCacheKey -Query "How do I use signals?" -RetrievalProfile "godot-expert" -Context @{ workspaceId = "ws-001"; engineTarget = "godot4" } -PackVersions @{ "godot-engine" = "v2.1.0" }
if ($key1 -eq $key2 -and $key1.Length -eq 64) {
    Write-Host "  PASS: Consistent SHA256 keys ($($key1.Substring(0, 16))...)" -ForegroundColor Green
} else {
    Write-Host "  FAIL" -ForegroundColor Red
}

# Test 2: Config
Write-Host "`nTest 2: Cache Configuration" -ForegroundColor Yellow
$config = Get-RetrievalCacheConfig -ProjectRoot $ProjectRoot
if ($config.defaultTTLMinutes -eq 60 -and $config.maxEntries -eq 1000) {
    Write-Host "  PASS: Config (TTL: $($config.defaultTTLMinutes)min, Max: $($config.maxEntries))" -ForegroundColor Green
} else {
    Write-Host "  FAIL" -ForegroundColor Red
}

# Test 3: Cache Entry Validation
Write-Host "`nTest 3: Cache Entry Validation" -ForegroundColor Yellow
$validEntry = @{ key = "test"; expiresAt = ([DateTime]::UtcNow.AddHours(1).ToString("yyyy-MM-ddTHH:mm:ssZ")) }
$expiredEntry = @{ key = "test"; expiresAt = ([DateTime]::UtcNow.AddHours(-1).ToString("yyyy-MM-ddTHH:mm:ssZ")) }
if ((Test-CacheEntryValid -CacheEntry $validEntry) -and -not (Test-CacheEntryValid -CacheEntry $expiredEntry)) {
    Write-Host "  PASS: Valid/Expired detection works" -ForegroundColor Green
} else {
    Write-Host "  FAIL" -ForegroundColor Red
}

# Test 4: Store and Retrieve
Write-Host "`nTest 4: Store and Retrieve" -ForegroundColor Yellow
$testQuery = "Test query $(Get-Random)"
$testResult = @{ answer = "Test answer"; confidence = 0.95 }
Set-CachedRetrieval -Query $testQuery -RetrievalProfile "test-profile" -Result $testResult -Context @{ workspaceId = "test-ws" } -PackVersions @{ "test-pack" = "v1.0.0" } -ProjectRoot $ProjectRoot | Out-Null
$getResult = Get-CachedRetrieval -Query $testQuery -RetrievalProfile "test-profile" -Context @{ workspaceId = "test-ws" } -PackVersions @{ "test-pack" = "v1.0.0" } -ProjectRoot $ProjectRoot
if ($getResult -and $getResult.Result.answer -eq "Test answer") {
    Write-Host "  PASS: Store/Retrieve works (hits: $($getResult.Metadata.hitCount))" -ForegroundColor Green
} else {
    Write-Host "  FAIL" -ForegroundColor Red
}

# Test 5: Second retrieve (hit count)
Write-Host "`nTest 5: Cache Hit Counter" -ForegroundColor Yellow
$getResult2 = Get-CachedRetrieval -Query $testQuery -RetrievalProfile "test-profile" -Context @{ workspaceId = "test-ws" } -PackVersions @{ "test-pack" = "v1.0.0" } -ProjectRoot $ProjectRoot
if ($getResult2.Metadata.hitCount -eq 2) {
    Write-Host "  PASS: Hit count incremented (hits: $($getResult2.Metadata.hitCount))" -ForegroundColor Green
} else {
    Write-Host "  FAIL (expected 2, got $($getResult2.Metadata.hitCount))" -ForegroundColor Red
}

# Test 6: Cache Stats
Write-Host "`nTest 6: Cache Statistics" -ForegroundColor Yellow
$stats = Get-RetrievalCacheStats -ProjectRoot $ProjectRoot
Write-Host "  PASS: Stats (Entries: $($stats.EntryCount))" -ForegroundColor Green

# Test 7: Config Save/Load
Write-Host "`nTest 7: Configuration Save/Load" -ForegroundColor Yellow
$newConfig = @{ defaultTTLMinutes = 90; maxEntries = 1500 }
Set-RetrievalCacheConfig -Config $newConfig -ProjectRoot $ProjectRoot | Out-Null
$loadedConfig = Get-RetrievalCacheConfig -ProjectRoot $ProjectRoot -ForceReload
if ($loadedConfig.defaultTTLMinutes -eq 90 -and $loadedConfig.maxEntries -eq 1500) {
    Write-Host "  PASS: Config saved/loaded correctly" -ForegroundColor Green
    Set-RetrievalCacheConfig -Config @{ defaultTTLMinutes = 60; maxEntries = 1000 } -ProjectRoot $ProjectRoot | Out-Null
} else {
    Write-Host "  FAIL" -ForegroundColor Red
}

# Test 8: Cache Invalidation
Write-Host "`nTest 8: Cache Invalidation" -ForegroundColor Yellow
$invResult = Invoke-CacheInvalidation -Reason "manual" -Criteria @{ retrievalProfile = "test-profile" } -ProjectRoot $ProjectRoot
Write-Host "  PASS: Invalidation removed $($invResult.RemovedCount) entries" -ForegroundColor Green

# Test 9: Pack Invalidation
Write-Host "`nTest 9: Pack Cache Invalidation" -ForegroundColor Yellow
Set-CachedRetrieval -Query "Pack test" -RetrievalProfile "pack-profile" -Result @{ answer = "pack answer" } -PackVersions @{ "godot-engine" = "v2.1.0" } -ProjectRoot $ProjectRoot | Out-Null
$packInvResult = Invoke-PackCacheInvalidation -PackId "godot-engine" -NewVersion "v2.2.0" -UpdateType "promotion" -ProjectRoot $ProjectRoot
Write-Host "  PASS: Pack invalidation (Removed: $($packInvResult.RemovedCount))" -ForegroundColor Green

# Test 10: Maintenance
Write-Host "`nTest 10: Cache Maintenance" -ForegroundColor Yellow
$mntResult = Invoke-CacheMaintenance -MaxAgeHours 24 -ProjectRoot $ProjectRoot
Write-Host "  PASS: Maintenance (Kept: $($mntResult.KeptCount), Expired: $($mntResult.ExpiredCount))" -ForegroundColor Green

# Test 11: Clear Cache
Write-Host "`nTest 11: Clear Cache" -ForegroundColor Yellow
$clearResult = Clear-RetrievalCache -Force -ProjectRoot $ProjectRoot
if ($clearResult.Success) {
    Write-Host "  PASS: Cache cleared" -ForegroundColor Green
} else {
    Write-Host "  FAIL" -ForegroundColor Red
}

Write-Host "`n=== All Tests Completed ===" -ForegroundColor Cyan
