# Release Workflow

## Bump module version

```powershell
.\tools\release\bump-module-version.ps1 -Version 0.1.1
```

This updates:

- `module/LLMWorkflow/LLMWorkflow.psd1` (`ModuleVersion`)
- `CHANGELOG.md` release stub (if missing)

## Create git release tag

```powershell
.\tools\release\create-release-tag.ps1 -Push
```

By default, version is read from the module manifest and tag format is `vX.Y.Z`.

When the tag is pushed, `.github/workflows/release.yml` automatically creates a
GitHub Release and uploads:

- `LLMWorkflow-<version>.zip`
- `LLMWorkflow-<version>.zip.sha256`
