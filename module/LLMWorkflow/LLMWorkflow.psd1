@{
    RootModule = 'LLMWorkflow.psm1'
    NestedModules = @('mcp/ExternalIngestion.ps1')
    ModuleVersion = '0.9.6'
    GUID = '8e7e91da-f11c-4a09-8ba2-4af68cc2d5fc'
    Author = 'DocDamage'
    CompanyName = 'DocDamage'
    Copyright = '(c) DocDamage. All rights reserved.'
    Description = 'All-in-one workflow module for CodeMunch Pro, ContextLattice, and MemPalace. Phase 5 Cross-Pack Arbitration - Multi-pack query routing, authority scoring, dispute sets, and answer labeling.'
    PowerShellVersion = '5.1'
        FunctionsToExport = @('*')
    AliasesToExport = @('llmup', 'llmdown', 'llmcheck', 'llmver', 'llmupdate', 'llmplugins', 'llmpalaces', 'llmsync', 'llmdashboard', 'llmheal')
    CmdletsToExport = @()
    VariablesToExport = @()
    PrivateData = @{
        PSData = @{
            Tags = @('CodeMunch', 'ContextLattice', 'MemPalace', 'workflow', 'RPGMaker', 'Godot', 'Blender', 'pack-framework')
            ProjectUri = 'https://github.com/DocDamage/CodeMunch-ContextLattice-MemPalace---All-in-one'
            LicenseUri = 'https://github.com/DocDamage/CodeMunch-ContextLattice-MemPalace---All-in-one/blob/main/LICENSE'
            ReleaseNotes = 'v0.7.0: Phase 7 External Ingestion Framework - Scalable ingestion from GitHub, GitLab, documentation sites, and custom APIs. Features async job execution, rate limit handling, incremental ingestion, error recovery, and secret management. 20 new functions for external source integration.'
        }
    }
}
