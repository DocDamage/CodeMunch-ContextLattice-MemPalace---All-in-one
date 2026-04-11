# LLMWorkflow PowerShell Module

Exports:

- `Install-LLMWorkflow`
- `Uninstall-LLMWorkflow`
- `Update-LLMWorkflow`
- `Get-LLMWorkflowVersion`
- `Test-LLMWorkflowSetup`
- `Invoke-LLMWorkflowUp`
- `llmup` / `llmdown` / `llmcheck` / `llmver` / `llmupdate` (aliases)

`Install-LLMWorkflow` installs the global launcher/assets into `~/.llm-workflow`.

`Invoke-LLMWorkflowUp` runs the all-in-one bootstrap directly using module-bundled
templates and scripts.

`Uninstall-LLMWorkflow` removes the global launcher/profile blocks and optional
module/install files.

`Get-LLMWorkflowVersion` reports manifest/install versions and install paths.

`Update-LLMWorkflow` downloads the latest (or requested) GitHub release artifact,
verifies SHA256, and installs it.

`Test-LLMWorkflowSetup` validates project prerequisites and can optionally run
ContextLattice connectivity checks.
