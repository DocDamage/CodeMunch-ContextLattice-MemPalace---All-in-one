# CodeMunch Workflow

This folder keeps a project-level wrapper around your global `codemunch-pro`
install so new repos can adopt the same indexing flow quickly.

## Prereqs

- `codemunch-pro` installed (currently tracked from your
  `feature-rex-foundation` branch).
- PATH wrappers available:
  - `codemunch-up`, `codemunch-down`, `codemunch-status`, `codemunch-logs`
  - `codemunch-index`, `codemunch-index-embed`
  - `codemunch-web-up`, `codemunch-web-down`, `codemunch-web-status`, `codemunch-web-logs`
  - `codemunch-init`, `codemunch-templates`

## Bootstrap this repo

```powershell
.\tools\codemunch\bootstrap-project.ps1
```

This creates:

- `.codemunch/index.defaults.json` with default include/exclude patterns
- `.codemunch/mcp.server.sample.json` with MCP client config snippet

## Index this repo

```powershell
.\tools\codemunch\index-project.ps1 -ProjectRoot . -Embed
```

Optional report output:

```powershell
.\tools\codemunch\index-project.ps1 -ProjectRoot . -Embed -OutFile ".codemunch\last-index.json"
```

## Reuse in other projects

Copy `tools/codemunch/` into another repo and run:

```powershell
.\tools\codemunch\bootstrap-project.ps1
.\tools\codemunch\index-project.ps1 -ProjectRoot . -Embed
```

