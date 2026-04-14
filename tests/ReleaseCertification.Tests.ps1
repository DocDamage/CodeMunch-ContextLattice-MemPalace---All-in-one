#requires -Version 5.1
<#
.SYNOPSIS
    Release certification tests for LLMWorkflow v1.0 readiness.

.DESCRIPTION
    Pester v5 test suite that certifies release readiness by verifying the
    existence of required files, modules, scripts, and documentation.

    Tests are organized by the categories defined in
    docs/V1_RELEASE_CRITERIA.md and docs/RELEASE_CERTIFICATION_CHECKLIST.md.

.NOTES
    File: ReleaseCertification.Tests.ps1
    Version: 1.0.0
    Author: LLM Workflow Team
    Requires: Pester 5.0+
#>

BeforeAll {
    $script:ProjectRoot = Join-Path (Join-Path $PSScriptRoot "..") ""
    $script:ModuleRoot = Join-Path $script:ProjectRoot "module\LLMWorkflow"
    $script:DocsRoot = Join-Path $script:ProjectRoot "docs"
    $script:ScriptsRoot = Join-Path $script:ProjectRoot "scripts"
    $script:PolicyRoot = Join-Path $script:ProjectRoot "policy"
    $script:CiRoot = Join-Path $script:ProjectRoot "tools\ci"
}

Describe "Documentation Truth" {
    It "VERSION file exists and is not empty" {
        $versionPath = Join-Path $script:ProjectRoot "VERSION"
        Test-Path -LiteralPath $versionPath | Should -Be $true
        $content = Get-Content -LiteralPath $versionPath -Raw
        $content | Should -Not -BeNullOrEmpty
        $content.Trim() | Should -Not -Be ''
    }

    It "RELEASE_STATE.md exists" {
        $path = Join-Path $script:DocsRoot "RELEASE_STATE.md"
        Test-Path -LiteralPath $path | Should -Be $true
    }

    It "DOCS_TRUTH_MATRIX.md exists" {
        $path = Join-Path $script:DocsRoot "DOCS_TRUTH_MATRIX.md"
        Test-Path -LiteralPath $path | Should -Be $true
    }

    It "All required documentation files exist" {
        $requiredDocs = @(
            'V1_RELEASE_CRITERIA.md',
            'RELEASE_CERTIFICATION_CHECKLIST.md',
            'RELEASE_STATE.md',
            'DOCS_TRUTH_MATRIX.md',
            'DOCUMENT_INGESTION_MODEL.md',
            'GAME_ASSET_INGESTION_MODEL.md',
            'SECURITY_BASELINE.md',
            'SUPPLY_CHAIN_POLICY.md',
            'POLICY_RUNTIME_MODEL.md',
            'OBSERVABILITY_ARCHITECTURE.md',
            'EVALUATION_OPERATIONS.md',
            'SELF_HEALING.md'
        )

        foreach ($doc in $requiredDocs) {
            $path = Join-Path $script:DocsRoot $doc
            Test-Path -LiteralPath $path | Should -Be $true -Because "$doc should exist"
        }
    }
}

Describe "Observability" {
    It "SpanFactory.ps1 exists" {
        $path = Join-Path $script:ModuleRoot "telemetry\SpanFactory.ps1"
        Test-Path -LiteralPath $path | Should -Be $true
    }

    It "TraceEnvelope.ps1 exists" {
        $path = Join-Path $script:ModuleRoot "telemetry\TraceEnvelope.ps1"
        Test-Path -LiteralPath $path | Should -Be $true
    }

    It "OpenTelemetryBridge.ps1 exists" {
        $path = Join-Path $script:ModuleRoot "telemetry\OpenTelemetryBridge.ps1"
        Test-Path -LiteralPath $path | Should -Be $true
    }
}

Describe "Policy" {
    It "PolicyAdapter.ps1 exists" {
        $path = Join-Path $script:ModuleRoot "policy\PolicyAdapter.ps1"
        Test-Path -LiteralPath $path | Should -Be $true
    }

    It "At least one OPA rego file exists" {
        $opaPath = Join-Path $script:PolicyRoot "opa"
        if (Test-Path -LiteralPath $opaPath) {
            $regoFiles = Get-ChildItem -Path $opaPath -Filter "*.rego" -ErrorAction SilentlyContinue
            # Guard against PS 5.1 single-item array unwrapping
            $regoList = @($regoFiles)
            $regoList.Count | Should -BeGreaterThan 0
        }
        else {
            throw "OPA policy directory not found: $opaPath"
        }
    }
}

Describe "Document Ingestion" {
    It "DoclingAdapter.ps1 exists" {
        $path = Join-Path $script:ModuleRoot "ingestion\DoclingAdapter.ps1"
        Test-Path -LiteralPath $path | Should -Be $true
    }

    It "TikaAdapter.ps1 exists" {
        $path = Join-Path $script:ModuleRoot "ingestion\TikaAdapter.ps1"
        Test-Path -LiteralPath $path | Should -Be $true
    }

    It "DocumentNormalizer.ps1 exists" {
        $path = Join-Path $script:ModuleRoot "ingestion\DocumentNormalizer.ps1"
        Test-Path -LiteralPath $path | Should -Be $true
    }
}

Describe "Game Asset Ingestion" {
    It "SpriteSheetParser.ps1 exists" {
        $path = Join-Path $script:ModuleRoot "extraction\SpriteSheetParser.ps1"
        Test-Path -LiteralPath $path | Should -Be $true
    }

    It "MarketplaceProvenanceNormalizer.ps1 exists" {
        $path = Join-Path $script:ModuleRoot "ingestion\MarketplaceProvenanceNormalizer.ps1"
        Test-Path -LiteralPath $path | Should -Be $true
    }
}

Describe "Security Baseline" {
    It "Invoke-SecurityBaseline.ps1 exists" {
        $path = Join-Path $script:ScriptsRoot "security\Invoke-SecurityBaseline.ps1"
        Test-Path -LiteralPath $path | Should -Be $true
    }

    It "Invoke-SBOMBuild.ps1 exists" {
        $path = Join-Path $script:ScriptsRoot "security\Invoke-SBOMBuild.ps1"
        Test-Path -LiteralPath $path | Should -Be $true
    }

    It "Invoke-SecretScan.ps1 exists" {
        $path = Join-Path $script:ScriptsRoot "security\Invoke-SecretScan.ps1"
        Test-Path -LiteralPath $path | Should -Be $true
    }

    It "Invoke-VulnerabilityScan.ps1 exists" {
        $path = Join-Path $script:ScriptsRoot "security\Invoke-VulnerabilityScan.ps1"
        Test-Path -LiteralPath $path | Should -Be $true
    }
}

Describe "Durable Execution" {
    It "DurableOrchestrator.ps1 exists" {
        $path = Join-Path $script:ModuleRoot "workflow\DurableOrchestrator.ps1"
        Test-Path -LiteralPath $path | Should -Be $true
    }
}

Describe "MCP Governance" {
    It "MCPToolRegistry.ps1 exists" {
        $path = Join-Path $script:ModuleRoot "mcp\MCPToolRegistry.ps1"
        Test-Path -LiteralPath $path | Should -Be $true
    }

    It "MCPToolLifecycle.ps1 exists" {
        $path = Join-Path $script:ModuleRoot "mcp\MCPToolLifecycle.ps1"
        Test-Path -LiteralPath $path | Should -Be $true
    }
}

Describe "Retrieval Backend" {
    It "RetrievalBackendAdapter.ps1 exists" {
        $path = Join-Path $script:ModuleRoot "retrieval\RetrievalBackendAdapter.ps1"
        Test-Path -LiteralPath $path | Should -Be $true
    }
}

Describe "CI Validation" {
    It "CI validation script exists" {
        $path = Join-Path $script:CiRoot "validate-docs-truth.ps1"
        Test-Path -LiteralPath $path | Should -Be $true
    }
}
