#requires -Version 5.1
<#
.SYNOPSIS
    Retrieval Integrity Tests for LLM Workflow Platform

.DESCRIPTION
    Pester v5 test suite for retrieval and answer integrity modules:
    - QueryRouter.ps1: Query routing and intent detection
    - CrossPackArbitration.ps1: Cross-pack dispute resolution
    - ConfidencePolicy.ps1: Confidence-based abstention

.NOTES
    File: RetrievalIntegrity.Tests.ps1
    Version: 1.0.0
    Author: LLM Workflow Team
    Requires: Pester 5.0+
#>

BeforeAll {
    # Set up test environment
    $script:TestRoot = Join-Path $TestDrive "RetrievalIntegrityTests"
    $script:ModuleRoot = Join-Path $PSScriptRoot ".." "module" "LLMWorkflow"
    $script:RetrievalModulePath = Join-Path $ModuleRoot "retrieval"
    
    # Create test directories
    New-Item -ItemType Directory -Path $script:TestRoot -Force | Out-Null
    
    # Import modules
    $queryRouterPath = Join-Path $script:RetrievalModulePath "QueryRouter.ps1"
    $crossPackArbitrationPath = Join-Path $script:RetrievalModulePath "CrossPackArbitration.ps1"
    $confidencePolicyPath = Join-Path $script:RetrievalModulePath "ConfidencePolicy.ps1"
    
    if (Test-Path $queryRouterPath) { . $queryRouterPath }
    if (Test-Path $crossPackArbitrationPath) { . $crossPackArbitrationPath }
    if (Test-Path $confidencePolicyPath) { . $confidencePolicyPath }
}

Describe "QueryRouter Module Tests" {
    Context "Get-QueryIntent Function" {
        It "Should detect API lookup intent" {
            $queries = @(
                "How do I use the GDScript API for signals?"
                "What are the parameters for the move method?"
                "Show me the documentation for Texture2D"
            )
            
            foreach ($query in $queries) {
                $intent = Get-QueryIntent -Query $query
                $intent.primaryIntent | Should -Be "api-lookup"
                $intent.confidence | Should -BeGreaterThan 0
            }
        }

        It "Should detect plugin pattern intent" {
            $queries = @(
                "How do I create a plugin with proper architecture?"
                "What's the best practice for plugin hooks?"
                "Show me a plugin pattern for RPG Maker"
            )
            
            foreach ($query in $queries) {
                $intent = Get-QueryIntent -Query $query
                $intent.primaryIntent | Should -Be "plugin-pattern"
            }
        }

        It "Should detect conflict diagnosis intent" {
            $queries = @(
                "Why is my plugin conflicting with another?"
                "I'm getting a TypeError in my code"
                "How to debug plugin compatibility issues?"
            )
            
            foreach ($query in $queries) {
                $intent = Get-QueryIntent -Query $query
                $intent.primaryIntent | Should -Be "conflict-diagnosis"
            }
        }

        It "Should detect codegen intent" {
            $queries = @(
                "Generate a class for player movement"
                "Create a script template for NPCs"
                "Write code for a battle system"
            )
            
            foreach ($query in $queries) {
                $intent = Get-QueryIntent -Query $query
                $intent.primaryIntent | Should -Be "codegen"
            }
        }

        It "Should track matched keywords" {
            $query = "How do I use the GDScript API for signals and methods?"
            $intent = Get-QueryIntent -Query $query
            
            $intent.matchedKeywords.Count | Should -BeGreaterThan 0
            $intent.matchedKeywords["api-lookup"] | Should -Contain "api"
            $intent.matchedKeywords["api-lookup"] | Should -Contain "method"
        }

        It "Should return all intent scores" {
            $query = "How do I create a plugin that uses the API?"
            $intent = Get-QueryIntent -Query $query
            
            $intent.scores.Count | Should -BeGreaterThan 0
            $intent.scores["api-lookup"] | Should -Not -BeNullOrEmpty
            $intent.scores["plugin-pattern"] | Should -Not -BeNullOrEmpty
        }
    }

    Context "Get-RetrievalProfile Function" {
        It "Should return profile configuration" {
            $profiles = @("api-lookup", "plugin-pattern", "codegen", "conflict-diagnosis")
            
            foreach ($profileName in $profiles) {
                $profile = Get-RetrievalProfile -ProfileName $profileName
                $profile | Should -Not -BeNullOrEmpty
                $profile.profileName | Should -Be $profileName
                $profile.description | Should -Not -BeNullOrEmpty
                $profile.packPreferences | Should -Not -BeNullOrEmpty
            }
        }

        It "Should return null for unknown profiles" {
            $profile = Get-RetrievalProfile -ProfileName "unknown-profile"
            $profile | Should -BeNullOrEmpty
        }

        It "Should include pack preferences" {
            $profile = Get-RetrievalProfile -ProfileName "api-lookup"
            $profile.packPreferences.primary | Should -Not -BeNullOrEmpty
            $profile.packPreferences.secondary | Should -Not -BeNullOrEmpty
        }
    }

    Context "Route-QueryToPacks Function" {
        It "Should route to appropriate packs" {
            $query = "How do I use GDScript signals?"
            $availablePacks = @(
                @{ packId = "godot-engine"; domain = "godot"; collections = @{} }
                @{ packId = "rpgmaker-mz"; domain = "rpgmaker"; collections = @{} }
            )
            
            $result = Route-QueryToPacks -Query $query -AvailablePacks $availablePacks -RetrievalProfile "api-lookup"
            
            $result | Should -Not -BeNullOrEmpty
            $result.selectedPacks.Count | Should -BeGreaterThan 0
        }

        It "Should calculate relevance scores" {
            $query = "GDScript node signals"
            $availablePacks = @(
                @{ packId = "godot-engine"; domain = "godot"; collections = @{} }
            )
            
            $result = Route-QueryToPacks -Query $query -AvailablePacks $availablePacks -RetrievalProfile "api-lookup"
            
            $result.packOrder[0].score | Should -BeGreaterThan 0
        }

        It "Should respect minimum threshold" {
            $query = "Some unrelated query that doesn't match anything"
            $availablePacks = @(
                @{ packId = "godot-engine"; domain = "godot"; collections = @{} }
            )
            
            $result = Route-QueryToPacks -Query $query -AvailablePacks $availablePacks -RetrievalProfile "api-lookup"
            
            # Should not select any packs if all below threshold
            $result.selectedPacks.Count | Should -Be 0
        }
    }

    Context "Invoke-QueryRouting Function" {
        It "Should complete full routing process" {
            $query = "How do I create a battle system plugin?"
            $result = Invoke-QueryRouting -Query $query -EnableArbitration $false
            
            $result | Should -Not -BeNullOrEmpty
            $result.routingId | Should -Not -BeNullOrEmpty
            $result.query | Should -Be $query
            $result.retrievalProfile | Should -Not -BeNullOrEmpty
            $result.detectedIntent | Should -Not -BeNullOrEmpty
            $result.executionTimeMs | Should -BeGreaterOrEqual 0
            $result.createdAt | Should -Not -BeNullOrEmpty
        }

        It "Should use explicit retrieval profile when provided" {
            $query = "Generate code for a plugin"
            $result = Invoke-QueryRouting -Query $query -RetrievalProfile "codegen" -EnableArbitration $false
            
            $result.retrievalProfile | Should -Be "codegen"
        }

        It "Should handle errors gracefully" {
            $result = Invoke-QueryRouting -Query "" -EnableArbitration $false
            
            $result | Should -Not -BeNullOrEmpty
            # Should still return a valid result structure even with empty query
            $result.routingId | Should -Not -BeNullOrEmpty
        }
    }

    Context "Get-RoutingExplanation Function" {
        It "Should generate text explanations" {
            $routingResult = Invoke-QueryRouting -Query "Test query" -EnableArbitration $false
            $explanation = Get-RoutingExplanation -RoutingResult $routingResult -Format "text"
            
            $explanation | Should -Not -BeNullOrEmpty
            $explanation | Should -Match "*Query Routing Decision*"
            $explanation | Should -Match "*Retrieval Profile*"
        }

        It "Should generate markdown explanations" {
            $routingResult = Invoke-QueryRouting -Query "Test query" -EnableArbitration $false
            $explanation = Get-RoutingExplanation -RoutingResult $routingResult -Format "markdown"
            
            $explanation | Should -Not -BeNullOrEmpty
            $explanation | Should -Match "## Query Routing Decision"
        }
    }
}

Describe "CrossPackArbitration Module Tests" {
    Context "Test-PackRelevance Function" {
        It "Should score pack relevance based on domain keywords" {
            $packManifest = @{
                packId = "godot-engine"
                domain = "godot"
                collections = @{}
            }
            
            $score1 = Test-PackRelevance -Query "GDScript signals" -PackManifest $packManifest
            $score2 = Test-PackRelevance -Query "RPG Maker plugins" -PackManifest $packManifest
            
            $score1 | Should -BeGreaterThan $score2
        }

        It "Should boost scores for authority roles" {
            $packManifest1 = @{
                packId = "pack1"
                collections = @{
                    coll1 = @{ authorityRole = "core-engine" }
                }
            }
            $packManifest2 = @{
                packId = "pack2"
                collections = @{
                    coll1 = @{ authorityRole = "starter-template" }
                }
            }
            
            $query = "Test query"
            $score1 = Test-PackRelevance -Query $query -PackManifest $packManifest1
            $score2 = Test-PackRelevance -Query $query -PackManifest $packManifest2
            
            $score1 | Should -BeGreaterThan $score2
        }

        It "Should return normalized scores between 0 and 1" {
            $packManifest = @{
                packId = "test"
                collections = @{}
            }
            
            $score = Test-PackRelevance -Query "Test query" -PackManifest $packManifest
            
            $score | Should -BeGreaterOrEqual 0.0
            $score | Should -BeLessOrEqual 1.0
        }
    }

    Context "Get-ArbitratedPackOrder Function" {
        It "Should order packs by relevance and authority" {
            $packs = @(
                @{ packId = "pack1"; collections = @{ coll1 = @{ authorityRole = "core-engine" } } }
                @{ packId = "pack2"; collections = @{ coll1 = @{ authorityRole = "starter-template" } } }
            )
            $workspaceContext = New-Object -TypeName PSObject -Property @{}
            
            $result = Get-ArbitratedPackOrder -Query "Test query" -Packs $packs -WorkspaceContext $workspaceContext
            
            $result.Count | Should -Be 2
            $result[0].score | Should -BeGreaterOrEqual $result[1].score
        }

        It "Should boost private project packs for project-local queries" {
            $packs = @(
                @{ packId = "mygame_private_v1"; collections = @{} }
                @{ packId = "public-pack"; collections = @{} }
            )
            $workspaceContext = New-Object -TypeName PSObject -Property @{}
            
            $result = Get-ArbitratedPackOrder -Query "How do I fix my project code?" -Packs $packs -WorkspaceContext $workspaceContext
            
            # Private pack should be boosted for project-local query
            $result | Where-Object { $_.packId -eq "mygame_private_v1" } | Should -Not -BeNullOrEmpty
        }
    }

    Context "Invoke-CrossPackArbitration Function" {
        It "Should resolve cross-pack queries" {
            $packs = @(
                @{ packId = "godot-engine"; collections = @{ coll1 = @{ authorityRole = "core-engine" } } }
                @{ packId = "rpgmaker-mz"; collections = @{ coll1 = @{ authorityRole = "core-runtime" } } }
            )
            $workspaceContext = New-Object -TypeName PSObject -Property @{}
            
            $result = Invoke-CrossPackArbitration -Query "Compare Godot and RPG Maker" -Packs $packs -WorkspaceContext $workspaceContext
            
            $result | Should -Not -BeNullOrEmpty
            $result.arbitrationId | Should -Not -BeNullOrEmpty
            $result.packOrder | Should -Not -BeNullOrEmpty
            $result.primaryPack | Should -Not -BeNullOrEmpty
            $result.isCrossPack | Should -Be $true
        }

        It "Should detect cross-pack queries" {
            $packs = @(
                @{ packId = "godot-engine"; collections = @{} }
                @{ packId = "rpgmaker-mz"; collections = @{} }
            )
            $workspaceContext = New-Object -TypeName PSObject -Property @{}
            
            $result = Invoke-CrossPackArbitration -Query "Godot vs RPG Maker" -Packs $packs -WorkspaceContext $workspaceContext
            
            $result.isCrossPack | Should -Be $true
        }

        It "Should set primary pack correctly" {
            $packs = @(
                @{ packId = "high-authority"; collections = @{ coll1 = @{ authorityRole = "core-engine" } } }
                @{ packId = "low-authority"; collections = @{ coll1 = @{ authorityRole = "starter-template" } } }
            )
            $workspaceContext = New-Object -TypeName PSObject -Property @{}
            
            $result = Invoke-CrossPackArbitration -Query "Test query" -Packs $packs -WorkspaceContext $workspaceContext
            
            $result.primaryPack | Should -Be "high-authority"
        }
    }

    Context "New-DisputeSet and Add-DisputeClaim Functions" {
        It "Should create dispute sets" {
            $dispute = New-DisputeSet -DisputedEntity "Best pattern for X" -Status "open"
            
            $dispute | Should -Not -BeNullOrEmpty
            $dispute.disputeId | Should -Not -BeNullOrEmpty
            $dispute.disputedEntity | Should -Be "Best pattern for X"
            $dispute.status | Should -Be "open"
            $dispute.competingClaims | Should -Not -BeNullOrEmpty
        }

        It "Should add claims to disputes" {
            $dispute = New-DisputeSet -DisputedEntity "Best pattern" -Status "open"
            $dispute = Add-DisputeClaim -DisputeSet $dispute -ClaimSource "pack1" -ClaimContent "Use approach A" -TrustLevel "High"
            $dispute = Add-DisputeClaim -DisputeSet $dispute -ClaimSource "pack2" -ClaimContent "Use approach B" -TrustLevel "Medium"
            
            $dispute.competingClaims.Count | Should -Be 2
            $dispute.competingClaims[0].source | Should -Be "pack1"
            $dispute.competingClaims[1].source | Should -Be "pack2"
        }

        It "Should resolve disputes by priority" {
            $dispute = New-DisputeSet -DisputedEntity "Test dispute" -Status "open"
            Add-DisputeClaim -DisputeSet $dispute -ClaimSource "godot-engine" -ClaimContent "Approach A" -TrustLevel "High" | Out-Null
            Add-DisputeClaim -DisputeSet $dispute -ClaimSource "rpgmaker-mz" -ClaimContent "Approach B" -TrustLevel "Medium" | Out-Null
            
            $resolved = Set-DisputePreferredSource -DisputeSet $dispute -PreferredSource "godot-engine" -Resolution "Higher authority"
            
            $resolved.status | Should -Be "resolved"
            $resolved.preferredSource | Should -Be "godot-engine"
            $resolved.resolution | Should -Be "Higher authority"
        }
    }

    Context "Add-CrossPackLabel Function" {
        It "Should add source labels to answers" {
            $answer = "This is the answer content."
            $labeled = Add-CrossPackLabel -Answer $answer -SourcePacks @("godot-engine") -PrimaryPack "godot-engine"
            
            $labeled | Should -Match "\[Source: godot-engine\]"
            $labeled | Should -Match "This is the answer content."
        }

        It "Should add cross-pack indicator for multiple sources" {
            $answer = "This is the answer content."
            $labeled = Add-CrossPackLabel -Answer $answer -SourcePacks @("godot-engine", "rpgmaker-mz") -PrimaryPack "godot-engine" -IsCrossPack $true
            
            $labeled | Should -Match "\[Cross-pack:*"
            $labeled | Should -Match "\[Note: This answer combines information from multiple domains*"
        }
    }
}

Describe "ConfidencePolicy Module Tests" {
    Context "Test-AnswerConfidence Function" {
        It "Should calculate confidence from high-quality evidence" {
            $evidence = @(
                @{ sourceId = "src1"; relevanceScore = 0.95; authorityScore = 0.90; sourceType = "core-runtime"; evidenceType = "code-example" }
                @{ sourceId = "src2"; relevanceScore = 0.88; authorityScore = 0.85; sourceType = "exemplar-pattern"; evidenceType = "tutorial" }
            )
            $answerPlan = @{ confidencePolicy = $null }
            
            $result = Test-AnswerConfidence -Evidence $evidence -AnswerPlan $answerPlan
            
            $result.confidenceScore | Should -BeGreaterThan 0.7
            $result.answerMode | Should -BeIn @("direct", "caveat")
            $result.shouldAbstain | Should -Be $false
        }

        It "Should abstain with low-confidence evidence" {
            $evidence = @(
                @{ sourceId = "src1"; relevanceScore = 0.30; authorityScore = 0.20; sourceType = "unknown"; evidenceType = "explanation" }
            )
            $answerPlan = @{ confidencePolicy = $null }
            
            $result = Test-AnswerConfidence -Evidence $evidence -AnswerPlan $answerPlan
            
            $result.confidenceScore | Should -BeLessThan 0.5
            $result.answerMode | Should -Be "abstain"
            $result.shouldAbstain | Should -Be $true
        }

        It "Should abstain with no evidence" {
            $answerPlan = @{ confidencePolicy = $null }
            
            $result = Test-AnswerConfidence -Evidence @() -AnswerPlan $answerPlan
            
            $result.confidenceScore | Should -Be 0.0
            $result.answerMode | Should -Be "abstain"
            $result.shouldAbstain | Should -Be $true
            $result.abstainReason | Should -Match "*No evidence provided*"
        }

        It "Should handle policy violations" {
            $evidence = @(
                @{ sourceId = "src1"; relevanceScore = 0.90; authorityScore = 0.90; sourceType = "core-runtime" }
            )
            $answerPlan = @{ confidencePolicy = $null }
            $context = @{ evidenceIssues = @(@{ type = "policy-violation"; severity = "critical" }) }
            
            $result = Test-AnswerConfidence -Evidence $evidence -AnswerPlan $answerPlan -Context $context
            
            $result.answerMode | Should -Be "escalate"
        }
    }

    Context "Get-ConfidenceComponents Function" {
        It "Should calculate all confidence components" {
            $evidence = @(
                @{ sourceId = "src1"; relevanceScore = 0.90; authorityScore = 0.85; sourceType = "core-runtime"; evidenceType = "code-example" }
            )
            
            $components = Get-ConfidenceComponents -Evidence $evidence -Context @{}
            
            $components.relevance | Should -Not -BeNullOrEmpty
            $components.authority | Should -Not -BeNullOrEmpty
            $components.consistency | Should -Not -BeNullOrEmpty
            $components.coverage | Should -Not -BeNullOrEmpty
        }

        It "Should calculate relevance component" {
            $evidence = @(
                @{ sourceId = "src1"; relevanceScore = 0.90 }
                @{ sourceId = "src2"; relevanceScore = 0.80 }
            )
            
            $relevance = Calculate-RelevanceComponent -Evidence $evidence
            
            $relevance.score | Should -BeGreaterThan 0
            $relevance.score | Should -BeLessOrEqual 1.0
            $relevance.details.Count | Should -Be 2
        }

        It "Should calculate authority component" {
            $evidence = @(
                @{ sourceId = "src1"; sourceType = "core-runtime"; trustTier = "High" }
                @{ sourceId = "src2"; sourceType = "exemplar-pattern"; trustTier = "Medium" }
            )
            
            $authority = Calculate-AuthorityComponent -Evidence $evidence
            
            $authority.score | Should -BeGreaterThan 0
            $authority.details.Count | Should -Be 2
        }

        It "Should calculate consistency component" {
            $evidence = @(
                @{ sourceId = "src1"; content = "Approach A"; claim = "approach-a" }
                @{ sourceId = "src2"; content = "Approach A"; claim = "approach-a" }
            )
            
            $consistency = Calculate-ConsistencyComponent -Evidence $evidence
            
            $consistency.score | Should -BeGreaterThan 0.8
            $consistency.details.hasContradictions | Should -Be $false
        }

        It "Should detect contradictions in consistency" {
            $evidence = @(
                @{ sourceId = "src1"; content = "Approach A"; claim = "approach-a" }
                @{ sourceId = "src2"; content = "Approach B"; claim = "approach-b" }
            )
            
            $consistency = Calculate-ConsistencyComponent -Evidence $evidence
            
            $consistency.details.hasContradictions | Should -Be $true
            $consistency.details.distinctClaims | Should -Be 2
        }

        It "Should calculate coverage component" {
            $evidence = @(
                @{ sourceId = "src1"; evidenceType = "code-example" }
                @{ sourceId = "src2"; evidenceType = "api-reference" }
            )
            $context = @{ requiredEvidenceTypes = @("code-example", "api-reference", "tutorial") }
            
            $coverage = Calculate-CoverageComponent -Evidence $evidence -Context $context
            
            $coverage.score | Should -BeGreaterThan 0
            $coverage.score | Should -BeLessThan 1.0  # Missing tutorial
        }
    }

    Context "Get-AnswerMode Function" {
        It "Should return direct for high confidence with no issues" {
            $policy = Get-DefaultConfidencePolicy
            $result = Get-AnswerMode -ConfidenceScore 0.90 -Policy $policy -EvidenceIssues @()
            
            $result | Should -Be "direct"
        }

        It "Should return caveat for medium confidence" {
            $policy = Get-DefaultConfidencePolicy
            $result = Get-AnswerMode -ConfidenceScore 0.75 -Policy $policy -EvidenceIssues @()
            
            $result | Should -Be "caveat"
        }

        It "Should return abstain for low confidence" {
            $policy = Get-DefaultConfidencePolicy
            $result = Get-AnswerMode -ConfidenceScore 0.40 -Policy $policy -EvidenceIssues @()
            
            $result | Should -Be "abstain"
        }

        It "Should return escalate for policy violations" {
            $policy = Get-DefaultConfidencePolicy
            $issues = @(@{ type = "policy-violation"; severity = "critical" })
            $result = Get-AnswerMode -ConfidenceScore 0.90 -Policy $policy -EvidenceIssues $issues
            
            $result | Should -Be "escalate"
        }

        It "Should return caveat for high confidence with major issues" {
            $policy = Get-DefaultConfidencePolicy
            $issues = @(@{ type = "uncertainty"; severity = "high" })
            $result = Get-AnswerMode -ConfidenceScore 0.90 -Policy $policy -EvidenceIssues $issues
            
            $result | Should -Be "caveat"
        }

        It "Should return dispute for conflicting high-authority sources" {
            $policy = Get-DefaultConfidencePolicy
            $issues = @(
                @{ type = "source-conflict"; authority = 0.80 }
                @{ type = "source-conflict"; authority = 0.75 }
            )
            $result = Get-AnswerMode -ConfidenceScore 0.85 -Policy $policy -EvidenceIssues $issues
            
            $result | Should -Be "dispute"
        }
    }

    Context "Test-ShouldAbstain Function" {
        It "Should abstain below threshold" {
            $policy = Get-DefaultConfidencePolicy
            $evidence = @(@{ sourceId = "src1" })
            
            $result = Test-ShouldAbstain -ConfidenceScore 0.40 -Evidence $evidence -Policy $policy
            
            $result | Should -Be $true
        }

        It "Should not abstain above threshold" {
            $policy = Get-DefaultConfidencePolicy
            $evidence = @(@{ sourceId = "src1" })
            
            $result = Test-ShouldAbstain -ConfidenceScore 0.80 -Evidence $evidence -Policy $policy
            
            $result | Should -Be $false
        }

        It "Should abstain with insufficient evidence count" {
            $policy = @{ thresholds = @{ abstain = 0.50 }; minimumEvidenceCount = 3 }
            $evidence = @(@{ sourceId = "src1" })
            
            $result = Test-ShouldAbstain -ConfidenceScore 0.80 -Evidence $evidence -Policy $policy
            
            $result | Should -Be $true
        }

        It "Should abstain when all sources are low trust" {
            $policy = @{ thresholds = @{ abstain = 0.50 }; minimumEvidenceCount = 1 }
            $evidence = @(
                @{ sourceId = "src1"; trustTier = "Low" }
                @{ sourceId = "src2"; trustTier = "Quarantined" }
            )
            
            $result = Test-ShouldAbstain -ConfidenceScore 0.80 -Evidence $evidence -Policy $policy
            
            $result | Should -Be $true
        }
    }

    Context "Get-DefaultConfidencePolicy Function" {
        It "Should return default policy structure" {
            $policy = Get-DefaultConfidencePolicy
            
            $policy | Should -Not -BeNullOrEmpty
            $policy.policyName | Should -Be "default"
            $policy.schemaVersion | Should -Be 1
            $policy.thresholds.direct | Should -Be 0.85
            $policy.thresholds.caveat | Should -Be 0.70
            $policy.thresholds.abstain | Should -Be 0.50
            $policy.weights.relevance | Should -Be 0.40
            $policy.weights.authority | Should -Be 0.30
            $policy.weights.consistency | Should -Be 0.20
            $policy.weights.coverage | Should -Be 0.10
        }
    }

    Context "Get-AbstainDecision Function" {
        It "Should create proper abstain decision" {
            $decision = Get-AbstainDecision -ConfidenceScore 0.0 -Reason "Insufficient evidence" -Alternatives @{ suggestion = "Try again" }
            
            $decision.answerMode | Should -Be "abstain"
            $decision.shouldAbstain | Should -Be $true
            $decision.abstainReason | Should -Be "Insufficient evidence"
            $decision.alternatives.suggestion | Should -Be "Try again"
            $decision.components.relevance.score | Should -Be 0.0
        }
    }

    Context "Get-EscalationDecision Function" {
        It "Should create proper escalation decision" {
            $decision = Get-EscalationDecision -Reason "Security boundary violation" -EscalationTarget "security-team" -Context @{ query = "test" }
            
            $decision.answerMode | Should -Be "escalate"
            $decision.shouldAbstain | Should -Be $true
            $decision.escalationTarget | Should -Be "security-team"
            $decision.escalationContext.query | Should -Be "test"
            $decision.evidenceIssues[0].severity | Should -Be "critical"
        }
    }
}
