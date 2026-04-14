#requires -Version 5.1
<#
.SYNOPSIS
    Pack Framework Tests for LLM Workflow Platform

.DESCRIPTION
    Pester v5 test suite for pack framework modules:
    - PackManifest.ps1: Pack manifest management
    - SourceRegistry.ps1: Source registry management
    - PackTransaction.ps1: Pack transactions and lockfiles

.NOTES
    File: PackFramework.Tests.ps1
    Version: 1.0.0
    Author: LLM Workflow Team
    Requires: Pester 5.0+
#>

BeforeAll {
    # Set up test environment
    $script:TestRoot = Join-Path $TestDrive "PackFrameworkTests"
    $script:ModuleRoot = Join-Path (Join-Path $PSScriptRoot "..") "module\LLMWorkflow"
    $script:PackModulePath = Join-Path $ModuleRoot "pack"
    
    # Create test directories
    New-Item -ItemType Directory -Path $script:TestRoot -Force | Out-Null
    New-Item -ItemType Directory -Path (Join-Path $script:TestRoot "packs") -Force | Out-Null
    New-Item -ItemType Directory -Path (Join-Path (Join-Path $script:TestRoot "packs") "manifests") -Force | Out-Null
    New-Item -ItemType Directory -Path (Join-Path (Join-Path $script:TestRoot "packs") "registries") -Force | Out-Null
    New-Item -ItemType Directory -Path (Join-Path (Join-Path $script:TestRoot "packs") "staging") -Force | Out-Null
    New-Item -ItemType Directory -Path (Join-Path (Join-Path $script:TestRoot "packs") "promoted") -Force | Out-Null
    
    # Import modules
    $packManifestPath = Join-Path $script:PackModulePath "PackManifest.ps1"
    $sourceRegistryPath = Join-Path $script:PackModulePath "SourceRegistry.ps1"
    $packTransactionPath = Join-Path $script:PackModulePath "PackTransaction.ps1"
    
    if (Test-Path $packManifestPath) { try { . $packManifestPath } catch { if ($_.Exception.Message -notlike "*Export-ModuleMember*") { throw } } }
    if (Test-Path $sourceRegistryPath) { try { . $sourceRegistryPath } catch { if ($_.Exception.Message -notlike "*Export-ModuleMember*") { throw } } }
    if (Test-Path $packTransactionPath) { try { . $packTransactionPath } catch { if ($_.Exception.Message -notlike "*Export-ModuleMember*") { throw } } }
}

Describe "PackManifest Module Tests" {
    Context "New-PackManifest Function" {
        It "Should create valid pack manifests" {
            $manifest = New-PackManifest -PackId "rpgmaker-mz" -Domain "game-dev" -Version "1.0.0-draft"
            
            $manifest | Should -Not -BeNullOrEmpty
            $manifest.schemaVersion | Should -Be 1
            $manifest.packId | Should -Be "rpgmaker-mz"
            $manifest.domain | Should -Be "game-dev"
            $manifest.version | Should -Be "1.0.0-draft"
            $manifest.status | Should -Be "draft"
            $manifest.channel | Should -Be "draft"
            $manifest.createdUtc | Should -Not -BeNullOrEmpty
            $manifest.updatedUtc | Should -Not -BeNullOrEmpty
            $manifest.createdByRunId | Should -Not -BeNullOrEmpty
        }

        It "Should validate packId format" {
            { New-PackManifest -PackId "Invalid_Pack" -Domain "test" -Version "1.0.0" } | 
                Should -Throw -ExpectedMessage "*Cannot validate argument on parameter*"
        }

        It "Should validate version format" {
            { New-PackManifest -PackId "test-pack" -Domain "test" -Version "invalid" } | 
                Should -Throw -ExpectedMessage "*Cannot validate argument on parameter*"
        }

        It "Should accept valid lifecycle states" {
            $states = @('draft', 'building', 'staged', 'validated', 'promoted', 'deprecated', 'retired', 'removed')
            foreach ($state in $states) {
                $manifest = New-PackManifest -PackId "test-$state" -Domain "test" -Version "1.0.0" -Status $state
                $manifest.status | Should -Be $state
            }
        }

        It "Should accept valid channels" {
            $channels = @('draft', 'candidate', 'stable', 'frozen')
            foreach ($channel in $channels) {
                $manifest = New-PackManifest -PackId "test-$channel" -Domain "test" -Version "1.0.0" -Channel $channel
                $manifest.channel | Should -Be $channel
            }
        }

        It "Should accept install profiles" {
            $profiles = @{
                minimal = @("src1", "src2")
                full = @("src1", "src2", "src3", "src4")
            }
            $manifest = New-PackManifest -PackId "test-profiles" -Domain "test" -Version "1.0.0" -InstallProfiles $profiles
            $manifest.installProfiles.minimal.Count | Should -Be 2
            $manifest.installProfiles.full.Count | Should -Be 4
        }
    }

    Context "Test-PackManifest Function" {
        It "Should validate required fields" {
            $manifest = @{ packId = "test"; domain = "test" }  # Missing version, status, channel
            $result = Test-PackManifest -Manifest $manifest
            
            $result.isValid | Should -Be $false
            $result.errors | Should -Contain "Missing required field: version"
            $result.errors | Should -Contain "Missing required field: status"
            $result.errors | Should -Contain "Missing required field: channel"
        }

        It "Should validate packId format" {
            $manifest = @{
                packId = "Invalid Pack"  # Space not allowed
                domain = "test"
                version = "1.0.0"
                status = "draft"
                channel = "draft"
            }
            $result = Test-PackManifest -Manifest $manifest
            
            $result.isValid | Should -Be $false
            $result.errors | Should -Contain "Invalid packId format: must be lowercase alphanumeric with hyphens only"
        }

        It "Should validate semantic versioning" {
            $manifest = @{
                packId = "test"
                domain = "test"
                version = "1.0"  # Missing patch version
                status = "draft"
                channel = "draft"
            }
            $result = Test-PackManifest -Manifest $manifest
            
            $result.isValid | Should -Be $false
            $result.errors | Should -Contain "Invalid version format: must follow semantic versioning"
        }

        It "Should pass valid manifests" {
            $manifest = @{
                packId = "valid-pack"
                domain = "test-domain"
                version = "1.0.0-alpha"
                status = "draft"
                channel = "draft"
            }
            $result = Test-PackManifest -Manifest $manifest
            
            $result.isValid | Should -Be $true
            $result.errors.Count | Should -Be 0
        }

        It "Should validate install profile names" {
            $manifest = @{
                packId = "test"
                domain = "test"
                version = "1.0.0"
                status = "draft"
                channel = "draft"
                installProfiles = @{
                    invalid = @("src1")
                }
            }
            $result = Test-PackManifest -Manifest $manifest
            
            $result.isValid | Should -Be $false
            $result.errors | Should -Contain "Invalid install profile name: invalid"
        }
    }

    Context "Set-PackLifecycleState Function" {
        It "Should transition states correctly" {
            $manifest = New-PackManifest -PackId "test-lifecycle" -Domain "test" -Version "1.0.0" -Status "validated"
            
            $result = Set-PackLifecycleState -Manifest $manifest -NewStatus "promoted" -Reason "Evaluation passed"
            
            $result.status | Should -Be "promoted"
            $result.lifecycleHistory.Count | Should -Be 1
            $result.lifecycleHistory[0].fromStatus | Should -Be "validated"
            $result.lifecycleHistory[0].toStatus | Should -Be "promoted"
            $result.lifecycleHistory[0].reason | Should -Be "Evaluation passed"
        }

        It "Should block invalid transitions to promoted" {
            $manifest = New-PackManifest -PackId "test-invalid" -Domain "test" -Version "1.0.0" -Status "draft"
            
            $result = Set-PackLifecycleState -Manifest $manifest -NewStatus "promoted"
            $result | Should -BeNullOrEmpty
            $manifest.status | Should -Be "draft"  # Unchanged
        }

        It "Should block building->promoted transition" {
            $manifest = New-PackManifest -PackId "test-invalid2" -Domain "test" -Version "1.0.0" -Status "building"
            
            $result = Set-PackLifecycleState -Manifest $manifest -NewStatus "promoted"
            $result | Should -BeNullOrEmpty
        }

        It "Should track multiple transitions" {
            $manifest = New-PackManifest -PackId "test-multi" -Domain "test" -Version "1.0.0" -Status "draft"
            
            Set-PackLifecycleState -Manifest $manifest -NewStatus "building" | Out-Null
            Set-PackLifecycleState -Manifest $manifest -NewStatus "staged" | Out-Null
            Set-PackLifecycleState -Manifest $manifest -NewStatus "validated" | Out-Null
            
            $manifest.lifecycleHistory.Count | Should -Be 3
        }
    }

    Context "Save-PackManifest and Get-PackManifest Functions" {
        It "Should save and load manifests" {
            $manifest = New-PackManifest -PackId "test-save" -Domain "test" -Version "1.0.0"
            $testPath = Join-Path (Join-Path (Join-Path $script:TestRoot "packs") "manifests") "test-save.json"
            
            Save-PackManifest -Manifest $manifest -Path $testPath | Out-Null
            
            Test-Path $testPath | Should -Be $true
            
            $loaded = Get-PackManifest -Path $testPath
            $loaded.packId | Should -Be "test-save"
            $loaded.domain | Should -Be "test"
            $loaded.version | Should -Be "1.0.0"
        }

        It "Should use default path when not specified" {
            $manifest = New-PackManifest -PackId "default-path" -Domain "test" -Version "1.0.0"
            
            $savedPath = Save-PackManifest -Manifest $manifest
            
            $savedPath | Should -BeLike "*packs/manifests/default-path.json"
        }

        It "Should load by packId" {
            $manifest = New-PackManifest -PackId "load-by-id" -Domain "test" -Version "1.0.0"
            Save-PackManifest -Manifest $manifest -Path (Join-Path (Join-Path (Join-Path $script:TestRoot "packs") "manifests") "load-by-id.json") | Out-Null
            
            Push-Location $script:TestRoot
            try {
                $loaded = Get-PackManifest -PackId "load-by-id"
                $loaded.packId | Should -Be "load-by-id"
            }
            finally {
                Pop-Location
            }
        }
    }

    Context "Get-PackManifestList Function" {
        It "Should list all manifests" {
            $manifest1 = New-PackManifest -PackId "list-test-1" -Domain "game-dev" -Version "1.0.0"
            $manifest2 = New-PackManifest -PackId "list-test-2" -Domain "3d-graphics" -Version "2.0.0"
            Save-PackManifest -Manifest $manifest1 -Path (Join-Path (Join-Path (Join-Path $script:TestRoot "packs") "manifests") "list-test-1.json") | Out-Null
            Save-PackManifest -Manifest $manifest2 -Path (Join-Path (Join-Path (Join-Path $script:TestRoot "packs") "manifests") "list-test-2.json") | Out-Null
            
            Push-Location $script:TestRoot
            try {
                $manifests = Get-PackManifestList
                $manifests.Count | Should -BeGreaterOrEqual 2
            }
            finally {
                Pop-Location
            }
        }

        It "Should filter by status" {
            $manifest1 = New-PackManifest -PackId "filter-status-1" -Domain "test" -Version "1.0.0" -Status "draft"
            $manifest2 = New-PackManifest -PackId "filter-status-2" -Domain "test" -Version "1.0.0" -Status "promoted"
            
            Save-PackManifest -Manifest $manifest1 -Path (Join-Path (Join-Path (Join-Path $script:TestRoot "packs") "manifests") "filter-status-1.json") | Out-Null
            Save-PackManifest -Manifest $manifest2 -Path (Join-Path (Join-Path (Join-Path $script:TestRoot "packs") "manifests") "filter-status-2.json") | Out-Null
            
            Push-Location $script:TestRoot
            try {
                $drafts = Get-PackManifestList -Status "draft"
                $promoted = Get-PackManifestList -Status "promoted"
                
                $drafts | Where-Object { $_.PackId -eq "filter-status-1" } | Should -Not -BeNullOrEmpty
                $promoted | Where-Object { $_.PackId -eq "filter-status-2" } | Should -Not -BeNullOrEmpty
            }
            finally {
                Pop-Location
            }
        }

        It "Should filter by domain" {
            $manifest1 = New-PackManifest -PackId "filter-domain-1" -Domain "game-dev" -Version "1.0.0"
            $manifest2 = New-PackManifest -PackId "filter-domain-2" -Domain "3d-graphics" -Version "1.0.0"
            
            Save-PackManifest -Manifest $manifest1 -Path (Join-Path (Join-Path (Join-Path $script:TestRoot "packs") "manifests") "filter-domain-1.json") | Out-Null
            Save-PackManifest -Manifest $manifest2 -Path (Join-Path (Join-Path (Join-Path $script:TestRoot "packs") "manifests") "filter-domain-2.json") | Out-Null
            
            Push-Location $script:TestRoot
            try {
                $gameDevs = Get-PackManifestList -Domain "game-dev"
                $gameDevs | Where-Object { $_.PackId -eq "filter-domain-1" } | Should -Not -BeNullOrEmpty
            }
            finally {
                Pop-Location
            }
        }
    }
}

Describe "SourceRegistry Module Tests" {
    Context "New-SourceRegistryEntry Function" {
        It "Should create valid source registry entries" {
            $entry = New-SourceRegistryEntry -SourceId "src-test" -RepoUrl "https://github.com/test/repo"
            
            $entry | Should -Not -BeNullOrEmpty
            $entry.schemaVersion | Should -Be 1
            $entry.sourceId | Should -Be "src-test"
            $entry.repoUrl | Should -Be "https://github.com/test/repo"
            $entry.selectedRef | Should -Be "main"
            $entry.parseMode | Should -Be "default"
            $entry.trustTier | Should -Be "Medium"
            $entry.priority | Should -Be "P2"
            $entry.state | Should -Be "active"
        }

        It "Should validate repoUrl format" {
            { New-SourceRegistryEntry -SourceId "invalid" -RepoUrl "ftp://invalid" } | 
                Should -Throw -ExpectedMessage "*Cannot validate argument on parameter*"
        }

        It "Should accept valid trust tiers" {
            $tiers = @('High', 'Medium-High', 'Medium', 'Low', 'Quarantined')
            foreach ($tier in $tiers) {
                $entry = New-SourceRegistryEntry -SourceId "test-$tier" -RepoUrl "https://github.com/test/repo" -TrustTier $tier
                $entry.trustTier | Should -Be $tier
            }
        }

        It "Should accept valid priority values" {
            $priorities = @('P0', 'P1', 'P2', 'P3', 'P4', 'P5')
            foreach ($priority in $priorities) {
                $entry = New-SourceRegistryEntry -SourceId "test-$priority" -RepoUrl "https://github.com/test/repo" -Priority $priority
                $entry.priority | Should -Be $priority
            }
        }

        It "Should accept engine metadata" {
            $entry = New-SourceRegistryEntry -SourceId "engine-test" -RepoUrl "https://github.com/test/repo" `
                -EngineTarget "godot-4.x" -EngineMinVersion "4.0" -EngineMaxVersion "4.2"
            
            $entry.engineTarget | Should -Be "godot-4.x"
            $entry.engineMinVersion | Should -Be "4.0"
            $entry.engineMaxVersion | Should -Be "4.2"
        }

        It "Should accept collections" {
            $entry = New-SourceRegistryEntry -SourceId "collections-test" -RepoUrl "https://github.com/test/repo" `
                -Collections @("core", "plugins", "examples")
            
            $entry.collections.Count | Should -Be 3
            $entry.collections | Should -Contain "core"
            $entry.collections | Should -Contain "plugins"
        }
    }

    Context "Test-SourceRegistryEntry Function" {
        It "Should validate required fields" {
            $entry = @{ repoUrl = "https://github.com/test/repo" }  # Missing sourceId
            $result = Test-SourceRegistryEntry -Entry $entry
            
            $result.isValid | Should -Be $false
            $result.errors | Should -Contain "Missing required field: sourceId"
        }

        It "Should validate URL format" {
            $entry = @{
                sourceId = "test"
                repoUrl = "not-a-url"
            }
            $result = Test-SourceRegistryEntry -Entry $entry
            
            $result.isValid | Should -Be $false
            $result.errors | Should -Contain "Invalid repoUrl: must be HTTP(S) URL"
        }

        It "Should validate trust tier" {
            $entry = @{
                sourceId = "test"
                repoUrl = "https://github.com/test/repo"
                trustTier = "Invalid"
            }
            $result = Test-SourceRegistryEntry -Entry $entry
            
            $result.isValid | Should -Be $false
            $result.errors | Should -Match "Invalid trustTier"
        }

        It "Should pass valid entries" {
            $entry = @{
                sourceId = "valid"
                repoUrl = "https://github.com/test/repo"
                trustTier = "High"
                state = "active"
            }
            $result = Test-SourceRegistryEntry -Entry $entry
            
            $result.isValid | Should -Be $true
            $result.errors.Count | Should -Be 0
        }
    }

    Context "Get-RetrievalPrioritySources Function" {
        It "Should order sources by priority" {
            $sources = @{
                src1 = New-SourceRegistryEntry -SourceId "src1" -RepoUrl "https://github.com/test/1" -Priority "P2"
                src0 = New-SourceRegistryEntry -SourceId "src0" -RepoUrl "https://github.com/test/0" -Priority "P0"
                src3 = New-SourceRegistryEntry -SourceId "src3" -RepoUrl "https://github.com/test/3" -Priority "P3"
            }
            
            $registry = @{ sources = $sources }
            $result = Get-RetrievalPrioritySources -Registry $registry
            
            $result.Count | Should -Be 3
            $result[0].priority | Should -Be "P0"
            $result[1].priority | Should -Be "P2"
            $result[2].priority | Should -Be "P3"
        }

        It "Should filter by collection" {
            $sources = @{
                src1 = New-SourceRegistryEntry -SourceId "src1" -RepoUrl "https://github.com/test/1" -Collections @("core")
                src2 = New-SourceRegistryEntry -SourceId "src2" -RepoUrl "https://github.com/test/2" -Collections @("plugins")
            }
            
            $registry = @{ sources = $sources }
            $result = Get-RetrievalPrioritySources -Registry $registry -Collection "core"
            
            $result.Count | Should -Be 1
            $result[0].sourceId | Should -Be "src1"
        }

        It "Should exclude inactive sources" {
            $sources = @{
                active = New-SourceRegistryEntry -SourceId "active" -RepoUrl "https://github.com/test/active"
                inactive = New-SourceRegistryEntry -SourceId "inactive" -RepoUrl "https://github.com/test/inactive"
            }
            $sources.inactive.state = "retired"
            
            $registry = @{ sources = $sources }
            $result = Get-RetrievalPrioritySources -Registry $registry
            
            $result.Count | Should -Be 1
            $result[0].sourceId | Should -Be "active"
        }
    }

    Context "Suspend-SourceQuarantine Function" {
        It "Should quarantine unsafe sources" {
            $entry = New-SourceRegistryEntry -SourceId "suspicious" -RepoUrl "https://github.com/test/repo"
            
            $result = Suspend-SourceQuarantine -Entry $entry -Reason "Suspicious binary content" -ReviewDate "2026-05-01"
            
            $result.state | Should -Be "quarantined"
            $result.quarantineReason | Should -Be "Suspicious binary content"
            $result.quarantineDate | Should -Not -BeNullOrEmpty
            $result.quarantineReviewDate | Should -Be "2026-05-01"
            $result.stateHistory.Count | Should -Be 1
        }

        It "Should track quarantine in state history" {
            $entry = New-SourceRegistryEntry -SourceId "track-quarantine" -RepoUrl "https://github.com/test/repo"
            $entry.state = "active"
            
            Suspend-SourceQuarantine -Entry $entry -Reason "Test" | Out-Null
            
            $entry.stateHistory[0].fromState | Should -Be "active"
            $entry.stateHistory[0].toState | Should -Be "quarantined"
            $entry.stateHistory[0].reason | Should -Be "Test"
        }
    }

    Context "Save-SourceRegistry and Get-SourceRegistry Functions" {
        It "Should save and load source registries" {
            $sources = @{
                src1 = New-SourceRegistryEntry -SourceId "src1" -RepoUrl "https://github.com/test/1"
                src2 = New-SourceRegistryEntry -SourceId "src2" -RepoUrl "https://github.com/test/2"
            }
            
            $savePath = Join-Path (Join-Path (Join-Path $script:TestRoot "packs") "registries") "test-save.sources.json"
            Save-SourceRegistry -PackId "test-save" -Sources $sources -Path $savePath | Out-Null
            
            Test-Path $savePath | Should -Be $true
            
            $loaded = Get-SourceRegistry -PackId "test-save" -Path $savePath
            $loaded.packId | Should -Be "test-save"
            $loaded.sources.src1.sourceId | Should -Be "src1"
            $loaded.sources.src2.sourceId | Should -Be "src2"
        }

        It "Should return empty registry for non-existent pack" {
            $loaded = Get-SourceRegistry -PackId "non-existent" -Path (Join-Path $script:TestRoot "non-existent.json")
            $loaded.packId | Should -Be "non-existent"
            $loaded.sources.Count | Should -Be 0
        }
    }
}

Describe "PackTransaction Module Tests" {
    Context "New-PackTransaction Function" {
        It "Should create valid transactions" {
            $transaction = New-PackTransaction -PackId "rpgmaker-mz" -PackVersion "1.0.0"
            
            $transaction | Should -Not -BeNullOrEmpty
            $transaction.schemaVersion | Should -Be 1
            $transaction.packId | Should -Be "rpgmaker-mz"
            $transaction.packVersion | Should -Be "1.0.0"
            $transaction.state | Should -Be "prepare"
            $transaction.stages.prepare.status | Should -Be "in-progress"
            $transaction.createdUtc | Should -Not -BeNullOrEmpty
        }

        It "Should support parent transactions" {
            $parent = New-PackTransaction -PackId "test" -PackVersion "1.0.0"
            $child = New-PackTransaction -PackId "test" -PackVersion "1.1.0" -ParentTransactionId $parent.transactionId
            
            $child.parentTransactionId | Should -Be $parent.transactionId
        }
    }

    Context "Move-PackTransactionStage Function" {
        It "Should advance through stages correctly" {
            $transaction = New-PackTransaction -PackId "test" -PackVersion "1.0.0"
            
            # Move to build
            $transaction = Move-PackTransactionStage -Transaction $transaction -Stage "build" -Success $true
            $transaction.state | Should -Be "build"
            $transaction.stages.prepare.status | Should -Be "completed"
            $transaction.stages.build.status | Should -Be "in-progress"
            
            # Move to validate
            $transaction = Move-PackTransactionStage -Transaction $transaction -Stage "validate" -Success $true
            $transaction.state | Should -Be "validate"
            $transaction.stages.build.status | Should -Be "completed"
            $transaction.stages.validate.status | Should -Be "in-progress"
        }

        It "Should transition to rollback on failure" {
            $transaction = New-PackTransaction -PackId "test" -PackVersion "1.0.0"
            $transaction = Move-PackTransactionStage -Transaction $transaction -Stage "build" -Success $false -Errors @("Build failed")
            
            $transaction.state | Should -Be "rollback"
            $transaction.stages.prepare.status | Should -Be "completed"
            $transaction.stages.prepare.errors.Count | Should -Be 0
        }

        It "Should track errors in stage" {
            $transaction = New-PackTransaction -PackId "test" -PackVersion "1.0.0"
            $transaction = Move-PackTransactionStage -Transaction $transaction -Stage "build" -Success $false `
                -Errors @("Error 1", "Error 2")
            
            $transaction.stages.build.errors.Count | Should -Be 2
            $transaction.stages.build.errors | Should -Contain "Error 1"
        }
    }

    Context "New-PackLockfile Function" {
        It "Should generate deterministic lockfiles" {
            $sources = @(
                @{ sourceId = "src1"; repoUrl = "https://github.com/test/1"; selectedRef = "main"; resolvedCommit = "abc123" }
                @{ sourceId = "src2"; repoUrl = "https://github.com/test/2"; selectedRef = "v1.0"; resolvedCommit = "def456" }
            )
            
            $lockfile1 = New-PackLockfile -PackId "test" -PackVersion "1.0.0" -Sources $sources
            Start-Sleep -Milliseconds 10
            $lockfile2 = New-PackLockfile -PackId "test" -PackVersion "1.0.0" -Sources $sources
            
            # Structure should be identical except timestamps
            $lockfile1.packId | Should -Be $lockfile2.packId
            $lockfile1.packVersion | Should -Be $lockfile2.packVersion
            $lockfile1.sources.Count | Should -Be $lockfile2.sources.Count
        }

        It "Should include build metadata" {
            $metadata = @{ buildNumber = 42; builder = "ci-system" }
            $lockfile = New-PackLockfile -PackId "test" -PackVersion "1.0.0" -BuildMetadata $metadata
            
            $lockfile.buildMetadata.buildNumber | Should -Be 42
            $lockfile.buildMetadata.builder | Should -Be "ci-system"
        }
    }

    Context "Save-PackLockfile and Get-PackLockfile Functions" {
        It "Should save lockfiles to staging" {
            $lockfile = New-PackLockfile -PackId "test-save" -PackVersion "1.0.0"
            $stagingDir = Join-Path (Join-Path (Join-Path $script:TestRoot "packs") "staging") "test-save"
            
            $savedPath = Save-PackLockfile -Lockfile $lockfile -Staging $true
            
            Test-Path $savedPath | Should -Be $true
            $savedPath | Should -BeLike "*staging*"
        }

        It "Should create latest symlink" {
            $lockfile = New-PackLockfile -PackId "test-latest" -PackVersion "1.0.0"
            $stagingDir = Join-Path (Join-Path (Join-Path $script:TestRoot "packs") "staging") "test-latest"

            Push-Location $script:TestRoot
            try {
                Save-PackLockfile -Lockfile $lockfile -Staging $true | Out-Null

                $latestPath = Join-Path $stagingDir "latest.pack.lock.json"
                Test-Path $latestPath | Should -Be $true
            }
            finally {
                Pop-Location
            }
        }

        It "Should load latest lockfile" {
            $lockfile = New-PackLockfile -PackId "test-load" -PackVersion "2.0.0"
            
            Push-Location $script:TestRoot
            try {
                Save-PackLockfile -Lockfile $lockfile -Staging $true | Out-Null
                $loaded = Get-PackLockfile -PackId "test-load"
                $loaded.packVersion | Should -Be "2.0.0"
            }
            finally {
                Pop-Location
            }
        }
    }

    Context "Publish-PackBuild Function" {
        It "Should promote valid builds" {
            # Create a transaction in validated state
            $transaction = New-PackTransaction -PackId "test-promote" -PackVersion "1.0.0"
            $transaction = Move-PackTransactionStage -Transaction $transaction -Stage "build" -Success $true
            $transaction = Move-PackTransactionStage -Transaction $transaction -Stage "validate" -Success $true
            
            Push-Location $script:TestRoot
            try {
                # Create a lockfile in staging
                $lockfile = New-PackLockfile -PackId "test-promote" -PackVersion "1.0.0"
                Save-PackLockfile -Lockfile $lockfile -Staging $true | Out-Null

                $result = Publish-PackBuild -PackId "test-promote" -Version "1.0.0" -Transaction $transaction
                
                $result.Success | Should -Be $true
                $result.Transaction.state | Should -Be "promote"
                $result.Transaction.stages.validate.status | Should -Be "completed"
            }
            finally {
                Pop-Location
            }
        }

        It "Should reject promotion of unvalidated builds" {
            $transaction = New-PackTransaction -PackId "test-reject" -PackVersion "1.0.0"
            $transaction = Move-PackTransactionStage -Transaction $transaction -Stage "build" -Success $true
            # Not validated!
            
            $result = Publish-PackBuild -PackId "test-reject" -Version "1.0.0" -Transaction $transaction
            $result | Should -BeNullOrEmpty
        }
    }

    Context "Undo-PackBuild Function" {
        It "Should roll back failed builds" {
            $transaction = New-PackTransaction -PackId "test-rollback" -PackVersion "2.0.0"
            
            Push-Location $script:TestRoot
            try {
                $targetLockfile = New-PackLockfile -PackId "test-rollback" -PackVersion "1.0.0"
                Save-PackLockfile -Lockfile $targetLockfile -Staging $false | Out-Null

                $result = Undo-PackBuild -PackId "test-rollback" -Transaction $transaction -RollbackTarget "1.0.0"
                
                $result.state | Should -Be "rollback"
                $result.rollbackTarget | Should -Be "1.0.0"
            }
            finally {
                Pop-Location
            }
        }

        It "Should handle rollback without target" {
            $transaction = New-PackTransaction -PackId "test-rollback-no-target" -PackVersion "1.0.0"
            
            $result = Undo-PackBuild -PackId "test-rollback-no-target" -Transaction $transaction
            
            $result.state | Should -Be "rollback"
            $result.rollbackTarget | Should -BeNullOrEmpty
        }
    }
}
