#requires -Version 5.1
<#
.SYNOPSIS
    Pester tests for the HumanAnnotations module.

.DESCRIPTION
    Tests for the Human Annotations and Overrides system.
#>

param(
    [string]$ProjectRoot = (Split-Path -Parent $PSScriptRoot)
)

try { . "$ProjectRoot\module\LLMWorkflow\governance\HumanAnnotations.ps1" } catch { if ($_.Exception.Message -notlike '*Export-ModuleMember*') { throw } }

# Ensure test directory exists
$testDir = Join-Path $ProjectRoot ".llm-workflow\state"
if (-not (Test-Path -LiteralPath $testDir)) {
    New-Item -ItemType Directory -Path $testDir -Force | Out-Null
}

Describe "HumanAnnotations Module Tests" {
    
    BeforeAll {
        $script:testProjectRoot = $ProjectRoot
        $script:testAnnotationId = $null
        $script:testOverrideId = $null
    }

    Context "Get-AnnotationRegistry" {
        It "Should return registry metadata" {
            $reg = Get-AnnotationRegistry -ProjectRoot $script:testProjectRoot
            $reg | Should -Not -Be $null
            $reg.SchemaVersion | Should -Be 1
            $reg.ValidTypes.AnnotationTypes.Count | Should -Be 7
            $reg.ValidTypes.EntityTypes.Count | Should -Be 4
        }

        It "Should include all valid annotation types" {
            $reg = Get-AnnotationRegistry -ProjectRoot $script:testProjectRoot
            $reg.ValidTypes.AnnotationTypes | Should -Contain 'correction'
            $reg.ValidTypes.AnnotationTypes | Should -Contain 'deprecation'
            $reg.ValidTypes.AnnotationTypes | Should -Contain 'confidence'
            $reg.ValidTypes.AnnotationTypes | Should -Contain 'compatibility'
            $reg.ValidTypes.AnnotationTypes | Should -Contain 'relevance'
            $reg.ValidTypes.AnnotationTypes | Should -Contain 'caveat'
            $reg.ValidTypes.AnnotationTypes | Should -Contain 'override'
        }
    }

    Context "New-HumanAnnotation" {
        It "Should create a new annotation with required parameters" {
            $ann = New-HumanAnnotation `
                -EntityId 'test-source-001' `
                -EntityType 'source' `
                -AnnotationType 'correction' `
                -Content 'Test correction content' `
                -Author 'testuser' `
                -ProjectRoot $script:testProjectRoot

            $ann | Should -Not -Be $null
            $ann.annotationId | Should -Not -BeNullOrEmpty
            $ann.entityId | Should -Be 'test-source-001'
            $ann.entityType | Should -Be 'source'
            $ann.annotationType | Should -Be 'correction'
            $ann.content | Should -Be 'Test correction content'
            $ann.author | Should -Be 'testuser'
            $ann.status | Should -Be 'active'
            $ann.votes.up | Should -Be 0
            $ann.votes.down | Should -Be 0

            $script:testAnnotationId = $ann.annotationId
        }

        It "Should create annotation with context" {
            $ann = New-HumanAnnotation `
                -EntityId 'test-source-002' `
                -EntityType 'pack' `
                -AnnotationType 'caveat' `
                -Content 'Caveat content' `
                -Author 'testuser2' `
                -Context @{ 
                    projectId = 'test-project'
                    workspaceId = 'workspace-1'
                    scope = 'project'
                    metadata = @{ priority = 'high' }
                } `
                -ProjectRoot $script:testProjectRoot

            $ann.projectId | Should -Be 'test-project'
            $ann.workspaceId | Should -Be 'workspace-1'
            $ann.scope | Should -Be 'project'
            $ann.metadata.priority | Should -Be 'high'
        }

        It "Should reject invalid entity type" {
            { New-HumanAnnotation `
                -EntityId 'test' `
                -EntityType 'invalid' `
                -AnnotationType 'correction' `
                -Content 'Test' `
                -Author 'test' `
                -ProjectRoot $script:testProjectRoot
            } | Should -Throw
        }

        It "Should reject empty entity ID" {
            { New-HumanAnnotation `
                -EntityId '' `
                -EntityType 'source' `
                -AnnotationType 'correction' `
                -Content 'Test' `
                -Author 'test' `
                -ProjectRoot $script:testProjectRoot
            } | Should -Throw
        }
    }

    Context "Get-EntityAnnotations" {
        It "Should retrieve annotations for an entity" {
            $annotations = Get-EntityAnnotations `
                -EntityId 'test-source-001' `
                -ProjectRoot $script:testProjectRoot

            $annotations.Count | Should -BeGreaterThan 0
            $annotations[0].entityId | Should -Be 'test-source-001'
        }

        It "Should filter by entity type" {
            $annotations = Get-EntityAnnotations `
                -EntityId 'test-source-001' `
                -EntityType 'source' `
                -ProjectRoot $script:testProjectRoot

            $annotations | ForEach-Object {
                $_.entityType | Should -Be 'source'
            }
        }

        It "Should exclude inactive annotations by default" {
            # Update annotation to superseded
            Update-Annotation `
                -AnnotationId $script:testAnnotationId `
                -Status 'superseded' `
                -ProjectRoot $script:testProjectRoot

            $annotations = Get-EntityAnnotations `
                -EntityId 'test-source-001' `
                -ProjectRoot $script:testProjectRoot

            $annotations | Where-Object { $_.annotationId -eq $script:testAnnotationId } | Should -BeNullOrEmpty
        }

        It "Should include inactive when requested" {
            $annotations = Get-EntityAnnotations `
                -EntityId 'test-source-001' `
                -IncludeInactive `
                -ProjectRoot $script:testProjectRoot

            $annotations | Where-Object { $_.annotationId -eq $script:testAnnotationId } | Should -Not -BeNullOrEmpty
        }
    }

    Context "Vote-Annotation" {
        BeforeAll {
            # Create fresh annotation for voting tests
            $script:voteTestAnn = New-HumanAnnotation `
                -EntityId 'vote-test-source' `
                -EntityType 'source' `
                -AnnotationType 'correction' `
                -Content 'Voting test' `
                -Author 'testuser' `
                -ProjectRoot $script:testProjectRoot
        }

        It "Should cast an upvote" {
            $result = Vote-Annotation `
                -AnnotationId $script:voteTestAnn.annotationId `
                -Vote 'up' `
                -ProjectRoot $script:testProjectRoot

            $result.TotalUp | Should -Be 1
            $result.TotalDown | Should -Be 0
            $result.Score | Should -Be 1
        }

        It "Should cast a downvote" {
            $result = Vote-Annotation `
                -AnnotationId $script:voteTestAnn.annotationId `
                -Vote 'down' `
                -ProjectRoot $script:testProjectRoot

            $result.TotalUp | Should -Be 1
            $result.TotalDown | Should -Be 1
            $result.Score | Should -Be 0
        }

        It "Should throw for non-existent annotation" {
            { Vote-Annotation `
                -AnnotationId 'non-existent-id' `
                -Vote 'up' `
                -ProjectRoot $script:testProjectRoot
            } | Should -Throw
        }
    }

    Context "Update-Annotation" {
        BeforeAll {
            $script:updateTestAnn = New-HumanAnnotation `
                -EntityId 'update-test-source' `
                -EntityType 'source' `
                -AnnotationType 'correction' `
                -Content 'Original content' `
                -Author 'testuser' `
                -ProjectRoot $script:testProjectRoot
        }

        It "Should update annotation content" {
            $updated = Update-Annotation `
                -AnnotationId $script:updateTestAnn.annotationId `
                -Content 'Updated content' `
                -ProjectRoot $script:testProjectRoot

            $updated.content | Should -Be 'Updated content'
            $updated.updatedAt | Should -Not -Be $updated.createdAt
        }

        It "Should update annotation status" {
            $updated = Update-Annotation `
                -AnnotationId $script:updateTestAnn.annotationId `
                -Status 'rejected' `
                -ProjectRoot $script:testProjectRoot

            $updated.status | Should -Be 'rejected'
        }

        It "Should update annotation metadata" {
            $updated = Update-Annotation `
                -AnnotationId $script:updateTestAnn.annotationId `
                -Metadata @{ reviewedBy = 'admin'; reviewDate = '2026-04-12' } `
                -ProjectRoot $script:testProjectRoot

            $updated.metadata.reviewedBy | Should -Be 'admin'
            $updated.metadata.reviewDate | Should -Be '2026-04-12'
        }

        It "Should return null for non-existent annotation" {
            $result = Update-Annotation `
                -AnnotationId 'non-existent-id' `
                -Content 'New content' `
                -ProjectRoot $script:testProjectRoot

            $result | Should -Be $null
        }
    }

    Context "New-ProjectOverride" {
        It "Should create a project-local override" {
            $override = New-ProjectOverride `
                -ProjectId 'test-project-override' `
                -EntityId 'pack-godot-001' `
                -OverrideData @{ maxVersion = '4.1'; skipValidation = $true } `
                -Reason 'Project requires specific Godot version' `
                -Author 'testuser' `
                -ProjectRoot $script:testProjectRoot

            $override | Should -Not -Be $null
            $override.annotationId | Should -Not -BeNullOrEmpty
            $override.projectId | Should -Be 'test-project-override'
            $override.entityId | Should -Be 'pack-godot-001'
            $override.annotationType | Should -Be 'override'
            $override.metadata.maxVersion | Should -Be '4.1'
            $override.metadata.skipValidation | Should -Be $true

            $script:testOverrideId = $override.annotationId
        }

        It "Should reject empty project ID" {
            { New-ProjectOverride `
                -ProjectId '' `
                -EntityId 'pack-001' `
                -OverrideData @{ } `
                -Reason 'Test' `
                -ProjectRoot $script:testProjectRoot
            } | Should -Throw
        }

        It "Should reject empty entity ID" {
            { New-ProjectOverride `
                -ProjectId 'test' `
                -EntityId '' `
                -OverrideData @{ } `
                -Reason 'Test' `
                -ProjectRoot $script:testProjectRoot
            } | Should -Throw
        }
    }

    Context "Get-EffectiveAnnotations" {
        BeforeAll {
            # Create multiple annotations for effective testing
            New-HumanAnnotation `
                -EntityId 'effective-test-source' `
                -EntityType 'source' `
                -AnnotationType 'correction' `
                -Content 'Global correction' `
                -Author 'testuser' `
                -Context @{ scope = 'global' } `
                -ProjectRoot $script:testProjectRoot

            New-HumanAnnotation `
                -EntityId 'effective-test-source' `
                -EntityType 'source' `
                -AnnotationType 'caveat' `
                -Content 'Project caveat' `
                -Author 'testuser' `
                -Context @{ scope = 'project'; projectId = 'effective-test-project' } `
                -ProjectRoot $script:testProjectRoot

            # Create project override
            New-ProjectOverride `
                -ProjectId 'effective-test-project' `
                -EntityId 'effective-test-source' `
                -OverrideData @{ customSetting = $true } `
                -Reason 'Project override' `
                -Author 'testuser' `
                -ProjectRoot $script:testProjectRoot
        }

        It "Should return annotations with context" {
            $effective = Get-EffectiveAnnotations `
                -EntityId 'effective-test-source' `
                -Context @{ projectId = 'effective-test-project' } `
                -ProjectRoot $script:testProjectRoot

            $effective | Should -Not -Be $null
            $effective.entityId | Should -Be 'effective-test-source'
            $effective.projectId | Should -Be 'effective-test-project'
        }

        It "Should include project overrides" {
            $effective = Get-EffectiveAnnotations `
                -EntityId 'effective-test-source' `
                -Context @{ projectId = 'effective-test-project' } `
                -ProjectRoot $script:testProjectRoot

            $effective.hasProjectOverrides | Should -Be $true
        }

        It "Should provide scope breakdown" {
            $effective = Get-EffectiveAnnotations `
                -EntityId 'effective-test-source' `
                -Context @{ projectId = 'effective-test-project' } `
                -ProjectRoot $script:testProjectRoot

            $effective.scopeBreakdown | Should -Not -Be $null
            $effective.scopeBreakdown.global | Should -Not -Be $null
        }
    }

    Context "Apply-Annotations" {
        It "Should apply correction to target" {
            $target = @{ 
                content = 'The API version is 2.4'
                confidence = 0.9 
            }
            
            $annotations = @(@{
                annotationType = 'correction'
                content = 'Replace: 2.4 -> 2.5'
                annotationId = 'test-correction'
                status = 'active'
                votes = @{ up = 1; down = 0 }
            })

            $result = Apply-Annotations -Target $target -Annotations $annotations

            $result._annotationCount | Should -Be 1
            $result._corrections.Count | Should -Be 1
        }

        It "Should apply deprecation" {
            $target = @{ content = 'Old API method' }
            
            $annotations = @(@{
                annotationType = 'deprecation'
                content = 'Deprecated in v3.0'
                annotationId = 'test-deprecation'
                status = 'active'
                createdAt = '2026-04-12T10:00:00Z'
                votes = @{ up = 0; down = 0 }
            })

            $result = Apply-Annotations -Target $target -Annotations $annotations

            $result.isDeprecated | Should -Be $true
            $result.deprecationNote | Should -Be 'Deprecated in v3.0'
            $result.deprecatedAt | Should -Be '2026-04-12T10:00:00Z'
        }

        It "Should apply caveat" {
            $target = @{ content = 'Some information' }
            
            $annotations = @(@{
                annotationType = 'caveat'
                content = 'This may not work on Windows'
                annotationId = 'test-caveat'
                status = 'active'
                author = 'testuser'
                votes = @{ up = 0; down = 0 }
            })

            $result = Apply-Annotations -Target $target -Annotations $annotations

            $result._caveats.Count | Should -Be 1
            $result._caveats[0].text | Should -Be 'This may not work on Windows'
        }

        It "Should skip inactive annotations" {
            $target = @{ content = 'Test' }
            
            $annotations = @(@{
                annotationType = 'caveat'
                content = 'Inactive caveat'
                annotationId = 'test-inactive'
                status = 'superseded'
                author = 'testuser'
                votes = @{ up = 0; down = 0 }
            })

            $result = Apply-Annotations -Target $target -Annotations $annotations

            $result._annotationCount | Should -Be 0
        }
    }

    Context "Export-Annotations" {
        BeforeAll {
            # Create test annotations for export
            1..3 | ForEach-Object {
                New-HumanAnnotation `
                    -EntityId "export-test-source-$_" `
                    -EntityType 'source' `
                    -AnnotationType 'correction' `
                    -Content "Export test $_" `
                    -Author 'testuser' `
                    -Context @{ scope = 'global' } `
                    -ProjectRoot $script:testProjectRoot
            }

            $script:exportPath = Join-Path $testDir 'test-export.json'
        }

        It "Should export annotations to file" {
            $result = Export-Annotations `
                -OutputPath $script:exportPath `
                -Filter @{ scopes = @('global') } `
                -ProjectRoot $script:testProjectRoot

            $result.Success | Should -Be $true
            $result.OutputPath | Should -Be $script:exportPath
            $result.Count | Should -BeGreaterThan 0
            Test-Path -LiteralPath $script:exportPath | Should -Be $true
        }

        It "Should export with entity type filter" {
            $exportWithFilter = Join-Path $testDir 'test-export-filtered.json'
            $result = Export-Annotations `
                -OutputPath $exportWithFilter `
                -Filter @{ entityTypes = @('pack') } `
                -ProjectRoot $script:testProjectRoot

            $result.Success | Should -Be $true
            Remove-Item -LiteralPath $exportWithFilter -Force -ErrorAction SilentlyContinue
        }
    }

    Context "Import-Annotations" {
        BeforeAll {
            $script:importExportPath = Join-Path $testDir 'test-import-export.json'
            
            # Create and export annotations
            New-HumanAnnotation `
                -EntityId 'import-test-source' `
                -EntityType 'source' `
                -AnnotationType 'correction' `
                -Content 'Import test' `
                -Author 'testuser' `
                -Context @{ scope = 'global' } `
                -ProjectRoot $script:testProjectRoot

            Export-Annotations `
                -OutputPath $script:importExportPath `
                -Filter @{ entityIds = @('import-test-source') } `
                -ProjectRoot $script:testProjectRoot
        }

        It "Should import annotations from file" {
            # Clear existing first
            $existing = Get-EntityAnnotations -EntityId 'import-test-source' -ProjectRoot $script:testProjectRoot -IncludeInactive
            $existing | ForEach-Object {
                Remove-Annotation -AnnotationId $_.annotationId -Force -ProjectRoot $script:testProjectRoot
            }

            $result = Import-Annotations `
                -Path $script:importExportPath `
                -ProjectRoot $script:testProjectRoot

            $result.Total | Should -BeGreaterThan 0
            ($result.Imported + $result.Updated) | Should -BeGreaterThan 0
        }

        It "Should merge annotations when -Merge specified" {
            $result = Import-Annotations `
                -Path $script:importExportPath `
                -Merge `
                -ProjectRoot $script:testProjectRoot

            # Most should be skipped or updated since they already exist
            $result.Skipped + $result.Updated | Should -BeGreaterThan 0
        }
    }

    Context "Register-Annotation" {
        It "Should register a pre-constructed annotation" {
            $annotation = @{
                entityId = 'register-test'
                entityType = 'source'
                annotationType = 'correction'
                content = 'Registered annotation'
                author = 'testuser'
                status = 'active'
                scope = 'global'
                votes = @{ up = 0; down = 0 }
            }

            $result = Register-Annotation `
                -Annotation $annotation `
                -ProjectRoot $script:testProjectRoot

            $result | Should -Not -Be $null
            $result.annotationId | Should -Not -BeNullOrEmpty
            $result.createdAt | Should -Not -BeNullOrEmpty
        }

        It "Should generate annotation ID if not provided" {
            $annotation = @{
                entityId = 'register-test-no-id'
                entityType = 'source'
                annotationType = 'correction'
                content = 'No ID provided'
                author = 'testuser'
            }

            $result = Register-Annotation `
                -Annotation $annotation `
                -ProjectRoot $script:testProjectRoot

            $result.annotationId | Should -Not -BeNullOrEmpty
            $result.annotationId | Should -Match '^ann-'
        }
    }

    Context "Remove-Annotation" {
        BeforeAll {
            $script:removeTestAnn = New-HumanAnnotation `
                -EntityId 'remove-test-source' `
                -EntityType 'source' `
                -AnnotationType 'correction' `
                -Content 'To be removed' `
                -Author 'testuser' `
                -ProjectRoot $script:testProjectRoot
        }

        It "Should remove an annotation" {
            $result = Remove-Annotation `
                -AnnotationId $script:removeTestAnn.annotationId `
                -Force `
                -ProjectRoot $script:testProjectRoot

            $result | Should -Be $true
        }

        It "Should return false for non-existent annotation" {
            $result = Remove-Annotation `
                -AnnotationId 'non-existent-id' `
                -Force `
                -ProjectRoot $script:testProjectRoot

            $result | Should -Be $false
        }
    }

    AfterAll {
        # Cleanup test files
        $testFiles = @(
            'test-export.json',
            'test-export-filtered.json',
            'test-import-export.json'
        )
        
        foreach ($file in $testFiles) {
            $path = Join-Path $testDir $file
            if (Test-Path -LiteralPath $path) {
                Remove-Item -LiteralPath $path -Force -ErrorAction SilentlyContinue
            }
        }

        # Note: We intentionally don't clean up annotations.json to preserve test data
        # In production, this would be handled appropriately
    }
}

Write-Host "`nTest execution complete. Run with Pester for full results." -ForegroundColor Green
