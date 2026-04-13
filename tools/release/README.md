# Release Workflow

## Related Docs
- [Repository README](../../README.md)
- [v1.0 Release Criteria](../../docs/releases/V1_RELEASE_CRITERIA.md)
- [Release Certification Checklist](../../docs/releases/RELEASE_CERTIFICATION_CHECKLIST.md)
- [Remaining Work](../../docs/implementation/REMAINING_WORK.md)

## Bump module version

```powershell
.\tools\release\bump-module-version.ps1 -Version 0.1.1
```

This updates:

- `module/LLMWorkflow/LLMWorkflow.psd1` (`ModuleVersion`)
- `compatibility.lock.json` (`tooling.llmworkflow_module_version`, `updated_utc`)
- `CHANGELOG.md` release stub (if missing)

## Create git release tag

```powershell
.\tools\release\create-release-tag.ps1 -Push
```

By default, version is read from the module manifest and tag format is `vX.Y.Z`.
The tag script also validates version parity with `compatibility.lock.json`.

When the tag is pushed, `.github/workflows/release.yml` automatically creates a
GitHub Release and uploads:

- `LLMWorkflow-<version>.zip`
- `LLMWorkflow-<version>.zip.sha256`
- `LLMWorkflow-<version>-signing.txt`

Optional code signing in release workflow:

- Set `CODESIGN_PFX_BASE64` and `CODESIGN_PFX_PASSWORD` secrets.

PowerShell Gallery publish:

- `.github/workflows/publish-gallery.yml` publishes module on Release publish.
- Requires `PSGALLERY_API_KEY` repository secret.
