#requires -Version 5.1
<#
.SYNOPSIS
    Policy Engine Tests for LLM Workflow Platform

.DESCRIPTION
    Pester v5 test suite for the policy externalization layer:
    - PolicyAdapter.ps1: adapter creation, fallback mode, allow/deny decisions
    - PolicyDecisionCache.ps1: cache hit/miss, TTL, clearing

.NOTES
    File: PolicyEngine.Tests.ps1
    Version: 1.0.0
    Requires: Pester 5.0+
#>

BeforeAll {
    $ErrorActionPreference = 'Stop'
    $script:ModuleRoot = Join-Path (Join-Path (Join-Path (Join-Path $PSScriptRoot "..") "module") "LLMWorkflow") "policy"
    $script:AdapterPath = Join-Path $script:ModuleRoot "PolicyAdapter.ps1"
    $script:CachePath = Join-Path $script:ModuleRoot "PolicyDecisionCache.ps1"

    if (Test-Path $script:AdapterPath) { . $script:AdapterPath }
    if (Test-Path $script:CachePath) { . $script:CachePath }
}

AfterAll {
    # Clean up any adapters and cache entries created during tests
    if ($script:AdapterInstances) {
        $keys = @($script:AdapterInstances.Keys)
        foreach ($k in $keys) {
            Remove-PolicyAdapter -AdapterId $k -ErrorAction SilentlyContinue | Out-Null
        }
    }
    if ($script:PolicyCache) {
        Clear-PolicyDecisionCache -ErrorAction SilentlyContinue | Out-Null
    }
}

Describe "PolicyAdapter Module Tests" {
    Context "New-PolicyAdapter" {
        It "Should create a fallback adapter by default" {
            $adapter = New-PolicyAdapter
            $adapter | Should -Not -BeNullOrEmpty
            $adapter.EngineType | Should -Be "fallback"
            $adapter.FallbackMode | Should -Be "in-process"
        }

        It "Should create an OPA adapter with a URI" {
            $adapter = New-PolicyAdapter -EngineUri "http://localhost:8181/v1/data" -EngineType "opa"
            $adapter.EngineType | Should -Be "opa"
            $adapter.EngineUri | Should -Be "http://localhost:8181/v1/data"
        }

        It "Should throw when creating an OPA adapter without a URI" {
            { New-PolicyAdapter -EngineType "opa" } | Should -Throw -ExpectedMessage "*EngineUri is required*"
        }
    }

    Context "Invoke-PolicyDecision - Fallback Mode" {
        BeforeEach {
            $script:FallbackAdapter = New-PolicyAdapter -EngineType "fallback" -FallbackMode "in-process"
        }

        It "Should allow a safe command in ci mode" {
            $result = Invoke-PolicyDecision -Adapter $script:FallbackAdapter `
                -Domain "execution_mode" `
                -InputObject @{ mode = "ci"; command = "build"; safetyLevel = "Mutating" }
            $result.Decision | Should -Be "allow"
            $result.Fallback | Should -Be $true
            $result.Explanation | Should -Match "allowed"
        }

        It "Should deny a destructive command in ci mode" {
            $result = Invoke-PolicyDecision -Adapter $script:FallbackAdapter `
                -Domain "execution_mode" `
                -InputObject @{ mode = "ci"; command = "delete"; safetyLevel = "Destructive" }
            $result.Decision | Should -Be "deny"
            $result.Explanation | Should -Match "Destructive*"
        }

        It "Should deny an unknown domain" {
            $result = Invoke-PolicyDecision -Adapter $script:FallbackAdapter `
                -Domain "unknown_domain" `
                -InputObject @{ }
            $result.Decision | Should -Be "deny"
            $result.Explanation | Should -Match "Unknown policy domain"
        }
    }

    Context "Invoke-PolicyDecision - Default-Decision Fallback" {
        BeforeEach {
            $script:DefaultDenyAdapter = New-PolicyAdapter -EngineType "fallback" -FallbackMode "default-decision" -DefaultDecision "deny"
            $script:DefaultAllowAdapter = New-PolicyAdapter -EngineType "fallback" -FallbackMode "default-decision" -DefaultDecision "allow"
        }

        It "Should return default deny when configured" {
            $result = Invoke-PolicyDecision -Adapter $script:DefaultDenyAdapter `
                -Domain "execution_mode" `
                -InputObject @{ mode = "interactive"; command = "help" }
            $result.Decision | Should -Be "deny"
            $result.Explanation | Should -Match "default decision 'deny'"
        }

        It "Should return default allow when configured" {
            $result = Invoke-PolicyDecision -Adapter $script:DefaultAllowAdapter `
                -Domain "execution_mode" `
                -InputObject @{ mode = "interactive"; command = "help" }
            $result.Decision | Should -Be "allow"
            $result.Explanation | Should -Match "default decision 'allow'"
        }
    }

    Context "Test-PolicyDecision Boolean Wrapper" {
        BeforeEach {
            $script:BoolAdapter = New-PolicyAdapter -EngineType "fallback" -FallbackMode "in-process"
        }

        It "Should return true for allowed decisions" {
            $allowed = Test-PolicyDecision -Adapter $script:BoolAdapter `
                -Domain "execution_mode" `
                -InputObject @{ mode = "interactive"; command = "sync"; safetyLevel = "Mutating" }
            $allowed | Should -Be $true
        }

        It "Should return false for denied decisions" {
            $allowed = Test-PolicyDecision -Adapter $script:BoolAdapter `
                -Domain "execution_mode" `
                -InputObject @{ mode = "mcp-readonly"; command = "sync"; safetyLevel = "Mutating" }
            $allowed | Should -Be $false
        }
    }

    Context "Get-PolicyExplanation" {
        It "Should return the explanation from a decision result" {
            $decision = [PSCustomObject]@{
                Decision = "allow"
                Explanation = "Test explanation."
                Fallback = $false
            }
            $explanation = Get-PolicyExplanation -DecisionResult $decision
            $explanation | Should -Be "Test explanation."
        }

        It "Should note fallback when present" {
            $decision = [PSCustomObject]@{
                Decision = "deny"
                Explanation = "Denied by policy."
                Fallback = $true
            }
            $explanation = Get-PolicyExplanation -DecisionResult $decision
            $explanation | Should -Match "Denied by policy"
            $explanation | Should -Match "fallback"
        }
    }

    Context "MCP Exposure Policy Domain" {
        BeforeEach {
            $script:McpAdapter = New-PolicyAdapter -EngineType "fallback" -FallbackMode "in-process"
        }

        It "Should allow read-only MCP tools" {
            $result = Invoke-PolicyDecision -Adapter $script:McpAdapter `
                -Domain "mcp_exposure" `
                -InputObject @{ toolCategory = "read-only"; workspaceBound = $true }
            $result.Decision | Should -Be "allow"
        }

        It "Should deny mutating tools without review" {
            $result = Invoke-PolicyDecision -Adapter $script:McpAdapter `
                -Domain "mcp_exposure" `
                -InputObject @{ toolCategory = "mutating"; requiresReview = $false; workspaceBound = $true }
            $result.Decision | Should -Be "deny"
        }
    }

    Context "Interpack Transfer Policy Domain" {
        BeforeEach {
            $script:TransferAdapter = New-PolicyAdapter -EngineType "fallback" -FallbackMode "in-process"
        }

        It "Should allow transfer with verified provenance" {
            $result = Invoke-PolicyDecision -Adapter $script:TransferAdapter `
                -Domain "interpack_transfer" `
                -InputObject @{ sourceQuarantine = $false; provenanceVerified = $true }
            $result.Decision | Should -Be "allow"
        }

        It "Should deny transfer from quarantine without promotion" {
            $result = Invoke-PolicyDecision -Adapter $script:TransferAdapter `
                -Domain "interpack_transfer" `
                -InputObject @{ sourceQuarantine = $true; promoted = $false; provenanceVerified = $true }
            $result.Decision | Should -Be "deny"
        }
    }

    Context "Workspace Boundary Policy Domain" {
        BeforeEach {
            $script:BoundaryAdapter = New-PolicyAdapter -EngineType "fallback" -FallbackMode "in-process"
        }

        It "Should allow private visibility without boundary crossing" {
            $result = Invoke-PolicyDecision -Adapter $script:BoundaryAdapter `
                -Domain "workspace_boundary" `
                -InputObject @{ visibility = "private"; crossesBoundary = $false }
            $result.Decision | Should -Be "allow"
        }

        It "Should deny private visibility crossing boundary" {
            $result = Invoke-PolicyDecision -Adapter $script:BoundaryAdapter `
                -Domain "workspace_boundary" `
                -InputObject @{ visibility = "private"; crossesBoundary = $true; allowedDestinations = @("dest1") }
            $result.Decision | Should -Be "deny"
        }
    }
}

Describe "PolicyDecisionCache Module Tests" {
    BeforeEach {
        Clear-PolicyDecisionCache | Out-Null
    }

    Context "Cache Hit and Miss" {
        It "Should return null on cache miss" {
            $entry = Get-PolicyDecisionCache -Key "nonexistent-key"
            $entry | Should -BeNullOrEmpty
        }

        It "Should return a hit after storing a decision" {
            $decision = [PSCustomObject]@{
                Decision = "allow"
                Explanation = "Allowed."
                Engine = "fallback"
                Fallback = $true
            }
            Set-PolicyDecisionCache -Key "test-key-1" -DecisionResult $decision | Out-Null
            $entry = Get-PolicyDecisionCache -Key "test-key-1"
            $entry | Should -Not -BeNullOrEmpty
            $entry.Decision | Should -Be "allow"
            $entry.Hit | Should -Be $true
        }
    }

    Context "Cache TTL" {
        It "Should expire entries after TTL elapses" {
            $decision = [PSCustomObject]@{
                Decision = "allow"
                Explanation = "Allowed."
                Engine = "fallback"
                Fallback = $true
            }
            Set-PolicyDecisionCache -Key "ttl-key" -DecisionResult $decision -TtlSeconds 1 | Out-Null
            Start-Sleep -Seconds 2
            $entry = Get-PolicyDecisionCache -Key "ttl-key"
            $entry | Should -BeNullOrEmpty
        }
    }

    Context "Test-PolicyDecisionCache" {
        It "Should return false for missing keys" {
            Test-PolicyDecisionCache -Key "missing-key" | Should -Be $false
        }

        It "Should return true for valid cached keys" {
            $decision = [PSCustomObject]@{
                Decision = "deny"
                Explanation = "Denied."
                Engine = "fallback"
                Fallback = $true
            }
            Set-PolicyDecisionCache -Key "valid-key" -DecisionResult $decision -TtlSeconds 60 | Out-Null
            Test-PolicyDecisionCache -Key "valid-key" | Should -Be $true
        }

        It "Should return false after entry expires" {
            $decision = [PSCustomObject]@{
                Decision = "deny"
                Explanation = "Denied."
                Engine = "fallback"
                Fallback = $true
            }
            Set-PolicyDecisionCache -Key "expiring-key" -DecisionResult $decision -TtlSeconds 1 | Out-Null
            Start-Sleep -Seconds 2
            Test-PolicyDecisionCache -Key "expiring-key" | Should -Be $false
        }
    }

    Context "Clear-PolicyDecisionCache" {
        It "Should clear all entries" {
            $decision = [PSCustomObject]@{
                Decision = "allow"
                Explanation = "Allowed."
                Engine = "fallback"
                Fallback = $true
            }
            Set-PolicyDecisionCache -Key "clear-key-1" -DecisionResult $decision | Out-Null
            Set-PolicyDecisionCache -Key "clear-key-2" -DecisionResult $decision | Out-Null
            $removed = Clear-PolicyDecisionCache
            $removed | Should -BeGreaterOrEqual 2
            Test-PolicyDecisionCache -Key "clear-key-1" | Should -Be $false
            Test-PolicyDecisionCache -Key "clear-key-2" | Should -Be $false
        }

        It "Should clear only expired entries when specified" {
            $decision = [PSCustomObject]@{
                Decision = "allow"
                Explanation = "Allowed."
                Engine = "fallback"
                Fallback = $true
            }
            Set-PolicyDecisionCache -Key "expired-key" -DecisionResult $decision -TtlSeconds 1 | Out-Null
            Start-Sleep -Seconds 2
            Set-PolicyDecisionCache -Key "fresh-key" -DecisionResult $decision -TtlSeconds 300 | Out-Null
            $removed = Clear-PolicyDecisionCache -ExpiredOnly
            $removed | Should -Be 1
            Test-PolicyDecisionCache -Key "expired-key" | Should -Be $false
            Test-PolicyDecisionCache -Key "fresh-key" | Should -Be $true
        }

        It "Should clear a specific key" {
            $decision = [PSCustomObject]@{
                Decision = "allow"
                Explanation = "Allowed."
                Engine = "fallback"
                Fallback = $true
            }
            Set-PolicyDecisionCache -Key "specific-key" -DecisionResult $decision | Out-Null
            $removed = Clear-PolicyDecisionCache -Key "specific-key"
            $removed | Should -Be 1
            Test-PolicyDecisionCache -Key "specific-key" | Should -Be $false
        }
    }

    Context "New-PolicyCacheKey" {
        It "Should generate deterministic keys" {
            $key1 = New-PolicyCacheKey -AdapterId "a1" -Domain "execution_mode" -InputObject @{ mode = "ci"; command = "build" }
            $key2 = New-PolicyCacheKey -AdapterId "a1" -Domain "execution_mode" -InputObject @{ mode = "ci"; command = "build" }
            $key1 | Should -Be $key2
        }

        It "Should generate different keys for different inputs" {
            $key1 = New-PolicyCacheKey -AdapterId "a1" -Domain "execution_mode" -InputObject @{ mode = "ci"; command = "build" }
            $key2 = New-PolicyCacheKey -AdapterId "a1" -Domain "execution_mode" -InputObject @{ mode = "ci"; command = "test" }
            $key1 | Should -Not -Be $key2
        }
    }
}
