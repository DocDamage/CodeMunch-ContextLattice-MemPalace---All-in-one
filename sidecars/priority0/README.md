# Priority 0 Sidecars

These are branch-native sidecar patch files for the first Priority 0 remediation pass.

They are intentionally stored under new paths so they can be reviewed, copied, or applied without overwriting tracked source files through the connector.

Included sidecars:
- `GoldenTasks.priority0.patch`
- `DoclingAdapter.priority0.patch`
- `ExternalIngestion.priority0.patch`
- `GeometryNodesParser.priority0.patch`

Scope of this pass:
- remove silent or effectively silent exception handling where it hides operational failures
- replace reusable-module `Write-Host` summary output with pipeline-safe information output
- fix golden-task confidence summary signal loss
- surface ingestion/parser fallback and cleanup failures instead of suppressing them
