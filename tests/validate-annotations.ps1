#requires -Version 5.1
<#
.SYNOPSIS
    Validation tests for the HumanAnnotations module.
#>
param(
    [string]$ProjectRoot = (Split-Path -Parent $PSScriptRoot)
)

$ErrorActionPreference = 'Continue'
Set-Location $ProjectRoot

Write-Host '=== HumanAnnotations Module Validation ===' -ForegroundColor Cyan

# Load module via dot-sourcing (consistent with project pattern)
$ModuleRoot = Join-Path $ProjectRoot 'module\LLMWorkflow'
$HumanAnnotationsPath = Join-Path $ModuleRoot 'governance\HumanAnnotations.ps1'

# Suppress Export-ModuleMember warning
$null = . $HumanAnnotationsPath 2>&1

# Test 1: Module exports
Write-Host 'Test 1: Module exports' -ForegroundColor Yellow
$functions = Get-Command | Where-Object { $_.Name -in @(
    'New-HumanAnnotation', 'Get-EntityAnnotations', 'Apply-Annotations',
    'New-ProjectOverride', 'Get-EffectiveAnnotations', 'Export-Annotations',
    'Import-Annotations', 'Get-AnnotationRegistry', 'Register-Annotation',
    'Update-Annotation', 'Vote-Annotation', 'Remove-Annotation'
)}
Write-Host "  Found $($functions.Count) functions"
if ($functions.Count -ne 12) {
    Write-Error "Expected 12 functions, found $($functions.Count)"
    exit 1
}

# Test 2: Get-AnnotationRegistry
Write-Host 'Test 2: Get-AnnotationRegistry' -ForegroundColor Yellow
$reg = Get-AnnotationRegistry
Write-Host "  Schema Version: $($reg.SchemaVersion)"
Write-Host "  Annotation Types: $($reg.ValidTypes.AnnotationTypes -join ', ')"
if ($reg.SchemaVersion -ne 1) {
    Write-Error "Expected schema version 1"
    exit 1
}

# Test 3: Create annotation
Write-Host 'Test 3: New-HumanAnnotation' -ForegroundColor Yellow
$ann = New-HumanAnnotation -EntityId 'test-001' -EntityType 'source' -AnnotationType 'correction' -Content 'Test correction' -Author 'tester'
Write-Host "  Created: $($ann.annotationId)"
$script:testId = $ann.annotationId
if (-not $ann.annotationId) {
    Write-Error "Annotation ID not generated"
    exit 1
}

# Test 4: Get annotations
Write-Host 'Test 4: Get-EntityAnnotations' -ForegroundColor Yellow
$annotations = Get-EntityAnnotations -EntityId 'test-001'
Write-Host "  Found $($annotations.Count) annotation(s)"
if ($annotations.Count -lt 1) {
    Write-Error "Expected at least 1 annotation"
    exit 1
}

# Test 5: Vote
Write-Host 'Test 5: Vote-Annotation' -ForegroundColor Yellow
$vote = Vote-Annotation -AnnotationId $script:testId -Vote up
Write-Host "  Score: $($vote.Score) (Up: $($vote.TotalUp))"
if ($vote.TotalUp -ne 1) {
    Write-Error "Expected 1 upvote"
    exit 1
}

# Test 6: Project override
Write-Host 'Test 6: New-ProjectOverride' -ForegroundColor Yellow
$ovr = New-ProjectOverride -ProjectId 'test-proj' -EntityId 'pack-001' -OverrideData @{ version = '1.0' } -Reason 'Test override'
Write-Host "  Created override: $($ovr.annotationId)"
if (-not $ovr.annotationId) {
    Write-Error "Override ID not generated"
    exit 1
}

# Test 7: Get effective
Write-Host 'Test 7: Get-EffectiveAnnotations' -ForegroundColor Yellow
$eff = Get-EffectiveAnnotations -EntityId 'test-001'
Write-Host "  Effective count: $($eff.annotationCount)"
if ($eff.annotationCount -lt 1) {
    Write-Error "Expected at least 1 effective annotation"
    exit 1
}

# Test 8: Export
Write-Host 'Test 8: Export-Annotations' -ForegroundColor Yellow
$exportPath = Join-Path $ProjectRoot 'test-export.json'
$exp = Export-Annotations -OutputPath $exportPath -Filter @{ entityIds = @('test-001') }
Write-Host "  Exported $($exp.Count) annotation(s)"
if ($exp.Count -lt 1) {
    Write-Error "Expected at least 1 exported annotation"
    exit 1
}

# Test 9: Apply annotations
Write-Host 'Test 9: Apply-Annotations' -ForegroundColor Yellow
$target = @{ content = 'Original'; confidence = 0.9 }
$applied = Apply-Annotations -Target $target -Annotations $eff.annotations
Write-Host "  Applied $($applied._annotationCount) annotation(s)"

# Test 10: Update annotation
Write-Host 'Test 10: Update-Annotation' -ForegroundColor Yellow
$updated = Update-Annotation -AnnotationId $script:testId -Content 'Updated content'
Write-Host "  Updated content: $($updated.content)"
if ($updated.content -ne 'Updated content') {
    Write-Error "Content not updated"
    exit 1
}

# Test 11: Register annotation
Write-Host 'Test 11: Register-Annotation' -ForegroundColor Yellow
$manualAnn = @{
    entityId = 'manual-test'
    entityType = 'source'
    annotationType = 'caveat'
    content = 'Manual annotation'
    author = 'tester'
}
$registered = Register-Annotation -Annotation $manualAnn
Write-Host "  Registered: $($registered.annotationId)"
if (-not $registered.annotationId) {
    Write-Error "Registered annotation ID not generated"
    exit 1
}

# Cleanup
Remove-Item $exportPath -Force -ErrorAction SilentlyContinue

Write-Host ''
Write-Host '=== All validation tests passed! ===' -ForegroundColor Green
