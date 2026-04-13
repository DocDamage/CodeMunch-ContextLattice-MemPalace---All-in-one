# Supply-Chain Policy

This document defines the supply-chain security policy for the **LLM Workflow** platform. It governs how Software Bill of Materials (SBOM) artifacts are produced, how vulnerability thresholds gate promotion, and how security findings block release advancement.

## Related Docs
- [Security Baseline Pipeline](../architecture/SECURITY_BASELINE.md)
- [Release State](../releases/RELEASE_STATE.md)
- [Implementation Progress](../implementation/PROGRESS.md)
- [Remaining Work](../implementation/REMAINING_WORK.md)

## Table of Contents

- [Policy Scope](#policy-scope)
- [SBOM Generation Requirements](#sbom-generation-requirements)
- [Promotion Gates](#promotion-gates)
- [Vulnerability Thresholds](#vulnerability-thresholds)
- [Blocking Conditions](#blocking-conditions)
- [Exceptions and Waivers](#exceptions-and-waivers)
- [Compliance Checklist](#compliance-checklist)

---

## Policy Scope

This policy applies to:

- All release candidates built from the `main` or `release/*` branches
- All Docker images produced by the platform
- All PowerShell modules and packs distributed to downstream consumers
- All configuration artifacts bundled with releases

---

## SBOM Generation Requirements

### When to Generate

An SBOM **must** be generated for every release candidate before it is promoted to the next environment.

| Artifact Type | SBOM Required | Format |
|---------------|---------------|--------|
| PowerShell modules | Yes | CycloneDX JSON |
| Docker images | Yes | CycloneDX JSON |
| JSON/YAML configurations | Yes | CycloneDX JSON |
| Pack bundles | Yes | CycloneDX JSON |

### What to Include

The SBOM must contain, at minimum:

- **Component name and version**
- **Component type** (`library`, `container`, `configuration`, `file`)
- **Package URL (PURL)** when applicable
- **Discovered file path** relative to the project root
- **Tool metadata** (generator name and version)

### Generation Command

```powershell
.\scripts\security\Invoke-SBOMBuild.ps1
Invoke-SBOMBuild -ProjectRoot . -OutputPath ./sbom.json
```

### Retention

SBOMs must be retained for the lifetime of the release plus 12 months. They should be stored alongside the release artifact in the artifact repository.

---

## Promotion Gates

A **promotion gate** is an automated check that must pass before a release candidate can move to the next stage (e.g., `dev` -> `staging` -> `production`).

### Gate Sequence

```text
Build -> Secret Scan -> Vulnerability Scan -> SBOM Build -> Promotion Gate -> Deploy
```

If any gate fails, promotion is blocked and the candidate must be remediated and rescanned.

### Gate Evaluation

The promotion gate is evaluated by `Test-PromotionGate` inside `Invoke-SecurityBaseline.ps1`. It compares scan summaries against configured thresholds.

Default thresholds:

| Severity | Default Maximum Allowed | Blocks Promotion |
|----------|------------------------|------------------|
| Critical | 0 | Yes |
| High | 0 | Yes |
| Medium | No limit | No (tracked) |
| Low | No limit | No (tracked) |

You can customize thresholds per environment:

```powershell
Invoke-SecurityBaseline `
    -ProjectRoot . `
    -MaxAllowedCritical 0 `
    -MaxAllowedHigh 1
```

---

## Vulnerability Thresholds

Thresholds define how many findings of a given severity are acceptable before a release candidate is rejected.

### Standard Thresholds

| Environment | Critical | High | Medium |
|-------------|----------|------|--------|
| **Development** | 0 | 1 | 5 |
| **Staging** | 0 | 0 | 2 |
| **Production** | 0 | 0 | 0 |

### Adjusting Thresholds

Thresholds can be adjusted for emergency patches or experimental branches, but any deviation must be documented in the release notes and approved by a maintainer.

---

## Blocking Conditions

The following conditions **automatically block** promotion, regardless of numeric thresholds:

1. **Critical secret detected** in any scanned file
2. **Hardcoded credential** in a configuration file committed to the repository
3. **Privileged container** (`privileged: true`) in a docker-compose file
4. **Use of `Invoke-Expression`** with user-controlled input in PowerShell scripts
5. **Missing SBOM** for the release candidate
6. **SBOM generation failure** or empty component list

### Promotion Blocked Message

When a gate blocks promotion, the `BlockedBy` array in the consolidated report lists the reasons:

```json
{
  "promotionGate": {
    "Passed": false,
    "BlockedBy": [
      "secrets-critical",
      "vulns-high"
    ]
  }
}
```

---

## Exceptions and Waivers

In rare cases, a finding may be accepted with a waiver.

### Waiver Requirements

- A waiver must be recorded as a JSON file in `.llm-workflow/waivers/`
- It must include:
  - Finding ID or pattern name
  - Justification
  - Expiration date
  - Approver name

### Waiver Example

```json
{
  "waiverId": "waiver-20260413-001",
  "patternName": "Dockerfile_No_Healthcheck",
  "filePath": "Dockerfile.windows",
  "justification": "Windows containers use a different health check mechanism outside the Dockerfile.",
  "approvedBy": "security-lead",
  "expiresAt": "2026-07-13T00:00:00Z"
}
```

> **Note:** The baseline scripts do not currently auto-apply waivers. This is a documented future enhancement.

---

## Compliance Checklist

Before a release candidate is promoted, verify the following:

- [ ] Secret scan completed with no critical findings
- [ ] Vulnerability scan completed with no critical findings
- [ ] High findings are within the threshold for the target environment
- [ ] SBOM was generated successfully and contains at least one component
- [ ] SBOM is stored with the release artifact
- [ ] No blocking conditions are present (or waivers are documented)
- [ ] Consolidated security baseline report is available

---

## See Also

- [SECURITY_BASELINE.md](../../docs/architecture/SECURITY_BASELINE.md)
- `scripts/security/Invoke-SecurityBaseline.ps1`
- `scripts/security/Invoke-SBOMBuild.ps1`
- `tests/SecurityBaseline.Tests.ps1`
