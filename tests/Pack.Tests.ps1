#requires -Version 5.1
<#
.SYNOPSIS
    Pack Module Tests for LLM Workflow Platform

.DESCRIPTION
    Comprehensive Pester v5 test suite for pack modules:
    - PackManifest.ps1: Manifest creation/validation
    - SourceRegistry.ps1: Source registration
    - PackTransaction.ps1: Transaction lifecycle

.NOTES
    File: Pack.Tests.ps1
    Version: 1.0.0
    Author: LLM Workflow Team
    Requires: Pester 5.0+
#>

BeforeAll {
    # Set up test environment
    $script:TestRoot = Join-Path $env:TEMP "LLMWorkflow_PackTests_$([Guid]::NewGuid().ToString('N'))"
    $script:ModuleRoot = Join-Path (Join-Path $PSScriptRoot "..") "module\LLMWorkflow"
    $script:PackModulePath = Join-Path $script:ModuleRoot "pack"
    
    # Create test directories
    New-Item -ItemType Directory -Path $script:TestRoot -Force | Out-Null
    New-Item -ItemType Directory -Path (Join-Path $script:TestRoot "packs") -Force | Out-Null
    New-Item -ItemType Directory -Path (Join-Path (Join-Path $script:TestRoot "packs") "manifests") -Force | Out-Null
    New-Item -ItemType Directory -Path (Join-Path (Join-Path $script:TestRoot "packs") "registries") -Force | Out-Null
    New-Item -ItemType Directory -Path (Join-Path (Join-Path $script:TestRoot "packs") "staging") -Force | Out-Null
    New-Item -ItemType Directory -Path (Join-Path (Join-Path $script:TestRoot "packs") "promoted") -Force | Out-Null
    
    # Import pack modules by dot-sourcing
    $packManifestPath = Join-Path $script:PackModulePath "PackManifest.ps1"
    $sourceRegistryPath = Join-Path $script:PackModulePath "SourceRegistry.ps1"
    $packTransactionPath = Join-Path $script:PackModulePath "PackTransaction.ps1"
    
    if (Test-Path $packManifestPath) { try { . $packManifestPath } catch { if ($_.Exception.Message -notlike "*Export-ModuleMember*") { throw } } }
    if (Test-Path $sourceRegistryPath) { try { . $sourceRegistryPath } catch { if ($_.Exception.Message -notlike "*Export-ModuleMember*") { throw } } }
    if (Test-Path $packTransactionPath) { try { . $packTransactionPath } catch { if ($_.Exception.Message -notlike "*Export-ModuleMember*") { throw } } }
    
    # Change to test directory
    Push-Location $script:TestRoot
}

AfterAll {
    # Return to original location and cleanup
    Pop-Location -ErrorAction SilentlyContinue
    if (Test-Path $script:TestRoot) {
        Remove-Item -Path $script:TestRoot -Recurse -Force -ErrorAction SilentlyContinue
    }
}

Describe "PackManifest Module Tests" {
    
    Context "New-PackManifest Function - Happy Path" {
        It "Should create a valid pack manifest with required fields" {
            $manifest = New-PackManifest `
                -PackId "test-pack" `
                -Domain "test-domain" `
                -Version "1.0.0"
            
            $manifest | Should -Not -BeNullOrEmpty
            $manifest.schemaVersion | Should -Be 1
            $manifest.packId | Should -Be "test-pack"
            $manifest.domain | Should -Be "test-domain"
            $manifest.version | Should -Be "1.0.0"
            $manifest.status | Should -Be "draft"
            $manifest.channel | Should -Be "draft"
            $manifest.createdUtc | Should -Not -BeNullOrEmpty
            $manifest.updatedUtc | Should -Not -BeNullOrEmpty
        }

        It "Should create manifest with all lifecycle states" {
            $states = @('draft', 'building', 'staged', 'validated', 'promoted', 'deprecated', 'retired', 'removed')
            
            foreach ($state in $states) {
                $manifest = New-PackManifest `
                    -PackId "test-$state" `
                    -Domain "test" `
                    -Version "1.0.0" `
                    -Status $state
                
                $manifest.status | Should -Be $state
            }
        }

        It "Should create manifest with all channels" {
            $channels = @('draft', 'candidate', 'stable', 'frozen')
            
            foreach ($channel in $channels) {
                $manifest = New-PackManifest `
                    -PackId "test-$channel" `
                    -Domain "test" `
                    -Version "1.0.0" `
                    -Channel $channel
                
                $manifest.channel | Should -Be $channel
            }
        }

        It "Should create manifest with install profiles" {
            $profiles = @{
                minimal = @("source1", "source2")
                full = @("source1", "source2", "source3", "source4")
            }
            
            $manifest = New-PackManifest `
                -PackId "test-profiles" `
                -Domain "test" `
                -Version "1.0.0" `
                -InstallProfiles $profiles
            
            $manifest.installProfiles | Should -Not -BeNullOrEmpty
            $manifest.installProfiles.minimal.Count | Should -Be 2
            $manifest.installProfiles.full.Count | Should -Be 4
        }

        It "Should create manifest with owners" {
            $owners = @{
                primary = "test-owner"
                maintainers = @("user1", "user2")
            }
            
            $manifest = New-PackManifest `
                -PackId "test-owners" `
                -Domain "test" `
                -Version "1.0.0" `
                -Owners $owners
            
            $manifest.owners.primary | Should -Be "test-owner"
        }

        It "Should create manifest with custom taxonomy version" {
            $manifest = New-PackManifest `
                -PackId "test-taxonomy" `
                -Domain "test" `
                -Version "1.0.0" `
                -TaxonomyVersion "2"
            
            $manifest.taxonomyVersion | Should -Be "2"
        }

        It "Should create manifest with default collections" {
            $collections = @("core", "extensions", "examples")
            
            $manifest = New-PackManifest `
                -PackId "test-collections" `
                -Domain "test" `
                -Version "1.0.0" `
                -DefaultCollections $collections
            
            $manifest.defaultCollections | Should -Be $collections
        }
    }

    Context "New-PackManifest Function - Error Cases" {
        It "Should throw on invalid packId format" {
            { New-PackManifest -PackId "Invalid_Pack" -Domain "test" -Version "1.0.0" } | Should -Throw
            { New-PackManifest -PackId "Invalid Pack" -Domain "test" -Version "1.0.0" } | Should -Throw
            { New-PackManifest -PackId "InvalidPack!" -Domain "test" -Version "1.0.0" } | Should -Throw
        }

        It "Should throw on invalid version format" {
            { New-PackManifest -PackId "test" -Domain "test" -Version "1.0" } | Should -Throw
            { New-PackManifest -PackId "test" -Domain "test" -Version "v1.0.0" } | Should -Throw
            { New-PackManifest -PackId "test" -Domain "test" -Version "1.0.0.0" } | Should -Throw
        }

        It "Should throw on invalid status" {
            { New-PackManifest -PackId "test" -Domain "test" -Version "1.0.0" -Status "invalid" } | Should -Throw
        }

        It "Should throw on invalid channel" {
            { New-PackManifest -PackId "test" -Domain "test" -Version "1.0.0" -Channel "invalid" } | Should -Throw
        }
    }

    Context "Test-PackManifest Function" {
        It "Should validate a correct manifest" {
            $manifest = New-PackManifest -PackId "test-valid" -Domain "test" -Version "1.0.0"
            $result = Test-PackManifest -Manifest $manifest
            
            $result.isValid | Should -Be $true
            $result.errors.Count | Should -Be 0
        }

        It "Should detect missing required fields" {
            $manifest = @{
                packId = "test"
                # Missing domain and version
                status = "draft"
                channel = "draft"
            }
            
            $result = Test-PackManifest -Manifest $manifest
            
            $result.isValid | Should -Be $false
            $result.errors | Should -Contain "Missing required field: domain"
            $result.errors | Should -Contain "Missing required field: version"
        }

        It "Should detect invalid packId format" {
            $manifest = @{
                packId = "Invalid Pack"
                domain = "test"
                version = "1.0.0"
                status = "draft"
                channel = "draft"
            }
            
            $result = Test-PackManifest -Manifest $manifest
            
            $result.isValid | Should -Be $false
            $result.errors | Should -Contain "Invalid packId format: must be lowercase alphanumeric with hyphens only"
        }

        It "Should detect invalid version format" {
            $manifest = @{
                packId = "test"
                domain = "test"
                version = "invalid-version"
                status = "draft"
                channel = "draft"
            }
            
            $result = Test-PackManifest -Manifest $manifest
            
            $result.isValid | Should -Be $false
            $result.errors | Should -Contain "Invalid version format: must follow semantic versioning"
        }

        It "Should detect invalid status" {
            $manifest = @{
                packId = "test"
                domain = "test"
                version = "1.0.0"
                status = "invalid-status"
                channel = "draft"
            }
            
            $result = Test-PackManifest -Manifest $manifest
            
            $result.isValid | Should -Be $false
            $result.errors | Should -Match "Invalid status"
        }

        It "Should detect invalid install profile names" {
            $manifest = @{
                packId = "test"
                domain = "test"
                version = "1.0.0"
                status = "draft"
                channel = "draft"
                installProfiles = @{
                    invalid = @("source1")
                }
            }
            
            $result = Test-PackManifest -Manifest $manifest
            
            $result.isValid | Should -Be $false
            $result.errors | Should -Contain "Invalid install profile name: invalid"
        }
    }

    Context "Save-PackManifest and Get-PackManifest Functions" {
        It "Should save and load manifest correctly" {
            $manifest = New-PackManifest -PackId "test-save" -Domain "test" -Version "1.0.0"
            $path = Join-Path (Join-Path (Join-Path $script:TestRoot "packs") "manifests") "test-save.json"
            
            $savedPath = Save-PackManifest -Manifest $manifest -Path $path
            $loaded = Get-PackManifest -Path $path
            
            $savedPath | Should -Be $path
            $loaded | Should -Not -BeNullOrEmpty
            $loaded.packId | Should -Be "test-save"
            $loaded.domain | Should -Be "test"
        }

        It "Should save to default path when not specified" {
            $manifest = New-PackManifest -PackId "test-default" -Domain "test" -Version "1.0.0"
            
            $savedPath = Save-PackManifest -Manifest $manifest
            
            Test-Path $savedPath | Should -Be $true
        }

        It "Should return null for non-existent manifest" {
            $loaded = Get-PackManifest -PackId "nonexistent-pack"
            $loaded | Should -BeNullOrEmpty
        }

        It "Should load by PackId" {
            $manifest = New-PackManifest -PackId "test-by-id" -Domain "test" -Version "1.0.0"
            Save-PackManifest -Manifest $manifest | Out-Null
            
            $loaded = Get-PackManifest -PackId "test-by-id"
            
            $loaded.packId | Should -Be "test-by-id"
        }
    }

    Context "Get-PackManifestList Function" {
        BeforeEach {
            # Create test manifests
            $manifest1 = New-PackManifest -PackId "list-test-1" -Domain "domain-a" -Version "1.0.0" -Status "draft"
            $manifest2 = New-PackManifest -PackId "list-test-2" -Domain "domain-b" -Version "2.0.0" -Status "promoted"
            Save-PackManifest -Manifest $manifest1 | Out-Null
            Save-PackManifest -Manifest $manifest2 | Out-Null
        }

        It "Should list all manifests" {
            $manifests = Get-PackManifestList
            
            $manifests.Count | Should -BeGreaterOrEqual 2
        }

        It "Should filter by status" {
            $manifests = Get-PackManifestList -Status "promoted"
            
            $manifests | ForEach-Object { $_.Status | Should -Be "promoted" }
        }

        It "Should filter by domain" {
            $manifests = Get-PackManifestList -Domain "domain-a"
            
            $manifests | ForEach-Object { $_.Domain | Should -Be "domain-a" }
        }
    }

    Context "Set-PackLifecycleState Function" {
        It "Should transition state correctly" {
            $manifest = New-PackManifest -PackId "lifecycle-test" -Domain "test" -Version "1.0.0" -Status "draft"
            
            $updated = Set-PackLifecycleState -Manifest $manifest -NewStatus "building" -Reason "Starting build"
            
            $updated.status | Should -Be "building"
            $updated.lifecycleHistory | Should -Not -BeNullOrEmpty
            $updated.lifecycleHistory[0].fromStatus | Should -Be "draft"
            $updated.lifecycleHistory[0].toStatus | Should -Be "building"
            $updated.lifecycleHistory[0].reason | Should -Be "Starting build"
        }

        It "Should block invalid transitions" {
            $manifest = New-PackManifest -PackId "transition-test" -Domain "test" -Version "1.0.0" -Status "draft"
            
            $result = Set-PackLifecycleState -Manifest $manifest -NewStatus "promoted"
            
            $result | Should -BeNullOrEmpty
        }

        It "Should only allow promoting validated builds" {
            $manifest = New-PackManifest -PackId "promote-test" -Domain "test" -Version "1.0.0" -Status "staged"
            
            $result = Set-PackLifecycleState -Manifest $manifest -NewStatus "promoted"
            
            $result | Should -BeNullOrEmpty
            
            $manifest.status = "validated"
            $result = Set-PackLifecycleState -Manifest $manifest -NewStatus "promoted"
            
            $result.status | Should -Be "promoted"
        }
    }

    Context "Get-PackInstallProfile Function" {
        It "Should return profile members" {
            $manifest = New-PackManifest -PackId "profile-test" -Domain "test" -Version "1.0.0" -InstallProfiles @{
                minimal = @("source1")
                full = @("source1", "source2", "source3")
            }
            
            $members = Get-PackInstallProfile -Manifest $manifest -ProfileName "minimal"
            $members.Count | Should -Be 1
            $members[0] | Should -Be "source1"
            
            $members = Get-PackInstallProfile -Manifest $manifest -ProfileName "full"
            $members.Count | Should -Be 3
        }

        It "Should warn and return empty for missing profile" {
            $manifest = New-PackManifest -PackId "profile-missing" -Domain "test" -Version "1.0.0"
            
            $members = Get-PackInstallProfile -Manifest $manifest -ProfileName "minimal"
            
            $members.Count | Should -Be 0
        }
    }

    Context "Export-PackSummary Function" {
        It "Should create summary from manifest" {
            $manifest = New-PackManifest -PackId "summary-test" -Domain "test-domain" -Version "1.2.3" -Status "promoted" -DefaultCollections @("core", "examples")
            
            $summary = Export-PackSummary -Manifest $manifest
            
            $summary.PackId | Should -Be "summary-test"
            $summary.Domain | Should -Be "test-domain"
            $summary.Version | Should -Be "1.2.3"
            $summary.Status | Should -Be "promoted"
            $summary.Collections | Should -Match "core"
        }
    }
}

Describe "SourceRegistry Module Tests" {
    
    Context "New-SourceRegistryEntry Function - Happy Path" {
        It "Should create a valid source entry" {
            $entry = New-SourceRegistryEntry `
                -SourceId "test-source" `
                -RepoUrl "https://github.com/test/repo"
            
            $entry | Should -Not -BeNullOrEmpty
            $entry.schemaVersion | Should -Be 1
            $entry.sourceId | Should -Be "test-source"
            $entry.repoUrl | Should -Be "https://github.com/test/repo"
            $entry.selectedRef | Should -Be "main"
            $entry.parseMode | Should -Be "default"
            $entry.trustTier | Should -Be "Medium"
            $entry.authorityRole | Should -Be "exemplar-pattern"
            $entry.priority | Should -Be "P2"
            $entry.state | Should -Be "active"
        }

        It "Should create entry with all trust tiers" {
            $tiers = @('High', 'Medium-High', 'Medium', 'Low', 'Quarantined')
            
            foreach ($tier in $tiers) {
                $entry = New-SourceRegistryEntry `
                    -SourceId "test-$tier" `
                    -RepoUrl "https://github.com/test/repo" `
                    -TrustTier $tier
                
                $entry.trustTier | Should -Be $tier
            }
        }

        It "Should create entry with all priorities" {
            $priorities = @('P0', 'P1', 'P2', 'P3', 'P4', 'P5')
            
            foreach ($priority in $priorities) {
                $entry = New-SourceRegistryEntry `
                    -SourceId "test-$priority" `
                    -RepoUrl "https://github.com/test/repo" `
                    -Priority $priority
                
                $entry.priority | Should -Be $priority
            }
        }

        It "Should create entry with engine metadata" {
            $entry = New-SourceRegistryEntry `
                -SourceId "engine-test" `
                -RepoUrl "https://github.com/test/repo" `
                -EngineTarget "Godot 4.0" `
                -EngineMinVersion "4.0.0" `
                -EngineMaxVersion "4.1.0"
            
            $entry.engineTarget | Should -Be "Godot 4.0"
            $entry.engineMinVersion | Should -Be "4.0.0"
            $entry.engineMaxVersion | Should -Be "4.1.0"
        }

        It "Should create entry with collections" {
            $entry = New-SourceRegistryEntry `
                -SourceId "collection-test" `
                -RepoUrl "https://github.com/test/repo" `
                -Collections @("core", "extensions")
            
            $entry.collections | Should -Contain "core"
            $entry.collections | Should -Contain "extensions"
        }

        It "Should create entry with risk notes" {
            $riskNotes = @{
                knownIssues = @("issue1", "issue2")
                reviewStatus = "pending"
            }
            
            $entry = New-SourceRegistryEntry `
                -SourceId "risk-test" `
                -RepoUrl "https://github.com/test/repo" `
                -RiskNotes $riskNotes
            
            $entry.riskNotes.knownIssues.Count | Should -Be 2
        }
    }

    Context "New-SourceRegistryEntry Function - Error Cases" {
        It "Should throw on invalid URL format" {
            { New-SourceRegistryEntry -SourceId "test" -RepoUrl "invalid-url" } | Should -Throw
            { New-SourceRegistryEntry -SourceId "test" -RepoUrl "ftp://server.com/file" } | Should -Throw
        }
    }

    Context "New-SourceFamilyEntry Function" {
        It "Should create a valid family entry" {
            $family = New-SourceFamilyEntry `
                -FamilyId "test-family" `
                -CanonicalSource "original-source"
            
            $family.familyId | Should -Be "test-family"
            $family.canonicalSource | Should -Be "original-source"
            $family.familyType | Should -Be "fork"
            $family.members | Should -Not -BeNullOrEmpty
        }

        It "Should support all family types" {
            $types = @('fork', 'mirror', 'rename', 'author-family', 'duplicate', 'wrapper')
            
            foreach ($type in $types) {
                $family = New-SourceFamilyEntry `
                    -FamilyId "test-$type" `
                    -CanonicalSource "original" `
                    -FamilyType $type
                
                $family.familyType | Should -Be $type
            }
        }
    }

    Context "Test-SourceRegistryEntry Function" {
        It "Should validate a correct entry" {
            $entry = New-SourceRegistryEntry -SourceId "valid" -RepoUrl "https://github.com/test/repo"
            $result = Test-SourceRegistryEntry -Entry $entry
            
            $result.isValid | Should -Be $true
            $result.errors.Count | Should -Be 0
        }

        It "Should detect missing required fields" {
            $entry = @{ repoUrl = "https://github.com/test/repo" }  # Missing sourceId
            $result = Test-SourceRegistryEntry -Entry $entry
            
            $result.isValid | Should -Be $false
            $result.errors | Should -Contain "Missing required field: sourceId"
        }

        It "Should detect invalid trust tier" {
            $entry = @{
                sourceId = "test"
                repoUrl = "https://github.com/test/repo"
                trustTier = "Invalid"
            }
            $result = Test-SourceRegistryEntry -Entry $entry
            
            $result.isValid | Should -Be $false
            $result.errors | Should -Match "Invalid trustTier"
        }

        It "Should detect invalid state" {
            $entry = @{
                sourceId = "test"
                repoUrl = "https://github.com/test/repo"
                state = "invalid-state"
            }
            $result = Test-SourceRegistryEntry -Entry $entry
            
            $result.isValid | Should -Be $false
            $result.errors | Should -Match "Invalid state"
        }
    }

    Context "Save-SourceRegistry and Get-SourceRegistry Functions" {
        It "Should save and load registry correctly" {
            $sources = @{
                source1 = New-SourceRegistryEntry -SourceId "source1" -RepoUrl "https://github.com/test/1"
                source2 = New-SourceRegistryEntry -SourceId "source2" -RepoUrl "https://github.com/test/2"
            }
            
            $path = Save-SourceRegistry -PackId "test-pack" -Sources $sources
            $loaded = Get-SourceRegistry -PackId "test-pack"
            
            $loaded | Should -Not -BeNullOrEmpty
            $loaded.packId | Should -Be "test-pack"
            $loaded.sources.Count | Should -Be 2
        }

        It "Should return empty registry for non-existent pack" {
            $registry = Get-SourceRegistry -PackId "nonexistent-pack"
            
            $registry | Should -Not -BeNullOrEmpty
            $registry.sources.Count | Should -Be 0
        }
    }

    Context "Set-SourceState Function" {
        It "Should transition source state correctly" {
            $entry = New-SourceRegistryEntry -SourceId "state-test" -RepoUrl "https://github.com/test/repo"
            
            $updated = Set-SourceState -Entry $entry -NewState "deprecated" -Reason "Outdated"
            
            $updated.state | Should -Be "deprecated"
            $updated.stateHistory | Should -Not -BeNullOrEmpty
            $updated.stateHistory[0].fromState | Should -Be "active"
            $updated.stateHistory[0].toState | Should -Be "deprecated"
        }

        It "Should support all valid states" {
            $states = @('active', 'deprecated', 'retired', 'quarantined', 'removed')
            
            foreach ($state in $states) {
                $entry = New-SourceRegistryEntry -SourceId "test-$state" -RepoUrl "https://github.com/test/repo"
                $updated = Set-SourceState -Entry $entry -NewState $state
                
                $updated.state | Should -Be $state
            }
        }
    }

    Context "Suspend-SourceQuarantine Function" {
        It "Should quarantine a source" {
            $entry = New-SourceRegistryEntry -SourceId "quarantine-test" -RepoUrl "https://github.com/test/repo"
            
            $quarantined = Suspend-SourceQuarantine -Entry $entry -Reason "Security review required" -ReviewDate "2026-12-31"
            
            $quarantined.state | Should -Be "quarantined"
            $quarantined.quarantineReason | Should -Be "Security review required"
            $quarantined.quarantineDate | Should -Not -BeNullOrEmpty
            $quarantined.quarantineReviewDate | Should -Be "2026-12-31"
        }
    }

    Context "Get-SourceByPriority Function" {
        It "Should filter by priority tiers" {
            $sources = @{
                p0 = New-SourceRegistryEntry -SourceId "p0" -RepoUrl "https://github.com/test/1" -Priority "P0"
                p1 = New-SourceRegistryEntry -SourceId "p1" -RepoUrl "https://github.com/test/2" -Priority "P1"
                p2 = New-SourceRegistryEntry -SourceId "p2" -RepoUrl "https://github.com/test/3" -Priority "P2"
            }
            $registry = @{ sources = $sources }
            
            $result = Get-SourceByPriority -Registry $registry -Priority @("P0", "P1")
            
            $result.Count | Should -Be 2
        }

        It "Should only return active sources" {
            $sources = @{
                active = New-SourceRegistryEntry -SourceId "active" -RepoUrl "https://github.com/test/1"
                retired = New-SourceRegistryEntry -SourceId "retired" -RepoUrl "https://github.com/test/2"
            }
            $sources.retired.state = "retired"
            $registry = @{ sources = $sources }
            
            $result = Get-SourceByPriority -Registry $registry -Priority @("P2")
            
            $result.Count | Should -Be 1
            $result[0].sourceId | Should -Be "active"
        }
    }

    Context "Get-SourceByAuthorityRole Function" {
        It "Should filter by authority role" {
            $sources = @{
                role1 = New-SourceRegistryEntry -SourceId "role1" -RepoUrl "https://github.com/test/1" -AuthorityRole "core-runtime"
                role2 = New-SourceRegistryEntry -SourceId "role2" -RepoUrl "https://github.com/test/2" -AuthorityRole "exemplar-pattern"
            }
            $registry = @{ sources = $sources }
            
            $result = Get-SourceByAuthorityRole -Registry $registry -AuthorityRole "core-runtime"
            
            $result.Count | Should -Be 1
            $result[0].sourceId | Should -Be "role1"
        }
    }

    Context "Get-RetrievalPrioritySources Function" {
        It "Should sort by priority then trust tier" {
            $sources = @{
                p1high = New-SourceRegistryEntry -SourceId "p1high" -RepoUrl "https://github.com/test/1" -Priority "P1" -TrustTier "High"
                p0medium = New-SourceRegistryEntry -SourceId "p0medium" -RepoUrl "https://github.com/test/2" -Priority "P0" -TrustTier "Medium"
                p0high = New-SourceRegistryEntry -SourceId "p0high" -RepoUrl "https://github.com/test/3" -Priority "P0" -TrustTier "High"
            }
            $registry = @{ sources = $sources }
            
            $result = Get-RetrievalPrioritySources -Registry $registry
            
            $result[0].sourceId | Should -Be "p0high"  # P0 + High
            $result[1].sourceId | Should -Be "p0medium"  # P0 + Medium
            $result[2].sourceId | Should -Be "p1high"  # P1 + High
        }

        It "Should filter by collection" {
            $sources = @{
                incollection = New-SourceRegistryEntry -SourceId "incollection" -RepoUrl "https://github.com/test/1" -Collections @("core")
                notincollection = New-SourceRegistryEntry -SourceId "notincollection" -RepoUrl "https://github.com/test/2" -Collections @("other")
            }
            $registry = @{ sources = $sources }
            
            $result = Get-RetrievalPrioritySources -Registry $registry -Collection "core"
            
            $result.Count | Should -Be 1
            $result[0].sourceId | Should -Be "incollection"
        }
    }

    Context "Export-SourceRegistrySummary Function" {
        It "Should create summary statistics" {
            $sources = @{
                s1 = New-SourceRegistryEntry -SourceId "s1" -RepoUrl "https://github.com/test/1" -Priority "P0" -TrustTier "High" -State "active"
                s2 = New-SourceRegistryEntry -SourceId "s2" -RepoUrl "https://github.com/test/2" -Priority "P1" -TrustTier "Medium" -State "active"
                s3 = New-SourceRegistryEntry -SourceId "s3" -RepoUrl "https://github.com/test/3" -Priority "P2" -TrustTier "Low" -State "retired"
            }
            $registry = @{ packId = "test-pack"; sources = $sources }
            
            $summary = Export-SourceRegistrySummary -Registry $registry
            
            $summary.PackId | Should -Be "test-pack"
            $summary.TotalSources | Should -Be 3
            $summary.ActiveSources | Should -Be 2
            $summary.ByPriority.P0 | Should -Be 1
            $summary.ByTrustTier.High | Should -Be 1
        }
    }
}

Describe "PackTransaction Module Tests" {
    
    Context "New-PackTransaction Function - Happy Path" {
        It "Should create a valid transaction" {
            $transaction = New-PackTransaction `
                -PackId "test-pack" `
                -PackVersion "1.0.0"
            
            $transaction | Should -Not -BeNullOrEmpty
            $transaction.schemaVersion | Should -Be 1
            $transaction.transactionId | Should -Not -BeNullOrEmpty
            $transaction.packId | Should -Be "test-pack"
            $transaction.packVersion | Should -Be "1.0.0"
            $transaction.state | Should -Be "prepare"
            $transaction.stages.prepare.status | Should -Be "in-progress"
        }

        It "Should create transaction with parent reference" {
            $parentTransaction = New-PackTransaction -PackId "test-pack" -PackVersion "0.9.0"
            
            $transaction = New-PackTransaction `
                -PackId "test-pack" `
                -PackVersion "1.0.0" `
                -ParentTransactionId $parentTransaction.transactionId
            
            $transaction.parentTransactionId | Should -Be $parentTransaction.transactionId
        }
    }

    Context "Move-PackTransactionStage Function" {
        It "Should advance through stages successfully" {
            $transaction = New-PackTransaction -PackId "test-pack" -PackVersion "1.0.0"
            
            # prepare -> build
            $transaction = Move-PackTransactionStage -Transaction $transaction -Stage "build" -Success $true
            $transaction.state | Should -Be "build"
            $transaction.stages.prepare.status | Should -Be "completed"
            $transaction.stages.build.status | Should -Be "in-progress"
            
            # build -> validate
            $transaction = Move-PackTransactionStage -Transaction $transaction -Stage "validate" -Success $true
            $transaction.state | Should -Be "validate"
            $transaction.stages.build.status | Should -Be "completed"
            
            # validate -> promote
            $transaction = Move-PackTransactionStage -Transaction $transaction -Stage "promote" -Success $true
            $transaction.state | Should -Be "promote"
            $transaction.stages.validate.status | Should -Be "completed"
        }

        It "Should transition to rollback on failure" {
            $transaction = New-PackTransaction -PackId "test-pack" -PackVersion "1.0.0"
            
            # Move to build, then fail
            $transaction = Move-PackTransactionStage -Transaction $transaction -Stage "build" -Success $true
            $transaction = Move-PackTransactionStage -Transaction $transaction -Stage "validate" -Success $false -Errors @("Validation failed")
            
            $transaction.state | Should -Be "rollback"
            $transaction.stages.validate.status | Should -Be "failed"
            $transaction.stages.validate.errors | Should -Contain "Validation failed"
        }

        It "Should support all stage transitions" {
            $stages = @('prepare', 'build', 'validate', 'promote', 'rollback')
            
            foreach ($stage in $stages) {
                $transaction = New-PackTransaction -PackId "test-$stage" -PackVersion "1.0.0"
                $transaction = Move-PackTransactionStage -Transaction $transaction -Stage $stage -Success $true
                
                $transaction.state | Should -Be $stage
            }
        }
    }

    Context "New-PackLockfile Function - Happy Path" {
        It "Should create a valid lockfile" {
            $lockfile = New-PackLockfile `
                -PackId "test-pack" `
                -PackVersion "1.0.0"
            
            $lockfile | Should -Not -BeNullOrEmpty
            $lockfile.schemaVersion | Should -Be 1
            $lockfile.packId | Should -Be "test-pack"
            $lockfile.packVersion | Should -Be "1.0.0"
            $lockfile.toolkitVersion | Should -Be "0.4.0"
            $lockfile.builtUtc | Should -Not -BeNullOrEmpty
        }

        It "Should create lockfile with custom versions" {
            $lockfile = New-PackLockfile `
                -PackId "test-pack" `
                -PackVersion "1.0.0" `
                -ToolkitVersion "1.0.0" `
                -TaxonomyVersion "2"
            
            $lockfile.toolkitVersion | Should -Be "1.0.0"
            $lockfile.taxonomyVersion | Should -Be "2"
        }

        It "Should create lockfile with sources" {
            $sources = @(
                @{
                    sourceId = "source1"
                    repoUrl = "https://github.com/test/1"
                    selectedRef = "main"
                    resolvedCommit = "abc123"
                    parseMode = "default"
                    parserVersion = "1.0.0"
                    chunkCount = 42
                }
            )
            
            $lockfile = New-PackLockfile `
                -PackId "test-pack" `
                -PackVersion "1.0.0" `
                -Sources $sources
            
            $lockfile.sources.Count | Should -Be 1
            $lockfile.sources[0].sourceId | Should -Be "source1"
            $lockfile.sources[0].chunkCount | Should -Be 42
        }

        It "Should include build metadata" {
            $metadata = @{
                buildMachine = "build-server-01"
                gitCommit = "abc123def456"
            }
            
            $lockfile = New-PackLockfile `
                -PackId "test-pack" `
                -PackVersion "1.0.0" `
                -BuildMetadata $metadata
            
            $lockfile.buildMetadata.buildMachine | Should -Be "build-server-01"
        }
    }

    Context "Save-PackLockfile and Get-PackLockfile Functions" {
        It "Should save lockfile to staging by default" {
            $lockfile = New-PackLockfile -PackId "save-test" -PackVersion "1.0.0"
            
            $path = Save-PackLockfile -Lockfile $lockfile -Staging $true
            
            Test-Path $path | Should -Be $true
            $path | Should -Match "packs[\\/]+staging"
        }

        It "Should save lockfile to promoted when specified" {
            $lockfile = New-PackLockfile -PackId "save-promoted" -PackVersion "1.0.0"
            
            $path = Save-PackLockfile -Lockfile $lockfile -Staging $false
            
            $path | Should -Match "packs[\\/]+promoted"
        }

        It "Should save latest lockfile" {
            $lockfile = New-PackLockfile -PackId "latest-test" -PackVersion "1.0.0"
            Save-PackLockfile -Lockfile $lockfile -Staging $true | Out-Null
            
            $latestPath = Join-Path (Join-Path (Join-Path (Join-Path $script:TestRoot "packs") "staging") "latest-test") "latest.pack.lock.json"
            Test-Path $latestPath | Should -Be $true
        }

        It "Should load latest lockfile" {
            $lockfile = New-PackLockfile -PackId "load-test" -PackVersion "2.0.0"
            Save-PackLockfile -Lockfile $lockfile -Staging $true | Out-Null
            
            $loaded = Get-PackLockfile -PackId "load-test"
            
            $loaded | Should -Not -BeNullOrEmpty
            $loaded.packId | Should -Be "load-test"
            $loaded.packVersion | Should -Be "2.0.0"
        }

        It "Should return null for non-existent lockfile" {
            $loaded = Get-PackLockfile -PackId "nonexistent-pack"
            $loaded | Should -BeNullOrEmpty
        }
    }

    Context "New-PackBuildManifest Function" {
        It "Should create a valid build manifest" {
            $lockfile = New-PackLockfile -PackId "build-test" -PackVersion "1.0.0"
            
            $manifest = New-PackBuildManifest `
                -PackId "build-test" `
                -PackVersion "1.0.0" `
                -Lockfile $lockfile
            
            $manifest | Should -Not -BeNullOrEmpty
            $manifest.schemaVersion | Should -Be 1
            $manifest.packId | Should -Be "build-test"
            $manifest.packVersion | Should -Be "1.0.0"
            $manifest.lockfilePath | Should -Not -BeNullOrEmpty
        }

        It "Should include artifact counts" {
            $counts = @{
                chunks = 100
                embeddings = 1000
                metadata = 50
            }
            
            $manifest = New-PackBuildManifest `
                -PackId "counts-test" `
                -PackVersion "1.0.0" `
                -ArtifactCounts $counts
            
            $manifest.artifactCounts.chunks | Should -Be 100
        }

        It "Should include evaluation results" {
            $evalResults = @{
                passed = $true
                testCount = 50
                passCount = 48
                failCount = 2
            }
            
            $manifest = New-PackBuildManifest `
                -PackId "eval-test" `
                -PackVersion "1.0.0" `
                -EvalResults $evalResults
            
            $manifest.evalResults.passed | Should -Be $true
            $manifest.statusSummary.overallStatus | Should -Be "passed"
            $manifest.statusSummary.testCount | Should -Be 50
        }
    }

    Context "Publish-PackBuild Function" {
        It "Should promote validated build" {
            # Create transaction in validate state
            $transaction = New-PackTransaction -PackId "promote-test" -PackVersion "1.0.0"
            $transaction = Move-PackTransactionStage -Transaction $transaction -Stage "build" -Success $true
            $transaction = Move-PackTransactionStage -Transaction $transaction -Stage "validate" -Success $true
            
            # Create and save lockfile in staging
            $lockfile = New-PackLockfile -PackId "promote-test" -PackVersion "1.0.0"
            Save-PackLockfile -Lockfile $lockfile -Staging $true | Out-Null
            
            $result = Publish-PackBuild -PackId "promote-test" -Version "1.0.0" -Transaction $transaction
            
            $result.Success | Should -Be $true
            $result.PromotedPath | Should -Not -BeNullOrEmpty
            $result.Transaction.state | Should -Be "promote"
        }

        It "Should fail if transaction not validated" {
            $transaction = New-PackTransaction -PackId "fail-test" -PackVersion "1.0.0"
            
            $result = Publish-PackBuild -PackId "fail-test" -Version "1.0.0" -Transaction $transaction
            
            $result | Should -BeNullOrEmpty
        }
    }

    Context "Undo-PackBuild Function" {
        It "Should rollback to target version" {
            $transaction = New-PackTransaction -PackId "rollback-test" -PackVersion "1.0.0"
            
            # Create a target lockfile in promoted
            $targetLockfile = New-PackLockfile -PackId "rollback-test" -PackVersion "0.9.0"
            Save-PackLockfile -Lockfile $targetLockfile -Staging $false | Out-Null
            
            $result = Undo-PackBuild -PackId "rollback-test" -Transaction $transaction -RollbackTarget "0.9.0"
            
            $result.state | Should -Be "rollback"
            $result.rollbackTarget | Should -Be "0.9.0"
        }

        It "Should set rollback state without target" {
            $transaction = New-PackTransaction -PackId "rollback-notarget" -PackVersion "1.0.0"
            
            $result = Undo-PackBuild -PackId "rollback-notarget" -Transaction $transaction
            
            $result.state | Should -Be "rollback"
        }
    }

    Context "Get-PackBuildStatus Function" {
        It "Should return build status summary" {
            # Create staging and promoted lockfiles
            $stagingLockfile = New-PackLockfile -PackId "status-test" -PackVersion "1.1.0"
            $promotedLockfile = New-PackLockfile -PackId "status-test" -PackVersion "1.0.0"
            
            Save-PackLockfile -Lockfile $stagingLockfile -Staging $true | Out-Null
            Save-PackLockfile -Lockfile $promotedLockfile -Staging $false | Out-Null
            
            $status = Get-PackBuildStatus -PackId "status-test"
            
            $status.PackId | Should -Be "status-test"
            $status.StagingBuilds | Should -BeGreaterOrEqual 1
            $status.PromotedBuilds | Should -BeGreaterOrEqual 1
            $status.LatestStaging | Should -Not -BeNullOrEmpty
            $status.LatestPromoted | Should -Not -BeNullOrEmpty
        }
    }

    Context "Transaction Lifecycle Integration" {
        It "Should complete full successful lifecycle" {
            # Start transaction
            $transaction = New-PackTransaction -PackId "lifecycle-test" -PackVersion "1.0.0"
            $transaction.state | Should -Be "prepare"
            
            # Move through stages
            $transaction = Move-PackTransactionStage -Transaction $transaction -Stage "build" -Success $true
            $transaction.state | Should -Be "build"
            
            $transaction = Move-PackTransactionStage -Transaction $transaction -Stage "validate" -Success $true
            $transaction.state | Should -Be "validate"
            
            # Create and save lockfile
            $lockfile = New-PackLockfile -PackId "lifecycle-test" -PackVersion "1.0.0"
            Save-PackLockfile -Lockfile $lockfile -Staging $true | Out-Null
            
            # Promote
            $result = Publish-PackBuild -PackId "lifecycle-test" -Version "1.0.0" -Transaction $transaction
            $result.Success | Should -Be $true
        }

        It "Should handle failure and rollback" {
            # Start transaction
            $transaction = New-PackTransaction -PackId "failure-test" -PackVersion "1.0.0"
            
            # Fail at build stage
            $transaction = Move-PackTransactionStage -Transaction $transaction -Stage "build" -Success $false -Errors @("Build failed")
            
            $transaction.state | Should -Be "rollback"
            $transaction.stages.build.status | Should -Be "failed"
            $transaction.stages.build.errors | Should -Contain "Build failed"
        }
    }
}
