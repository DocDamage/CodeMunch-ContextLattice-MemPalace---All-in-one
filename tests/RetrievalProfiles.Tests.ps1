#requires -Version 5.1
<#
.SYNOPSIS
    Unit tests for the RetrievalProfiles module.

.DESCRIPTION
    Tests all public functions of the RetrievalProfiles module to ensure
    correct behavior for built-in profiles and custom profile creation.
#>

$ErrorActionPreference = 'Stop'

# Import the module
$projectRoot = Split-Path -Parent $PSScriptRoot
$modulePath = [System.IO.Path]::Combine($projectRoot, 'module', 'LLMWorkflow', 'retrieval', 'RetrievalProfiles.ps1')
Import-Module $modulePath -Force

$testResults = @{
    Passed = 0
    Failed = 0
    Tests = @()
}

function Test-Assertion {
    param(
        [string]$Name,
        [scriptblock]$Test
    )
    
    try {
        & $Test
        $testResults.Passed++
        $testResults.Tests += @{ Name = $Name; Result = 'PASSED'; Error = $null }
        Write-Host "  [PASS] $Name" -ForegroundColor Green
    }
    catch {
        $testResults.Failed++
        $testResults.Tests += @{ Name = $Name; Result = 'FAILED'; Error = $_.Exception.Message }
        Write-Host "  [FAIL] $Name : $($_.Exception.Message)" -ForegroundColor Red
    }
}

Write-Host "`n=== Testing RetrievalProfiles Module ===`n" -ForegroundColor Cyan

# Test 1: Get-AllRetrievalProfiles
Write-Host "Test Group: Get-AllRetrievalProfiles" -ForegroundColor Yellow
Test-Assertion "Returns array of profiles" {
    $profiles = Get-AllRetrievalProfiles
    if ($profiles -eq $null -or $profiles.Count -eq 0) { throw "No profiles returned" }
    if ($profiles.Count -ne 7) { throw "Expected 7 built-in profiles, got $($profiles.Count)" }
}

Test-Assertion "Each profile has required fields" {
    $profiles = Get-AllRetrievalProfiles
    foreach ($p in $profiles) {
        if (-not $p.name) { throw "Profile missing name" }
        if (-not $p.description) { throw "Profile missing description" }
        if (-not $p.category) { throw "Profile missing category" }
    }
}

Test-Assertion "All 7 built-in profiles present" {
    $profiles = Get-AllRetrievalProfiles
    $expected = @('api-lookup', 'plugin-pattern', 'conflict-diagnosis', 'codegen', 
                  'private-project-first', 'tooling-workflow', 'reverse-format')
    foreach ($exp in $expected) {
        if (($profiles | Where-Object { $_.name -eq $exp }).Count -eq 0) {
            throw "Missing profile: $exp"
        }
    }
}

# Test 2: Get-RetrievalProfileConfig
Write-Host "`nTest Group: Get-RetrievalProfileConfig" -ForegroundColor Yellow

Test-Assertion "Returns correct profile for api-lookup" {
    $profile = Get-RetrievalProfileConfig -ProfileName 'api-lookup'
    if ($profile -eq $null) { throw "Profile not found" }
    if ($profile.name -ne 'api-lookup') { throw "Wrong profile name" }
    if ($profile.minTrustTier -ne 'high') { throw "Wrong minTrustTier" }
}

Test-Assertion "Returns correct profile for plugin-pattern" {
    $profile = Get-RetrievalProfileConfig -ProfileName 'plugin-pattern'
    if ($profile -eq $null) { throw "Profile not found" }
    if ($profile.minTrustTier -ne 'medium') { throw "Wrong minTrustTier" }
    if ($profile.requireMultipleSources -ne $true) { throw "requireMultipleSources should be true" }
}

Test-Assertion "Returns correct profile for conflict-diagnosis" {
    $profile = Get-RetrievalProfileConfig -ProfileName 'conflict-diagnosis'
    if ($profile -eq $null) { throw "Profile not found" }
    if ($profile.minTrustTier -ne 'medium-high') { throw "Wrong minTrustTier" }
    if ($profile.config.crossSourceComparison -ne $true) { throw "crossSourceComparison should be true" }
}

Test-Assertion "Returns correct profile for codegen" {
    $profile = Get-RetrievalProfileConfig -ProfileName 'codegen'
    if ($profile -eq $null) { throw "Profile not found" }
    if ($profile.minTrustTier -ne 'medium-high') { throw "Wrong minTrustTier" }
    if ($profile.config.multipleSourceAggregation -ne $true) { throw "multipleSourceAggregation should be true" }
}

Test-Assertion "Returns correct profile for private-project-first" {
    $profile = Get-RetrievalProfileConfig -ProfileName 'private-project-first'
    if ($profile -eq $null) { throw "Profile not found" }
    if ($profile.privateProjectFirst -ne $true) { throw "privateProjectFirst should be true" }
    if ($profile.config.labelFallbacksExplicitly -ne $true) { throw "labelFallbacksExplicitly should be true" }
}

Test-Assertion "Returns correct profile for tooling-workflow" {
    $profile = Get-RetrievalProfileConfig -ProfileName 'tooling-workflow'
    if ($profile -eq $null) { throw "Profile not found" }
    if ($profile.minTrustTier -ne 'medium') { throw "Wrong minTrustTier" }
}

Test-Assertion "Returns correct profile for reverse-format" {
    $profile = Get-RetrievalProfileConfig -ProfileName 'reverse-format'
    if ($profile -eq $null) { throw "Profile not found" }
    if ($profile.config.specialHandlingDecompilation -ne $true) { throw "specialHandlingDecompilation should be true" }
}

Test-Assertion "Returns null for nonexistent profile" {
    $profile = Get-RetrievalProfileConfig -ProfileName 'nonexistent-profile'
    if ($profile -ne $null) { throw "Should return null for nonexistent profile" }
}

Test-Assertion "Profile config is a deep copy (modification doesn't affect original)" {
    $profile1 = Get-RetrievalProfileConfig -ProfileName 'api-lookup'
    $profile2 = Get-RetrievalProfileConfig -ProfileName 'api-lookup'
    $profile1.description = "MODIFIED"
    if ($profile2.description -eq "MODIFIED") { throw "Profile not deep copied" }
}

# Test 3: Test-RetrievalProfileExists
Write-Host "`nTest Group: Test-RetrievalProfileExists" -ForegroundColor Yellow

Test-Assertion "Returns true for built-in profiles" {
    if (-not (Test-RetrievalProfileExists -ProfileName 'api-lookup')) { throw "Should exist" }
    if (-not (Test-RetrievalProfileExists -ProfileName 'codegen')) { throw "Should exist" }
}

Test-Assertion "Returns false for nonexistent profile" {
    if (Test-RetrievalProfileExists -ProfileName 'nonexistent') { throw "Should not exist" }
}

Test-Assertion "Case insensitive matching" {
    if (-not (Test-RetrievalProfileExists -ProfileName 'API-LOOKUP')) { throw "Should be case insensitive" }
    if (-not (Test-RetrievalProfileExists -ProfileName 'Codegen')) { throw "Should be case insensitive" }
}

# Test 4: Get-ProfilePackPreferences
Write-Host "`nTest Group: Get-ProfilePackPreferences" -ForegroundColor Yellow

Test-Assertion "Returns pack preferences for api-lookup" {
    $prefs = Get-ProfilePackPreferences -ProfileName 'api-lookup'
    if ($prefs.Count -eq 0) { throw "No preferences returned" }
    if ($prefs[0] -ne 'core_api') { throw "First preference should be core_api" }
}

Test-Assertion "Returns empty array for nonexistent profile" {
    $prefs = Get-ProfilePackPreferences -ProfileName 'nonexistent'
    if (($prefs | Measure-Object).Count -ne 0) { throw "Should return empty array" }
}

Test-Assertion "Filters against available packs when provided" {
    $available = @('core_api', 'tooling')
    $prefs = Get-ProfilePackPreferences -ProfileName 'api-lookup' -AvailablePacks $available
    if ($prefs.Count -eq 0) { throw "Should have some matches" }
}

# Test 5: Get-ProfileEvidenceTypes
Write-Host "`nTest Group: Get-ProfileEvidenceTypes" -ForegroundColor Yellow

Test-Assertion "Returns evidence types for codegen" {
    $types = Get-ProfileEvidenceTypes -ProfileName 'codegen'
    if ($types.Count -eq 0) { throw "No types returned" }
    if ($types -notcontains 'code-example') { throw "Should include code-example" }
}

Test-Assertion "Returns correct evidence types for api-lookup" {
    $types = Get-ProfileEvidenceTypes -ProfileName 'api-lookup'
    if ($types -notcontains 'api-reference') { throw "Should include api-reference" }
    if ($types -notcontains 'schema-definition') { throw "Should include schema-definition" }
}

# Test 6: New-CustomRetrievalProfile
Write-Host "`nTest Group: New-CustomRetrievalProfile" -ForegroundColor Yellow

Test-Assertion "Creates custom profile successfully" {
    $config = @{
        description = 'Test custom profile'
        packPreferences = @('pack1', 'pack2')
        evidenceTypes = @('code-example', 'configuration')
    }
    $profile = New-CustomRetrievalProfile -ProfileName 'test-custom' -Config $config
    if ($profile.name -ne 'test-custom') { throw "Wrong profile name" }
    if ($profile.description -ne 'Test custom profile') { throw "Wrong description" }
}

Test-Assertion "Custom profile appears in Get-AllRetrievalProfiles" {
    if (-not (Test-RetrievalProfileExists -ProfileName 'test-custom')) { throw "Custom profile not found" }
}

Test-Assertion "Cannot create profile with empty name" {
    $config = @{ description = 'Test'; packPreferences = @('p1'); evidenceTypes = @('t1') }
    try {
        New-CustomRetrievalProfile -ProfileName '' -Config $config
        throw "Should have thrown exception"
    }
    catch { }
}

Test-Assertion "Cannot create profile without description" {
    $config = @{ packPreferences = @('p1'); evidenceTypes = @('t1') }
    try {
        New-CustomRetrievalProfile -ProfileName 'test-bad' -Config $config
        throw "Should have thrown exception"
    }
    catch { }
}

Test-Assertion "Cannot create profile without packPreferences" {
    $config = @{ description = 'Test'; evidenceTypes = @('t1') }
    try {
        New-CustomRetrievalProfile -ProfileName 'test-bad' -Config $config
        throw "Should have thrown exception"
    }
    catch { }
}

Test-Assertion "Cannot create profile without evidenceTypes" {
    $config = @{ description = 'Test'; packPreferences = @('p1') }
    try {
        New-CustomRetrievalProfile -ProfileName 'test-bad' -Config $config
        throw "Should have thrown exception"
    }
    catch { }
}

Test-Assertion "Cannot overwrite built-in profile" {
    $config = @{ description = 'Test'; packPreferences = @('p1'); evidenceTypes = @('t1') }
    try {
        New-CustomRetrievalProfile -ProfileName 'api-lookup' -Config $config
        throw "Should have thrown exception"
    }
    catch { }
}

# Test 7: Additional utility functions
Write-Host "`nTest Group: Additional Utility Functions" -ForegroundColor Yellow

Test-Assertion "Get-ProfileMinTrustTier returns correct value" {
    $tier = Get-ProfileMinTrustTier -ProfileName 'api-lookup'
    if ($tier -ne 'high') { throw "Expected 'high', got '$tier'" }
}

Test-Assertion "Test-ProfileRequiresMultipleSources returns correct value" {
    $result = Test-ProfileRequiresMultipleSources -ProfileName 'plugin-pattern'
    if (-not $result) { throw "Should be true for plugin-pattern" }
    
    $result = Test-ProfileRequiresMultipleSources -ProfileName 'api-lookup'
    if ($result) { throw "Should be false for api-lookup" }
}

Test-Assertion "Get-ProfileCategories returns categories" {
    $categories = Get-ProfileCategories
    if ($categories.Count -eq 0) { throw "No categories returned" }
    $refCat = $categories | Where-Object { $_.name -eq 'reference' }
    if ($refCat.Count -eq 0) { throw "Reference category not found" }
}

# Test 8: Profile-specific configuration validation
Write-Host "`nTest Group: Profile Configuration Validation" -ForegroundColor Yellow

Test-Assertion "api-lookup has requireAuthorityRole specified" {
    $profile = Get-RetrievalProfileConfig -ProfileName 'api-lookup'
    if ($profile.config.requireAuthorityRole.Count -eq 0) { throw "Should have authority roles" }
}

Test-Assertion "private-project-first has fallback configuration" {
    $profile = Get-RetrievalProfileConfig -ProfileName 'private-project-first'
    if ($profile.config.fallbackToPublic -ne $true) { throw "fallbackToPublic should be true" }
    if (-not $profile.config.fallbackLabelFormat) { throw "Should have fallbackLabelFormat" }
}

Test-Assertion "reverse-format has deconfiguration settings" {
    $profile = Get-RetrievalProfileConfig -ProfileName 'reverse-format'
    if ($profile.config.warnOnLegalIssues -ne $true) { throw "warnOnLegalIssues should be true" }
}

# Summary
Write-Host "`n=== Test Summary ===" -ForegroundColor Cyan
Write-Host "Passed: $($testResults.Passed)" -ForegroundColor Green
Write-Host "Failed: $($testResults.Failed)" -ForegroundColor $(if ($testResults.Failed -gt 0) { 'Red' } else { 'Green' })

if ($testResults.Failed -gt 0) {
    exit 1
}
