# Security Baseline Pipeline

This document describes the **Workstream 5** security baseline for the LLM Workflow platform. The baseline runs secret scanning, SBOM generation, and vulnerability scanning without requiring external security tools to be installed.

## Related Docs
- [Post-0.9.6 Strategic Execution Plan](../implementation/LLMWorkflow_Post_0.9.6_Strategic_Execution_Plan.md)
- [Implementation Progress](../implementation/PROGRESS.md)
- [Remaining Work](../implementation/REMAINING_WORK.md)
- [Supply-Chain Policy](../reference/SUPPLY_CHAIN_POLICY.md)

## Table of Contents

- [Overview](#overview)
- [Tools and Equivalents](#tools-and-equivalents)
- [Pipeline Steps](#pipeline-steps)
- [Running the Baseline](#running-the-baseline)
- [Interpreting Findings](#interpreting-findings)
- [Report Outputs](#report-outputs)
- [CI/CD Integration](#cicd-integration)

---

## Overview

The security baseline ensures that every release candidate is scanned for:

1. **Secrets and sensitive data** (API keys, tokens, private keys, PII)
2. **Software Bill of Materials (SBOM)** for supply-chain transparency
3. **Vulnerable patterns** in Docker, Compose, and PowerShell artifacts

All scans are implemented as PowerShell 5.1-compatible scripts under `scripts/security/`. They simulate the behavior of industry-standard tools so the pipeline can run anywhere, including environments where those tools are not installed.

---

## Tools and Equivalents

| Industry Tool | LLM Workflow Equivalent | Purpose |
|---------------|------------------------|---------|
| **TruffleHog** | `Invoke-SecretScan.ps1` | Regex-based secret detection |
| **Syft** | `Invoke-SBOMBuild.ps1` | CycloneDX-compatible SBOM generation |
| **Semgrep** | `Invoke-VulnerabilityScan.ps1` (code rules) | Detects risky code patterns |
| **Trivy** | `Invoke-VulnerabilityScan.ps1` (config rules) | Detects misconfigurations in Docker and Compose files |

> **Note:** The wrappers are designed to be drop-in replacements for local/CI use. If the real tools are installed, you can wire them in later without changing the pipeline interface.

---

## Pipeline Steps

The orchestrator script `Invoke-SecurityBaseline.ps1` runs the following steps in order:

```text
1. Secret Scan     -> Invoke-SecretScan.ps1
2. SBOM Build      -> Invoke-SBOMBuild.ps1
3. Vulnerability Scan -> Invoke-VulnerabilityScan.ps1
4. Promotion Gate  -> Test-PromotionGate (embedded in baseline)
5. Consolidated Report -> security-baseline-<timestamp>.json
```

### Step 1: Secret Scan

Scans text-based files for patterns matching:

- OpenAI, Anthropic, and AWS API keys
- Bearer tokens and JWTs
- SQL, MongoDB, and Redis connection strings
- RSA/SSH/PEM private keys
- Credit card numbers and SSNs
- Hardcoded passwords

### Step 2: SBOM Build

Discovers and catalogs:

- PowerShell modules (`.psd1` manifests)
- JSON configuration files
- Dockerfiles and docker-compose files
- PowerShell scripts (`.ps1`)

Outputs a **CycloneDX 1.5** JSON document with component metadata, PURLs, and properties.

### Step 3: Vulnerability Scan

Checks for misconfigurations and risky patterns:

- `:latest` tags and `USER root` in Dockerfiles
- Missing `HEALTHCHECK` in Dockerfiles
- `privileged: true` and `network_mode: host` in docker-compose
- `Invoke-Expression`, remote downloads, and weak TLS in PowerShell
- Hardcoded credentials in config files

### Step 4: Promotion Gate

Compares scan summaries against thresholds:

- **Default:** zero critical and zero high findings allowed
- If thresholds are exceeded, `promotionGate.Passed` is `false` and `BlockedBy` lists the reasons

### Step 5: Consolidated Report

A single JSON file is produced containing:

- Timestamps and paths
- Overall pass/fail status
- Per-scan summaries
- Promotion gate result

---

## Running the Baseline

### Full Baseline

```powershell
# Run all scans with default settings
.\scripts\security\Invoke-SecurityBaseline.ps1
Invoke-SecurityBaseline -ProjectRoot . -OutputPath ./security-reports

# Fail if any critical finding is found
Invoke-SecurityBaseline -ProjectRoot . -OutputPath ./security-reports -FailOnCritical
```

### Individual Scans

```powershell
# Secret scan only
.\scripts\security\Invoke-SecretScan.ps1
Invoke-SecretScan -ProjectRoot . -OutputPath ./secret-scan-results.json

# SBOM only
.\scripts\security\Invoke-SBOMBuild.ps1
Invoke-SBOMBuild -ProjectRoot . -OutputPath ./sbom.json

# Vulnerability scan only
.\scripts\security\Invoke-VulnerabilityScan.ps1
Invoke-VulnerabilityScan -ProjectRoot . -OutputPath ./vuln-scan-results.json
```

---

## Interpreting Findings

### Severity Levels

| Severity | Meaning | Action |
|----------|---------|--------|
| **Critical** | Secret or vulnerability that poses immediate risk | Block promotion; fix before release |
| **High** | Significant misconfiguration or dangerous pattern | Block promotion by default; fix promptly |
| **Medium** | Notable issue that should be tracked | Address in next sprint |
| **Low** | Minor hygiene issue | Track and fix when convenient |

### Common Findings

| Finding | Likely Cause | Fix |
|---------|--------------|-----|
| `OpenAI_API_Key` | Hardcoded API key in script or config | Move to environment variables or secret vault |
| `Dockerfile_Latest_Tag` | `FROM node:latest` | Pin to a specific digest or version tag |
| `PowerShell_InvokeExpression` | Dynamic script execution | Replace with parameterized calls |
| `DockerCompose_Privileged` | Container needs host access | Drop privileges and use capabilities instead |

---

## Report Outputs

All reports are written as UTF-8 JSON files.

| Report | File Name Pattern |
|--------|-------------------|
| Secret Scan | `secret-scan-<timestamp>.json` |
| Vulnerability Scan | `vulnerability-scan-<timestamp>.json` |
| SBOM | `sbom-<timestamp>.json` |
| Consolidated Baseline | `security-baseline-<timestamp>.json` |

### Consolidated Report Structure

```json
{
  "timestamp": "2026-04-13T10:48:09Z",
  "projectRoot": "F:\\...\\CodeMunch-ContextLattice-MemPalace---All-in-one",
  "outputDirectory": "F:\\...\\security-reports",
  "overallPassed": true,
  "promotionGate": {
    "Passed": true,
    "BlockedBy": [],
    "Thresholds": {
      "MaxAllowedCritical": 0,
      "MaxAllowedHigh": 0
    },
    "SecretScan": { "Critical": 0, "High": 0 },
    "VulnerabilityScan": { "Critical": 0, "High": 0 }
  },
  "scans": {
    "secretScan": { "reportPath": "...", "summary": { ... } },
    "sbom": { "outputPath": "...", "componentCount": 42, "success": true },
    "vulnerabilityScan": { "reportPath": "...", "summary": { ... } }
  }
}
```

---

## CI/CD Integration

The baseline can be invoked as a single step in a CI pipeline:

```powershell
# Example Azure DevOps / GitHub Actions step
- task: PowerShell@2
  inputs:
    targetType: 'inline'
    script: |
      .\scripts\security\Invoke-SecurityBaseline.ps1
      Invoke-SecurityBaseline `
        -ProjectRoot $(Build.SourcesDirectory) `
        -OutputPath $(Build.ArtifactStagingDirectory)\security-reports `
        -FailOnCritical
  displayName: 'Run Security Baseline'
```

If `-FailOnCritical` is used, the step will fail and block downstream stages when critical findings are present.

---

## See Also

- [SUPPLY_CHAIN_POLICY.md](../../docs/reference/SUPPLY_CHAIN_POLICY.md)
- `scripts/security/Invoke-SecurityBaseline.ps1`
- `scripts/security/Invoke-SecretScan.ps1`
- `scripts/security/Invoke-SBOMBuild.ps1`
- `scripts/security/Invoke-VulnerabilityScan.ps1`
