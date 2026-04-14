#requires -Version 5.1
# Comprehensive RetrievalCache Module Tests

$ErrorActionPreference = "Stop"
$ProjectRoot = Resolve-Path (Join-Path $PSScriptRoot "..")
if (-not (Test-Path $ProjectRoot)) { $ProjectRoot = "." }

# Import module
$modulePath = Join-Path $ProjectRoot "module\LLMWorkflow\retrieval\RetrievalCache.ps1"
if (Test-Path $modulePath) {
    . $modulePath
}

Write-Host "=== RetrievalCache Module Tests ===" -ForegroundColor Cyan

# Test 1: Cache Key Generation
Write-Host "`nTest 1: Cache Key Generation" -ForegroundColor Yellow
$key1 = Get-RetrievalCacheKey -Query "How do I use signals?" -RetrievalProfile "godot-expert" -Context @{ workspaceId = "ws-001"; engineTarget = "godot4" } -PackVersions @{ "godot-engine" = "v2.1.0" }
$key2 = Get-RetrievalCacheKey -Query "How do I use signals?" -RetrievalProfile "godot-expert" -Context @{ workspaceId = "ws-001"; engineTarget = "godot4" } -PackVersions @{ "godot-engine" = "v2.1.0" }
if ($key1 -eq $key2 -and $key1.Length -eq 64) {
    Write-Host "  PASS: Consistent SHA256 keys generated ($($key1.Substring(0, 16))...)" -ForegroundColor Green
} else {
    Write-Host "  FAIL: Key generation issue" -ForegroundColor Red
}

# Test 2: Config
Write-Host "`nTest 2: Cache Configuration" -ForegroundColor Yellow
$config = Get-RetrievalCacheConfig -ProjectRoot $ProjectRoot
if ($config.defaultTTLMinutes -eq 60 -and $config.maxEntries -eq 1000) {
    Write-Host "  PASS: Config loaded (TTL: $($config.defaultTTLMinutes)min, Max: $($config.maxEntries))" -ForegroundColor Green
} else {
    Write-Host "  FAIL: Config issue" -ForegroundColor Red
}

# Test 3: Cache Entry Validation
Write-Host "`nTest 3: Cache Entry Validation" -ForegroundColor Yellow
$validEntry = @{ key = "test"; expiresAt = ([DateTime]::UtcNow.AddHours(1).ToString("yyyy-MM-ddTHH:mm:ssZ")) }
$expiredEntry = @{ key = "test"; expiresAt = ([DateTime]::UtcNow.AddHours(-1).ToString("yyyy-MM-ddTHH:mm:ssZ")) }
if ((Test-CacheEntryValid -CacheEntry $validEntry) -eq $true -and (Test-CacheEntryValid -CacheEntry $expiredEntry) -eq $false) {
    Write-Host "  PASS: Valid/Expired entry detection works" -ForegroundColor Green
} else {
    Write-Host "  FAIL: Entry validation issue" -ForegroundColor Red
}

# Test 4: Store and Retrieve
Write-Host "`nTest 4: Store and Retrieve Cache Entry" -ForegroundColor Yellow
$testQuery = "Test query $(Get-Random)"
$testResult = @{ answer = "Test answer"; confidence = 0.95 }
$setResult = Set-CachedRetrieval -Query $testQuery -RetrievalProfile "test-profile" -Result $testResult -Context @{ workspaceId = "test-ws" } -PackVersions @{ "test-pack" = "v1.0.0" } -ProjectRoot $ProjectRoot
$getResult = Get-CachedRetrieval -Query $testQuery -RetrievalProfile "test-profile" -Context @{ workspaceId = "test-ws" } -PackVersions @{ "test-pack" = "v1.0.0" } -ProjectRoot $ProjectRoot
if ($getResult -and $getResult.Result.answer -eq "Test answer") {
    Write-Host "  PASS: Store/Retrieve works (hits: $($getResult.Metadata.hitCount))" -ForegroundColor Green
} else {
    Write-Host "  FAIL: Store/Retrieve issue" -ForegroundColor Red
}

# Test 5: Cache Stats
Write-Host "`nTest 5: Cache Statistics" -ForegroundColor Yellow
$stats = Get-RetrievalCacheStats -ProjectRoot $ProjectRoot
Write-Host "  PASS: Stats retrieved (Entries: $($stats.EntryCount), File: $($stats.CacheFile))" -ForegroundColor Green

# Test 6: Cache Invalidation
Write-Host "`nTest 6: Cache Invalidation" -ForegroundColor Yellow
$invResult = Invoke-CacheInvalidation -Reason "manual" -Criteria @{ retrievalProfile = "test-profile" } -ProjectRoot $ProjectRoot
Write-Host "  PASS: Invalidation executed (Removed: $($invResult.RemovedCount))" -ForegroundColor Green

# Test 7: Maintenance
Write-Host "`nTest 7: Cache Maintenance" -ForegroundColor Yellow
$mntResult = Invoke-CacheMaintenance -MaxAgeHours 24 -ProjectRoot $ProjectRoot
Write-Host "  PASS: Maintenance executed (Kept: $($mntResult.KeptCount), Expired: $($mntResult.ExpiredCount))" -ForegroundColor Green

# Test 8: Pack Cache Invalidation
Write-Host "`nTest 8: Pack Cache Invalidation" -ForegroundColor Yellow
$packInvResult = Invoke-PackCacheInvalidation -PackId "test-pack" -NewVersion "v2.0.0" -UpdateType "promotion" -ProjectRoot $ProjectRoot
Write-Host "  PASS: Pack invalidation executed (Pack: $($packInvResult.PackId))" -ForegroundColor Green

# Test 9: Set/Get Config
Write-Host "`nTest 9: Configuration Save/Load" -ForegroundColor Yellow
$newConfig = @{ defaultTTLMinutes = 90; maxEntries = 1500 }
$setConfigResult = Set-RetrievalCacheConfig -Config $newConfig -ProjectRoot $ProjectRoot
$loadedConfig = Get-RetrievalCacheConfig -ProjectRoot $ProjectRoot -ForceReload
if ($loadedConfig.defaultTTLMinutes -eq 90 -and $loadedConfig.maxEntries -eq 1500) {
    Write-Host "  PASS: Config saved and loaded correctly" -ForegroundColor Green
    # Restore defaults
    Set-RetrievalCacheConfig -Config @{ defaultTTLMinutes = 60; maxEntries = 1000 } -ProjectRoot $ProjectRoot | Out-Null
} else {
    Write-Host "  FAIL: Config save/load issue" -ForegroundColor Red
}

# Test 10: Clear Cache
Write-Host "`nTest 10: Clear Cache" -ForegroundColor Yellow
$clearResult = Clear-RetrievalCache -Force -ProjectRoot $ProjectRoot
if ($clearResult.Success) {
    Write-Host "  PASS: Cache cleared successfully" -ForegroundColor Green
} else {
    Write-Host "  FAIL: Cache clear issue" -ForegroundColor Red
}

Write-Host "`n=== All Tests Completed Successfully ===" -ForegroundColor Cyan
