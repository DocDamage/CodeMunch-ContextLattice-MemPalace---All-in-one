#requires -Version 5.1
<#
.SYNOPSIS
    MCP Governance Tests for LLM Workflow Platform

.DESCRIPTION
    Pester v5 test suite for MCP governance modules:
    - MCPToolRegistry.ps1: Tool registration, discovery, export/import
    - MCPToolLifecycle.ps1: Lifecycle transitions and deprecation

.NOTES
    File: MCPGovernance.Tests.ps1
    Version: 1.0.0
    Author: LLM Workflow Team
    Requires: Pester 5.0+
#>

BeforeAll {
    $script:ModuleRoot = Join-Path (Join-Path (Join-Path $PSScriptRoot "..") "module") "LLMWorkflow"
    $script:MCPModulePath = Join-Path $ModuleRoot "mcp"

    $registryPath = Join-Path $script:MCPModulePath "MCPToolRegistry.ps1"
    $lifecyclePath = Join-Path $script:MCPModulePath "MCPToolLifecycle.ps1"

    if (Test-Path $registryPath) { try { . $registryPath } catch { if ($_.Exception.Message -notlike "*Export-ModuleMember*") { throw } } }
    if (Test-Path $lifecyclePath) { try { . $lifecyclePath } catch { if ($_.Exception.Message -notlike "*Export-ModuleMember*") { throw } } }
}

Describe "MCPToolRegistry Module Tests" {
    BeforeEach {
        $script:registry = New-MCPToolRegistry
    }

    Context "New-MCPToolRegistry Function" {
        It "Should create an empty registry" {
            $script:registry | Should -Not -Be $null
            $script:registry.Count | Should -Be 0
            $script:registry -is [System.Collections.Hashtable] | Should -Be $true
        }
    }

    Context "Register-MCPTool Function" {
        It "Should register a tool with full metadata" {
            $tool = Register-MCPTool `
                -ToolId "search-retrieval" `
                -OwningPack "retrieval" `
                -SafetyLevel "read-only" `
                -Capability "search" `
                -ExecutionModeRequirements @("mcp-readonly", "interactive") `
                -IsMutating $false `
                -IsReadOnly $true `
                -ReviewRequired $false `
                -DependencyFootprint @("RetrievalBackendAdapter") `
                -TelemetryTags @("search", "retrieval") `
                -Version "1.0.0" `
                -Registry $script:registry

            $tool | Should -Not -BeNullOrEmpty
            $tool.toolId | Should -Be "search-retrieval"
            $tool.owningPack | Should -Be "retrieval"
            $tool.safetyLevel | Should -Be "read-only"
            $tool.capability | Should -Be "search"
            $tool.executionModeRequirements.Count | Should -Be 2
            $tool.executionModeRequirements | Should -Contain "mcp-readonly"
            $tool.isMutating | Should -Be $false
            $tool.isReadOnly | Should -Be $true
            $tool.dependencyFootprint | Should -Contain "RetrievalBackendAdapter"
            $tool.telemetryTags | Should -Contain "search"
            $tool.version | Should -Be "1.0.0"
            $tool.lifecycleState | Should -Be "draft"
            $tool.registeredAt | Should -Not -BeNullOrEmpty
        }

        It "Should reject read-only safety level for mutating tools" {
            { Register-MCPTool `
                -ToolId "bad-tool" `
                -OwningPack "test" `
                -SafetyLevel "read-only" `
                -Capability "ingest" `
                -IsMutating $true `
                -Registry $script:registry } | Should -Throw -ExpectedMessage "*SafetyLevel cannot be 'read-only' when IsMutating is true*"
        }

        It "Should update an existing tool on re-registration" {
            Register-MCPTool -ToolId "update-test" -OwningPack "test" -SafetyLevel "read-only" -Capability "search" -Version "1.0.0" -Registry $script:registry | Out-Null
            $updated = Register-MCPTool -ToolId "update-test" -OwningPack "test" -SafetyLevel "read-only" -Capability "search" -Version "1.1.0" -Registry $script:registry

            $updated.version | Should -Be "1.1.0"
            $script:registry.Count | Should -Be 1
        }
    }

    Context "Get-MCPTool Function" {
        It "Should retrieve a registered tool" {
            Register-MCPTool -ToolId "get-test" -OwningPack "test" -SafetyLevel "read-only" -Capability "search" -Registry $script:registry | Out-Null

            $result = Get-MCPTool -ToolId "get-test" -Registry $script:registry

            $result | Should -Not -BeNullOrEmpty
            $result.toolId | Should -Be "get-test"
        }

        It "Should return null for missing tool" {
            $result = Get-MCPTool -ToolId "missing" -Registry $script:registry
            $result | Should -BeNullOrEmpty
        }
    }

    Context "Find-MCPTools Function" {
        BeforeEach {
            Register-MCPTool -ToolId "tool-a" -OwningPack "pack-a" -SafetyLevel "read-only" -Capability "search" -Registry $script:registry | Out-Null
            Register-MCPTool -ToolId "tool-b" -OwningPack "pack-a" -SafetyLevel "mutating" -Capability "ingest" -Registry $script:registry | Out-Null
            Register-MCPTool -ToolId "tool-c" -OwningPack "pack-b" -SafetyLevel "read-only" -Capability "search" -Registry $script:registry | Out-Null
            Register-MCPTool -ToolId "tool-d" -OwningPack "pack-b" -SafetyLevel "destructive" -Capability "heal" -Deprecated $true -LifecycleState "deprecated" -Registry $script:registry | Out-Null
        }

        It "Should discover tools by capability" {
            $results = Find-MCPTools -Capability "search" -Registry $script:registry
            $results.Count | Should -Be 2
            $results.toolId | Should -Contain "tool-a"
            $results.toolId | Should -Contain "tool-c"
        }

        It "Should discover tools by pack" {
            $results = Find-MCPTools -OwningPack "pack-a" -Registry $script:registry
            $results.Count | Should -Be 2
            $results.toolId | Should -Contain "tool-a"
            $results.toolId | Should -Contain "tool-b"
        }

        It "Should discover tools by safety level" {
            $results = Find-MCPTools -SafetyLevel "mutating" -Registry $script:registry
            @($results).Count | Should -Be 1
            @($results)[0].toolId | Should -Be "tool-b"
        }

        It "Should exclude deprecated tools by default" {
            $results = Find-MCPTools -Registry $script:registry
            $results.toolId | Should -Not -Contain "tool-d"
        }

        It "Should include deprecated tools when requested" {
            $results = Find-MCPTools -IncludeDeprecated -Registry $script:registry
            $results.toolId | Should -Contain "tool-d"
            $results.Count | Should -Be 4
        }
    }

    Context "Export-MCPToolRegistry Function" {
        It "Should export registry to JSON" {
            Register-MCPTool -ToolId "export-test" -OwningPack "test" -SafetyLevel "read-only" -Capability "search" -Registry $script:registry | Out-Null

            $exportPath = Join-Path $TestDrive "mcp-registry.json"
            $result = Export-MCPToolRegistry -Path $exportPath -Registry $script:registry

            $result.Success | Should -Be $true
            $result.ToolCount | Should -Be 1
            Test-Path $exportPath | Should -Be $true

            $content = Get-Content -Path $exportPath -Raw | ConvertFrom-Json
            $content.schemaVersion | Should -Be 1
            $content.tools.Count | Should -Be 1
            $content.tools[0].toolId | Should -Be "export-test"
        }
    }

    Context "Import-MCPToolRegistry Function" {
        It "Should import registry from JSON" {
            $exportPath = Join-Path $TestDrive "mcp-registry.json"
            $importRegistry = New-MCPToolRegistry
            Register-MCPTool -ToolId "import-test" -OwningPack "test" -SafetyLevel "read-only" -Capability "search" -Version "1.0.0" -Registry $importRegistry | Out-Null
            Export-MCPToolRegistry -Path $exportPath -Registry $importRegistry | Out-Null

            $newRegistry = New-MCPToolRegistry
            $result = Import-MCPToolRegistry -Path $exportPath -Merge:$false -Registry $newRegistry

            $result.Success | Should -Be $true
            $result.ImportedCount | Should -Be 1
            $script:MCPToolRegistry["import-test"] | Should -Not -BeNullOrEmpty
        }

        It "Should merge imported tools with existing registry" {
            $exportPath = Join-Path $TestDrive "mcp-registry-merge.json"
            Register-MCPTool -ToolId "existing" -OwningPack "test" -SafetyLevel "read-only" -Capability "search" -Registry $script:registry | Out-Null
            Export-MCPToolRegistry -Path $exportPath -Registry $script:registry | Out-Null

            $script:registry.Clear()
            Register-MCPTool -ToolId "new-tool" -OwningPack "test" -SafetyLevel "mutating" -Capability "ingest" -Registry $script:registry | Out-Null

            $result = Import-MCPToolRegistry -Path $exportPath -Merge:$true -Registry $script:registry

            $result.TotalCount | Should -Be 2
            $script:registry["existing"] | Should -Not -BeNullOrEmpty
            $script:registry["new-tool"] | Should -Not -BeNullOrEmpty
        }
    }
}

Describe "MCPToolLifecycle Module Tests" {
    BeforeEach {
        $script:registry = New-MCPToolRegistry
        Register-MCPTool -ToolId "lifecycle-test" -OwningPack "test" -SafetyLevel "read-only" -Capability "search" -LifecycleState "draft" -Registry $script:registry | Out-Null
    }

    Context "Test-MCPToolLifecycleTransition Function" {
        It "Should allow valid transitions" {
            (Test-MCPToolLifecycleTransition -FromState "draft" -ToState "experimental").IsValid | Should -Be $true
            (Test-MCPToolLifecycleTransition -FromState "experimental" -ToState "stable").IsValid | Should -Be $true
            (Test-MCPToolLifecycleTransition -FromState "stable" -ToState "deprecated").IsValid | Should -Be $true
            (Test-MCPToolLifecycleTransition -FromState "deprecated" -ToState "retired").IsValid | Should -Be $true
            (Test-MCPToolLifecycleTransition -FromState "deprecated" -ToState "stable").IsValid | Should -Be $true
        }

        It "Should deny invalid transitions" {
            (Test-MCPToolLifecycleTransition -FromState "retired" -ToState "stable").IsValid | Should -Be $false
            (Test-MCPToolLifecycleTransition -FromState "stable" -ToState "experimental").IsValid | Should -Be $false
            (Test-MCPToolLifecycleTransition -FromState "draft" -ToState "stable").IsValid | Should -Be $false
        }

        It "Should allow same-state as valid" {
            (Test-MCPToolLifecycleTransition -FromState "stable" -ToState "stable").IsValid | Should -Be $true
        }
    }

    Context "Set-MCPToolLifecycleState Function" {
        It "Should transition a tool between allowed states" {
            $result = Set-MCPToolLifecycleState -ToolId "lifecycle-test" -State "experimental" -Registry $script:registry

            $result.Success | Should -Be $true
            $result.PreviousState | Should -Be "draft"
            $result.NewState | Should -Be "experimental"

            $tool = Get-MCPTool -ToolId "lifecycle-test" -Registry $script:registry
            $tool.lifecycleState | Should -Be "experimental"
        }

        It "Should throw on invalid transitions" {
            { Set-MCPToolLifecycleState -ToolId "lifecycle-test" -State "stable" -Registry $script:registry } |
                Should -Throw -ExpectedMessage "*Invalid lifecycle transition*"
        }

        It "Should set deprecation fields when transitioning to deprecated" {
            Set-MCPToolLifecycleState -ToolId "lifecycle-test" -State "experimental" -Registry $script:registry | Out-Null
            Set-MCPToolLifecycleState -ToolId "lifecycle-test" -State "stable" -Registry $script:registry | Out-Null

            $result = Set-MCPToolLifecycleState -ToolId "lifecycle-test" -State "deprecated" `
                -DeprecationNotice "Use new-search instead." -ReplacedBy "new-search" -Registry $script:registry

            $result.Success | Should -Be $true

            $tool = Get-MCPTool -ToolId "lifecycle-test" -Registry $script:registry
            $tool.deprecated | Should -Be $true
            $tool.deprecationNotice | Should -Be "Use new-search instead."
            $tool.replacedBy | Should -Be "new-search"
        }

        It "Should clear deprecation when reversing to stable" {
            Set-MCPToolLifecycleState -ToolId "lifecycle-test" -State "experimental" -Registry $script:registry | Out-Null
            Set-MCPToolLifecycleState -ToolId "lifecycle-test" -State "stable" -Registry $script:registry | Out-Null
            Set-MCPToolLifecycleState -ToolId "lifecycle-test" -State "deprecated" -Registry $script:registry | Out-Null

            $result = Set-MCPToolLifecycleState -ToolId "lifecycle-test" -State "stable" -Registry $script:registry

            $result.Success | Should -Be $true
            $tool = Get-MCPTool -ToolId "lifecycle-test" -Registry $script:registry
            $tool.deprecated | Should -Be $false
        }
    }

    Context "Get-MCPToolDeprecationNotice Function" {
        It "Should return deprecation info for deprecated tools" {
            Set-MCPToolLifecycleState -ToolId "lifecycle-test" -State "experimental" -Registry $script:registry | Out-Null
            Set-MCPToolLifecycleState -ToolId "lifecycle-test" -State "stable" -Registry $script:registry | Out-Null
            Set-MCPToolLifecycleState -ToolId "lifecycle-test" -State "deprecated" -DeprecationNotice "Old tool." -ReplacedBy "new-tool" -Registry $script:registry | Out-Null

            $notice = Get-MCPToolDeprecationNotice -ToolId "lifecycle-test" -Registry $script:registry

            $notice | Should -Not -BeNullOrEmpty
            $notice.toolId | Should -Be "lifecycle-test"
            $notice.deprecated | Should -Be $true
            $notice.message | Should -Be "Old tool."
            $notice.replacedBy | Should -Be "new-tool"
        }

        It "Should return null for active tools" {
            $notice = Get-MCPToolDeprecationNotice -ToolId "lifecycle-test" -Registry $script:registry
            $notice | Should -BeNullOrEmpty
        }
    }

    Context "Deprecated Tool Visibility" {
        It "Should remain discoverable when deprecated" {
            Set-MCPToolLifecycleState -ToolId "lifecycle-test" -State "experimental" -Registry $script:registry | Out-Null
            Set-MCPToolLifecycleState -ToolId "lifecycle-test" -State "stable" -Registry $script:registry | Out-Null
            Set-MCPToolLifecycleState -ToolId "lifecycle-test" -State "deprecated" -Registry $script:registry | Out-Null

            $found = Find-MCPTools -IncludeDeprecated -Registry $script:registry
            $found.toolId | Should -Contain "lifecycle-test"
        }
    }

    Context "Invoke-MCPToolRegistrySync Function" {
        It "Should sync registry with canonical source" {
            $syncPath = Join-Path $TestDrive "mcp-sync.json"
            $syncRegistry = New-MCPToolRegistry
            Register-MCPTool -ToolId "sync-a" -OwningPack "test" -SafetyLevel "read-only" -Capability "search" -Registry $syncRegistry | Out-Null
            Export-MCPToolRegistry -Path $syncPath -Registry $syncRegistry | Out-Null

            $newRegistry = New-MCPToolRegistry
            Register-MCPTool -ToolId "sync-b" -OwningPack "test" -SafetyLevel "mutating" -Capability "ingest" -Registry $newRegistry | Out-Null

            $result = Invoke-MCPToolRegistrySync -Path $syncPath -Registry $newRegistry

            $result.Success | Should -Be $true
            $result.MergedCount | Should -Be 1
            $result.TotalCount | Should -Be 2
        }

        It "Should remove expired retired tools" {
            $syncPath = Join-Path $TestDrive "mcp-sync-expired.json"
            $expiredRegistry = New-MCPToolRegistry
            Register-MCPTool -ToolId "old-retired" -OwningPack "test" -SafetyLevel "read-only" -Capability "search" -LifecycleState "retired" -Registry $expiredRegistry | Out-Null

            # Manually set updatedAt to older than default retention
            $tool = $expiredRegistry["old-retired"]
            $tool.updatedAt = [DateTime]::UtcNow.AddDays(-200).ToString("yyyy-MM-ddTHH:mm:ssZ", [System.Globalization.CultureInfo]::InvariantCulture)
            $expiredRegistry["old-retired"] = $tool

            Export-MCPToolRegistry -Path $syncPath -Registry $expiredRegistry | Out-Null

            $result = Invoke-MCPToolRegistrySync -Path $syncPath -RemoveExpired -Registry $expiredRegistry

            $result.RemovedCount | Should -Be 1
            $result.TotalCount | Should -Be 0
        }
    }
}
