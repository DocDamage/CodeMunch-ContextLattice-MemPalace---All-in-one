@{
    RootModule = 'LLMWorkflow.psm1'
    NestedModules = @('mcp/ExternalIngestion.ps1')
    ModuleVersion = '0.7.0'
    GUID = '8e7e91da-f11c-4a09-8ba2-4af68cc2d5fc'
    Author = 'DocDamage'
    CompanyName = 'DocDamage'
    Copyright = '(c) DocDamage. All rights reserved.'
    Description = 'All-in-one workflow module for CodeMunch Pro, ContextLattice, and MemPalace. Phase 5 Cross-Pack Arbitration - Multi-pack query routing, authority scoring, dispute sets, and answer labeling.'
    PowerShellVersion = '5.1'
    FunctionsToExport = @('Install-LLMWorkflow', 'Uninstall-LLMWorkflow', 'Update-LLMWorkflow', 'Get-LLMWorkflowVersion', 'Test-LLMWorkflowSetup', 'Invoke-LLMWorkflowUp', 'Test-ProviderKey', 'Get-ProviderProfile', 'Resolve-ProviderProfile', 'Get-ProviderPreferenceOrder', 'Get-LLMWorkflowPlugins', 'Register-LLMWorkflowPlugin', 'Unregister-LLMWorkflowPlugin', 'Invoke-LLMWorkflowPlugins', 'Get-LLMWorkflowPalaces', 'Test-LLMWorkflowPalace', 'Sync-LLMWorkflowPalace', 'Sync-LLMWorkflowAllPalaces', 'Get-LLMWorkflowPluginManifest', 'Save-LLMWorkflowPluginManifest', 'New-LLMWorkflowGamePreset', 'Get-LLMWorkflowGameTemplates', 'Export-LLMWorkflowAssetManifest', 'Show-LLMWorkflowDashboard', 'Invoke-LLMWorkflowHeal', 'Test-LLMWorkflowIssue', 'Repair-LLMWorkflowIssue', 'Get-LLMWorkflowRepairHistory', 'Clear-LLMWorkflowRepairHistory', 'Export-LLMWorkflowRepairHistory', 
        # Phase 1 Priority 1: Journaling + Checkpoints (RunId, Logging, Journal)
        'New-RunId', 'Get-CurrentRunId', 'Set-CurrentRunId', 'Clear-CurrentRunId', 'Test-RunIdFormat', 'Parse-RunId',
        'New-LogEntry', 'Write-StructuredLog', 'Get-LogPath', 'Read-StructuredLog', 'Set-LogDirectory',
        'New-RunManifest', 'Complete-RunManifest', 'New-JournalEntry', 'Get-JournalState', 'Export-JournalReport', 'Add-RunArtifact',
        # Phase 1 Priority 2: File Locking + Atomic Writes
        'Lock-File', 'Unlock-File', 'Test-FileLock', 'Get-LockInfo', 'Remove-StaleLock', 'Test-StaleLock', 'Release-AllLocks', 'Get-AllLocks',
        'Write-AtomicFile', 'Backup-AndWrite', 'Write-JsonAtomic', 'Read-JsonAtomic', 'Sync-File', 'Sync-Directory', 'Backup-File', 'Add-JsonLine',
        'Read-StateFile', 'Write-StateFile', 'Update-StateFile', 'Test-StateVersion', 'Backup-StateFile', 'Migrate-StateFile', 'Get-StateFiles', 'Initialize-StateFile',
        # Phase 1 Priority 3: Effective Configuration
        'Get-DefaultConfig', 'Get-ConfigSchema', 'Test-ConfigValue', 'Test-SecretKey', 'Protect-ConfigSecrets', 'Get-ValidExecutionModes', 'Test-ExecutionMode',
        'Get-ConfigPath', 'Find-ProjectRoot', 'Initialize-ProjectConfigDir', 'Initialize-CentralConfigDir', 'Get-ProjectConfig', 'Get-ProfileConfig', 'Get-EnvironmentConfig', 'Save-ProjectConfig', 'Save-CentralConfig',
        'Get-EffectiveConfig', 'Get-ConfigValue', 'Test-ConfigValidation', 'Export-ConfigExplanation', 'Get-ExecutionMode', 'Set-ExecutionMode', 'Clear-ConfigCache',
        'Get-LLMWorkflowEffectiveConfig', 'Invoke-LLMConfig', 'Register-LLMConfigAlias',
        # Phase 1 Priority 4: Policy + Execution Modes
        'Get-PolicyRules', 'Test-PolicyPermission', 'Assert-PolicyPermission', 'Test-RequiresConfirmation', 'Request-Confirmation', 'Register-PolicyAction', 'Get-PolicyExitCode',
        'Get-ExecutionModePolicy', 'Test-ExecutionModeCapability', 'Switch-ExecutionMode', 'Get-AllowedCommands', 'Get-CommandSafetyLevel', 'Get-ExecutionModeContext', 'Get-CurrentExecutionMode',
        'New-CommandContract', 'Test-CommandContract', 'Invoke-WithContract', 'New-ExecutionPlan', 'Add-PlanStep', 'Show-ExecutionPlan', 'Invoke-ExecutionPlan',
        # Phase 1 Priority 5: Workspace + Visibility Boundaries
        'Get-CurrentWorkspace', 'New-Workspace', 'Switch-Workspace', 'Get-WorkspacePacks', 'Test-WorkspaceContext', 'Get-WorkspaceList', 'Remove-Workspace',
        'Test-VisibilityRule', 'Get-PackVisibility', 'Test-ExportPermission', 'Protect-SecretData', 'Test-SecretInContent', 'Protect-LogEntry', 'Assert-NotExportable',
        'New-PackVisibilityConfig', 'Test-PackAccess', 'Get-RetrievalPriority', 'Test-CanAnswerFromPack', 'Get-PackAnswerLabel', 'Select-PacksForQuery',
        # Phase 2 Priority 1: Pack Manifest + Source Registry
        'New-PackManifest', 'Test-PackManifest', 'Save-PackManifest', 'Get-PackManifest', 'Get-PackManifestList', 'Set-PackLifecycleState', 'Get-PackInstallProfile', 'Export-PackSummary',
        'New-SourceRegistryEntry', 'New-SourceFamilyEntry', 'Test-SourceRegistryEntry', 'Save-SourceRegistry', 'Get-SourceRegistry', 'Set-SourceState', 'Suspend-SourceQuarantine',
        'Get-SourceByPriority', 'Get-SourceByAuthorityRole', 'Get-RetrievalPrioritySources', 'Export-SourceRegistrySummary',
        # Phase 2 Priority 2: Pack Transaction + Lockfile
        'New-PackTransaction', 'Move-PackTransactionStage', 'New-PackLockfile', 'Save-PackLockfile', 'Get-PackLockfile', 'New-PackBuildManifest', 'Publish-PackBuild', 'Undo-PackBuild', 'Get-PackBuildStatus',
        # Phase 3 Priority 1: Health Score + Monitoring
        'Get-PackHealthScore', 'Test-PackHealth', 'Get-WorkspaceHealthSummary', 'Export-HealthReport',
        # Phase 3 Priority 2: Planner + Executor Previews
        'New-ExecutionPlan', 'Add-PlanStep', 'Show-ExecutionPlan', 'Invoke-ExecutionPlan', 'Export-PlanManifest', 'Import-PlanManifest', 'Get-PlanStepTemplate', 'Get-PlanSummary',
        # Phase 3 Priority 3: Git Hooks Integration
        'Install-LLMWorkflowGitHooks', 'Uninstall-LLMWorkflowGitHooks', 'Test-GitHookConfiguration', 'Invoke-GitHookPreCommit', 'Invoke-GitHookPostCommit', 'Invoke-GitHookPrePush', 'New-GitHookScript', 'Write-GitHookLog',
        # Phase 3 Priority 4: Compatibility + Version Management
        'Test-CompatibilityMatrix', 'Get-CompatibilityReport', 'Export-CompatibilityLock', 'Test-VersionCompatibility', 'Get-VersionDrift', 'Assert-CompatibilityBeforeOperation', 'Register-KnownCompatibility', 'Get-KnownCompatibility', 'Test-CrossPackCompatibility', 'Parse-SemanticVersion', 'Test-VersionRange', 'ConvertFrom-JsonToHashtable',
        # Phase 3 Priority 5: Include/Exclude Rules + Filters
        'New-IncludeExcludeFilter', 'Test-PathAgainstFilter', 'Get-IncludedSources', 'Get-IncludedFiles', 'Export-FilterConfig', 'Import-FilterConfig', 'Get-DefaultFilters', 'Add-FilterPattern', 'Remove-FilterPattern',
        # Phase 3 Priority 6: Notification Hooks
        'Register-NotificationHook', 'Unregister-NotificationHook', 'Get-NotificationHooks', 'Send-Notification', 'Invoke-NotificationWebhook', 'Invoke-NotificationCommand', 'Test-NotificationHook', 'New-NotificationPayload',
        # Phase 5 Priority 1: Cross-Pack Arbitration
        'Invoke-CrossPackArbitration', 'Test-PackRelevance', 'Get-ArbitratedPackOrder', 'New-PackArbitrationResult', 'Export-ArbitrationResult',
        'Test-DomainSpecificity', 'Test-ProjectLocalContext', 'Get-PackAuthorityScore', 'Test-CrossPackAnswer', 'Add-CrossPackLabel',
        'Resolve-PackConflicts', 'New-DisputeSet', 'Add-DisputeClaim', 'Export-DisputeSet', 'Set-DisputePreferredSource',
        'Get-AvailablePacks', 'Get-PackRetrievalProfile', 'Test-PackRetrievalProfile', 'Get-ArbitrationStatistics',
        # Phase 6 Priority 1: Human Annotations and Overrides
        'New-HumanAnnotation', 'Get-EntityAnnotations', 'Apply-Annotations', 'New-ProjectOverride', 'Get-EffectiveAnnotations',
        'Export-Annotations', 'Import-Annotations', 'Get-AnnotationRegistry', 'Register-Annotation', 'Update-Annotation',
        'Vote-Annotation', 'Remove-Annotation',
        # Phase 7: External Ingestion Framework (MCP Integration)
        'Register-IngestionSource', 'Unregister-IngestionSource', 'Get-IngestionSources', 'Test-IngestionSource',
        'Invoke-GitHubRepoIngestion', 'Get-GitHubReleaseAssets', 'Invoke-GitHubWorkflowSync', 'Get-GitHubRepoMetadata',
        'Invoke-GitLabRepoIngestion', 'Get-GitLabProjectMetadata',
        'Invoke-DocsSiteIngestion', 'Get-DocsSitemap', 'Invoke-APIReferenceIngestion',
        'Start-IngestionJob', 'Get-IngestionJobStatus', 'Stop-IngestionJob', 'Get-IngestionJobLogs',
        'Get-IngestionRateLimit', 'Invoke-IngestionWithBackoff', 'Set-IngestionThrottle')
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
