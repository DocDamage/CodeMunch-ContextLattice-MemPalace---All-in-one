@{
    RootModule = 'LLMWorkflow.psm1'
    NestedModules = @(
        'ingestion/ExternalIngestion.ps1',
        'ingestion/ExtractionPipeline.ps1'
    )
    ModuleVersion = '0.9.6'
    GUID = '8e7e91da-f11c-4a09-8ba2-4af68cc2d5fc'
    Author = 'DocDamage'
    CompanyName = 'DocDamage'
    Copyright = '(c) DocDamage. All rights reserved.'
    Description = 'All-in-one workflow module for CodeMunch Pro, ContextLattice, and MemPalace. Phase 5 Cross-Pack Arbitration - Multi-pack query routing, authority scoring, dispute sets, and answer labeling.'
    PowerShellVersion = '5.1'
    FunctionsToExport = @(
        'Invoke-LLMWorkflowUp', 'Uninstall-LLMWorkflow', 'Install-LLMWorkflow', 'Update-LLMWorkflow', 
        'Get-LLMWorkflowVersion', 'Test-LLMWorkflowSetup',
        'Invoke-QueryRouting', 'Get-RetrievalProfile', 'Get-RetrievalProfileList', 'Get-QueryIntent', 'Get-RoutingExplanation',
        'New-AnswerPlan', 'Add-PlanEvidence', 'Test-AnswerPlanCompleteness',
        'New-AnswerTrace', 'Add-TraceEvidence', 'Export-AnswerTrace',
        'Get-CachedRetrieval', 'Invoke-CacheInvalidation', 'Invoke-CacheMaintenance', 'Clear-RetrievalCache',
        'Invoke-LLMWorkflowHeal', 'Show-LLMWorkflowDashboard', 'Get-LLMWorkflowPlugins', 'Get-LLMWorkflowPalaces', 'Sync-LLMWorkflowAllPalaces',
        'Get-GoldenTasks', 'Test-GoldenTaskCompleteness', 'Invoke-PackGoldenTasks', 'Test-GoldenTaskResult',
        'Get-TelemetryLog', 'Clear-TelemetryLog',
        'New-IngestionJob', 'Start-IngestionJob', 'Get-IngestionJob', 'Stop-IngestionJob', 'Remove-IngestionJob',
        'Register-IngestionSource', 'Test-IngestionSource', 'Get-IngestionMetrics',
        'Invoke-GitHubRepoIngestion', 'Invoke-DocsSiteIngestion',
        'Invoke-StructuredExtraction', 'Invoke-BatchExtraction', 'Export-ExtractionReport',
        'New-PackSnapshot', 'Export-PackSnapshot', 'Import-PackSnapshot', 'Restore-FromSnapshot',
        'New-FederatedMemoryNode', 'Register-FederatedNode', 'New-SharedMemorySpace',
        'Start-InteractiveConfig', 'ConvertFrom-NaturalLanguageConfig'
    )
    AliasesToExport = @('llmup', 'llmdown', 'llmcheck', 'llmver', 'llmupdate', 'llmplugins', 'llmpalaces', 'llmsync', 'llmdashboard', 'llmheal')
    CmdletsToExport = @()
    VariablesToExport = @()
    PrivateData = @{
        PSData = @{
            Tags = @('CodeMunch', 'ContextLattice', 'MemPalace', 'workflow', 'RPGMaker', 'Godot', 'Blender', 'pack-framework')
            ProjectUri = 'https://github.com/DocDamage/CodeMunch-ContextLattice-MemPalace---All-in-one'
            LicenseUri = 'https://github.com/DocDamage/CodeMunch-ContextLattice-MemPalace---All-in-one/blob/main/LICENSE'
            ReleaseNotes = 'v0.9.6: Technical debt reduction, consolidation of extraction/MCP modules, bounded context and testing portability improvements.'
        }
    }
}

