# Changelog

All notable changes to this project will be documented in this file.

The format is based on Keep a Changelog and this project follows Semantic Versioning.

## [Unreleased]

### Added
- GitHub Actions CI smoke and Pester test workflow.
- Pester suite for module exports, bootstrap behavior, env loading, and profile idempotency.
- Versioned PowerShell module install/update flow.

## [0.1.0] - 2026-04-11

### Added
- Canonical all-in-one toolkit for CodeMunch Pro, ContextLattice, and MemPalace.
- Global one-shot bootstrap command (`llm-workflow-up`, `llmup`).
- Versioned PowerShell module (`LLMWorkflow`) with:
  - `Install-LLMWorkflow`
  - `Invoke-LLMWorkflowUp`
  - `llmup` alias

