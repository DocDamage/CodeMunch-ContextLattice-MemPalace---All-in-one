#requires -Version 5.1
<#
.SYNOPSIS
    Retrieval Backend Adapter Tests for LLM Workflow Platform

.DESCRIPTION
    Pester v5 test suite for the RetrievalBackendAdapter module:
    - Adapter creation for Qdrant and LanceDB
    - Document add, search, and remove operations
    - Connection testing

.NOTES
    File: RetrievalBackend.Tests.ps1
    Version: 1.0.0
    Author: LLM Workflow Team
    Requires: Pester 5.0+
#>

BeforeAll {
    $script:ModuleRoot = Join-Path (Join-Path (Join-Path $PSScriptRoot "..") "module") "LLMWorkflow"
    $script:RetrievalModulePath = Join-Path $ModuleRoot "retrieval"

    $adapterPath = Join-Path $script:RetrievalModulePath "RetrievalBackendAdapter.ps1"
    if (Test-Path $adapterPath) { . $adapterPath }
}

Describe "RetrievalBackendAdapter Module Tests" {
    BeforeAll {
        $script:LanceDbTestPath = Join-Path $TestDrive "lancedb-test"
    }

    Context "New-RetrievalBackendAdapter Function" {
        It "Should create a Qdrant adapter" {
            $adapter = New-RetrievalBackendAdapter -Backend "qdrant" -Collection "test-pack"

            $adapter | Should -Not -BeNullOrEmpty
            $adapter.backend | Should -Be "qdrant"
            $adapter.collection | Should -Be "test-pack"
            $adapter.baseUrl | Should -Be "http://localhost:6333"
            $adapter.adapterId | Should -Not -BeNullOrEmpty
        }

        It "Should create a LanceDB adapter" {
            $adapter = New-RetrievalBackendAdapter -Backend "lancedb" -Collection "test-pack" -DataPath $script:LanceDbTestPath

            $adapter | Should -Not -BeNullOrEmpty
            $adapter.backend | Should -Be "lancedb"
            $adapter.collection | Should -Be "test-pack"
            $adapter.dataPath | Should -Be $script:LanceDbTestPath
            $adapter.adapterId | Should -Not -BeNullOrEmpty
        }

        It "Should use custom base URL for Qdrant" {
            $adapter = New-RetrievalBackendAdapter -Backend "qdrant" -Collection "test-pack" -BaseUrl "http://qdrant:6333"
            $adapter.baseUrl | Should -Be "http://qdrant:6333"
        }

        It "Should default LanceDB data path when not provided" {
            $adapter = New-RetrievalBackendAdapter -Backend "lancedb" -Collection "test-pack"
            $adapter.dataPath | Should -Not -BeNullOrEmpty
        }
    }

    Context "Test-RetrievalBackendConnection Function" {
        It "Should report Qdrant as reachable (mock)" {
            $adapter = New-RetrievalBackendAdapter -Backend "qdrant" -Collection "test-pack"
            $result = Test-RetrievalBackendConnection -Adapter $adapter

            $result.Success | Should -Be $true
            $result.Reachable | Should -Be $true
            $result.Backend | Should -Be "qdrant"
            $result.MockHealthCheck.status | Should -Be "ok"
        }

        It "Should verify LanceDB data path is writable" {
            $adapter = New-RetrievalBackendAdapter -Backend "lancedb" -Collection "test-pack" -DataPath $script:LanceDbTestPath
            $result = Test-RetrievalBackendConnection -Adapter $adapter

            $result.Success | Should -Be $true
            $result.Reachable | Should -Be $true
            $result.Backend | Should -Be "lancedb"
            Test-Path $script:LanceDbTestPath | Should -Be $true
        }
    }

    Context "Add-RetrievalDocument Function" {
        It "Should return mock success for Qdrant" {
            $adapter = New-RetrievalBackendAdapter -Backend "qdrant" -Collection "test-pack"
            $result = Add-RetrievalDocument -Adapter $adapter -DocumentId "doc-1" -Vector @(0.1, 0.2, 0.3) -Payload @{ text = "hello" }

            $result.Success | Should -Be $true
            $result.DocumentId | Should -Be "doc-1"
            $result.mockResponse.status | Should -Be "ok"
            $result.mockResponse.operation | Should -Be "upsert"
        }

        It "Should persist document for LanceDB" {
            $adapter = New-RetrievalBackendAdapter -Backend "lancedb" -Collection "test-pack" -DataPath $script:LanceDbTestPath
            $result = Add-RetrievalDocument -Adapter $adapter -DocumentId "doc-lance-1" -Vector @(0.1, 0.2, 0.3) -Payload @{ packId = "test-pack"; text = "hello lance" }

            $result.Success | Should -Be $true
            Test-Path $result.TableFile | Should -Be $true
        }
    }

    Context "Search-RetrievalBackend Function" {
        It "Should return mock search result for Qdrant" {
            $adapter = New-RetrievalBackendAdapter -Backend "qdrant" -Collection "test-pack"
            $result = Search-RetrievalBackend -Adapter $adapter -Vector @(0.1, 0.2, 0.3) -Limit 5

            $result.Success | Should -Be $true
            $result.Backend | Should -Be "qdrant"
            $result.mockResponse.status | Should -Be "ok"
            $result.mockResponse.operation | Should -Be "search"
        }

        It "Should search documents for LanceDB" {
            $adapter = New-RetrievalBackendAdapter -Backend "lancedb" -Collection "search-test" -DataPath $script:LanceDbTestPath
            Add-RetrievalDocument -Adapter $adapter -DocumentId "doc-1" -Vector @(1.0, 0.0, 0.0) -Payload @{ packId = "pack-a"; text = "alpha" } | Out-Null
            Add-RetrievalDocument -Adapter $adapter -DocumentId "doc-2" -Vector @(0.0, 1.0, 0.0) -Payload @{ packId = "pack-b"; text = "beta" } | Out-Null
            Add-RetrievalDocument -Adapter $adapter -DocumentId "doc-3" -Vector @(0.9, 0.1, 0.0) -Payload @{ packId = "pack-a"; text = "gamma" } | Out-Null

            $result = Search-RetrievalBackend -Adapter $adapter -Vector @(1.0, 0.0, 0.0) -Filter @{ packId = "pack-a" } -Limit 2

            $result.Success | Should -Be $true
            $result.Results.Count | Should -Be 2
            $result.Results[0].id | Should -Be "doc-1"
            $result.Results[0].score | Should -BeGreaterThan 0.99
        }

        It "Should apply filters correctly for LanceDB" {
            $adapter = New-RetrievalBackendAdapter -Backend "lancedb" -Collection "filter-test" -DataPath $script:LanceDbTestPath
            Add-RetrievalDocument -Adapter $adapter -DocumentId "f-1" -Vector @(1.0, 0.0) -Payload @{ category = "code"; lang = "powershell" } | Out-Null
            Add-RetrievalDocument -Adapter $adapter -DocumentId "f-2" -Vector @(0.0, 1.0) -Payload @{ category = "doc"; lang = "markdown" } | Out-Null

            $result = Search-RetrievalBackend -Adapter $adapter -Vector @(1.0, 0.0) -Filter @{ category = "doc" } -Limit 5

            $result.Success | Should -Be $true
            $result.Results.Count | Should -Be 1
            $result.Results[0].id | Should -Be "f-2"
        }
    }

    Context "Remove-RetrievalDocument Function" {
        It "Should return mock success for Qdrant" {
            $adapter = New-RetrievalBackendAdapter -Backend "qdrant" -Collection "test-pack"
            $result = Remove-RetrievalDocument -Adapter $adapter -DocumentId "doc-1"

            $result.Success | Should -Be $true
            $result.DocumentId | Should -Be "doc-1"
            $result.mockResponse.status | Should -Be "ok"
            $result.mockResponse.operation | Should -Be "delete"
        }

        It "Should remove document from LanceDB" {
            $adapter = New-RetrievalBackendAdapter -Backend "lancedb" -Collection "remove-test" -DataPath $script:LanceDbTestPath
            Add-RetrievalDocument -Adapter $adapter -DocumentId "r-1" -Vector @(1.0, 0.0) -Payload @{ text = "remove me" } | Out-Null
            Add-RetrievalDocument -Adapter $adapter -DocumentId "r-2" -Vector @(0.0, 1.0) -Payload @{ text = "keep me" } | Out-Null

            $result = Remove-RetrievalDocument -Adapter $adapter -DocumentId "r-1"

            $result.Success | Should -Be $true
            $result.Removed | Should -Be $true

            $search = Search-RetrievalBackend -Adapter $adapter -Vector @(1.0, 0.0) -Limit 10
            $search.Results.id | Should -Not -Contain "r-1"
            $search.Results.id | Should -Contain "r-2"
        }

        It "Should handle removing non-existent LanceDB document gracefully" {
            $adapter = New-RetrievalBackendAdapter -Backend "lancedb" -Collection "remove-empty" -DataPath $script:LanceDbTestPath
            $result = Remove-RetrievalDocument -Adapter $adapter -DocumentId "no-such-doc"

            $result.Success | Should -Be $true
            $result.Removed | Should -Be $false
        }
    }

    Context "Cosine Similarity Helper" {
        It "Should compute identical vectors with score 1.0" {
            $score = Get-CosineSimilarity -VectorA @(1.0, 0.0, 0.0) -VectorB @(1.0, 0.0, 0.0)
            $score | Should -Be 1.0
        }

        It "Should compute orthogonal vectors with score 0.0" {
            $score = Get-CosineSimilarity -VectorA @(1.0, 0.0) -VectorB @(0.0, 1.0)
            $score | Should -Be 0.0
        }

        It "Should return 0.0 for mismatched dimensions" {
            $score = Get-CosineSimilarity -VectorA @(1.0, 0.0) -VectorB @(1.0, 0.0, 0.0)
            $score | Should -Be 0.0
        }
    }
}
