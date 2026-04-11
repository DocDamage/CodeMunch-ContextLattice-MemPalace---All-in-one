# Changelog

All notable changes to this project will be documented in this file.

The format is based on Keep a Changelog and this project follows Semantic Versioning.

## [Unreleased]

### Added
- TODO

## [0.2.0] - 2026-04-11

### Added
- New module commands:
  - `Get-LLMWorkflowVersion`
  - `Update-LLMWorkflow` (GitHub release download + SHA256 verification)
  - `Test-LLMWorkflowSetup`
  - aliases: `llmver`, `llmupdate`, `llmcheck`
- `compatibility.lock.json` with pinned tested refs for CodeMunch/ContextLattice/MemPalace.
- Compatibility lock validation CI gate (`tools/ci/validate-compatibility-lock.ps1`).
- Mock ContextLattice integration harness with Pester integration tests.
- Release hardening:
  - optional Authenticode signing in release workflow
  - signing report artifact
- New automation workflows:
  - PowerShell Gallery publish
  - supply-chain workflow (dependency review, SBOM, pip-audit)

## [0.1.0] - 2026-04-11

### Added
- Canonical all-in-one toolkit for CodeMunch Pro, ContextLattice, and MemPalace.
- Global one-shot bootstrap command (`llm-workflow-up`, `llmup`).
- Versioned PowerShell module (`LLMWorkflow`) with:
  - `Install-LLMWorkflow`
  - `Invoke-LLMWorkflowUp`
  - `llmup` alias
