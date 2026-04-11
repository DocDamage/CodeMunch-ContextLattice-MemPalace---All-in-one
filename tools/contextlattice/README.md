# ContextLattice Workflow

This folder adds a project-level setup and verification flow for using a local
ContextLattice orchestrator with this repository.

Upstream project: `https://github.com/DocDamage/ContextLattice`

## Prereqs

- A running ContextLattice stack (default orchestrator URL: `http://127.0.0.1:8075`)
- `CONTEXTLATTICE_ORCHESTRATOR_API_KEY` from your ContextLattice `.env`
- PowerShell 7+ or Windows PowerShell

## Bootstrap this repo

```powershell
.\tools\contextlattice\bootstrap-project.ps1
```

This creates:

- `.contextlattice/orchestrator.env.sample`
- `.contextlattice/mcp.server.sample.json`

## Verify connectivity

```powershell
.\tools\contextlattice\verify.ps1
```

Optional explicit inputs:

```powershell
.\tools\contextlattice\verify.ps1 `
  -OrchestratorUrl "http://127.0.0.1:8075" `
  -ApiKey "<your-api-key>"
```

Optional smoke memory write+search:

```powershell
.\tools\contextlattice\verify.ps1 -SmokeTest -ProjectName "urpgmaker"
```

Strict smoke (fail if search hit is not visible within retry window):

```powershell
.\tools\contextlattice\verify.ps1 -SmokeTest -RequireSearchHit -ProjectName "urpgmaker"
```
